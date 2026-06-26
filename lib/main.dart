// lib/main.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';
import 'services/app_log.dart';
import 'services/beacon_service.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLog.instance.initFile();
  appLog('App started');

  // ── Flutter framework error hook ──────────────────────────
  // Catches widget build errors, assertion failures, etc.
  // These are the red "Exception" banners you see on screen.
  FlutterError.onError = (FlutterErrorDetails details) {
    // Let Flutter handle printing to console as usual
    FlutterError.presentError(details);
    // Also funnel into our log so it gets flushed to Firestore
    appLog('[FlutterError] ${details.exceptionAsString()}');
    final stack = details.stack?.toString() ?? '';
    if (stack.isNotEmpty) {
      // Only first 3 lines of stack to keep it readable
      final brief = stack.split('\n').take(3).join(' | ');
      appLog('[FlutterError] stack: $brief');
    }
  };

  // ── Platform/isolate error hook ───────────────────────────
  // Catches async errors not caught by FlutterError, e.g. "Bad state",
  // unhandled Future exceptions, platform channel errors.
  PlatformDispatcher.instance.onError = (error, stack) {
    appLog('[PlatformError] $error');
    final brief = stack.toString().split('\n').take(3).join(' | ');
    appLog('[PlatformError] stack: $brief');
    return true; // return true = we handled it, don't also crash
  };

  try {
    await Firebase.initializeApp();
    appLog('[Firebase] initialized ✅');
  } catch (e) {
    appLog('[Firebase] init failed (non-fatal): $e');
  }

  // Ping on launch (non-blocking)
  appLog('[Main] firing BeaconService.ping()...');
  BeaconService.ping();
  appLog('[Main] BeaconService.ping() fired (non-blocking)');

  // Start periodic log sync — only flushes when new lines exist
  appLog('[Main] starting log sync...');
  BeaconService.startLogSync();
  appLog('[Main] log sync started ✅');

  // Start kill switch listener — real-time Firestore snapshot
  // This must be awaited so the listener is attached before the UI renders,
  // ensuring the kill screen shows immediately if already killed at launch.
  appLog('[Main] starting kill switch listener...');
  await BeaconService.startKillSwitch();
  appLog('[Main] kill switch listener started ✅');

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final prefs     = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool('onboarded') ?? false;
  appLog('[Main] onboarded=$onboarded');

  appLog('[Main] calling runApp...');
  runApp(FaceAttendanceApp(onboarded: onboarded));
  appLog('[Main] runApp called ✅');
}

class FaceAttendanceApp extends StatefulWidget {
  final bool onboarded;
  const FaceAttendanceApp({super.key, required this.onboarded});

  @override
  State<FaceAttendanceApp> createState() => _FaceAttendanceAppState();
}

class _FaceAttendanceAppState extends State<FaceAttendanceApp> {
  late bool _onboarded;

  @override
  void initState() {
    super.initState();
    _onboarded = widget.onboarded;
    appLog('[FaceAttendanceApp] initState() — _onboarded=$_onboarded');
  }

  @override
  Widget build(BuildContext context) {
    appLog('[FaceAttendanceApp] build() called');
    return MaterialApp(
      title: 'Face Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: ValueListenableBuilder<bool>(
        valueListenable: BeaconService.appAlive,
        builder: (context, alive, _) {
          appLog('[KillSwitch] ValueListenableBuilder fired — alive=$alive');

          if (!alive) {
            appLog('[KillSwitch] 🔴 rendering kill screen');
            appLog('[KillSwitch] kill message: "${BeaconService.killMessage}"');
            return Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.block,
                          size: 64,
                          color: AppColors.danger,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Access Revoked',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          BeaconService.killMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          appLog('[KillSwitch] ✅ rendering normal app — onboarded=$_onboarded');
          return _onboarded
              ? const MainShell()
              : OnboardingScreen(
                  onDone: () {
                    appLog('[FaceAttendanceApp] onboarding done — switching to MainShell');
                    setState(() => _onboarded = true);
                  },
                );
        },
      ),
    );
  }
}