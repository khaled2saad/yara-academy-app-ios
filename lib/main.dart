import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'core/auth.dart';
import 'core/push.dart';
import 'core/theme.dart';
import 'screens/home.dart';
import 'screens/lesson_alert.dart';
import 'screens/login.dart';
import 'screens/splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  final auth = AuthState(api)..boot();
  runApp(
    MultiProvider(
      providers: [
        Provider<Api>.value(value: api),
        ChangeNotifierProvider<AuthState>.value(value: auth),
      ],
      child: const YaraApp(),
    ),
  );
}

class YaraApp extends StatefulWidget {
  const YaraApp({super.key});
  @override
  State<YaraApp> createState() => _YaraAppState();
}

class _YaraAppState extends State<YaraApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<({Map<String, dynamic> data, bool foreground})>? _alerts;
  bool _showingAlert = false;
  LessonAlert? _visibleAlert;
  bool _intro = true; // keep the splash on screen long enough to be seen

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alerts = Push.lessonAlerts.listen(
      (event) => _showLessonAlert(event.data, event.foreground),
    );
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _intro = false);
    });
  }

  Future<void> _showLessonAlert(
    Map<String, dynamic> data,
    bool foreground,
  ) async {
    final auth = context.read<AuthState>();
    final studentId = auth.id;
    if (data['type'] == 'teacher_ring'
        ? (!auth.isTeacher || data['recipientId'] != auth.id)
        : !auth.isStudent)
      return;
    final alert = LessonAlert.fromPush(data);
    final navigator = _navigator.currentState;
    if (alert == null || navigator == null) return;
    if (_showingAlert) {
      if (_visibleAlert?.key == alert.key) {
        try {
          final lesson = await alert.fetch(context.read<Api>());
          if (mounted &&
              auth.id == studentId &&
              _visibleAlert?.key == alert.key &&
              lesson['joined'] != true) {
            if (data['type'] == 'lesson_ring_manual' ||
                data['type'] == 'teacher_ring')
              _visibleAlert = alert;
            if (foreground) {
              await alert.playNotification(lesson['title'] as String);
            }
          }
        } on ApiError {
          // The appointment may have been changed or cancelled while the alert was open.
        }
      }
      return;
    }
    _showingAlert = true;
    try {
      final lesson = await alert.fetch(context.read<Api>());
      if (!mounted ||
          !navigator.mounted ||
          auth.id != studentId ||
          lesson['joined'] == true) {
        return;
      }
      _visibleAlert = alert;
      if (foreground ||
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(alert.playNotification(lesson['title'] as String));
      }
      await navigator.push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => LessonAlertScreen(
            currentAlert: () => _visibleAlert ?? alert,
            title: lesson['title'] as String,
          ),
        ),
      );
    } on ApiError catch (error) {
      debugPrint('YaraPush alert rejected: ${error.status} ${error.code}');
      if (!foreground && navigator.mounted) {
        ScaffoldMessenger.maybeOf(
          navigator.context,
        )?.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      await LessonAlert.cancelRinging();
      _visibleAlert = null;
      _showingAlert = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        context.read<AuthState>().status == AuthStatus.signedIn) {
      unawaited(Push.register(context.read<Api>()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alerts?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthState, AuthStatus>((a) => a.status);
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'أكاديمية يارا',
      debugShowCheckedModeBanner: false,
      theme: Ya.theme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (status) {
          // checking the saved session: stay on a plain night-sky frame (no animation) so a signed-in user never sees the intro
          AuthStatus.booting => const NightSky(
            key: ValueKey('boot'),
            child: Scaffold(backgroundColor: Colors.transparent),
          ),
          AuthStatus.offline => const Splash(
            key: ValueKey('splash'),
            message: 'بنحاول نتصل بالخادم…',
          ),
          // already signed in: skip the timed intro and go straight to the app
          AuthStatus.signedIn => const HomeScreen(key: ValueKey('home')),
          _ when _intro => const Splash(key: ValueKey('splash')),
          AuthStatus.signedOut => const Dawn(
            key: ValueKey('login'),
            child: LoginScreen(),
          ),
        },
      ),
    );
  }
}
