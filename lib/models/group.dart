// lib/models/group.dart
class StudentGroup {
  final int? id;
  final String name;
  final String? createdAt;
  final int memberCount;

  const StudentGroup({
    this.id,
    required this.name,
    this.createdAt,
    this.memberCount = 0,
  });

  factory StudentGroup.fromMap(Map<String, dynamic> map) => StudentGroup(
        id: map['id'] as int?,
        name: map['name'] as String,
        createdAt: map['created_at'] as String?,
        memberCount: (map['member_count'] as int?) ?? 0,
      );
}