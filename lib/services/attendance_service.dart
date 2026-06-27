// lib/services/attendance_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_record.dart';
import 'database_service.dart';
import 'app_log.dart';

class AttendanceService {
  final DatabaseService _db = DatabaseService();

  static String get todayDate =>
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  static String get sessionLabel {
    final t = DateTime.now();
    return 'Session · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> saveSession({
    required String      date,
    required String      label,
    required Set<String> presentNames,
    required String      groupName,
    int? groupId,
  }) async {
    appLog('[AttendanceService] saveSession date=$date label=$label group=$groupName');
    final domainStudents = groupId != null
        ? await _db.getStudentsInGroup(groupId)
        : await _db.getAllStudents();

    final records = <AttendanceRecord>[];
    for (final s in domainStudents) {
      final status = presentNames.contains(s.name) ? 'present' : 'absent';
      records.add(AttendanceRecord(
        sessionDate:  date,
        sessionLabel: label,
        studentName:  s.name,
        status:       status,
        groupName:    groupName,
      ));
    }

    await _db.insertRecords(records);
    appLog('[AttendanceService] saveSession done — ${records.length} record(s) ✅');

    try {
      final prefs    = await SharedPreferences.getInstance();
      final orgId    = prefs.getString('org_id')       ?? '';
      final acctName = prefs.getString('account_name') ?? '';

      if (orgId.isEmpty || acctName.isEmpty) {
        appLog('[AttendanceService] Firestore skip — orgId or acctName empty');
        return;
      }

      appLog('[AttendanceService] Firestore mirror org=$orgId account=$acctName records=${records.length}');

      final fs       = FirebaseFirestore.instance;
      final acctRef  = fs.collection('orgs').doc(orgId).collection('accounts').doc(acctName);
      final rollNoMap = await _db.getRollNoMap();

      // Firestore batch limit is 500 — chunk if needed
      const chunkSize = 400;
      for (int start = 0; start < records.length; start += chunkSize) {
        final chunk = records.sublist(start,
            (start + chunkSize).clamp(0, records.length));
        final batch = fs.batch();
        for (final r in chunk) {
          final ref = acctRef
              .collection('attendance')
              .doc(r.sessionDate)
              .collection(r.sessionLabel)
              .doc(r.studentName);
          batch.set(ref, {
            'name':       r.studentName,
            'roll_no':    rollNoMap[r.studentName] ?? '',
            'status':     r.status,
            'group_name': r.groupName,
            'synced_at':  FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      // Flat mirror for web dashboard querying
      for (int start = 0; start < records.length; start += chunkSize) {
        final chunk = records.sublist(start,
            (start + chunkSize).clamp(0, records.length));
        final batch = fs.batch();
        for (final r in chunk) {
          final ref = acctRef
              .collection('attendance_flat')
              .doc('${r.sessionDate}__${r.sessionLabel}__${r.studentName}'.replaceAll(' ', '_').replaceAll('·', '-'));
          batch.set(ref, {
            'account':      acctName,
            'date':         r.sessionDate,
            'session':      r.sessionLabel,
            'student_name': r.studentName,
            'roll_no':      rollNoMap[r.studentName] ?? '',
            'status':       r.status,
            'group_name':   r.groupName,
            'synced_at':    FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      appLog('[AttendanceService] Firestore mirror done ✅');
    } catch (e) {
      appLog('[AttendanceService] Firestore mirror failed (non-fatal): $e');
    }
  }

  Future<void> syncStatusUpdate({
  required String orgId,
  required String date,
  required String label,
  required String studentName,
  required String newStatus,
  required String accountName,
}) async {
  try {
    final fs      = FirebaseFirestore.instance;
    final acctRef = fs.collection('orgs').doc(orgId)
        .collection('accounts').doc(accountName);

    await acctRef
        .collection('attendance').doc(date)
        .collection(label).doc(studentName)
        .update({
      'status':     newStatus,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': accountName,
    });

    final flatDocId = '${date}__${label}__${studentName}'
        .replaceAll(' ', '_')
        .replaceAll('·', '-');
    await acctRef
        .collection('attendance_flat').doc(flatDocId)
        .update({
      'status':     newStatus,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': accountName,
    });

    appLog('[AttendanceService] Firestore status sync done ✅ $studentName→$newStatus');
  } catch (e) {
    appLog('[AttendanceService] Firestore status sync failed (non-fatal): $e');
  }
}

  Future<List<String>> getSessionDates() async => _db.distinctDates();

  Future<List<String>> getGroupNames() async => _db.distinctGroupNames();

  Future<List<AttendanceRecord>> getRecordsForDate(String date) async =>
      _db.recordsForDate(date);

  Future<Map<String, Map<String, int>>> attendanceSummary() async =>
      _db.attendanceSummary();

  Future<void> deleteSession(String date, String label) async {
    appLog('[AttendanceService] deleteSession date=$date label=$label');
    await _db.deleteSession(date, label);
  }

  // ── Excel export ──────────────────────────────────────────
  //
  // [selectedSessions] is a list of (date, label) pairs chosen by the user.
  // One sheet per session. Header block at top of each sheet.

  Future<File> exportToExcel(
    List<({String date, String label})> selectedSessions,
  ) async {
    final prefs   = await SharedPreferences.getInstance();
    final orgName = prefs.getString('org_id')       ?? 'Institution';
    final acctName= prefs.getString('account_name') ?? '';

    // Roll number lookup
    final rollNoMap = await _db.getRollNoMap();

    final excel = Excel.createExcel();
    // Remove default Sheet1
    excel.delete('Sheet1');

    for (final session in selectedSessions) {
      final records = await _db.recordsForDateAndLabel(session.date, session.label);
      if (records.isEmpty) continue;

      // Sheet name: sanitise label for Excel (max 31 chars, no special chars)
      final rawSheetName = '${session.date} ${session.label}'
          .replaceAll(RegExp(r'[:\\/?*\[\]]'), '-');
      final sheetName = rawSheetName.length > 31
          ? rawSheetName.substring(0, 31)
          : rawSheetName;

      final sheet = excel[sheetName];

      final present = records.where((r) => r.status == 'present').length;
      final absent  = records.length - present;
      final pct     = records.isEmpty
          ? '0%'
          : '${(present / records.length * 100).toStringAsFixed(1)}%';

      final groupName = records.first.groupName;

      // ── Helper: bold cell style ───────────────────────────
      CellStyle boldStyle() => CellStyle(
            bold: true,
            fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
            backgroundColorHex: ExcelColor.fromHexString('#1E293B'),
          );

      CellStyle headerStyle() => CellStyle(
            bold: true,
            fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
            backgroundColorHex: ExcelColor.fromHexString('#2563EB'),
          );

      CellStyle presentStyle() => CellStyle(
            fontColorHex: ExcelColor.fromHexString('#16A34A'),
            bold: true,
          );

      CellStyle absentStyle() => CellStyle(
            fontColorHex: ExcelColor.fromHexString('#DC2626'),
            bold: true,
          );

      // ── Header block (rows 0–6) ───────────────────────────
      void writeHeader(int row, String key, String value) {
        final keyCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        keyCell.value = TextCellValue(key);
        keyCell.cellStyle = boldStyle();

        final valCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
        valCell.value = TextCellValue(value);
      }

      writeHeader(0, 'Institution',    orgName);
      writeHeader(1, 'Account',        acctName);
      writeHeader(2, 'Date',           DateFormat('dd MMM yyyy').format(DateTime.parse(session.date)));
      writeHeader(3, 'Session',        session.label);
      writeHeader(4, 'Group / Domain', groupName);
      writeHeader(5, 'Total Students', '${records.length}');
      writeHeader(6, 'Present',        '$present');
      writeHeader(7, 'Absent',         '$absent');
      writeHeader(8, 'Attendance %',   pct);

      // Blank separator row
      // (row 9 left empty)

      // ── Column headers (row 10) ───────────────────────────
      final colHeaders = ['Date', 'Name', 'Roll No', 'Status'];
      for (int col = 0; col < colHeaders.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 10));
        cell.value = TextCellValue(colHeaders[col]);
        cell.cellStyle = headerStyle();
      }

      // ── Data rows (from row 11) ───────────────────────────
      final dateStr = DateFormat('dd-MM-yy').format(DateTime.parse(session.date));
      for (int i = 0; i < records.length; i++) {
        final r   = records[i];
        final row = 11 + i;

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            TextCellValue(dateStr);

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
            TextCellValue(r.studentName);

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value =
            TextCellValue(rollNoMap[r.studentName] ?? '');

        final statusCell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        statusCell.value = TextCellValue(r.status == 'present' ? 'Present' : 'Absent');
        statusCell.cellStyle =
            r.status == 'present' ? presentStyle() : absentStyle();
      }

      // Column widths
      sheet.setColumnWidth(0, 14); // Date
      sheet.setColumnWidth(1, 28); // Name
      sheet.setColumnWidth(2, 12); // Roll No
      sheet.setColumnWidth(3, 12); // Status
    }

    if (excel.sheets.isEmpty) {
      throw Exception('No records found for selected sessions.');
    }

    final bytes = excel.save();
    if (bytes == null) throw Exception('Failed to encode Excel file.');

    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Attendance_Report.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    appLog('[AttendanceService] Excel export done ✅ path=${file.path}');
    return file;
  }
}