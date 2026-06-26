// lib/screens/select_group_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../models/group.dart';
import '../services/database_service.dart';
import 'attendance_screen.dart';

class SelectGroupScreen extends StatefulWidget {
  const SelectGroupScreen({super.key});
  @override
  State<SelectGroupScreen> createState() => _SelectGroupScreenState();
}

class _SelectGroupScreenState extends State<SelectGroupScreen> {
  final DatabaseService _db = DatabaseService();
  List<StudentGroup> _groups = [];
  int _allCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groups = await _db.getAllGroups();
    final count  = await _db.studentCount();
    if (!mounted) return;
    setState(() { _groups = groups; _allCount = count; _loading = false; });
  }

  void _start({int? groupId, required String groupName}) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => AttendanceScreen(groupId: groupId, groupName: groupName),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Select Group'),
          const Text('Choose the domain for this session',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _GroupTile(
                  icon: Icons.groups_outlined,
                  iconBg: AppColors.accent,
                  title: 'All Students',
                  sub: '$_allCount student(s) · entire roster',
                  onTap: () => _start(groupId: null, groupName: 'All Students'),
                ),
                const SizedBox(height: 14),
                if (_groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No groups created yet.\nCreate one from the Roster → Groups tab.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ),
                  )
                else ...[
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('GROUPS',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11,
                            fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                  ),
                  ..._groups.map((g) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GroupTile(
                          icon: Icons.folder_shared_outlined,
                          iconBg: AppColors.accentTeal,
                          title: g.name,
                          sub: '${g.memberCount} student(s)',
                          onTap: () => _start(groupId: g.id, groupName: g.name),
                        ),
                      )),
                ],
              ],
            ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title, sub;
  final VoidCallback onTap;
  const _GroupTile({required this.icon, required this.iconBg, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ]),
        ),
      );
}