import 'package:flutter/material.dart';

import 'app.dart';
import 'shared/services/formation_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialNotificationPayload =
      await FormationNotificationService.instance.initialize();
  runApp(
    ImitationOfChristApp(
      initialNotificationPayload: initialNotificationPayload,
    ),
  );
}
