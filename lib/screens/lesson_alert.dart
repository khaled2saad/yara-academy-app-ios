import 'dart:async';

import 'package:flutter/material.dart';
import '../core/lesson_alert.dart';
export '../core/lesson_alert.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'chat.dart';

class LessonAlertScreen extends StatefulWidget {
  const LessonAlertScreen({
    super.key,
    required this.currentAlert,
    required this.title,
  });
  final LessonAlert Function() currentAlert;
  final String title;

  @override
  State<LessonAlertScreen> createState() => _LessonAlertScreenState();
}

class _LessonAlertScreenState extends State<LessonAlertScreen> {
  bool _busy = false;

  Future<void> _answer() async {
    setState(() => _busy = true);
    await widget.currentAlert().clearNotification();
    if (!mounted) return;
    final api = context.read<Api>();
    final auth = context.read<AuthState>();
    final studentId = auth.id;
    final alert = widget.currentAlert();
    try {
      final lesson = await alert.fetch(api);
      if (!mounted || auth.id != studentId) return;
      if (alert.forTeacher && auth.isTeacher) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ChatScreen(
              courseId: alert.courseId,
              title: widget.title,
              studentId: lesson['studentId'] as String,
            ),
          ),
        );
        return;
      }
      if (!auth.isStudent) return;
      final url = lesson['url'] as String?;
      if (url == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                ChatScreen(courseId: alert.courseId, title: widget.title),
          ),
        );
        return;
      }
      final opened = await openZoomLink(context, url);
      if (opened && auth.id == studentId) {
        unawaited(
          api
              .post(
                '/courses/${alert.courseId}/attendance/join',
                body: {'messageId': lesson['messageId']},
              )
              .then<void>((_) {}, onError: (Object _) {}),
        );
        if (mounted) Navigator.of(context).pop();
      }
    } on ApiError catch (error) {
      if (mounted) toast(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ya.bg,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CircleAvatar(
                  radius: 46,
                  backgroundColor: Ya.soft,
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: Ya.strong,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'أكاديمية يارا',
                  textAlign: TextAlign.center,
                  style: Ya.display(),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.currentAlert().heading,
                  textAlign: TextAlign.center,
                  style: Ya.display(size: 22),
                ),
                const SizedBox(height: 8),
                Text(widget.title, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                GradButton(
                  label: widget.currentAlert().forTeacher
                      ? 'رد على الطالب'
                      : 'رد على الحصة',
                  icon: Icons.login_rounded,
                  onPressed: _busy ? null : _answer,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
