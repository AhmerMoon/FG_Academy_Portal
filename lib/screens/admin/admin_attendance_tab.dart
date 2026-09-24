import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/list_sorting.dart';
import '../../utils/automation_launcher.dart';
import '../../utils/error_state_view.dart';
import '../../utils/dashboard_section_header.dart';

class AdminAttendanceTab extends StatefulWidget {
  final Function(Widget screen)? onNavigate;
  final VoidCallback? onBack;

  const AdminAttendanceTab({super.key, this.onNavigate, this.onBack});

  @override
  State<AdminAttendanceTab> createState() => _AdminAttendanceTabState();
}

class _AdminAttendanceTabState extends State<AdminAttendanceTab> {
  final supabase = Supabase.instance.client;
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
      final response = await supabase.from('batches').select().order('name');
      final studentsResponse = await supabase
          .from('students')
          .select('batch_id');
      final today = DateTime.now().toIso8601String().split('T')[0];
      final attendanceResponse = await supabase
          .from('attendance')
          .select('batch_id, status')
          .eq('date', today);
      final strengthByBatch = <String, int>{};
      for (final student in studentsResponse) {
        final batchId = student['batch_id']?.toString();
        if (batchId != null) {
          strengthByBatch[batchId] = (strengthByBatch[batchId] ?? 0) + 1;
        }
      }
      final presentByBatch = <String, int>{};
      final absentByBatch = <String, int>{};
      for (final record in attendanceResponse) {
        final batchId = record['batch_id']?.toString();
        if (batchId == null) continue;
        if (record['status'] == 'present') {
          presentByBatch[batchId] = (presentByBatch[batchId] ?? 0) + 1;
        } else if (record['status'] == 'absent') {
          absentByBatch[batchId] = (absentByBatch[batchId] ?? 0) + 1;
        }
      }
      final batchesWithStats = response.map((batch) {
        final batchId = batch['id'].toString();
        final batchCopy = Map<String, dynamic>.from(batch);
        batchCopy['student_count'] = strengthByBatch[batchId] ?? 0;
        batchCopy['present_count'] = presentByBatch[batchId] ?? 0;
        batchCopy['absent_count'] = absentByBatch[batchId] ?? 0;
        return batchCopy;
      }).toList();
      if (!mounted) return;
      setState(() {
        batches = sortBatches(batchesWithStats);
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Error: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage =
            'Unable to load attendance batches. Check your connection and try again.';
      });
    }
  }

  void _openAttendance(BuildContext context, String batchId, String batchName) {
    final String today = DateTime.now().toIso8601String().split('T')[0];
    final screen = EditAttendanceScreen(
      batchId: batchId,
      batchName: batchName,
      initialDate: today,
    );

    if (widget.onNavigate != null && widget.onBack != null) {
      widget.onNavigate!(
        EditAttendanceScreen(
          batchId: batchId,
          batchName: batchName,
          initialDate: today,
          onBack: widget.onBack,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    ).then((_) {
      if (mounted) fetchBatches();
    });
  }

  Future<void> _startAutomation() async {
    final started = await launchAutomation();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          started
              ? 'Automation Started'
              : 'Automation could not start. Check the backend file and Windows setup.',
        ),
        backgroundColor: started ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) {
      return ErrorStateView(message: errorMessage!, onRetry: fetchBatches);
    }
    final isExpanded = MediaQuery.sizeOf(context).width >= 800;

    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('assets/images/school_bg.png'),
          fit: BoxFit.cover,
          opacity: 0.2,
        ),
      ),
      child: Column(
        children: [
          DashboardSectionHeader(
            title: 'Attendance',
            subtitle: 'Today\'s strength and attendance by batch',
            trailing: isExpanded
                ? Tooltip(
                    message: 'Send WhatsApp Reports',
                    child: Material(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _startAutomation,
                        borderRadius: BorderRadius.circular(10),
                        child: const SizedBox(
                          width: 56,
                          height: 56,
                          child: Center(
                            child: FaIcon(
                              FontAwesomeIcons.whatsapp,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: batches.isEmpty
                ? const Center(child: Text('No batches found.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: batches.length,
                    itemBuilder: (context, index) {
                      final batch = batches[index];
                      final batchName = batch['name']?.toString() ?? 'Batch';

                      return Card(
                        elevation: 3,
                        color: Colors.white.withValues(alpha: 0.96),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          leading: const Icon(
                            Icons.fact_check,
                            color: Color(0xFF0B2B5E),
                            size: 26,
                          ),
                          title: Text(
                            batchName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          subtitle: isExpanded
                              ? const Text('Tap to view and edit attendance')
                              : Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      _AttendanceCount(
                                        label: 'Total',
                                        value: batch['student_count'] ?? 0,
                                        color: Colors.blueGrey,
                                      ),
                                      _AttendanceCount(
                                        label: 'Present',
                                        value: batch['present_count'] ?? 0,
                                        color: Colors.green,
                                      ),
                                      _AttendanceCount(
                                        label: 'Absent',
                                        value: batch['absent_count'] ?? 0,
                                        color: Colors.red,
                                      ),
                                    ],
                                  ),
                                ),
                          trailing: isExpanded
                              ? SizedBox(
                                  width: 210,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      _AttendanceCount(
                                        label: 'Total',
                                        value: batch['student_count'] ?? 0,
                                        color: Colors.blueGrey,
                                      ),
                                      _AttendanceCount(
                                        label: 'Present',
                                        value: batch['present_count'] ?? 0,
                                        color: Colors.green,
                                      ),
                                      _AttendanceCount(
                                        label: 'Absent',
                                        value: batch['absent_count'] ?? 0,
                                        color: Colors.red,
                                      ),
                                    ],
                                  ),
                                )
                              : null,
                          onTap: () =>
                              _openAttendance(context, batch['id'], batchName),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCount extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;

  const _AttendanceCount({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
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
  final VoidCallback? onBack;

  const EditAttendanceScreen({
    super.key,
    required this.batchId,
    required this.batchName,
    required this.initialDate,
    this.onBack,
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
  String? errorMessage;
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

      if (!mounted) return;
      setState(() {
        students = sortStudents(studentsRes);
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Error: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage =
            'Unable to load attendance. Check your connection and try again.';
      });
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
          automaticallyImplyLeading: widget.onBack == null,
          leading: widget.onBack == null
              ? null
              : IconButton(
                  tooltip: 'Back to Attendance',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: modifiedStudents.isEmpty
                      ? widget.onBack
                      : () => _showUnsavedWarningDialog(widget.onBack!),
                ),
          title: Text(widget.batchName),
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: isLoading ? null : _pickDate,
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
          child: Column(
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
                      onPressed: isLoading ? null : () => _changeDate(-1),
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
                      onPressed: isLoading || !canGoForward
                          ? null
                          : () => _changeDate(1),
                      color: canGoForward && !isLoading
                          ? Colors.black
                          : Colors.grey,
                    ),
                  ],
                ),
              ),
              // Students List
              Expanded(
                child: errorMessage != null
                    ? ErrorStateView(
                        message: errorMessage!,
                        onRetry: fetchStudentsAndAttendance,
                      )
                    : isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final sId = student['id'];
                          final status = attendanceData[sId] ?? 'unmarked';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            color: Colors.white.withValues(alpha: 0.96),
                            elevation: 2,
                            child: ListTile(
                              title: Text(student['name']),
                              trailing: SizedBox(
                                width: 150,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () =>
                                            _updateLocalStatus(sId, 'present'),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: status == 'present'
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
                                              color: status == 'present'
                                                  ? Colors.white
                                                  : Colors.black54,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () =>
                                            _updateLocalStatus(sId, 'absent'),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: status == 'absent'
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
                                              color: status == 'absent'
                                                  ? Colors.white
                                                  : Colors.black54,
                                              fontWeight: FontWeight.bold,
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
              if (modifiedStudents.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ElevatedButton.icon(
                    onPressed: isLoading ? null : _saveChangesToSupabase,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
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
