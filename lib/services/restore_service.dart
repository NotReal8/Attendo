// lib/services/restore_service.dart
//
// Restoration flow:
//   1. fetchAccount() — checks orgs/{orgId}/accounts/{accountName} exists.
//      Caller compares account_pass + role against what the user typed.
//   2. restoreAll()   — pulls students, groups, attendance (from the flat
//      mirror) and inserts into the local (assumed-empty, fresh-install) DB.
//      On ANY failure, wipes whatever was already inserted — partial data
//      is treated as corruption, not a recoverable state.

import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';
import '../models/attendance_record.dart';
import 'database_service.dart';
import 'app_log.dart';

class RestoreService {
  final DatabaseService _db = DatabaseService();

  /// Returns the Firestore account doc data, or null if it doesn't exist.
  Future<Map<String, dynamic>?> fetchAccount(String orgId, String accountName) async {
    if (orgId.isEmpty || accountName.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('orgs').doc(orgId)
          .collection('accounts').doc(accountName)
          .get();
      if (!doc.exists) {
        appLog('[Restore] orgs/$orgId/accounts/$accountName not found');
        return null;
      }
      appLog('[Restore] orgs/$orgId/accounts/$accountName found ✅');
      return doc.data();
    } catch (e) {
      appLog('[Restore] fetchAccount FAIL: $e');
      rethrow;
    }
  }

  Future<void> restoreAll({
    required String orgId,
    required String accountName,
    required void Function(String stage, int done, int total) onProgress,
  }) async {
    final acctRef = FirebaseFirestore.instance
        .collection('orgs').doc(orgId)
        .collection('accounts').doc(accountName);

    try {
      // ── Students ──────────────────────────────────────────
      onProgress('Fetching students…', 0, 0);
      final studentsSnap = await acctRef.collection('students').get();
      final sTotal = studentsSnap.docs.length;
      int sDone = 0;
      final restoredNames = <String>{};

      for (final doc in studentsSnap.docs) {
        final d = doc.data();
        final name = (d['name'] as String?)?.trim() ?? doc.id;
        final embB64 = d['embedding'] as String?;

        if (name.isNotEmpty && embB64 != null && embB64.isNotEmpty) {
          final embBytes = base64Decode(embB64);
          if (embBytes.length % 4 == 0) {
            final bd  = ByteData.sublistView(embBytes);
            final emb = Float32List(embBytes.length ~/ 4);
            for (int j = 0; j < emb.length; j++) {
              emb[j] = bd.getFloat32(j * 4, Endian.little);
            }
            final student = Student(
              name: name,
              rollNo: (d['roll_no'] as String?) ?? '',
              embedding: emb,
              sampleCount: (d['sample_count'] as int?) ?? 1,
              registeredAt: (d['registered_at'] as String?) ?? DateTime.now().toIso8601String(),
            );
            await _db.upsertStudent(student);
            restoredNames.add(name);
          } else {
            appLog('[Restore] "$name" skipped — corrupt embedding length');
          }
        } else {
          appLog('[Restore] "$name" skipped — missing name/embedding');
        }

        sDone++;
        onProgress('Restoring students…', sDone, sTotal);
      }
      appLog('[Restore] students done: ${restoredNames.length}/$sTotal');

      // ── Groups ────────────────────────────────────────────
      onProgress('Fetching groups…', 0, 0);
      final groupsSnap = await acctRef.collection('groups').get();
      final gTotal = groupsSnap.docs.length;
      int gDone = 0;

      for (final doc in groupsSnap.docs) {
        final d = doc.data();
        final name = (d['name'] as String?)?.trim() ?? doc.id;

        if (name.isNotEmpty) {
          final rawMembers = (d['members'] as List<dynamic>?) ?? [];
          // Local check: only keep members that were actually restored above —
          // protects against a stale member list referencing a deleted student.
          final members = rawMembers
              .map((m) => (m as String).trim())
              .where((m) => restoredNames.contains(m))
              .toSet();

          final exists = await _db.groupNameExists(name);
          if (!exists) {
            final groupId = await _db.createGroup(name);
            await _db.setGroupMembers(groupId, members);
          }
        }

        gDone++;
        onProgress('Restoring groups…', gDone, gTotal);
      }
      appLog('[Restore] groups done: $gTotal');

      // ── Attendance (from the flat mirror — flat collection means we
      //    don't need to already know every date/label to list records) ──
      onProgress('Fetching attendance…', 0, 0);
      final attSnap = await acctRef.collection('attendance_flat').get();
      final aTotal = attSnap.docs.length;
      final records = <AttendanceRecord>[];

      for (final doc in attSnap.docs) {
        final d      = doc.data();
        final date   = (d['date']         as String?)?.trim() ?? '';
        final label  = (d['session']      as String?)?.trim() ?? '';
        final name   = (d['student_name'] as String?)?.trim() ?? '';
        final status = (d['status']       as String?)?.trim() ?? '';
        final group  = (d['group_name']   as String?)?.trim() ?? 'All Students';

        if (date.isEmpty || label.isEmpty || name.isEmpty ||
            (status != 'present' && status != 'absent')) {
          continue;
        }

        records.add(AttendanceRecord(
          sessionDate: date, sessionLabel: label,
          studentName: name, status: status, groupName: group,
        ));
      }
      if (records.isNotEmpty) await _db.insertRecords(records);
      onProgress('Restoring attendance…', aTotal, aTotal);
      appLog('[Restore] attendance done: ${records.length}/$aTotal');

      onProgress('Done', 1, 1);
    } catch (e) {
      appLog('[Restore] FAILED — wiping partial data: $e');
      try { await _db.resetAllData(); } catch (_) {}
      rethrow;
    }
  }
}