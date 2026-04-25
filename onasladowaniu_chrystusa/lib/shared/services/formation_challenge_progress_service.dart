import 'package:shared_preferences/shared_preferences.dart';

class FormationChallengeProgressService {
  static const String _keyIsStarted = 'formation_challenge_is_started';
  static const String _keyStartedAt = 'formation_challenge_started_at';
  static const String _keyLastCompletedDay =
      'formation_challenge_last_completed_day';

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
  }

  Future<int> getLastCompletedDay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastCompletedDay) ?? 0;
  }

  Future<void> markDayCompleted(int dayNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCompletedDay = await getLastCompletedDay();
    if (dayNumber <= lastCompletedDay) return;

    await prefs.setInt(_keyLastCompletedDay, dayNumber);
  }

  Future<bool> isDayCompleted(int dayNumber) async {
    final lastCompletedDay = await getLastCompletedDay();
    return dayNumber <= lastCompletedDay;
  }
}
