import 'package:flutter_test/flutter_test.dart';
import 'package:onasladowaniu_chrystusa/features/audio/ui/audio_player_screen.dart';

void main() {
  group('shouldSyncAudioProgressAnchor', () {
    test('accepts a backward seek position while audio is playing', () {
      expect(
        shouldSyncAudioProgressAnchor(
          playerPosition: const Duration(seconds: 50),
          displayPosition: const Duration(seconds: 60),
          isPlaying: true,
          forceNextPositionSync: false,
        ),
        isTrue,
      );
    });

    test('ignores tiny backward drift while audio is playing', () {
      expect(
        shouldSyncAudioProgressAnchor(
          playerPosition: const Duration(milliseconds: 59850),
          displayPosition: const Duration(seconds: 60),
          isPlaying: true,
          forceNextPositionSync: false,
        ),
        isFalse,
      );
    });
  });
}
