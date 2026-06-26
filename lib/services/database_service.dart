// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/student.dart';
import '../models/attendance_record.dart';
import '../models/group.dart';

class DatabaseService {
  static final DatabaseService _i = DatabaseService._();
  factory DatabaseService() => _i;
  DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final path = p.join(await getDatabasesPath(), 'face_attendance.db');
    return openDatabase(path, version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE students (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            name          TEXT    NOT NULL UNIQUE,
            roll_no       TEXT    NOT NULL DEFAULT '',
            embedding     BLOB    NOT NULL,
            sample_count  INTEGER NOT NULL DEFAULT 1,
            registered_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE attendance (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            session_date  TEXT NOT NULL,
            session_label TEXT NOT NULL,
            student_name  TEXT NOT NULL,
            status        TEXT NOT NULL,
            group_name    TEXT NOT NULL DEFAULT 'All Students'
          )
        ''');
        await db.execute('CREATE INDEX idx_date ON attendance(session_date)');

        await db.execute('''
          CREATE TABLE groups (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT NOT NULL UNIQUE,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE group_members (
            group_id     INTEGER NOT NULL,
            student_name TEXT    NOT NULL,
            PRIMARY KEY (group_id, student_name),
            FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add roll_no column to existing installs
          await db.execute(
            "ALTER TABLE students ADD COLUMN roll_no TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
  }

  // ── Students ──────────────────────────────────────────────

  Future<void> upsertStudent(Student s) async {
    final db = await database;
    await db.insert('students', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Student>> getAllStudents() async {
    final db = await database;
    return (await db.query('students', orderBy: 'name ASC'))
        .map(Student.fromMap)
        .toList();
  }

  Future<void> deleteStudent(String name) async {
    final db = await database;
    await db.delete('students', where: 'name = ?', whereArgs: [name]);
    await db.delete('group_members', where: 'student_name = ?', whereArgs: [name]);
  }

  Future<int> studentCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM students')) ??
        0;
  }

  /// Returns a map of student name → roll number for quick lookup during export.
  Future<Map<String, String>> getRollNoMap() async {
    final db   = await database;
    final rows = await db.query('students', columns: ['name', 'roll_no']);
    return {for (final r in rows) r['name'] as String: (r['roll_no'] as String?) ?? ''};
  }

  // ── Groups ────────────────────────────────────────────────

  Future<bool> groupNameExists(String name, {int? excludeId}) async {
    final db = await database;
    final rows = await db.query(
      'groups',
      where: excludeId != null ? 'name = ? AND id != ?' : 'name = ?',
      whereArgs: excludeId != null ? [name, excludeId] : [name],
    );
    return rows.isNotEmpty;
  }

  Future<int> createGroup(String name) async {
    final db = await database;
    return db.insert('groups', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> renameGroup(int id, String newName) async {
    final db = await database;
    await db.update('groups', {'name': newName}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteGroup(int id) async {
    final db = await database;
    await db.delete('group_members', where: 'group_id = ?', whereArgs: [id]);
    await db.delete('groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<StudentGroup>> getAllGroups() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT g.id as id, g.name as name, g.created_at as created_at,
             COUNT(m.student_name) as member_count
      FROM groups g
      LEFT JOIN group_members m ON m.group_id = g.id
      GROUP BY g.id
      ORDER BY g.name ASC
    ''');
    return rows.map(StudentGroup.fromMap).toList();
  }

  Future<List<String>> getGroupMemberNames(int groupId) async {
    final db = await database;
    final rows = await db.query('group_members',
        columns: ['student_name'], where: 'group_id = ?', whereArgs: [groupId]);
    return rows.map((r) => r['student_name'] as String).toList();
  }

  Future<List<Student>> getStudentsInGroup(int groupId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.* FROM students s
      INNER JOIN group_members m ON m.student_name = s.name
      WHERE m.group_id = ?
      ORDER BY s.name ASC
    ''', [groupId]);
    return rows.map(Student.fromMap).toList();
  }

  Future<void> setGroupMembers(int groupId, Set<String> studentNames) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);
      final batch = txn.batch();
      for (final name in studentNames) {
        batch.insert('group_members', {'group_id': groupId, 'student_name': name},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  // ── Attendance ────────────────────────────────────────────

  Future<void> insertRecords(List<AttendanceRecord> records) async {
    final db    = await database;
    final batch = db.batch();
    for (final r in records) {
      batch.insert('attendance', r.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<AttendanceRecord>> recordsForDate(String date) async {
    final db = await database;
    return (await db.query('attendance',
            where: 'session_date = ?',
            whereArgs: [date],
            orderBy: 'session_label ASC, student_name ASC'))
        .map(AttendanceRecord.fromMap)
        .toList();
  }

  Future<List<AttendanceRecord>> recordsForDateAndLabel(
      String date, String label) async {
    final db = await database;
    return (await db.query(
      'attendance',
      where: 'session_date = ? AND session_label = ?',
      whereArgs: [date, label],
      orderBy: 'student_name ASC',
    )).map(AttendanceRecord.fromMap).toList();
  }

  Future<List<String>> distinctDates() async {
    final db = await database;
    return (await db.rawQuery(
            'SELECT DISTINCT session_date FROM attendance ORDER BY session_date DESC'))
        .map((r) => r['session_date'] as String)
        .toList();
  }

  Future<List<String>> distinctLabelsForDate(String date) async {
    final db = await database;
    return (await db.rawQuery(
      'SELECT DISTINCT session_label FROM attendance WHERE session_date = ? ORDER BY session_label ASC',
      [date],
    )).map((r) => r['session_label'] as String).toList();
  }

  Future<List<String>> distinctGroupNames() async {
    final db = await database;
    return (await db.rawQuery(
            'SELECT DISTINCT group_name FROM attendance ORDER BY group_name ASC'))
        .map((r) => r['group_name'] as String)
        .toList();
  }

  Future<List<AttendanceRecord>> allRecords() async {
    final db = await database;
    return (await db.query('attendance',
            orderBy:
                'session_date DESC, session_label ASC, student_name ASC'))
        .map(AttendanceRecord.fromMap)
        .toList();
  }

  Future<Map<String, Map<String, int>>> attendanceSummary() async {
    final db   = await database;
    final rows = await db.rawQuery('''
      SELECT student_name, status, COUNT(*) as cnt
      FROM attendance
      GROUP BY student_name, status
    ''');
    final Map<String, Map<String, int>> result = {};
    for (final r in rows) {
      final name   = r['student_name'] as String;
      final status = r['status'] as String;
      final count  = r['cnt'] as int;
      result.putIfAbsent(name, () => {'present': 0, 'absent': 0});
      result[name]![status] = count;
    }
    return result;
  }

  Future<void> deleteSession(String date, String label) async {
    final db = await database;
    await db.delete(
      'attendance',
      where: 'session_date = ? AND session_label = ?',
      whereArgs: [date, label],
    );
  }

  Future<void> resetAllData() async {
    final db = await database;
    await db.delete('students');
    await db.delete('attendance');
    await db.delete('group_members');
    await db.delete('groups');
  }

  Future<void> updateRecordStatus(int id, String newStatus) async {
    final db = await database;
    await db.update(
      'attendance',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Set<String>> existingAttendanceKeys() async {
    final db   = await database;
    final rows = await db.rawQuery(
      'SELECT session_date, session_label, student_name, group_name FROM attendance',
    );
    final keys = <String>{};
    for (final r in rows) {
      final date  = r['session_date']  as String;
      final label = r['session_label'] as String;
      final name  = r['student_name']  as String;
      final group = r['group_name']    as String? ?? 'All Students';
      keys.add('$date|$label|$name|$group');
    }
    return keys;
  }
}