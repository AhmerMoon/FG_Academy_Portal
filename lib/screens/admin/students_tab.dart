import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/list_sorting.dart';

// 1. Main Tab: Shows list of Batches
class StudentsTab extends StatefulWidget {
  const StudentsTab({super.key});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
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
      debugPrint('Error fetching batches: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (batches.isEmpty)
      return const Center(child: Text('No batches found in Supabase.'));

    return ListView.builder(
      itemCount: batches.length,
      itemBuilder: (context, index) {
        final batch = batches[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                  builder: (context) => BatchStudentsScreen(
                    batchId: batch['id'],
                    batchName: batch['name'],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// 2. Sub-Screen: Shows students of the selected Batch with full CRUD
class BatchStudentsScreen extends StatefulWidget {
  final String batchId;
  final String batchName;

  const BatchStudentsScreen({
    super.key,
    required this.batchId,
    required this.batchName,
  });

  @override
  State<BatchStudentsScreen> createState() => _BatchStudentsScreenState();
}

class _BatchStudentsScreenState extends State<BatchStudentsScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> students = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchStudents();
  }

  Future<void> fetchStudents() async {
    try {
      final response = await supabase
          .from('students')
          .select()
          .eq('batch_id', widget.batchId)
          .order('name');
      setState(() {
        students = sortStudents(response);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching students: $e');
      setState(() => isLoading = false);
    }
  }

  void _showStudentFormDialog({Map<String, dynamic>? student}) {
    final isEditing = student != null;
    final nameController = TextEditingController(
      text: isEditing ? student['name'] : '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Student Name' : 'Add New Student'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Student Name'),
              ),
              // Note: Subject Stream ka dropdown baad me yahan add hoga
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(context); // Dialog band karo
                setState(() => isLoading = true); // Spinner chalao

                try {
                  if (isEditing) {
                    // Update Query
                    await supabase
                        .from('students')
                        .update({'name': name})
                        .eq('id', student['id']);
                  } else {
                    // Insert Query
                    await supabase.from('students').insert({
                      'name': name,
                      'batch_id': widget.batchId,
                    });
                  }
                  fetchStudents(); // Naya data load karo
                } catch (e) {
                  debugPrint('Error saving student: $e');
                  setState(() => isLoading = false);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _deleteStudent(String id, String name) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Student?'),
          content: Text(
            'Kiya tum waqai "$name" ko delete karna chahte ho? Iski saari attendance history bhi hamesha ke liye delete ho jayegi.',
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
              onPressed: () async {
                Navigator.pop(context);
                setState(() => isLoading = true);

                try {
                  // Foreign key constraint avoid karne ke liye pehle uski attendance delete karni paregi
                  await supabase
                      .from('attendance')
                      .delete()
                      .eq('student_id', id);
                  // Phir student delete hoga
                  await supabase.from('students').delete().eq('id', id);
                  fetchStudents();
                } catch (e) {
                  debugPrint('Error deleting student: $e');
                  setState(() => isLoading = false);
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text('${widget.batchName} - Students')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showStudentFormDialog(),
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/school_bg.png'),
            fit: BoxFit.cover,
            opacity: 0.25,
          ),
        ),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : students.isEmpty
            ? const Center(child: Text('Is batch mein koi student nahi hai.'))
            : LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          columnSpacing: 24,
                          columns: const [
                            DataColumn(label: Text('Name')),
                            DataColumn(numeric: true, label: Text('Actions')),
                          ],
                          rows: students.map((s) {
                            return DataRow(
                              cells: [
                                DataCell(Text(s['name'])),
                                DataCell(
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () =>
                                              _showStudentFormDialog(
                                                student: s,
                                              ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => _deleteStudent(
                                            s['id'],
                                            s['name'],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
