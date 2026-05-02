import 'audio_track.dart';

class AudioCatalog {
  static const String baseUrl =
      'https://bartololongo.pl/uploads/audio/o-nasladowaniu/v1';

  static const Map<String, int> _bookNumbersByCode = {
    'I': 1,
    'II': 2,
    'III': 3,
    'IV': 4,
  };

  static AudioTrack? trackForChapter({
    required String chapterReference,
    required String title,
    required String subtitle,
  }) {
    final parsed = _parseChapterReference(chapterReference);
    if (parsed == null) return null;

    final (:bookNumber, :chapterNumber) = parsed;
    final url = audioUrlForReference(chapterReference);
    if (url == null) return null;

    final chapterPath = chapterNumber.toString().padLeft(2, '0');
    final id = 'book_${bookNumber}_chapter_$chapterPath';
    final trackTitle = title.trim().isNotEmpty
        ? title.trim()
        : 'Rozdział $chapterNumber';

    return AudioTrack(
      id: id,
      bookNumber: bookNumber,
      chapterNumber: chapterNumber,
      title: trackTitle,
      subtitle: subtitle,
      url: url,
    );
  }

  static String? audioUrlForReference(String chapterReference) {
    final parsed = _parseChapterReference(chapterReference);
    if (parsed == null) return null;

    final chapterPath = parsed.chapterNumber.toString().padLeft(2, '0');
    return '$baseUrl/book_${parsed.bookNumber}/chapter_$chapterPath.m4a';
  }

  static Map<String, String?> previewUrlsForReferences(
    Iterable<String> chapterReferences,
  ) {
    return {
      for (final reference in chapterReferences)
        reference: audioUrlForReference(reference),
    };
  }

  static ({int bookNumber, int chapterNumber})? _parseChapterReference(
    String chapterReference,
  ) {
    final parts = chapterReference.trim().split('-');
    if (parts.length != 2) return null;

    final bookCode = parts[0].trim().toUpperCase();
    final bookNumber = _bookNumbersByCode[bookCode];
    final chapterNumber = int.tryParse(parts[1].trim());
    if (bookNumber == null || chapterNumber == null) return null;

    return (bookNumber: bookNumber, chapterNumber: chapterNumber);
  }
}
