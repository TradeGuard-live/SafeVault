import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';

class LocalNotificationService {
  static LocalNotificationService? _instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  bool _isInitialized = false;

  LocalNotificationService._({FlutterLocalNotificationsPlugin? plugin})
    : _notificationsPlugin = plugin ?? FlutterLocalNotificationsPlugin();

  static LocalNotificationService get instance =>
      _instance ??= LocalNotificationService._();

  Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Notification tapped
      },
    );

    // Create Notification Channel for Android 8+
    final androidChannel = AndroidNotificationChannel(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      description: AppConstants.notificationChannelDesc,
      importance: Importance.high,
      enableVibration: true,
    );

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidImplementation?.createNotificationChannel(androidChannel);

    _isInitialized = true;
  }

  /// Requests permission on Android 13+
  Future<bool> requestPermission() async {
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    final granted = await androidImplementation
        ?.requestNotificationsPermission();
    return granted ?? false;
  }

  /// Schedules a safe local expiry notification.
  /// Example: "Your Vehicle Insurance expires in 7 days."
  Future<void> scheduleExpiryReminder({
    required int notificationId,
    required String documentName,
    required DateTime scheduledDate,
    required int daysBefore,
  }) async {
    await initialize();

    final now = DateTime.now();
    if (scheduledDate.isBefore(now)) {
      return; // Cannot schedule for past date
    }

    String title = '';
    String body = '';
    if (daysBefore == 0) {
      title = 'Document Expired';
      body = 'Your $documentName expires today.';
    } else if (daysBefore == 1) {
      title = 'Document Expiry Tomorrow';
      body = 'Your $documentName expires tomorrow.';
    } else {
      title = 'Upcoming Expiry Reminder';
      body = 'Your $documentName expires in $daysBefore days.';
    }

    // Set reminder for 9:00 AM on the scheduled date
    final scheduledTime = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
      9,
      0,
    );

    final tzDateTime = tz.TZDateTime.from(
      scheduledTime.isBefore(now)
          ? scheduledTime.add(const Duration(minutes: 5))
          : scheduledTime,
      tz.local,
    );

    const androidDetails = AndroidNotificationDetails(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      channelDescription: AppConstants.notificationChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    bool canUseExact = false;
    try {
      canUseExact =
          await androidImplementation?.canScheduleExactNotifications() ?? false;
    } catch (_) {}

    final scheduleMode = canUseExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    try {
      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: tzDateTime,
        notificationDetails: notificationDetails,
        androidScheduleMode: scheduleMode,
      );
    } catch (e) {
      // If exact alarms are not permitted by Android OS policy, gracefully fallback to inexact
      try {
        await _notificationsPlugin.zonedSchedule(
          id: notificationId,
          title: title,
          body: body,
          scheduledDate: tzDateTime,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (fallbackError) {
        debugPrint(
          'LocalNotificationService: Could not schedule reminder: $fallbackError',
        );
      }
    }
  }

  /// Schedules an offline card expiry reminder without leaking full PAN or sensitive data.
  /// Example: "Your HDFC debit card is expiring soon."
  Future<void> scheduleCardExpiryReminder({
    required int notificationId,
    required String bankName,
    required String cardType,
    required DateTime scheduledDate,
    required int daysBefore,
  }) async {
    await initialize();

    final now = DateTime.now();
    if (scheduledDate.isBefore(now)) {
      return;
    }

    final title = 'Card Expiry Reminder';
    final body = daysBefore <= 0
        ? 'Your $bankName ${cardType.toLowerCase()} card is expiring this month.'
        : 'Your $bankName ${cardType.toLowerCase()} card is expiring soon.';

    final scheduledTime = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
      9,
      0,
    );

    final tzDateTime = tz.TZDateTime.from(
      scheduledTime.isBefore(now)
          ? scheduledTime.add(const Duration(minutes: 5))
          : scheduledTime,
      tz.local,
    );

    const androidDetails = AndroidNotificationDetails(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      channelDescription: AppConstants.notificationChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    bool canUseExact = false;
    try {
      canUseExact =
          await androidImplementation?.canScheduleExactNotifications() ?? false;
    } catch (_) {}

    final scheduleMode = canUseExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    try {
      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: tzDateTime,
        notificationDetails: notificationDetails,
        androidScheduleMode: scheduleMode,
      );
    } catch (e) {
      try {
        await _notificationsPlugin.zonedSchedule(
          id: notificationId,
          title: title,
          body: body,
          scheduledDate: tzDateTime,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (fallbackError) {
        debugPrint(
          'LocalNotificationService: Could not schedule card reminder: $fallbackError',
        );
      }
    }
  }

  /// Cancels a specific notification by its integer ID.
  Future<void> cancelNotification(int notificationId) async {
    await initialize();
    await _notificationsPlugin.cancel(id: notificationId);
  }

  /// Cancels all scheduled notifications.
  Future<void> cancelAll() async {
    await initialize();
    await _notificationsPlugin.cancelAll();
  }
}
