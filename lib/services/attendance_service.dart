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

  // ── Excel export — by session ─────────────────────────────

  Future<File> exportToExcel(
    List<({String date, String label})> selectedSessions,
  ) async {
    final prefs   = await SharedPreferences.getInstance();
    final orgName = prefs.getString('org_id')       ?? 'Institution';
    final acctName= prefs.getString('account_name') ?? '';

    final rollNoMap = await _db.getRollNoMap();

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    for (final session in selectedSessions) {
      final records = await _db.recordsForDateAndLabel(session.date, session.label);
      if (records.isEmpty) continue;

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

      final colHeaders = ['Date', 'Name', 'Roll No', 'Status'];
      for (int col = 0; col < colHeaders.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 10));
        cell.value = TextCellValue(colHeaders[col]);
        cell.cellStyle = headerStyle();
      }

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

      sheet.setColumnWidth(0, 14);
      sheet.setColumnWidth(1, 28);
      sheet.setColumnWidth(2, 12);
      sheet.setColumnWidth(3, 12);
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

  // ── Excel export — by student ─────────────────────────────
  //
  // One sheet per student. Each sheet lists every session they appear in,
  // with a summary header block matching the session-export style.

  Future<File> exportStudentsToExcel(List<String> studentNames) async {
    final prefs    = await SharedPreferences.getInstance();
    final orgName  = prefs.getString('org_id')       ?? 'Institution';
    final acctName = prefs.getString('account_name') ?? '';

    final rollNoMap = await _db.getRollNoMap();

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    for (final name in studentNames) {
      final records = await _db.recordsForStudent(name);

      // Sheet name: student name sanitised, max 31 chars
      final rawSheet = name.replaceAll(RegExp(r'[:\\/?*\[\]]'), '-');
      final sheetName = rawSheet.length > 31 ? rawSheet.substring(0, 31) : rawSheet;

      final sheet = excel[sheetName];

      final total   = records.length;
      final present = records.where((r) => r.status == 'present').length;
      final absent  = total - present;
      final pct     = total == 0
          ? '0%'
          : '${(present / total * 100).toStringAsFixed(1)}%';

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

      void writeHeader(int row, String key, String value) {
        final keyCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        keyCell.value = TextCellValue(key);
        keyCell.cellStyle = boldStyle();
        final valCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
        valCell.value = TextCellValue(value);
      }

      writeHeader(0, 'Institution',     orgName);
      writeHeader(1, 'Account',         acctName);
      writeHeader(2, 'Student',         name);
      writeHeader(3, 'Roll No',         rollNoMap[name] ?? '');
      writeHeader(4, 'Total Sessions',  '$total');
      writeHeader(5, 'Present',         '$present');
      writeHeader(6, 'Absent',          '$absent');
      writeHeader(7, 'Attendance %',    pct);

      // Column headers (row 9)
      final colHeaders = ['Date', 'Session', 'Group', 'Status'];
      for (int col = 0; col < colHeaders.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 9));
        cell.value = TextCellValue(colHeaders[col]);
        cell.cellStyle = headerStyle();
      }

      // Data rows from row 10
      for (int i = 0; i < records.length; i++) {
        final r   = records[i];
        final row = 10 + i;

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            TextCellValue(DateFormat('dd-MM-yy').format(DateTime.parse(r.sessionDate)));
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
            TextCellValue(r.sessionLabel);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value =
            TextCellValue(r.groupName);

        final statusCell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        statusCell.value = TextCellValue(r.status == 'present' ? 'Present' : 'Absent');
        statusCell.cellStyle =
            r.status == 'present' ? presentStyle() : absentStyle();
      }

      sheet.setColumnWidth(0, 14);
      sheet.setColumnWidth(1, 24);
      sheet.setColumnWidth(2, 20);
      sheet.setColumnWidth(3, 12);

      appLog('[AttendanceService] exportStudents: "$name" — $total record(s)');
    }

    if (excel.sheets.isEmpty) {
      throw Exception('No attendance records found for selected students.');
    }

    final bytes = excel.save();
    if (bytes == null) throw Exception('Failed to encode Excel file.');

    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Student_Attendance_Report.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    appLog('[AttendanceService] Student Excel export done ✅ path=${file.path}');
    return file;
  }
}