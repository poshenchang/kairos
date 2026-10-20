// lib/services/platform_notification/notification_bridge_web.dart

// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

Future<bool> showPlatformNotification({required String title, required String body}) async {
  try {
    final result = js.context.callMethod('kairosShowNotification', [title, body]);
    return result == true;
  } catch (_) {
    return false;
  }
}

Future<String> requestPlatformNotificationPermission() async {
  try {
    final promise = js.context.callMethod('kairosRequestPermission');
    if (promise != null) {
      // Notification.requestPermission() in browsers returns a Promise or uses a callback
      return promise.toString();
    }
  } catch (_) {}
  return 'denied';
}

String getPlatformNotificationPermission() {
  try {
    final status = js.context.callMethod('kairosGetPermission');
    return status?.toString() ?? 'default';
  } catch (_) {
    return 'unsupported';
  }
}

