import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'app.dart';
import 'core/api/api_config.dart';
import 'core/services/onesignal_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kDebugMode) OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(ApiConfig.oneSignalAppId);
    OneSignal.Notifications.requestPermission(false);
  } catch (e) {
    debugPrint('[OneSignal] Init failed: $e');
  }

  final oneSignalService = OneSignalService();
  await oneSignalService.init();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('❌ FlutterError: ${details.exception}\n${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('❌ Async error: $error\n$stack');
    return true;
  };

  ErrorWidget.builder = (details) {
    if (kReleaseMode) {
      return const Material(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Произошла ошибка.\nПерезапустите приложение.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return ErrorWidget(details.exception);
  };

  runApp(App(oneSignalService: oneSignalService));
}
