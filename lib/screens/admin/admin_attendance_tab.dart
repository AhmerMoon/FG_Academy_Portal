import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_theme.dart';
import '../../utils/automation_launcher.dart';
import '../../utils/dashboard_section_header.dart';
import '../../utils/error_state_view.dart';
import '../../widgets/academy_background.dart';
import '../../utils/list_sorting.dart';

class AdminAttendanceTab extends StatefulWidget {
  final Function(Widget screen)? onNavigate;
  final VoidCallback? onBack;

  const AdminAttendanceTab({super.key, this.onNavigate, this.onBack});

  @override
  State<AdminAttendanceTab> createState() => _AdminAttendanceTabState();
}

class _AdminAttendanceTabState extends State<AdminAttendanceTab> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<dynamic> batches = [];

  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    fetchBatches();
  }

  String get _today => DateTime.now().toIso8601String().split('T').first;

  Future<void> fetchBatches() async {
    try {
      final results = await Future.wait([
        supabase.from('batches').select('id, name, class_level'),
        supabase.from('students').select('batch_id'),
        supabase
            .from('attendance')
            .select('batch_id, status')
            .eq('date', _today),
      ]);

      final batchRows = results[0];
      final studentRows = results[1];
      final attendanceRows = results[2];

      final total = <String, int>{};
      final present = <String, int>{};
      final absent = <String, int>{};

      for (final student in studentRows) {
        final id = student['batch_id']?.toString();

        if (id != null) {
          total[id] = (total[id] ?? 0) + 1;
        }
      }

      for (final row in attendanceRows) {
        final id = row['batch_id']?.toString();

        if (id == null) continue;

        if (row['status'] == 'present') {
          present[id] = (present[id] ?? 0) + 1;
        }

        if (row['status'] == 'absent') {
          absent[id] = (absent[id] ?? 0) + 1;
        }
      }

      final mapped = batchRows.map((batch) {
        final id = batch['id'].toString();

        final copy = Map<String, dynamic>.from(batch);

        copy['student_count'] = total[id] ?? 0;
        copy['present_count'] = present[id] ?? 0;
        copy['absent_count'] = absent[id] ?? 0;

        return copy;
      }).toList();

      if (!mounted) return;

      setState(() {
        batches = sortBatches(mapped);

        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Attendance dashboard error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;

        errorMessage =
            'Unable to load attendance batches. Check your connection and try again.';
      });
    }
  }

  void _openAttendance(Map<String, dynamic> batch) {
    final id = batch['id'].toString();

    final name = batch['name']?.toString() ?? 'Batch';

    final screen = EditAttendanceScreen(
      batchId: id,
      batchName: name,
      initialDate: _today,
    );

    if (widget.onNavigate != null && widget.onBack != null) {
      widget.onNavigate!(
        EditAttendanceScreen(
          batchId: id,
          batchName: name,
          initialDate: _today,
          onBack: widget.onBack,
        ),
      );

      return;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((
      _,
    ) {
      if (mounted) {
        fetchBatches();
      }
    });
  }

  Future<void> _startAutomation() async {
    final started = await launchAutomation();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          started
              ? 'WhatsApp report automation started.'
              : 'Automation could not start.',
        ),
        backgroundColor: started ? AppTheme.success : AppTheme.danger,
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

    return RefreshIndicator(
      onRefresh: fetchBatches,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: DashboardSectionHeader(
              title: 'Attendance',
              subtitle: 'Today’s batch strength and attendance overview',
              trailing: isWindowsPlatform
                  ? ElevatedButton.icon(
                      onPressed: _startAutomation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                      ),
                      icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 17),
                      label: const Text('Send Reports'),
                    )
                  : null,
            ),
          ),
          if (batches.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('No batches found.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildAttendanceBatchCard(
                    Map<String, dynamic>.from(batches[index]),
                  ),
                  childCount: batches.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceBatchCard(Map<String, dynamic> batch) {
    final total = (batch['student_count'] as num?)?.toInt() ?? 0;
    final present = (batch['present_count'] as num?)?.toInt() ?? 0;
    final absent = (batch['absent_count'] as num?)?.toInt() ?? 0;
    final unmarked = total - present - absent;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openAttendance(batch),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final title = Row(
                children: [
                  Container(
                    width: 47,
                    height: 47,
                    decoration: BoxDecoration(
                      color: AppTheme.fgNavyBlue.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: AppTheme.fgNavyBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch['name']?.toString() ?? 'Batch',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Open attendance register',
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
              );

              final stats = Wrap(
                spacing: 8,
                runSpacing: 7,
                children: [
                  _AttendanceBadge(
                    label: 'Total',
                    value: total,
                    color: AppTheme.info,
                  ),
                  _AttendanceBadge(
                    label: 'Present',
                    value: present,
                    color: AppTheme.success,
                  ),
                  _AttendanceBadge(
                    label: 'Absent',
                    value: absent,
                    color: AppTheme.danger,
                  ),
                  _AttendanceBadge(
                    label: 'Unmarked',
                    value: unmarked < 0 ? 0 : unmarked,
                    color: AppTheme.warning,
                  ),
                ],
              );

              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 12), stats],
                    )
                  : Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 14),
                        stats,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _AttendanceBadge extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _AttendanceBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 66),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EDIT ATTENDANCE
