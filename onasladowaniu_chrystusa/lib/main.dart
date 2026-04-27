import 'package:flutter/material.dart';

import 'app.dart';
import 'shared/services/formation_notification_service.dart';
import 'shared/services/formation_widget_snapshot_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialNotificationPayload = await FormationNotificationService.instance
      .initialize();
  try {
    await FormationWidgetSnapshotService.configureAppGroup();
    await FormationWidgetSnapshotService().refresh();
  } catch (_) {
    // Widget data should never block app startup.
  }
  runApp(
    ImitationOfChristApp(
      initialNotificationPayload: initialNotificationPayload,
    ),
  );
}
