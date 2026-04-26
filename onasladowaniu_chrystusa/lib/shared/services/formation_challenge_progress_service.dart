import 'package:shared_preferences/shared_preferences.dart';

class FormationChallengeProgressService {
  static const String _keyIsStarted = 'formation_challenge_is_started';
  static const String _keyStartedAt = 'formation_challenge_started_at';
  static const String _keyLastCompletedDay =
      'formation_challenge_last_completed_day';
  static const String _keyCompletedDays =
      'formation_challenge_completed_days_v1';

  Future<bool> isStarted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsStarted) ?? false;
  }

  Future<DateTime?> getStartDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyStartedAt);
    if (raw == null || raw.isEmpty) return null;

    return DateTime.tryParse(raw);
  }

  Future<void> startChallenge({DateTime? startDate}) async {
    final prefs = await SharedPreferences.getInstance();
    final startedAt = startDate ?? DateTime.now();

    await prefs.setBool(_keyIsStarted, true);
    await prefs.setString(_keyStartedAt, startedAt.toIso8601String());
  }

  Future<void> resetChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsStarted);
    await prefs.remove(_keyStartedAt);
    await prefs.remove(_keyLastCompletedDay);
    await prefs.remove(_keyCompletedDays);
  }

  Future<int> getLastCompletedDay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastCompletedDay) ?? 0;
  }

  Future<Set<int>> getCompletedDays() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_keyCompletedDays);

    if (stored == null) {
      final legacyLastCompletedDay = await getLastCompletedDay();
      if (legacyLastCompletedDay <= 0) return <int>{};
      return <int>{legacyLastCompletedDay};
    }

    return stored
        .map(int.tryParse)
        .whereType<int>()
        .where((dayNumber) => dayNumber > 0)
        .toSet();
  }

  Future<void> markDayCompleted(int dayNumber) async {
    if (dayNumber <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final completedDays = await getCompletedDays();
    completedDays.add(dayNumber);

    final sortedDays = completedDays.toList()..sort();
    await prefs.setStringList(
      _keyCompletedDays,
      sortedDays.map((day) => day.toString()).toList(),
    );

    final lastCompletedDay = await getLastCompletedDay();
    if (dayNumber > lastCompletedDay) {
      await prefs.setInt(_keyLastCompletedDay, dayNumber);
    }
  }

  Future<bool> isDayCompleted(int dayNumber) async {
    final completedDays = await getCompletedDays();
    return completedDays.contains(dayNumber);
  }
}
