import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// A session lasts 50 minutes; free Zoom cuts a meeting at 40.
const sessionMin = 50, zoomMin = 40, zoomWarn = 5;

bool sessionDue(Course c) {
  final since = DateTime.tryParse('${c.json['pendingSince'] ?? ''}');
  return c.pendingConfirmation && since != null && DateTime.now().isAfter(since.add(const Duration(minutes: sessionMin)));
}

/// "هل تمت الحصة؟" box shown on a course that waits for confirmation (teacher + supervisor).
class ConfirmBox extends StatelessWidget {
  const ConfirmBox({super.key, required this.pendingSince, required this.onConfirm});
  final DateTime? pendingSince;
  final void Function(bool held) onConfirm;

  @override
  Widget build(BuildContext context) {
    final since = pendingSince;
    final due = since != null && DateTime.now().isAfter(since.add(const Duration(minutes: sessionMin)));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: due ? Ya.warnBg : Ya.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: due ? Ya.gold : Colors.transparent, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(due ? '⏰ انتهى وقت الحصة، هل تمت؟' : 'هل تمت الحصة؟', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GradButton(label: 'تمت', gradient: Ya.waGradient, height: 42, onPressed: () => onConfirm(true))),
          const SizedBox(width: 8),
          Expanded(child: SoftButton(label: 'لم تتم', height: 42, onPressed: () => onConfirm(false))),
        ]),
      ]),
    );
  }
}

/// Confirm the session (with a dialog) and report back.
Future<bool> confirmSession(
  BuildContext context,
  String courseId,
  bool held, {
  String? studentId,
  String? pendingSince,
}) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(held ? 'تأكيد: الحصة تمت؟' : 'تأكيد: الحصة لم تتم؟'),
      content: Text(held ? 'سيتم احتساب حصة للطالب والمعلمة.' : 'مش هتتحسب أي حصة.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
      ],
    ),
  );
  if (sure != true || !context.mounted) return false;
  try {
    final response = await context.read<Api>().post(
      '/courses/$courseId/sessions/confirm',
      body: {'held': held, 'studentId': ?studentId, 'pendingSince': ?pendingSince},
    );
    if (context.mounted) toast(context, response['held'] == true ? '✅ تم تسجيل الحصة، أحسنت!' : 'تم تسجيل أن الحصة لم تتم');
    return true;
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return false;
  }
}

