import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      macOS: initializationSettingsDarwin,
      iOS: initializationSettingsDarwin,
    );

    await _notificationsPlugin.initialize(initializationSettings);

    // Android 13+ requires the POST_NOTIFICATIONS runtime permission (no-op on
    // older versions). Granting it lets both the download notifications and
    // the media playback notification be shown.
    if (!kIsWeb && Platform.isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'download_channel',
          'Downloads',
          channelDescription: 'Show download progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          maxProgress: maxProgress,
          progress: progress,
          onlyAlertOnce: true,
          // White silhouette for the status bar + the color app logo in the
          // shade: without these the notification shows no app icon at all.
          icon: 'ic_notification',
          largeIcon: const DrawableResourceAndroidBitmap('ic_launcher_large'),
          color: const Color(0xFFFFFFFF),
        );
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await _notificationsPlugin.show(id, title, body, platformChannelSpecifics);
  }

  Future<void> showCompletionNotification({
    required int id,
    required String title,
    required String body,
    bool isError = false,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'download_channel',
          'Downloads',
          channelDescription: 'Show download progress',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: false,
          icon: 'ic_notification',
          largeIcon: const DrawableResourceAndroidBitmap('ic_launcher_large'),
          color: const Color(0xFFFFFFFF),
        );
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await _notificationsPlugin.show(id, title, body, platformChannelSpecifics);
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}
