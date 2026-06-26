// lib/screens/enrollment_screen.dart
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';
import '../models/student.dart';
import '../services/app_log.dart';
import '../services/enrollment_service.dart';
import 'home_screen.dart';
import '../app_colors.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final EnrollmentService _service = EnrollmentService();
  final TextEditingController _nameController = TextEditingController();

  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _saving = false;
  final List<Uint8List> _capturedPhotos = [];
  final List<Student> _students = [];
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _initCamera();
    await _refreshStudents();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Camera permission is required.');
      return;
    }
    try {
      final cams = await availableCameras();
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      _cameraController = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Camera init failed: $e');
    }
  }

  Future<void> _refreshStudents() async {
    final list = await _service.getEnrolledStudents();
    if (!mounted) return;
    setState(() {
      _students
        ..clear()
        ..addAll(list);
    });
  }

  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_capturedPhotos.length >= 3) return;
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _capturedPhotos.add(bytes));
    } catch (e) {
      setState(() => _errorMsg = 'Capture failed: $e');
    }
  }

  Future<void> _saveStudent() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMsg = 'Enter student name first.');
      return;
    }
    if (_capturedPhotos.length != 3) {
      setState(() => _errorMsg = 'Capture 3 photos before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _errorMsg = null;
    });
    try {
      await _service.enrollStudentFromCaptures(name, List.of(_capturedPhotos));
      _nameController.clear();
      _capturedPhotos.clear();
      await _refreshStudents();
    } catch (e) {
      appLog('Student enrollment failed: $e');
      if (!mounted) return;
      setState(() => _errorMsg = '$e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _finish() async {
    if (_students.isEmpty) {
      setState(() => _errorMsg = 'Enroll at least 1 student.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Students')),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _cameraReady
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CameraPreview(_cameraController!),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Student name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed:
                            (_capturedPhotos.length < 3 && _cameraReady && !_saving)
                                ? _capturePhoto
                                : null,
                        icon: const Icon(Icons.camera_alt),
                        label: Text('Capture (${_capturedPhotos.length}/3)'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _capturedPhotos.isEmpty
                            ? null
                            : () => setState(() => _capturedPhotos.clear()),
                        child: const Text('Clear Photos'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 60,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _capturedPhotos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _capturedPhotos[i],
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _saveStudent,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save Student'),
                  ),
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMsg!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Enrolled students (${_students.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _students.length,
                      itemBuilder: (_, i) {
                        final student = _students[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.verified_user),
                          title: Text(student.name),
                          subtitle: Text('${student.sampleCount} samples'),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _finish,
                    child: const Text('Finish Enrollment'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}