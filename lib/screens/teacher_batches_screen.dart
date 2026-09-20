import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'student_screen.dart';
import '../app_theme.dart';
import '../utils/list_sorting.dart';

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

  @override
  void initState() {
    super.initState();
    fetchBatches();
    syncOfflineData();
  }

  Future<void> syncOfflineData() async {
    final offlineBox = Hive.box('offline_attendance');
    if (offlineBox.isEmpty) return;

    bool syncedSomething = false;

    for (var key in offlineBox.keys.toList()) {
      try {
        final data = offlineBox.get(key);
        final List<Map<String, dynamic>> syncData =
            List<Map<String, dynamic>>.from(
              (data as List).map((item) => Map<String, dynamic>.from(item)),
            );

        await supabase
            .from('attendance')
            .upsert(syncData, onConflict: 'student_id, date');
        await offlineBox.delete(key);
        syncedSomething = true;
      } catch (e) {
        debugPrint('Background sync failed for key $key: $e');
      }
    }

    if (syncedSomething && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline attendance synced to cloud! ☁️✅'),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> fetchBatches() async {
    try {
      final response = await supabase.from('batches').select().order('name');
      setState(() {
        batches = sortBatches(response);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching data: $e');
      setState(() => isLoading = false);
    }
  }

  void _openStudentsScreen(String batchId, String batchName) {
    final screen = StudentsScreen(batchId: batchId, batchName: batchName);

    if (widget.onNavigate != null) {
      widget.onNavigate!(screen);
      return;
    }

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
            : batches.isEmpty
            ? const Center(child: Text('No batches found. Check Supabase.'))
            : ListView.builder(
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
                      onTap: () => _openStudentsScreen(batch['id'], batchName),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
