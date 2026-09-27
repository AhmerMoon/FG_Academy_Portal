import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'student_screen.dart';
import '../app_theme.dart';
import '../utils/list_sorting.dart';
import '../utils/error_state_view.dart';
import '../utils/dashboard_section_header.dart';

class TeacherBatchesScreen extends StatefulWidget {
  final Function(Widget screen)? onNavigate;

  const TeacherBatchesScreen({super.key, this.onNavigate});

  @override
  State<TeacherBatchesScreen> createState() => _TeacherBatchesScreenState();
}

class _TeacherBatchesScreenState extends State<TeacherBatchesScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> batches = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchBatches();
  }

  Widget _buildBatchesHeader() {
    return const DashboardSectionHeader(
      title: 'My Batches',
      subtitle: 'Choose a batch to take today\'s attendance',
    );
  }

  Future<void> fetchBatches() async {
    try {
      final response = await supabase.from('batches').select().order('name');
      if (!mounted) return;
      setState(() {
        batches = sortBatches(response);
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage =
            'Unable to load batches. Check your connection and try again.';
      });
    }
  }

  void _openStudentsScreen(String batchId, String batchName) {
    final screen = StudentsScreen(batchId: batchId, batchName: batchName);
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('assets/images/school_bg.png'),
          fit: BoxFit.cover,
          opacity: 0.18,
        ),
      ),
      child: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
            ? ErrorStateView(message: errorMessage!, onRetry: fetchBatches)
            : batches.isEmpty
            ? Column(
                children: [
                  _buildBatchesHeader(),
                  const Expanded(
                    child: Center(
                      child: Text('No batches found. Check Supabase.'),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _buildBatchesHeader(),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: batches.length,
                      itemBuilder: (context, index) {
                        final batch = batches[index];
                        final batchName = batch['name']?.toString() ?? 'Batch';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 3,
                          color: Colors.white.withValues(alpha: 0.96),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            leading: Icon(
                              Icons.folder_open,
                              color: AppTheme.fgNavyBlue,
                              size: 28,
                            ),
                            title: Text(
                              batchName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            subtitle: const Text('Open batch details'),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: Colors.black54,
                            ),
                            onTap: () =>
                                _openStudentsScreen(batch['id'], batchName),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
