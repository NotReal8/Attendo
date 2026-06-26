// lib/models/attendance_record.dart
class AttendanceRecord {
  final int?   id;
  final String sessionDate;
  final String sessionLabel;
  final String studentName;
  final String status;
  final String groupName;

  const AttendanceRecord({
    this.id,
    required this.sessionDate,
    required this.sessionLabel,
    required this.studentName,
    required this.status,
    this.groupName = 'All Students',
  });

  bool get isPresent => status == 'present';

  Map<String, dynamic> toMap() => {
        'session_date':  sessionDate,
        'session_label': sessionLabel,
        'student_name':  studentName,
        'status':        status,
        'group_name':    groupName,
      };

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) =>
      AttendanceRecord(
        id:           map['id'] as int?,
        sessionDate:  map['session_date'] as String,
        sessionLabel: map['session_label'] as String,
        studentName:  map['student_name'] as String,
        status:       map['status'] as String,
        groupName:    (map['group_name'] as String?) ?? 'All Students',
      );
}