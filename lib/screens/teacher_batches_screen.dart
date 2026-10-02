import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../utils/dashboard_section_header.dart';
import '../utils/error_state_view.dart';
import '../utils/list_sorting.dart';
import 'student_screen.dart';

class TeacherBatchesScreen extends StatefulWidget {
  final Function(Widget screen)? onNavigate;

  const TeacherBatchesScreen({super.key, this.onNavigate});

  @override
  State<TeacherBatchesScreen> createState() => _TeacherBatchesScreenState();
}

class _TeacherBatchesScreenState extends State<TeacherBatchesScreen> {
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
        supabase.from('batches').select('id, name, class_level'),
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
      debugPrint('Teacher batches error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;

        errorMessage =
            'Unable to load batches. Check your connection and try again.';
      });
    }
  }

  void _openBatch(Map<String, dynamic> batch) {
    final screen = StudentsScreen(
      batchId: batch['id'].toString(),
      batchName: batch['name']?.toString() ?? 'Batch',
    );

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((
      _,
    ) {
      if (mounted) {
        fetchBatches();
      }
    });
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
        final desktop = constraints.maxWidth >= 860;
        final header = DashboardSectionHeader(
          title: 'My Batches',
          subtitle: 'Select a class to record today’s attendance',
          trailing: IconButton(
            tooltip: 'Refresh',
            color: Colors.white,
            onPressed: fetchBatches,
            icon: const Icon(Icons.refresh_rounded),
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
                  child: Center(child: Text('No batches available.')),
                )
              else if (!desktop)
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final batch = Map<String, dynamic>.from(batches[index]);
                      return _TeacherBatchCard(
                        batch: batch,
                        onTap: () => _openBatch(batch),
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
                      return _TeacherBatchCard(
                        batch: batch,
                        onTap: () => _openBatch(batch),
                      );
                    }, childCount: batches.length),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 2.7,
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

class _TeacherBatchCard extends StatelessWidget {
  final Map<String, dynamic> batch;
  final VoidCallback onTap;

  const _TeacherBatchCard({required this.batch, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = (batch['student_count'] as num?)?.toInt() ?? 0;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      batch['name']?.toString() ?? 'Batch',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$count students',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Open today’s attendance',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
