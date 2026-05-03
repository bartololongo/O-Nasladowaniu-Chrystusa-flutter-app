import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../data/audio_track.dart';
import '../services/app_audio_player_service.dart';

class InlineAudioPlayerCard extends StatefulWidget {
  final AudioTrack track;

  const InlineAudioPlayerCard({super.key, required this.track});

  @override
  State<InlineAudioPlayerCard> createState() => _InlineAudioPlayerCardState();
}

class _InlineAudioPlayerCardState extends State<InlineAudioPlayerCard> {
  final AppAudioPlayerService _audioService = AppAudioPlayerService.instance;

  StreamSubscription<PlaybackEvent>? _playbackErrorSubscription;
  String? _errorMessage;
  bool _isDraggingProgress = false;
  Duration _dragPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _playbackErrorSubscription = _audioService.playbackEventStream.listen(
      (_) {},
      onError: (_) {
        if (!mounted || !_isCurrentTrack) return;
        setState(() {
          _errorMessage =
              'Nie udało się odtworzyć audio. Sprawdź połączenie z internetem.';
        });
      },
    );
  }

  @override
  void dispose() {
    _playbackErrorSubscription?.cancel();
    super.dispose();
  }

  bool get _isCurrentTrack => _audioService.currentTrack?.id == widget.track.id;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: StreamBuilder<AudioTrack?>(
        stream: _audioService.currentTrackStream,
        initialData: _audioService.currentTrack,
        builder: (context, currentTrackSnapshot) {
          final isCurrentTrack =
              currentTrackSnapshot.data?.id == widget.track.id;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.headphones_rounded, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nagranie lektorskie',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.track.subtitle} · Rozdział ${widget.track.chapterNumber}',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.track.title,
                          style: const TextStyle(height: 1.28),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: colorScheme.error.withValues(alpha: 0.9),
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _buildProgress(isCurrentTrack),
              const SizedBox(height: 12),
              _buildControls(isCurrentTrack),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgress(bool isCurrentTrack) {
    return StreamBuilder<Duration?>(
      stream: _audioService.durationStream,
      builder: (context, durationSnapshot) {
        final duration = isCurrentTrack
            ? durationSnapshot.data ?? Duration.zero
            : Duration.zero;

        return StreamBuilder<Duration>(
          stream: _audioService.positionStream,
          builder: (context, positionSnapshot) {
            final streamedPosition = isCurrentTrack
                ? _clampPosition(
                    positionSnapshot.data ?? Duration.zero,
                    duration,
                  )
                : Duration.zero;
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(position)),
                    Text(_formatDuration(duration)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls(bool isCurrentTrack) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PlayerState>(
      stream: _audioService.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final processingState = playerState?.processingState;
        final isLoading =
            isCurrentTrack &&
            (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering);
        final isPlaying = isCurrentTrack && (playerState?.playing ?? false);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSeekButton(
              tooltip: 'Cofnij o 10 sekund',
              label: '-10',
              onPressed: !isCurrentTrack || isLoading
                  ? null
                  : () => unawaited(
                      _audioService.seekRelative(const Duration(seconds: -10)),
                    ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 58,
              height: 58,
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
                        isPlaying ? _audioService.pause() : _playOrResume(),
                      ),
                child: isLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow,
                        size: 34,
                      ),
              ),
            ),
            const SizedBox(width: 16),
            _buildSeekButton(
              tooltip: 'Przewiń o 10 sekund',
              label: '+10',
              onPressed: !isCurrentTrack || isLoading
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

  Future<void> _playOrResume() async {
    try {
      setState(() {
        _errorMessage = null;
      });

      if (_isCurrentTrack) {
        await _audioService.resume();
      } else {
        await _audioService.playTrack(widget.track);
      }
    } catch (_) {
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

  Duration _durationFromSliderValue(double value, Duration duration) {
    final maxMilliseconds = duration.inMilliseconds;
    if (maxMilliseconds <= 0) return Duration.zero;

    final milliseconds = value.round().clamp(0, maxMilliseconds);
    return Duration(milliseconds: milliseconds);
  }

  Future<void> _seekToSliderValue(double value, Duration duration) async {
    final target = _durationFromSliderValue(value, duration);
    try {
      await _audioService.seek(target);
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
