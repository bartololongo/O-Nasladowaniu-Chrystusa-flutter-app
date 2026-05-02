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

    final chapterCode = _chapterCode(chapterNumber);
    final id = 'book_${bookNumber}_chapter_$chapterCode';
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

    final chapterCode = _chapterCode(parsed.chapterNumber);
    return '$baseUrl/book_${parsed.bookNumber}/chapter_$chapterCode.m4a';
  }

  static Map<String, String?> previewUrlsForReferences(
    Iterable<String> chapterReferences,
  ) {
    return {
      for (final reference in chapterReferences)
        reference: audioUrlForReference(reference),
    };
  }

  static String? chapterReferenceForTrackId(String trackId) {
    final match = RegExp(r'^book_(\d+)_chapter_(\d+)$').firstMatch(trackId);
    if (match == null) return null;

    final bookNumber = int.tryParse(match.group(1)!);
    final chapterNumber = int.tryParse(match.group(2)!);
    if (bookNumber == null || chapterNumber == null) return null;

    final bookCode = _bookCodesByNumber[bookNumber];
    if (bookCode == null) return null;

    return '$bookCode-$chapterNumber';
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

  static String _chapterCode(int chapterNumber) {
    // Hosting audio używa formatu chapter_XX.m4a dla wszystkich ksiąg.
    return chapterNumber.toString().padLeft(2, '0');
  }

  static const Map<int, String> _bookCodesByNumber = {
    1: 'I',
    2: 'II',
    3: 'III',
    4: 'IV',
  };
}
