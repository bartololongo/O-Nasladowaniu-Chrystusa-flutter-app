import '../../../shared/models/book_models.dart';
import '../../../shared/services/book_repository.dart';
import '../data/audio_catalog.dart';
import '../data/audio_track.dart';
import 'app_audio_player_service.dart';

class AudioResumeTileData {
  final bool hasSavedProgress;
  final String chapterReference;

  const AudioResumeTileData({
    required this.hasSavedProgress,
    required this.chapterReference,
  });

  String get title =>
      hasSavedProgress ? 'Kontynuuj słuchanie' : 'Rozpocznij słuchanie';

  String get subtitle =>
      AudioResumeService.chapterMetaForReference(chapterReference);
}

class AudioResumeService {
  AudioResumeService({
    AppAudioPlayerService? audioService,
    BookRepository? bookRepository,
  }) : _audioService = audioService ?? AppAudioPlayerService.instance,
       _bookRepository = bookRepository ?? BookRepository();

  static const String defaultChapterReference = 'I-1';

  final AppAudioPlayerService _audioService;
  final BookRepository _bookRepository;

  Future<AudioResumeTileData> loadTileData() async {
    final chapterReference = await lastChapterReference();

    return AudioResumeTileData(
      hasSavedProgress: chapterReference != null,
      chapterReference: chapterReference ?? defaultChapterReference,
    );
  }

  Future<String?> lastChapterReference() async {
    final trackId = await _audioService.getLastTrackId();
    if (trackId == null) return null;

    return AudioCatalog.chapterReferenceForTrackId(trackId);
  }

  Future<AudioTrack?> lastOrFirstTrack() async {
    final chapterReference =
        await lastChapterReference() ?? defaultChapterReference;

    return audioTrackForChapterReference(chapterReference);
  }

  Future<AudioTrack?> audioTrackForChapterReference(
    String chapterReference,
  ) async {
    final chapter = await _bookRepository.getChapterByReference(
      chapterReference,
    );
    if (chapter == null) return null;

    return AudioCatalog.trackForChapter(
      chapterReference: chapter.reference,
      title: chapter.title,
      subtitle: _bookTitleForChapter(chapter),
    );
  }

  static String chapterMetaForReference(String chapterReference) {
    final parts = chapterReference.split('-');
    if (parts.length == 2) {
      return 'Księga ${parts[0]}, rozdział ${parts[1]}';
    }

    return 'Rozdział $chapterReference';
  }

  static String _bookTitleForChapter(BookChapter chapter) {
    final bookCode = chapter.reference.split('-').first;

    return switch (bookCode) {
      'I' => 'Księga pierwsza',
      'II' => 'Księga druga',
      'III' => 'Księga trzecia',
      'IV' => 'Księga czwarta',
      _ => 'Księga $bookCode',
    };
  }
}
