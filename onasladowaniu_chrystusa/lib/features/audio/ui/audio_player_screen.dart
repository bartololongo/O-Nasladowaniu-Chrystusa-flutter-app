import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../shared/models/book_models.dart';
import '../../../shared/navigation/app_page_route.dart';
import '../../../shared/services/book_repository.dart';
import '../data/audio_catalog.dart';
import '../data/audio_track.dart';
import '../services/app_audio_player_service.dart';
import '../../settings/settings_screen.dart';

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
    unawaited(_audioService.initializePlaybackSpeed());
    unawaited(_applyKeepScreenOnSetting());
    unawaited(_loadAutoAdvanceSetting());
    unawaited(_loadAdjacentTracks());
    unawaited(_startPlayback(_track));
  }

  @override
  void dispose() {
    _playbackErrorSubscription?.cancel();
    _playerStateSubscription?.cancel();
    unawaited(WakelockPlus.disable());
    unawaited(_audioService.pause());
    super.dispose();
  }

  Future<void> _applyKeepScreenOnSetting() async {
    final keepScreenOn = await _audioService.getKeepScreenOnInPlayer();
    if (!mounted) {
      await WakelockPlus.disable();
      return;
    }

    if (keepScreenOn) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
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
                  _buildProgressActions(context),
                  const SizedBox(height: 8),
                  _buildProgress(context),
                  const SizedBox(height: 2),
                  _buildControls(context),
                  const SizedBox(height: 28),
                  _buildAutoAdvanceToggle(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Wstecz',
          ),
          const SizedBox(width: 4),
          Icon(Icons.headphones_rounded, size: 28, color: colorScheme.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Nagranie lektorskie',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Wybierz rozdział',
            onPressed: _showChapterPicker,
            icon: const Icon(Icons.format_list_bulleted_rounded),
          ),
          IconButton(
            tooltip: 'Ustawienia',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => const SettingsScreen(),
      ),
    );
    if (!mounted) return;

    await _applyKeepScreenOnSetting();
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
                                subtitle: Text('Rozdział ${chapter.number}'),
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

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final artworkSize = constraints.maxWidth.clamp(0.0, 240.0);

          return Container(
            width: artworkSize,
            height: artworkSize,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.28),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/audio/lockscreen_artwork.png',
                  fit: BoxFit.cover,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          );
        },
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
    return _AudioProgressSlider(audioService: _audioService);
  }

  Widget _buildProgressActions(BuildContext context) {
    return Row(
      children: [
        _buildPlaybackSpeedButton(context),
        const SizedBox(width: 10),
        _AudioSeekButton(
          tooltip: 'Cofnij o 10 sekund',
          label: '-10',
          size: 42,
          fontSize: 13,
          onPressed: () => unawaited(
            _audioService.seekRelative(const Duration(seconds: -10)),
          ),
        ),
        const SizedBox(width: 8),
        _AudioSeekButton(
          tooltip: 'Przewiń o 10 sekund',
          label: '+10',
          size: 42,
          fontSize: 13,
          onPressed: () => unawaited(
            _audioService.seekRelative(const Duration(seconds: 10)),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    final isBusy = _isLoadingAdjacentTracks || _isChangingTrack;

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 310;
          final transportSize = isCompact ? 64.0 : 76.0;
          final playSize = isCompact ? 72.0 : 76.0;
          final spacing = isCompact ? 24.0 : 42.0;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StreamBuilder<Duration>(
                stream: _audioService.positionStream,
                initialData: _audioService.currentPosition,
                builder: (context, snapshot) {
                  final canRestartCurrentTrack =
                      (snapshot.data ?? Duration.zero) >
                      _previousTrackRestartThreshold;
                  final canUsePreviousButton =
                      !isBusy &&
                      (canRestartCurrentTrack || _previousTrack != null);

                  return _AudioTransportButton(
                    tooltip: 'Poprzedni rozdział',
                    icon: Icons.skip_previous_rounded,
                    size: transportSize,
                    iconSize: isCompact ? 44 : 52,
                    onPressed: canUsePreviousButton
                        ? () => unawaited(_restartOrChangeToPreviousTrack())
                        : null,
                  );
                },
              ),
              SizedBox(width: spacing),
              _AudioPlayPauseButton(
                size: playSize,
                audioService: _audioService,
                onTogglePlay: _togglePlay,
              ),
              SizedBox(width: spacing),
              _AudioTransportButton(
                tooltip: 'Następny rozdział',
                icon: Icons.skip_next_rounded,
                size: transportSize,
                iconSize: isCompact ? 44 : 52,
                onPressed: isBusy || _nextTrack == null
                    ? null
                    : () => unawaited(_changeTrack(_nextTrack)),
              ),
            ],
          );
        },
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

  Widget _buildPlaybackSpeedButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.center,
      child: StreamBuilder<double>(
        stream: _audioService.playbackSpeedStream,
        initialData: _audioService.playbackSpeed,
        builder: (context, snapshot) {
          final speed =
              snapshot.data ?? AppAudioPlayerService.defaultPlaybackSpeed;

          return FilledButton.tonalIcon(
            onPressed: _showPlaybackSpeedSheet,
            icon: const Icon(Icons.speed_rounded),
            label: Text(_formatPlaybackSpeed(speed)),
            style: FilledButton.styleFrom(
              foregroundColor: colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          );
        },
      ),
    );
  }

  void _showPlaybackSpeedSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: StreamBuilder<double>(
              stream: _audioService.playbackSpeedStream,
              initialData: _audioService.playbackSpeed,
              builder: (context, snapshot) {
                final currentSpeed =
                    snapshot.data ?? AppAudioPlayerService.defaultPlaybackSpeed;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Tempo odtwarzania',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Wybierz tempo dla nagrania lektorskiego.',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final speed
                            in AppAudioPlayerService.availablePlaybackSpeeds)
                          ChoiceChip(
                            label: Text(_formatPlaybackSpeed(speed)),
                            selected: _isSamePlaybackSpeed(currentSpeed, speed),
                            onSelected: (_) {
                              unawaited(_audioService.setPlaybackSpeed(speed));
                              Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  bool _isSamePlaybackSpeed(double first, double second) {
    return (first - second).abs() < 0.001;
  }

  String _formatPlaybackSpeed(double speed) {
    if ((speed - speed.roundToDouble()).abs() < 0.001) {
      return '${speed.toStringAsFixed(1)}x';
    }

    if (((speed * 10).roundToDouble() - speed * 10).abs() < 0.001) {
      return '${speed.toStringAsFixed(1)}x';
    }

    return '${speed.toStringAsFixed(2)}x';
  }

  Future<void> _restartOrChangeToPreviousTrack() async {
    if (_audioService.currentPosition > _previousTrackRestartThreshold) {
      await _audioService.seek(Duration.zero);
      return;
    }

    await _changeTrack(_previousTrack);
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

  static const Duration _previousTrackRestartThreshold = Duration(seconds: 3);
}

class _AudioProgressSlider extends StatefulWidget {
  final AppAudioPlayerService audioService;

  const _AudioProgressSlider({required this.audioService});

  @override
  State<_AudioProgressSlider> createState() => _AudioProgressSliderState();
}

class _AudioProgressSliderState extends State<_AudioProgressSlider> {
  bool _isDraggingProgress = false;
  Duration _dragPosition = Duration.zero;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: widget.audioService.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;

        return StreamBuilder<Duration>(
          stream: widget.audioService.positionStream,
          builder: (context, positionSnapshot) {
            final streamedPosition = _clampPosition(
              positionSnapshot.data ?? Duration.zero,
              duration,
            );
            final position = _isDraggingProgress
                ? _clampPosition(_dragPosition, duration)
                : streamedPosition;

            return Column(
              children: [
                Slider(
                  value: position.inMilliseconds.toDouble(),
                  max: duration.inMilliseconds > 0
                      ? duration.inMilliseconds.toDouble()
                      : 1,
                  onChanged: duration == Duration.zero
                      ? null
                      : (value) {
                          setState(() {
                            _isDraggingProgress = true;
                            _dragPosition = _durationFromSliderValue(
                              value,
                              duration,
                            );
                          });
                        },
                  onChangeEnd: duration == Duration.zero
                      ? null
                      : (value) =>
                            unawaited(_seekToSliderValue(value, duration)),
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

  Duration _clampPosition(Duration position, Duration duration) {
    if (duration == Duration.zero) return position;
    if (position > duration) return duration;
    return position;
  }

  Duration _durationFromSliderValue(double value, Duration duration) {
    final maxMilliseconds = duration.inMilliseconds;
    if (maxMilliseconds <= 0) return Duration.zero;

    final milliseconds = value.round().clamp(0, maxMilliseconds);
    return Duration(milliseconds: milliseconds);
  }

  Future<void> _seekToSliderValue(double value, Duration duration) async {
    final target = _durationFromSliderValue(value, duration);
    try {
      await widget.audioService.seek(target);
    } finally {
      if (mounted) {
        setState(() {
          _dragPosition = target;
          _isDraggingProgress = false;
        });
      }
    }
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

class _AudioPlayPauseButton extends StatelessWidget {
  final double size;
  final AppAudioPlayerService audioService;
  final Future<void> Function() onTogglePlay;

  const _AudioPlayPauseButton({
    this.size = 76,
    required this.audioService,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PlayerState>(
      stream: audioService.playerStateStream.distinct(
        (previous, next) =>
            _AudioPlayPauseState.fromPlayerState(previous) ==
            _AudioPlayPauseState.fromPlayerState(next),
      ),
      builder: (context, snapshot) {
        final buttonState = _AudioPlayPauseState.fromPlayerState(snapshot.data);

        return SizedBox(
          width: size,
          height: size,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            onPressed: buttonState.isLoading
                ? null
                : () => unawaited(
                    buttonState.isPlaying
                        ? audioService.pause()
                        : onTogglePlay(),
                  ),
            child: buttonState.isLoading
                ? SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : Icon(
                    buttonState.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow,
                    size: size * 0.55,
                  ),
          ),
        );
      },
    );
  }
}

class _AudioPlayPauseState {
  final bool isPlaying;
  final bool isLoading;

  const _AudioPlayPauseState({
    required this.isPlaying,
    required this.isLoading,
  });

  factory _AudioPlayPauseState.fromPlayerState(PlayerState? state) {
    return _AudioPlayPauseState(
      isPlaying: state?.playing ?? false,
      isLoading: state?.processingState == ProcessingState.loading,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _AudioPlayPauseState &&
        other.isPlaying == isPlaying &&
        other.isLoading == isLoading;
  }

  @override
  int get hashCode => Object.hash(isPlaying, isLoading);
}

class _AudioTransportButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  const _AudioTransportButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: colorScheme.primary,
        disabledColor: colorScheme.onSurface.withValues(alpha: 0.28),
        icon: Icon(icon, size: iconSize),
      ),
    );
  }
}

class _AudioSeekButton extends StatelessWidget {
  final String tooltip;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double fontSize;

  const _AudioSeekButton({
    required this.tooltip,
    required this.label,
    required this.onPressed,
    this.size = 44,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Text(
          label,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
