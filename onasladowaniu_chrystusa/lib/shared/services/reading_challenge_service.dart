import 'package:shared_preferences/shared_preferences.dart';

class ReadingChallengeState {
  final DateTime? startedAt;
  final String? furthestChapterRef;

  const ReadingChallengeState({
    this.startedAt,
    this.furthestChapterRef,
  });

  bool get isActive => startedAt != null;
}

class ReadingChallengeService {
  static const String _keyStartedAt = 'reading_challenge_started_at';
  static const String _keyFurthestChapterRef =
      'reading_challenge_furthest_chapter_ref';

  Future<ReadingChallengeState> getState() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_keyStartedAt);
    final furthestRef = prefs.getString(_keyFurthestChapterRef);

    DateTime? startedAt;
    if (millis != null) {
      startedAt = DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return ReadingChallengeState(
      startedAt: startedAt,
      furthestChapterRef: furthestRef,
    );
  }

  Future<void> startChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyStartedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    // przy starcie wyzwania czyścimy info o najdalszym rozdziale
    await prefs.remove(_keyFurthestChapterRef);
  }

  Future<void> resetChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStartedAt);
    await prefs.remove(_keyFurthestChapterRef);
  }

  /// Ustawienie najdalszego rozdziału osiągniętego w ramach wyzwania.
  Future<void> updateFurthestChapter(String chapterRef) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFurthestChapterRef, chapterRef);
  }

  Future<String?> getFurthestChapterRef() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFurthestChapterRef);
  }
}
