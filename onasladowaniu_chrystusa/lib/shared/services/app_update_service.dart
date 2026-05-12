import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppUpdateAvailability {
  final bool isAvailable;
  final bool isDismissed;
  final String? localVersion;
  final String? remoteVersion;
  final String? storeUrl;

  const AppUpdateAvailability({
    required this.isAvailable,
    this.isDismissed = false,
    this.localVersion,
    this.remoteVersion,
    this.storeUrl,
  });
}

class AppUpdateService {
  static const String dismissedVersionKey = 'app.update.dismissed_version';
  static const String iosAppStoreId = 'TODO_APP_STORE_ID';
  static const String iosBundleId = 'pl.bartololongo.onasladowaniuChrystusa';
  static const Duration _timeout = Duration(seconds: 8);

  final HttpClient _httpClient;
  final bool Function() _isIos;
  final Future<PackageInfo> Function() _packageInfoLoader;

  AppUpdateService({
    HttpClient? httpClient,
    bool Function()? isIos,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _httpClient = httpClient ?? HttpClient(),
       _isIos = isIos ?? (() => Platform.isIOS),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  Future<AppUpdateAvailability> checkAvailability() async {
    if (!_isIos()) {
      return const AppUpdateAvailability(isAvailable: false);
    }

    try {
      final packageInfo = await _packageInfoLoader();
      final localVersion = packageInfo.version;
      final uri = Uri.parse(_lookupUrl);

      final request = await _httpClient.getUrl(uri).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return AppUpdateAvailability(
          isAvailable: false,
          localVersion: localVersion,
        );
      }

      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return AppUpdateAvailability(
          isAvailable: false,
          localVersion: localVersion,
        );
      }

      final resultCount = decoded['resultCount'];
      final results = decoded['results'];
      if (resultCount is! int ||
          resultCount <= 0 ||
          results is! List ||
          results.isEmpty ||
          results.first is! Map<String, dynamic>) {
        return AppUpdateAvailability(
          isAvailable: false,
          localVersion: localVersion,
        );
      }

      final result = results.first as Map<String, dynamic>;
      final remoteVersion = result['version'];
      if (remoteVersion is! String || remoteVersion.isEmpty) {
        return AppUpdateAvailability(
          isAvailable: false,
          localVersion: localVersion,
        );
      }

      final comparison = compareSemanticVersions(remoteVersion, localVersion);
      if (comparison == null || comparison <= 0) {
        return AppUpdateAvailability(
          isAvailable: false,
          localVersion: localVersion,
          remoteVersion: remoteVersion,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final dismissedVersion = prefs.getString(dismissedVersionKey);

      return AppUpdateAvailability(
        isAvailable: true,
        isDismissed: dismissedVersion == remoteVersion,
        localVersion: localVersion,
        remoteVersion: remoteVersion,
        storeUrl: result['trackViewUrl'] is String
            ? result['trackViewUrl'] as String
            : null,
      );
    } catch (error, stackTrace) {
      debugPrint('AppUpdateService: availability check failed. $error');
      debugPrintStack(
        label: 'AppUpdateService: availability stackTrace',
        stackTrace: stackTrace,
      );
      return const AppUpdateAvailability(isAvailable: false);
    }
  }

  Future<void> dismissAppVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(dismissedVersionKey, version);
  }

  static int? compareSemanticVersions(String remote, String local) {
    final remoteParts = _parseSemanticVersion(remote);
    final localParts = _parseSemanticVersion(local);
    if (remoteParts == null || localParts == null) return null;

    for (var i = 0; i < remoteParts.length; i++) {
      final diff = remoteParts[i].compareTo(localParts[i]);
      if (diff != 0) return diff;
    }

    return 0;
  }

  static List<int>? _parseSemanticVersion(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 3) return null;

    final parsed = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      parsed.add(number);
    }

    return parsed;
  }

  String get _lookupUrl {
    if (iosAppStoreId != 'TODO_APP_STORE_ID') {
      return 'https://itunes.apple.com/lookup?id=$iosAppStoreId&country=pl';
    }

    return 'https://itunes.apple.com/lookup?bundleId=$iosBundleId&country=pl';
  }
}
