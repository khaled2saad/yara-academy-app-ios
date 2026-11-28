import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'apple_push_token.dart';
import 'lesson_alert.dart';

@pragma('vm:entry-point')
Future<void> lessonBackgroundMessage(RemoteMessage message) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  if (!{
    'lesson_ring',
    'lesson_ring_retry',
    'lesson_ring_manual',
    'teacher_ring',
  }.contains(message.data['type'])) {
    return;
  }
  final alert = LessonAlert.fromPush(message.data);
  if (alert == null) return;
  try {
    String? token;
    try {
      token = await const FlutterSecureStorage().read(key: 'ya_token');
    } catch (_) {}
    final preferences = await SharedPreferences.getInstance();
    token ??= preferences.getString('ya_token_fb');
    if (token == null) return;
    final api = Api()..token = token;
    final lesson = await alert.fetch(api);
    if (lesson['joined'] != true) {
      await alert.playNotification(lesson['title'] as String);
    }
  } catch (_) {
    // Cancelled, expired or unauthorized alerts must not start ringing.
  }
}

/// Push notifications (FCM).
/// Safe without `android/app/google-services.json`: initialisation fails quietly and everything stays off.
class Push {
  static const _webOptions = FirebaseOptions(
    apiKey: 'AIzaSyBsBykjb_ibfeuw8ra_WqjTLGTJlkpxhng',
    authDomain: 'device-streaming-2ca492cd.firebaseapp.com',
    appId: '1:17974910911:web:874a17bb35231966380b0a',
    messagingSenderId: '17974910911',
    projectId: 'device-streaming-2ca492cd',
    storageBucket: 'device-streaming-2ca492cd.firebasestorage.app',
  );
  static const _vapid =
      'BCdwEjZK2ayQH_BoixBsdzUVvgkgrNmljtxC5effIvuLLU9ogcdwEXBrBhOX7-5TM9YqBrHcueUqL-F0EBe5FDk';
  // Firebase iOS app "Yara iOS" (com.yara.yaraAcademy). These are client identifiers, not secrets.
  static const _iosOptions = FirebaseOptions(
    apiKey: 'AIzaSyBZ-z-ZrFk0fzvaYqW1Jn-4WAWY_1tZw6c',
    appId: '1:17974910911:ios:6bbcb3e29127a664380b0a',
    messagingSenderId: '17974910911',
    projectId: 'device-streaming-2ca492cd',
    iosBundleId: 'com.yara.yaraAcademy',
  );

  static bool _ready = false;
  static bool _tried = false;
  static String? _token;
  static StreamSubscription<String>? _refreshSub;
  static Timer? _registrationRetry;
  static Api? _activeApi;
  static bool _registering = false;
  static int _registrationEpoch = 0;
  static final _lessonAlerts =
      StreamController<
        ({Map<String, dynamic> data, bool foreground})
      >.broadcast();
  static Stream<({Map<String, dynamic> data, bool foreground})>
  get lessonAlerts => _lessonAlerts.stream;

  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  static void _handle(RemoteMessage? message, {required bool foreground}) {
    if (message == null) return;
    final data = message.data;
    debugPrint('YaraPush received type=${data['type']} foreground=$foreground');
    if (data['type'] == 'lesson_ring' ||
        data['type'] == 'lesson_ring_retry' ||
        data['type'] == 'lesson_ring_manual' ||
        data['type'] == 'teacher_ring') {
      _lessonAlerts.add((data: data, foreground: foreground));
    }
  }

