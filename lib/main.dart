import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'app.dart';
import 'core/services/onesignal_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("db306b7b-eb8d-49f4-8fd0-b4f312afd1a3");
  OneSignal.Notifications.requestPermission(false);

  final oneSignalService = OneSignalService();
  await oneSignalService.init();

  runApp(App(oneSignalService: oneSignalService));
}
