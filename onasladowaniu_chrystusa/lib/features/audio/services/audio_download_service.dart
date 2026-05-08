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

  Future<File> downloadTrack(AudioTrack track) async {
    final targetFile = await localFileForTrack(track);
    if (await targetFile.exists()) return targetFile;

    final directory = targetFile.parent;
    await directory.create(recursive: true);

    final tempFile = File('${targetFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(track.url));
      final response = await request.close();

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

      if (await targetFile.exists()) {
        await tempFile.delete();
        return targetFile;
      }

      return tempFile.rename(targetFile.path);
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    } finally {
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
