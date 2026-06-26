// lib/services/app_log.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:async';

class AppLog extends ChangeNotifier {
  AppLog._();
  static final AppLog instance = AppLog._();

  final List<String> _entries = [];
  File? _logFile;
  bool  _fileReady = false;

  List<String> get entries => List.unmodifiable(_entries);
  String get allText => _entries.join('\n');
  String get logFilePath =>
      _fileReady ? (_logFile?.path ?? 'unavailable') : 'unavailable';

  Future<void> initFile() async {
    try {
      final dir = Directory('/storage/emulated/0/FaceAttendance');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _logFile = File('${dir.path}/app_log.txt');
      await _logFile!.writeAsString(
          '\n=== Session: ${DateTime.now()} ===\n',
          mode: FileMode.append);
      _fileReady = true;
    } catch (e) {
      _fileReady = false;
    }
  }

  Timer? _notifyTimer;

void add(String message) {
  final t = DateTime.now();
  final ts = '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
  final entry = '[$ts] $message';
  _entries.add(entry);
  _notifyTimer?.cancel();
  _notifyTimer = Timer(const Duration(milliseconds: 300), notifyListeners);
  if (_fileReady && _logFile != null) {
    _logFile!
        .writeAsString('$entry\n', mode: FileMode.append)
        .catchError((_) => _logFile!);
  }
  // ignore: avoid_print
  print(entry);
}

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

void appLog(String msg) => AppLog.instance.add(msg);