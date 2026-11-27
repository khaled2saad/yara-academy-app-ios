import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

const studyDecors = {
  'library': 'المكتبة',
  'rooftop': 'الحديقة فوق السطح',
  'ocean': 'المرصد تحت الماء',
  'garden': 'قاعة الحديقة الكبيرة',
  'space': 'قاعة الفضاء',
};

int studyDecorCapacity(String decor) =>
    decor == 'garden' || decor == 'space' ? 12 : 6;

const studyAvatars = {
  'mint': ('نعناع', Color(0xFF43A78C), Color(0xFFF1B582), Color(0xFF352535)),
  'berry': ('توت', Color(0xFFBC5792), Color(0xFFD48965), Color(0xFF492E32)),
  'amber': ('عنبر', Color(0xFFE3A73B), Color(0xFFA66648), Color(0xFF28212C)),
  'ocean': ('موج', Color(0xFF378EC0), Color(0xFFF4C8A3), Color(0xFF523432)),
  'plum': ('بنفسج', Color(0xFF886BCD), Color(0xFFBD7D57), Color(0xFF342830)),
  'coral': ('مرجان', Color(0xFFE4816E), Color(0xFFEEBA93), Color(0xFF895637)),
  'olive': ('زيتون', Color(0xFF81994C), Color(0xFF8F513D), Color(0xFF302536)),
  'indigo': ('نيلي', Color(0xFF596BC3), Color(0xFFE0A57F), Color(0xFF342B43)),
};

class StudyBackdrop extends StatelessWidget {
  const StudyBackdrop(this.decor, {super.key});

  final String decor;

  @override
  Widget build(BuildContext context) => decor == 'garden' || decor == 'space'
      ? Image.asset('assets/study_$decor.png', fit: BoxFit.cover)
      : ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: const Alignment(0, .15),
            child: SizedBox.square(
              dimension: 724,
              child: ClipRect(
                child: OverflowBox(
                  alignment: switch (decor) {
                    'rooftop' => Alignment.center,
                    'ocean' => Alignment.centerRight,
                    _ => Alignment.centerLeft,
                  },
                  minWidth: 2172,
                  maxWidth: 2172,
                  child: Image.asset(
                    'assets/study_room_decors.png',
                    fit: BoxFit.fill,
                    errorBuilder: (_, _, _) => const ColoredBox(color: Ya.soft),
                  ),
                ),
              ),
            ),
          ),
        );
}

class StudyAvatar extends StatelessWidget {
  const StudyAvatar(
    this.id, {
    super.key,
    this.facesLeft = false,
    this.size = 46,
    this.motion,
    this.seat = 0,
    this.arrival = 1,
    this.writingPage,
  });

  final String id;
  final bool facesLeft;
  final double size;
  final Animation<double>? motion;
  final int seat;
  final double arrival;

  /// Position of the notebook in the profile's 64-unit drawing coordinates.
  final Offset? writingPage;

  @override
  Widget build(BuildContext context) {
    final avatar = studyAvatars[id] ?? studyAvatars.values.first;
    return SizedBox(
      width: writingPage == null
          ? size
          : math.max(size * 1.65, (writingPage!.dx + 12) * size / 64),
      height: writingPage == null ? size : size * 1.34,
      child: Transform.flip(
        flipX: facesLeft,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _Profile(
              avatar.$2,
              avatar.$3,
              avatar.$4,
              studyAvatars.keys.toList().indexOf(id),
              motion: motion,
              seat: seat,
              arrival: arrival,
              writingPage: writingPage,
              unit: size / 64,
            ),
          ),
        ),
      ),
    );
  }
}

// A right-facing cartoon profile. The opposite seat mirrors the pose.
class _Profile extends CustomPainter {
  _Profile(
    this.shirt,
    this.skin,
    this.hair,
    this.style, {
    this.motion,
    required this.seat,
    required this.arrival,
    required this.writingPage,
    required this.unit,
  }) : super(repaint: motion);

