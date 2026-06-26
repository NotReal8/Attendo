// lib/services/stress_test_service.dart
//
// Stages:
//   1 — Insert 1000 random students with synthetic normalized embeddings.
//       Wipes any previously inserted stress students first (re-run safe).
//   2 — Camera abuse: navigate AttendanceScreen, pop, repeat 50 cycles. (UNCHANGED)
//   3 — DB corruption: malformed writes, duplicates, broken JSON, mid-sync deletes,
//       transaction rollback, unicode overflow, null-byte embedding.
//   4 — Memory pressure: load all 1000 embeddings, run 1000×1000 cosine similarity
//       matrix THREE times to force GC churn + thermal throttle.
//   5 — Attendance storm: 200 sessions × 1000 students = 200k records sequentially.
//   6 — Concurrent DB writes: 25 async chains × 100 records simultaneously.
//   7 — Read storm: 500 concurrent getAllStudents() + attendanceSummary() calls
//       to stress SQLite connection serialization under load.
//   8 — Embedding GC churn: tight float32 average+normalize loops on 1000 embeddings,
//       repeated 500 times to expose memory leaks in Float32List allocation.
//   9 — Export/Import round-trip: export full roster + all attendance to JSON,
//       re-import on a wiped DB, verify student and record counts match.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_record.dart';
import '../models/student.dart';
import '../screens/attendance_screen.dart';
import 'app_log.dart';
import 'beacon_service.dart';
import 'database_service.dart';
import 'transfer_service.dart';

// ── Public API ────────────────────────────────────────────────────────────────

class StressTestService {
  StressTestService._();
  static final StressTestService instance = StressTestService._();

  final DatabaseService _db = DatabaseService();

  final _statusCtrl = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusCtrl.stream;

  bool _aborted = false;

  // ── Name pool (realistic college names — expanded for 1000) ───────────────

  static const List<String> _firstNames = [
    'Aarav','Aditya','Akash','Amit','Ananya','Anjali','Ankit','Ansh',
    'Arjun','Arpit','Avni','Ayush','Bhavna','Deepak','Deepika','Dhruv',
    'Divya','Gaurav','Himanshu','Isha','Ishaan','Jatin','Karan','Kavya',
    'Komal','Kritika','Kunal','Lakshmi','Manish','Meera','Mohit','Muskan',
    'Naman','Nandini','Neha','Nikhil','Nisha','Pallavi','Pankaj','Pooja',
    'Prachi','Pranav','Priya','Rahul','Raj','Rajan','Rakesh','Riya',
    'Rohit','Sachin','Sahil','Sandeep','Sanjay','Sara','Shivam','Shreya',
    'Shruti','Siddharth','Simran','Sneha','Sonam','Sunil','Suresh','Tanvi',
    'Tarun','Tushar','Uday','Vaibhav','Vedant','Vijay','Vikas','Vishal',
    'Yash','Yogesh','Zara','Kabir','Mihir','Natasha','Piyush','Ridhi',
    'Ritika','Rohan','Ruhi','Sameer','Shubham','Swati','Tanya','Urvashi',
    'Vibha','Vikram','Vinay','Vineet','Vivek','Yamini','Yuvraj','Zoya',
    'Aakash','Abhinav','Achint','Aditi','Agam','Aishwarya','Ajay','Ajit',
    'Alok','Alpa','Amisha','Amrita','Anand','Aniket','Anil','Anish',
    'Ankita','Anmol','Anu','Anuj','Apoorv','Archit','Arman','Arnav',
    'Arpita','Arshdeep','Arun','Arvind','Ashish','Ashna','Ashok','Astha',
    'Atul','Avantika','Ayaan','Bhuvan','Chandan','Chirag','Darshan','Dev',
    'Devika','Disha','Divyam','Ekta','Farhan','Farida','Garima','Gaurangi',
    'Girish','Gita','Gopal','Gulab','Harish','Harshit','Hemant','Hina',
    'Hitesh','Husna','Ishan','Jagdish','Jai','Jaideep','Jaimin','Jalpa',
    'Janak','Jaya','Jayesh','Jigar','Jignesh','Jinesh','Juhi','Jyoti',
    'Kanika','Kartik','Kashish','Kedar','Keshav','Khyati','Kirti','Komal',
  ];

