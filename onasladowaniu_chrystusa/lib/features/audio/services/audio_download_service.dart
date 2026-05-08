import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/audio_track.dart';

class AudioDownloadedTrackInfo {
  final AudioTrack track;
  final File file;
  final int sizeBytes;
  final DateTime? downloadedAt;

  const AudioDownloadedTrackInfo({
    required this.track,
    required this.file,
    required this.sizeBytes,
    required this.downloadedAt,
  });
}

class AudioBatchDownloadResult {
  final int requestedCount;
  final int downloadedCount;
  final int skippedCount;
  final int failedCount;
  final bool cancelled;

  const AudioBatchDownloadResult({
    required this.requestedCount,
    required this.downloadedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.cancelled,
  });
}

class AudioDownloadCancelToken {
  final List<void Function()> _listeners = <void Function()>[];
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;

    _isCancelled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }

    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const AudioDownloadCancelledException();
    }
  }
}

class AudioDownloadCancelledException implements Exception {
  const AudioDownloadCancelledException();
}

class AudioDownloadService {
  const AudioDownloadService();

  Future<bool> isTrackDownloaded(AudioTrack track) async {
    final file = await localFileForTrack(track);
    return file.exists();
  }

  Future<File?> downloadedFileForTrack(AudioTrack track) async {
    final file = await localFileForTrack(track);
    if (await file.exists()) return file;

    return null;
  }

  Future<File> localFileForTrack(AudioTrack track) async {
    final directory = await _downloadsDirectory();
    return File('${directory.path}/${_safeTrackFileName(track)}');
  }

  Future<List<AudioDownloadedTrackInfo>> listDownloads(
    Iterable<AudioTrack> tracks,
  ) async {
    final downloads = <AudioDownloadedTrackInfo>[];

    for (final track in tracks) {
      final file = await downloadedFileForTrack(track);
      if (file == null) continue;

      final stat = await file.stat();
      downloads.add(
        AudioDownloadedTrackInfo(
          track: track,
          file: file,
          sizeBytes: stat.size,
          downloadedAt: stat.modified,
        ),
      );
    }

    downloads.sort((a, b) {
      final bookComparison = a.track.bookNumber.compareTo(b.track.bookNumber);
      if (bookComparison != 0) return bookComparison;

      return a.track.chapterNumber.compareTo(b.track.chapterNumber);
    });

    return downloads;
  }

  Future<int> getTotalDownloadedBytes(Iterable<AudioTrack> tracks) async {
    final downloads = await listDownloads(tracks);
    return downloads.fold<int>(0, (sum, info) => sum + info.sizeBytes);
  }

  Future<List<AudioTrack>> missingDownloads(Iterable<AudioTrack> tracks) async {
    final missingTracks = <AudioTrack>[];

    for (final track in tracks) {
      if (!await isTrackDownloaded(track)) {
        missingTracks.add(track);
      }
    }

    return missingTracks;
  }

  Future<AudioBatchDownloadResult> downloadMissingTracks(
    Iterable<AudioTrack> tracks, {
    AudioDownloadCancelToken? cancelToken,
    void Function(int completed, int total, AudioTrack track)? onProgress,
  }) async {
    final allTracks = tracks.toList(growable: false);
    final missingTracks = await missingDownloads(allTracks);
    var downloadedCount = 0;
    var failedCount = 0;
    var cancelled = false;

    for (final track in missingTracks) {
      if (cancelToken?.isCancelled ?? false) {
        cancelled = true;
        break;
      }

      try {
        await downloadTrack(track, cancelToken: cancelToken);
        downloadedCount += 1;
      } on AudioDownloadCancelledException {
        cancelled = true;
        break;
      } catch (_) {
        failedCount += 1;
      }

      onProgress?.call(
        downloadedCount + failedCount,
        missingTracks.length,
        track,
      );
    }

    return AudioBatchDownloadResult(
      requestedCount: missingTracks.length,
      downloadedCount: downloadedCount,
      skippedCount: allTracks.length - missingTracks.length,
      failedCount: failedCount,
      cancelled: cancelled,
    );
  }

  Future<bool> deleteDownload(AudioTrack track) async {
    final file = await localFileForTrack(track);
    if (!await file.exists()) return false;

    await file.delete();
    return true;
  }

  Future<void> deleteAllDownloads(Iterable<AudioTrack> tracks) async {
    for (final track in tracks) {
      await deleteDownload(track);
    }
  }

  Future<File> downloadTrack(
    AudioTrack track, {
    AudioDownloadCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final targetFile = await localFileForTrack(track);
    if (await targetFile.exists()) return targetFile;

    final directory = targetFile.parent;
    await directory.create(recursive: true);

    final tempFile = File('${targetFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final client = HttpClient();
    void cancelClient() {
      client.close(force: true);
    }

    cancelToken?.addListener(cancelClient);
    try {
      cancelToken?.throwIfCancelled();
      final request = await client.getUrl(Uri.parse(track.url));
      cancelToken?.throwIfCancelled();
      final response = await request.close();
      cancelToken?.throwIfCancelled();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Audio download failed with HTTP ${response.statusCode}',
          uri: Uri.parse(track.url),
        );
      }

      final sink = tempFile.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }
      cancelToken?.throwIfCancelled();

      if (await targetFile.exists()) {
        await tempFile.delete();
        return targetFile;
      }

      return tempFile.rename(targetFile.path);
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (cancelToken?.isCancelled ?? false) {
        throw const AudioDownloadCancelledException();
      }
      rethrow;
    } finally {
      cancelToken?.removeListener(cancelClient);
      client.close(force: true);
    }
  }

  Future<Directory> _downloadsDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/audio/downloads');
  }

  String _safeTrackFileName(AudioTrack track) {
    final safeId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '$safeId.m4a';
  }
}
