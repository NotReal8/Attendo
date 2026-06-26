// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_colors.dart';
import '../services/app_log.dart';
import '../services/database_service.dart';
import 'register_student_screen.dart';
import 'select_group_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _studentCount = 0;

  @override
  void initState() {
    super.initState();
    AppLog.instance.addListener(_onLog);
    _loadCount();
  }

  @override
  void dispose() {
    AppLog.instance.removeListener(_onLog);
    super.dispose();
  }

  void _onLog() { if (mounted) setState(() {}); }

  Future<void> _loadCount() async {
    final c = await DatabaseService().studentCount();
    if (mounted) setState(() => _studentCount = c);
  }

  @override
  Widget build(BuildContext context) {
    final logs = AppLog.instance.entries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Face Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Register student',
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RegisterStudentScreen()))
              .then((_) => _loadCount()),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Hero stats card ───────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.heroGradientStart, AppColors.heroGradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              const Icon(Icons.face_retouching_natural,
                  size: 28, color: Colors.white70),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_studentCount student(s) registered',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const Text('Ready for attendance',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Action buttons ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _ActionTile(
                icon: Icons.camera_alt_outlined,
                label: 'Take Attendance',
                sub: 'Choose a group, then recognise faces',
                iconBg: AppColors.accent,
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SelectGroupScreen()))
                  .then((_) => _loadCount()),
              ),
              const SizedBox(height: 10),
              _ActionTile(
                icon: Icons.person_add_outlined,
                label: 'Register Student',
                sub: 'Add a new student profile with photos',
                iconBg: AppColors.accentTeal,
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterStudentScreen()))
                  .then((_) => _loadCount()),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Debug log panel ───────────────────────────────
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                  child: Row(children: [
                    const Icon(Icons.terminal, size: 13, color: Colors.white38),
                    const SizedBox(width: 6),
                    const Text('Debug Log',
                        style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    _logBtn(Icons.copy, 'Copy', () {
                      Clipboard.setData(ClipboardData(text: AppLog.instance.allText));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Log copied'), duration: Duration(seconds: 1)));
                    }),
                    const SizedBox(width: 4),
                    _logBtn(Icons.delete_outline, 'Clear', () => AppLog.instance.clear()),
                  ]),
                ),
                const Divider(height: 1, color: Color(0xFF1E293B)),
                Expanded(
                  child: logs.isEmpty
                      ? Center(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Text('Log will appear here…',
                                style: TextStyle(color: Colors.white24, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text('File: ${AppLog.instance.logFilePath}',
                                style: const TextStyle(color: Colors.white24, fontSize: 10),
                                textAlign: TextAlign.center),
                          ]),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: logs.length,
                          reverse: true,
                          itemBuilder: (_, i) {
                            final e = logs[logs.length - 1 - i];
                            final isErr = e.contains('ERROR') || e.contains('❌');
                            final isOk  = e.contains('✅') || e.contains('MATCH') || e.contains('ready');
                            final color = isErr ? AppColors.danger : isOk ? AppColors.present : Colors.white38;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(e, style: TextStyle(color: color, fontSize: 10.5, fontFamily: 'monospace')),
                            );
                          },
                        ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logBtn(IconData icon, String label, VoidCallback onTap) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 12, color: Colors.white24),
        label: Text(label, style: const TextStyle(color: Colors.white24, fontSize: 11)),
        style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color iconBg;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label, required this.sub, required this.iconBg, required this.onTap});

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
              Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ]),
        ),
      );
}