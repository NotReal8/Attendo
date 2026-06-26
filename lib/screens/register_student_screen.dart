// lib/screens/register_student_screen.dart
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_colors.dart';
import '../services/app_log.dart';
import '../services/enrollment_service.dart';
import '../services/face_service.dart';

class RegisterStudentScreen extends StatefulWidget {
  const RegisterStudentScreen({super.key});

  @override
  State<RegisterStudentScreen> createState() => _RegisterStudentScreenState();
}

class _RegisterStudentScreenState extends State<RegisterStudentScreen> {
  final EnrollmentService     _service     = EnrollmentService();
  final FaceService           _faceService = FaceService();
  final TextEditingController _nameCtrl    = TextEditingController();
  final TextEditingController _rollNoCtrl  = TextEditingController();

  final List<Uint8List> _photos = [];
  bool _saving  = false;
  bool _showCam = false;
  bool _showReady = false;

  CameraController? _cam;
  bool _camReady    = false;
  CameraLensDirection _lensDirection = CameraLensDirection.front;

  bool _opening = false;
  bool _busy    = false;

  DateTime? _lastCapture;
  static const int _captureCooldownMs = 2500;
  static const int _maxPhotos         = 5;

  static const int _frameThrottleMs = 500;
  DateTime? _lastFrameEval;

  Rect? _faceBox;
  bool  _faceDetected = false;

  double? _faceEulerY;
  double? _faceEulerX;
  double? _faceWidthRatio;

  // ── Lifecycle ─────────────────────────────────────────────

  @override
  void dispose() {
    appLog('[Screen] dispose()');
    _nameCtrl.dispose();
    _rollNoCtrl.dispose();
    _cam?.stopImageStream().catchError((_) {});
    _cam?.dispose();
    super.dispose();
  }

  // ── Camera open/close ─────────────────────────────────────

  Future<void> _openCamera() async {
    if (_opening) {
      appLog('[Camera] _openCamera() — already opening, ignoring duplicate call');
      return;
    }
    _opening = true;
    appLog('[Camera] _openCamera()');

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) { _snack('Camera permission denied.'); return; }

      final cams = await availableCameras();
      if (cams.isEmpty) { _snack('No cameras found.'); return; }

      final cam = cams.firstWhere(
        (c) => c.lensDirection == _lensDirection,
        orElse: () => cams.first,
      );
      appLog('[Camera] Using: ${cam.lensDirection.name} sensor=${cam.sensorOrientation}°');

      _cam = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      try {
        await _cam!.initialize();
      } catch (e) {
        appLog('[Camera] initialize() FAIL: $e');
        _snack('Camera init failed: $e');
        try { _cam?.dispose(); } catch (_) {}
        _cam = null;
        return;
      }
      appLog('[Camera] initialized ✅ preview=${_cam!.value.previewSize}');

      if (!mounted) return;

      try {
        await _cam!.startImageStream(_onFrame);
        appLog('[Camera] stream started ✅ format=jpeg');
      } catch (e) {
        appLog('[Camera] startImageStream(jpeg) FAIL: $e');
        _snack('Camera stream failed: $e');
        try { _cam?.dispose(); } catch (_) {}
        _cam = null;
        return;
      }

