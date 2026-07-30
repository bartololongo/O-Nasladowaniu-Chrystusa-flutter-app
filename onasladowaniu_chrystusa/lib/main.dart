import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'shared/services/formation_notification_service.dart';
import 'shared/services/formation_widget_snapshot_service.dart';

const bool _scheduleFormationNotificationTest = bool.fromEnvironment(
  'FORMATION_NOTIFICATION_TEST',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await JustAudioBackground.init(
    androidNotificationChannelId: 'pl.bartololongo.onasladowaniu.audio',
    androidNotificationChannelName: 'O naśladowaniu Chrystusa',
    androidNotificationOngoing: true,
  );
  final initialNotificationPayload = await FormationNotificationService.instance
      .initialize();
  if (kDebugMode && _scheduleFormationNotificationTest) {
    await FormationNotificationService.instance.scheduleTestNotification(
      delay: const Duration(seconds: 45),
    );
  }
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