// ============================================================================

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
  final SupabaseClient supabase = Supabase.instance.client;

  List<dynamic> students = [];

  final Map<String, String> attendanceData = {};
  final Map<String, int> _priorAbsenceStreak = {};

  final Set<String> modifiedStudents = {};

  bool isLoading = true;
  bool isSaving = false;

  String? errorMessage;

  late DateTime currentDate;

  @override
  void initState() {
    super.initState();

    currentDate = DateTime.parse(widget.initialDate);

    fetchStudentsAndAttendance();
  }

  String get dateString => currentDate.toIso8601String().split('T').first;

  bool get canGoForward {
    final today = DateTime.now();

    final cleanToday = DateTime(today.year, today.month, today.day);

    return currentDate.isBefore(cleanToday);
  }

  int get presentCount =>
      attendanceData.values.where((status) => status == 'present').length;

  int get absentCount =>
      attendanceData.values.where((status) => status == 'absent').length;

  int get unmarkedCount => students.length - presentCount - absentCount;

  String _dateOnly(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
    ).toIso8601String().split('T').first;
  }

  int _absenceStreakFor(String studentId) {
    final previous = _priorAbsenceStreak[studentId] ?? 0;
    final selectedStatus = attendanceData[studentId];

    if (selectedStatus == 'present') {
      return 0;
    }

    if (selectedStatus == 'absent') {
      return previous + 1;
    }

    return previous;
  }

  bool _needsParentFollowUp(String studentId) {
    return _absenceStreakFor(studentId) >= 4;
  }

  Future<void> fetchStudentsAndAttendance() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final historyStart = _dateOnly(
        currentDate.subtract(const Duration(days: 60)),
      );

      final results = await Future.wait([
        supabase
            .from('students')
            .select('id, name')
            .eq('batch_id', widget.batchId)
            .order('name', ascending: true),
        supabase
            .from('attendance')
            .select('student_id, status')
            .eq('batch_id', widget.batchId)
            .eq('date', dateString),
        supabase
            .from('attendance')
            .select('student_id, date, status')
            .eq('batch_id', widget.batchId)
            .gte('date', historyStart)
            .lt('date', dateString)
            .order('date', ascending: false),
      ]);

      final studentRows = sortStudents(results[0]);
      final attendanceRows = results[1];
      final historyRows = results[2];

      attendanceData.clear();
      _priorAbsenceStreak.clear();
      modifiedStudents.clear();

      for (final student in studentRows) {
        _priorAbsenceStreak[student['id'].toString()] = 0;
      }

      for (final row in attendanceRows) {
        attendanceData[row['student_id'].toString()] = row['status'].toString();
      }

      final historyByStudent = <String, List<Map<String, dynamic>>>{};

      for (final rawRow in historyRows) {
        final row = Map<String, dynamic>.from(rawRow);
        final studentId = row['student_id']?.toString();

        if (studentId == null) continue;

        historyByStudent.putIfAbsent(studentId, () => []).add(row);
      }

      for (final entry in historyByStudent.entries) {
        entry.value.sort(
          (a, b) => b['date'].toString().compareTo(a['date'].toString()),
        );

        var streak = 0;

        for (final row in entry.value) {
          final status = row['status']?.toString();

          if (status == 'absent') {
            streak++;
            continue;
          }

          if (status == 'present') {
            break;
          }
        }

        _priorAbsenceStreak[entry.key] = streak;
      }

      if (!mounted) return;

      setState(() {
        students = studentRows;

        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Attendance load error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;

        errorMessage =
            'Unable to load attendance. Check your connection and try again.';
      });
    }
  }

  void _setStatus(String studentId, String status) {
    setState(() {
      attendanceData[studentId] = status;

      modifiedStudents.add(studentId);
    });
  }

  void _markAll(String status) {
    setState(() {
      for (final student in students) {
        final id = student['id'].toString();

        attendanceData[id] = status;

        modifiedStudents.add(id);
      }
    });
  }

  Future<void> _saveChanges() async {
    if (modifiedStudents.isEmpty) {
      _showMessage('No attendance changes to save.');

      return;
    }

    final updates = <Map<String, dynamic>>[];

    for (final studentId in modifiedStudents) {
      final status = attendanceData[studentId];

      if (status == null) {
        continue;
      }

      updates.add({
        'student_id': studentId,
        'batch_id': widget.batchId,
        'date': dateString,
        'status': status,
      });
    }

    if (updates.isEmpty) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await supabase
          .from('attendance')
          .upsert(updates, onConflict: 'student_id, date');

      if (!mounted) return;

      setState(() {
        modifiedStudents.clear();

        isSaving = false;
      });

      _showMessage('Attendance saved successfully.');
    } catch (e) {
      debugPrint('Attendance save error: $e');

      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      _showMessage('Unable to save attendance.', error: true);
    }
  }

  Future<bool> _confirmDiscard() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Unsaved Changes'),
              content: Text(
                '${modifiedStudents.length} attendance change(s) have not been saved. Discard them?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Keep Editing'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Discard'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _changeToDate(DateTime date) async {
    if (modifiedStudents.isNotEmpty) {
      final discard = await _confirmDiscard();

      if (!discard || !mounted) {
        return;
      }
    }

    setState(() {
      currentDate = date;
    });

    await fetchStudentsAndAttendance();
  }

  Future<void> _changeDate(int days) async {
    await _changeToDate(currentDate.add(Duration(days: days)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2026, 8, 1),
      lastDate: DateTime.now(),
    );

    if (picked == null || !mounted) {
      return;
    }

    await _changeToDate(picked);
  }

  Future<void> _attemptBack() async {
    if (modifiedStudents.isNotEmpty) {
      final discard = await _confirmDiscard();

      if (!discard || !mounted) {
        return;
      }
    }

    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: modifiedStudents.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _attemptBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _attemptBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(widget.batchName),
          actions: [
            IconButton(
              tooltip: 'Choose Date',
              onPressed: isLoading ? null : _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
            ),
            const SizedBox(width: 5),
          ],
        ),
        body: AcademyBackground(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Previous Day',
                              onPressed: isLoading
                                  ? null
                                  : () => _changeDate(-1),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: isLoading ? null : _pickDate,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 9,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        DateFormat('EEEE').format(currentDate),
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                      Text(
                                        DateFormat(
                                          'dd MMM yyyy',
                                        ).format(currentDate),
                                        style: const TextStyle(
                                          color: AppTheme.fgNavyBlue,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next Day',
                              onPressed: isLoading || !canGoForward
                                  ? null
                                  : () => _changeDate(1),
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                        const Divider(height: 22),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _AttendanceBadge(
                              label: 'Total',
                              value: students.length,
                              color: AppTheme.info,
                            ),
                            _AttendanceBadge(
                              label: 'Present',
                              value: presentCount,
                              color: AppTheme.success,
                            ),
                            _AttendanceBadge(
                              label: 'Absent',
                              value: absentCount,
                              color: AppTheme.danger,
                            ),
                            _AttendanceBadge(
                              label: 'Unmarked',
                              value: unmarkedCount < 0 ? 0 : unmarkedCount,
                              color: AppTheme.warning,
                            ),
                            _AttendanceBadge(
                              label: 'Changed',
                              value: modifiedStudents.length,
                              color: AppTheme.fgGold,
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isLoading || isSaving
                                    ? null
                                    : () => _markAll('present'),
                                icon: const Icon(Icons.done_all_rounded),
                                label: const Text('Mark All Present'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.success,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isLoading || isSaving
                                    ? null
                                    : () => _markAll('absent'),
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Mark All Absent'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: errorMessage != null
                    ? ErrorStateView(
                        message: errorMessage!,
                        onRetry: fetchStudentsAndAttendance,
                      )
                    : isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : students.isEmpty
                    ? const Center(child: Text('No students found.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final student = students[index];

                          final id = student['id'].toString();

                          final status = attendanceData[id];

                          final absenceStreak = _absenceStreakFor(id);

                          final needsFollowUp = _needsParentFollowUp(id);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: needsFollowUp
                                    ? AppTheme.danger.withValues(alpha: 0.55)
                                    : AppTheme.border,
                                width: needsFollowUp ? 1.4 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: needsFollowUp
                                        ? AppTheme.danger.withValues(
                                            alpha: 0.10,
                                          )
                                        : AppTheme.fgNavyBlue.withValues(
                                            alpha: 0.08,
                                          ),
                                    foregroundColor: needsFollowUp
                                        ? AppTheme.danger
                                        : AppTheme.fgNavyBlue,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          student['name']?.toString() ??
                                              'Student',
                                          style: TextStyle(
                                            color: needsFollowUp
                                                ? AppTheme.danger
                                                : AppTheme.textPrimary,
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        if (needsFollowUp) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            'Absent $absenceStreak consecutive attendance days • Parent follow-up',
                                            style: const TextStyle(
                                              color: AppTheme.danger,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  _StatusButton(
                                    label: 'P',
                                    selected: status == 'present',
                                    selectedColor: AppTheme.success,
                                    onTap: isSaving
                                        ? null
                                        : () => _setStatus(id, 'present'),
                                  ),
                                  const SizedBox(width: 7),
                                  _StatusButton(
                                    label: 'A',
                                    selected: status == 'absent',
                                    selectedColor: AppTheme.danger,
                                    onTap: isSaving
                                        ? null
                                        : () => _setStatus(id, 'absent'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: modifiedStudents.isEmpty
            ? null
            : SafeArea(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : _saveChanges,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      isSaving
                          ? 'Saving…'
                          : 'Save ${modifiedStudents.length} Change(s)',
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback? onTap;

  const _StatusButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? selectedColor : AppTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 48,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? selectedColor : AppTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
