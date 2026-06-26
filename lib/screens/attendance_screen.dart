// lib/screens/attendance_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_colors.dart';
import '../models/student.dart';
import '../services/attendance_service.dart';
import '../services/database_service.dart';
import '../services/face_service.dart';
import '../services/liveness_service.dart';
import '../services/app_log.dart';


class AttendanceScreen extends StatefulWidget {
  final int? groupId;
  final String groupName;
  const AttendanceScreen({super.key, this.groupId, this.groupName = 'All Students'});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with WidgetsBindingObserver {
  final _faceService  = FaceService();
  final _db           = DatabaseService();
  final _attService   = AttendanceService();
  final _liveness     = LivenessService.instance;

  CameraController? _cam;
  bool _camReady   = false;
  bool _processing = false;
  bool _saving     = false;
  CameraLensDirection _lensDirection = CameraLensDirection.front;

  List<Student>     _students     = [];
  final Set<String> _presentNames = {};
  final Set<String> _lastDetected = {};
  List<MatchResult> _lastResults  = [];

  /// Normalized face box [0..1] — coords relative to the baked image
  Rect? _faceBox;
  bool  _faceMatched = false;

  /// Normalized 5-point landmarks [0..1] — same coordinate space as _faceBox.
  /// Order: left-eye, right-eye, nose tip, left-mouth, right-mouth.
  List<Offset>? _landmarks;

  /// Actual baked image size that SCRFD ran against (post-bakeOrientation)
  Size? _bakedImageSize;

  // Position guidance from latest detection
  double? _faceEulerY;
  double? _faceEulerX;
  double? _faceWidthRatio;

  // Temporal voting — confirmation driven by FaceService.castVote.
  String? _votingName;
  int     _voteCount = 0; // UI-only display counter (mirrors FaceService buffer)

  // Cooldown — prevents re-marking someone just confirmed
  final Map<String, DateTime> _cooldown = {};
  static const int _cooldownSecs = 6;

  // ── Liveness state ────────────────────────────────────────
  bool   _livenessChecking = false;
  bool   _livenessFailed   = false;

  static const int _frameMs = 650;
  DateTime?  _lastFrame;

  /// Latest raw JPEG from the camera stream — consumed by frameSupplier during liveness voting.
  Uint8List? _latestJpeg;
  /// Timestamp of _latestJpeg — frameSupplier uses this to guarantee frame freshness.
  DateTime?  _latestJpegTime;

  late String _sessionDate;
  late String _sessionLabel;

  // ── Watchdog: clears stale UI state when frames stop arriving ──
  // Driven by RAW camera callback arrival (not by inference cadence), so it
  // reflects an actual HAL freeze rather than how busy _processFrame is.
  // A single Timer.periodic just polls "how long since the last raw frame" —
  // this avoids both (a) the original per-frame Timer alloc/cancel churn,
  // and (b) coupling staleness to the (slow, variable-length) recognition
  // pipeline, which caused false-positive recovery loops.
  static const int _staleMs = 2000;
  static const int _staleCheckMs = 500;
  Timer? _staleTimer;
  DateTime? _lastRawFrameAt;
  bool _staleFired = false;

  // ── Recovery: stale watchdog triggers a full camera teardown+reinit ──
  // (mirrors what a notification-shade interruption forces by accident).
  // _recovering spans teardown → reinit → stabilization observation.
  // _recoveryBusy guards only the active teardown/reinit async section so
  // a re-freeze during the stabilization window still triggers a fresh attempt
  // instead of being swallowed.
  bool _recovering   = false;
  bool _recoveryBusy = false;
  int  _recoveryAttempts = 0;
  static const int _maxRecoveryAttempts = 3;
  // Stream must run freeze-free for this long after reinit before it's trusted —
  // prevents re-trusting a stream that dies again after a single frame.
  static const int _stabilizeWindowMs = 3500;
  Timer? _stabilizeWindowTimer;

  // ── Preload / retry state ─────────────────────────────────
  bool  _preloading  = true;   // hides camera until first real frame arrives
  bool  _preloadErr  = false;  // true after _maxRetries exhausted
  int   _retryCount  = 0;
  static const int _maxRetries       = 3;
  static const int _preloadWatchdogMs = 3000; // ms to wait for first frame
  Timer? _preloadWatchdog;

  // Updates the last-seen timestamp and (re)arms the periodic checker.
  // Cheap: no Timer allocation on the hot path — Timer.periodic is created
  // once and left running for the lifetime of the camera session.
  void _resetStaleTimer() {
    _lastRawFrameAt = DateTime.now();
    _staleFired = false;
    _staleTimer ??= Timer.periodic(
      const Duration(milliseconds: _staleCheckMs),
      (_) => _checkStaleWatchdog(),
    );
  }

  void _checkStaleWatchdog() {
    if (_staleFired || _lastRawFrameAt == null) return;
    if (DateTime.now().difference(_lastRawFrameAt!).inMilliseconds < _staleMs) return;
    _staleFired = true;
    if (!mounted) return;
    appLog('[Frame] stale watchdog fired — clearing UI state and triggering recovery');
    _processing = false;
    setState(() {
      _faceBox        = null;
      _lastResults    = [];
      _faceMatched    = false;
      _faceEulerY     = null;
      _faceEulerX     = null;
      _faceWidthRatio = null;
      _landmarks      = null;
      _votingName     = null;
      _voteCount      = 0;
      _livenessFailed = false;
    });
    _handleStaleDetected();
  }

  // Entry point for any stale-frame detection. Safe to call repeatedly —
  // ignores overlap with an in-flight teardown/reinit, but still escalates
  // a re-freeze that happens during the post-reinit stabilization window.
  void _handleStaleDetected() {
    if (_recoveryBusy) {
      appLog('[Recovery] stale fired mid-recovery — ignoring overlap');
      return;
    }
    final freshFreeze = !_recovering;
    if (freshFreeze) _recoveryAttempts = 0;
    _recovering = true;
    if (mounted) setState(() {});
    appLog('[Recovery] triggered (fresh=$freshFreeze) attempt=${_recoveryAttempts + 1}');
    _recoveryAttempt();
  }

  Future<void> _recoveryAttempt() async {
    _recoveryBusy = true;
    _stabilizeWindowTimer?.cancel();
    _recoveryAttempts++;
    appLog('[Recovery] attempt $_recoveryAttempts/$_maxRecoveryAttempts');

    if (_recoveryAttempts > _maxRecoveryAttempts) {
      appLog('[Recovery] exhausted attempts — falling back to preload error screen');
      _recoveryBusy = false;
      _recovering   = false;
      if (mounted) setState(() { _preloadErr = true; _preloading = true; });
      return;
    }

    _staleTimer?.cancel();
    _staleTimer = null;
    _processing = false;

    final cam = _cam;
    _cam = null;
    if (cam != null) {
      try {
        if (cam.value.isStreamingImages) await cam.stopImageStream();
      } catch (e) {
        appLog('[Recovery] stopImageStream error: $e');
      }
      try {
        cam.dispose();
      } catch (e) {
        appLog('[Recovery] dispose error: $e');
      }
    }
    if (!mounted) return;
    setState(() => _camReady = false);

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final ok = await _initCam();
    if (!mounted) return;

    if (!ok) {
      appLog('[Recovery] reinit failed — retrying in 1s');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) _recoveryAttempt();
      return;
    }

    appLog('[Recovery] reinit OK — observing ${_stabilizeWindowMs}ms before trusting stream');
    _recoveryBusy = false;
    _stabilizeWindowTimer = Timer(const Duration(milliseconds: _stabilizeWindowMs), () {
      if (!mounted) return;
      if (!_recovering) return;
      appLog('[Recovery] stabilized ✅ — resuming normal operation');
      _recoveryAttempts = 0;
      _recovering = false;
      setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionDate  = AttendanceService.todayDate;
    _sessionLabel = AttendanceService.sessionLabel;
    appLog('=== Attendance session: $_sessionLabel ===');
    _faceService.init(); // pre-warm SCRFD + ArcFace — non-blocking
    _liveness.init();   // pre-warm MiniFASNet — non-blocking
    _loadStudents();
    _startPreload();
  }

  Future<void> _loadStudents() async {
    _students = widget.groupId != null
        ? await _db.getStudentsInGroup(widget.groupId!)
        : await _db.getAllStudents();
    appLog('[Attendance] Loaded ${_students.length} student(s) for matching '
        '(group=${widget.groupName})');
    if (_students.isEmpty) {
      appLog('[Attendance] ⚠️ No students enrolled in this domain — add students to the group first');
    }
  }

  // ── Preload orchestration ─────────────────────────────────

  void _startPreload() {
    _retryCount = 0;
    _preloadErr = false;
    _preloading = true;
    _recovering = false;
    _recoveryBusy = false;
    _recoveryAttempts = 0;
    _stabilizeWindowTimer?.cancel();
    _attemptCamInit();
  }

  Future<void> _attemptCamInit() async {
    appLog('[Preload] attempt ${_retryCount + 1}/$_maxRetries');
    final success = await _initCam();
    if (!mounted) return;

    if (!success) {
      _retryCount++;
      if (_retryCount >= _maxRetries) {
        appLog('[Preload] all retries exhausted — showing error');
        setState(() { _preloadErr = true; _preloading = true; });
        return;
      }
      appLog('[Preload] retry in 1s…');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) _attemptCamInit();
      return;
    }

    // _initCam succeeded — arm preload watchdog.
    // If no frame arrives within _preloadWatchdogMs, HAL is stalled → retry.
    _preloadWatchdog?.cancel();
    _preloadWatchdog = Timer(
        const Duration(milliseconds: _preloadWatchdogMs), () {
      if (!mounted) return;
      if (!_preloading) return; // first frame already cleared it
      appLog('[Preload] watchdog fired — no frame after ${_preloadWatchdogMs}ms → retry');
      _retryCount++;
      if (_retryCount >= _maxRetries) {
        appLog('[Preload] all retries exhausted — showing error');
        setState(() { _preloadErr = true; });
        return;
      }
      // Tear down stalled camera silently, then retry
      _cam?.stopImageStream().catchError((_) {});
      _cam?.dispose();
      _cam = null;
      if (mounted) setState(() => _camReady = false);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _attemptCamInit();
      });
    });
  }

  /// Returns true on success, false on any failure.
  Future<bool> _initCam() async {
    appLog('[Attendance] _initCam() START');
    _processing = false;

    final ok = await Permission.camera.request();
    if (!ok.isGranted) {
      appLog('ERROR: Camera permission denied');
      return false;
    }

    final cams = await availableCameras();
    if (cams.isEmpty) {
      appLog('ERROR: No cameras found on device');
      return false;
    }

    final cam = cams.firstWhere(
      (c) => c.lensDirection == _lensDirection,
      orElse: () => cams.first,
    );

    appLog('[Attendance] Selected camera: ${cam.lensDirection}');

    _cam = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cam!.initialize();
      appLog('[Attendance] Camera initialized ✅');

      try {
        await _cam!.setFocusMode(FocusMode.auto);
        appLog('[Attendance] FocusMode.auto set ✅');
      } catch (e) {
        appLog('[Attendance] setFocusMode not supported (non-fatal): $e');
      }
      try {
        await _cam!.setExposureMode(ExposureMode.auto);
        appLog('[Attendance] ExposureMode.auto set ✅');
      } catch (e) {
        appLog('[Attendance] setExposureMode not supported (non-fatal): $e');
      }

      // Allow the HAL pipeline to drain before streaming begins.
      await Future.delayed(const Duration(milliseconds: 500));

      await _cam!.startImageStream(_onFrame);
      appLog('[Attendance] Image stream started ✅');
    } catch (e) {
      appLog('[Attendance] Camera init FAILED ❌: $e');
      try { _cam?.dispose(); } catch (_) {}
      _cam = null;
      return false;
    }

    if (!mounted) return false;
    setState(() => _camReady = true);
    appLog('[Attendance] Camera READY ✅');
    _resetStaleTimer();
    return true;
  }

  void _onFrame(CameraImage image) {
    // MUST be synchronous — async callbacks cause Android to stop delivering frames.

    // Unconditional, cheap (timestamp only) — tracks raw camera delivery
    // independent of inference cadence, so the stale watchdog reflects
    // actual HAL freezes rather than how busy _processFrame currently is.
    _resetStaleTimer();

    if (_preloading) {
      _preloadWatchdog?.cancel();
      appLog('[Preload] first frame received — camera live ✅');
      if (mounted) setState(() => _preloading = false);
    }

    if (image.format.group != ImageFormatGroup.jpeg) return;

    final now = DateTime.now();

    // Throttle check BEFORE any allocation — keeps _onFrame cheap on every frame.
    if (_processing) return;
    if (_lastFrame != null &&
        now.difference(_lastFrame!).inMilliseconds < _frameMs) return;

    // Only copy bytes when we're actually going to process this frame.
    // The buffer is reused by the plugin so the copy is still required,
    // but doing it here means 29 out of 30 frames incur zero allocation.
    final jpeg = Uint8List.fromList(image.planes[0].bytes);
    final w    = image.width;
    final h    = image.height;

    _latestJpeg     = jpeg;
    _latestJpegTime = now;

    _processing = true;
    _lastFrame  = now;

    // Dispatch inference asynchronously so _onFrame returns immediately.
    _processFrame(jpeg, w, h);
  }

  Future<void> _processFrame(Uint8List jpeg, int w, int h) async {
    final now = DateTime.now();
    try {
      final detection = await _faceService.matchFaceWithBox(
        jpeg,
        _students,
        w,
        h,
      );

      if (!mounted) return;

      final results    = detection.matches;
      final box        = detection.faceBox;
      final eulerY     = detection.faceEulerY;
      final eulerX     = detection.faceEulerX;
      final widthRatio = detection.faceWidthRatio;
      final bakedSize  = detection.bakedImageSize;

      setState(() {
        _lastResults      = results;
        _faceBox          = box;
        _faceMatched      = false;
        _faceEulerY       = eulerY;
        _faceEulerX       = eulerX;
        _faceWidthRatio   = widthRatio;
        if (bakedSize != null) _bakedImageSize = bakedSize;
        _landmarks        = detection.landmarks;
      });

      if (results.isEmpty || box == null) {
        if (mounted) setState(() {
          _votingName = null;
          _voteCount  = 0;
          _landmarks  = null;
          _livenessFailed = false;
        });
        return;
      }

      final best = results.first;

      if (best.similarity < _faceService.matchThreshold) {
        appLog('[Frame] No match — best: ${best.name} sim=${best.similarityPercent}');
        if (_votingName != best.name) {
          if (mounted) setState(() { _votingName = null; _voteCount = 0; });
        }
        return;
      }

      // Already confirmed this session — skip voting
      if (_presentNames.contains(best.name)) return;

      // Cooldown guard
      final last = _cooldown[best.name];
      if (last != null && now.difference(last).inSeconds < _cooldownSecs) return;

      // ── Temporal vote ─────────────────────────────────────
      final confirmed = _faceService.castVote(best.name, best.similarity);

      // Update UI vote counter — cap at votesRequired so badge never shows 3/2, 4/2
      final buf = _faceService.voteBufferFor(best.name)
          .clamp(0, FaceService.votesRequired);
      if (mounted) {
        setState(() {
          _votingName = best.name;
          _voteCount  = buf;
        });
      }

      if (confirmed) {
        appLog('[Attendance] Vote confirmed for ${best.name} ✅');

        // ── MiniFASNet liveness gate (multi-frame voting) ──
        // Run ONLY here — after vote confirmation, not every frame.
        // frameSupplier captures the latest JPEG from the stream on demand.
        if (mounted) setState(() => _livenessChecking = true);

        final bakedSize2 = _bakedImageSize;
        if (bakedSize2 == null) {
          appLog('[Liveness] ABORT — bakedImageSize not available');
          _faceService.clearVotes(best.name);
          if (mounted) setState(() {
            _votingName = null; _voteCount = 0; _livenessChecking = false;
          });
          return;
        }

        // Capture frames on demand from the live stream.
        // Each call waits for a JPEG that arrived strictly after the call began,
        // guaranteeing frames 1/2/3 are distinct captures from the camera.
        Future<Uint8List?> frameSupplier() async {
          final callTime = DateTime.now();
          for (int i = 0; i < 20; i++) {
            final t = _latestJpegTime;
            final j = _latestJpeg;
            if (t != null && j != null && t.isAfter(callTime)) return j;
            await Future.delayed(const Duration(milliseconds: 50));
          }
          appLog('[Liveness] frameSupplier timeout — no fresh frame available');
          return null;
        }

        final result = await _liveness.checkLivenessWithVoting(
          frameSupplier: frameSupplier,
          faceBox:       box,
          bakedW:        bakedSize2.width,
          bakedH:        bakedSize2.height,
          candidateName: best.name,
        );

        if (result == null) {
          // Model not ready or preprocessing failed — fail safe: reject
          appLog('[Liveness] result null — rejecting as inconclusive');
          _faceService.clearVotes(best.name);
          if (mounted) setState(() {
            _votingName = null; _voteCount = 0;
            _livenessChecking = false; _livenessFailed = true;
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _livenessFailed = false);
          });
          return;
        }

        if (!result.isReal) {
          appLog('[Liveness] ❌ SPOOF for ${best.name} '
              'p_real=${result.realScore.toStringAsFixed(3)} '
              'p_spoof=${result.spoofScore.toStringAsFixed(3)} '
              'inference_ms=${result.inferenceMs}');
          _faceService.clearVotes(best.name);
          if (mounted) setState(() {
            _votingName = null; _voteCount = 0;
            _livenessChecking = false; _livenessFailed = true;
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _livenessFailed = false);
          });
          return;
        }

        appLog('[Liveness] ✅ REAL for ${best.name} '
            'p_real=${result.realScore.toStringAsFixed(3)} '
            'inference_ms=${result.inferenceMs}');
        _faceService.clearVotes(best.name);
        if (mounted) setState(() {
          _votingName = null; _voteCount = 0; _livenessChecking = false;
        });
        _markPresent(best.name, now);
      }
    } catch (e, st) {
      appLog('[Frame] ERROR: $e');
      appLog('[Frame] ${st.toString().split('\n').take(3).join(' | ')}');
    } finally {
      _processing = false;
    }
  }

  void _markPresent(String name, DateTime now) {
    _cooldown[name] = now;
    if (mounted) {
      setState(() {
        _presentNames.add(name);
        _lastDetected..clear()..add(name);
        _faceMatched = true;
      });
      appLog('[Attendance] ✅ $name marked PRESENT');
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _lastDetected.clear());
      });
    }
  }

  Future<void> _flipCamera() async {
    appLog('[Attendance] Flipping camera');
    _preloadWatchdog?.cancel();
    _staleTimer?.cancel();
    _staleTimer = null;
    _stabilizeWindowTimer?.cancel();
    _recovering   = false;
    _recoveryBusy = false;
    _processing = false;
    await _cam?.stopImageStream();
    _cam?.dispose();
    _cam = null;
    setState(() {
      _camReady   = false;
      _preloading = true;
      _preloadErr = false;
      _lensDirection = _lensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;
    });
    _retryCount = 0;
    _attemptCamInit();
  }

  Future<void> _finish() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Finish attendance?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '${_presentNames.length} student(s) present.\n'
          'All others will be marked absent.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;

    // Fully close the camera BEFORE processing. stopImageStream() alone
    // leaves _staleTimer/_preloadWatchdog armed, so the frame gap during
    // saveSession() trips stale-detection -> recovery reinit, causing the
    // "Preparing camera" flicker loop while saving. Tear everything down
    // first so no recovery can fire mid-save.
    _preloadWatchdog?.cancel();
    _staleTimer?.cancel();
    _staleTimer = null;
    _stabilizeWindowTimer?.cancel();
    _recovering   = false;
    _recoveryBusy = false;
    _processing   = false;

    // _cam and _camReady must flip together in one setState — nulling _cam
    // outside setState left a window where a rebuild (e.g. triggered by the
    // confirm dialog's Navigator.pop, or the await below) could run with
    // _camReady still true but _cam already null, hitting `_cam!` in build()
    // and throwing the null-check error briefly before settling.
    final cam = _cam;
    if (mounted) {
      setState(() {
        _cam      = null;
        _camReady = false;
      });
    } else {
      _cam = null;
    }

    if (cam != null) {
      try {
        if (cam.value.isStreamingImages) await cam.stopImageStream();
      } catch (e) {
        appLog('[Finish] stopImageStream error: $e');
      }
      try {
        cam.dispose();
      } catch (e) {
        appLog('[Finish] dispose error: $e');
      }
    }
    if (mounted) setState(() => _saving = true);

    _faceService.clearAllVotes();
    await _attService.saveSession(
      date:         _sessionDate,
      label:        _sessionLabel,
      presentNames: Set.from(_presentNames),
      groupName:    widget.groupName,
      groupId:      widget.groupId,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Row(children: [
          Icon(Icons.check_circle_outline, color: AppColors.present),
          SizedBox(width: 8),
          Text('Saved', style: TextStyle(color: AppColors.textPrimary)),
        ]),
        content: Text(
          '${_presentNames.length} present · $_sessionLabel',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showErr(String msg) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Error',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Text(msg,
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _preloadWatchdog?.cancel();
      _staleTimer?.cancel();
      _staleTimer = null;
      _stabilizeWindowTimer?.cancel();
      _recovering   = false;
      _recoveryBusy = false;
      _processing = false;
      if (_cam != null && _cam!.value.isInitialized) {
        _cam!.stopImageStream().catchError((_) {});
        _cam!.dispose();
        _cam = null;
      }
      if (mounted) setState(() { _camReady = false; _preloading = true; });
    } else if (state == AppLifecycleState.resumed) {
      _retryCount = 0;
      _preloadErr = false;
      _attemptCamInit();
    }
  }

  @override
  void dispose() {
    _preloadWatchdog?.cancel();
    _staleTimer?.cancel();
    _stabilizeWindowTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _faceService.clearAllVotes();
    _cam?.dispose();
    super.dispose();
  }

  // ── Guidance text ─────────────────────────────────────────
  String _guidanceText() {
    if (_faceBox == null) return 'Look straight at the camera';

    final ratio = _faceWidthRatio ?? 0.0;
    if (ratio > 0.65) return 'Move back a little';
    if (ratio < 0.12) return 'Move closer';

    final eulerY = _faceEulerY ?? 0.0;
    if (eulerY > 20) return 'Turn your face left';
    if (eulerY < -20) return 'Turn your face right';

    final eulerX = _faceEulerX ?? 0.0;
    if (eulerX > 20) return 'Tilt your head down slightly';
    if (eulerX < -15) return 'Tilt your head up slightly';

    if (_livenessChecking) return 'Verifying liveness…';
    if (_livenessFailed)   return '❌ Rejected — spoof detected';

    if (_votingName != null && _voteCount > 0) return 'Hold still…';

    return 'Face detected — stay still';
  }

  Color _guidanceColor() {
    if (_faceBox == null)  return Colors.white70;
    if (_livenessFailed)   return AppColors.danger;
    if (_livenessChecking) return Colors.orange;

    final ratio  = _faceWidthRatio ?? 0.0;
    final eulerY = (_faceEulerY ?? 0.0).abs();
    final eulerX = (_faceEulerX ?? 0.0).abs();

    if (ratio > 0.65 || ratio < 0.12) return Colors.orange;
    if (eulerY > 20 || eulerX > 20)   return Colors.orange;
    return AppColors.present;
  }

  Color _boxColor() {
    if (_faceMatched)     return AppColors.present;
    if (_faceBox != null) return Colors.white54;
    return Colors.white54;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Take Attendance',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            Text('${widget.groupName}  ·  $_sessionLabel  ·  $_sessionDate',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_outlined),
            tooltip: 'Flip camera',
            onPressed: _camReady ? _flipCamera : null,
          ),
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: AppColors.textPrimary, strokeWidth: 2)))
              : TextButton(
                  onPressed: _finish,
                  child: const Text('Finish',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700))),
        ],
      ),
      body: _preloading
          ? _PreloadScreen(
              isError:  _preloadErr,
              onRetry:  _preloadErr ? _startPreload : null,
            )
          : _camReady
          ? Stack(
              fit: StackFit.expand,
              children: [
                // ── Camera preview ──────────────────────────
                CameraPreview(_cam!),

                // ── Face bounding box overlay ───────────────
                if (_faceBox != null)
                  _FaceBoxOverlay(
                    box:            _faceBox!,
                    color:          _boxColor(),
                    bakedImageSize: _bakedImageSize,
                    cameraAspect:   _cam!.value.aspectRatio,
                    landmarks:      _landmarks,
                    label: _faceMatched && _lastDetected.isNotEmpty
                        ? _lastDetected.first
                        : (_lastResults.isNotEmpty &&
                                _lastResults.first.similarity >=
                                    _faceService.matchThreshold
                            ? _lastResults.first.name
                            : null),
                  ),

                // ── Guidance banner ─────────────────────────
                Positioned(
                  top: 12, left: 60, right: 60,
                  child: _GuidanceBanner(
                    text:  _guidanceText(),
                    color: _guidanceColor(),
                  ),
                ),

                // ── Recovery banner ─────────────────────────
                if (_recovering)
                  Positioned(
                    top: 56, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '🔄  Reconnecting camera…',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),

                // ── Status dot ──────────────────────────────
                Positioned(
                  top: 12, left: 12,
                  child: _StatusDot(processing: _processing),
                ),

                // ── Confidence panel ────────────────────────
                if (_lastResults.isNotEmpty)
                  Positioned(
                    top: 56, right: 12,
                    child: _ConfidencePanel(
                      results:   _lastResults,
                      threshold: _faceService.matchThreshold,
                    ),
                  ),

                // ── Marked present badge ────────────────────
                if (_lastDetected.isNotEmpty)
                  Positioned(
                    top: 100, left: 0, right: 0,
                    child: _DetectionBadge(name: _lastDetected.first),
                  ),

                // ── Voting / verifying badge ─────────────────
                if (_votingName != null && _voteCount > 0)
                  Positioned(
                    bottom: 196, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Verifying $_votingName… '
                          '$_voteCount/${FaceService.votesRequired}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),

                // ── Liveness checking badge ──────────────────
                if (_livenessChecking)
                  Positioned(
                    bottom: 240, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.90),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '🔍  Checking liveness…',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),

                // ── Liveness failed badge ────────────────────
                if (_livenessFailed)
                  Positioned(
                    bottom: 240, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.90),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '❌  Rejected Face — spoof detected',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),

                // ── No face prompt ──────────────────────────
                if (_faceBox == null)
                  Positioned(
                    bottom: 196, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Text(
                          '👤  Show your face to the camera',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),

                // ── Present panel ───────────────────────────
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: _PresentPanel(names: _presentNames),
                ),
              ],
            )
          : (_recovering
              ? const _PreloadScreen(isError: false, onRetry: null)
              : const SizedBox.shrink()),
    );
  }
}

