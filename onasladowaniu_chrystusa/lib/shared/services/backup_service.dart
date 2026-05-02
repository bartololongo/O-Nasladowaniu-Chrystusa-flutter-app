import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Serwis do backupu i przywracania danych aplikacji.
///
/// Zamiast wołać metody poszczególnych serwisów (Journal, Favorites, Bookmarks,
/// ReadingChallenge, Preferences), backupuje po prostu cały stan
/// SharedPreferences, w którym te serwisy trzymają swoje dane.
///
/// Format backupu:
/// {
///   "app_id": "o_nasladowaniu_chrystusa",
///   "schema_version": 1,
///   "created_at": "2025-11-28T19:00:00.000Z",
///   "data": {
///     "shared_preferences": {
///       "jakiś_klucz": 123,
///       "inny_klucz": "wartość",
///       "lista": ["a", "b", "c"]
///     }
///   }
/// }
class BackupService {
  static const String appId = 'o_nasladowaniu_chrystusa';
  static const int schemaVersion = 1;
  static const String _formationPendingPayloadKey = 'formation_pending_payload';
  static const String _audioPositionKeyPrefix = 'audio_position_ms_';
  static const String _audioLastTrackKey = 'audio_last_track_id';

  /// Tworzy strukturę JSON do zapisania w pliku – na podstawie SharedPreferences.
  Future<Map<String, dynamic>> createBackupJson() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    final Map<String, dynamic> prefsData = <String, dynamic>{};
    final Map<String, int> audioPositionsMs = <String, int>{};
    String? audioLastTrackId;

    for (final key in keys) {
      if (key == _formationPendingPayloadKey) {
        continue;
      }

      final value = prefs.get(key);

      if (key.startsWith(_audioPositionKeyPrefix)) {
        if (value is int && value >= 0) {
          final trackId = key.substring(_audioPositionKeyPrefix.length);
          if (trackId.isNotEmpty) {
            audioPositionsMs[trackId] = value;
          }
        }
      } else if (key == _audioLastTrackKey &&
          value is String &&
          value.trim().isNotEmpty) {
        audioLastTrackId = value;
      }

      if (value is bool || value is int || value is double || value is String) {
        prefsData[key] = value;
      } else if (value is List<String>) {
        prefsData[key] = value;
      } else {
        // Nietypowy typ – na razie pomijamy.
      }
    }

    final Map<String, dynamic> audioPlaybackData = <String, dynamic>{
      'positionsMs': audioPositionsMs,
    };
    if (audioLastTrackId != null) {
      audioPlaybackData['lastTrackId'] = audioLastTrackId;
    }
    return <String, dynamic>{
      'app_id': appId,
      'schema_version': schemaVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'data': <String, dynamic>{
        'shared_preferences': prefsData,
        'audioPlayback': audioPlaybackData,
      },
    };
  }

  /// Przywraca dane z JSON-a (SharedPreferences).
  ///
  /// - waliduje app_id i schema_version,
  /// - czyści aktualne SharedPreferences,
  /// - zapisuje wartości z backupu.
  ///
  /// Rzuca [FormatException], jeśli format jest nieprawidłowy.
  Future<void> restoreFromBackupJson(Map<String, dynamic> json) async {
    final rawAppId = json['app_id'];
    if (rawAppId != appId) {
      throw const FormatException(
        'Ten plik nie pochodzi z aplikacji "O naśladowaniu Chrystusa".',
      );
    }

    final rawSchemaVersion = json['schema_version'];
    if (rawSchemaVersion is! int) {
      throw const FormatException(
        'Nieprawidłowa wartość pola "schema_version" w backupie.',
      );
    }

    if (rawSchemaVersion > schemaVersion) {
      throw FormatException(
        'Backup pochodzi z nowszej wersji aplikacji (schema_version=$rawSchemaVersion). '
        'Zaktualizuj aplikację, aby móc go przywrócić.',
      );
    }

    final rawData = json['data'];
    if (rawData is! Map) {
      throw const FormatException(
        'Nieprawidłowy format sekcji "data" w pliku backupu.',
      );
    }

    final dataMap = Map<String, dynamic>.from(rawData as Map);
    final rawPrefsSection = dataMap['shared_preferences'];

    if (rawPrefsSection is! Map) {
      throw const FormatException(
        'Brak lub nieprawidłowa sekcja "shared_preferences" w backupie.',
      );
    }

    final prefsData = Map<String, dynamic>.from(
      rawPrefsSection as Map<Object?, Object?>,
    );
    final audioPlaybackData = dataMap['audioPlayback'];

    final prefs = await SharedPreferences.getInstance();

    // 1) Czyścimy wszystko (uwaga: znika cały stan aplikacji w SharedPreferences)
    await prefs.clear();

    // 2) Zapisujemy z backupu
    for (final entry in prefsData.entries) {
      final key = entry.key;
      final value = entry.value;

      if (!_isValidSharedPreferenceEntry(key, value)) {
        continue;
      }

      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        // Zakładamy, że lista jest listą stringów
        final list = value.whereType<String>().toList();
        await prefs.setStringList(key, list);
      } else {
        // Nietypowy typ – pomijamy.
      }
    }

    await _restoreAudioPlaybackSection(prefs, audioPlaybackData);
  }

  bool _isValidSharedPreferenceEntry(String key, Object? value) {
    if (key.startsWith(_audioPositionKeyPrefix)) {
      final trackId = key.substring(_audioPositionKeyPrefix.length);
      return trackId.isNotEmpty && value is int && value >= 0;
    }

    if (key == _audioLastTrackKey) {
      return value is String && value.trim().isNotEmpty;
    }

    return true;
  }

  Future<void> _restoreAudioPlaybackSection(
    SharedPreferences prefs,
    Object? rawAudioPlaybackSection,
  ) async {
    if (rawAudioPlaybackSection is! Map) return;

    final audioPlaybackSection = Map<String, dynamic>.from(
      rawAudioPlaybackSection as Map<Object?, Object?>,
    );
    final rawPositions = audioPlaybackSection['positionsMs'];

    if (rawPositions is Map) {
      final positions = Map<String, dynamic>.from(
        rawPositions as Map<Object?, Object?>,
      );

      for (final entry in positions.entries) {
        final trackId = entry.key.trim();
        final milliseconds = entry.value;

        if (trackId.isEmpty || milliseconds is! int || milliseconds < 0) {
          continue;
        }

        await prefs.setInt('$_audioPositionKeyPrefix$trackId', milliseconds);
      }
    }

    final lastTrackId = audioPlaybackSection['lastTrackId'];
    if (lastTrackId is String && lastTrackId.trim().isNotEmpty) {
      await prefs.setString(_audioLastTrackKey, lastTrackId);
    }
  }
}
