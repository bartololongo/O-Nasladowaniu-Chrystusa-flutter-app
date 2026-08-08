import 'package:flutter_test/flutter_test.dart';
import 'package:onasladowaniu_chrystusa/shared/formatters/reader_reference_formatter.dart';

void main() {
  group('ReaderReferenceFormatter', () {
    test('formats chapter reference', () {
      expect(
        ReaderReferenceFormatter.format('II-10'),
        'Księga II, rozdział 10',
      );
    });

    test('formats numeric paragraph reference', () {
      expect(
        ReaderReferenceFormatter.format('II-10-3'),
        'Księga II, rozdział 10, akapit 3',
      );
    });

    test('hides technical selection suffix', () {
      expect(
        ReaderReferenceFormatter.format('II-10-sel'),
        'Księga II, rozdział 10',
      );
    });
  });
}
