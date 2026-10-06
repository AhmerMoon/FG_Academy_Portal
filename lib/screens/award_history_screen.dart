import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/fee_models.dart';
import '../models/portal_user.dart';
import 'award_list_preview_screen.dart';

class AwardHistoryScreen extends StatelessWidget {
  final SupabaseClient supabase;
  final PortalUser? user;
  final Map<String, dynamic> batch;
  final String subjectCode;

  final List<Map<String, dynamic>> tests;

  const AwardHistoryScreen({
    super.key,
    required this.supabase,
    required this.user,
    required this.batch,
    required this.subjectCode,
    required this.tests,
  });

  String _formatMarks(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  void _openPreview(BuildContext context, Map<String, dynamic> test) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AwardListPreviewScreen(
          supabase: supabase,
          user: user,
          batch: batch,
          test: test,
          subjectCode: subjectCode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(title: const Text('Award List History')),

      body: tests.isEmpty
          ? const Center(child: Text('No previous tests found.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: tests.length,
              itemBuilder: (context, index) {
                final test = tests[index];

                final testNo = (test['test_no'] as num?)?.toInt() ?? 0;

                final maxMarks = (test['max_marks'] as num?)?.toDouble() ?? 0;

                final date = DateTime.tryParse(
                  test['test_date']?.toString() ?? '',
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 23,
                          backgroundColor: AppTheme.fgNavyBlue.withValues(
                            alpha: 0.08,
                          ),
                          foregroundColor: AppTheme.fgNavyBlue,
                          child: Text(
                            'T$testNo',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${batch['name']} • '
                                '${feeSubjectLabel(subjectCode)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                '${date == null ? '-' : DateFormat('dd MMM yyyy').format(date)}'
                                '  •  Total: ${_formatMarks(maxMarks)}',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        IconButton(
                          tooltip: 'Preview & Share',
                          onPressed: () {
                            _openPreview(context, test);
                          },
                          icon: const FaIcon(
                            FontAwesomeIcons.whatsapp,
                            color: Color(0xFF25D366),
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
