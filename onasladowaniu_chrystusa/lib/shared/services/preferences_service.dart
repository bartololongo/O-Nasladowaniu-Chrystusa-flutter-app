import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _keyLastChapterRef = 'last_chapter_ref';
  static const String _keyJumpChapterRef = 'jump_chapter_ref';
  static const String _keyReaderFontSize = 'reader_font_size';
  static const String _keyPendingReaderSearchQuery =
      'pending_reader_search_query';
  static const String _keyPendingReaderSearchToken =
      'pending_reader_search_token';

  // NOWE: numer akapitu, do którego mamy się „zbliżyć” przy skoku
  static const String _keyJumpParagraphNumber = 'jump_paragraph_number';

  String _scrollKeyForChapter(String ref) => 'scroll_offset_$ref';

  /// Zapisz referencję ostatnio czytanego rozdziału, np. "I-3".
  Future<void> saveLastChapterRef(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastChapterRef, reference);
  }

  /// Alias używany w niektórych miejscach kodu.
  Future<void> setLastChapterRef(String reference) async {
    await saveLastChapterRef(reference);
  }

  /// Odczytaj referencję ostatnio czytanego rozdziału.
  /// Zwraca null, jeśli jeszcze nic nie zostało zapisane.
  Future<String?> getLastChapterRef() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastChapterRef);
  }

  /// Tymczasowy skok do rozdziału (np. z "Zobacz w książce").
  /// Reader przy starcie najpierw sprawdzi jump, a potem last.
  Future<void> setJumpChapterRef(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyJumpChapterRef, reference);
  }

  Future<String?> getJumpChapterRef() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyJumpChapterRef);
  }

  Future<void> clearJumpChapterRef() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyJumpChapterRef);
  }

  /// Jednorazowa fraza do lokalnego "Znajdź w rozdziale" po skoku do czytnika.
  Future<void> setPendingReaderSearchQuery(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedQuery = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedQuery.length < 2) {
      await prefs.remove(_keyPendingReaderSearchQuery);
      await prefs.remove(_keyPendingReaderSearchToken);
      return;
    }

    await prefs.setString(_keyPendingReaderSearchQuery, normalizedQuery);
    await prefs.setInt(
      _keyPendingReaderSearchToken,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<String?> takePendingReaderSearchQuery() async {
    final request = await takePendingReaderSearchRequest();
    return request?.query;
  }

  Future<PendingReaderSearchRequest?> takePendingReaderSearchRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final query = prefs.getString(_keyPendingReaderSearchQuery);
    final token = prefs.getInt(_keyPendingReaderSearchToken);
    await prefs.remove(_keyPendingReaderSearchQuery);
    await prefs.remove(_keyPendingReaderSearchToken);

    if (query == null || query.trim().length < 2) {
      return null;
    }

    return PendingReaderSearchRequest(
      query: query,
      token: token ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// NOWE: numer akapitu (1-based) do którego mamy się zbliżyć.
  Future<void> setJumpParagraphNumber(int number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyJumpParagraphNumber, number);
  }

  Future<int?> getJumpParagraphNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyJumpParagraphNumber);
  }

  Future<void> clearJumpParagraphNumber() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyJumpParagraphNumber);
  }

  /// Zapisz rozmiar czcionki w czytniku.
  Future<void> saveReaderFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReaderFontSize, size);
  }

  /// Odczytaj rozmiar czcionki w czytniku.
  /// Zwraca null, jeśli użytkownik jeszcze nic nie ustawił.
  Future<double?> getReaderFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyReaderFontSize);
  }

  /// Zapisz pozycję scrolla dla danego rozdziału.
  Future<void> saveScrollOffset(String chapterRef, double offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollKeyForChapter(chapterRef), offset);
  }

  /// Odczytaj pozycję scrolla dla danego rozdziału.
  /// Zwraca null, jeśli brak zapisanej pozycji.
  Future<double?> getScrollOffset(String chapterRef) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_scrollKeyForChapter(chapterRef));
  }
}

class PendingReaderSearchRequest {
  final String query;
  final int token;

  const PendingReaderSearchRequest({required this.query, required this.token});
}
