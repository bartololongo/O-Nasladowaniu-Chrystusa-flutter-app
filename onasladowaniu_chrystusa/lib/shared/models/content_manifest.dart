class ContentManifest {
  final int schemaVersion;
  final String contentVersion;
  final String minAppVersion;
  final String url;
  final String sha256;
  final DateTime? publishedAt;
  final String? notes;

  const ContentManifest({
    required this.schemaVersion,
    required this.contentVersion,
    required this.minAppVersion,
    required this.url,
    required this.sha256,
    this.publishedAt,
    this.notes,
  });

  factory ContentManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    final publishedAt = _optionalString(json, 'publishedAt');

    if (schemaVersion is! num) {
      throw const FormatException('Manifest schemaVersion must be a number.');
    }

    return ContentManifest(
      schemaVersion: schemaVersion.toInt(),
      contentVersion: _requiredString(json, 'contentVersion'),
      minAppVersion: _requiredString(json, 'minAppVersion'),
      url: _requiredString(json, 'url'),
      sha256: _requiredString(json, 'sha256'),
      publishedAt: publishedAt == null ? null : DateTime.parse(publishedAt),
      notes: _optionalString(json, 'notes'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Manifest $key must be a non-empty string.');
    }

    return value.trim();
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('Manifest $key must be a string.');
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() {
    return 'ContentManifest('
        'schemaVersion: $schemaVersion, '
        'contentVersion: $contentVersion, '
        'minAppVersion: $minAppVersion, '
        'url: $url, '
        'publishedAt: $publishedAt'
        ')';
  }
}
