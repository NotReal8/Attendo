// lib/screens/roster_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../app_colors.dart';
import '../models/student.dart';
import '../models/group.dart';
import '../services/database_service.dart';
import '../services/attendance_service.dart';
import 'register_student_screen.dart';
import 'group_form_screen.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});
  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final DatabaseService   _db  = DatabaseService();
  final AttendanceService _att = AttendanceService();

  int _tab = 0; // 0 = Students, 1 = Groups

  List<Student>                 _students = [];
  Map<String, Map<String, int>> _summary  = {};
  List<StudentGroup>            _groups   = [];
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  bool _selectMode = false;
  final Set<String> _selectedStudents = {};
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
    _load();
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final students = await _db.getAllStudents();
    final summary  = await _att.attendanceSummary();
    final groups   = await _db.getAllGroups();
    if (!mounted) return;
    setState(() { _students = students; _summary = summary; _groups = groups; _loading = false; });
  }

  Future<void> _deleteStudent(Student s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete ${s.name}?', style: const TextStyle(color: AppColors.textPrimary)),
        content: const Text('This removes their face data and group memberships. Attendance records are kept.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteStudent(s.name);
    _load();
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try { return DateFormat('MMM d, yyyy').format(DateTime.parse(iso)); } catch (_) { return iso; }
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF2563EB), Color(0xFF0EA5E9), Color(0xFF8B5CF6),
      Color(0xFFEC4899), Color(0xFF10B981), Color(0xFFF59E0B),
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedStudents.clear();
    });
  }

  Future<void> _exportSelectedStudents() async {
    if (_selectedStudents.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await _att.exportStudentsToExcel(_selectedStudents.toList());
      await Share.shareXFiles([XFile(file.path)], subject: 'Student Attendance Report');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_selectMode ? '${_selectedStudents.length} selected' : 'Roster'),
          if (!_selectMode)
            Text(_tab == 0 ? '${_students.length} students registered' : '${_groups.length} group(s)',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
        ]),
        actions: _tab != 0
            ? [
                IconButton(icon: const Icon(Icons.add_box_outlined), tooltip: 'Create group',
                    onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GroupFormScreen())).then((_) => _load())),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
              ]
            : (_selectMode
                ? [
                    _exporting
                        ? const Padding(padding: EdgeInsets.all(14),
                            child: SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))
                        : IconButton(
                            icon: const Icon(Icons.file_download_outlined),
                            tooltip: 'Export selected',
                            onPressed: _selectedStudents.isEmpty ? null : _exportSelectedStudents,
                          ),
                    IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: _toggleSelectMode),
                  ]
                : [
                    IconButton(icon: const Icon(Icons.checklist_outlined), tooltip: 'Select students',
                        onPressed: _students.isEmpty ? null : _toggleSelectMode),
                    IconButton(icon: const Icon(Icons.person_add_outlined), tooltip: 'Register student',
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const RegisterStudentScreen())).then((_) => _load())),
                    IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
                  ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(children: [
              Expanded(child: _TabButton(label: 'Students', icon: Icons.people_outline,
                  selected: _tab == 0, onTap: () => setState(() => _tab = 0))),
              Expanded(child: _TabButton(label: 'Groups', icon: Icons.folder_shared_outlined,
                  selected: _tab == 1, onTap: () => setState(() => _tab = 1))),
            ]),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : (_tab == 0 ? _studentsTab(context) : _groupsTab(context)),
        ),
      ]),
    );
  }

  // ── Students tab ──────────────────────────────────────────

  Widget _studentsTab(BuildContext context) {
    return _students.isEmpty
        ? _emptyStudentsState(context)
        : Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search student…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => _searchCtrl.clear())
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  isDense: true,
                ),
              ),
            ),
            if (_selectMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(children: [
                  TextButton(
                    onPressed: () => setState(() {
                      final filtered = _query.isEmpty
                          ? _students
                          : _students.where((s) => s.name.toLowerCase().contains(_query)).toList();
                      final allSelected = filtered.every((s) => _selectedStudents.contains(s.name));
                      if (allSelected) {
                        for (final s in filtered) _selectedStudents.remove(s.name);
                      } else {
                        for (final s in filtered) _selectedStudents.add(s.name);
                      }
                    }),
                    child: const Text('Select / Clear all'),
                  ),
                ]),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accent,
                child: Builder(builder: (_) {
                  final filtered = _query.isEmpty
                      ? _students
                      : _students.where((s) => s.name.toLowerCase().contains(_query)).toList();
                  if (filtered.isEmpty) return const Center(
                    child: Text('No students match your search.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)));
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _StudentCard(
                      student:     filtered[i],
                      summary:     _summary[filtered[i].name] ?? {'present': 0, 'absent': 0},
                      avatarColor: _avatarColor(filtered[i].name),
                      onDelete:    () => _deleteStudent(filtered[i]),
                      formatDate:  _formatDate,
                      selectMode:  _selectMode,
                      selected:    _selectedStudents.contains(filtered[i].name),
                      onTap: _selectMode
                          ? () => setState(() {
                              final name = filtered[i].name;
                              if (_selectedStudents.contains(name)) {
                                _selectedStudents.remove(name);
                              } else {
                                _selectedStudents.add(name);
                              }
                            })
                          : null,
                    ),
                  );
                }),
              ),
            ),
          ]);
  }

  Widget _emptyStudentsState(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: AppColors.accentDim, shape: BoxShape.circle),
            child: const Icon(Icons.people_outline, size: 40, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          const Text('No students registered',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Tap + to register a student',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          SizedBox(
            width: 180,
            child: ElevatedButton(
              onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RegisterStudentScreen())).then((_) => _load()),
              child: const Text('Register Student'),
            ),
          ),
        ]),
      );

  // ── Groups tab ────────────────────────────────────────────

  Widget _groupsTab(BuildContext context) {
    if (_groups.isEmpty) return _emptyGroupsState(context);
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final g = _groups[i];
          return _GroupCard(
            group: g,
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => GroupFormScreen(existingGroup: g))).then((_) => _load()),
          );
        },
      ),
    );
  }

  Widget _emptyGroupsState(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: AppColors.accentDim, shape: BoxShape.circle),
            child: const Icon(Icons.folder_shared_outlined, size: 40, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          const Text('No groups created',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Group students into classes for attendance',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          SizedBox(
            width: 180,
            child: ElevatedButton(
              onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GroupFormScreen())).then((_) => _load()),
              child: const Text('Create Group'),
            ),
          ),
        ]),
      );
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 1))] : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: selected ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: selected ? AppColors.accent : AppColors.textMuted)),
          ]),
        ),
      );
}

