// lib/services/platform_notification/notification_bridge_native.dart

import 'dart:io';

Future<bool> showPlatformNotification({required String title, required String body}) async {
  if (Platform.isLinux) {
    try {
      final res = await Process.run('notify-send', [
        '-a',
        'Kairos',
        '-i',
        'kairos',
        title,
        body,
      ]);
      return res.exitCode == 0;
    } catch (_) {}
  }
  return false;
}

Future<String> requestPlatformNotificationPermission() async {
  return 'granted';
}

String getPlatformNotificationPermission() {
  return 'granted';
}

Future<void> hardReloadBrowser() async {}

