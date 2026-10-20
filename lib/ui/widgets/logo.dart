import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// The Encore mark, "Echo play": a play button with two fading echoes
/// behind it. Same geometry as tool/icons.py, which renders the app icons.
class EncoreMark extends StatelessWidget {
  const EncoreMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _MarkPainter());
}

/// The mark with the name beside it.
class EncoreWordmark extends StatelessWidget {
  const EncoreWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const EncoreMark(size: 30),
        const SizedBox(width: 10),
        Text(
          'Encore',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        ),
      ],
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  // tool/icons.py: (centre x, circumradius, opacity), back to front, in the
  // icon's unit square; corner radius and gap as there.
  static const _layers = [
    (0.32, 0.15, 0.28),
    (0.43, 0.195, 0.55),
    (0.56, 0.24, 1.0),
  ];
  static const _corner = 0.2;
  static const _gap = 0.03;

  // The mark's horizontal extent within the icon (back triangle's left edge
  // to the front tip), used to scale it to fill the widget.
  static const _left = 0.32 - 0.15 / 2;
  static const _right = 0.56 + 0.24;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / (_right - _left);
    Offset at(double x, double y) =>
        Offset((x - _left) * k, size.height / 2 + (y - 0.5) * k);

    Path triangle(double cx, double r) {
      final inner = r - 2 * _corner * r;
      final points = [
        for (final a in [0.0, 2 * pi / 3, 4 * pi / 3])
          at(cx + inner * cos(a), 0.5 + inner * sin(a)),
      ];
      return Path()..addPolygon(points, true);
    }

    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    for (final (cx, r, opacity) in _layers) {
      final path = triangle(cx, r);
      final stroke = 2 * _corner * r * k;
      // Cut a transparent gap around this (nearer) triangle first.
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke + 2 * _gap * k,
      );
      // A filled triangle stroked with round joins has rounded corners.
      final paint = Paint()
        ..shader = EncoreColors.brandGradient.createShader(bounds)
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke;
      canvas.drawPath(path, paint..style = PaintingStyle.fill);
      canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
