import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../shared/layout/responsive_layout.dart';
import '../../../shared/navigation/app_page_route.dart';
import '../data/audio_track.dart';
import '../services/app_audio_player_service.dart';
import 'audio_player_screen.dart';

class InlineAudioPlayerCard extends StatefulWidget {
  final AudioTrack track;
  final int keepScreenOnRefreshToken;

  const InlineAudioPlayerCard({
    super.key,
    required this.track,
    this.keepScreenOnRefreshToken = 0,
  });

  @override
  State<InlineAudioPlayerCard> createState() => _InlineAudioPlayerCardState();
}

class _InlineAudioPlayerCardState extends State<InlineAudioPlayerCard>
    with WidgetsBindingObserver {
  final AppAudioPlayerService _audioService = AppAudioPlayerService.instance;

  StreamSubscription<PlaybackEvent>? _playbackErrorSubscription;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    unawaited(_applyKeepScreenOnSetting());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackErrorSubscription?.cancel();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InlineAudioPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepScreenOnRefreshToken != widget.keepScreenOnRefreshToken) {
      unawaited(_applyKeepScreenOnSetting());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_applyKeepScreenOnSetting());
    }
  }

  bool get _isCurrentTrack => _audioService.currentTrack?.id == widget.track.id;

  Future<void> _applyKeepScreenOnSetting() async {
    final keepScreenOn = await _audioService.getKeepScreenOnInPlayer();
    if (!mounted) return;

    if (keepScreenOn) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompact = context.isCompactAndroid;

    return Container(
      padding: EdgeInsets.fromLTRB(
        context.layoutValue(16, compact: 12),
        context.layoutValue(14, compact: 8),
        context.layoutValue(16, compact: 12),
        context.layoutValue(16, compact: 8),
      ),
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
                  SizedBox(width: context.layoutValue(10, compact: 8)),
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
                        SizedBox(height: context.layoutValue(4, compact: 1)),
                        Text(
                          '${widget.track.subtitle} · Rozdział ${widget.track.chapterNumber}',
                          maxLines: isCompact ? 1 : null,
                          overflow: isCompact
                              ? TextOverflow.ellipsis
                              : TextOverflow.visible,
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                          ),
                        ),
                        SizedBox(height: context.layoutValue(6, compact: 2)),
                        Text(
                          widget.track.title,
                          maxLines: isCompact ? 3 : null,
                          overflow: isCompact
                              ? TextOverflow.ellipsis
                              : TextOverflow.visible,
                          style: TextStyle(
                            fontSize: isCompact ? 13.5 : null,
                            height: isCompact ? 1.18 : 1.28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Pełny odtwarzacz',
                    onPressed: _openFullPlayer,
                    icon: const Icon(Icons.open_in_full_rounded),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                SizedBox(height: context.layoutValue(12, compact: 6)),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: colorScheme.error.withValues(alpha: 0.9),
                    height: 1.3,
                  ),
                ),
              ],
              SizedBox(height: context.layoutValue(14, compact: 4)),
              _buildProgress(isCurrentTrack),
              SizedBox(height: context.layoutValue(12, compact: 6)),
              _buildControls(isCurrentTrack),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgress(bool isCurrentTrack) {
    return _InlineAudioProgressSlider(
      audioService: _audioService,
      isCurrentTrack: isCurrentTrack,
    );
  }

  Widget _buildControls(bool isCurrentTrack) {
    return RepaintBoundary(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _InlineAudioSeekButton(
            tooltip: 'Cofnij o 10 sekund',
            label: '-10',
            onPressed: !isCurrentTrack
                ? null
                : () => unawaited(
                    _audioService.seekRelative(const Duration(seconds: -10)),
                  ),
          ),
          SizedBox(width: context.layoutValue(16, compact: 12)),
          _InlineAudioPlayPauseButton(
            audioService: _audioService,
            isCurrentTrack: isCurrentTrack,
            onPlayOrResume: _playOrResume,
            size: context.layoutValue(58, compact: 52),
            iconSize: context.layoutValue(34, compact: 30),
          ),
          SizedBox(width: context.layoutValue(16, compact: 12)),
          _InlineAudioSeekButton(
            tooltip: 'Przewiń o 10 sekund',
            label: '+10',
            onPressed: !isCurrentTrack
                ? null
                : () => unawaited(
                    _audioService.seekRelative(const Duration(seconds: 10)),
                  ),
          ),
        ],
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

  Future<void> _openFullPlayer() async {
    final currentTrack = _audioService.currentTrack;
    final track = currentTrack?.id == widget.track.id
        ? currentTrack!
        : widget.track;

    await Navigator.of(
      context,
    ).push(AppPageRoute.fade(builder: (_) => AudioPlayerScreen(track: track)));
    if (!mounted) return;

    await _applyKeepScreenOnSetting();
  }
}

