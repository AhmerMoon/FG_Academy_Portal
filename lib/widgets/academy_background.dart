import 'package:flutter/material.dart';

import '../app_theme.dart';

class AcademyBackground extends StatelessWidget {
  final Widget child;

  final double imageOpacity;

  const AcademyBackground({
    super.key,
    required this.child,
    this.imageOpacity = 0.23,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // School photograph clearly visible.
        Image.asset(
          'assets/images/school_bg.png',
          fit: BoxFit.cover,
          opacity: AlwaysStoppedAnimation<double>(imageOpacity),
        ),

        // Warm academic overlay:
        // enough readability without killing the photograph.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.backgroundLight.withValues(alpha: 0.80),
                AppTheme.academyIvory.withValues(alpha: 0.84),
                Colors.white.withValues(alpha: 0.80),
              ],
              stops: const [0, 0.58, 1],
            ),
          ),
        ),

        // Institutional decorative gold glow.
        Positioned(
          right: -120,
          top: -130,
          child: IgnorePointer(
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.fgGold.withValues(alpha: 0.055),
              ),
            ),
          ),
        ),

        // Subtle navy visual anchor.
        Positioned(
          left: -150,
          bottom: -170,
          child: IgnorePointer(
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.fgNavyBlue.withValues(alpha: 0.035),
              ),
            ),
          ),
        ),

        Positioned.fill(child: child),
      ],
    );
  }
}
