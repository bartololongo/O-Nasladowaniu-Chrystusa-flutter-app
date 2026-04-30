import 'audio_track.dart';

class AudioCatalog {
  static const String baseUrl =
      'https://TWOJA_DOMENA/uploads/audio/o-nasladowaniu/v1';

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
    final parts = chapterReference.split('-');
    if (parts.length != 2) return null;

    final bookNumber = _bookNumbersByCode[parts[0]];
    final chapterNumber = int.tryParse(parts[1]);
    if (bookNumber == null || chapterNumber == null) return null;

    final chapterPath = chapterNumber.toString().padLeft(2, '0');
    final id = 'book_${bookNumber}_chapter_$chapterPath';

    return AudioTrack(
      id: id,
      bookNumber: bookNumber,
      chapterNumber: chapterNumber,
      title: title,
      subtitle: subtitle,
      url: '$baseUrl/book_$bookNumber/chapter_$chapterPath.m4a',
    );
  }
}