  static const List<String> _lastNames = [
    'Agarwal','Ahuja','Batra','Bhatt','Chauhan','Chopra','Desai','Dubey',
    'Garg','Goyal','Gupta','Iyer','Jain','Joshi','Kapoor','Kaur',
    'Khan','Khanna','Kumar','Malhotra','Mehta','Mishra','Nair','Pandey',
    'Patel','Pillai','Rao','Rastogi','Reddy','Saxena','Shah','Sharma',
    'Shukla','Singh','Sinha','Srivastava','Tiwari','Trivedi','Upadhyay','Verma',
    'Yadav','Arora','Bajaj','Bansal','Bose','Chatterjee','Das','Dey',
    'Ghosh','Mukherjee','Chandra','Dixit','Dwivedi','Fernandes','Hegde','Kulkarni',
    'Lal','Menon','Modi','Nanda','Ojha','Patil','Puri','Rajan',
    'Rathore','Sehgal','Sethi','Soni','Srinivasan','Subramaniam','Thakur','Vaid',
    'Walia','Yadav','Zutshi','Bahl','Bakshi','Balakrishnan','Bhattacharya','Bhave',
  ];

  // ── Embedding helpers ─────────────────────────────────────────────────────

  static Float32List _generateEmbedding(String name, {int size = 192}) {
    int seed = 0;
    for (int i = 0; i < name.length; i++) {
      seed = seed * 31 + name.codeUnitAt(i);
      seed &= 0x7FFFFFFF;
    }
    final rng = Random(seed);
    final raw = Float32List(size);
    double norm = 0;
    for (int i = 0; i < size; i++) {
      raw[i] = (rng.nextDouble() * 2 - 1).toDouble();
      norm += raw[i] * raw[i];
    }
    norm = sqrt(norm);
    for (int i = 0; i < size; i++) raw[i] /= norm;
    return raw;
  }

  static double _cosine(Float32List a, Float32List b) {
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (sqrt(na) * sqrt(nb));
  }

  static Float32List _normalize(Float32List e) {
    double norm = 0;
    for (final v in e) norm += v * v;
    norm = sqrt(norm);
    if (norm == 0) return e;
    final out = Float32List(e.length);
    for (int i = 0; i < e.length; i++) out[i] = e[i] / norm;
    return out;
  }