class _InlineAudioPlayPauseButton extends StatelessWidget {
  final AppAudioPlayerService audioService;
  final bool isCurrentTrack;
  final Future<void> Function() onPlayOrResume;
  final double size;
  final double iconSize;

  const _InlineAudioPlayPauseButton({
    required this.audioService,
    required this.isCurrentTrack,
    required this.onPlayOrResume,
    this.size = 58,
    this.iconSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PlayerState>(
      stream: audioService.playerStateStream.distinct(
        (previous, next) =>
            _InlineAudioPlayPauseState.fromPlayerState(
              previous,
              isCurrentTrack: isCurrentTrack,
            ) ==
            _InlineAudioPlayPauseState.fromPlayerState(
              next,
              isCurrentTrack: isCurrentTrack,
            ),
      ),
      builder: (context, snapshot) {
        final buttonState = _InlineAudioPlayPauseState.fromPlayerState(
          snapshot.data,
          isCurrentTrack: isCurrentTrack,
        );

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
                        : onPlayOrResume(),
                  ),
            child: buttonState.isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.3,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : Icon(
                    buttonState.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow,
                    size: iconSize,
                  ),
          ),
        );
      },
    );
  }
}

class _InlineAudioPlayPauseState {
  final bool isPlaying;
  final bool isLoading;

  const _InlineAudioPlayPauseState({
    required this.isPlaying,
    required this.isLoading,
  });

  factory _InlineAudioPlayPauseState.fromPlayerState(
    PlayerState? state, {
    required bool isCurrentTrack,
  }) {
    return _InlineAudioPlayPauseState(
      isPlaying: isCurrentTrack && (state?.playing ?? false),
      isLoading:
          isCurrentTrack && state?.processingState == ProcessingState.loading,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _InlineAudioPlayPauseState &&
        other.isPlaying == isPlaying &&
        other.isLoading == isLoading;
  }

  @override
  int get hashCode => Object.hash(isPlaying, isLoading);
}

class _InlineAudioSeekButton extends StatelessWidget {
  final String tooltip;
  final String label;
  final VoidCallback? onPressed;

  const _InlineAudioSeekButton({
    required this.tooltip,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
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
}

class _InlineAudioProgressSlider extends StatefulWidget {
  final AppAudioPlayerService audioService;
  final bool isCurrentTrack;

  const _InlineAudioProgressSlider({
    required this.audioService,
    required this.isCurrentTrack,
  });

  @override
  State<_InlineAudioProgressSlider> createState() =>
      _InlineAudioProgressSliderState();
}

class _InlineAudioProgressSliderState
    extends State<_InlineAudioProgressSlider> {
  bool _isDraggingProgress = false;
  Duration _dragPosition = Duration.zero;

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompactAndroid;

    return StreamBuilder<Duration?>(
      stream: widget.audioService.durationStream,
      builder: (context, durationSnapshot) {
        final duration = widget.isCurrentTrack
            ? durationSnapshot.data ?? Duration.zero
            : Duration.zero;

        return StreamBuilder<Duration>(
          stream: widget.audioService.positionStream,
          builder: (context, positionSnapshot) {
            final streamedPosition = widget.isCurrentTrack
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
                SliderTheme(
                  data: SliderTheme.of(
                    context,
                  ).copyWith(trackHeight: isCompact ? 3 : null),
                  child: Slider(
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
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.layoutValue(0, compact: 4),
                  ),
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
