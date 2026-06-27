// lib/services/liveness_service.dart
//
// Presentation Attack Detection — MiniFASNetV2SE (facenox quantized variant)
//
// Model: best_model_quantized.onnx  (~600 KB INT8 quantized)
// Input:  [1, 3, 128, 128]  float32  RGB  pixel/255 → [0.0, 1.0]
// Output: [1, 2]  softmax   [p_spoof, p_real]  ← index 0 = spoof, index 1 = real
//
// Trigger: called ONLY after vote confirmation (not every frame).
// Crop:    face bbox expanded by _bboxExpansion to include forehead/chin context.
//          MiniFASNet was trained on padded crops — tight bbox performs worse.
//
// Voting logic (checkLivenessWithVoting):
//   Frame 1 + 2: both real → REAL. Both spoof → SPOOF.
//   Split (1 real, 1 spoof) → Frame 3 as tiebreaker.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'app_log.dart';

class LivenessResult {
  final bool isReal;
  final double realScore;   // p_real ∈ [0..1]
  final double spoofScore;  // p_spoof ∈ [0..1]
  final int inferenceMs;

  const LivenessResult({
    required this.isReal,
    required this.realScore,
    required this.spoofScore,
    required this.inferenceMs,
  });
}

class LivenessService {
  LivenessService._();
  static final LivenessService instance = LivenessService._();

  // ── Config ────────────────────────────────────────────────

  /// Real face threshold against p_real (index 1 of model output).
  /// With the correct index, 0.50 is the natural decision boundary.
  static const double _realThreshold = 0.50;

  /// Bbox expansion multiplier around face centre.
  /// MiniFASNet training used padded crops; too-tight crops hurt accuracy.
  static const double _bboxExpansion = 1.5;

  static const int _inputSize = 128;

  // ── State ─────────────────────────────────────────────────

  OrtSession? _session;
  String?     _inputName;
  bool        _initializing = false;
  bool        _ready        = false;

  // ── Init ──────────────────────────────────────────────────

  Future<void> init() async {
    if (_ready) return;
    if (_initializing) {
      while (_initializing) await Future.delayed(const Duration(milliseconds: 30));
      return;
    }
    _initializing = true;
    appLog('[Liveness] init(): loading MiniFASNetV2SE...');
    try {
      OrtEnv.instance.init();

      final opts = OrtSessionOptions()
        ..setInterOpNumThreads(1)
        ..setIntraOpNumThreads(1);

      final bytes = (await rootBundle.load('assets/models/best_model_quantized.onnx'))
          .buffer.asUint8List();
      _session   = OrtSession.fromBuffer(bytes, opts);
      _inputName = _session!.inputNames.first;

      appLog('[Liveness] MiniFASNetV2SE loaded ✅ '
          'input=$_inputName outputs=${_session!.outputNames}');
      _ready = true;
    } catch (e, st) {
      appLog('[Liveness] init FAIL: $e');
      appLog('[Liveness] stack: ${st.toString().split('\n').take(3).join(' | ')}');
    } finally {
      _initializing = false;
    }
  }

  bool get ready => _ready;

  // ── Multi-frame voting API ────────────────────────────────
  //
  // Accepts a frameSupplier callback that returns the next JPEG frame on demand.
  // This keeps frame capture in the caller (attendance_screen) and model logic here.
  //
  // Logic:
  //   Run frame 1 and frame 2.
  //   Both real  → return real.
  //   Both spoof → return spoof.
  //   Split      → run frame 3 as tiebreaker; return its result.
  //
  // frameSupplier must return null if no frame is available (treated as spoof for safety).