  static Future<bool> _init() async {
    if (!kIsWeb && (!_ios && defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }
    if (_ready) return true;
    if (_tried) return false;
    _tried = true;
    try {
      await Firebase.initializeApp(
        options: kIsWeb
            ? _webOptions
            : _ios
            ? _iosOptions
            : null,
      );
      _ready = true;
      if (!kIsWeb)
        FirebaseMessaging.onBackgroundMessage(lessonBackgroundMessage);
      await LessonAlert.initialize(
        onTap: (data) {
          _lessonAlerts.add((data: data, foreground: false));
        },
      );
      FirebaseMessaging.onMessage.listen(
        (message) => _handle(message, foreground: true),
      );
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handle(message, foreground: false),
      );
      unawaited(
        FirebaseMessaging.instance.getInitialMessage().then<void>(
          (message) => _handle(message, foreground: false),
          onError: (Object _) {},
        ),
      );
    } catch (error) {
      debugPrint('YaraPush initialization failed: $error');
      _ready = false;
      _tried = false;
    }
    return _ready;
  }

  /// Call after the user is signed in.
  static Future<void> register(Api api) async {
    if (api.token == null) return;
    _activeApi = api;
    if (_registering) return;
    _registering = true;
    _registrationRetry?.cancel();
    final epoch = _registrationEpoch;
    bool isActive() =>
        epoch == _registrationEpoch &&
        identical(_activeApi, api) &&
        api.token != null;
    var retry = false;
    try {
      if (!await _init()) {
        retry = true;
        return;
      }
      if (!isActive()) return;
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission();
      if (!isActive() ||
          settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      // Listen before requesting the initial token so a late native callback
      // cannot be lost when APNs has not finished registering yet.
      _refreshSub ??= fm.onTokenRefresh.listen((nt) async {
        final currentApi = _activeApi;
        final currentEpoch = _registrationEpoch;
        if (currentApi == null || currentApi.token == null) return;
        _token = nt;
        if (!await _send(currentApi, nt) &&
            currentEpoch == _registrationEpoch &&
            identical(currentApi, _activeApi)) {
          _retryRegistration(currentApi);
        }
      });
      if (!kIsWeb &&
          _ios &&
          !await waitForApplePushToken(
            readToken: fm.getAPNSToken,
            isActive: isActive,
          )) {
        debugPrint('YaraPush Apple token pending; registration will retry');
        retry = true;
        return;
      }
      if (!isActive()) return;
      final t = await fm.getToken(
        vapidKey: kIsWeb ? _vapid : null,
        serviceWorkerScriptPath: kIsWeb ? '/firebase-messaging-sw.js' : null,
      );
      if (!isActive()) return;
      if (t == null) {
        retry = true;
        return;
      }
      _token = t;
      retry = !await _send(api, t);
    } catch (error) {
      debugPrint('YaraPush registration failed: $error');
      retry = true;
      // never let push break login
    } finally {
      _registering = false;
      if (retry && isActive()) _retryRegistration(api);
      // A new login may have arrived while the previous user's attempt was
      // waiting for APNs. Start the new registration after that attempt exits.
      if (epoch != _registrationEpoch && _activeApi != null) {
        unawaited(register(_activeApi!));
      }
    }
  }

  static void _retryRegistration(Api api) {
    _registrationRetry?.cancel();
    if (!identical(api, _activeApi) || api.token == null) return;
    _registrationRetry = Timer(const Duration(seconds: 30), () {
      if (identical(api, _activeApi) && api.token != null) {
        unawaited(register(api));
      }
    });
  }

  static Future<bool> _send(Api api, String t) async {
    try {
      if (api.token == null) return false;
      await api.post(
        '/push/token',
        body: {
          'token': t,
          'platform': kIsWeb
              ? 'web'
              : _ios
              ? 'ios'
              : 'android_ring',
        },
      );
      debugPrint('YaraPush device registered');
      return true;
    } catch (error) {
      debugPrint('YaraPush device registration request failed: $error');
      return false;
    }
  }

  /// Call before signing out so the next person on this phone doesn't get this user's notifications.
  static Future<void> unregister(Api api) async {
    _registrationEpoch++;
    _activeApi = null;
    _registrationRetry?.cancel();
    await _refreshSub?.cancel();
    _refreshSub = null;
    await LessonAlert.cancelRinging();
    final t = _token;
    _token = null;
    if (t == null || api.token == null) return;
    try {
      await api.request('DELETE', '/push/token', body: {'token': t});
    } catch (_) {}
  }
}
