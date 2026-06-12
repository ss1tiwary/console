import 'package:flutter/material.dart';

/// Resolve Console wordmark + icon mark.
/// Used on the shared landing screen via AuthConfig.logo.
class ConsoleLogo extends StatelessWidget {
  final double size;
  const ConsoleLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconMark(size: size),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RESOLVE',
              style: TextStyle(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: const Color(0xFF212529),
              ),
            ),
            Text(
              'CONSOLE',
              style: TextStyle(
                fontSize: size * 0.24,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.5,
                color: const Color(0xFF4263EB),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconMark extends StatelessWidget {
  final double size;
  const _IconMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF212529),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: CustomPaint(
        painter: _GridPainter(),
      ),
    );
  }
}

/// 3×3 dot grid with the bottom-right dot replaced by a filled accent square —
/// signals "active record / cursor" and ties the mark to the indigo palette.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dotColor = Color(0xFF6C757D);
    const accentColor = Color(0xFF4263EB);

    final dotR = size.width * 0.055;
    final gap = size.width * 0.26;
    final start = size.width * 0.26;

    final dot = Paint()..color = dotColor;
    final accent = Paint()..color = accentColor;

    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final x = start + col * gap;
        final y = start + row * gap;
        final isAccent = row == 2 && col == 2;
        if (isAccent) {
          final r = dotR * 1.5;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 2),
              Radius.circular(r * 0.4),
            ),
            accent,
          );
        } else {
          canvas.drawCircle(Offset(x, y), dotR, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
