import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yara_academy/core/lesson_alert.dart';
import 'package:yara_academy/screens/study_room_art.dart';

void main() {
  test('lesson alert validates its target before opening a screen', () {
    expect(LessonAlert.fromPush({}), isNull);
    expect(LessonAlert.fromPush({'courseId': 'course', 'type': 'teacher_ring'}), isNull);
    final alert = LessonAlert.fromPush({
      'courseId': 'course', 'type': 'teacher_ring', 'studentId': 'student',
      'lessonKey': 'round:one', 'sentAt': '2026-11-25T08:00:00.000Z',
    });
    expect(alert, isNotNull);
    expect(alert!.forTeacher, isTrue);
    expect(alert.courseId, 'course');
  });
  test('shared room seating limits and avatars', () {
    for (final decor in ['library', 'rooftop', 'ocean']) {
      expect(studyDecorCapacity(decor), 6);
    }
    for (final decor in ['garden', 'space']) {
      expect(studyDecorCapacity(decor), 12);
    }
    expect(studyAvatars.length, 8);
  });
  testWidgets('all shared avatars render in both seat directions', (tester) async {
    for (final id in studyAvatars.keys) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [
        StudyAvatar(id, size: 64, writingPage: const Offset(85, 60)),
        StudyAvatar(id, size: 64, facesLeft: true, writingPage: const Offset(85, 60)),
      ]))));
      expect(tester.takeException(), isNull, reason: id);
    }
  });
}