  Future<LivenessResult?> checkLivenessWithVoting({
    required Future<Uint8List?> Function() frameSupplier,
    required Rect    faceBox,
    required double  bakedW,
    required double  bakedH,
    required String  candidateName,
  }) async {
    appLog('[Liveness] voting check START candidate=$candidateName');

    // Frame 1
    final jpeg1 = await frameSupplier();
    if (jpeg1 == null) {
      appLog('[Liveness] voting ABORT — frame 1 null');
      return null;
    }
    final r1 = await checkLiveness(
        jpegBytes: jpeg1, faceBox: faceBox,
        bakedW: bakedW, bakedH: bakedH,
        candidateName: '$candidateName[1/3]');
    if (r1 == null) {
      appLog('[Liveness] voting ABORT — frame 1 inference null');
      return null;
    }

    // Frame 2 — small delay so frames aren't identical
    await Future.delayed(const Duration(milliseconds: 200));
    final jpeg2 = await frameSupplier();
    if (jpeg2 == null) {
      appLog('[Liveness] voting ABORT — frame 2 null');
      return null;
    }
    final r2 = await checkLiveness(
        jpegBytes: jpeg2, faceBox: faceBox,
        bakedW: bakedW, bakedH: bakedH,
        candidateName: '$candidateName[2/3]');
    if (r2 == null) {
      appLog('[Liveness] voting ABORT — frame 2 inference null');
      return null;
    }

    appLog('[Liveness] voting frames 1+2: '
        'f1=${r1.isReal ? "REAL" : "SPOOF"}(${r1.realScore.toStringAsFixed(3)}) '
        'f2=${r2.isReal ? "REAL" : "SPOOF"}(${r2.realScore.toStringAsFixed(3)})');

    // Both agree — no tiebreaker needed
    if (r1.isReal && r2.isReal) {
      appLog('[Liveness] voting RESULT: REAL (2/2 agree) candidate=$candidateName');
      return LivenessResult(
        isReal:      true,
        realScore:   (r1.realScore + r2.realScore) / 2,
        spoofScore:  (r1.spoofScore + r2.spoofScore) / 2,
        inferenceMs: r1.inferenceMs + r2.inferenceMs,
      );
    }
    if (!r1.isReal && !r2.isReal) {
      appLog('[Liveness] voting RESULT: SPOOF (2/2 agree) candidate=$candidateName');
      return LivenessResult(
        isReal:      false,
        realScore:   (r1.realScore + r2.realScore) / 2,
        spoofScore:  (r1.spoofScore + r2.spoofScore) / 2,
        inferenceMs: r1.inferenceMs + r2.inferenceMs,
      );
    }

    // Split — run tiebreaker frame 3
    appLog('[Liveness] voting SPLIT — running tiebreaker frame 3 candidate=$candidateName');
    await Future.delayed(const Duration(milliseconds: 200));
    final jpeg3 = await frameSupplier();
    if (jpeg3 == null) {
      appLog('[Liveness] voting tiebreaker ABORT — frame 3 null → defaulting SPOOF');
      return LivenessResult(
        isReal:      false,
        realScore:   (r1.realScore + r2.realScore) / 2,
        spoofScore:  (r1.spoofScore + r2.spoofScore) / 2,
        inferenceMs: r1.inferenceMs + r2.inferenceMs,
      );
    }
    final r3 = await checkLiveness(
        jpegBytes: jpeg3, faceBox: faceBox,
        bakedW: bakedW, bakedH: bakedH,
        candidateName: '$candidateName[3/3]');
    if (r3 == null) {
      appLog('[Liveness] voting tiebreaker inference null → defaulting SPOOF');
      return null;
    }

    appLog('[Liveness] voting RESULT: tiebreaker=${r3.isReal ? "REAL" : "SPOOF"} '
        '(${r3.realScore.toStringAsFixed(3)}) candidate=$candidateName');
    return LivenessResult(
      isReal:      r3.isReal,
      realScore:   (r1.realScore + r2.realScore + r3.realScore) / 3,
      spoofScore:  (r1.spoofScore + r2.spoofScore + r3.spoofScore) / 3,
      inferenceMs: r1.inferenceMs + r2.inferenceMs + r3.inferenceMs,
    );
  }

  // ── Single-frame primitive ────────────────────────────────
  //
  // Used internally by checkLivenessWithVoting.
  // Can still be called directly if needed.