      setState(() { _camReady = true; _showCam = true; _busy = false; });
    } catch (e) {
      appLog('[Camera] FAIL: $e');
      _snack('Camera error: $e');
    } finally {
      _opening = false;
      appLog('[Camera] _opening reset to false');
    }
  }

  Future<void> _closeCamera() async {
    appLog('[Camera] _closeCamera()');
    final cam = _cam;
    _cam = null;
    if (cam != null) {
      try {
        if (cam.value.isStreamingImages) await cam.stopImageStream();
      } catch (e) {
        appLog('[Camera] stopImageStream on close: $e');
      }
      try {
        cam.dispose();
      } catch (e) {
        appLog('[Camera] dispose error: $e');
      }
    }
    if (mounted) {
      setState(() {
        _camReady       = false;
        _showCam        = false;
        _faceBox        = null;
        _faceDetected   = false;
        _faceEulerY     = null;
        _faceEulerX     = null;
        _faceWidthRatio = null;
        _busy           = false;
      });
    }
    appLog('[Camera] closed ✅');
  }

  Future<void> _flipCamera() async {
    appLog('[Camera] flip');
    _lensDirection = _lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    await _closeCamera();
    await _openCamera();
  }

  // ── Frame handler ─────────────────────────────────────────

  void _onFrame(CameraImage image) {
    if (_busy) return;
    if (_photos.length >= _maxPhotos) return;

    final now = DateTime.now();

    if (_lastFrameEval != null &&
        now.difference(_lastFrameEval!).inMilliseconds < _frameThrottleMs) return;
    _lastFrameEval = now;

    if (image.format.group == ImageFormatGroup.jpeg) {
      _busy = true;
      _processFrame(image.planes[0].bytes, image.width, image.height, now);
    } else {
      appLog('[Frame] Unsupported format: ${image.format.group} — skipping');
    }
  }

  Future<void> _processFrame(
      Uint8List jpeg, int w, int h, DateTime frameTime) async {
    try {
      final faces = await _faceService.detectFaces(jpeg);

      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          _faceDetected   = false;
          _faceBox        = null;
          _faceEulerY     = null;
          _faceEulerX     = null;
          _faceWidthRatio = null;
        });
        return;
      }

      final face = faces.reduce((a, b) =>
          (a.width * a.height) > (b.width * b.height) ? a : b);

      final normBox = Rect.fromLTWH(
        face.left   / w,
        face.top    / h,
        face.width  / w,
        face.height / h,
      );

      if (!mounted) return;
      setState(() {
        _faceDetected   = true;
        _faceBox        = normBox;
        _faceEulerY     = null;
        _faceEulerX     = null;
        _faceWidthRatio = face.width / w;
      });

      final sinceLastCapture = _lastCapture == null
          ? _captureCooldownMs + 1
          : frameTime.difference(_lastCapture!).inMilliseconds;

      if (sinceLastCapture >= _captureCooldownMs && _photos.length < _maxPhotos) {
        _lastCapture = frameTime;
        Uint8List displayJpeg = jpeg;
        try {
          final rawImg = img.decodeImage(jpeg);
          if (rawImg != null) {
            final baked = img.bakeOrientation(rawImg);
            displayJpeg = Uint8List.fromList(img.encodeJpg(baked, quality: 90));
          }
        } catch (e) {
          appLog('[Capture] bakeOrientation failed (non-fatal): $e');
        }
        setState(() => _photos.add(displayJpeg));
        appLog('[Capture] grabbed frame — photos=${_photos.length}/$_maxPhotos');

        if (_photos.length >= _maxPhotos) {
          appLog('[Capture] max reached — closing camera');
          await _closeCamera();
        }
      }
    } catch (e) {
      appLog('[Frame] ERROR: $e');
    } finally {
      if (_busy) _busy = false;
    }
  }

  // ── Save ──────────────────────────────────────────────────

  Future<void> _save() async {
    final name   = _nameCtrl.text.trim();
    final rollNo = _rollNoCtrl.text.trim();
    if (name.isEmpty)   { _snack('Enter a student name.');   return; }
    if (rollNo.isEmpty) { _snack('Enter a roll number.');    return; }
    if (_photos.isEmpty){ _snack('Add at least one photo.'); return; }

    setState(() => _saving = true);
    try {
      await _service.enrollStudentFromCaptures(name, _photos, rollNo: rollNo);
      appLog('[Save] enrolled "$name" (roll=$rollNo) ✅');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      appLog('[Save] FAIL: $e');
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Guidance helpers ──────────────────────────────────────

  String _guidanceText() {
    if (!_faceDetected || _faceBox == null) return 'Show your face to the camera';
    final ratio = _faceWidthRatio ?? 0.0;
    if (ratio > 0.65) return 'Move back a little';
    if (ratio < 0.12) return 'Move closer';
    if (_busy) return '📸 Capturing…';
    return '✅ Hold still — auto-capturing';
  }

  Color _guidanceColor() {
    if (!_faceDetected) return Colors.white70;
    final ratio = _faceWidthRatio ?? 0.0;
    if (ratio > 0.65 || ratio < 0.12) return Colors.orange;
    return AppColors.present;
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) =>
      _showCam ? _cameraOverlay() : (_showReady ? _readyScreen() : _form());

  // ── Ready screen ──────────────────────────────────────────

  Widget _readyScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Get Ready')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.face_retouching_natural, size: 64, color: AppColors.accent),
            const SizedBox(height: 24),
            const Text(
              'Position your face in the frame.\nThe camera will capture photos automatically — no need to tap anything.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _showReady = false);
                _openCamera();
              },
              icon: const Icon(Icons.check),
              label: const Text("I'm Ready"),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _showReady = false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Camera overlay ────────────────────────────────────────

  Widget _cameraOverlay() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_camReady && _cam != null)
            _AdaptiveCameraPreview(controller: _cam!)
          else
            const Center(child: CircularProgressIndicator(color: AppColors.textSecondary)),

          if (_faceBox != null)
            LayoutBuilder(builder: (_, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final boxColor = _busy ? AppColors.present : Colors.orangeAccent;
              return Positioned(
                left:   _faceBox!.left   * w,
                top:    _faceBox!.top    * h,
                width:  _faceBox!.width  * w,
                height: _faceBox!.height * h,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: boxColor, width: 2.5),
                    borderRadius: BorderRadius.circular(6),
                    color: boxColor.withOpacity(0.06),
                  ),
                ),
              );
            }),

          Positioned(
            top: 12, left: 70, right: 70,
            child: SafeArea(
              child: _EnrollGuidanceBanner(
                text:  _guidanceText(),
                color: _guidanceColor(),
              ),
            ),
          ),

          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _camBtn('Cancel', onTap: () async {
                      appLog('[Camera] Cancel tapped');
                      await _closeCamera();
                    }),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(_maxPhotos, (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _photos.length ? AppColors.present : Colors.white24,
                        ),
                      )),
                    ),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      GestureDetector(
                        onTap: _camReady ? _flipCamera : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: const Icon(Icons.flip_camera_ios_outlined, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _camBtn(
                        'Done',
                        color: _photos.isEmpty ? Colors.black38 : AppColors.present.withOpacity(0.9),
                        onTap: _photos.isEmpty ? null : () async {
                          appLog('[Camera] Done tapped');
                          await _closeCamera();
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 52, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  _photos.isEmpty
                      ? 'Camera auto-captures when your face is detected'
                      : '${_photos.length}/$_maxPhotos photos captured — ${_maxPhotos - _photos.length} more to go',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Form ──────────────────────────────────────────────────

  Widget _form() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Register Student')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Student Name',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'e.g. John Smith',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Roll Number',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _rollNoCtrl,
              keyboardType: TextInputType.text,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'e.g. 101',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Photos  (${_photos.length}/$_maxPhotos)',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                if (_photos.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _photos.clear()),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('Clear all', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_photos.isNotEmpty) ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _photos.asMap().entries.map((e) {
                  return Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(e.value, width: 90, height: 90, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 3, right: 3,
                      child: GestureDetector(
                        onTap: () => setState(() => _photos.removeAt(e.key)),
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ]);
                }).toList(),
              ),
              const SizedBox(height: 14),
            ],
            OutlinedButton.icon(
              onPressed: _photos.length >= _maxPhotos
                  ? null
                  : () => setState(() => _showReady = true),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_photos.isEmpty ? 'Open Camera' : 'Add More Photos'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Camera auto-captures when it detects your face. Move for different angles.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving…' : 'Save Student'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _camBtn(String label, {VoidCallback? onTap, Color color = Colors.black54}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _EnrollGuidanceBanner extends StatelessWidget {
  final String text;
  final Color  color;
  const _EnrollGuidanceBanner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.55), width: 1.2),
        ),
        child: Text(text, textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _AdaptiveCameraPreview extends StatelessWidget {
  final CameraController controller;
  const _AdaptiveCameraPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) return const ColoredBox(color: Colors.black);
    return LayoutBuilder(builder: (_, constraints) {
      final screenW = constraints.maxWidth;
      final screenH = constraints.maxHeight;
      final rawRatio = controller.value.aspectRatio;
      final camRatio = screenH > screenW ? (1.0 / rawRatio) : rawRatio;

      double previewW, previewH;
      if (screenW / screenH > camRatio) {
        previewW = screenW;
        previewH = screenW / camRatio;
      } else {
        previewH = screenH;
        previewW = screenH * camRatio;
      }

      return ClipRect(
        child: OverflowBox(
          maxWidth: previewW,
          maxHeight: previewH,
          child: SizedBox(width: previewW, height: previewH, child: CameraPreview(controller)),
        ),
      );
    });
  }
}