  final Color shirt, skin, hair;
  final int style, seat;
  final Animation<double>? motion;
  final double arrival;
  final double unit;
  final Offset? writingPage;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(unit);
    final paint = Paint()..isAntiAlias = true;
    final time = motion == null ? 0.0 : motion!.value * 24 + seat * .71;
    final stride = (1 - arrival) * math.sin(arrival * 6 * math.pi) * 5;
    final breathing = motion == null ? 0.0 : math.sin(time * math.pi / 2);
    final writing = motion == null
        ? 0.0
        : (math.sin(time * math.pi * 2 / 3) + .35).clamp(0.0, 1.0);
    final hand = writing * math.sin(time * math.pi * 4);
    final blink = motion != null && time % 4.8 > 4.67;
    final page = writingPage;
    final lean = page != null && page.dx > 95 ? 9.0 : 0.0;
    void shape(Path path, Color color) =>
        canvas.drawPath(path, paint..color = color);
    void circle(double x, double y, double radius, Color color) =>
        canvas.drawCircle(Offset(x, y), radius, paint..color = color);

    canvas.drawOval(
      const Rect.fromLTWH(5, 51, 55, 11),
      paint..color = const Color(0x49342225),
    );
    if (page != null && arrival >= .94) {
      // Legs point into the table. Its near edge occludes the knees and shoes,
      // instead of painting them on top of the tabletop or the chair cushion.
      final tableEdge = 30 + (page.dx - 30) * .5;
      canvas.save();
      canvas.clipPath(
        Path()
          ..moveTo(-12, 0)
          ..lineTo(tableEdge + 8, 0)
          ..lineTo(tableEdge - 7, 86)
          ..lineTo(-12, 86)
          ..close(),
      );
      paint
        ..color = const Color(0xFF344657)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(22, 55)
          ..quadraticBezierTo(tableEdge, 57, tableEdge + 14, 64)
          ..lineTo(tableEdge + 10, 79),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(17, 55)
          ..quadraticBezierTo(tableEdge - 7, 59, tableEdge + 6, 66)
          ..lineTo(tableEdge + 3, 78),
        paint,
      );
      paint
        ..color = const Color(0xFF202936)
        ..strokeWidth = 3.8;
      canvas.drawLine(
        Offset(tableEdge + 9, 81),
        Offset(tableEdge + 17, 81),
        paint,
      );
      canvas.drawLine(
        Offset(tableEdge + 2, 80),
        Offset(tableEdge + 9, 80),
        paint,
      );
      paint.style = PaintingStyle.fill;
      canvas.restore();
    } else if (arrival < .985) {
      paint
        ..color = Ya.ink
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(24, 52), Offset(22 + stride, 59), paint);
      canvas.drawLine(const Offset(36, 52), Offset(38 - stride, 59), paint);
    }
    if (page == null || arrival < .94) canvas.translate(0, breathing * .75);
    shape(
      Path()
        ..moveTo(14, 57)
        ..lineTo(14, 41)
        ..quadraticBezierTo(17 + lean, 34, 25 + lean, 35)
        ..lineTo(34 + lean, 36)
        ..quadraticBezierTo(42 + lean, 38, 44, 53)
        ..lineTo(43, 58)
        ..quadraticBezierTo(27, 63, 14, 57)
        ..close(),
      shirt,
    );
    if (page == null || arrival < .94) {
      shape(
        Path()
          ..moveTo(12, 57)
          ..quadraticBezierTo(11, 40, 23, 37)
          ..lineTo(36, 37)
          ..quadraticBezierTo(47, 39, 48, 55)
          ..quadraticBezierTo(34, 63, 12, 57)
          ..close(),
        shirt,
      );
      shape(
        Path()
          ..moveTo(33, 45)
          ..quadraticBezierTo(48, 47, 55 + hand * 3, 49 + hand)
          ..quadraticBezierTo(
            61 + hand * 3,
            51 + hand,
            57 + hand * 3,
            55 + hand,
          )
          ..quadraticBezierTo(41, 55, 33, 52)
          ..close(),
        skin,
      );
    }
    canvas.save();
    canvas.translate(lean, 0);
    canvas.translate(29, 27);
    canvas.rotate(writing * .12 + breathing * .035);
    canvas.translate(-29, -27);
    circle(29, 24, 18, skin);
    shape(
      Path()
        ..moveTo(42, 21)
        ..lineTo(52, 28)
        ..quadraticBezierTo(54, 32, 46, 32)
        ..quadraticBezierTo(43, 42, 33, 41)
        ..lineTo(27, 40)
        ..close(),
      skin,
    );
    if (style == 1 || style == 4 || style == 7) {
      circle(13, 29, 9, hair);
      circle(12, 38, 7, hair);
    }
    if (style == 2 || style == 6) {
      for (final offset in const [
        Offset(14, 15),
        Offset(20, 10),
        Offset(28, 8),
        Offset(35, 9),
        Offset(42, 13),
      ]) {
        circle(offset.dx, offset.dy, 8, hair);
      }
    }
    shape(
      Path()
        ..moveTo(11, 22)
        ..quadraticBezierTo(10, 2, 31, 5)
        ..quadraticBezierTo(46, 6, 47, 18)
        ..quadraticBezierTo(42, 14, 37, 16)
        ..quadraticBezierTo(30, 24, 21, 22)
        ..lineTo(18, 34)
        ..quadraticBezierTo(10, 34, 11, 22)
        ..close(),
      hair,
    );
    circle(22, 27, 4, skin);
    if (blink) {
      paint
        ..color = const Color(0xFF2B2530)
        ..strokeWidth = 1.5;
      canvas.drawLine(const Offset(40, 24), const Offset(44, 24), paint);
    } else {
      circle(42, 24 + writing * 1.4, 2, const Color(0xFF2B2530));
    }
    circle(37, 31, 2.6, const Color(0x60CC6570));
    if (style == 0 || style == 3) {
      paint
        ..color = Ya.ink
        ..strokeWidth = 1.3
        ..style = PaintingStyle.stroke;
      canvas.drawOval(const Rect.fromLTWH(37, 19, 11, 10), paint);
      canvas.drawLine(const Offset(37, 23), const Offset(26, 24), paint);
      paint.style = PaintingStyle.fill;
    }
    canvas.restore();
    if (page != null && arrival >= .94) {
      final tip = Offset(
        page.dx + hand * 2,
        page.dy + math.sin(time * math.pi * 4) * writing,
      );
      final grip = tip - const Offset(5, 8);
      final shoulder = Offset(38 + lean, 48);
      final elbow = Offset(
        shoulder.dx + (grip.dx - shoulder.dx) * .55,
        math.max(shoulder.dy + 10, grip.dy + 7),
      );
      paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 9
        ..color = shirt;
      canvas.drawLine(shoulder, elbow, paint);
      paint
        ..strokeWidth = 6
        ..color = skin;
      canvas.drawLine(elbow, grip, paint);
      paint
        ..strokeWidth = 1.9
        ..color = const Color(0xFFF1C965);
      canvas.drawLine(tip - const Offset(9, 15), tip, paint);
      paint.style = PaintingStyle.fill;
      circle(grip.dx, grip.dy, 2.6, skin);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Profile oldDelegate) =>
      oldDelegate.shirt != shirt ||
      oldDelegate.skin != skin ||
      oldDelegate.hair != hair ||
      oldDelegate.style != style ||
      oldDelegate.motion != motion ||
      oldDelegate.seat != seat ||
      oldDelegate.arrival != arrival ||
      oldDelegate.unit != unit ||
      oldDelegate.writingPage != writingPage;
}