// ── Preload screen ─────────────────────────────────────────────

class _PreloadScreen extends StatefulWidget {
  final bool isError;
  final VoidCallback? onRetry;
  const _PreloadScreen({required this.isError, this.onRetry});

  @override
  State<_PreloadScreen> createState() => _PreloadScreenState();
}

class _PreloadScreenState extends State<_PreloadScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Opacity(
                opacity: widget.isError ? 1.0 : 0.55 + _pulse.value * 0.45,
                child: child,
              ),
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: widget.isError
                      ? AppColors.danger.withOpacity(0.12)
                      : AppColors.accentDim,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.isError
                      ? Icons.videocam_off_outlined
                      : Icons.face_retouching_natural,
                  size: 36,
                  color: widget.isError ? AppColors.danger : AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.isError ? 'Camera unavailable' : 'Preparing camera…',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isError
                  ? 'Could not start the camera after several attempts.'
                  : 'Getting things ready',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            if (widget.isError && widget.onRetry != null) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: 180,
                child: ElevatedButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Guidance banner ────────────────────────────────────────────

class _GuidanceBanner extends StatelessWidget {
  final String text;
  final Color  color;
  const _GuidanceBanner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.55), width: 1.2),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      );
}

// ── Face bounding box overlay ──────────────────────────────────

