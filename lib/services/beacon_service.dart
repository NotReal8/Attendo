// lib/services/beacon_service.dart
//
// All Firebase/Firestore logic lives here.
//
// Responsibilities:
//   1. ping()          — called on launch / name change. Writes to users/ + pings/
//   2. startLogSync()  — starts a periodic timer that flushes new logs to Firestore
//                        ONLY when new lines have actually been added since the last flush.
//   3. flushLogs()     — can be called manually; sends pending log lines to Firestore.
//   4. startKillSwitch() — attaches a real-time Firestore listener to config/kill_switch.
//                          Flips appAlive notifier which the UI reacts to immediately.
//   5. stopKillSwitch()  — cancels the listener cleanly.
//
// Firestore layout:
//   users/<deviceId>                    — one doc per device, updated every ping
//     account_name, last_seen, device_model, device_brand, device_id
//
//   pings/<auto-id>                     — one doc per app launch
//     account_name, timestamp, device_*, android_version, sdk_int, ...
//
//   logs/<deviceId>/sessions/<auto-id>  — batched log chunks
//     account_name, device_id, flushed_at, line_count, lines: [...]
//
//   config/kill_switch                  — remote kill switch document
//     active: bool                      — false = kill everyone
//     message: string                   — shown on kill screen
//     killed_devices: []                — list of device IDs to kill individually
//     killed_accounts: []               — list of account names to kill individually

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_log.dart';

class BeaconService {
  BeaconService._();

  // ── Internal state ────────────────────────────────────────

  static Timer?  _logTimer;
  static String? _cachedDeviceId;
  static int     _lastFlushedIndex = 0; // how many log lines already sent

  static const int _logIntervalSeconds = 15;

  // ── Kill switch state ─────────────────────────────────────

  static StreamSubscription<DocumentSnapshot>? _killSwitchSub;

  /// true  = app is permitted to run normally
  /// false = app is killed, UI shows block screen
  static final ValueNotifier<bool> appAlive = ValueNotifier(true);

  /// Message shown on the block screen when app is killed
  static String killMessage = 'This app has been disabled by the administrator.';

  // ── Device ID ─────────────────────────────────────────────

  static Future<String> _deviceId() async {
    if (_cachedDeviceId != null) {
      appLog('[Beacon] _deviceId() — returning cached: $_cachedDeviceId');
      return _cachedDeviceId!;
    }

    appLog('[Beacon] _deviceId() — fetching from DeviceInfoPlugin...');

    final info    = DeviceInfoPlugin();
    final android = await info.androidInfo;

    _cachedDeviceId = android.id.isNotEmpty
        ? android.id
        : '${android.brand}_${android.model}'.replaceAll(' ', '_');

    appLog('[Beacon] _deviceId() — resolved: $_cachedDeviceId');

    return _cachedDeviceId!;
  }

  // ── Ping ──────────────────────────────────────────────────
  // Called on launch and whenever the account name changes.

  static Future<void> ping() async {
    try {
      appLog('[Beacon] ping() started');

      final info        = DeviceInfoPlugin();
      final android     = await info.androidInfo;
      final prefs       = await SharedPreferences.getInstance();

      final accountName = prefs.getString('account_name') ?? 'Unknown';
      final accountPass = prefs.getString('account_pass') ?? '';
      final accountRole = prefs.getString('account_role') ?? 'Teacher';
      final orgId       = prefs.getString('org_id') ?? '';

      final deviceId    = await _deviceId();

      // Save device_id to prefs so AttendanceService can read it
      await prefs.setString('device_id', deviceId);

      final now         = FieldValue.serverTimestamp();

      appLog(
        '[Beacon] ping() — '
        'account="$accountName" '
        'role="$accountRole" '
        'org="$orgId" '
        'deviceId="$deviceId"'
      );

      final pingData = {
        'account_name':    accountName,
        'account_role':    accountRole,
        'org_id':          orgId,
        'timestamp':       now,
        'device_id':       deviceId,
        'device_model':    android.model,
        'device_brand':    android.brand,
        'android_version': android.version.release,
        'sdk_int':         android.version.sdkInt,
        'manufacturer':    android.manufacturer,
        'package':         'com.yourapp.faceattendance',
        'app_version':     '1.0.0',
      };

      final db = FirebaseFirestore.instance;

      // Keep pings and users unchanged (left as-is per instructions)
      await db.collection('pings').add(pingData);
      appLog('[Beacon] ping() — pings/ write done ✅');

      await db.collection('users').doc(deviceId).set({
        'account_name': accountName,
        'account_role': accountRole,
        'org_id':       orgId,
        'last_seen':    now,
        'device_model': android.model,
        'device_brand': android.brand,
        'device_id':    deviceId,
      }, SetOptions(merge: true));
      appLog('[Beacon] ping() — users/ upsert done ✅');

      // ── New structured path: orgs/{orgId}/accounts/{accountName} ──
      if (orgId.isNotEmpty && accountName != 'Unknown') {
        await db
            .collection('orgs').doc(orgId)
            .collection('accounts').doc(accountName)
            .set({
          'account_name':    accountName,
          'account_pass':    accountPass,
          'role':            accountRole,
          'device_id':       deviceId,
          'device_model':    android.model,
          'device_brand':    android.brand,
          'android_version': android.version.release,
          'last_seen':       now,
        }, SetOptions(merge: true));
        appLog('[Beacon] ping() — orgs/$orgId/accounts/$accountName upserted ✅');
      }

      appLog(
        '[Beacon] ping() sent ✅ '
        'account="$accountName" '
        'org="$orgId"'
      );

    } catch (e) {

      appLog('[Beacon] ping() failed (non-fatal): $e');
    }
  }

