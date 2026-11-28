/// APNs registration can finish after notification permission is granted.
/// Never request an FCM token until Apple's token is available.
Future<bool> waitForApplePushToken({
  required Future<String?> Function() readToken,
  required bool Function() isActive,
  Future<void> Function(Duration)? delay,
  int attempts = 20,
}) async {
  final pause = delay ?? Future<void>.delayed;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (!isActive()) return false;
    final token = await readToken();
    if (!isActive()) return false;
    if (token != null && token.isNotEmpty) return true;
    if (attempt + 1 < attempts) {
      await pause(const Duration(milliseconds: 500));
    }
  }
  return false;
}
