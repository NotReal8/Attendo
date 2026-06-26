// lib/services/transfer_service.dart
//
// Export envelope format (version 2): students, groups, attendance (with groupName).
// Import rules:
//   Students   — skip if name already exists (case-insensitive)
//   Groups     — skip if name already exists; members filtered to known students
//   Attendance — skip if (sessionDate + sessionLabel + studentName + groupName) exists

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_record.dart';
import '../models/student.dart';
import 'app_log.dart';
import 'database_service.dart';

class TransferResult {
  final int studentsImported;
  final int studentsSkipped;
  final int studentsFailed;
  final List<String> skippedStudentNames;
  final List<String> failedStudentNames;

  final int groupsImported;
  final int groupsSkipped;
  final int groupsFailed;

  final int attendanceImported;
  final int attendanceSkipped;
  final int attendanceFailed;

  const TransferResult({
    required this.studentsImported,
    required this.studentsSkipped,
    required this.studentsFailed,
    required this.skippedStudentNames,
    required this.failedStudentNames,
    required this.groupsImported,
    required this.groupsSkipped,
    required this.groupsFailed,
    required this.attendanceImported,
    required this.attendanceSkipped,
    required this.attendanceFailed,
  });

  @override
  String toString() => 'TransferResult('
      'studentsImported=$studentsImported, studentsSkipped=$studentsSkipped, studentsFailed=$studentsFailed, '
      'groupsImported=$groupsImported, groupsSkipped=$groupsSkipped, groupsFailed=$groupsFailed, '
      'attendanceImported=$attendanceImported, attendanceSkipped=$attendanceSkipped, attendanceFailed=$attendanceFailed)';
}

class TransferService {
  static final TransferService _i = TransferService._();
  factory TransferService() => _i;
  TransferService._();

  final DatabaseService _db = DatabaseService();

  static const int    _formatVersion  = 2;
  static const String _exportFileName = 'roster_export.json';

  // ── Export ────────────────────────────────────────────────