  // ── Log sync ──────────────────────────────────────────────
  // Starts a repeating timer. On each tick:
  //   - Checks if new log lines exist since last flush
  //   - If yes → writes them to Firestore under logs/<deviceId>/sessions/
  //   - If no  → skips silently (no network call, no cost)

  static void startLogSync() {

    if (_logTimer != null) {
      appLog('[Beacon] startLogSync() — already running, skipping');
      return;
    }

    appLog(
      '[Beacon] startLogSync() — '
      'interval=${_logIntervalSeconds}s'
    );

    _logTimer = Timer.periodic(
      Duration(seconds: _logIntervalSeconds),
      (_) => flushLogs(),
    );

    appLog('[Beacon] startLogSync() — timer started ✅');
  }

  static void stopLogSync() {

    appLog('[Beacon] stopLogSync() called');

    _logTimer?.cancel();
    _logTimer = null;

    appLog('[Beacon] stopLogSync() — timer cancelled ✅');
  }

  // ── Flush logs ────────────────────────────────────────────
  // Sends only new lines (since last flush) to Firestore.
  // If nothing new → returns immediately without any network call.

  static Future<void> flushLogs() async {

    try {

      final allEntries = AppLog.instance.entries;

      // Nothing new since last flush — skip entirely, no write
      if (allEntries.length <= _lastFlushedIndex) return;

      final newLines =
          allEntries.sublist(_lastFlushedIndex).toList();

      // Sanity cap: never send more than 200 lines per flush
      final toSend = newLines.length > 200
          ? newLines.sublist(newLines.length - 200)
          : newLines;

      final prefs       = await SharedPreferences.getInstance();
      final accountName = prefs.getString('account_name') ?? 'Unknown';
      final orgId       = prefs.getString('org_id')       ?? '';
      final deviceId    = await _deviceId();

      // Date key for log grouping: yyyy-MM-dd
      final dateKey = DateTime.now().toIso8601String().substring(0, 10);

      if (orgId.isNotEmpty && accountName != 'Unknown') {
        // New path: orgs/{orgId}/accounts/{accountName}/logs/{date}/{auto-id}
        await FirebaseFirestore.instance
            .collection('orgs').doc(orgId)
            .collection('accounts').doc(accountName)
            .collection('logs').doc(dateKey)
            .collection('entries')
            .add({
          'device_id':  deviceId,
          'flushed_at': FieldValue.serverTimestamp(),
          'line_count': toSend.length,
          'lines':      toSend,
        });
      } else {
        // Fallback to old path if account not set yet
        await FirebaseFirestore.instance
            .collection('logs')
            .doc(deviceId)
            .collection('sessions')
            .add({
          'account_name': accountName,
          'device_id':    deviceId,
          'flushed_at':   FieldValue.serverTimestamp(),
          'line_count':   toSend.length,
          'lines':        toSend,
        });
      }

      _lastFlushedIndex = allEntries.length;

      // ignore: avoid_print
      print(
        '[Beacon] flushLogs() '
        'sent ${toSend.length} line(s) to Firestore ✅'
      );

    } catch (e) {

      // ignore: avoid_print
      print('[Beacon] flushLogs() failed (non-fatal): $e');
    }
  }

