import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/presentation/auth_providers.dart';

// ============================================================================
// MATHEMATICAL EASING ENGINE (PORTED PRECISELY FROM CANVAS ANIMATION)
// ============================================================================
class _Ease {
  static double clamp(double v, double min, double max) {
    return v < min ? min : (v > max ? max : v);
  }

  static double norm(double v, double a, double b) {
    if (a == b) return 0.0;
    return clamp((v - a) / (b - a), 0.0, 1.0);
  }

  static double lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  static double outCubic(double t) {
    final inv = 1.0 - t;
    return 1.0 - (inv * inv * inv);
  }

  static double inOutCubic(double t) {
    if (t < 0.5) {
      return 4.0 * t * t * t;
    } else {
      final inv = -2.0 * t + 2.0;
      return 1.0 - (inv * inv * inv) / 2.0;
    }
  }

  static double outBack(double t, [double s = 1.70158]) {
    final c3 = s + 1.0;
    final tm1 = t - 1.0;
    return 1.0 + c3 * (tm1 * tm1 * tm1) + s * (tm1 * tm1);
  }
}

// ============================================================================
// SPLASH SCREEN WIDGET WITH COLD-START LIFECYCLE GUARD
// ============================================================================
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// True once the cold-start animation has played in this OS process lifetime.
  /// When true, any subsequent app activation while in RAM completely skips the
  /// animation and routes immediately to the biometric / PIN unlock screen.
  static bool hasCompletedInitialColdSplash = false;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  bool _hasNavigated = false;

  static const int totalFrames = 41;
  static const int animFps = 14;
  // DURATION = 41 / 14 = ~2.92857 seconds
  static const Duration animDuration = Duration(milliseconds: 2930);

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: animDuration,
    );

    // Warm resume check: If already played in this process, skip immediately
    if (SplashScreen.hasCompletedInitialColdSplash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkVaultStatus(skipAnimation: true);
      });
      return;
    }

    _animController.forward();
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _checkVaultStatus(skipAnimation: false);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkVaultStatus({required bool skipAnimation}) async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    SplashScreen.hasCompletedInitialColdSplash = true;

    final keyService = ref.read(keyManagementServiceProvider);
    final session = ref.read(vaultSessionProvider);

    if (session.isUnlocked) {
      context.go('/dashboard');
      return;
    }

    final isInitialized = await keyService.isVaultInitialized();
    if (!mounted) return;

    if (!isInitialized) {
      context.go('/welcome');
    } else {
      context.go('/biometric-unlock');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1018),
      body: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, _) {
            final frameFloat = _animController.value * totalFrames;
            return CustomPaint(
              painter: _SafeVaultSplashPainter(
                frameFloat: frameFloat,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// NATIVE FLUTTER CANVAS PAINTER REPRODUCING THE EXACT HTML5 ANIMATION
// ============================================================================
class _SafeVaultSplashPainter extends CustomPainter {
  final double frameFloat;

  static const int totalFrames = 41;
  static const int stageSplitFrame = 28;
  static const bool onionSkin = true;

  _SafeVaultSplashPainter({required this.frameFloat});

  Path _traceSquircle(double cx, double cy, double size, [double exponent = 4.2]) {
    final half = size * 0.5;
    const steps = 64;
    final path = Path();
    for (int i = 0; i <= steps; i++) {
      final a = (i / steps) * math.pi * 2.0;
      final cosA = math.cos(a);
      final sinA = math.sin(a);
      final signCos = cosA < 0 ? -1.0 : (cosA > 0 ? 1.0 : 0.0);
      final signSin = sinA < 0 ? -1.0 : (sinA > 0 ? 1.0 : 0.0);
      final x = cx + half * signCos * math.pow(cosA.abs(), 2.0 / exponent);
      final y = cy + half * signSin * math.pow(sinA.abs(), 2.0 / exponent);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  Path _traceShieldDoc(double w, double h, double fold) {
    final hw = w * 0.5;
    final topY = -h * 0.5;
    final botY = h * 0.5;
    final shoulderY = h * 0.06;
    final r = w * 0.11;

    final path = Path();
    path.moveTo(0, topY);
    path.lineTo(hw - fold, topY);
    path.lineTo(hw, topY + fold);
    path.lineTo(hw, shoulderY);
    path.cubicTo(hw, h * 0.31, hw * 0.45, h * 0.43, 0, botY);
    path.cubicTo(-hw * 0.45, h * 0.43, -hw, h * 0.31, -hw, shoulderY);
    path.lineTo(-hw, topY + r);
    path.quadraticBezierTo(-hw, topY, -hw + r, topY);
    path.close();
    return path;
  }

  void _drawSafeVaultIcon(
    Canvas canvas, {
    required double x,
    required double y,
    required double size,
    double alpha = 1.0,
    double drawProgress = 1.0,
    double iconScale = 1.0,
    double innerScale = 1.0,
    double glowStrength = 0.0,
  }) {
    if (size <= 1.0 || alpha <= 0.01) return;

    canvas.save();
    final clampedAlpha = _Ease.clamp(alpha, 0.0, 1.0);
    canvas.translate(x, y);
    canvas.scale(iconScale, iconScale);

    // 1. Dark Navy Squircle Tile (#121D2D)
    final squirclePath = _traceSquircle(0, 0, size, 4.2);

    // Shadow
    final shadowPaint = Paint()
      ..color = glowStrength > 0.01
          ? Color.fromRGBO(234, 179, 8, _Ease.clamp(0.34 * glowStrength * clampedAlpha, 0.0, 1.0))
          : Color.fromRGBO(0, 0, 0, 0.48 * clampedAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * (0.22 + glowStrength * 0.24));

    canvas.save();
    canvas.translate(0, size * 0.08);
    canvas.drawPath(squirclePath, shadowPaint);
    canvas.restore();

    final bgPaint = Paint()
      ..color = const Color(0xFF121D2D).withValues(alpha: clampedAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawPath(squirclePath, bgPaint);

    // 2. Inner Squircle Border
    final innerSquircle = _traceSquircle(0, 0, size - 1.5, 4.2);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, size * 0.018)
      ..color = (glowStrength > 0.01
              ? Color.fromRGBO(16, 185, 129, _Ease.clamp(0.35 + glowStrength * 0.55, 0.0, 1.0))
              : const Color(0xFF233247))
          .withValues(alpha: clampedAlpha);
    canvas.drawPath(innerSquircle, borderPaint);

    // 3. SafeVault Split Shield-Document Emblem
    canvas.save();
    canvas.scale(innerScale, innerScale);

    final sw = size * 0.58;
    final sh = size * 0.68;
    final fold = sw * 0.26;
    final rimW = size * 0.056;

    final pShield = _Ease.norm(drawProgress, 0.0, 0.58);
    final pFold = _Ease.norm(drawProgress, 0.22, 0.72);

    if (pShield > 0.01) {
      canvas.save();
      // Reveal shield from top to bottom
      final clipTop = -sh * 0.56;
      final clipHeight = sh * 1.12 * pShield;
      canvas.clipRect(Rect.fromLTWH(-sw, clipTop, sw * 2, clipHeight));

      // Outer Rim: Left Half (Emerald Green)
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(-sw, -sh, sw, sh * 2));
      final greenGrad = ui.Gradient.linear(
        Offset(-sw * 0.5, -sh * 0.5),
        Offset(0, sh * 0.5),
        const [Color(0xFF4ADE80), Color(0xFF10B981), Color(0xFF047857)],
        [0.0, 0.5, 1.0],
      );
      final greenPaint = Paint()
        ..shader = greenGrad
        ..color = Colors.white.withValues(alpha: clampedAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawPath(_traceShieldDoc(sw, sh, fold), greenPaint);
      canvas.restore();

      // Outer Rim: Right Half (Metallic Gold)
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, -sh, sw, sh * 2));
      final goldGrad = ui.Gradient.linear(
        Offset(0, -sh * 0.5),
        Offset(sw * 0.5, sh * 0.5),
        const [Color(0xFFFDE047), Color(0xFFEAB308), Color(0xFFA16207)],
        [0.0, 0.5, 1.0],
      );
      final goldPaint = Paint()
        ..shader = goldGrad
        ..color = Colors.white.withValues(alpha: clampedAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawPath(_traceShieldDoc(sw, sh, fold), goldPaint);
      canvas.restore();

      // Inner Dark Navy Shield Body (Two-tone split)
      canvas.save();
      final innerShieldPath = _traceShieldDoc(sw - rimW * 2, sh - rimW * 2, fold * 0.78);
      canvas.clipPath(innerShieldPath);

      // Left half interior
      canvas.drawRect(
        Rect.fromLTWH(-sw, -sh, sw, sh * 2),
        Paint()..color = const Color(0xFF162C46).withValues(alpha: clampedAlpha),
      );
      // Right half interior
      canvas.drawRect(
        Rect.fromLTWH(0, -sh, sw, sh * 2),
        Paint()..color = const Color(0xFF0E2036).withValues(alpha: clampedAlpha),
      );

      // Crisp inner rim highlight
      final innerHighlight = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, size * 0.012)
        ..color = Color.fromRGBO(255, 255, 255, 0.14 * clampedAlpha);
      canvas.drawPath(innerShieldPath, innerHighlight);
      canvas.restore();

      // Top-Right Folded Document Corner Flap
      if (pFold > 0.01) {
        final hw = sw * 0.5;
        final topY = -sh * 0.5;
        final flapCornerX = _Ease.lerp(hw, hw - fold, pFold);
        final flapCornerY = _Ease.lerp(topY, topY + fold, pFold);
        final flapR = fold * 0.24;

        final flapGrad = ui.Gradient.linear(
          Offset(hw - fold, topY + fold),
          Offset(hw - fold * 0.2, topY + fold * 0.2),
          const [Color(0xFFFEF08A), Color(0xFFFACC15), Color(0xFFCA8A04)],
          [0.0, 0.55, 1.0],
        );

        final flapPath = Path();
        flapPath.moveTo(hw - fold, topY);
        flapPath.lineTo(hw, topY + fold);
        flapPath.lineTo(flapCornerX + flapR, flapCornerY);
        flapPath.quadraticBezierTo(flapCornerX, flapCornerY, flapCornerX, flapCornerY - flapR);
        flapPath.close();

        // Subtle drop shadow under flap
        final flapShadow = Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.45 * clampedAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.04);
        canvas.save();
        canvas.translate(-size * 0.012, size * 0.015);
        canvas.drawPath(flapPath, flapShadow);
        canvas.restore();

        final flapPaint = Paint()
          ..shader = flapGrad
          ..color = Colors.white.withValues(alpha: clampedAlpha)
          ..style = PaintingStyle.fill;
        canvas.drawPath(flapPath, flapPaint);
      }

      canvas.restore(); // Clip top-to-bottom
    }

    // 4. Three Horizontal Silver Document Bars
    final barH = math.max(2.6, size * 0.044);
    final barW = sw * 0.52;
    final barYs = [-sh * 0.09, sh * 0.03, sh * 0.15];
    final barStarts = [0.24, 0.36, 0.48];

    for (int i = 0; i < 3; i++) {
      final pBar = _Ease.outCubic(_Ease.norm(drawProgress, barStarts[i], barStarts[i] + 0.46));
      if (pBar <= 0.01) continue;

      final curW = barW * pBar;
      final bx = -barW * 0.5;
      final by = barYs[i] - barH * 0.5;
      final rad = barH * 0.5;

      final silverGrad = ui.Gradient.linear(
        Offset(bx, by),
        Offset(bx + barW, by),
        const [Color(0xFFCBD5E1), Color(0xFFFFFFFF), Color(0xFF94A3B8)],
        [0.0, 0.5, 1.0],
      );

      final barPaint = Paint()
        ..shader = silverGrad
        ..color = Colors.white.withValues(alpha: clampedAlpha)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, curW, barH), Radius.circular(rad)),
        barPaint,
      );
    }

    canvas.restore(); // Emblem scale
    canvas.restore(); // Main translate/scale
  }

  void _drawSparkleAccents(
    Canvas canvas,
    double cx,
    double cy,
    double iconSize,
    double frameFloat,
  ) {
    final sparkles = [
      {'dx': -0.68, 'dy': -0.56, 'start': 6.0, 'dur': 11.0, 'color': const Color(0xFF10B981), 'r': 6.0},
      {'dx': 0.72, 'dy': -0.52, 'start': 11.0, 'dur': 11.0, 'color': const Color(0xFFFACC15), 'r': 7.0},
      {'dx': -0.62, 'dy': 0.58, 'start': 15.0, 'dur': 10.0, 'color': const Color(0xFF34D399), 'r': 5.5},
    ];

    for (final sp in sparkles) {
      final start = sp['start'] as double;
      final dur = sp['dur'] as double;
      final p = _Ease.norm(frameFloat, start, start + dur);
      if (p <= 0.0 || p >= 1.0) continue;

      final env = math.sin(p * math.pi);
      final dx = sp['dx'] as double;
      final dy = sp['dy'] as double;
      final sx = cx + dx * iconSize * (0.95 + p * 0.22);
      final sy = cy + dy * iconSize * (0.95 + p * 0.22);
      final rad = (sp['r'] as double) * env;

      canvas.save();
      canvas.translate(sx, sy);
      canvas.rotate(p * 0.8);

      final starPath = Path();
      starPath.moveTo(0, -rad);
      starPath.quadraticBezierTo(0, 0, rad, 0);
      starPath.quadraticBezierTo(0, 0, 0, rad);
      starPath.quadraticBezierTo(0, 0, -rad, 0);
      starPath.quadraticBezierTo(0, 0, 0, -rad);
      starPath.close();

      final paint = Paint()
        ..color = (sp['color'] as Color).withValues(alpha: env * 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawPath(starPath, paint);
      canvas.restore();
    }
  }

  void _drawWordmark(
    Canvas canvas, {
    required double startX,
    required double centerY,
    required double fontSize,
    required double introT,
    double retractT = 0.0,
    double? clipLeftX,
  }) {
    const word = 'SafeVault';

    canvas.save();
    if (clipLeftX != null) {
      canvas.clipRect(Rect.fromLTWH(clipLeftX, 0, 4000, 4000));
    }

    // Pre-measure total width
    final testSpan = TextSpan(
      text: word,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
      ),
    );
    final totalPainter = TextPainter(text: testSpan, textDirection: TextDirection.ltr);
    totalPainter.layout();
    final totalWidth = totalPainter.width;

    final vaultGrad = ui.Gradient.linear(
      Offset(startX + totalWidth * 0.45, centerY - fontSize * 0.4),
      Offset(startX + totalWidth, centerY + fontSize * 0.4),
      const [Color(0xFFFACC15), Color(0xFFEAB308)],
      [0.0, 1.0],
    );

    final slideBackX = -_Ease.inOutCubic(retractT) * (totalWidth + fontSize * 0.65);

    double penX = startX;
    for (int i = 0; i < word.length; i++) {
      final ch = word[i];
      final isVaultPart = i >= 4; // "Vault" in metallic gold, "Safe" in crisp white

      final charSpan = TextSpan(
        text: ch,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
        ),
      );
      final chPainter = TextPainter(text: charSpan, textDirection: TextDirection.ltr);
      chPainter.layout();
      final chWidth = chPainter.width;
      final chHeight = chPainter.height;

      final charStart = (i / word.length) * 0.52;
      final charEnd = charStart + 0.48;
      final localIn = _Ease.norm(introT, charStart, charEnd);
      final springScale = _Ease.outBack(localIn, 1.85);
      final alpha = _Ease.clamp(localIn * 1.45, 0.0, 1.0) * (1.0 - _Ease.norm(retractT, 0.45, 0.95));

      if (alpha > 0.01 && springScale > 0.01) {
        final liftY = (1.0 - _Ease.outCubic(localIn)) * fontSize * 0.36;
        final drawX = penX + slideBackX;

        // Onion-skin ghost trail
        if (onionSkin && localIn > 0.06 && localIn < 0.88 && retractT == 0.0) {
          canvas.save();
          canvas.translate(drawX + chWidth * 0.5, centerY + liftY * 1.75);
          canvas.scale(springScale * 0.9, springScale * 0.9);
          final ghostPaint = Paint()
            ..color = (isVaultPart ? const Color(0xFFFACC15) : const Color(0xFF10B981))
                .withValues(alpha: 0.22 * (1.0 - localIn));
          final ghostPainter = TextPainter(
            text: TextSpan(
              text: ch,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
                foreground: ghostPaint,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          ghostPainter.layout();
          ghostPainter.paint(canvas, Offset(-chWidth * 0.5, -chHeight * 0.5));
          canvas.restore();
        }

        canvas.save();
        canvas.translate(drawX + chWidth * 0.5, centerY + liftY);
        canvas.scale(springScale, springScale);

        final charPaint = Paint();
        if (isVaultPart) {
          charPaint.shader = vaultGrad;
          charPaint.color = Colors.white.withValues(alpha: alpha);
        } else {
          charPaint.color = const Color(0xFFF8FAFC).withValues(alpha: alpha);
        }

        final livePainter = TextPainter(
          text: TextSpan(
            text: ch,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              foreground: charPaint,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        livePainter.layout();
        livePainter.paint(canvas, Offset(-chWidth * 0.5, -chHeight * 0.5));
        canvas.restore();
      }

      penX += chWidth;
    }

    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 1. Dark Background (#0B1018)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF0B1018),
    );

    // 2. Ambient Radial Glow (Emerald & Gold)
    final cx = w * 0.5;
    final cy = h * 0.5;
    final minDim = math.min(w, h);

    final radGlow = ui.Gradient.radial(
      Offset(cx, cy),
      minDim * 0.55,
      const [
        Color.fromRGBO(16, 185, 129, 0.11),
        Color.fromRGBO(234, 179, 8, 0.05),
        Color.fromRGBO(0, 0, 0, 0.0),
      ],
      [0.0, 0.55, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = radGlow,
    );

    // 4. Responsive Sizing
    final iconSize = _Ease.clamp(minDim * 0.21, 60.0, 120.0);
    final fontSize = (iconSize * 0.60).roundToDouble();
    final gap = (iconSize * 0.22).roundToDouble();

    // Measure total lockup width
    final measureSpan = TextSpan(
      text: 'SafeVault',
      style: TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
      ),
    );
    final measurePainter = TextPainter(text: measureSpan, textDirection: TextDirection.ltr);
    measurePainter.layout();
    final wordWidth = measurePainter.width;

    final lockupWidth = iconSize + gap + wordWidth;
    final leftLockupIconX = cx - lockupWidth * 0.5 + iconSize * 0.5;

    // 5. Staging (Split at Frame 28)
    if (frameFloat <= stageSplitFrame) {
      final p1 = _Ease.norm(frameFloat, 0.0, stageSplitFrame.toDouble());
      final popScale = _Ease.outBack(_Ease.norm(p1, 0.0, 0.42), 1.85);
      final strokeDraw = _Ease.outCubic(_Ease.norm(p1, 0.06, 0.66));
      final textIntro = _Ease.norm(p1, 0.12, 0.88);
      final slideLeft = _Ease.outCubic(_Ease.norm(p1, 0.08, 0.52));

      final iconX = _Ease.lerp(cx, leftLockupIconX, slideLeft);
      final textX = iconX + iconSize * 0.5 + gap;

      if (onionSkin && p1 > 0.04 && p1 < 0.48) {
        _drawSafeVaultIcon(
          canvas,
          x: _Ease.lerp(cx, iconX, 0.6),
          y: cy,
          size: iconSize * popScale * 0.94,
          alpha: 0.2 * (1.0 - p1 * 2.0),
          drawProgress: strokeDraw,
        );
      }

      _drawWordmark(
        canvas,
        startX: textX,
        centerY: cy,
        fontSize: fontSize,
        introT: textIntro,
        retractT: 0.0,
        clipLeftX: iconX,
      );

      _drawSafeVaultIcon(
        canvas,
        x: iconX,
        y: cy,
        size: iconSize * popScale,
        drawProgress: strokeDraw,
      );

      _drawSparkleAccents(canvas, iconX, cy, iconSize, frameFloat);
    } else {
      final p2 = _Ease.norm(frameFloat, stageSplitFrame.toDouble(), totalFrames.toDouble());
      final retractT = _Ease.norm(p2, 0.0, 0.72);
      final centerGlide = _Ease.inOutCubic(_Ease.norm(p2, 0.12, 0.88));

      final iconX = _Ease.lerp(leftLockupIconX, cx, centerGlide);
      final textX = iconX + iconSize * 0.5 + gap;

      final beatEnv = math.sin(_Ease.norm(p2, 0.18, 1.0) * math.pi);
      final elasticScale = 1.0 + beatEnv * 0.13;
      final innerBeat = 1.0 + beatEnv * 0.09;
      final baseGrow = _Ease.lerp(1.0, 1.12, centerGlide);

      if (retractT < 0.98) {
        _drawWordmark(
          canvas,
          startX: textX,
          centerY: cy,
          fontSize: fontSize,
          introT: 1.0,
          retractT: retractT,
          clipLeftX: iconX,
        );
      }

      if (onionSkin && beatEnv > 0.15) {
        _drawSafeVaultIcon(
          canvas,
          x: iconX,
          y: cy,
          size: iconSize * baseGrow * (1.0 + beatEnv * 0.2),
          alpha: 0.16 * beatEnv,
          drawProgress: 1.0,
        );
      }

      _drawSafeVaultIcon(
        canvas,
        x: iconX,
        y: cy,
        size: iconSize * baseGrow,
        iconScale: elasticScale,
        innerScale: innerBeat,
        drawProgress: 1.0,
        glowStrength: beatEnv,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SafeVaultSplashPainter oldDelegate) {
    return oldDelegate.frameFloat != frameFloat;
  }
}
