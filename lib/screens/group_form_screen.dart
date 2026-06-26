// lib/screens/group_form_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_colors.dart';
import '../models/group.dart';
import '../models/student.dart';
import '../services/app_log.dart';
import '../services/database_service.dart';

class GroupFormScreen extends StatefulWidget {
  final StudentGroup? existingGroup;
  const GroupFormScreen({super.key, this.existingGroup});

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Student> _allStudents = [];
  final Set<String> _selected = {};
  String _query = '';
  bool _loading = true;
  bool _saving  = false;
  String? _error;

  bool get _editing => widget.existingGroup != null;

  @override
  void initState() {
    super.initState();
    if (_editing) _nameCtrl.text = widget.existingGroup!.name;
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final students = await _db.getAllStudents();
    Set<String> selected = {};
    if (_editing && widget.existingGroup!.id != null) {
      selected = (await _db.getGroupMemberNames(widget.existingGroup!.id!)).toSet();
    }
    if (!mounted) return;
    setState(() {
      _allStudents = students;
      _selected
        ..clear()
        ..addAll(selected);
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter a group name.'); return; }
    if (_selected.isEmpty) { setState(() => _error = 'Select at least 1 student.'); return; }

    setState(() { _saving = true; _error = null; });
    try {
      final exists = await _db.groupNameExists(name, excludeId: widget.existingGroup?.id);
      if (exists) {
        setState(() => _error = 'A group with this name already exists.');
        return;
      }

      int groupId;
      if (_editing && widget.existingGroup!.id != null) {
        groupId = widget.existingGroup!.id!;
        await _db.renameGroup(groupId, name);
      } else {
        groupId = await _db.createGroup(name);
      }
      await _db.setGroupMembers(groupId, _selected);
      appLog('[Groups] Saved "$name" with ${_selected.length} member(s)');

      // Sync to Firestore
      try {
        final prefs    = await SharedPreferences.getInstance();
        final orgId    = prefs.getString('org_id')       ?? '';
        final acctName = prefs.getString('account_name') ?? '';
        if (orgId.isNotEmpty && acctName.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('orgs').doc(orgId)
              .collection('accounts').doc(acctName)
              .collection('groups').doc(name)
              .set({
            'name':       name,
            'members':    _selected.toList(),
            'synced_at':  FieldValue.serverTimestamp(),
          });
          appLog('[Groups] Firestore sync done ✅');
        }
      } catch (e) {
        appLog('[Groups] Firestore sync failed (non-fatal): $e');
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      appLog('[Groups] Save failed: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existingGroup?.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete group?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('This removes "${widget.existingGroup!.name}". Students and past attendance records are kept.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteGroup(id);
    appLog('[Groups] Deleted "${widget.existingGroup!.name}"');

    // Sync delete to Firestore
    try {
      final prefs    = await SharedPreferences.getInstance();
      final orgId    = prefs.getString('org_id')       ?? '';
      final acctName = prefs.getString('account_name') ?? '';
      if (orgId.isNotEmpty && acctName.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('orgs').doc(orgId)
            .collection('accounts').doc(acctName)
            .collection('groups').doc(widget.existingGroup!.name)
            .delete();
        appLog('[Groups] Firestore delete done ✅');
      }
    } catch (e) {
      appLog('[Groups] Firestore delete failed (non-fatal): $e');
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _allStudents
        : _allStudents.where((s) => s.name.toLowerCase().contains(_query)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_editing ? 'Edit Group' : 'Create Group'),
        actions: [
          if (_editing)
            IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.danger), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      hintText: 'e.g. Grade 10 - Section A',
                      prefixIcon: Icon(Icons.folder_shared_outlined),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    Expanded(
                      child: Text('Members (${_selected.length} selected)',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                    TextButton(
                      onPressed: filtered.isEmpty ? null : () => setState(() {
                        final allSelected = filtered.every((s) => _selected.contains(s.name));
                        if (allSelected) {
                          for (final s in filtered) _selected.remove(s.name);
                        } else {
                          for (final s in filtered) _selected.add(s.name);
                        }
                      }),
                      child: const Text('Select / Clear all'),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                Expanded(
                  child: _allStudents.isEmpty
                      ? const Center(child: Text('No students registered yet.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final checked = _selected.contains(s.name);
                            return CheckboxListTile(
                              dense: true,
                              value: checked,
                              activeColor: AppColors.accent,
                              title: Text(s.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                              subtitle: Text('${s.sampleCount} sample(s)',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              onChanged: (v) => setState(() {
                                if (v == true) _selected.add(s.name); else _selected.remove(s.name);
                              }),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check),
                    label: Text(_saving ? 'Saving…' : (_editing ? 'Save Changes' : 'Create Group')),
                  ),
                ),
              ],
            ),
    );
  }
}