  static Float32List _average(List<Float32List> list) {
    final len = list[0].length;
    final avg = Float32List(len);
    for (final e in list) { for (int i = 0; i < len; i++) avg[i] += e[i]; }
    for (int i = 0; i < len; i++) avg[i] /= list.length;
    return avg;
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  void _emit(String msg) {
    appLog('[StressTest] $msg');
    if (!_statusCtrl.isClosed) _statusCtrl.add(msg);
  }

  void _abort(String reason) {
    _aborted = true;
    _emit('🛑 ABORTED: $reason');
  }

  Future<void> _killApp(String reason, String accountName) async {
    _emit('💀 FATAL: $reason — triggering kill screen');
    BeaconService.appAlive.value = false;
    BeaconService.killMessage = 'Stress test fatal failure: $reason';
    try {
      final prefs = await SharedPreferences.getInstance();
      final acct  = prefs.getString('account_name') ?? accountName;
      await FirebaseFirestore.instance
          .collection('config')
          .doc('kill_switch')
          .set({
        'active':           false,
        'message':          'Stress test fatal failure on "$acct": $reason',
        'killed_accounts':  [acct],
        'stress_failure':   true,
        'failed_at':        FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      appLog('[StressTest] Firebase write failed: $e');
    }
  }

  // ── Generate N unique student names ───────────────────────────────────────

  static List<String> _generateNames(int count) {
    final names = <String>{};
    final rng   = Random(42);
    int attempt = 0;
    while (names.length < count) {
      final first = _firstNames[rng.nextInt(_firstNames.length)];
      final last  = _lastNames[rng.nextInt(_lastNames.length)];
      String name = '$first $last';
      if (names.contains(name)) name = '$name ${attempt % 1000 + 1}';
      names.add(name);
      attempt++;
    }
    return names.toList();
  }

  static double _quickNorm(Float32List e) {
    double n = 0;
    for (final v in e) n += v * v;
    return sqrt(n);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 1 — Insert 1000 students (re-run safe: wipes previous stress data)
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage1() async {
    _aborted = false;
    const targetCount = 1000;
    _emit('━━━ STAGE 1: Generating $targetCount student profiles (re-run safe) ━━━');

    try {
      // ── Re-run safety: delete any previously inserted stress students ────
      _emit('Checking for leftover stress students from previous run...');
      final prevNames = _generateNames(targetCount);
      final db = await DatabaseService().database;
      int wiped = 0;
      // Batch-delete in chunks of 50 to avoid huge IN clauses
      for (int i = 0; i < prevNames.length; i += 50) {
        final chunk = prevNames.sublist(i, min(i + 50, prevNames.length));
        final placeholders = List.filled(chunk.length, '?').join(',');
        final deleted = await db.rawDelete(
          'DELETE FROM students WHERE name IN ($placeholders)',
          chunk,
        );
        wiped += deleted;
      }
      if (wiped > 0) {
        _emit('🧹 Wiped $wiped leftover stress student(s) from previous run');
      } else {
        _emit('✅ No leftover stress students found');
      }

      final names = _generateNames(targetCount);
      _emit('Generated ${names.length} unique names');

      int inserted = 0;
      int failed   = 0;

      const batchSize = 20;
      for (int i = 0; i < names.length; i += batchSize) {
        if (_aborted) break;

        final batch = names.sublist(i, min(i + batchSize, names.length));
        for (final name in batch) {
          try {
            final emb = _generateEmbedding(name);
            final student = Student(
              name:         name,
              embedding:    emb,
              sampleCount:  3,
              registeredAt: DateTime.now().toIso8601String(),
            );
            await _db.upsertStudent(student);
            inserted++;
            if (inserted % 100 == 0 || inserted <= 5) {
              _emit('✅ [$inserted/$targetCount] Inserted: $name '
                  '(norm=${_quickNorm(emb).toStringAsFixed(4)})');
            }
          } catch (e) {
            failed++;
            _emit('❌ FAIL insert "$name": $e');
          }
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }

      final count = await _db.studentCount();
      _emit('━━━ Stage 1 complete: inserted=$inserted failed=$failed '
          'total_in_db=$count ━━━');

      if (inserted == 0) {
        _emit('❌ Stage 1 produced zero inserts — check DB');
        return false;
      }
      return true;
    } catch (e, st) {
      appLog('[StressTest] Stage1 UNCAUGHT: $e\n$st');
      _emit('💥 Stage 1 crashed: $e');
      _abort('Stage 1 uncaught exception: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 2 — Camera abuse (50 cycles — UNCHANGED)
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage2(BuildContext context) async {
    _emit('━━━ STAGE 2: Camera abuse — 50 open/close cycles ━━━');

    const cycles    = 50;
    const holdMs    = 3000;
    const watchdogS = 15;

    int completed = 0;
    int crashed   = 0;

    for (int i = 0; i < cycles; i++) {
      if (_aborted) break;
      if (!context.mounted) {
        _emit('⚠️ Context unmounted at cycle $i — stopping Stage 2');
        break;
      }

      _emit('📷 Cycle ${i + 1}/$cycles — pushing AttendanceScreen');

      bool timedOut = false;
      final completer = Completer<void>();

      final watchdog = Timer(Duration(seconds: watchdogS), () {
        timedOut = true;
        if (context.mounted) {
          try { Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/stress'); }
          catch (_) {}
        }
        if (!completer.isCompleted) completer.complete();
      });

      try {
        if (!context.mounted) break;

        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        ).then((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await Future.delayed(Duration(milliseconds: holdMs));
        watchdog.cancel();

        if (!timedOut && context.mounted) {
          try { Navigator.of(context).pop(); } catch (_) {}
        }

        await completer.future.timeout(const Duration(seconds: 3),
            onTimeout: () {});

        completed++;
        _emit('✅ Cycle ${i + 1} done');
      } catch (e, st) {
        crashed++;
        watchdog.cancel();
        appLog('[StressTest] Stage2 cycle ${i + 1} CRASH: $e\n'
            '${st.toString().split('\n').take(3).join(' | ')}');
        _emit('❌ Cycle ${i + 1} crash: $e');
        if (context.mounted) {
          try { Navigator.of(context).popUntil((r) => r.isFirst); }
          catch (_) {}
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await Future.delayed(const Duration(milliseconds: 200));
    }

    _emit('━━━ Stage 2 complete: cycles_done=$completed crashed=$crashed ━━━');
    return crashed < cycles;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 3 — DB corruption (expanded)
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage3() async {
    _emit('━━━ STAGE 3: Database corruption testing (expanded) ━━━');

    int passed = 0;
    int failed = 0;

    // 3a: Empty fields
    _emit('3a: Malformed attendance row (empty fields)...');
    try {
      final db = await DatabaseService().database;
      await db.rawInsert(
        'INSERT INTO attendance (session_date, session_label, student_name, status) VALUES (?, ?, ?, ?)',
        ['', 'Session · 99:99', '', ''],
      );
      await db.rawDelete("DELETE FROM attendance WHERE session_date = '' AND student_name = ''");
      _emit('3a: DB accepted + cleaned up ✅'); passed++;
    } catch (e) {
      _emit('3a: DB rejected malformed row ✅'); passed++;
    }

    // 3b: Duplicate attendance key
    _emit('3b: Duplicate attendance key...');
    try {
      final dupeRec = AttendanceRecord(
        sessionDate: '2099-01-01', sessionLabel: 'Session · 00:00',
        studentName: 'Stress Test Dupe', status: 'present',
      );
      await _db.insertRecords([dupeRec]);
      await _db.insertRecords([dupeRec]);
      final db = await DatabaseService().database;
      await db.rawDelete("DELETE FROM attendance WHERE student_name = 'Stress Test Dupe'");
      _emit('3b: Duplicate handled + cleaned ✅'); passed++;
    } catch (e) {
      _emit('3b: threw: $e'); failed++;
    }

    // 3c: Broken JSON import
    _emit('3c: Broken JSON to TransferService...');
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/broken_roster.json');
      await file.writeAsString('{ "version": 1, "students": [INVALID JSON HERE}}}');
      bool parseOk = false;
      try { json.decode(await file.readAsString()); parseOk = true; } catch (_) {}
      if (!parseOk) { _emit('3c: Broken JSON rejected ✅'); passed++; }
      else { _emit('3c: Broken JSON unexpectedly parsed ⚠️'); failed++; }
      await file.delete();
    } catch (e) {
      _emit('3c: Exception: $e'); failed++;
    }

    // 3d: Mid-sync delete
    _emit('3d: Mid-sync delete...');
    try {
      final db = await DatabaseService().database;
      final recs = List.generate(40, (i) => AttendanceRecord(
        sessionDate: '2099-02-02', sessionLabel: 'Session · 01:00',
        studentName: 'MidSyncStudent $i',
        status: i.isEven ? 'present' : 'absent',
      ));
      await _db.insertRecords(recs);
      final deleteF = db.rawDelete(
          "DELETE FROM attendance WHERE session_date = '2099-02-02' AND student_name LIKE 'MidSyncStudent %'");
      final insertF = _db.insertRecords([AttendanceRecord(
        sessionDate: '2099-02-02', sessionLabel: 'Session · 01:00',
        studentName: 'MidSyncLateStudent', status: 'present',
      )]);
      await Future.wait([deleteF, insertF]);
      await db.rawDelete("DELETE FROM attendance WHERE session_date = '2099-02-02'");
      _emit('3d: Concurrent delete+insert without crash ✅'); passed++;
    } catch (e) {
      _emit('3d: threw: $e'); failed++;
    }

    // 3e: Zero-length embedding
    _emit('3e: Zero-length embedding...');
    try {
      final s = Student(name: '__ZeroEmbedTest__', embedding: Float32List(0), sampleCount: 1);
      await _db.upsertStudent(s);
      await _db.deleteStudent('__ZeroEmbedTest__');
      _emit('3e: Zero-length handled + cleaned ✅'); passed++;
    } catch (e) {
      _emit('3e: Rejected (acceptable) ✅'); passed++;
    }

    // 3f: 2000-char name
    _emit('3f: 2000-char student name...');
    try {
      final longName = 'X' * 2000;
      await _db.upsertStudent(Student(
        name: longName, embedding: _generateEmbedding(longName), sampleCount: 1));
      await _db.deleteStudent(longName);
      _emit('3f: Long name handled + cleaned ✅'); passed++;
    } catch (e) {
      _emit('3f: Long name rejected ✅'); passed++;
    }

    // 3g: Transaction rollback simulation
    _emit('3g: Transaction rollback — insert then force error...');
    try {
      final db = await DatabaseService().database;
      bool rolledBack = false;
      try {
        await db.transaction((txn) async {
          await txn.rawInsert(
            'INSERT INTO attendance (session_date, session_label, student_name, status) VALUES (?, ?, ?, ?)',
            ['2099-03-03', 'Session · 02:00', 'RollbackStudent', 'present'],
          );
          // Force constraint violation to trigger rollback
          throw Exception('Forced rollback for test');
        });
      } catch (_) {
        rolledBack = true;
      }
      final rows = await db.rawQuery(
          "SELECT COUNT(*) as c FROM attendance WHERE student_name = 'RollbackStudent'");
      final count = (rows.first['c'] as int?) ?? 0;
      if (rolledBack && count == 0) {
        _emit('3g: Transaction rolled back correctly ✅'); passed++;
      } else {
        _emit('3g: ⚠️ Rollback may not have worked — count=$count'); failed++;
      }
    } catch (e) {
      _emit('3g: threw: $e'); failed++;
    }

    // 3h: Unicode + emoji student name
    _emit('3h: Unicode/emoji name...');
    try {
      const unicodeName = '学生 こんにちは 🎓 الطالب';
      await _db.upsertStudent(Student(
        name: unicodeName, embedding: _generateEmbedding(unicodeName), sampleCount: 1));
      await _db.deleteStudent(unicodeName);
      _emit('3h: Unicode name round-tripped ✅'); passed++;
    } catch (e) {
      _emit('3h: Unicode rejected: $e'); failed++;
    }

    // 3i: Null-byte in embedding (raw binary corruption)
    _emit('3i: Null-byte corrupted embedding...');
    try {
      final corruptEmb = Float32List(192); // all zeros — valid float but degenerate
      await _db.upsertStudent(Student(
        name: '__NullEmbedTest__', embedding: corruptEmb, sampleCount: 1));
      final students = await _db.getAllStudents();
      final found = students.any((s) => s.name == '__NullEmbedTest__');
      await _db.deleteStudent('__NullEmbedTest__');
      _emit('3i: All-zero embedding stored=${found ? "yes" : "no"}, cleaned ✅'); passed++;
    } catch (e) {
      _emit('3i: threw: $e'); failed++;
    }

    _emit('━━━ Stage 3 complete: passed=$passed failed=$failed ━━━');
    if (failed >= 5) {
      await _killApp('Stage 3: $failed/9 corruption tests failed', 'stress_tester');
      return false;
    }
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 4 — Memory pressure: 1000×1000 cosine, 3 full passes
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage4() async {
    _emit('━━━ STAGE 4: Memory pressure — 1000×1000 cosine × 3 passes ━━━');

    try {
      _emit('Loading all students from DB...');
      final students = await _db.getAllStudents();
      _emit('Loaded ${students.length} students into RAM');

      if (students.isEmpty) { _emit('⚠️ No students — Stage 4 skipped'); return true; }

      final embeddings = students.map((s) => s.embedding).toList();
      _emit('Starting ${embeddings.length}×${embeddings.length} cosine matrix × 3 passes...');

      for (int pass = 1; pass <= 3; pass++) {
        final sw = Stopwatch()..start();
        double maxSim = -2, minSim = 2;
        int pairs = 0;

        for (int i = 0; i < embeddings.length; i++) {
          for (int j = i + 1; j < embeddings.length; j++) {
            final sim = _cosine(embeddings[i], embeddings[j]);
            if (sim > maxSim) maxSim = sim;
            if (sim < minSim) minSim = sim;
            pairs++;
          }
          if (i % 50 == 0) {
            _emit('  Pass $pass — row $i/${embeddings.length} '
                'pairs=$pairs elapsed=${sw.elapsedMilliseconds}ms');
            await Future.delayed(Duration.zero);
          }
        }
        sw.stop();
        _emit('  ✅ Pass $pass done: pairs=$pairs '
            'max=${maxSim.toStringAsFixed(4)} min=${minSim.toStringAsFixed(4)} '
            'time=${sw.elapsedMilliseconds}ms');

        // Explicitly trigger GC between passes by re-loading
        if (pass < 3) {
          _emit('  Reloading embeddings from DB (GC pressure)...');
          await _db.getAllStudents();
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      _emit('━━━ Stage 4 complete ━━━');
      return true;
    } catch (e, st) {
      appLog('[StressTest] Stage4 CRASH: $e\n${st.toString().split('\n').take(3).join(' | ')}');
      _emit('💥 Stage 4 crashed: $e');
      _abort('Stage 4: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 5 — Attendance storm: 200 sessions × 1000 students (thermal test)
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage5() async {
    _emit('━━━ STAGE 5: Attendance storm — 200 sessions × 1000 students ━━━');

    try {
      final students = await _db.getAllStudents();
      if (students.isEmpty) { _emit('⚠️ No students — Stage 5 skipped'); return true; }

      final rng      = Random();
      final allNames = students.map((s) => s.name).toList();
      int totalRecs  = 0;
      final times    = <int>[];

      for (int session = 0; session < 200; session++) {
        if (_aborted) break;

        final month = (session ~/ 28 + 1).clamp(1, 12);
        final day   = (session % 28 + 1).clamp(1, 28);
        final date  = '2099-${month.toString().padLeft(2, '0')}'
                      '-${day.toString().padLeft(2, '0')}';
        final label = 'Session · ${(session % 24).toString().padLeft(2, '0')}:00';

        final presentCount = (allNames.length * (0.3 + rng.nextDouble() * 0.5)).toInt();
        allNames.shuffle(rng);
        final presentSet = allNames.take(presentCount).toSet();

        final records = allNames.map((name) => AttendanceRecord(
          sessionDate: date, sessionLabel: label, studentName: name,
          status: presentSet.contains(name) ? 'present' : 'absent',
        )).toList();

        final sw = Stopwatch()..start();
        await _db.insertRecords(records);
        sw.stop();
        times.add(sw.elapsedMilliseconds);
        totalRecs += records.length;

        if (session % 20 == 0 || session == 199) {
          final avgMs = times.isEmpty ? 0 : times.reduce((a, b) => a + b) ~/ times.length;
          _emit('Session ${session + 1}/200 — ${records.length} records '
              '(${presentCount} present) in ${sw.elapsedMilliseconds}ms '
              '(avg=${avgMs}ms)');
        }

        await Future.delayed(const Duration(milliseconds: 5));
      }

      final dbCount = await _totalAttendanceCount();
      _emit('━━━ Stage 5 complete: total_inserted≈$totalRecs rows_in_db=$dbCount ━━━');

      _emit('Cleaning up Stage 5 sessions...');
      final db = await DatabaseService().database;
      for (int month = 1; month <= 12; month++) {
        await db.rawDelete(
            "DELETE FROM attendance WHERE session_date LIKE '2099-${month.toString().padLeft(2, '0')}%'");
      }
      _emit('Stage 5 cleanup done ✅');
      return true;
    } catch (e, st) {
      appLog('[StressTest] Stage5 CRASH: $e\n${st.toString().split('\n').take(3).join(' | ')}');
      _emit('💥 Stage 5 crashed: $e');
      _abort('Stage 5: $e');
      return false;
    }
  }

  Future<int> _totalAttendanceCount() async {
    final db   = await DatabaseService().database;
    final rows = await db.rawQuery('SELECT COUNT(*) as c FROM attendance');
    return (rows.first['c'] as int?) ?? 0;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 6 — Concurrent DB writes: 25 chains × 100 records
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage6() async {
    _emit('━━━ STAGE 6: Concurrent DB writes — 25 chains × 100 records ━━━');

    try {
      final sw    = Stopwatch()..start();
      final date  = '2099-12-31';
      int chainsDone = 0;
      int chainsErr  = 0;

      final futures = List.generate(25, (chain) async {
        try {
          final records = List.generate(100, (i) => AttendanceRecord(
            sessionDate: date, sessionLabel: 'ConcurrentChain-$chain',
            studentName: 'ConStudent_C${chain}_R$i',
            status: i.isEven ? 'present' : 'absent',
          ));
          await _db.insertRecords(records);
          _emit('Chain $chain done (100 records)');
          chainsDone++;
        } catch (e) {
          _emit('❌ Chain $chain fail: $e');
          chainsErr++;
        }
      });

      await Future.wait(futures);
      sw.stop();

      final db = await DatabaseService().database;
      final rows = await db.rawQuery(
          "SELECT COUNT(*) as c FROM attendance WHERE session_date = '$date'");
      final actualCount = (rows.first['c'] as int?) ?? 0;
      final expectedMax = chainsDone * 100;

      _emit('chains_ok=$chainsDone chains_fail=$chainsErr '
          'rows=$actualCount expected=$expectedMax '
          'elapsed=${sw.elapsedMilliseconds}ms');

      if (actualCount < expectedMax * 0.5 && chainsDone > 0) {
        _emit('⚠️ Significant row loss: $actualCount/$expectedMax');
      } else {
        _emit('✅ Row count acceptable');
      }

      await db.rawDelete("DELETE FROM attendance WHERE session_date = '$date'");
      _emit('━━━ Stage 6 complete ━━━');
      return chainsErr < 25;
    } catch (e, st) {
      appLog('[StressTest] Stage6 CRASH: $e\n${st.toString().split('\n').take(3).join(' | ')}');
      _emit('💥 Stage 6 crashed: $e');
      _abort('Stage 6: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 7 — Read storm: 500 concurrent DB reads
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage7() async {
    _emit('━━━ STAGE 7: Read storm — 500 concurrent DB reads ━━━');

    try {
      final sw = Stopwatch()..start();
      int  ok  = 0;
      int  err = 0;

      // Fire 500 concurrent reads in 5 waves of 100
      for (int wave = 0; wave < 5; wave++) {
        _emit('Wave ${wave + 1}/5 — launching 100 concurrent reads...');
        final futures = List.generate(100, (i) async {
          try {
            if (i % 2 == 0) {
              await _db.getAllStudents();
            } else {
              await _db.attendanceSummary();
            }
            ok++;
          } catch (e) {
            err++;
            appLog('[StressTest] Stage7 read error: $e');
          }
        });
        await Future.wait(futures);
        _emit('  Wave ${wave + 1} done — ok=$ok err=$err elapsed=${sw.elapsedMilliseconds}ms');
        await Future.delayed(const Duration(milliseconds: 50));
      }

      sw.stop();
      _emit('━━━ Stage 7 complete: ok=$ok err=$err total_elapsed=${sw.elapsedMilliseconds}ms ━━━');
      if (err > 50) {
        _emit('⚠️ High error rate: $err/500');
        return false;
      }
      return true;
    } catch (e, st) {
      appLog('[StressTest] Stage7 CRASH: $e\n${st.toString().split('\n').take(3).join(' | ')}');
      _emit('💥 Stage 7 crashed: $e');
      _abort('Stage 7: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 8 — Embedding GC churn: 500 tight float32 average/normalize loops
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage8() async {
    _emit('━━━ STAGE 8: Embedding GC churn — 500 iterations of avg+normalize ━━━');

    try {
      _emit('Loading embeddings from DB...');
      final students = await _db.getAllStudents();
      if (students.isEmpty) { _emit('⚠️ No students — Stage 8 skipped'); return true; }

      final embeddings = students.map((s) => s.embedding).toList();
      _emit('Loaded ${embeddings.length} embeddings — starting GC churn loop...');

      final sw = Stopwatch()..start();
      Float32List? lastResult;

      for (int iter = 0; iter < 500; iter++) {
        // Compute average of a sliding window of 10 embeddings
        final start   = iter % (embeddings.length - 10);
        final window  = embeddings.sublist(start, start + 10);
        final avg     = _average(window);
        final normed  = _normalize(avg);
        // Also compute cosine of result against itself (sanity: must be ~1.0)
        final selfSim = _cosine(normed, normed);

        if (selfSim < 0.99) {
          _emit('⚠️ iter $iter: self-cosine=$selfSim (expected ~1.0) — possible float corruption');
        }

        lastResult = normed;

        if (iter % 100 == 0) {
          _emit('  iter $iter/500 — last_norm=${_quickNorm(normed).toStringAsFixed(6)} '
              'self_sim=${selfSim.toStringAsFixed(6)} '
              'elapsed=${sw.elapsedMilliseconds}ms');
          await Future.delayed(Duration.zero); // yield to event loop
        }
      }

      sw.stop();
      _emit('━━━ Stage 8 complete — '
          'final_vec_size=${lastResult?.length ?? 0} '
          'elapsed=${sw.elapsedMilliseconds}ms ━━━');
      return true;
    } catch (e, st) {
      appLog('[StressTest] Stage8 CRASH: $e\n${st.toString().split('\n').take(3).join(' | ')}');
      _emit('💥 Stage 8 crashed: $e');
      _abort('Stage 8: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STAGE 9 — Export/Import round-trip integrity test
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> runStage9() async {
    _emit('━━━ STAGE 9: Export/Import round-trip integrity ━━━');

    try {
      // ── Snapshot before export ────────────────────────────────────────
      final beforeStudents = await _db.getAllStudents();
      final beforeAttCount = await _totalAttendanceCount();
      _emit('Before export: ${beforeStudents.length} students, $beforeAttCount attendance rows');

      if (beforeStudents.isEmpty) {
        _emit('⚠️ No students to export — Stage 9 skipped');
        return true;
      }

      // ── Export ────────────────────────────────────────────────────────
      _emit('Exporting roster...');
      final sw   = Stopwatch()..start();
      File exportFile;
      try {
        exportFile = await TransferService().exportRoster();
      } catch (e) {
        _emit('❌ Export failed: $e');
        return false;
      }
      sw.stop();

      final fileSizeKb = (await exportFile.length()) ~/ 1024;
      _emit('Export done in ${sw.elapsedMilliseconds}ms — file=${fileSizeKb}KB');

      // ── Wipe DB ───────────────────────────────────────────────────────
      _emit('Wiping entire DB for clean import test...');
      await _db.resetAllData();
      final afterWipe = await _db.studentCount();
      _emit('DB wiped — student count=$afterWipe');

      // ── Import ────────────────────────────────────────────────────────
      _emit('Importing from exported file...');
      sw.reset(); sw.start();
      final result = await TransferService().importRoster(exportFile.path);
      sw.stop();
      _emit('Import done in ${sw.elapsedMilliseconds}ms');
      _emit('  students imported=${result.studentsImported} '
          'skipped=${result.studentsSkipped} failed=${result.studentsFailed}');
      _emit('  attendance imported=${result.attendanceImported} '
          'skipped=${result.attendanceSkipped} failed=${result.attendanceFailed}');

      // ── Verify counts ─────────────────────────────────────────────────
      final afterStudents = await _db.studentCount();
      final afterAttCount = await _totalAttendanceCount();
      _emit('After import: $afterStudents students, $afterAttCount attendance rows');

      bool pass = true;
      if (afterStudents != beforeStudents.length) {
        _emit('⚠️ Student count mismatch: expected=${beforeStudents.length} got=$afterStudents');
        pass = false;
      } else {
        _emit('✅ Student count matches: $afterStudents');
      }
      if (afterAttCount != beforeAttCount) {
        _emit('⚠️ Attendance count mismatch: expected=$beforeAttCount got=$afterAttCount');
        pass = false;
      } else {
        _emit('✅ Attendance count matches: $afterAttCount');
      }

      // ── Verify a sample embedding round-trips correctly ───────────────
      _emit('Spot-checking 5 embedding round-trips...');
      final reimported = await _db.getAllStudents();
      final origMap = {for (final s in beforeStudents) s.name: s.embedding};
      int embOk  = 0;
      int embErr = 0;
      for (final s in reimported.take(5)) {
        final orig = origMap[s.name];
        if (orig == null) { embErr++; continue; }
        final sim = _cosine(orig, s.embedding);
        if (sim > 0.9999) {
          _emit('  ✅ "${s.name}" embedding sim=$sim');
          embOk++;
        } else {
          _emit('  ⚠️ "${s.name}" embedding drift: sim=$sim');
          embErr++;
        }
      }
      _emit('Embedding spot-check: ok=$embOk err=$embErr');

      // Clean up the export file
      try { await exportFile.delete(); } catch (_) {}

      _emit('━━━ Stage 9 complete — pass=${pass && embErr == 0} ━━━');
      return pass;
    } catch (e, st) {
      appLog('[StressTest] Stage9 CRASH: $e\n${st.toString().split('\n').take(3).join(' | ')}');
      _emit('💥 Stage 9 crashed: $e');
      _abort('Stage 9: $e');
      return false;
    }
  }

  void dispose() {
    _statusCtrl.close();
  }
}