import 'package:catchup/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Crisp vector-rendered CatchUP logo matching the uploaded brand identity:
/// - Jumping fish + checklist clipboard + dual cyan/blue ocean waves
/// - Bold "Catch" + "UP"
/// - Tagline: "EVERY CATCH COUNTS. EVERY STOCK MATTERS."
/// - Optional interactive `eyeOffset` (for cursor tracking on desktop & touch/typing tracking on mobile)
/// - Optional `eyesShy` (closes eyes into friendly arcs when entering password on mobile/touch)
class CatchUpLogo extends StatelessWidget {
  final double iconSize;
  final double fontSize;
  final bool showTagline;
  final bool? forDarkBackground;
  final bool iconOnly;
  final Offset? eyeOffset;
  final bool eyesShy;

  const CatchUpLogo({
    super.key,
    this.iconSize = 54,
    this.fontSize = 23,
    this.showTagline = false,
    this.forDarkBackground,
    this.iconOnly = false,
    this.eyeOffset,
    this.eyesShy = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final useLightInk = forDarkBackground ?? isDarkTheme;

    final primaryInk = useLightInk ? Colors.white : const Color(0xFF0A2E52);
    final cyanInk =
        useLightInk ? const Color(0xFF29C5F6) : const Color(0xFF0696C7);
    final deepWaveInk =
        useLightInk ? const Color(0xFF0284C7) : const Color(0xFF0C699E);

    final emblem = SizedBox(
      width: iconSize * 1.55,
      height: iconSize,
      child: CustomPaint(
        painter: _CatchUpEmblemPainter(
          primaryInk: primaryInk,
          cyanInk: cyanInk,
          deepWaveInk: deepWaveInk,
          eyeOffset: eyeOffset,
          eyesShy: eyesShy,
        ),
      ),
    );

    if (iconOnly || fontSize == 0) {
      return emblem;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        emblem,
        SizedBox(height: (iconSize * 0.06).clamp(4.0, 10.0)),
        // Crisp "CatchUP" wordmark
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.05,
            ),
            children: [
              TextSpan(
                text: 'Catch',
                style: TextStyle(color: primaryInk),
              ),
              TextSpan(
                text: 'UP',
                style: TextStyle(
                  color: cyanInk,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        if (showTagline) ...[
          SizedBox(height: (fontSize * 0.16).clamp(4.0, 12.0)),
          Text(
            'EVERY CATCH COUNTS. EVERY STOCK MATTERS.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primaryInk.withValues(alpha: 0.94),
              fontSize: (fontSize * 0.25).clamp(8.0, 18.5),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _CatchUpEmblemPainter extends CustomPainter {
  final Color primaryInk;
  final Color cyanInk;
  final Color deepWaveInk;
  final Offset? eyeOffset;
  final bool eyesShy;

  const _CatchUpEmblemPainter({
    required this.primaryInk,
    required this.cyanInk,
    required this.deepWaveInk,
    this.eyeOffset,
    this.eyesShy = false,
  });

  void _drawWatchingEye({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required Offset look,
  }) {
    const darkNavy = Color(0xFF07263E);

    final scleraPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = darkNavy
      ..style = PaintingStyle.stroke
      ..strokeWidth = (radius * 0.24).clamp(1.4, 3.0);

    canvas.drawCircle(center, radius, scleraPaint);
    canvas.drawCircle(center, radius, borderPaint);

    if (eyesShy) {
      // Closed happy arc when user is typing a hidden password
      final arcPaint = Paint()
        ..color = darkNavy
        ..style = PaintingStyle.stroke
        ..strokeWidth = (radius * 0.26).clamp(1.5, 3.2)
        ..strokeCap = StrokeCap.round;
      final arcPath = Path()
        ..moveTo(center.dx - radius * 0.55, center.dy + radius * 0.10)
        ..quadraticBezierTo(
          center.dx,
          center.dy - radius * 0.55,
          center.dx + radius * 0.55,
          center.dy + radius * 0.10,
        );
      canvas.drawPath(arcPath, arcPaint);
      return;
    }

    // Pupil + iris shift toward target
    final maxShift = radius * 0.44;
    final pupilCenter = Offset(
      center.dx + (look.dx.clamp(-1.0, 1.0) * maxShift),
      center.dy + (look.dy.clamp(-1.0, 1.0) * maxShift),
    );

    final irisPaint = Paint()
      ..color = cyanInk
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pupilCenter, radius * 0.54, irisPaint);

    final pupilPaint = Paint()
      ..color = darkNavy
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pupilCenter, radius * 0.34, pupilPaint);

    // Specular highlight dot
    final glintPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(
        pupilCenter.dx - radius * 0.14,
        pupilCenter.dy - radius * 0.14,
      ),
      (radius * 0.15).clamp(0.9, 2.6),
      glintPaint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = primaryInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = (h * 0.068).clamp(2.2, 10.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = primaryInk
      ..style = PaintingStyle.fill;

    // 1. Jumping Fish (left side, arching up and right)
    final fishOuter = Path()
      ..moveTo(w * 0.36, h * 0.88)
      ..cubicTo(w * 0.19, h * 0.65, w * 0.24, h * 0.22, w * 0.45, h * 0.11)
      ..cubicTo(w * 0.51, h * 0.08, w * 0.56, h * 0.10, w * 0.59, h * 0.14)
      ..cubicTo(w * 0.57, h * 0.32, w * 0.49, h * 0.44, w * 0.40, h * 0.49)
      ..cubicTo(w * 0.32, h * 0.56, w * 0.31, h * 0.72, w * 0.36, h * 0.88)
      ..close();
    canvas.drawPath(fishOuter, strokePaint);

    // Dorsal fin on upper-left of fish
    final dorsalFin = Path()
      ..moveTo(w * 0.31, h * 0.31)
      ..lineTo(w * 0.23, h * 0.24)
      ..quadraticBezierTo(w * 0.31, h * 0.16, w * 0.38, h * 0.17)
      ..close();
    canvas.drawPath(dorsalFin, fillPaint);

    // Side pectoral fin
    final sideFin = Path()
      ..moveTo(w * 0.44, h * 0.45)
      ..lineTo(w * 0.43, h * 0.58)
      ..lineTo(w * 0.50, h * 0.43)
      ..close();
    canvas.drawPath(sideFin, fillPaint);

    // Fish Eye (tracks cursor or mobile input when eyeOffset is provided)
    if (eyeOffset != null) {
      _drawWatchingEye(
        canvas: canvas,
        center: Offset(w * 0.48, h * 0.22),
        radius: (h * 0.084).clamp(4.0, 20.0),
        look: eyeOffset!,
      );
    } else {
      canvas.drawCircle(
        Offset(w * 0.49, h * 0.22),
        (h * 0.042).clamp(1.8, 6.5),
        fillPaint,
      );
    }

    // 2. Tilted Inventory Clipboard (right side)
    final boardPath = Path()
      ..moveTo(w * 0.59, h * 0.53)
      ..lineTo(w * 0.63, h * 0.24)
      ..quadraticBezierTo(w * 0.64, h * 0.20, w * 0.68, h * 0.21)
      ..lineTo(w * 0.83, h * 0.25)
      ..quadraticBezierTo(w * 0.87, h * 0.26, w * 0.86, h * 0.31)
      ..lineTo(w * 0.82, h * 0.61);
    canvas.drawPath(boardPath, strokePaint);

    // Clipboard top clip
    final clipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.75, h * 0.22),
        width: w * 0.13,
        height: h * 0.09,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(clipRect, fillPaint);

    if (eyeOffset != null) {
      // Pair of watching eyes perched on the clipboard clip
      final eyeR = (h * 0.072).clamp(3.5, 17.5);
      _drawWatchingEye(
        canvas: canvas,
        center: Offset(w * 0.71, h * 0.19),
        radius: eyeR,
        look: eyeOffset!,
      );
      _drawWatchingEye(
        canvas: canvas,
        center: Offset(w * 0.79, h * 0.21),
        radius: eyeR,
        look: eyeOffset!,
      );
    } else {
      canvas.drawCircle(
        Offset(w * 0.75, h * 0.16),
        (h * 0.04).clamp(1.6, 5.5),
        strokePaint,
      );
    }

    // Checkmarks & lines inside clipboard
    final checkPaint = Paint()
      ..color = primaryInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = (h * 0.048).clamp(1.6, 7.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final check1 = Path()
      ..moveTo(w * 0.65, h * 0.36)
      ..lineTo(w * 0.67, h * 0.39)
      ..lineTo(w * 0.71, h * 0.34);
    canvas.drawPath(check1, checkPaint);
    canvas.drawLine(
      Offset(w * 0.74, h * 0.37),
      Offset(w * 0.81, h * 0.39),
      checkPaint,
    );

    final check2 = Path()
      ..moveTo(w * 0.64, h * 0.47)
      ..lineTo(w * 0.66, h * 0.50)
      ..lineTo(w * 0.70, h * 0.45);
    canvas.drawPath(check2, checkPaint);
    canvas.drawLine(
      Offset(w * 0.73, h * 0.48),
      Offset(w * 0.80, h * 0.50),
      checkPaint,
    );

    // 3. Two-tone Ocean Waves below fish & clipboard
    final topWavePaint = Paint()
      ..color = cyanInk
      ..style = PaintingStyle.fill;
    final topWave = Path()
      ..moveTo(w * 0.36, h * 0.79)
      ..cubicTo(w * 0.48, h * 0.56, w * 0.62, h * 0.58, w * 0.74, h * 0.67)
      ..cubicTo(w * 0.80, h * 0.71, w * 0.85, h * 0.71, w * 0.90, h * 0.68)
      ..cubicTo(w * 0.82, h * 0.82, w * 0.69, h * 0.83, w * 0.57, h * 0.74)
      ..cubicTo(w * 0.49, h * 0.69, w * 0.42, h * 0.72, w * 0.36, h * 0.79)
      ..close();
    canvas.drawPath(topWave, topWavePaint);

    final bottomWavePaint = Paint()
      ..color = deepWaveInk
      ..style = PaintingStyle.fill;
    final bottomWave = Path()
      ..moveTo(w * 0.36, h * 0.85)
      ..cubicTo(w * 0.45, h * 0.73, w * 0.56, h * 0.76, w * 0.73, h * 0.87)
      ..cubicTo(w * 0.64, h * 0.93, w * 0.55, h * 0.89, w * 0.46, h * 0.94)
      ..cubicTo(w * 0.42, h * 0.96, w * 0.39, h * 0.91, w * 0.36, h * 0.85)
      ..close();
    canvas.drawPath(bottomWave, bottomWavePaint);
  }

  @override
  bool shouldRepaint(covariant _CatchUpEmblemPainter oldDelegate) {
    return oldDelegate.primaryInk != primaryInk ||
        oldDelegate.eyeOffset != eyeOffset ||
        oldDelegate.eyesShy != eyesShy;
  }
}

/// CatchUP logo indicator with "Loading..." label used for all page and section loading states.
class CatchUpLoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;

  const CatchUpLoadingIndicator({
    super.key,
    this.message = 'Loading...',
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CatchUpLogo(
              iconSize: size,
              fontSize: 22,
              showTagline: true,
              forDarkBackground: isDark,
            ),
            const SizedBox(height: 14),
            Text(
              'Loading...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.5,
                color: isDark ? Colors.white : AppColors.sidebarNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact CatchUP logo + "Loading..." indicator for buttons and inline actions.
class CatchUpButtonLoading extends StatelessWidget {
  final String label;
  final bool forDarkBackground;

  const CatchUpButtonLoading({
    super.key,
    this.label = 'Loading...',
    this.forDarkBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CatchUpLogo(
          iconSize: 22,
          fontSize: 0,
          iconOnly: true,
          forDarkBackground: forDarkBackground,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: forDarkBackground ? Colors.white : AppColors.sidebarNavy,
          ),
        ),
      ],
    );
  }
}

/// Decorative multi-layered ocean wave graphic for the bottom of the sidebar
/// and login/setup headers.
class SidebarBottomWave extends StatelessWidget {
  final double height;

  const SidebarBottomWave({super.key, this.height = 56});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: _BottomWavePainter(),
      ),
    );
  }
}

class _BottomWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final backWavePaint = Paint()
      ..color = AppColors.oceanWaveMid.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    final backPath = Path()
      ..moveTo(0, h * 0.45)
      ..quadraticBezierTo(w * 0.28, h * 0.10, w * 0.55, h * 0.42)
      ..quadraticBezierTo(w * 0.82, h * 0.72, w, h * 0.30)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(backPath, backWavePaint);

    final frontWavePaint = Paint()
      ..color = AppColors.oceanWaveLight.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final frontPath = Path()
      ..moveTo(0, h * 0.65)
      ..quadraticBezierTo(w * 0.25, h * 0.90, w * 0.52, h * 0.58)
      ..quadraticBezierTo(w * 0.78, h * 0.26, w, h * 0.62)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(frontPath, frontWavePaint);

    final crestPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final crestPath = Path()
      ..moveTo(0, h * 0.65)
      ..quadraticBezierTo(w * 0.25, h * 0.90, w * 0.52, h * 0.58)
      ..quadraticBezierTo(w * 0.78, h * 0.26, w, h * 0.62);
    canvas.drawPath(crestPath, crestPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
