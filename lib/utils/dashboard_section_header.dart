import 'package:flutter/material.dart';

import '../app_theme.dart';

class DashboardSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const DashboardSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;

        return Container(
          width: double.infinity,
          margin: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            compact ? 7 : 12,
            compact ? 8 : 12,
            compact ? 5 : 7,
          ),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(compact ? 13 : 17),
            border: Border.all(
              color: AppTheme.fgGold.withValues(alpha: 0.52),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.fgNavyBlue.withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: compact ? 10 : 18,
                top: -30,
                child: Icon(
                  Icons.school_rounded,
                  size: compact ? 88 : 120,
                  color: Colors.white.withValues(alpha: 0.045),
                ),
              ),

              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 13 : 19,
                  vertical: compact ? 11 : 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 5 : 6,
                      height: compact ? 42 : 52,
                      decoration: BoxDecoration(
                        gradient: AppTheme.goldGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),

                    SizedBox(width: compact ? 10 : 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 17 : 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),

                          const SizedBox(height: 2),

                          Text(
                            subtitle,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.80),
                              fontSize: compact ? 12 : 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (trailing != null) ...[
                      SizedBox(width: compact ? 6 : 14),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
