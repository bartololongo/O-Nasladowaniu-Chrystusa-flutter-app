import 'package:flutter_test/flutter_test.dart';
import 'package:onasladowaniu_chrystusa/shared/services/app_update_service.dart';

void main() {
  group('AppUpdateService.compareSemanticVersions', () {
    test('detects patch update', () {
      expect(AppUpdateService.compareSemanticVersions('2.0.1', '2.0.0'), 1);
    });

    test('detects minor update over higher patch', () {
      expect(AppUpdateService.compareSemanticVersions('2.1.0', '2.0.9'), 1);
    });

    test('treats equal versions as not newer', () {
      expect(AppUpdateService.compareSemanticVersions('2.0.0', '2.0.0'), 0);
    });

    test('compares multi-digit minor versions numerically', () {
      expect(AppUpdateService.compareSemanticVersions('2.10.0', '2.2.0'), 1);
    });
  });
}
