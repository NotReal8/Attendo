// lib/screens/restore_progress_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class RestoreProgressScreen extends StatelessWidget {
  final String  stage;
  final int     done;
  final int     total;
  final bool    failed;
  final String? error;
  final VoidCallback onBack;

  const RestoreProgressScreen({
    super.key,
    required this.stage,
    required this.done,
    required this.total,
    required this.failed,
    required this.error,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? done / total : null;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: failed ? AppColors.danger.withOpacity(0.12) : AppColors.accentDim,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    failed ? Icons.cloud_off_outlined : Icons.cloud_download_outlined,
                    size: 36,
                    color: failed ? AppColors.danger : AppColors.accent,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  failed ? 'Restore Failed' : 'Restoring Your Account',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  failed ? (error ?? 'Something went wrong.') : stage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (!failed)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 220,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: AppColors.accentDim,
                        valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    ),
                  ),
                if (!failed && total > 0) ...[
                  const SizedBox(height: 8),
                  Text('$done / $total',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
                if (failed) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No data was kept on this device. Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 200,
                    child: ElevatedButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}