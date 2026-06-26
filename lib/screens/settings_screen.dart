// lib/screens/settings_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_colors.dart';
import '../services/app_log.dart';
import '../services/beacon_service.dart';
import '../services/database_service.dart';
import '../services/stress_test_service.dart';
import '../services/transfer_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _accountName = '', _accountRole = '', _orgId = '';
  bool _exporting = false, _importing = false;

  @override
  void initState() { super.initState(); _loadName(); }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _accountName = prefs.getString('account_name') ?? '';
      _accountRole = prefs.getString('account_role') ?? '';
      _orgId       = prefs.getString('org_id')       ?? '';
    });
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _accountName);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Account Name', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(controller: ctrl, autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: 'Enter your name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_name', result);
    setState(() => _accountName = result);
    BeaconService.ping();
  }

  Future<void> _exportRoster() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await TransferService().exportRoster();
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Student Roster Export — $_accountName',
          text: 'Roster export from Face Attendance.');
    } catch (e) { if (mounted) _showError('Export failed: $e'); }
    finally { if (mounted) setState(() => _exporting = false); }
  }

  Future<void> _importRoster() async {
    if (_importing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Import Roster', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Select a roster_export.json file to import.\n\nStudents and attendance records already on this device will be skipped.',
          style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Choose File')),
        ],
      ),
    );
    if (confirmed != true) return;
    FilePickerResult? pickerResult;
    try {
      pickerResult = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json'],
          allowMultiple: false, dialogTitle: 'Select roster_export.json');
    } catch (e) { if (mounted) _showError('Could not open file picker: $e'); return; }
    if (pickerResult == null || pickerResult.files.isEmpty) return;
    final pickedPath = pickerResult.files.single.path;
    if (pickedPath == null) { if (mounted) _showError('Could not read the selected file path.'); return; }
    setState(() => _importing = true);
    try {
      final result = await TransferService().importRoster(pickedPath);
      if (!mounted) return;
      final buffer = StringBuffer();
      buffer.writeln('── Students ──');
      buffer.writeln('${result.studentsImported} imported.');
      if (result.studentsSkipped > 0) { buffer.writeln('${result.studentsSkipped} skipped:'); for (final n in result.skippedStudentNames) buffer.writeln('  • $n'); }
      if (result.studentsFailed > 0)  { buffer.writeln('${result.studentsFailed} failed:');  for (final n in result.failedStudentNames)  buffer.writeln('  • $n'); }
      buffer.writeln('\n── Groups ──');
      buffer.writeln('${result.groupsImported} imported.');
      if (result.groupsSkipped > 0) buffer.writeln('${result.groupsSkipped} skipped.');
      if (result.groupsFailed  > 0) buffer.writeln('${result.groupsFailed} failed.');
      buffer.writeln('\n── Attendance ──');
      buffer.writeln('${result.attendanceImported} record(s) imported.');
      if (result.attendanceSkipped > 0) buffer.writeln('${result.attendanceSkipped} skipped.');
      if (result.attendanceFailed  > 0) buffer.writeln('${result.attendanceFailed} failed.');
      await showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Import Complete', style: TextStyle(color: AppColors.textPrimary)),
        content: SingleChildScrollView(child: Text(buffer.toString().trim(),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ));
    } catch (e) { if (mounted) _showError('Import failed: $e'); }
    finally { if (mounted) setState(() => _importing = false); }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Clear All Data?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('This will permanently delete all students and attendance records.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete Everything', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseService().resetAllData();
    appLog('[Settings] All data cleared by user');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All data cleared.'), duration: Duration(seconds: 2)));
  }

  Future<void> _launchStressTest() async =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const _StressTestScreen()));

  void _showError(String message) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Error', style: TextStyle(color: AppColors.textPrimary)),
      content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Settings'),
          const Text('Account · Data · Developer',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel('ACCOUNT'),
          const SizedBox(height: 8),
          _SettingsTile(icon: Icons.person_outline,   label: 'ACCOUNT NAME', value: _accountName.isEmpty ? 'Not set' : _accountName, onTap: _editName,
              trailing: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _SettingsTile(icon: Icons.business_outlined, label: 'ORGANIZATION', value: _orgId.isEmpty ? 'Not set' : _orgId, onTap: () {}),
          const SizedBox(height: 8),
          _SettingsTile(icon: Icons.badge_outlined,    label: 'ROLE',         value: _accountRole.isEmpty ? 'Not set' : _accountRole, onTap: () {}),
          const SizedBox(height: 8),
          _SettingsTile(icon: Icons.mail_outline,      label: 'CONTACT',      value: 'upadhyayaarush727@gmail.com', onTap: () {
            Clipboard.setData(const ClipboardData(text: 'upadhyayaarush727@gmail.com'));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Email copied'), duration: Duration(seconds: 1)));
          }, trailing: const Icon(Icons.copy_outlined, size: 16, color: AppColors.textMuted)),
          const SizedBox(height: 28),

          _sectionLabel('ROSTER TRANSFER'),
          const SizedBox(height: 8),
          _TransferTile(
            icon: Icons.upload_outlined,
            label: _exporting ? 'Exporting…' : 'Export Roster',
            sub: 'Save students + attendance history to a file',
            loading: _exporting,
            onTap: (_exporting || _importing) ? null : _exportRoster,
          ),
          const SizedBox(height: 8),
          _TransferTile(
            icon: Icons.download_outlined,
            label: _importing ? 'Importing…' : 'Import Roster',
            sub: 'Load students + attendance from an exported file',
            loading: _importing,
            onTap: (_exporting || _importing) ? null : _importRoster,
          ),
          const SizedBox(height: 28),

          _sectionLabel('DEVELOPER'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _launchStressTest,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accentTeal.withOpacity(0.4)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(children: [
                Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: AppColors.accentTeal.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.bolt, color: AppColors.accentTeal, size: 22)),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Stress Test', style: TextStyle(color: AppColors.accentTeal, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('9-stage · 1000-student environment simulation',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ])),
                const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 28),

          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: ListTile(
              leading: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.delete_forever_outlined, color: AppColors.danger, size: 20)),
              title: const Text('Clear All Data',
                  style: TextStyle(color: AppColors.danger, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Deletes all students & records',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              onTap: _clearAllData,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final String label, value; final VoidCallback onTap; final Widget? trailing;
  const _SettingsTile({required this.icon, required this.label, required this.value, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: AppColors.accent, size: 18)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
            ])),
            if (trailing != null) trailing!,
          ]),
        ),
      );
}

