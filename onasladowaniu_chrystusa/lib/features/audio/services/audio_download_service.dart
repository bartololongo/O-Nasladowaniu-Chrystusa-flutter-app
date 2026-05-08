import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/audio_track.dart';

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
