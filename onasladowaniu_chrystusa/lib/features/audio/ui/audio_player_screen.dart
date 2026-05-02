import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

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

  StreamSubscription<PlaybackEvent>? _playbackErrorSubscription;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _playbackErrorSubscription = _audioService.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'AudioPlayerScreen: playbackEventStream error. '
          'trackId=${widget.track.id}, url=${widget.track.url}, '
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
    unawaited(_startPlayback());
  }

  @override
  void dispose() {
    _playbackErrorSubscription?.cancel();
    unawaited(_audioService.pause());
    super.dispose();
  }

  Future<void> _startPlayback() async {
    try {
      setState(() {
        _errorMessage = null;
      });
      await _audioService.playTrack(widget.track);
    } catch (error, stackTrace) {
      debugPrint(
        'AudioPlayerScreen: startPlayback failed. '
        'trackId=${widget.track.id}, url=${widget.track.url}, '
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nagranie lektorskie')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          children: [
            _buildCoverBlock(context),
            const SizedBox(height: 28),
            Text(
              widget.track.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rozdział ${widget.track.chapterNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.track.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 28),
            if (_errorMessage != null) ...[
              _buildErrorMessage(context),
              const SizedBox(height: 20),
            ],
            _buildProgress(context),
            const SizedBox(height: 24),
            _buildControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverBlock(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.28)),
      ),
      child: Center(
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primary.withValues(alpha: 0.14),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.42),
            ),
          ),
          child: Icon(
            Icons.headphones_rounded,
            size: 56,
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

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: 'Cofnij o 15 sekund',
              onPressed: isLoading
                  ? null
                  : () => unawaited(
                      _audioService.seekRelative(const Duration(seconds: -15)),
                    ),
              icon: const Icon(Icons.replay_rounded),
            ),
            const SizedBox(width: 18),
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
            const SizedBox(width: 18),
            IconButton.filledTonal(
              tooltip: 'Przewiń o 15 sekund',
              onPressed: isLoading
                  ? null
                  : () => unawaited(
                      _audioService.seekRelative(const Duration(seconds: 15)),
                    ),
              icon: const Icon(Icons.forward_rounded),
            ),
          ],
        );
      },
    );
  }

  Future<void> _togglePlay() async {
    try {
      setState(() {
        _errorMessage = null;
      });
      if (_audioService.currentTrack?.id == widget.track.id) {
        await _audioService.resume();
      } else {
        await _audioService.playTrack(widget.track);
      }
    } catch (error, stackTrace) {
      debugPrint(
        'AudioPlayerScreen: togglePlay failed. '
        'trackId=${widget.track.id}, url=${widget.track.url}, '
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
