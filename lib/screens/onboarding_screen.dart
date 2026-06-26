// lib/screens/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_colors.dart';
import '../services/beacon_service.dart';
import '../services/restore_service.dart';
import 'restore_progress_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _orgCtrl  = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _role = 'Teacher';
  bool _saving = false, _obscure = true;
  String? _error;

  // ── Restore-on-login state ────────────────────────────────
  bool   _restoring      = false;
  bool   _restoreFailed  = false;
  String? _restoreError;
  String _restoreStage   = 'Connecting…';
  int    _restoreDone    = 0;
  int    _restoreTotal   = 0;

  Future<void> _save() async {
    final org  = _orgCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (org.isEmpty || name.isEmpty || pass.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });

    Map<String, dynamic>? existing;
    try {
      existing = await RestoreService().fetchAccount(org, name);
    } catch (e) {
      setState(() { _saving = false; _error = 'Could not reach server: $e'; });
      return;
    }

    if (existing != null) {
      final storedPass = existing['account_pass'] as String? ?? '';
      final storedRole = existing['role'] as String? ?? '';
      if (storedPass != pass || storedRole != _role) {
        setState(() {
          _saving = false;
          _error  = 'Account exists but password or role does not match.';
        });
        return;
      }
      setState(() { _saving = false; _restoring = true; });
      _runRestore(org, name, pass, _role);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('org_id',       org);
    await prefs.setString('account_name', name);
    await prefs.setString('account_pass', pass);
    await prefs.setString('account_role', _role);
    await prefs.setBool('onboarded', true);
    BeaconService.ping();
    widget.onDone();
  }

  Future<void> _runRestore(String org, String name, String pass, String role) async {
    setState(() {
      _restoreFailed = false;
      _restoreError  = null;
      _restoreStage  = 'Connecting…';
      _restoreDone   = 0;
      _restoreTotal  = 0;
    });
    try {
      await RestoreService().restoreAll(
        orgId: org,
        accountName: name,
        onProgress: (stage, done, total) {
          if (!mounted) return;
          setState(() { _restoreStage = stage; _restoreDone = done; _restoreTotal = total; });
        },
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('org_id',       org);
      await prefs.setString('account_name', name);
      await prefs.setString('account_pass', pass);
      await prefs.setString('account_role', role);
      await prefs.setBool('onboarded', true);
      BeaconService.ping();
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) setState(() { _restoreFailed = true; _restoreError = '$e'; });
    }
  }

  @override
  void dispose() { _orgCtrl.dispose(); _nameCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return RestoreProgressScreen(
        stage:  _restoreStage,
        done:   _restoreDone,
        total:  _restoreTotal,
        failed: _restoreFailed,
        error:  _restoreError,
        onBack: () => setState(() => _restoring = false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 40),
            Container(
              width: 72, height: 72,
              margin: const EdgeInsets.only(bottom: 24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.heroGradientStart, AppColors.heroGradientEnd],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.face_retouching_natural, size: 38, color: Colors.white),
            ),
            const Text('Welcome', textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Set up your account to get started.', textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            const SizedBox(height: 40),
            TextField(controller: _orgCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Organization ID',
                    hintText: 'e.g. SpringfieldHS or 1234567',
                    prefixIcon: Icon(Icons.business_outlined))),
            const SizedBox(height: 6),
            const Text('Ask your HR/admin for the Organization ID.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(height: 20),
            TextField(controller: _nameCtrl, textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Username',
                    hintText: 'e.g. Mr. Smith', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 20),
            TextField(controller: _passCtrl, obscureText: _obscure,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textMuted, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                )),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _role, dropdownColor: AppColors.card,
              decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.badge_outlined)),
              items: const [
                DropdownMenuItem(value: 'Teacher', child: Text('Teacher',    style: TextStyle(color: AppColors.textPrimary))),
                DropdownMenuItem(value: 'HR',      child: Text('HR / Admin', style: TextStyle(color: AppColors.textPrimary))),
              ],
              onChanged: (v) { if (v != null) setState(() => _role = v); },
            ),
            const SizedBox(height: 8),
            const Text(
              'Already have an account? Enter the same Organization ID, Username, Password and Role to restore your data.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 32),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Get Started'),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}