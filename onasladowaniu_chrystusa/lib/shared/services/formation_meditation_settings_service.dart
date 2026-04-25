import 'package:shared_preferences/shared_preferences.dart';

class FormationMeditationSettingsService {
  static const String _keyDurationMinutes =
      'formation_meditation_duration_minutes';
  static const int defaultDurationMinutes = 15;
  static const List<int> allowedDurationMinutes = [5, 10, 15, 20, 30];

  Future<int> getDurationMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_keyDurationMinutes);
    if (stored == null || !allowedDurationMinutes.contains(stored)) {
      return defaultDurationMinutes;
    }
    return stored;
  }

  Future<void> setDurationMinutes(int minutes) async {
    if (!allowedDurationMinutes.contains(minutes)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDurationMinutes, minutes);
  }
}
