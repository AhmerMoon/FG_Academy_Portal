import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_theme.dart';
import '../../utils/dashboard_section_header.dart';
import '../../utils/error_state_view.dart';
import '../../utils/list_sorting.dart';

class BatchesTab extends StatefulWidget {
  const BatchesTab({super.key});

  @override
  State<BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends State<BatchesTab> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<dynamic> batches = [];

  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    fetchBatches();
  }

  Future<void> fetchBatches() async {
    try {
      final results = await Future.wait([
        supabase
            .from('batches')
            .select('id, name, class_level, whatsapp_group_id'),
        supabase.from('students').select('batch_id'),
      ]);

      final batchRows = results[0];
      final studentRows = results[1];

      final counts = <String, int>{};

      for (final student in studentRows) {
        final id = student['batch_id']?.toString();

        if (id != null) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }

      final mapped = batchRows.map((batch) {
        final copy = Map<String, dynamic>.from(batch);

        copy['student_count'] = counts[batch['id'].toString()] ?? 0;

        return copy;
      }).toList();

      if (!mounted) return;

      setState(() {
        batches = sortBatches(mapped);

        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Batch fetch error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;

        errorMessage =
            'Unable to load batches. Check your connection and try again.';
      });
    }
  }

  Future<void> _openBatchForm({Map<String, dynamic>? batch}) async {
    final draft = await _showBatchFormDialog(batch: batch);

    if (draft == null) return;

    await _saveBatch(draft: draft, existingBatch: batch);
  }

  Future<_BatchDraft?> _showBatchFormDialog({
    Map<String, dynamic>? batch,
  }) async {
    final editing = batch != null;

    final nameController = TextEditingController(
      text: batch?['name']?.toString() ?? '',
    );

    final whatsappController = TextEditingController(
      text: batch?['whatsapp_group_id']?.toString() ?? '',
    );

    int selectedLevel = (batch?['class_level'] as num?)?.toInt() ?? 9;

    final result = await showDialog<_BatchDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(editing ? 'Edit Batch' : 'Add Batch'),
              content: SizedBox(
                width: 430,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Batch Name',
                          prefixIcon: Icon(Icons.class_outlined),
                        ),
                      ),

                      const SizedBox(height: 14),

                      DropdownButtonFormField<int>(
                        key: ValueKey(selectedLevel),
                        initialValue: selectedLevel,
                        decoration: const InputDecoration(
                          labelText: 'Class Level',
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 9, child: Text('9th')),
                          DropdownMenuItem(value: 10, child: Text('10th')),
                          DropdownMenuItem(value: 11, child: Text('11th')),
                          DropdownMenuItem(value: 12, child: Text('12th')),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            selectedLevel = value;
                          });
                        },
                      ),

                      const SizedBox(height: 14),

                      TextField(
                        controller: whatsappController,
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp Group ID',
                          hintText: 'Optional',
                          prefixIcon: Icon(Icons.forum_outlined),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.fgNavyBlue.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Text(
                          'Class level is used by attendance, fee reporting and financial grouping. Keep it aligned with the batch name.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final name = nameController.text.trim();

                    if (name.isEmpty) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _BatchDraft(
                        name: name,
                        classLevel: selectedLevel,
                        whatsappGroupId: whatsappController.text.trim().isEmpty
                            ? null
                            : whatsappController.text.trim(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    whatsappController.dispose();

    return result;
  }

  Future<void> _saveBatch({
    required _BatchDraft draft,
    Map<String, dynamic>? existingBatch,
  }) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = <String, dynamic>{
        'name': draft.name,
        'class_level': draft.classLevel,
        'whatsapp_group_id': draft.whatsappGroupId,
      };

      if (existingBatch != null) {
        await supabase
            .from('batches')
            .update(data)
            .eq('id', existingBatch['id']);
      } else {
        await supabase.from('batches').insert(data);
      }

      await fetchBatches();

      if (!mounted) return;

      _showMessage(
        existingBatch == null
            ? 'Batch created successfully.'
            : 'Batch updated successfully.',
      );
    } catch (e) {
      debugPrint('Batch save error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      _showMessage('Could not save batch. Please try again.', error: true);
    }
  }

  void _showMessage(String value, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return ErrorStateView(message: errorMessage!, onRetry: fetchBatches);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        final header = DashboardSectionHeader(
          title: 'Batches',
          subtitle: 'Class groups and communication settings',
          trailing: ElevatedButton.icon(
            onPressed: () => _openBatchForm(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.fgGold,
              foregroundColor: AppTheme.fgNavyBlue,
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Batch'),
          ),
        );

        return RefreshIndicator(
          onRefresh: fetchBatches,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: header),
              if (batches.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('No batches found.')),
                )
              else if (columns == 1)
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final batch = Map<String, dynamic>.from(batches[index]);
                      return _BatchCard(
                        batch: batch,
                        onEdit: () => _openBatchForm(batch: batch),
                      );
                    }, childCount: batches.length),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final batch = Map<String, dynamic>.from(batches[index]);
                      return _BatchCard(
                        batch: batch,
                        onEdit: () => _openBatchForm(batch: batch),
                      );
                    }, childCount: batches.length),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 2.55,
                        ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BatchDraft {
  final String name;
  final int classLevel;
  final String? whatsappGroupId;

  const _BatchDraft({
    required this.name,
    required this.classLevel,
    required this.whatsappGroupId,
  });
}

class _BatchCard extends StatelessWidget {
  final Map<String, dynamic> batch;
  final VoidCallback onEdit;

  const _BatchCard({required this.batch, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final name = batch['name']?.toString() ?? 'Batch';

    final classLevel = (batch['class_level'] as num?)?.toInt() ?? 0;

    final whatsapp = batch['whatsapp_group_id']?.toString();

    final count = (batch['student_count'] as num?)?.toInt() ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.fgNavyBlue.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.groups_2_outlined,
                color: AppTheme.fgNavyBlue,
                size: 27,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (classLevel > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.fgGold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Class $classLevel',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.fgNavyBlue,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 5),

                  Text(
                    '$count students',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    whatsapp == null || whatsapp.isEmpty
                        ? 'WhatsApp group not configured'
                        : 'WhatsApp: $whatsapp',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            IconButton(
              tooltip: 'Edit Batch',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              color: AppTheme.fgNavyBlue,
            ),
          ],
        ),
      ),
    );
  }
}