class _GroupCard extends StatelessWidget {
  final StudentGroup group;
  final VoidCallback onTap;
  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.accentTeal, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.folder_shared_outlined, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              Text('${group.memberCount} student(s)',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ]),
        ),
      );
}

class _StudentCard extends StatelessWidget {
  final Student              student;
  final Map<String, int>     summary;
  final Color                avatarColor;
  final VoidCallback         onDelete;
  final String Function(String?) formatDate;
  final bool                 selectMode;
  final bool                 selected;
  final VoidCallback?        onTap;

  const _StudentCard({
    required this.student,
    required this.summary,
    required this.avatarColor,
    required this.onDelete,
    required this.formatDate,
    this.selectMode = false,
    this.selected = false,
    this.onTap,
  });

  static const Color _midColor = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final present = summary['present'] ?? 0;
    final absent  = summary['absent']  ?? 0;
    final total   = present + absent;
    final pct     = total == 0 ? 0.0 : present / total;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.accent.withOpacity(0.6) : AppColors.cardBorder,
              width: selected ? 1.4 : 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (selectMode) ...[
              Checkbox(
                value: selected,
                activeColor: AppColors.accent,
                onChanged: (_) => onTap?.call(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
            ],
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
              child: Center(child: Text(
                student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(student.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              Text('Registered ${formatDate(student.registeredAt)}  ·  ${student.sampleCount} sample(s)',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ])),
            if (!selectMode)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.textMuted, size: 20),
                onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _StatChip(label: 'Present', value: '$present', color: AppColors.present),
            const SizedBox(width: 8),
            _StatChip(label: 'Absent',  value: '$absent',  color: AppColors.textMuted),
            const SizedBox(width: 8),
            _StatChip(label: 'Rate', value: '${(pct * 100).toStringAsFixed(0)}%',
                color: pct >= 0.75 ? AppColors.present : pct >= 0.50 ? _midColor : AppColors.danger),
          ]),
          if (total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct, minHeight: 4,
                backgroundColor: AppColors.accentDim,
                valueColor: AlwaysStoppedAnimation<Color>(pct >= 0.75 ? AppColors.present : AppColors.danger),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ]),
      );
}