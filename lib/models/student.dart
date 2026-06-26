// lib/models/student.dart
import 'dart:typed_data';

class Student {
  final int?        id;
  final String      name;
  final String      rollNo;
  final Float32List embedding;
  final int         sampleCount;
  final String?     registeredAt;

  const Student({
    this.id,
    required this.name,
    this.rollNo = '',
    required this.embedding,
    this.sampleCount = 1,
    this.registeredAt,
  });

  Map<String, dynamic> toMap() {
    final bd = ByteData(embedding.length * 4);
    for (int i = 0; i < embedding.length; i++) {
      bd.setFloat32(i * 4, embedding[i], Endian.little);
    }
    return {
      'name':          name,
      'roll_no':       rollNo,
      'embedding':     bd.buffer.asUint8List(),
      'sample_count':  sampleCount,
      'registered_at': registeredAt ?? DateTime.now().toIso8601String(),
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    final bytes = map['embedding'] as Uint8List;
    final bd    = ByteData.sublistView(bytes);
    final emb   = Float32List(bytes.length ~/ 4);
    for (int i = 0; i < emb.length; i++) {
      emb[i] = bd.getFloat32(i * 4, Endian.little);
    }
    return Student(
      id:           map['id'] as int?,
      name:         map['name'] as String,
      rollNo:       (map['roll_no'] as String?) ?? '',
      embedding:    emb,
      sampleCount:  (map['sample_count'] as int?) ?? 1,
      registeredAt: map['registered_at'] as String?,
    );
  }
}