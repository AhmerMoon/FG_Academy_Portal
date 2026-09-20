import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'student_screen.dart';
import '../utils/list_sorting.dart';

class TeacherBatchesScreen extends StatefulWidget {
  const TeacherBatchesScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('assets/images/school_bg.png'),
          fit: BoxFit.cover,
          opacity: 0.25,
        ),
      ),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : batches.isEmpty
          ? const Center(child: Text('No batches found. Check Supabase.'))
          : ListView.builder(
              itemCount: batches.length,
              itemBuilder: (context, index) {
                final batch = batches[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    title: Text(
                      batch['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StudentsScreen(
                            batchId: batch['id'],
                            batchName: batch['name'],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