  Future<LivenessResult?> checkLiveness({
    required Uint8List jpegBytes,
    required Rect      faceBox,
    required double    bakedW,
    required double    bakedH,
    required String    candidateName,
  }) async {
    if (!_ready) {
      appLog('[Liveness] checkLiveness called before init — attempting lazy init');
      await init();
      if (!_ready) {
        appLog('[Liveness] checkLiveness ABORT — model still not ready');
        return null;
      }
    }

    final session   = _session;
    final inputName = _inputName;
    if (session == null || inputName == null) {
      appLog('[Liveness] checkLiveness ABORT — session null');
      return null;
    }

    final t0 = DateTime.now();

    try {
      final rawDecoded = img.decodeImage(jpegBytes);
      if (rawDecoded == null) {
        appLog('[Liveness] FAIL — decodeImage null');
        return null;
      }
      final decoded = img.bakeOrientation(rawDecoded);

      // Use the actual decoded dimensions — not the caller's snapshot.
      // If bakeOrientation rotates (e.g. portrait sensor JPEG), the snapshot
      // bakedW/bakedH would be transposed relative to this frame's real size,
      // causing the crop to land in the wrong region.
      final actualW = decoded.width.toDouble();
      final actualH = decoded.height.toDouble();
      if (actualW != bakedW || actualH != bakedH) {
        appLog('[Liveness] WARNING — decoded size ${actualW.toInt()}×${actualH.toInt()} '
            'differs from snapshot ${bakedW.toInt()}×${bakedH.toInt()} — using actual');
      }

      final facePixelLeft   = faceBox.left   * actualW;
      final facePixelTop    = faceBox.top    * actualH;
      final facePixelWidth  = faceBox.width  * actualW;
      final facePixelHeight = faceBox.height * actualH;

      final cx = facePixelLeft + facePixelWidth  / 2;
      final cy = facePixelTop  + facePixelHeight / 2;
      final hw = (facePixelWidth  / 2) * _bboxExpansion;
      final hh = (facePixelHeight / 2) * _bboxExpansion;

      final x = (cx - hw).clamp(0, decoded.width.toDouble()  - 1).toInt();
      final y = (cy - hh).clamp(0, decoded.height.toDouble() - 1).toInt();
      final w = (hw * 2).clamp(1, decoded.width.toDouble()  - x).toInt();
      final h = (hh * 2).clamp(1, decoded.height.toDouble() - y).toInt();

      appLog('[Liveness] crop: x=$x y=$y w=$w h=$h '
          '(face px: ${facePixelWidth.toInt()}×${facePixelHeight.toInt()}) '
          'expansion=×$_bboxExpansion candidate=$candidateName');

      final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      final resized = img.copyResize(cropped,
          width: _inputSize, height: _inputSize,
          interpolation: img.Interpolation.linear);

      final input = Float32List(_inputSize * _inputSize * 3);
      for (int py = 0; py < _inputSize; py++) {
        for (int px = 0; px < _inputSize; px++) {
          final p      = resized.getPixel(px, py);
          final offset = py * _inputSize + px;
          input[0 * _inputSize * _inputSize + offset] = p.r.toDouble() / 255.0;
          input[1 * _inputSize * _inputSize + offset] = p.g.toDouble() / 255.0;
          input[2 * _inputSize * _inputSize + offset] = p.b.toDouble() / 255.0;
        }
      }

      appLog('[Liveness] MiniFASNet input: '
          'shape=[1,3,$_inputSize,$_inputSize] '
          'channel_order=RGB norm=[0,1] '
          'candidate=$candidateName');

      OrtValueTensor? tensor;
      List<OrtValue?>? outputs;
      try {
        tensor  = OrtValueTensor.createTensorWithDataList(
            input, [1, 3, _inputSize, _inputSize]);
        outputs = await session.runAsync(OrtRunOptions(), {inputName: tensor});
      } catch (e) {
        appLog('[Liveness] inference error: $e');
        return null;
      } finally {
        tensor?.release();
      }

      if (outputs == null || outputs.isEmpty) {
        appLog('[Liveness] FAIL — null/empty outputs');
        outputs?.forEach((o) => o?.release());
        return null;
      }

      final rawOut = outputs[0]?.value;
      outputs.forEach((o) => o?.release());

      // BEFORE:
      final List<double> logits = [];
      _flatten(rawOut, logits);

      // AFTER (insert here):
      appLog('[Liveness] RAW logits: [0]=${logits[0].toStringAsFixed(4)} [1]=${logits[1].toStringAsFixed(4)}');

      // Model output per header doc: index 0 = p_spoof, index 1 = p_real.
      // Previous code had these swapped, causing real faces to read the
      // spoof slot — flagging everything as spoof.
      final softmax = _softmax2(logits[0], logits[1]);
      final pSpoof = softmax[0];
      final pReal  = softmax[1];

      final inferenceMs = DateTime.now().difference(t0).inMilliseconds;
      final isReal = pReal >= _realThreshold;

      appLog('[Liveness] MiniFASNet result: '
          'candidate=$candidateName '
          'p_real=${pReal.toStringAsFixed(4)} '
          'p_spoof=${pSpoof.toStringAsFixed(4)} '
          'real/fake=${isReal ? "REAL ✅" : "SPOOF ❌"} '
          'threshold=$_realThreshold '
          'inference_ms=$inferenceMs');

      return LivenessResult(
        isReal:       isReal,
        realScore:    pReal,
        spoofScore:   pSpoof,
        inferenceMs:  inferenceMs,
      );
    } catch (e, st) {
      appLog('[Liveness] checkLiveness ERROR: $e');
      appLog('[Liveness] stack: ${st.toString().split('\n').take(3).join(' | ')}');
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  void _flatten(dynamic value, List<double> out) {
    if (value == null) return;
    if (value is List) {
      for (final v in value) _flatten(v, out);
    } else if (value is double) {
      out.add(value);
    } else if (value is num) {
      out.add(value.toDouble());
    } else if (value is Float32List) {
      for (final v in value) out.add(v);
    }
  }

  List<double> _softmax2(double a, double b) {
    final maxV = max(a, b);
    final ea = exp(a - maxV);
    final eb = exp(b - maxV);
    final sum = ea + eb;
    return [ea / sum, eb / sum];
  }

  void dispose() {
    _session?.release();
    _session = null;
    _ready   = false;
    appLog('[Liveness] disposed');
  }
}