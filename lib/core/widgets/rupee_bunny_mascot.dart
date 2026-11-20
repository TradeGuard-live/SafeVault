import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme_colors.dart';
import '../theme/app_theme.dart';

enum MascotPose {
  happy,       // Holding golden coin with a happy smile
  saving,      // Hugging a cute savings coin pouch
  thinking,    // Tilted ear, paw on chin for empty/filter states
  celebration, // Both paws raised with cheerful confetti
  sleeping,    // Peaceful snooze with closed eyes and z's
  travel,      // Traveling bunny with a cute mini backpack
  friendly,    // Waving a paw warmly for friendly welcome
}

/// Original RupeeFlow mascot: "Peachy the Bunny".
/// Rendered 100% offline using high-performance Flutter CustomPainter primitives
/// with crisp vector scaling, zero network dependencies, and gentle floating micro-animation.
class RupeeBunnyMascot extends StatefulWidget {
  final MascotPose pose;
  final double size;
  final bool animated;

  const RupeeBunnyMascot({
    super.key,
    required this.pose,
    this.size = 110,
    this.animated = true,
  });

  @override
  State<RupeeBunnyMascot> createState() => _RupeeBunnyMascotState();
}

class _RupeeBunnyMascotState extends State<RupeeBunnyMascot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _animation = Tween<double>(begin: -3.5, end: 3.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.animated) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant RupeeBunnyMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated != oldWidget.animated) {
      if (widget.animated) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0.5;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.of(context);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, widget.animated ? _animation.value : 0),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _BunnyPainter(
                pose: widget.pose,
                themeColors: themeColors,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BunnyPainter extends CustomPainter {
  final MascotPose pose;
  final AppThemeColors themeColors;

  _BunnyPainter({required this.pose, required this.themeColors});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 120.0;
    final strokeWidth = 2.2 * scale;

    const bodyCream = Color(0xFFFFFDF8);
    final outlineBrown = themeColors.isDark ? const Color(0xFF393149) : const Color(0xFF4A3028);
    final innerEarPeach = themeColors.primaryPeach;
    final blushPink = themeColors.accentPink;
    final coinGold = themeColors.warmYellow;
    final primaryAccent = themeColors.primaryAccent;

    final mainStroke = Paint()
      ..color = outlineBrown
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bodyFill = Paint()
      ..color = bodyCream
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2.0;
    final headCenterY = size.height * 0.52;
    final headRadiusX = 32.0 * scale;
    final headRadiusY = 28.0 * scale;

    // 1. Draw Ears based on Pose
    switch (pose) {
      case MascotPose.thinking:
        _drawEar(canvas, centerX - 14 * scale, headCenterY - 22 * scale, -22, scale, bodyFill, innerEarPeach, mainStroke);
        _drawEar(canvas, centerX + 14 * scale, headCenterY - 24 * scale, 10, scale, bodyFill, innerEarPeach, mainStroke);
        break;
      case MascotPose.sleeping:
        _drawEar(canvas, centerX - 16 * scale, headCenterY - 18 * scale, -48, scale * 0.9, bodyFill, innerEarPeach, mainStroke);
        _drawEar(canvas, centerX + 16 * scale, headCenterY - 18 * scale, 48, scale * 0.9, bodyFill, innerEarPeach, mainStroke);
        break;
      case MascotPose.celebration:
        _drawEar(canvas, centerX - 15 * scale, headCenterY - 25 * scale, -14, scale * 1.05, bodyFill, innerEarPeach, mainStroke);
        _drawEar(canvas, centerX + 15 * scale, headCenterY - 25 * scale, 14, scale * 1.05, bodyFill, innerEarPeach, mainStroke);
        break;
      default:
        _drawEar(canvas, centerX - 14 * scale, headCenterY - 24 * scale, -8, scale, bodyFill, innerEarPeach, mainStroke);
        _drawEar(canvas, centerX + 14 * scale, headCenterY - 24 * scale, 8, scale, bodyFill, innerEarPeach, mainStroke);
        break;
    }

    // 2. Draw Bunny Body / Paws
    final bodyRect = Rect.fromCenter(
      center: Offset(centerX, headCenterY + 28 * scale),
      width: 44 * scale,
      height: 34 * scale,
    );
    canvas.drawOval(bodyRect, bodyFill);
    canvas.drawOval(bodyRect, mainStroke);

    // 3. Draw Head
    final headRect = Rect.fromCenter(
      center: Offset(centerX, headCenterY),
      width: headRadiusX * 2,
      height: headRadiusY * 2,
    );
    canvas.drawOval(headRect, bodyFill);
    canvas.drawOval(headRect, mainStroke);

    // 4. Draw Blush Cheeks
    final blushPaint = Paint()
      ..color = blushPink.withOpacity(0.65)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX - 18 * scale, headCenterY + 6 * scale), 6.5 * scale, blushPaint);
    canvas.drawCircle(Offset(centerX + 18 * scale, headCenterY + 6 * scale), 6.5 * scale, blushPaint);

    // 5. Draw Eyes
    if (pose == MascotPose.sleeping) {
      // Curved sleeping snooze eyes
      final eyePaint = Paint()
        ..color = outlineBrown
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale
        ..strokeCap = StrokeCap.round;

      final leftArc = Path()
        ..moveTo(centerX - 17 * scale, headCenterY - 2 * scale)
        ..quadraticBezierTo(centerX - 12 * scale, headCenterY + 3 * scale, centerX - 7 * scale, headCenterY - 2 * scale);
      canvas.drawPath(leftArc, eyePaint);

      final rightArc = Path()
        ..moveTo(centerX + 7 * scale, headCenterY - 2 * scale)
        ..quadraticBezierTo(centerX + 12 * scale, headCenterY + 3 * scale, centerX + 17 * scale, headCenterY - 2 * scale);
      canvas.drawPath(rightArc, eyePaint);
    } else {
      // Big sparkling happy eyes
      final eyePaint = Paint()..color = outlineBrown..style = PaintingStyle.fill;
      final highlightPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;

      // Left eye
      canvas.drawCircle(Offset(centerX - 12 * scale, headCenterY - 2 * scale), 4.2 * scale, eyePaint);
      canvas.drawCircle(Offset(centerX - 13.5 * scale, headCenterY - 3.5 * scale), 1.5 * scale, highlightPaint);

      // Right eye
      canvas.drawCircle(Offset(centerX + 12 * scale, headCenterY - 2 * scale), 4.2 * scale, eyePaint);
      canvas.drawCircle(Offset(centerX + 10.5 * scale, headCenterY - 3.5 * scale), 1.5 * scale, highlightPaint);
    }

    // 6. Cute Little Nose & Smiling Mouth
    final nosePaint = Paint()..color = themeColors.deepPeach..style = PaintingStyle.fill;
    final nosePath = Path()
      ..moveTo(centerX - 2.5 * scale, headCenterY + 3 * scale)
      ..lineTo(centerX + 2.5 * scale, headCenterY + 3 * scale)
      ..lineTo(centerX, headCenterY + 5.5 * scale)
      ..close();
    canvas.drawPath(nosePath, nosePaint);

    final mouthPaint = Paint()
      ..color = outlineBrown
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round;

    final mouthPath = Path()
      ..moveTo(centerX - 6 * scale, headCenterY + 8 * scale)
      ..quadraticBezierTo(centerX - 3 * scale, headCenterY + 11 * scale, centerX, headCenterY + 8.5 * scale)
      ..quadraticBezierTo(centerX + 3 * scale, headCenterY + 11 * scale, centerX + 6 * scale, headCenterY + 8 * scale);
    canvas.drawPath(mouthPath, mouthPaint);

    // 7. Paws & Pose Props
    switch (pose) {
      case MascotPose.happy:
        // Golden Coin held happily
        final coinPaint = Paint()..color = coinGold..style = PaintingStyle.fill;
        final coinBorder = Paint()
          ..color = outlineBrown
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * scale;
        final coinCenter = Offset(centerX, headCenterY + 28 * scale);
        canvas.drawCircle(coinCenter, 13 * scale, coinPaint);
        canvas.drawCircle(coinCenter, 13 * scale, coinBorder);
        // Rupee / Vault Emblem inside coin
        final emblemPaint = Paint()
          ..color = outlineBrown
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 * scale;
        canvas.drawLine(
          Offset(coinCenter.dx - 4 * scale, coinCenter.dy - 3 * scale),
          Offset(coinCenter.dx + 4 * scale, coinCenter.dy - 3 * scale),
          emblemPaint,
        );
        canvas.drawLine(
          Offset(coinCenter.dx - 4 * scale, coinCenter.dy),
          Offset(coinCenter.dx + 4 * scale, coinCenter.dy),
          emblemPaint,
        );

        // Paws holding coin
        canvas.drawCircle(Offset(centerX - 13 * scale, headCenterY + 28 * scale), 4.5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX - 13 * scale, headCenterY + 28 * scale), 4.5 * scale, mainStroke);
        canvas.drawCircle(Offset(centerX + 13 * scale, headCenterY + 28 * scale), 4.5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX + 13 * scale, headCenterY + 28 * scale), 4.5 * scale, mainStroke);
        break;

      case MascotPose.saving:
        // Savings Pouch
        final pouchPaint = Paint()..color = themeColors.mint..style = PaintingStyle.fill;
        final pouchBorder = Paint()
          ..color = outlineBrown
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * scale;
        final pouchRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(centerX, headCenterY + 29 * scale), width: 26 * scale, height: 22 * scale),
          Radius.circular(8 * scale),
        );
        canvas.drawRRect(pouchRect, pouchPaint);
        canvas.drawRRect(pouchRect, pouchBorder);

        // Ribbon tie
        final tiePaint = Paint()..color = primaryAccent..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(centerX, headCenterY + 20 * scale), 3 * scale, tiePaint);

        // Paws hugging pouch
        canvas.drawCircle(Offset(centerX - 12 * scale, headCenterY + 27 * scale), 4.5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX - 12 * scale, headCenterY + 27 * scale), 4.5 * scale, mainStroke);
        canvas.drawCircle(Offset(centerX + 12 * scale, headCenterY + 27 * scale), 4.5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX + 12 * scale, headCenterY + 27 * scale), 4.5 * scale, mainStroke);
        break;

      case MascotPose.thinking:
        // Paw on chin
        canvas.drawCircle(Offset(centerX - 8 * scale, headCenterY + 16 * scale), 5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX - 8 * scale, headCenterY + 16 * scale), 5 * scale, mainStroke);

        // Little question sparkle
        final sparkPaint = Paint()
          ..color = primaryAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * scale
          ..strokeCap = StrokeCap.round;
        final sx = centerX + 26 * scale;
        final sy = headCenterY - 14 * scale;
        canvas.drawLine(Offset(sx - 4 * scale, sy), Offset(sx + 4 * scale, sy), sparkPaint);
        canvas.drawLine(Offset(sx, sy - 4 * scale), Offset(sx, sy + 4 * scale), sparkPaint);
        break;

      case MascotPose.celebration:
        // Raised paws!
        canvas.drawCircle(Offset(centerX - 24 * scale, headCenterY - 8 * scale), 5.5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX - 24 * scale, headCenterY - 8 * scale), 5.5 * scale, mainStroke);
        canvas.drawCircle(Offset(centerX + 24 * scale, headCenterY - 8 * scale), 5.5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX + 24 * scale, headCenterY - 8 * scale), 5.5 * scale, mainStroke);

        // Confetti dots
        final colors = [themeColors.primaryPeach, themeColors.mint, themeColors.softLavender, coinGold];
        final confettiOffsets = [
          Offset(centerX - 36 * scale, headCenterY - 26 * scale),
          Offset(centerX + 34 * scale, headCenterY - 28 * scale),
          Offset(centerX - 28 * scale, headCenterY + 6 * scale),
          Offset(centerX + 30 * scale, headCenterY + 8 * scale),
        ];
        for (int i = 0; i < confettiOffsets.length; i++) {
          final cPaint = Paint()..color = colors[i % colors.length]..style = PaintingStyle.fill;
          canvas.drawCircle(confettiOffsets[i], 3.2 * scale, cPaint);
        }
        break;

      case MascotPose.sleeping:
        // Gentle "z z Z" text
        final textPainter = TextPainter(
          text: TextSpan(
            text: 'z z Z',
            style: TextStyle(
              color: outlineBrown.withOpacity(0.7),
              fontSize: 12 * scale,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(centerX + 24 * scale, headCenterY - 28 * scale));
        break;

      case MascotPose.friendly:
      default:
        // Cheerful waving paw
        canvas.drawCircle(Offset(centerX + 22 * scale, headCenterY - 2 * scale), 5.5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX + 22 * scale, headCenterY - 2 * scale), 5.5 * scale, mainStroke);
        canvas.drawCircle(Offset(centerX - 10 * scale, headCenterY + 26 * scale), 5 * scale, bodyFill);
        canvas.drawCircle(Offset(centerX - 10 * scale, headCenterY + 26 * scale), 5 * scale, mainStroke);
        break;
    }
  }

  void _drawEar(
    Canvas canvas,
    double baseX,
    double baseY,
    double tiltAngleDegrees,
    double scale,
    Paint bodyFill,
    Color innerColor,
    Paint stroke,
  ) {
    canvas.save();
    canvas.translate(baseX, baseY);
    canvas.rotate(tiltAngleDegrees * math.pi / 180.0);

    final earRect = Rect.fromCenter(
      center: Offset(0, -22 * scale),
      width: 15 * scale,
      height: 44 * scale,
    );
    final earRRect = RRect.fromRectAndRadius(earRect, Radius.circular(8 * scale));
    canvas.drawRRect(earRRect, bodyFill);
    canvas.drawRRect(earRRect, stroke);

    final innerRect = Rect.fromCenter(
      center: Offset(0, -20 * scale),
      width: 8 * scale,
      height: 32 * scale,
    );
    final innerRRect = RRect.fromRectAndRadius(innerRect, Radius.circular(5 * scale));
    final innerPaint = Paint()..color = innerColor.withOpacity(0.85)..style = PaintingStyle.fill;
    canvas.drawRRect(innerRRect, innerPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BunnyPainter oldDelegate) {
    return oldDelegate.pose != pose || oldDelegate.themeColors != themeColors;
  }
}