class _FaceBoxOverlay extends StatelessWidget {
  final Rect    box;
  final Color   color;
  final String? label;
  final Size?   bakedImageSize;
  final double  cameraAspect;
  final List<Offset>? landmarks;

  const _FaceBoxOverlay({
    required this.box,
    required this.color,
    required this.cameraAspect,
    this.bakedImageSize,
    this.label,
    this.landmarks,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;

        final double imgAspect = bakedImageSize != null
            ? bakedImageSize!.width / bakedImageSize!.height
            : (screenW / screenH);

        double renderW, renderH, offsetX, offsetY;
        if (screenW / screenH > imgAspect) {
          renderW = screenW;
          renderH = screenW / imgAspect;
          offsetX = 0;
          offsetY = (screenH - renderH) / 2;
        } else {
          renderH = screenH;
          renderW = screenH * imgAspect;
          offsetX = (screenW - renderW) / 2;
          offsetY = 0;
        }

        final left   = offsetX + box.left   * renderW;
        final top    = offsetY + box.top    * renderH;
        final width  =           box.width  * renderW;
        final height =           box.height * renderH;

        List<Offset> screenKps = const [];
        if (landmarks != null && landmarks!.length == 5) {
          screenKps = landmarks!.map((p) =>
              Offset(offsetX + p.dy * renderW, offsetY + p.dx * renderH)).toList();
        }

        return Stack(children: [
          Positioned(
            left: left, top: top, width: width, height: height,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2.5),
                borderRadius: BorderRadius.circular(6),
                color: color.withOpacity(0.06),
              ),
            ),
          ),
          if (screenKps.length == 5) ...[
            _LandmarkDot(pos: screenKps[0], dotColor: const Color(0xFF00E5FF)),
            _LandmarkDot(pos: screenKps[1], dotColor: const Color(0xFF00E5FF)),
            _LandmarkDot(pos: screenKps[2], dotColor: const Color(0xFFFFEB3B)),
            _LandmarkDot(pos: screenKps[3], dotColor: const Color(0xFFFF9800)),
            _LandmarkDot(pos: screenKps[4], dotColor: const Color(0xFFFF9800)),
          ],
          if (label != null)
            Positioned(
              left: left,
              top: (top + height + 4).clamp(0, screenH - 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.88),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ]);
      },
    );
  }
}

