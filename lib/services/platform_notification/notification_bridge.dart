// lib/services/platform_notification/notification_bridge.dart

import 'notification_bridge_native.dart'
    if (dart.library.js_interop) 'notification_bridge_web.dart'
    if (dart.library.io) 'notification_bridge_native.dart' as impl;

Future<bool> showPlatformNotification({required String title, required String body}) =>
    impl.showPlatformNotification(title: title, body: body);

Future<String> requestPlatformNotificationPermission() =>
    impl.requestPlatformNotificationPermission();

String getPlatformNotificationPermission() =>
    impl.getPlatformNotificationPermission();

