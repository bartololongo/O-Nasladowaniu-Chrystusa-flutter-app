class ReaderReferenceFormatter {
  const ReaderReferenceFormatter._();

  static String format(String reference) {
    final normalized = reference.trim();
    if (normalized.isEmpty) return 'Odniesienie';

    final parts = normalized.split('-');
    if (parts.length >= 2) {
      final base = 'Księga ${parts[0]}, rozdział ${parts[1]}';
      if (parts.length >= 3) {
        final paragraphNumber = int.tryParse(parts[2]);
        if (paragraphNumber != null) {
          return '$base, akapit $paragraphNumber';
        }
      }
      return base;
    }

    return 'Odniesienie $normalized';
  }
}
