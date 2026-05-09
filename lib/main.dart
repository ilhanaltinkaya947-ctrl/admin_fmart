import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/api/api_config.dart';
import 'core/services/onesignal_service.dart';

// DSN passed at build time:
//   flutter build ios --release --dart-define=SENTRY_DSN=https://...@sentry.io/...
const _sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
const _sentryEnv =
    String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: 'production');

Future<void> _bootstrap() async {
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
    if (_sentryDsn.isNotEmpty) {
      Sentry.captureException(details.exception, stackTrace: details.stack);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('❌ Async error: $error\n$stack');
    if (_sentryDsn.isNotEmpty) {
      Sentry.captureException(error, stackTrace: stack);
    }
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

Future<void> main() async {
  if (_sentryDsn.isEmpty) {
    await _bootstrap();
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.environment = _sentryEnv;
      options.tracesSampleRate = 0.1;
      options.attachScreenshot = false;
      options.attachViewHierarchy = false;
      options.sendDefaultPii = false;
      options.beforeSend = (event, hint) async {
        // Strip Authorization headers if any leaked into breadcrumbs.
        final breadcrumbs = event.breadcrumbs;
        if (breadcrumbs != null) {
          for (final b in breadcrumbs) {
            final data = b.data;
            if (data != null) {
              data.remove('authorization');
              data.remove('Authorization');
              data.remove('access_token');
              data.remove('refresh_token');
            }
          }
        }
        return event;
      };
    },
    appRunner: _bootstrap,
  );
}
