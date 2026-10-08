import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/fee_models.dart';
import '../models/portal_user.dart';
import 'award_list_preview_screen.dart';
import 'award_progress_screen.dart';

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

  void _openTestPreview(BuildContext context, Map<String, dynamic> test) {
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

  void _openProgress(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AwardProgressScreen(
          supabase: supabase,
          user: user,
          batch: batch,
          subjectCode: subjectCode,
          tests: tests,
        ),
      ),
    );
  }

  bool _canDeleteTest(Map<String, dynamic> test) {
    final currentUser = user;

    if (currentUser == null) {
      return false;
    }

    if (currentUser.isAdmin) {
      return true;
    }

    return test['created_by']?.toString() == currentUser.userId;
  }

  Future<void> _deleteTest(
    BuildContext context,
    Map<String, dynamic> test,
  ) async {
    final testNo = (test['test_no'] as num?)?.toInt() ?? 0;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text('Delete T$testNo?'),
              content: Text(
                'This will permanently delete '
                'T$testNo and all marks saved '
                'for this test.\n\n'
                'This action cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(dialogContext, true);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete Test'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    try {
      await supabase.rpc(
        'delete_award_test',
        params: {'p_test_id': test['id'].toString()},
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('T$testNo deleted successfully.'),
          backgroundColor: AppTheme.success,
        ),
      );

      // Return to Award Lists screen.
      // Parent reloads fresh tests automatically.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete T$testNo.\n$e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: const Text('Award List History')),
      body: tests.isEmpty
          ? const Center(child: Text('No previous tests found.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      _openProgress(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppTheme.fgNavyBlue.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.trending_up_rounded,
                              color: AppTheme.fgNavyBlue,
                              size: 29,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'All Tests Progress',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${batch['name']} • '
                                  '${feeSubjectLabel(subjectCode)} • '
                                  '${tests.length} '
                                  '${tests.length == 1 ? 'test' : 'tests'} • '
                                  'Combined progress',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 17, 4, 9),
                  child: Text(
                    'Individual Tests',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.fgNavyBlue,
                    ),
                  ),
                ),

                ...tests.map((test) {
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
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
                                  ' • Total: ${_formatMarks(maxMarks)}',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Preview & Share',
                            onPressed: () {
                              _openTestPreview(context, test);
                            },
                            icon: const FaIcon(
                              FontAwesomeIcons.whatsapp,
                              color: Color(0xFF25D366),
                              size: 23,
                            ),
                          ),
                          if (_canDeleteTest(test))
                            IconButton(
                              tooltip: 'Delete Test',
                              onPressed: () {
                                _deleteTest(context, test);
                              },
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppTheme.danger,
                                size: 24,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
