import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/audio_track.dart';

class AppAudioPlayerService {
  AppAudioPlayerService._();

  static final AppAudioPlayerService instance = AppAudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  final StreamController<AudioTrack?> _currentTrackController =
      StreamController<AudioTrack?>.broadcast();

  AudioTrack? _currentTrack;
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _saveTimer;

  AudioTrack? get currentTrack => _currentTrack;

  Stream<AudioTrack?> get currentTrackStream => _currentTrackController.stream;

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<PlaybackEvent> get playbackEventStream => _player.playbackEventStream;

  Future<void> playTrack(AudioTrack track) async {
    if (_currentTrack?.id != track.id) {
      await _saveCurrentPosition();
      _currentTrack = track;
      _currentTrackController.add(track);
      await _player.setUrl(track.url);
      final savedPosition = await _getSavedPosition(track);
      final duration = _player.duration;
      if (_isRestorablePosition(savedPosition, duration)) {
        await _player.seek(savedPosition);
      }
    }

    await _saveLastTrack(track);
    _startPositionPersistence();
    await _player.play();
  }

  Future<void> pause() async {
    await _saveCurrentPosition();
    await _player.pause();
  }

  Future<void> resume() async {
    await _saveLastTrack(_currentTrack);
    _startPositionPersistence();
    await _player.play();
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

  void _startPositionPersistence() {
    _positionSubscription ??= _player.positionStream.listen((_) {
      _saveTimer ??= Timer(const Duration(seconds: 5), () {
        _saveTimer = null;
        unawaited(_saveCurrentPosition());
      });
    });
  }

  bool _isRestorablePosition(Duration position, Duration? duration) {
    if (position < const Duration(seconds: 5)) return false;
    if (duration == null) return true;

    return position < duration - const Duration(seconds: 10);
  }

  Future<Duration> _getSavedPosition(AudioTrack track) async {
    final preferences = await SharedPreferences.getInstance();
    final milliseconds = preferences.getInt(_positionKey(track.id)) ?? 0;
    return Duration(milliseconds: milliseconds);
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

  String _positionKey(String trackId) => 'audio_position_ms_$trackId';

  static const String _lastTrackKey = 'audio_last_track_id';
}
