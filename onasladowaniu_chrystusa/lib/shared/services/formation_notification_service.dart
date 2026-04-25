import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
void formationNotificationTapBackground(NotificationResponse response) {
  DartPluginRegistrant.ensureInitialized();
  debugPrint(
    '[FormationNotification] onDidReceiveBackgroundNotificationResponse '
    'payload=${response.payload}',
  );
  unawaited(
    FormationNotificationService.savePendingPayloadFromBackground(
      response.payload,
    ),
  );
}

void formationNotificationTapForeground(NotificationResponse response) {
  FormationNotificationService.instance.handleNotificationResponse(
    response.payload,
    source: 'onDidReceiveNotificationResponse',
  );
}

class FormationReminderTime {
  final int hour;
  final int minute;

  const FormationReminderTime({
    required this.hour,
    required this.minute,
  });

  String get formatted {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay toTimeOfDay() => TimeOfDay(hour: hour, minute: minute);
}

class FormationNotificationService {
  static const String formationPayload = 'formation_challenge';

  static const String _keyReminderEnabled = 'formation_reminder_enabled';
  static const String _keyReminderHour = 'formation_reminder_hour';
  static const String _keyReminderMinute = 'formation_reminder_minute';
  static const String _keyPendingPayload = 'formation_pending_payload';
  static const int _notificationId = 1001;
  static const MethodChannel _nativeTapChannel =
      MethodChannel('formation_notification_taps');

  static final FormationNotificationService instance =
      FormationNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _payloadController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool _nativeTapHandlerRegistered = false;
  String? _pendingPayload;

  FormationNotificationService._();

  Stream<String> get payloadStream => _payloadController.stream;

  Future<String?> takePendingPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _pendingPayload;
    final storedPayload = prefs.getString(_keyPendingPayload);
    final resolvedPayload = payload ?? storedPayload;
    _pendingPayload = null;
    await prefs.remove(_keyPendingPayload);
    debugPrint(
      '[FormationNotification] takePendingPayload returned '
      'payload=$resolvedPayload',
    );
    return resolvedPayload;
  }

  static Future<void> savePendingPayloadFromBackground(String? payload) async {
    if (payload == null || payload.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPendingPayload, payload);
    debugPrint(
      '[FormationNotification] pending payload set=$payload from background',
    );
  }

  Future<String?> initialize() async {
    debugPrint(
      '[FormationNotification] initialize start, initialized=$_initialized',
    );
    _registerNativeTapHandler();
    if (_initialized) return null;

    await _configureLocalTimeZone();

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );

    final initializeResult = await _notifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: formationNotificationTapForeground,
      onDidReceiveBackgroundNotificationResponse:
          formationNotificationTapBackground,
    );
    debugPrint(
      '[FormationNotification] plugin initialize result=$initializeResult',
    );
    if (initializeResult != true) return null;

    debugPrint(
      '[FormationNotification] plugin initialized with response callback',
    );

    _initialized = true;

    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    debugPrint(
      '[FormationNotification] didNotificationLaunchApp='
      '${launchDetails?.didNotificationLaunchApp}',
    );
    debugPrint(
      '[FormationNotification] launch payload='
      '${launchDetails?.notificationResponse?.payload}',
    );
    if ((launchDetails?.didNotificationLaunchApp ?? false) &&
        launchDetails?.notificationResponse?.payload != null) {
      final payload = launchDetails!.notificationResponse!.payload!;
      unawaited(
        _setPendingPayload(
          payload,
          source: 'cold start',
          emitToStream: false,
        ),
      );
      debugPrint(
        '[FormationNotification] pending payload saved from cold start: '
        'payload=$payload',
      );
      return payload;
    }

    return null;
  }

  void _registerNativeTapHandler() {
    if (_nativeTapHandlerRegistered) return;

    _nativeTapChannel.setMethodCallHandler((call) async {
      if (call.method != 'notificationTap') return;

      final payload = call.arguments as String?;
      handleNotificationResponse(
        payload,
        source: 'native notification tap',
      );
    });
    _nativeTapHandlerRegistered = true;
    debugPrint('[FormationNotification] native tap channel registered');
  }

  void handleNotificationResponse(
    String? payload, {
    required String source,
  }) {
    debugPrint(
      '[FormationNotification] $source payload=$payload',
    );
    if (payload == null || payload.isEmpty) return;

    unawaited(
      _setPendingPayload(
        payload,
        source: source,
        emitToStream: true,
      ),
    );
  }

  Future<void> _setPendingPayload(
    String payload, {
    required String source,
    required bool emitToStream,
  }) async {
    _pendingPayload = payload;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPendingPayload, payload);
    debugPrint(
      '[FormationNotification] pending payload set=$payload from $source',
    );
    debugPrint(
      '[FormationNotification] pending payload saved to preferences from '
      '$source: '
      'payload=$payload',
    );
    if (emitToStream) {
      _payloadController.add(payload);
    }
  }

  Future<void> _configureLocalTimeZone() async {
    tz.initializeTimeZones();

    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
  }

  Future<bool> isReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyReminderEnabled) ?? false;
  }

  Future<FormationReminderTime> getReminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_keyReminderHour) ?? 20;
    final minute = prefs.getInt(_keyReminderMinute) ?? 0;

    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return const FormationReminderTime(hour: 20, minute: 0);
    }

    return FormationReminderTime(hour: hour, minute: minute);
  }

  Future<void> setReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReminderEnabled, enabled);

    if (enabled) {
      await scheduleDailyReminder();
    } else {
      await cancelDailyReminder();
    }
  }

  Future<void> setReminderTime({
    required int hour,
    required int minute,
  }) async {
    final safeHour = hour.clamp(0, 23);
    final safeMinute = minute.clamp(0, 59);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReminderHour, safeHour);
    await prefs.setInt(_keyReminderMinute, safeMinute);

    if (await isReminderEnabled()) {
      await scheduleDailyReminder();
    }
  }

  Future<void> scheduleDailyReminder() async {
    await initialize();
    await _configureLocalTimeZone();
    await _requestPermissions();

    final reminderTime = await getReminderTime();
    debugPrint(
      '[FormationNotification] scheduleDailyReminder: '
      'time=${reminderTime.formatted}, payload=$formationPayload',
    );
    await _notifications.zonedSchedule(
      id: _notificationId,
      title: 'Droga naśladowania',
      body: 'Znajdź dzisiaj chwilę na medytację',
      scheduledDate: _nextInstanceOf(reminderTime.hour, reminderTime.minute),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'formation_reminder',
          'Droga naśladowania',
          channelDescription: 'Codzienne przypomnienie o Drodze naśladowania',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: formationPayload,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<List<PendingNotificationRequest>>
      getPendingNotificationRequests() async {
    await initialize();
    return _notifications.pendingNotificationRequests();
  }

  Future<void> scheduleTestNotificationInTenSeconds() async {
    await initialize();
    await _configureLocalTimeZone();
    await _requestPermissions();

    await _notifications.zonedSchedule(
      id: _notificationId + 1,
      title: 'Droga naśladowania',
      body: 'Znajdź dzisiaj chwilę na medytację',
      scheduledDate: tz.TZDateTime.now(tz.local).add(
        const Duration(seconds: 10),
      ),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'formation_reminder',
          'Droga naśladowania',
          channelDescription: 'Codzienne przypomnienie o Drodze naśladowania',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: formationPayload,
    );
  }

  Future<void> cancelDailyReminder() async {
    await initialize();
    await _notifications.cancel(id: _notificationId);
  }

  Future<void> _requestPermissions() async {
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _notifications
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }
}