class _LandmarkDot extends StatelessWidget {
  final Offset pos;
  final Color  dotColor;
  const _LandmarkDot({required this.pos, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: pos.dx - 4,
      top:  pos.dy - 4,
      child: Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dotColor,
          boxShadow: [
            BoxShadow(color: Colors.black54, blurRadius: 2, spreadRadius: 0),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final bool processing;
  const _StatusDot({required this.processing});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: processing ? Colors.orange : AppColors.present,
            ),
          ),
          const SizedBox(width: 6),
          Text(processing ? 'Processing…' : 'Scanning',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      );
}

class _ConfidencePanel extends StatelessWidget {
  final List<MatchResult> results;
  final double threshold;
  const _ConfidencePanel({required this.results, required this.threshold});

  Color _barColor(double sim) {
    if (sim >= 0.7) return AppColors.present;
    if (sim >= 0.4) return const Color(0xFFFFB74D);
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final top = results.take(5).toList();
    return Container(
      width: 170,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Best Matches',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...top.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(r.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(r.similarityPercent,
                          style: TextStyle(
                              color: _barColor(r.similarity),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: r.similarity.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: AppColors.accentDim,
                        valueColor:
                            AlwaysStoppedAnimation(_barColor(r.similarity)),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _DetectionBadge extends StatelessWidget {
  final String name;
  const _DetectionBadge({required this.name});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.present,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                  color: AppColors.present.withOpacity(0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ]),
        ),
      );
}

class _PresentPanel extends StatelessWidget {
  final Set<String> names;
  const _PresentPanel({required this.names});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxHeight: 180),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.82),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: const Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.people_outline,
                  color: AppColors.textSecondary, size: 14),
              const SizedBox(width: 6),
              Text('Present  (${names.length})',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            if (names.isEmpty)
              const Text('Step in front of the camera to be marked present.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12))
            else
              Flexible(
                child: ListView.builder(
                  itemCount: names.length,
                  itemBuilder: (_, i) {
                    final name = names.elementAt(i);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.accentDim,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Text(name,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
}