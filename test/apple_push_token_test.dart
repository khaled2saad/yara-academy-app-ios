import 'package:flutter_test/flutter_test.dart';
import 'package:yara_academy/core/apple_push_token.dart';

void main() {
  test(
    'waits for a late APNs token instead of requesting FCM immediately',
    () async {
      var reads = 0;
      var pauses = 0;
      final ready = await waitForApplePushToken(
        readToken: () async => ++reads == 3 ? 'apple-token' : null,
        isActive: () => true,
        delay: (_) async {
          pauses++;
        },
      );
      expect(ready, isTrue);
      expect(reads, 3);
      expect(pauses, 2);
    },
  );

  test(
    'missing APNs token returns a retryable result after a bounded wait',
    () async {
      var reads = 0;
      final ready = await waitForApplePushToken(
        readToken: () async {
          reads++;
          return null;
        },
        isActive: () => true,
        delay: (_) async {},
        attempts: 3,
      );
      expect(ready, isFalse);
      expect(reads, 3);
    },
  );

  test('signing out cancels an APNs wait before another token read', () async {
    var active = true;
    var reads = 0;
    final ready = await waitForApplePushToken(
      readToken: () async {
        reads++;
        return null;
      },
      isActive: () => active,
      delay: (_) async {
        active = false;
      },
    );
    expect(ready, isFalse);
    expect(reads, 1);
  });

  test(
    'a token arriving after logout cannot register the previous account',
    () async {
      var active = true;
      final ready = await waitForApplePushToken(
        readToken: () async {
          active = false;
          return 'late-apple-token';
        },
        isActive: () => active,
      );
      expect(ready, isFalse);
    },
  );
}
