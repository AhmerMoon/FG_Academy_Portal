import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/student_group_helper.dart';

class StudentStreamBadge extends StatelessWidget {
  const StudentStreamBadge({
    super.key,
    required this.classLevel,
    required this.subjects,
    this.onDark = false,
  });

  final int classLevel;
  final Iterable<String> subjects;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final label = studentStreamLabelForSubjects(classLevel, subjects);
    if (label == null) return const SizedBox.shrink();

    final (icon, color) = switch (label) {
      'Computer' || 'FCS' => (Icons.computer_outlined, AppTheme.info),
      'Biology' || 'Pre-Medical' => (Icons.biotech_outlined, AppTheme.danger),
      'Pre-Engineering' => (Icons.science_outlined, AppTheme.warning),
      _ => (Icons.tune_rounded, AppTheme.textSecondary),
    };
    final foreground = onDark ? Colors.white : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.13)
            : color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: onDark
              ? Colors.white.withValues(alpha: 0.35)
              : color.withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: onDark ? AppTheme.fgGold : color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
