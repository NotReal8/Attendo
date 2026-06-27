// lib/services/face_worker.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'face_service.dart';
import 'app_log.dart';
import '../models/student.dart';

class FaceWorker {
  FaceWorker._();
  static final FaceWorker instance = FaceWorker._();

  Isolate? _isolate;
  SendPort? _workerSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();

  bool _ready = false;
  bool _starting = false;
  Completer<void>? _readyCompleter;

  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  Future<void> init() async {
    if (_ready) return;
    if (_starting) return _readyCompleter!.future;

    _starting = true;
    _readyCompleter = Completer<void>();

    final token = RootIsolateToken.instance;
    if (token == null) {
      _starting = false;
      throw Exception('FaceWorker.init() must be called from the main isolate');
    }

    final detBytes = (await rootBundle.load('assets/models/det_500m.onnx')).buffer.asUint8List();
    final embBytes = (await rootBundle.load('assets/models/w600k_mbf.onnx')).buffer.asUint8List();

    _mainReceivePort.listen(_onMessage);

    _isolate = await Isolate.spawn(
      _faceWorkerEntry,
      [_mainReceivePort.sendPort, token, detBytes, embBytes],
    );

    await _readyCompleter!.future;
    _starting = false;
  }

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _workerSendPort = message;
      _ready = true;
      if (!(_readyCompleter?.isCompleted ?? true)) _readyCompleter!.complete();
      return;
    }
    if (message is Map) {
      final log = message['log'];
      if (log is String) {
        appLog('[Worker] $log');
        return;
      }
      final id = message['id'] as int?;
      if (id != null) _pending.remove(id)?.complete(message as Map<String, dynamic>);
    }
  }

  Future<FaceDetectionResult> matchFaceWithBox(
    Uint8List jpeg,
    List<Student> students,
    int w,
    int h,
  ) async {
    if (!_ready) await init();

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final studentsPayload = students
        .map((s) => {
              'name': s.name,
              'rollNo': s.rollNo,
              'embedding': s.embedding,
              'sampleCount': s.sampleCount,
              'registeredAt': s.registeredAt,
            })
        .toList();

    _workerSendPort!.send({
      'cmd': 'match',
      'id': id,
      'jpeg': jpeg,
      'w': w,
      'h': h,
      'students': studentsPayload,
    });

    final response = await completer.future;

    final error = response['error'] as String?;
    if (error != null) throw Exception('FaceWorker: $error');

    final faceBoxMap = response['faceBox'] as Map?;
    final landmarksRaw = response['landmarks'] as List?;
    final bakedW = response['bakedW'] as double?;
    final bakedH = response['bakedH'] as double?;

    return FaceDetectionResult(
      matches: ((response['matches'] as List?) ?? [])
          .map((m) => MatchResult(
                name: m['name'] as String,
                confidence: m['confidence'] as double,
                similarity: m['similarity'] as double,
              ))
          .toList(),
      faceBox: faceBoxMap == null
          ? null
          : Rect.fromLTWH(
              faceBoxMap['left'] as double,
              faceBoxMap['top'] as double,
              faceBoxMap['width'] as double,
              faceBoxMap['height'] as double,
            ),
      faceEulerY: response['faceEulerY'] as double?,
      faceEulerX: response['faceEulerX'] as double?,
      faceWidthRatio: response['faceWidthRatio'] as double?,
      bakedImageSize: (bakedW != null && bakedH != null) ? Size(bakedW, bakedH) : null,
      landmarks: landmarksRaw
          ?.map((o) => Offset(o['dx'] as double, o['dy'] as double))
          .toList(),
    );
  }
}

void _faceWorkerEntry(List<dynamic> args) async {
  final SendPort mainSendPort = args[0] as SendPort;
  final RootIsolateToken token = args[1] as RootIsolateToken;
  final Uint8List detBytes = args[2] as Uint8List;
  final Uint8List embBytes = args[3] as Uint8List;

  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  int lastSentLogIndex = 0;
  AppLog.instance.addListener(() {
    final entries = AppLog.instance.entries;
    if (entries.length > lastSentLogIndex) {
      for (int i = lastSentLogIndex; i < entries.length; i++) {
        mainSendPort.send({'log': entries[i]});
      }
      lastSentLogIndex = entries.length;
    }
  });

  final faceService = FaceService();
  await faceService.init(preloadedDetBytes: detBytes, preloadedEmbBytes: embBytes);

  final workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  workerReceivePort.listen((message) async {
    if (message is! Map || message['cmd'] != 'match') return;
    final id = message['id'] as int;
    try {
      final jpeg = message['jpeg'] as Uint8List;
      final w = message['w'] as int;
      final h = message['h'] as int;
      final studentsRaw = message['students'] as List;

      final students = studentsRaw
          .map((m) => Student(
                name: m['name'] as String,
                rollNo: (m['rollNo'] as String?) ?? '',
                embedding: m['embedding'] as Float32List,
                sampleCount: (m['sampleCount'] as int?) ?? 1,
                registeredAt: m['registeredAt'] as String?,
              ))
          .toList();

      final result = await faceService.matchFaceWithBox(jpeg, students, w, h);

      mainSendPort.send({
        'id': id,
        'matches': result.matches
            .map((mr) => {'name': mr.name, 'confidence': mr.confidence, 'similarity': mr.similarity})
            .toList(),
        'faceBox': result.faceBox == null
            ? null
            : {
                'left': result.faceBox!.left,
                'top': result.faceBox!.top,
                'width': result.faceBox!.width,
                'height': result.faceBox!.height,
              },
        'faceEulerY': result.faceEulerY,
        'faceEulerX': result.faceEulerX,
        'faceWidthRatio': result.faceWidthRatio,
        'bakedW': result.bakedImageSize?.width,
        'bakedH': result.bakedImageSize?.height,
        'landmarks': result.landmarks?.map((o) => {'dx': o.dx, 'dy': o.dy}).toList(),
      });
    } catch (e) {
      mainSendPort.send({'id': id, 'error': e.toString()});
    }
  });
}