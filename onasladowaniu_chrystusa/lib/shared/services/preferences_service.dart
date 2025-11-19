import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _keyLastChapterRef = 'last_chapter_ref';
  static const String _keyReaderFontSize = 'reader_font_size';

  String _scrollKeyForChapter(String ref) => 'scroll_offset_$ref';

  /// Zapisz referencję ostatnio czytanego rozdziału, np. "I-3".
  Future<void> saveLastChapterRef(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastChapterRef, reference);
  }

  /// Odczytaj referencję ostatnio czytanego rozdziału.
  /// Zwraca null, jeśli jeszcze nic nie zostało zapisane.
  Future<String?> getLastChapterRef() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastChapterRef);
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
