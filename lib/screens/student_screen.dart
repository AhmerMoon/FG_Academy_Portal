import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/list_sorting.dart';

class StudentsScreen extends StatefulWidget {
  final String batchId;
  final String batchName;

  const StudentsScreen({
    super.key,
    required this.batchId,
    required this.batchName,
  });

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> students = [];
  bool isLoading = true;

  Map<String, String?> attendanceStatus =
      {}; // student_id -> 'present' / 'absent' / null

  final String todayDate = DateTime.now().toIso8601String().split('T')[0];

  @override
  void initState() {
    super.initState();
    fetchStudentsAndAttendance();
  }

  Future<void> fetchStudentsAndAttendance() async {
    try {
      // 1. Fetch Students
      final studentsResponse = await supabase
          .from('students')
          .select()
          .eq('batch_id', widget.batchId)
          .order('name', ascending: true);

      // 2. Fetch Today's Attendance for this Batch (Agar kisi aur teacher ne lagai ho)
      final attendanceResponse = await supabase
          .from('attendance')
          .select('student_id, status')
          .eq('batch_id', widget.batchId)
          .eq('date', todayDate);

      setState(() {
        students = sortStudents(studentsResponse);

        // Sab ko pehle unmarked (null) set karo
        for (var student in students) {
          attendanceStatus[student['id']] = null;
        }

        // Existing attendance is loaded so it can be edited and resubmitted.
        for (var record in attendanceResponse) {
          final sId = record['student_id'];
          attendanceStatus[sId] = record['status'];
        }

        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching data: $e');
      setState(() => isLoading = false);
    }
  }

  void markAll(String status) {
    setState(() {
      for (var student in students) {
        attendanceStatus[student['id']] = status;
      }
    });
  }

  void _showAddStudentDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add New Student'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Student Name'),
            textCapitalization: TextCapitalization.words,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(dialogContext);
                setState(() => isLoading = true);

                try {
                  final newStudent = await supabase
                      .from('students')
                      .insert({'name': name, 'batch_id': widget.batchId})
                      .select()
                      .single();

                  await supabase.from('attendance').insert({
                    'student_id': newStudent['id'],
                    'batch_id': widget.batchId,
                    'date': todayDate,
                    'status': 'present',
                  });

                  if (!mounted) return;

                  setState(() {
                    students.add(newStudent);
                    students = sortStudents(students);
                    attendanceStatus[newStudent['id']] = 'present';
                    isLoading = false;
                  });

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Student added and marked Present for today! ✅',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('Error adding student: $e');
                  if (mounted) {
                    setState(() => isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to add student.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Save & Mark P'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmSubmitAttendance() async {
    final presentCount = attendanceStatus.values
        .where((status) => status == 'present')
        .length;

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirm Attendance'),
            content: Text(
              'Total Present Students: $presentCount\n\n'
              'Aik baar count karlo ke bachay poore hain kya? '
              'Kya attendance submit karni hai?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Submit'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 800;
    final buttonTextSize = isDesktop ? 16.0 : 14.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          '${widget.batchName} Attendance',
          style: TextStyle(fontSize: isDesktop ? 22 : 18),
        ),
        actions: [
          IconButton(
            onPressed: _showAddStudentDialog,
            tooltip: 'Add student',
            icon: const Icon(Icons.person_add),
          ),
        ],
      ),
      body: Container(
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
              : students.isEmpty
              ? const Center(child: Text('No students found for this batch.'))
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => markAll('present'),
                            icon: const Icon(Icons.check, size: 18),
                            label: Text(
                              'All P',
                              style: TextStyle(fontSize: buttonTextSize),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(110, 42),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => markAll('absent'),
                            icon: const Icon(Icons.close, size: 18),
                            label: Text(
                              'All A',
                              style: TextStyle(fontSize: buttonTextSize),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(110, 42),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final studentId = student['id'];
                          final currentStatus = attendanceStatus[studentId];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 3,
                            color: Colors.white.withOpacity(0.96),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Icon(
                                Icons.person,
                                color: const Color(0xFF0B2B5E),
                              ),
                              title: Text(
                                student['name'],
                                style: TextStyle(
                                  fontSize: isDesktop ? 18 : 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              trailing: SizedBox(
                                width: 150,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () {
                                          setState(() {
                                            attendanceStatus[studentId] =
                                                'present';
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: currentStatus == 'present'
                                                ? Colors.green
                                                : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'P',
                                            style: TextStyle(
                                              color: currentStatus == 'present'
                                                  ? Colors.white
                                                  : Colors.black54,
                                              fontWeight: FontWeight.bold,
                                              fontSize: isDesktop ? 18 : 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () {
                                          setState(() {
                                            attendanceStatus[studentId] =
                                                'absent';
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: currentStatus == 'absent'
                                                ? Colors.red
                                                : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'A',
                                            style: TextStyle(
                                              color: currentStatus == 'absent'
                                                  ? Colors.white
                                                  : Colors.black54,
                                              fontWeight: FontWeight.bold,
                                              fontSize: isDesktop ? 18 : 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: () async {
                          final shouldSubmit = await _confirmSubmitAttendance();
                          if (!shouldSubmit || !mounted) return;

                          final List<Map<String, dynamic>> newAttendanceData =
                              [];

                          attendanceStatus.forEach((studentId, status) {
                            if (status != null) {
                              newAttendanceData.add({
                                'student_id': studentId,
                                'batch_id': widget.batchId,
                                'date': todayDate,
                                'status': status,
                              });
                            }
                          });

                          if (newAttendanceData.isEmpty) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Koi nayi attendance mark nahi ki gayi.',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Saving attendance...'),
                            ),
                          );

                          final offlineBox = Hive.box('offline_attendance');
                          final String localKey =
                              '${widget.batchId}_$todayDate';

                          await offlineBox.put(localKey, newAttendanceData);

                          try {
                            await supabase
                                .from('attendance')
                                .upsert(
                                  newAttendanceData,
                                  onConflict: 'student_id, date',
                                );
                            await offlineBox.delete(localKey);

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Attendance synced! ✅'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(context);
                          } catch (e) {
                            debugPrint('Supabase push failed: $e');
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Saved offline. 💾'),
                                backgroundColor: Colors.blueGrey,
                              ),
                            );
                            Navigator.pop(context);
                          }
                        },
                        child: const Text(
                          'Submit Attendance',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