class _TransferTile extends StatelessWidget {
  final IconData icon; final String label, sub; final bool loading; final VoidCallback? onTap;
  const _TransferTile({required this.icon, required this.label, required this.sub, required this.loading, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(10)),
                child: loading
                    ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))
                    : Icon(icon, color: AppColors.accent, size: 20)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              Text(sub,   style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ])),
            if (!loading) const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ]),
        ),
      );
}

// ── Stress Test Screen ─────────────────────────────────────────

class _StressTestScreen extends StatefulWidget {
  const _StressTestScreen();
  @override
  State<_StressTestScreen> createState() => _StressTestScreenState();
}

class _StressTestScreenState extends State<_StressTestScreen> {
  final _svc        = StressTestService.instance;
  final _log        = <String>[];
  final _scrollCtrl = ScrollController();
  bool _running = false; int _currentStage = 0;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _svc.statusStream.listen((msg) {
      if (!mounted) return;
      setState(() => _log.add(msg));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });
    });
  }

  @override
  void dispose() { _sub?.cancel(); _scrollCtrl.dispose(); super.dispose(); }

  void _addLog(String msg) { appLog('[StressUI] $msg'); if (mounted) setState(() => _log.add(msg)); }

  Future<bool> _askPermission(String stageName) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Begin $stageName?', style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('Stage $_currentStage completed. Proceed to $stageName?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stop Here')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Run It')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _runAll() async {
    if (_running) return;
    setState(() { _running = true; _log.clear(); _currentStage = 0; });
    try {
      _currentStage = 1; _addLog('▶ Starting Stage 1 (1000 students)...');
      if (!await _svc.runStage1()) { _addLog('⛔ Stage 1 failed.'); return; }
      _addLog('✅ Stage 1 passed.');
      if (!await _askPermission('Stage 2 (Camera Abuse — 50 cycles)')) { _addLog('🛑 Stopped after Stage 1.'); return; }
      _currentStage = 2; _addLog('▶ Starting Stage 2...');
      if (!await _svc.runStage2(context)) { _addLog('⛔ Stage 2 failed.'); return; }
      _addLog('✅ Stage 2 passed.');
      if (!await _askPermission('Stage 3 (DB Corruption — 9 tests)')) { _addLog('🛑 Stopped after Stage 2.'); return; }
      _currentStage = 3; _addLog('▶ Starting Stage 3...');
      if (!await _svc.runStage3()) { _addLog('⛔ Stage 3 fatal — app killed.'); return; }
      _addLog('✅ Stage 3 passed.');
      if (!await _askPermission('Stage 4 (Memory Pressure — 1000×1000 × 3 passes)')) { _addLog('🛑 Stopped after Stage 3.'); return; }
      _currentStage = 4; _addLog('▶ Starting Stage 4...');
      if (!await _svc.runStage4()) { _addLog('⛔ Stage 4 failed.'); return; }
      _addLog('✅ Stage 4 passed.');
      if (!await _askPermission('Stage 5 (Attendance Storm — 200 sessions × 1000)')) { _addLog('🛑 Stopped after Stage 4.'); return; }
      _currentStage = 5; _addLog('▶ Starting Stage 5...');
      if (!await _svc.runStage5()) { _addLog('⛔ Stage 5 failed.'); return; }
      _addLog('✅ Stage 5 passed.');
      if (!await _askPermission('Stage 6 (Concurrent Writes — 25 chains × 100)')) { _addLog('🛑 Stopped after Stage 5.'); return; }
      _currentStage = 6; _addLog('▶ Starting Stage 6...');
      final s6ok = await _svc.runStage6();
      _addLog(s6ok ? '✅ Stage 6 passed.' : '⚠️ Stage 6 partial failure.');
      if (!await _askPermission('Stage 7 (Read Storm — 500 concurrent reads)')) { _addLog('🛑 Stopped after Stage 6.'); return; }
      _currentStage = 7; _addLog('▶ Starting Stage 7...');
      if (!await _svc.runStage7()) { _addLog('⛔ Stage 7 failed.'); return; }
      _addLog('✅ Stage 7 passed.');
      if (!await _askPermission('Stage 8 (Embedding GC Churn — 500 iterations)')) { _addLog('🛑 Stopped after Stage 7.'); return; }
      _currentStage = 8; _addLog('▶ Starting Stage 8...');
      if (!await _svc.runStage8()) { _addLog('⛔ Stage 8 failed.'); return; }
      _addLog('✅ Stage 8 passed.');
      if (!await _askPermission('Stage 9 (Export/Import Round-Trip Integrity)')) { _addLog('🛑 Stopped after Stage 8.'); return; }
      _currentStage = 9; _addLog('▶ Starting Stage 9...');
      final s9ok = await _svc.runStage9();
      _addLog(s9ok ? '✅ Stage 9 passed.' : '⚠️ Stage 9 integrity mismatch.');
      _addLog(''); _addLog('🎉 ALL 9 STAGES COMPLETE — stress test finished.');
    } catch (e, st) {
      appLog('[StressTest] TOP-LEVEL CRASH: $e\n$st');
      _addLog('💥 TOP-LEVEL CRASH: $e');
    } finally {
      if (mounted) setState(() { _running = false; _currentStage = 0; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_running ? 'Stress Test — Stage $_currentStage Running…' : 'Stress Test  (9 stages)'),
        actions: [
          if (!_running && _log.isNotEmpty)
            IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy log', onPressed: () {
              Clipboard.setData(ClipboardData(text: _log.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Log copied'), duration: Duration(seconds: 1)));
            }),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(9, (i) {
            final stage = i + 1;
            return _StagePill(stage: stage, active: _currentStage == stage, done: _currentStage > stage);
          })),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: _log.isEmpty
                ? const Center(child: Text('Press Start to begin stress test.',
                    style: TextStyle(color: Colors.white38, fontSize: 13)))
                : ListView.builder(
                    controller: _scrollCtrl, padding: const EdgeInsets.all(10), itemCount: _log.length,
                    itemBuilder: (_, i) {
                      final line = _log[i];
                      final isErr  = line.contains('❌') || line.contains('💥') || line.contains('CRASH') || line.contains('FAIL');
                      final isOk   = line.contains('✅') || line.contains('🎉');
                      final isWarn = line.contains('⚠️') || line.contains('🛑') || line.contains('⏰');
                      final color  = isErr ? AppColors.danger : isOk ? AppColors.present : isWarn ? const Color(0xFFF59E0B) : Colors.white38;
                      return Padding(padding: const EdgeInsets.only(bottom: 2),
                          child: Text(line, style: TextStyle(color: color, fontSize: 10.5, fontFamily: 'monospace')));
                    }),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: ElevatedButton.icon(
            onPressed: _running ? null : _runAll,
            style: ElevatedButton.styleFrom(
                backgroundColor: _running ? AppColors.accentDim : AppColors.accentTeal,
                foregroundColor: Colors.white),
            icon: _running
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                : const Icon(Icons.bolt),
            label: Text(_running ? 'Running Stage $_currentStage…' : 'Start Stress Test'),
          ),
        ),
      ]),
    );
  }
}

class _StagePill extends StatelessWidget {
  final int stage; final bool active, done;
  const _StagePill({required this.stage, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.accentTeal : done ? AppColors.present : AppColors.accentDim;
    final fg = (active || done) ? Colors.white : AppColors.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(20),
        boxShadow: active ? [BoxShadow(color: AppColors.accentTeal.withOpacity(0.4), blurRadius: 8)] : null,
      ),
      child: Text('S$stage', style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}