// lib/services/enrollment_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'database_service.dart';
import 'app_log.dart';
import 'face_service.dart';
import '../models/student.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnrollmentService {
  final DatabaseService _db   = DatabaseService();
  final FaceService     _face = FaceService();

  Future<bool> isEnrolled() async => (await _db.studentCount()) > 0;

  Future<Student> enrollStudentFromCaptures(
    String rawName,
    List<Uint8List> photos, {
    String rollNo = '',
  }) async {
    final name = rawName.trim();
    if (name.isEmpty) throw Exception('Student name is required.');
    if (photos.isEmpty) throw Exception('At least 1 photo required.');

    final embedding = await _face.embeddingFromPhotos(photos);
    if (embedding == null) throw Exception('No face detected in any photo.');

    final student = Student(
      name:         name,
      rollNo:       rollNo.trim(),
      embedding:    embedding,
      sampleCount:  photos.length,
      registeredAt: DateTime.now().toIso8601String(),
    );
    await _db.upsertStudent(student);

    try {
      final prefs    = await SharedPreferences.getInstance();
      final orgId    = prefs.getString('org_id')       ?? '';
      final acctName = prefs.getString('account_name') ?? '';
      if (orgId.isNotEmpty && acctName.isNotEmpty) {
        // Encode embedding as base64 so it survives Firestore round-trip
        final bd = ByteData(student.embedding.length * 4);
        for (int i = 0; i < student.embedding.length; i++) {
          bd.setFloat32(i * 4, student.embedding[i], Endian.little);
        }
        final embB64 = base64Encode(bd.buffer.asUint8List());

        await FirebaseFirestore.instance
            .collection('orgs').doc(orgId)
            .collection('accounts').doc(acctName)
            .collection('students').doc(name)
            .set({
          'name':          name,
          'roll_no':       rollNo.trim(),
          'sample_count':  photos.length,
          'registered_at': student.registeredAt,
          'embedding':     embB64,
          'synced_at':     FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      appLog('Student Firestore sync failed (non-fatal): $e');
    }

    appLog('Enrolled "$name" (roll=$rollNo) with ${photos.length} photo(s).');
    return student;
  }

  Future<List<Student>> getEnrolledStudents() => _db.getAllStudents();

  Future<void> deleteStudent(String name) => _db.deleteStudent(name);

  Future<void> resetEnrollment() async {
    await _db.resetAllData();
    appLog('Enrollment reset');
  }
}