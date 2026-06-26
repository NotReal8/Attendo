// lib/screens/records_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_colors.dart';
import '../models/attendance_record.dart';
import '../services/attendance_service.dart';
import '../services/database_service.dart';
import '../services/app_log.dart';

// ═══════════════════════════════════════════════════════════════
// RecordsScreen — Year list (root)
// ═══════════════════════════════════════════════════════════════

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final DatabaseService _db = DatabaseService();
  List<String> _years = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dates = await _db.distinctDates();
    final years = dates.map((d) => d.substring(0, 4)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (!mounted) return;
    setState(() { _years = years; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Attendance Records'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _years.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _years.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _FolderTile(
                    icon: Icons.calendar_today_outlined,
                    label: _years[i],
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => _MonthScreen(year: _years[i]))),
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _MonthScreen
// ═══════════════════════════════════════════════════════════════

class _MonthScreen extends StatefulWidget {
  final String year;
  const _MonthScreen({required this.year});
  @override
  State<_MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<_MonthScreen> {
  final DatabaseService _db = DatabaseService();
  List<String> _months = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dates = await _db.distinctDates();
    final months = dates
        .where((d) => d.startsWith(widget.year))
        .map((d) => d.substring(0, 7))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (!mounted) return;
    setState(() { _months = months; _loading = false; });
  }

  String _monthLabel(String ym) {
    try {
      return DateFormat('MMMM yyyy').format(DateTime.parse('$ym-01'));
    } catch (_) { return ym; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.year),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _months.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _FolderTile(
                icon: Icons.calendar_month_outlined,
                label: _monthLabel(_months[i]),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => _DayScreen(yearMonth: _months[i]))),
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _DayScreen
// ═══════════════════════════════════════════════════════════════

class _DayScreen extends StatefulWidget {
  final String yearMonth; // "yyyy-MM"
  const _DayScreen({required this.yearMonth});
  @override
  State<_DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<_DayScreen> {
  final DatabaseService _db = DatabaseService();
  List<String> _days = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dates = await _db.distinctDates();
    final days = dates
        .where((d) => d.startsWith(widget.yearMonth))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (!mounted) return;
    setState(() { _days = days; _loading = false; });
  }

  String _dayLabel(String iso) {
    try { return DateFormat('EEE, MMM d yyyy').format(DateTime.parse(iso)); }
    catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    final title = DateFormat('MMMM yyyy')
        .format(DateTime.parse('${widget.yearMonth}-01'));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _days.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _FolderTile(
                icon: Icons.today_outlined,
                label: _dayLabel(_days[i]),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => _SessionScreen(date: _days[i]))),
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _SessionScreen — lists sessions for a date; multi-select export & delete
// ═══════════════════════════════════════════════════════════════

class _SessionScreen extends StatefulWidget {
  final String date;
  const _SessionScreen({required this.date});
  @override
  State<_SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<_SessionScreen> {
  final DatabaseService   _db      = DatabaseService();
  final AttendanceService _service = AttendanceService();

  List<String>    _labels   = [];
  Set<String>     _selected = {};
  bool _loading   = false;
  bool _exporting = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _selected.clear(); });
    final labels = await _db.distinctLabelsForDate(widget.date);
    if (!mounted) return;
    setState(() { _labels = labels; _loading = false; });
  }

  Future<void> _delete(String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete session?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete "$label" on ${_fmtDate(widget.date)}?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteSession(widget.date, label);
    await _load();
  }

  Future<void> _exportSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final sessions = _selected
          .map((label) => (date: widget.date, label: label))
          .toList();
      final file = await _service.exportToExcel(sessions);
      await Share.shareXFiles([XFile(file.path)], subject: 'Attendance Report');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _fmtDate(String iso) {
    try { return DateFormat('EEE, MMM d yyyy').format(DateTime.parse(iso)); }
    catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    final anySelected = _selected.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_fmtDate(widget.date)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          if (anySelected)
            _exporting
                ? const Padding(padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))
                : IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: 'Export selected',
                    onPressed: _exportSelected,
                  ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _labels.isEmpty
              ? const Center(child: Text('No sessions found.',
                  style: TextStyle(color: AppColors.textSecondary)))
              : Column(
                  children: [
                    if (_labels.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Row(children: [
                          TextButton(
                            onPressed: () => setState(() {
                              if (_selected.length == _labels.length) {
                                _selected.clear();
                              } else {
                                _selected = Set.from(_labels);
                              }
                            }),
                            child: Text(
                              _selected.length == _labels.length ? 'Deselect All' : 'Select All',
                            ),
                          ),
                          if (anySelected)
                            Text('${_selected.length} selected for export',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ]),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _labels.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final label = _labels[i];
                          final checked = _selected.contains(label);
                          return _SessionTile(
                            label: label,
                            checked: checked,
                            onCheckChanged: (v) => setState(() {
                              if (v == true) _selected.add(label); else _selected.remove(label);
                            }),
                            onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => _StudentsScreen(
                                date: widget.date, label: label))),
                            onDelete: () => _delete(label),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool?> onCheckChanged;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _SessionTile({
    required this.label, required this.checked,
    required this.onCheckChanged, required this.onTap, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: checked ? AppColors.accent.withOpacity(0.5) : AppColors.cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Checkbox(
          value: checked,
          activeColor: AppColors.accent,
          onChanged: onCheckChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 8),
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.access_time_rounded, color: AppColors.accent, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600))),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// _StudentsScreen — student list with multi-select status edit
// ═══════════════════════════════════════════════════════════════

class _StudentsScreen extends StatefulWidget {
  final String date;
  final String label;
  const _StudentsScreen({required this.date, required this.label});
  @override
  State<_StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<_StudentsScreen> {
  final DatabaseService   _db      = DatabaseService();
  final AttendanceService _service = AttendanceService();

  List<AttendanceRecord> _records   = [];
  Set<int>               _selected  = {};
  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _selected.clear(); });
    final records = await _db.recordsForDateAndLabel(widget.date, widget.label);
    if (!mounted) return;
    setState(() { _records = records; _loading = false; });
  }

  Future<void> _saveChanges(String newStatus) async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      final prefs    = await SharedPreferences.getInstance();
      final acctName = prefs.getString('account_name') ?? 'Unknown';
      final orgId    = prefs.getString('org_id')       ?? '';

      for (final idx in _selected) {
        final r = _records[idx];
        if (r.id == null) continue;
        await _db.updateRecordStatus(r.id!, newStatus);
        appLog('[Records] ${r.studentName} → $newStatus by $acctName');
        await _service.syncStatusUpdate(
          orgId: orgId, date: r.sessionDate, label: r.sessionLabel,
          studentName: r.studentName, newStatus: newStatus, accountName: acctName,
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _domainName =>
      _records.isNotEmpty ? _records.first.groupName : '';

  @override
  Widget build(BuildContext context) {
    final anySelected = _selected.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label),
          if (_domainName.isNotEmpty)
            Text(_domainName,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(children: [
              // Select all row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  TextButton(
                    onPressed: () => setState(() {
                      if (_selected.length == _records.length) {
                        _selected.clear();
                      } else {
                        _selected = Set.from(Iterable.generate(_records.length));
                      }
                    }),
                    child: Text(_selected.length == _records.length
                        ? 'Deselect All' : 'Select All'),
                  ),
                  if (anySelected)
                    Text('${_selected.length} selected',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ]),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: _records.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.cardBorder),
                    itemBuilder: (_, i) {
                      final r = _records[i];
                      final checked = _selected.contains(i);
                      return Container(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Row(
    children: [

      Checkbox(
        value: checked,
        activeColor: AppColors.accent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (v) => setState(() {
          if (v == true) {
            _selected.add(i);
          } else {
            _selected.remove(i);
          }
        }),
      ),

      const SizedBox(width: 8),

      Expanded(
        child: Text(
          r.studentName,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
          ),
        ),
      ),

      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: (r.isPresent
                  ? AppColors.present
                  : AppColors.textMuted)
              .withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          r.isPresent ? 'Present' : 'Absent',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: r.isPresent
                ? AppColors.present
                : AppColors.textSecondary,
          ),
        ),
      ),

      const SizedBox(width: 8),
    ],
  ),
);
                    },
                  ),
                ),
              ),
              // Bottom action bar
              if (anySelected)
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: const Border(top: BorderSide(color: AppColors.cardBorder)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                          blurRadius: 8, offset: const Offset(0, -2))],
                    ),
                    child: _saving
                        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                        : Row(children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  side: const BorderSide(color: AppColors.danger),
                                  minimumSize: const Size(0, 44),
                                ),
                                onPressed: () => _saveChanges('absent'),
                                child: const Text('Mark Absent'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.present,
                                  minimumSize: const Size(0, 44),
                                ),
                                onPressed: () => _saveChanges('present'),
                                child: const Text('Mark Present'),
                              ),
                            ),
                          ]),
                  ),
                ),
            ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Shared widgets
// ═══════════════════════════════════════════════════════════════

class _FolderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _FolderTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14,
                fontWeight: FontWeight.w600))),
        const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
      ]),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80,
          decoration: BoxDecoration(color: AppColors.accentDim, shape: BoxShape.circle),
          child: const Icon(Icons.event_note_outlined, size: 40, color: AppColors.accent)),
      const SizedBox(height: 16),
      const Text('No records yet',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      const SizedBox(height: 6),
      const Text('Take attendance to see history here.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
    ]),
  );
}