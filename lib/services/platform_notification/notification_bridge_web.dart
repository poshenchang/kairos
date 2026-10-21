// lib/services/platform_notification/notification_bridge_web.dart
//
// Calls the notification helpers defined in web/index.html. Uses
// dart:js_interop so it compiles for both the JS and WebAssembly web builds.

import 'dart:js_interop';

@JS('kairosShowNotification')
external JSBoolean? _showNotification(JSString title, JSString body);

@JS('kairosRequestPermission')
external JSPromise<JSString>? _requestPermission();

@JS('kairosGetPermission')
external JSString? _getPermission();

@JS('kairosHardReload')
external JSPromise<JSAny?>? _hardReload();

Future<bool> showPlatformNotification({required String title, required String body}) async {
  try {
    return _showNotification(title.toJS, body.toJS)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

Future<String> requestPlatformNotificationPermission() async {
  try {
    // Notification.requestPermission() resolves to "granted" | "denied" | "default"
    final result = await _requestPermission()?.toDart;
    if (result != null) return result.toDart;
  } catch (_) {}
  return 'denied';
}

String getPlatformNotificationPermission() {
  try {
    return _getPermission()?.toDart ?? 'default';
  } catch (_) {
    return 'unsupported';
  }
}

Future<void> hardReloadBrowser() async {
  try {
    await _hardReload()?.toDart;
  } catch (_) {}
}
