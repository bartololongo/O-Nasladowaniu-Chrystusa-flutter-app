import 'package:shared_preferences/shared_preferences.dart';

class ReadingChallengeState {
  final DateTime? startedAt;

  const ReadingChallengeState({this.startedAt});

  bool get isActive => startedAt != null;
}

class ReadingChallengeService {
  static const String _keyStartedAt = 'reading_challenge_started_at';

  Future<ReadingChallengeState> getState() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_keyStartedAt);
    DateTime? startedAt;
    if (millis != null) {
      startedAt = DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return ReadingChallengeState(startedAt: startedAt);
  }

  Future<void> startChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyStartedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> resetChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStartedAt);
  }
}
