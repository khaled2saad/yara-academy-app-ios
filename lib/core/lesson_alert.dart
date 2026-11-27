import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'web_ring.dart';

import 'api.dart';

class LessonAlert {
  const LessonAlert._(
    this.courseId,
    this.key,
    this._path,
    this._query,
    this.data,
  );

  static LessonAlert? fromPush(Map<String, dynamic> data) {
    final course = data['courseId'];
    if (course is! String || course.isEmpty) return null;
    if (data['type'] == 'teacher_ring') {
      final key = data['lessonKey'],
          sentAt = data['sentAt'],
          student = data['studentId'];
      if (key is! String ||
          sentAt is! String ||
          DateTime.tryParse(sentAt) == null ||
          student is! String ||
          student.isEmpty)
        return null;
      return LessonAlert._(
        course,
        'teacher:$student:$key',
        '/courses/$course/teacher-nudge',
        {'lessonKey': key, 'sentAt': sentAt, 'studentId': student},
        data,
      );
    }
    if (data['type'] == 'lesson_ring_manual') {
      final key = data['lessonKey'];
      final sentAt = data['sentAt'];
      if (key is! String ||
          key.isEmpty ||
          sentAt is! String ||
          DateTime.tryParse(sentAt) == null) {
        return null;
      }
      return LessonAlert._(course, key, '/courses/$course/lesson-nudge', {
        'lessonKey': key,
        'sentAt': sentAt,
      }, data);
    }
    final appointment = data['appointmentId'];
    final start = data['startsAt'];
    if (appointment is! String ||
        appointment.isEmpty ||
        start is! String ||
        DateTime.tryParse(start) == null) {
      return null;
    }
    return LessonAlert._(
      course,
      'appointment:$appointment:$start',
      '/courses/$course/appointments/$appointment/lesson-alert',
      {'startsAt': start},
      data,
    );
  }

  final String courseId, key, _path;
  final Map<String, dynamic> _query;
  final Map<String, dynamic> data;
  bool get forTeacher => data['type'] == 'teacher_ring';
  String get heading => forTeacher
      ? 'طالبك يناديك'
      : data['type'] == 'lesson_ring_manual'
      ? 'المعلمة تناديك'
      : 'موعد حصتك الآن';

  Future<Map<String, dynamic>> fetch(Api api) async =>
      await api.get(_path, query: _query) as Map<String, dynamic>;

  static final _notifications = FlutterLocalNotificationsPlugin();
  static Future<bool?>? _notificationSetup;
  static const _notificationId = 74001;

  static Future<void> initialize({
    void Function(Map<String, dynamic>)? onTap,
  }) async {
    if (kIsWeb) {
      if (onTap != null) initializeWebRing(onTap);
      return;
    }
    await (_notificationSetup ??= _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && onTap != null) {
          try {
            onTap((jsonDecode(payload) as Map).cast<String, dynamic>());
          } catch (_) {}
        }
      },
    ));
    if (onTap != null) {
      final launch = await _notifications.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        try {
          onTap((jsonDecode(payload) as Map).cast<String, dynamic>());
        } catch (_) {}
      }
    }
  }

  Future<void> playNotification(String title) async {
    if (kIsWeb) {
      playWebRing();
      return;
    }
    try {
      await initialize();
      await _notifications.show(
        id: _notificationId,
        title: 'أكاديمية يارا – $heading',
        body: title,
        payload: jsonEncode(data),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'yara_lesson',
            'تنبيهات موعد الحصة',
            importance: Importance.high,
            priority: Priority.high,
            sound: RawResourceAndroidNotificationSound('yara_lesson'),
            ongoing: true,
            autoCancel: false,
            additionalFlags: Int32List.fromList([4]),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentSound: true,
            sound: 'yara_lesson.wav',
            presentBanner: false,
            presentList: false,
          ),
        ),
      );
    } catch (_) {
      // Notification permission or the device may prevent the sound.
    }
  }

  Future<void> clearNotification() async {
    await cancelRinging();
  }

  static Future<void> cancelRinging() async {
    if (kIsWeb) {
      stopWebRing();
      return;
    }
    try {
      await initialize();
      await _notifications.cancel(id: _notificationId);
    } catch (_) {}
  }
}
