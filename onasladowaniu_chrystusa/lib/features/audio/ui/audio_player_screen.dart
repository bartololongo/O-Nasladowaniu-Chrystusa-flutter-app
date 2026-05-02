import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../shared/models/book_models.dart';
import '../../../shared/services/book_repository.dart';
import '../data/audio_catalog.dart';
import '../data/audio_track.dart';
import '../services/app_audio_player_service.dart';

class AudioPlayerScreen extends StatefulWidget {
  final AudioTrack track;

  const AudioPlayerScreen({super.key, required this.track});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final AppAudioPlayerService _audioService = AppAudioPlayerService.instance;
  final BookRepository _bookRepository = BookRepository();

  StreamSubscription<PlaybackEvent>? _playbackErrorSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  late AudioTrack _track;
  AudioTrack? _previousTrack;
  AudioTrack? _nextTrack;
  String? _errorMessage;
  bool _autoAdvanceEnabled = false;
  bool _isLoadingAdjacentTracks = false;
  bool _isChangingTrack = false;
  bool _handledCompletedTrack = false;

  @override
  void initState() {
    super.initState();
    _track = widget.track;
    _playbackErrorSubscription = _audioService.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'AudioPlayerScreen: playbackEventStream error. '
          'trackId=${_track.id}, url=${_track.url}, '
          'errorType=${error.runtimeType}, error=$error',
        );
        debugPrintStack(
          label: 'AudioPlayerScreen: playbackEventStream stackTrace',
          stackTrace: stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Nie udało się odtworzyć audio. Sprawdź połączenie z internetem.';
        });
      },
    );
    _playerStateSubscription = _audioService.playerStateStream.listen(
      _handlePlayerStateChanged,
    );
    unawaited(_loadAutoAdvanceSetting());
    unawaited(_loadAdjacentTracks());
    unawaited(_startPlayback(_track));
  }

  @override
  void dispose() {
    _playbackErrorSubscription?.cancel();
    _playerStateSubscription?.cancel();
    unawaited(_audioService.pause());
    super.dispose();
  }

  Future<void> _loadAutoAdvanceSetting() async {
    final enabled = await _audioService.getAutoAdvanceEnabled();
    if (!mounted) return;
    setState(() {
      _autoAdvanceEnabled = enabled;
    });
  }

  Future<void> _setAutoAdvanceEnabled(bool enabled) async {
    setState(() {
      _autoAdvanceEnabled = enabled;
    });
    await _audioService.setAutoAdvanceEnabled(enabled);
  }

  Future<void> _startPlayback(AudioTrack track) async {
    try {
      setState(() {
        _errorMessage = null;
      });
      await _audioService.playTrack(track);
    } catch (error, stackTrace) {
      debugPrint(
        'AudioPlayerScreen: startPlayback failed. '
        'trackId=${track.id}, url=${track.url}, '
        'errorType=${error.runtimeType}, error=$error',
      );
      debugPrintStack(
        label: 'AudioPlayerScreen: startPlayback stackTrace',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Nie udało się odtworzyć audio. Sprawdź połączenie z internetem.';
      });
    }
  }

  Future<void> _loadAdjacentTracks() async {
    final track = _track;
    setState(() {
      _isLoadingAdjacentTracks = true;
    });

    BookChapter? previousChapter;
    BookChapter? nextChapter;
    try {
      final reference = _chapterReferenceForTrack(track);
      previousChapter = await _bookRepository.getPreviousChapter(reference);
      nextChapter = await _bookRepository.getNextChapter(reference);
    } catch (error, stackTrace) {
      debugPrint(
        'AudioPlayerScreen: adjacent track lookup failed. '
        'trackId=${track.id}, errorType=${error.runtimeType}, error=$error',
      );
      debugPrintStack(
        label: 'AudioPlayerScreen: adjacent track lookup stackTrace',
        stackTrace: stackTrace,
      );
    }

    if (!mounted || _track.id != track.id) return;

    setState(() {
      _previousTrack = _audioTrackForChapter(previousChapter);
      _nextTrack = _audioTrackForChapter(nextChapter);
      _isLoadingAdjacentTracks = false;
    });
  }

  Future<void> _changeTrack(AudioTrack? track) async {
    if (track == null || _isChangingTrack) return;

    setState(() {
      _track = track;
      _errorMessage = null;
      _previousTrack = null;
      _nextTrack = null;
      _isChangingTrack = true;
      _handledCompletedTrack = false;
    });

    try {
      await _loadAdjacentTracks();
      await _startPlayback(track);
    } finally {
      if (mounted && _track.id == track.id) {
        setState(() {
          _isChangingTrack = false;
        });
      }
    }
  }

  void _handlePlayerStateChanged(PlayerState state) {
    if (state.processingState != ProcessingState.completed) {
      _handledCompletedTrack = false;
      return;
    }

    if (_handledCompletedTrack) return;
    _handledCompletedTrack = true;

    if (!_autoAdvanceEnabled || _nextTrack == null) return;
    unawaited(_changeTrack(_nextTrack));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nagranie lektorskie'),
        actions: [
          IconButton(
            tooltip: 'Wybierz rozdział',
            onPressed: _showChapterPicker,
            icon: const Icon(Icons.format_list_bulleted_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          children: [
            _buildCoverBlock(context),
            const SizedBox(height: 20),
            Text(
              _track.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rozdział ${_track.chapterNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _track.title,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.fade,
              softWrap: true,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null) ...[
              _buildErrorMessage(context),
              const SizedBox(height: 16),
            ],
            _buildProgress(context),
            const SizedBox(height: 18),
            _buildControls(context),
            const SizedBox(height: 12),
            _buildAutoAdvanceToggle(context),
          ],
        ),
      ),
    );
  }

  void _showChapterPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: FutureBuilder<BookCollection>(
            future: _bookRepository.getCollection(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      'Błąd wczytywania listy rozdziałów:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final collection = snapshot.data;
              final books = collection?.books ?? const <Book>[];
              if (books.isEmpty) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: Text('Brak ksiąg w kolekcji')),
                );
              }

              return _buildChapterPickerSheet(context, books);
            },
          ),
        );
      },
    );
  }

  Widget _buildChapterPickerSheet(BuildContext context, List<Book> books) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentReference = _chapterReferenceForTrack(_track);

    var selectedBookIndex = books.indexWhere(
      (book) =>
          book.chapters.any((chapter) => chapter.reference == currentReference),
    );
    if (selectedBookIndex < 0) selectedBookIndex = 0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final selectedBook = books[selectedBookIndex];
            final audioChapters = selectedBook.chapters
                .where((chapter) => _audioTrackForChapter(chapter) != null)
                .toList();

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Wybierz księgę i rozdział',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: books.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final book = books[index];
                        final isSelected = index == selectedBookIndex;

                        return ChoiceChip(
                          label: Text(
                            'Księga ${book.code}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setModalState(() {
                              selectedBookIndex = index;
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: audioChapters.isEmpty
                        ? const Center(
                            child: Text('Brak nagrań dla tej księgi'),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: audioChapters.length,
                            itemBuilder: (context, index) {
                              final chapter = audioChapters[index];
                              final isCurrent =
                                  chapter.reference == currentReference;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(chapter.title),
                                subtitle: Text(
                                  'Rozdział ${chapter.number} · ${chapter.reference}',
                                ),
                                trailing: isCurrent
                                    ? Icon(
                                        Icons.check,
                                        color: colorScheme.primary,
                                      )
                                    : null,
                                onTap: () {
                                  final track = _audioTrackForChapter(chapter);
                                  Navigator.of(context).pop();
                                  unawaited(_changeTrack(track));
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCoverBlock(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 156,
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.28)),
      ),
      child: Center(
        child: Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primary.withValues(alpha: 0.14),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.42),
            ),
          ),
          child: Icon(
            Icons.headphones_rounded,
            size: 42,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
      ),
      child: Text(
        _errorMessage!,
        textAlign: TextAlign.center,
        style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.86)),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: _audioService.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;

        return StreamBuilder<Duration>(
          stream: _audioService.positionStream,
          builder: (context, positionSnapshot) {
            final position = _clampPosition(
              positionSnapshot.data ?? Duration.zero,
              duration,
            );

            return Column(
              children: [
                Slider(
                  value: position.inMilliseconds.toDouble(),
                  max: duration.inMilliseconds > 0
                      ? duration.inMilliseconds.toDouble()
                      : 1,
                  onChanged: duration == Duration.zero
                      ? null
                      : (value) => unawaited(
                          _audioService.seek(
                            Duration(milliseconds: value.round()),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position)),
                      Text(_formatDuration(duration)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PlayerState>(
      stream: _audioService.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final processingState = playerState?.processingState;
        final isLoading =
            processingState == ProcessingState.loading ||
            processingState == ProcessingState.buffering;
        final isPlaying = playerState?.playing ?? false;
        final isBusy = _isLoadingAdjacentTracks || _isChangingTrack;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSeekButton(
              tooltip: 'Cofnij o 10 sekund',
              label: '-10',
              onPressed: isLoading
                  ? null
                  : () => unawaited(
                      _audioService.seekRelative(const Duration(seconds: -10)),
                    ),
            ),
            const SizedBox(width: 8),
            _buildTransportButton(
              tooltip: 'Poprzedni rozdział',
              icon: Icons.skip_previous_rounded,
              onPressed: isBusy || _previousTrack == null
                  ? null
                  : () => unawaited(_changeTrack(_previousTrack)),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              height: 76,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                onPressed: isLoading
                    ? null
                    : () => unawaited(
                        isPlaying ? _audioService.pause() : _togglePlay(),
                      ),
                child: isLoading
                    ? SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow,
                        size: 42,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            _buildTransportButton(
              tooltip: 'Następny rozdział',
              icon: Icons.skip_next_rounded,
              onPressed: isBusy || _nextTrack == null
                  ? null
                  : () => unawaited(_changeTrack(_nextTrack)),
            ),
            const SizedBox(width: 8),
            _buildSeekButton(
              tooltip: 'Przewiń o 10 sekund',
              label: '+10',
              onPressed: isLoading
                  ? null
                  : () => unawaited(
                      _audioService.seekRelative(const Duration(seconds: 10)),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransportButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }

  Widget _buildSeekButton({
    required String tooltip,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildAutoAdvanceToggle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.playlist_play_rounded,
            color: _autoAdvanceEnabled
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.68),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Autoodtwarzanie kolejnych rozdziałów',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.88),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: _autoAdvanceEnabled,
            onChanged: (value) => unawaited(_setAutoAdvanceEnabled(value)),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlay() async {
    try {
      setState(() {
        _errorMessage = null;
      });
      if (_audioService.currentTrack?.id == _track.id) {
        await _audioService.resume();
      } else {
        await _audioService.playTrack(_track);
      }
    } catch (error, stackTrace) {
      debugPrint(
        'AudioPlayerScreen: togglePlay failed. '
        'trackId=${_track.id}, url=${_track.url}, '
        'errorType=${error.runtimeType}, error=$error',
      );
      debugPrintStack(
        label: 'AudioPlayerScreen: togglePlay stackTrace',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Nie udało się odtworzyć audio. Sprawdź połączenie z internetem.';
      });
    }
  }

  AudioTrack? _audioTrackForChapter(BookChapter? chapter) {
    if (chapter == null) return null;

    return AudioCatalog.trackForChapter(
      chapterReference: chapter.reference,
      title: chapter.title,
      subtitle: _bookTitleForReference(chapter.reference),
    );
  }

  String _chapterReferenceForTrack(AudioTrack track) {
    return '${_bookCodeForNumber(track.bookNumber)}-${track.chapterNumber}';
  }

  String _bookCodeForNumber(int bookNumber) {
    return switch (bookNumber) {
      1 => 'I',
      2 => 'II',
      3 => 'III',
      4 => 'IV',
      _ => bookNumber.toString(),
    };
  }

  String _bookTitleForReference(String chapterReference) {
    final bookCode = chapterReference.split('-').first;

    return switch (bookCode) {
      'I' => 'Księga pierwsza',
      'II' => 'Księga druga',
      'III' => 'Księga trzecia',
      'IV' => 'Księga czwarta',
      _ => 'Księga $bookCode',
    };
  }

  Duration _clampPosition(Duration position, Duration duration) {
    if (duration == Duration.zero) return position;
    if (position > duration) return duration;
    return position;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }
}
