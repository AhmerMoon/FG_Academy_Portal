import 'package:flutter/material.dart';

import '../app_theme.dart';

class StudentTrackingBadges extends StatelessWidget {
  const StudentTrackingBadges({
    super.key,
    required this.student,
    this.longAbsent = false,
  });

  final dynamic student;
  final bool longAbsent;

  bool get _isNew {
    final created = DateTime.tryParse(
      student['created_at']?.toString() ?? '',
    )?.toLocal();
    if (created == null) return false;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
            .difference(DateTime(created.year, created.month, created.day))
            .inDays <
        7;
  }

  bool get _missingContact =>
      (student['contact_number']?.toString().trim() ?? '').isEmpty;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    if (_isNew) badges.add(const _Badge('NEW', AppTheme.info));
    if (_missingContact) {
      badges.add(const _Badge('NO CONTACT', AppTheme.warning));
    }
    if (longAbsent) badges.add(const _Badge('4+ ABSENT', AppTheme.danger));
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 5, runSpacing: 4, children: badges),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
