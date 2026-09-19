import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/list_sorting.dart';

class AdminAttendanceTab extends StatefulWidget {
  const AdminAttendanceTab({super.key});

  @override
  State<AdminAttendanceTab> createState() => _AdminAttendanceTabState();
}

class _AdminAttendanceTabState extends State<AdminAttendanceTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> batches = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchBatches();
  }

  Future<void> fetchBatches() async {
    try {
      final response = await supabase.from('batches').select().order('name');
      setState(() {
        batches = sortBatches(response);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => isLoading = false);
    }
  }

  void _openAttendance(BuildContext context, String batchId, String batchName) {
    // Default initial date aaj ki set kardi
    final String today = DateTime.now().toIso8601String().split('T')[0];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditAttendanceScreen(
          batchId: batchId,
          batchName: batchName,
          initialDate: today,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (batches.isEmpty) return const Center(child: Text('No batches found.'));

    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('assets/images/school_bg.png'),
          fit: BoxFit.cover,
          opacity: 0.25,
        ),
      ),
      child: ListView.builder(
        itemCount: batches.length,
        itemBuilder: (context, index) {
          final batch = batches[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              leading: const Icon(Icons.fact_check, color: Colors.teal),
              title: Text(
                batch['name'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Tap to view and edit attendance'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _openAttendance(context, batch['id'], batch['name']),
            ),
          );
        },
      ),
    );
  }
}

// Sub-Screen: Attendance Viewer & Editor with Date Navigator
// Sub-Screen: Attendance Viewer & Editor with Date Navigator & Safe Save
class EditAttendanceScreen extends StatefulWidget {
  final String batchId;
  final String batchName;
  final String initialDate;

  const EditAttendanceScreen({
    super.key,
    required this.batchId,
    required this.batchName,
    required this.initialDate,
  });

  @override
  State<EditAttendanceScreen> createState() => _EditAttendanceScreenState();
}

class _EditAttendanceScreenState extends State<EditAttendanceScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> students = [];
  Map<String, String> attendanceData = {};
  Set<String> modifiedStudents =
      {}; // Track karega kis bache ka data change hua
  bool isLoading = true;
  late DateTime currentDate;

  @override
  void initState() {
    super.initState();
    currentDate = DateTime.parse(widget.initialDate);
    fetchStudentsAndAttendance();
  }

  Future<void> fetchStudentsAndAttendance() async {
    final String dateString = currentDate.toIso8601String().split('T')[0];

    try {
      final studentsRes = await supabase
          .from('students')
          .select()
          .eq('batch_id', widget.batchId)
          .order('name');
      final attendanceRes = await supabase
          .from('attendance')
          .select('student_id, status')
          .eq('batch_id', widget.batchId)
          .eq('date', dateString);

      attendanceData.clear();
      modifiedStudents.clear(); // Nayi date par reset kar do

      for (var record in attendanceRes) {
        attendanceData[record['student_id']] = record['status'];
      }

      setState(() {
        students = sortStudents(studentsRes);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => isLoading = false);
    }
  }

  void _updateLocalStatus(String studentId, String newStatus) {
    setState(() {
      attendanceData[studentId] = newStatus;
      modifiedStudents.add(studentId); // Mark as modified
    });
  }

  Future<void> _saveChangesToSupabase() async {
    if (modifiedStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Koi change nahi kiya gaya.')),
      );
      return;
    }

    setState(() => isLoading = true);
    final String dateString = currentDate.toIso8601String().split('T')[0];
    List<Map<String, dynamic>> updates = [];

    // Sirf unko update karo jin me change aya ha
    for (String sId in modifiedStudents) {
      updates.add({
        'student_id': sId,
        'batch_id': widget.batchId,
        'date': dateString,
        'status': attendanceData[sId],
      });
    }

    try {
      await supabase
          .from('attendance')
          .upsert(updates, onConflict: 'student_id, date');
      setState(() {
        modifiedStudents.clear(); // Save hone k baad clear kar do
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Attendance updated successfully! ✅',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Update failed: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Error saving attendance!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _changeDate(int days) {
    if (modifiedStudents.isNotEmpty) {
      // Agar unsaved changes hain to warn karo
      _showUnsavedWarningDialog(() {
        setState(() {
          currentDate = currentDate.add(Duration(days: days));
          isLoading = true;
        });
        fetchStudentsAndAttendance();
      });
      return;
    }

    setState(() {
      currentDate = currentDate.add(Duration(days: days));
      isLoading = true;
    });
    fetchStudentsAndAttendance();
  }

  void _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2026, 8, 1),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      if (modifiedStudents.isNotEmpty) {
        _showUnsavedWarningDialog(() {
          setState(() {
            currentDate = picked;
            isLoading = true;
          });
          fetchStudentsAndAttendance();
        });
        return;
      }

      setState(() {
        currentDate = picked;
        isLoading = true;
      });
      fetchStudentsAndAttendance();
    }
  }

  void _showUnsavedWarningDialog(VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
          'Tumne kuch attendance change ki ha par save nahi ki. Date change karne se changes zaya ho jayengi. Proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text('Discard & Proceed'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String dateString = currentDate.toIso8601String().split('T')[0];
    final bool canGoForward = currentDate.isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );

    return PopScope(
      canPop: modifiedStudents.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && modifiedStudents.isNotEmpty) {
          _showUnsavedWarningDialog(() => Navigator.pop(context));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.batchName),
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: _pickDate,
            ),
          ],
        ),
        body: Column(
          children: [
            // Date Navigator Bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.teal.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 30),
                    onPressed: () => _changeDate(-1),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    dateString,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 30),
                    onPressed: canGoForward ? () => _changeDate(1) : null,
                    color: canGoForward ? Colors.black : Colors.grey,
                  ),
                ],
              ),
            ),
            // Students List
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: students.length,
                      itemBuilder: (context, index) {
                        final student = students[index];
                        final sId = student['id'];
                        final status = attendanceData[sId] ?? 'unmarked';

                        return ListTile(
                          title: Text(student['name']),
                          trailing: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'present', label: Text('P')),
                              ButtonSegment(value: 'absent', label: Text('A')),
                            ],
                            selected: {
                              status == 'unmarked' ? 'absent' : status,
                            },
                            onSelectionChanged: (Set<String> newSelection) {
                              _updateLocalStatus(sId, newSelection.first);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        // Save Button (Sirf tab show hoga jab koi change aya ho)
        floatingActionButton: modifiedStudents.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _saveChangesToSupabase,
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
              )
            : null,
      ),
    );
  }
}