  Future<File> exportRoster() async {
    appLog('[TransferService] exportRoster() started');

    final students = await _db.getAllStudents();
    if (students.isEmpty) {
      throw Exception('No students enrolled. Enroll students before exporting.');
    }

    final prefs       = await SharedPreferences.getInstance();
    final accountName = prefs.getString('account_name') ?? 'Unknown';

    final studentJsonList = <Map<String, dynamic>>[];
    for (final s in students) {
      final bd = ByteData(s.embedding.length * 4);
      for (int j = 0; j < s.embedding.length; j++) {
        bd.setFloat32(j * 4, s.embedding[j], Endian.little);
      }
      studentJsonList.add({
        'name':         s.name,
        'rollNo':       s.rollNo,
        'sampleCount':  s.sampleCount,
        'registeredAt': s.registeredAt ?? DateTime.now().toIso8601String(),
        'embedding':    base64Encode(bd.buffer.asUint8List()),
      });
    }
    appLog('[TransferService] exportRoster() — students serialized ✅');

    final groups = await _db.getAllGroups();
    final groupJsonList = <Map<String, dynamic>>[];
    for (final g in groups) {
      if (g.id == null) continue;
      final members = await _db.getGroupMemberNames(g.id!);
      groupJsonList.add({
        'name':      g.name,
        'createdAt': g.createdAt ?? DateTime.now().toIso8601String(),
        'members':   members,
      });
    }
    appLog('[TransferService] exportRoster() — groups serialized ✅');

    final records = await _db.allRecords();
    final attendanceJsonList = records.map((r) => {
          'sessionDate':  r.sessionDate,
          'sessionLabel': r.sessionLabel,
          'studentName':  r.studentName,
          'status':     r.status,

          'groupName':    r.groupName,

          }).toList();
          appLog('[TransferService] exportRoster() — attendance serialized ✅');

    final envelope = {
  'version':         _formatVersion,
  'exportedAt':      DateTime.now().toIso8601String(),
  'accountName':     accountName,
  'studentCount':    students.length,
  'groupCount':      groupJsonList.length,
  'attendanceCount': records.length,
  'students':        studentJsonList,
  'groups':          groupJsonList,
  'attendance':      attendanceJsonList,
};

final jsonString = const JsonEncoder.withIndent('  ').convert(envelope);

final dir      = await getApplicationDocumentsDirectory();
final filePath = '${dir.path}/$_exportFileName';
final file = File(filePath);
await file.writeAsString(jsonString, flush: true);
appLog('[TransferService] exportRoster() — file written ✅  path=$filePath');

return file;
}
// ── Import ────────────────────────────────────────────────
Future<TransferResult> importRoster(String filePath) async {

appLog('[TransferService] importRoster() started — path=$filePath');

final file   = File(filePath);
final exists = await file.exists();
if (!exists) throw Exception('Import file not found: $filePath');

final jsonString = await file.readAsString();

late Map<String, dynamic> envelope;
try {
  envelope = json.decode(jsonString) as Map<String, dynamic>;
} catch (e) {
  throw Exception('Invalid file format. The selected file is not a valid roster export.');
}

final version = envelope['version'] as int? ?? 0;
if (version != 1 && version != _formatVersion) {
  throw Exception('Unsupported export version: $version. Expected $_formatVersion.');
}
appLog('[TransferService] importRoster() — version=$version');

// ════════════════════════════════════════════════════
// PASS 1 — Students
// ════════════════════════════════════════════════════

final rawStudents = envelope['students'] as List<dynamic>?;
if (rawStudents == null || rawStudents.isEmpty) {
  throw Exception('Export file contains no student records.');
}

final existingStudents = await _db.getAllStudents();
final existingNames    = existingStudents.map((s) => s.name.toLowerCase()).toSet();

int studentsImported = 0;
int studentsSkipped  = 0;
int studentsFailed   = 0;
final skippedStudentNames = <String>[];
final failedStudentNames  = <String>[];

for (int i = 0; i < rawStudents.length; i++) {
  final raw = rawStudents[i];
  if (raw is! Map<String, dynamic>) {
    studentsFailed++;
    failedStudentNames.add('record_$i');
    continue;
  }

  final name = (raw['name'] as String?)?.trim() ?? '';
  if (name.isEmpty) {
    studentsFailed++;
    failedStudentNames.add('(empty name at index $i)');
    continue;
  }

  if (existingNames.contains(name.toLowerCase())) {
    studentsSkipped++;
    skippedStudentNames.add(name);
    continue;
  }

  final sampleCount  = (raw['sampleCount']  as int?)    ?? 1;
  final registeredAt = (raw['registeredAt'] as String?) ?? DateTime.now().toIso8601String();
  final rollNo       = (raw['rollNo']       as String?) ?? '';
  final embeddingB64 = raw['embedding']     as String?;

  if (embeddingB64 == null || embeddingB64.isEmpty) {
    studentsFailed++;
    failedStudentNames.add(name);
    continue;
  }

  late Uint8List embeddingBytes;
  try {
    embeddingBytes = base64Decode(embeddingB64);
  } catch (e) {
    studentsFailed++;
    failedStudentNames.add(name);
    continue;
  }

  if (embeddingBytes.length % 4 != 0) {
    studentsFailed++;
    failedStudentNames.add(name);
    continue;
  }

  final bd  = ByteData.sublistView(embeddingBytes);
  final emb = Float32List(embeddingBytes.length ~/ 4);
  for (int j = 0; j < emb.length; j++) {
    emb[j] = bd.getFloat32(j * 4, Endian.little);
  }

  final student = Student(
    name:         name,
    rollNo:       rollNo,
    embedding:    emb,
    sampleCount:  sampleCount,
    registeredAt: registeredAt,
  );

  try {
    await _db.upsertStudent(student);
    studentsImported++;
    existingNames.add(name.toLowerCase());
  } catch (e) {
    studentsFailed++;
    failedStudentNames.add(name);
  }
}

appLog('[TransferService] importRoster() — student pass done: '
    'imported=$studentsImported skipped=$studentsSkipped failed=$studentsFailed');

// ════════════════════════════════════════════════════
// PASS 2 — Groups
// ════════════════════════════════════════════════════

int groupsImported = 0;
int groupsSkipped  = 0;
int groupsFailed   = 0;

final rawGroups = envelope['groups'] as List<dynamic>?;
if (rawGroups == null || rawGroups.isEmpty) {
  appLog('[TransferService] importRoster() — no groups in envelope — skipping group pass');
} else {
  // Names of students now present locally (post student-pass)
  final allLocalNames = (await _db.getAllStudents()).map((s) => s.name).toSet();

  for (int i = 0; i < rawGroups.length; i++) {
    final raw = rawGroups[i];
    if (raw is! Map<String, dynamic>) { groupsFailed++; continue; }

    final name = (raw['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) { groupsFailed++; continue; }

    final exists = await _db.groupNameExists(name);
    if (exists) { groupsSkipped++; continue; }

    final rawMembers = (raw['members'] as List<dynamic>?) ?? [];
    final members = rawMembers
        .map((m) => (m as String).trim())
        .where((m) => allLocalNames.contains(m))
        .toSet();

    try {
      final groupId = await _db.createGroup(name);
      await _db.setGroupMembers(groupId, members);
      groupsImported++;
      appLog('[TransferService] importRoster() — group "$name" imported with ${members.length} member(s)');
    } catch (e) {
      groupsFailed++;
      appLog('[TransferService] importRoster() — group "$name" FAIL: $e');
    }
  }
}

appLog('[TransferService] importRoster() — group pass done: '
    'imported=$groupsImported skipped=$groupsSkipped failed=$groupsFailed');

// ════════════════════════════════════════════════════
// PASS 3 — Attendance records
// ════════════════════════════════════════════════════

final rawAttendance = envelope['attendance'] as List<dynamic>?;

int attendanceImported = 0;
int attendanceSkipped  = 0;
int attendanceFailed   = 0;

if (rawAttendance == null || rawAttendance.isEmpty) {
  appLog('[TransferService] importRoster() — no attendance array — skipping');
} else {
  final existingKeys = await _db.existingAttendanceKeys();
  final toInsert = <AttendanceRecord>[];

  for (int i = 0; i < rawAttendance.length; i++) {
    final raw = rawAttendance[i];
    if (raw is! Map<String, dynamic>) { attendanceFailed++; continue; }

    final sessionDate  = (raw['sessionDate']  as String?)?.trim() ?? '';
    final sessionLabel = (raw['sessionLabel'] as String?)?.trim() ?? '';
    final studentName  = (raw['studentName']  as String?)?.trim() ?? '';
    final status       = (raw['status']       as String?)?.trim() ?? '';
    final groupName    = (raw['groupName']    as String?)?.trim() ?? 'All Students';

    if (sessionDate.isEmpty || sessionLabel.isEmpty ||
        studentName.isEmpty || status.isEmpty) {
      attendanceFailed++;
      continue;
    }

    if (status != 'present' && status != 'absent') {
      attendanceFailed++;
      continue;
    }

    final key = '$sessionDate|$sessionLabel|$studentName|$groupName';

    if (existingKeys.contains(key)) {
      attendanceSkipped++;
      continue;
    }

    toInsert.add(AttendanceRecord(
      sessionDate:  sessionDate,
      sessionLabel: sessionLabel,
      studentName:  studentName,
      status:       status,
      groupName:    groupName,
    ));
    existingKeys.add(key);
  }

  if (toInsert.isNotEmpty) {
    try {
      await _db.insertRecords(toInsert);
      attendanceImported = toInsert.length;
    } catch (e) {
      attendanceFailed   += toInsert.length;
      attendanceImported  = 0;
    }
  }
}

appLog('[TransferService] importRoster() — attendance pass done: '
    'imported=$attendanceImported skipped=$attendanceSkipped failed=$attendanceFailed');

final result = TransferResult(
  studentsImported:    studentsImported,
  studentsSkipped:     studentsSkipped,
  studentsFailed:      studentsFailed,
  skippedStudentNames: skippedStudentNames,
  failedStudentNames:  failedStudentNames,
  groupsImported:      groupsImported,
  groupsSkipped:       groupsSkipped,
  groupsFailed:        groupsFailed,
  attendanceImported:  attendanceImported,
  attendanceSkipped:   attendanceSkipped,
  attendanceFailed:    attendanceFailed,
);
appLog('[TransferService] importRoster() complete ✅  $result');
return result;

}

}