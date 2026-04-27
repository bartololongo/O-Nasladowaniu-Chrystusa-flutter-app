import 'package:home_widget/home_widget.dart';

import 'formation_challenge_progress_service.dart';
import 'formation_challenge_service.dart';

class FormationWidgetSnapshotService {
  static const String widgetPayload = 'formation_widget';

  static const String keyIsStarted = 'formation_widget_is_started';
  static const String keyDayNumber = 'formation_widget_day_number';
  static const String keyTotalDays = 'formation_widget_total_days';
  static const String keyCompletedCount = 'formation_widget_completed_count';
  static const String keyProgressPercent = 'formation_widget_progress_percent';
  static const String keyTodayCompleted = 'formation_widget_today_completed';
  static const String keyCatchUpCount = 'formation_widget_catch_up_count';
  static const String keyMessage = 'formation_widget_message';
  static const String keyUpdatedAt = 'formation_widget_updated_at';

  static const String _widgetName = 'FormationWidget';

  final FormationChallengeProgressService _progressService;
  final FormationChallengeService _challengeService;

  FormationWidgetSnapshotService({
    FormationChallengeProgressService? progressService,
    FormationChallengeService? challengeService,
  }) : _progressService =
           progressService ?? FormationChallengeProgressService(),
       _challengeService = challengeService ?? FormationChallengeService();

  Future<void> refresh() async {
    try {
      final snapshot = await _buildSnapshot();
      await _saveSnapshot(snapshot);
      await updateWidget();
    } catch (_) {
      // Widget snapshot is preparatory and must not block app flows.
    }
  }

  Future<void> updateSnapshot() => refresh();

  Future<void> updateWidget() async {
    try {
      await HomeWidget.updateWidget(name: _widgetName);
    } catch (_) {
      // Native widget targets are not present yet. Snapshot saving should still
      // work, so updating the widget is best-effort in this preparation stage.
    }
  }

  Future<_FormationWidgetSnapshot> _buildSnapshot() async {
    final totalDays = await _challengeService.getTotalDays();
    final isStarted = await _progressService.isStarted();
    final startedAt = await _progressService.getStartDate();

    if (!isStarted || startedAt == null) {
      return _FormationWidgetSnapshot(
        isStarted: false,
        dayNumber: 0,
        totalDays: totalDays,
        completedCount: 0,
        progressPercent: 0,
        todayCompleted: false,
        catchUpCount: 0,
        message: 'Rozpocznij Drogę naśladowania.',
        updatedAt: DateTime.now(),
      );
    }

    final currentDay = await _challengeService.getDayForDate(
      startedAt,
      DateTime.now(),
    );
    final completedDays = await _progressService.getCompletedDays();
    final completedCount = completedDays
        .where((day) => day > 0 && day <= totalDays)
        .length;
    final catchUpCount = [
      for (var day = 1; day < currentDay.dayNumber; day++)
        if (!completedDays.contains(day)) day,
    ].length;
    final todayCompleted = completedDays.contains(currentDay.dayNumber);

    final message = catchUpCount > 0
        ? 'Masz $catchUpCount ${_daysToCatchUpLabel(catchUpCount)} do nadrobienia.'
        : todayCompleted
        ? 'Dzisiejszy dzień ukończony. Wróć jutro.'
        : 'Dziś czeka na Ciebie kolejny krok Drogi.';

    return _FormationWidgetSnapshot(
      isStarted: true,
      dayNumber: currentDay.dayNumber,
      totalDays: totalDays,
      completedCount: completedCount,
      progressPercent: totalDays == 0 ? 0 : completedCount / totalDays,
      todayCompleted: todayCompleted,
      catchUpCount: catchUpCount,
      message: message,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _saveSnapshot(_FormationWidgetSnapshot snapshot) async {
    await HomeWidget.saveWidgetData<bool>(keyIsStarted, snapshot.isStarted);
    await HomeWidget.saveWidgetData<int>(keyDayNumber, snapshot.dayNumber);
    await HomeWidget.saveWidgetData<int>(keyTotalDays, snapshot.totalDays);
    await HomeWidget.saveWidgetData<int>(
      keyCompletedCount,
      snapshot.completedCount,
    );
    await HomeWidget.saveWidgetData<double>(
      keyProgressPercent,
      snapshot.progressPercent,
    );
    await HomeWidget.saveWidgetData<bool>(
      keyTodayCompleted,
      snapshot.todayCompleted,
    );
    await HomeWidget.saveWidgetData<int>(
      keyCatchUpCount,
      snapshot.catchUpCount,
    );
    await HomeWidget.saveWidgetData<String>(keyMessage, snapshot.message);
    await HomeWidget.saveWidgetData<String>(
      keyUpdatedAt,
      snapshot.updatedAt.toIso8601String(),
    );
  }

  String _daysToCatchUpLabel(int count) {
    if (count == 1) return 'dzień';

    final mod100 = count % 100;
    final mod10 = count % 10;
    if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) {
      return 'dni';
    }

    return 'dni';
  }
}

class _FormationWidgetSnapshot {
  final bool isStarted;
  final int dayNumber;
  final int totalDays;
  final int completedCount;
  final double progressPercent;
  final bool todayCompleted;
  final int catchUpCount;
  final String message;
  final DateTime updatedAt;

  const _FormationWidgetSnapshot({
    required this.isStarted,
    required this.dayNumber,
    required this.totalDays,
    required this.completedCount,
    required this.progressPercent,
    required this.todayCompleted,
    required this.catchUpCount,
    required this.message,
    required this.updatedAt,
  });
}