  // ── Kill switch ───────────────────────────────────────────

  static Future<void> startKillSwitch() async {

    appLog('[KillSwitch] startKillSwitch() called');

    if (_killSwitchSub != null) {
      appLog(
        '[KillSwitch] already running — '
        'skipping duplicate attach'
      );
      return;
    }

    appLog(
      '[KillSwitch] resolving device ID '
      'and account name...'
    );

    final deviceId    = await _deviceId();
    final prefs       = await SharedPreferences.getInstance();
    final accountName = prefs.getString('account_name') ?? 'Unknown';

    appLog(
      '[KillSwitch] this device="$deviceId" '
      'account="$accountName"'
    );

    appLog(
      '[KillSwitch] attaching snapshot listener '
      'to config/kill_switch...'
    );

    _killSwitchSub = FirebaseFirestore.instance
        .collection('config')
        .doc('kill_switch')
        .snapshots()
        .listen(

      (snapshot) {

        appLog('[KillSwitch] ── snapshot received ──');
        appLog('[KillSwitch] snapshot.exists=${snapshot.exists}');

        if (!snapshot.exists) {

          appLog(
            '[KillSwitch] document does not exist '
            '— treating as alive ✅'
          );

          appAlive.value = true;
          return;
        }

        final data =
            snapshot.data() as Map<String, dynamic>;

        appLog('[KillSwitch] raw document data: $data');

        final bool globalActive =
            data['active'] as bool? ?? true;

        final String message =
            data['message'] as String?
            ?? 'This app has been disabled by the administrator.';

        final List<dynamic> killedDevices =
            data['killed_devices'] as List<dynamic>? ?? [];

        final List<dynamic> killedAccounts =
            data['killed_accounts'] as List<dynamic>? ?? [];

        appLog('[KillSwitch] globalActive=$globalActive');
        appLog('[KillSwitch] message="$message"');
        appLog('[KillSwitch] killedDevices=$killedDevices');
        appLog('[KillSwitch] killedAccounts=$killedAccounts');

        final bool deviceKilled =
            killedDevices.contains(deviceId);

        final bool accountKilled =
            killedAccounts.contains(accountName);

        appLog(
          '[KillSwitch] deviceKilled=$deviceKilled '
          '(checking "$deviceId" in $killedDevices)'
        );

        appLog(
          '[KillSwitch] accountKilled=$accountKilled '
          '(checking "$accountName" in $killedAccounts)'
        );

        final bool shouldBeAlive =
            globalActive &&
            !deviceKilled &&
            !accountKilled;

        appLog(
          '[KillSwitch] shouldBeAlive=$shouldBeAlive '
          '(globalActive=$globalActive '
          'deviceKilled=$deviceKilled '
          'accountKilled=$accountKilled)'
        );

        if (!shouldBeAlive) {

          killMessage = message;

          appLog(
            '[KillSwitch] 🔴 KILL SIGNAL ACTIVE '
            '— updating appAlive to false'
          );

          appLog(
            '[KillSwitch] kill reason: '
            'globalActive=$globalActive '
            'deviceKilled=$deviceKilled '
            'accountKilled=$accountKilled'
          );

        } else {

          appLog(
            '[KillSwitch] ✅ app is permitted '
            '— appAlive remains/becomes true'
          );
        }

        appLog(
          '[KillSwitch] setting appAlive.value '
          '= $shouldBeAlive'
        );

        appAlive.value = shouldBeAlive;

        appLog('[KillSwitch] appAlive.value set ✅');
      },

      onError: (e) {

        // On network error / permission error
        // fail open so outage doesn't lock users

        appLog(
          '[KillSwitch] stream error '
          '(non-fatal, treating as alive): $e'
        );

        appAlive.value = true;
      },

      onDone: () {

        appLog(
          '[KillSwitch] stream closed (onDone) '
          '— treating as alive'
        );

        appAlive.value = true;
      },
    );

    appLog('[KillSwitch] snapshot listener attached ✅');
  }

  static void stopKillSwitch() {

    appLog('[KillSwitch] stopKillSwitch() called');

    _killSwitchSub?.cancel();
    _killSwitchSub = null;

    appLog('[KillSwitch] listener cancelled ✅');
  }
}