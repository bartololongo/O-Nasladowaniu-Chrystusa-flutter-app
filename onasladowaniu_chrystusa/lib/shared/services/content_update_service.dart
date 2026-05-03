import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_manifest.dart';
import 'book_repository.dart';

enum ContentUpdateStatus {
  upToDate,
  updated,
  skippedIncompatibleAppVersion,
  manifestUnavailable,
  downloadFailed,
  invalidHash,
  invalidJson,
  unknownError,
}

class ContentUpdateResult {
  final ContentUpdateStatus status;
  final String? localVersion;
  final String? remoteVersion;
  final String? message;

  const ContentUpdateResult({
    required this.status,
    this.localVersion,
    this.remoteVersion,
    this.message,
  });
}

class ContentUpdateService {
  static const String manifestUrl =
      'https://bartololongo.pl/uploads/content/o-nasladowaniu/v1/manifest.json';

  static const Duration _timeout = Duration(seconds: 10);
  static const String _localVersionKey = 'content.book.version';
  static const String _localSha256Key = 'content.book.sha256';
  static const String _updatedAtKey = 'content.book.updatedAt';
  static const String _bundledAppVersion = '1.5.0';

  final HttpClient _httpClient;
  final String currentAppVersion;

  ContentUpdateService({HttpClient? httpClient, String? currentAppVersion})
    : _httpClient = httpClient ?? HttpClient(),
      currentAppVersion = currentAppVersion ?? _bundledAppVersion;

  Future<String?> getLocalContentVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localVersionKey);
  }

  Future<bool> hasLocalOverride() async {
    final file = await BookRepository.localOverrideFile();
    return file.exists();
  }

  Future<void> restoreBundledContent() async {
    final file = await BookRepository.localOverrideFile();
    if (await file.exists()) {
      await file.delete();
    }

    final tempFile = File('${file.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localVersionKey);
    await prefs.remove(_localSha256Key);
    await prefs.remove(_updatedAtKey);
  }

  Future<ContentUpdateResult> checkAndDownloadLatest() async {
    String? localVersion;
    String? remoteVersion;

    try {
      final prefs = await SharedPreferences.getInstance();
      localVersion = prefs.getString(_localVersionKey);

      final manifestBytes = await _downloadBytes(Uri.parse(manifestUrl));
      if (manifestBytes == null) {
        return ContentUpdateResult(
          status: ContentUpdateStatus.manifestUnavailable,
          localVersion: localVersion,
          message: 'Manifest is unavailable.',
        );
      }

      final manifest = _parseManifest(manifestBytes);
      remoteVersion = manifest.contentVersion;

      if (_compareVersions(currentAppVersion, manifest.minAppVersion) < 0) {
        return ContentUpdateResult(
          status: ContentUpdateStatus.skippedIncompatibleAppVersion,
          localVersion: localVersion,
          remoteVersion: remoteVersion,
          message:
              'App version $currentAppVersion is lower than '
              '${manifest.minAppVersion}.',
        );
      }

      if (localVersion != null &&
          _compareVersions(remoteVersion, localVersion) <= 0) {
        return ContentUpdateResult(
          status: ContentUpdateStatus.upToDate,
          localVersion: localVersion,
          remoteVersion: remoteVersion,
        );
      }

      final contentBytes = await _downloadBytes(Uri.parse(manifest.url));
      if (contentBytes == null) {
        return ContentUpdateResult(
          status: ContentUpdateStatus.downloadFailed,
          localVersion: localVersion,
          remoteVersion: remoteVersion,
          message: 'Content JSON download failed.',
        );
      }

      final actualHash = sha256.convert(contentBytes).toString();
      if (actualHash.toLowerCase() != manifest.sha256.toLowerCase()) {
        return ContentUpdateResult(
          status: ContentUpdateStatus.invalidHash,
          localVersion: localVersion,
          remoteVersion: remoteVersion,
          message: 'Downloaded content hash does not match manifest.',
        );
      }

      final rawContent = utf8.decode(contentBytes);
      try {
        BookRepository.parseAndValidateCollection(rawContent);
      } catch (error, stackTrace) {
        debugPrint(
          'ContentUpdateService: downloaded content rejected. '
          'errorType=${error.runtimeType}, error=$error',
        );
        debugPrintStack(
          label: 'ContentUpdateService: invalid content stackTrace',
          stackTrace: stackTrace,
        );
        return ContentUpdateResult(
          status: ContentUpdateStatus.invalidJson,
          localVersion: localVersion,
          remoteVersion: remoteVersion,
          message: 'Downloaded content JSON is invalid.',
        );
      }

      await _writeLocalOverride(contentBytes);
      await prefs.setString(_localVersionKey, remoteVersion);
      await prefs.setString(_localSha256Key, actualHash);
      await prefs.setString(_updatedAtKey, DateTime.now().toIso8601String());

      return ContentUpdateResult(
        status: ContentUpdateStatus.updated,
        localVersion: localVersion,
        remoteVersion: remoteVersion,
      );
    } on FormatException catch (error, stackTrace) {
      debugPrint('ContentUpdateService: invalid manifest/content. $error');
      debugPrintStack(
        label: 'ContentUpdateService: format stackTrace',
        stackTrace: stackTrace,
      );
      return ContentUpdateResult(
        status: ContentUpdateStatus.invalidJson,
        localVersion: localVersion,
        remoteVersion: remoteVersion,
        message: error.message,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'ContentUpdateService: update failed. '
        'errorType=${error.runtimeType}, error=$error',
      );
      debugPrintStack(
        label: 'ContentUpdateService: update stackTrace',
        stackTrace: stackTrace,
      );
      return ContentUpdateResult(
        status: ContentUpdateStatus.unknownError,
        localVersion: localVersion,
        remoteVersion: remoteVersion,
        message: error.toString(),
      );
    }
  }

  ContentManifest _parseManifest(List<int> bytes) {
    final decoded = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    return ContentManifest.fromJson(decoded);
  }

  Future<List<int>?> _downloadBytes(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      return response
          .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk))
          .timeout(_timeout);
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    }
  }

  Future<void> _writeLocalOverride(List<int> bytes) async {
    final targetFile = await BookRepository.localOverrideFile();
    final parentDirectory = targetFile.parent;
    if (!await parentDirectory.exists()) {
      await parentDirectory.create(recursive: true);
    }

    final tempFile = File('${targetFile.path}.tmp');
    await tempFile.writeAsBytes(bytes, flush: true);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tempFile.rename(targetFile.path);
  }

  int _compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < length; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }

    return 0;
  }

  List<int> _versionParts(String version) {
    final baseVersion = version.split('+').first.trim();
    if (baseVersion.isEmpty) return const [0];

    return baseVersion
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList(growable: false);
  }
}
