/// Where the Yara backend lives.
/// Defaults to the live production server, so a build that forgets to pass
/// --dart-define=API_BASE=... still works out of the box.
/// For local development against your own machine, override with:
///   flutter run --dart-define=API_BASE=http://10.0.2.2:4000   (Android emulator)
///   flutter run --dart-define=API_BASE=http://localhost:4000  (web / iOS simulator on the same Mac)
class Config {
  static const _define = String.fromEnvironment('API_BASE');
  static const _prod = 'https://yaraacademy.tech';

  static String get baseUrl {
    if (_define.isNotEmpty) return _define;
    return _prod;
  }

  static const sessionRefreshEvery = Duration(hours: 6);
}