/// Light and bubbles drift independently of the people in the room.
class StudyRoomAtmosphere extends CustomPainter {
  StudyRoomAtmosphere(this.decor, this.motion) : super(repaint: motion);

  final String decor;
  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final ocean = decor == 'ocean';
    for (var i = 0; i < 18; i++) {
      final rate = i % 3 + 1;
      final phase = (motion.value * rate + (i * .6180339)) % 1;
      final drift = math.sin((phase * math.pi * 2) + i) * .022;
      final x = (.08 + ((i * .379) % .84) + drift) * size.width;
      final y = (ocean ? .74 - phase * .69 : .07 + phase * .56) * size.height;
      final alpha = math.sin(phase * math.pi) * (ocean ? .45 : .46);
      final radius = (ocean ? 2.5 + i % 4 : 1.1 + i % 3) * size.width / 724;
      paint
        ..style = ocean ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1.3
        ..color = (ocean ? const Color(0xFFD6F8FF) : const Color(0xFFFFE6AC))
            .withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StudyRoomAtmosphere oldDelegate) =>
      oldDelegate.decor != decor || oldDelegate.motion != motion;
}

class StudyAvatarPicker extends StatelessWidget {
  const StudyAvatarPicker({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in studyAvatars.entries)
        ChoiceChip(
          avatar: StudyAvatar(entry.key, size: 28),
          label: Text(entry.value.$1),
          selected: selected == entry.key,
          onSelected: (_) => onSelect(entry.key),
        ),
    ],
  );
}
