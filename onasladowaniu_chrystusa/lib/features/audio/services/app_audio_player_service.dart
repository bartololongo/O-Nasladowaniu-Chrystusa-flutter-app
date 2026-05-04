import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/audio_track.dart';

class AppAudioPlayerService {
  AppAudioPlayerService._();

  static final AppAudioPlayerService instance = AppAudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  final StreamController<AudioTrack?> _currentTrackController =
      StreamController<AudioTrack?>.broadcast();
  final StreamController<double> _playbackSpeedController =
      StreamController<double>.broadcast();

  AudioTrack? _currentTrack;
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _saveTimer;
  Future<void>? _audioSessionConfiguration;
  Future<void>? _playbackSpeedInitialization;
  double _playbackSpeed = defaultPlaybackSpeed;

  AudioTrack? get currentTrack => _currentTrack;

  Stream<AudioTrack?> get currentTrackStream => _currentTrackController.stream;

  double get playbackSpeed => _playbackSpeed;

  Stream<double> get playbackSpeedStream => _playbackSpeedController.stream;

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<PlaybackEvent> get playbackEventStream => _player.playbackEventStream;

  Future<bool> getAutoAdvanceEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_autoAdvanceEnabledKey) ?? false;
  }

  Future<void> setAutoAdvanceEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoAdvanceEnabledKey, enabled);
  }

  Future<void> initializePlaybackSpeed() {
    return _playbackSpeedInitialization ??= _loadSavedPlaybackSpeed();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final normalizedSpeed = _normalizePlaybackSpeed(speed);
    await initializePlaybackSpeed();

    _playbackSpeed = normalizedSpeed;
    _playbackSpeedController.add(normalizedSpeed);
    await _player.setSpeed(normalizedSpeed);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_playbackSpeedKey, normalizedSpeed);
  }

  Future<String?> getLastTrackId() async {
    final preferences = await SharedPreferences.getInstance();
    final trackId = preferences.getString(_lastTrackKey);
    if (trackId == null || trackId.trim().isEmpty) return null;

    return trackId;
  }

  Future<void> playTrack(AudioTrack track) async {
    try {
      if (_currentTrack?.id != track.id) {
        await _ensurePlaybackAudioSession();
        await initializePlaybackSpeed();
        await _saveCurrentPosition();
        _currentTrack = track;
        _currentTrackController.add(track);
        await _player.setAudioSource(_audioSourceForTrack(track));
        await _player.setSpeed(_playbackSpeed);
        await _restoreSavedPosition(track);
      } else {
        await _restoreSavedPositionIfPlayerIsAtStart(track);
      }

      await _saveLastTrack(track);
      _startPositionPersistence();
      await _player.play();
    } catch (error, stackTrace) {
      _logPlaybackError(
        action: 'playTrack',
        track: track,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> pause() async {
    await _saveCurrentPosition();
    await _player.pause();
  }

  Future<void> resume() async {
    final track = _currentTrack;
    try {
      await _saveLastTrack(track);
      _startPositionPersistence();
      await _player.play();
    } catch (error, stackTrace) {
      _logPlaybackError(
        action: 'resume',
        track: track,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    await _saveCurrentPosition();
  }

  Future<void> seekRelative(Duration offset) async {
    final duration = _player.duration;
    final currentPosition = _player.position;
    var target = currentPosition + offset;

    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && target > duration) target = duration;

    await seek(target);
  }

  Future<void> stop() async {
    await _saveCurrentPosition();
    _saveTimer?.cancel();
    _saveTimer = null;
    await _player.stop();
  }

  Future<void> clearSavedPlaybackProgress() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final preferences = await SharedPreferences.getInstance();
    final audioKeys = preferences
        .getKeys()
        .where(
          (key) => key.startsWith(_positionKeyPrefix) || key == _lastTrackKey,
        )
        .toList();

    for (final key in audioKeys) {
      await preferences.remove(key);
    }

    if (_currentTrack != null) {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> reloadCurrentTrackSavedPosition() async {
    final track = _currentTrack;
    if (track == null) return;

    await _restoreSavedPosition(track);
  }

  void _startPositionPersistence() {
    _positionSubscription ??= _player.positionStream.listen((_) {
      _saveTimer ??= Timer(const Duration(seconds: 5), () {
        _saveTimer = null;
        unawaited(_saveCurrentPosition());
      });
    });
  }

  Future<void> _ensurePlaybackAudioSession() {
    return _audioSessionConfiguration ??= _configurePlaybackAudioSession();
  }

  Future<void> _configurePlaybackAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  Future<void> _loadSavedPlaybackSpeed() async {
    final preferences = await SharedPreferences.getInstance();
    final savedSpeed = preferences.getDouble(_playbackSpeedKey);
    final speed = _normalizePlaybackSpeed(savedSpeed);

    _playbackSpeed = speed;
    _playbackSpeedController.add(speed);
    await _player.setSpeed(speed);
  }

  double _normalizePlaybackSpeed(double? speed) {
    if (speed == null) return defaultPlaybackSpeed;

    for (final availableSpeed in availablePlaybackSpeeds) {
      if ((availableSpeed - speed).abs() < 0.001) return availableSpeed;
    }

    return defaultPlaybackSpeed;
  }

  AudioSource _audioSourceForTrack(AudioTrack track) {
    return AudioSource.uri(
      Uri.parse(track.url),
      tag: MediaItem(
        id: track.id,
        album: 'O naśladowaniu Chrystusa',
        title: track.title,
        artist: 'Tomasz à Kempis',
        displayTitle: track.title,
        displaySubtitle: track.subtitle,
      ),
    );
  }

  bool _isRestorablePosition(Duration position, Duration? duration) {
    if (position < const Duration(seconds: 5)) return false;
    if (duration == null) return true;

    return position < duration - const Duration(seconds: 10);
  }

  Future<Duration> _getSavedPosition(AudioTrack track) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _positionKey(track.id);
    final milliseconds = preferences.getInt(key) ?? 0;
    return Duration(milliseconds: milliseconds);
  }

  Future<void> _restoreSavedPosition(AudioTrack track) async {
    final savedPosition = await _getSavedPosition(track);
    final duration = _player.duration;
    if (_isRestorablePosition(savedPosition, duration)) {
      await _player.seek(savedPosition);
    }
  }

  Future<void> _restoreSavedPositionIfPlayerIsAtStart(AudioTrack track) async {
    final savedPosition = await _getSavedPosition(track);
    final duration = _player.duration;
    final currentPosition = _player.position;

    if (currentPosition >= const Duration(seconds: 5)) return;
    if (!_isRestorablePosition(savedPosition, duration)) return;

    await _player.seek(savedPosition);
  }

  Future<void> _saveCurrentPosition() async {
    final track = _currentTrack;
    if (track == null) return;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      _positionKey(track.id),
      _player.position.inMilliseconds,
    );
    await _saveLastTrack(track);
  }

  Future<void> _saveLastTrack(AudioTrack? track) async {
    if (track == null) return;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastTrackKey, track.id);
  }

  String _positionKey(String trackId) => '$_positionKeyPrefix$trackId';

  void _logPlaybackError({
    required String action,
    required AudioTrack? track,
    required Object error,
    required StackTrace stackTrace,
  }) {
    debugPrint(
      'AppAudioPlayerService: $action failed. '
      'trackId=${track?.id}, url=${track?.url}, '
      'errorType=${error.runtimeType}, error=$error',
    );
    debugPrintStack(
      label: 'AppAudioPlayerService: $action stackTrace',
      stackTrace: stackTrace,
    );
  }

  static const String _positionKeyPrefix = 'audio_position_ms_';
  static const String _lastTrackKey = 'audio_last_track_id';
  static const String _autoAdvanceEnabledKey = 'audio_auto_advance_enabled';
  static const String _playbackSpeedKey = 'audio.playback.speed';
  static const double defaultPlaybackSpeed = 1.0;
  static const List<double> availablePlaybackSpeeds = [
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];
}
