import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import '../utils/error_state_view.dart';
import '../utils/list_sorting.dart';
import '../widgets/academy_background.dart';
import '../utils/student_group_helper.dart';

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
  final SupabaseClient supabase = Supabase.instance.client;

  List<dynamic> students = [];

  final Map<String, String?> attendanceStatus = {};

  final Map<String, int> _priorAbsenceStreak = {};

  final Set<String> modifiedStudents = {};

  bool isLoading = true;

  bool isSaving = false;

  bool _isAddingStudent = false;

  String? errorMessage;

  int? _classLevel;

  String? _teacherSubjectCode;

  late final String todayDate;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    todayDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).toIso8601String().split('T').first;

    fetchStudentsAndAttendance();
  }

  int get presentCount =>
      attendanceStatus.values.where((status) => status == 'present').length;

  int get absentCount =>
      attendanceStatus.values.where((status) => status == 'absent').length;

  int get unmarkedCount => students.length - presentCount - absentCount;

  bool get hasUnsavedChanges => modifiedStudents.isNotEmpty;

  String _dateOnly(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
    ).toIso8601String().split('T').first;
  }

  String _subjectLabel(String code) {
    switch (code) {
      case 'Phy':
        return 'Physics';

      case 'Chem':
        return 'Chemistry';

      case 'Math':
        return 'Mathematics';

      case 'Eng':
        return 'English';

      case 'Comp':
        return 'Computer';

      case 'Bio':
        return 'Biology';

      default:
        return code;
    }
  }

  bool _shouldFilterAttendanceBySubject(int classLevel, String? subjectCode) {
    if (subjectCode == null) {
      return false;
    }

    if (classLevel == 9 || classLevel == 10) {
      return const {'Comp', 'Bio'}.contains(subjectCode);
    }

    if (classLevel == 11 || classLevel == 12) {
      return const {'Comp', 'Bio', 'Chem'}.contains(subjectCode);
    }

    return false;
  }

  int _absenceStreakFor(String studentId) {
    final previous = _priorAbsenceStreak[studentId] ?? 0;

    final todayStatus = attendanceStatus[studentId];

    if (todayStatus == 'present') {
      return 0;
    }

    if (todayStatus == 'absent') {
      return previous + 1;
    }

    return previous;
  }

  bool _needsParentFollowUp(String studentId) {
    return _absenceStreakFor(studentId) >= 4;
  }

  Future<void> fetchStudentsAndAttendance() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      // ========================================================
      // CLASS CONTEXT
      // ========================================================

      final batchRow = await supabase
          .from('batches')
          .select('id, class_level')
          .eq('id', widget.batchId)
          .single();

      final classLevel = (batchRow['class_level'] as num?)?.toInt();

      if (classLevel == null) {
        throw StateError('Batch class level is unavailable.');
      }

      // ========================================================
      // TEACHER SUBJECT
      // ========================================================

      String? teacherSubject;

      final authUser = supabase.auth.currentUser;

      if (authUser != null) {
        final assignments = await supabase
            .from('teacher_assignments')
            .select('subject_code')
            .eq('teacher_id', authUser.id)
            .eq('class_level', classLevel)
            .limit(1);

        if (assignments.isNotEmpty) {
          teacherSubject = assignments.first['subject_code']?.toString();
        }
      }

      final filterBySubject = _shouldFilterAttendanceBySubject(
        classLevel,
        teacherSubject,
      );

      // ========================================================
      // STUDENTS + ATTENDANCE
      // ========================================================

      final today = DateTime.parse(todayDate);

      final historyStart = _dateOnly(today.subtract(const Duration(days: 60)));

      final results = await Future.wait<dynamic>([
        supabase
            .from('students')
            .select('id, name, stream')
            .eq('batch_id', widget.batchId)
            .order('name', ascending: true),

        supabase
            .from('attendance')
            .select('student_id, status')
            .eq('batch_id', widget.batchId)
            .eq('date', todayDate),

        supabase
            .from('attendance')
            .select('student_id, date, status')
            .eq('batch_id', widget.batchId)
            .gte('date', historyStart)
            .lt('date', todayDate)
            .order('date', ascending: false),
      ]);

      final rawStudents = results[0] as List;

      final filteredStudents = rawStudents.where((raw) {
        if (!filterBySubject) {
          return true;
        }

        final stream = raw['stream'];

        if (stream is! List) {
          return false;
        }

        return stream.map((item) => item.toString()).contains(teacherSubject);
      }).toList();

      final studentRows = sortStudents(filteredStudents);

      final visibleIds = studentRows
          .map((student) => student['id'].toString())
          .toSet();

      final attendanceRows = results[1] as List;

      final historyRows = results[2] as List;

      attendanceStatus.clear();
      _priorAbsenceStreak.clear();
      modifiedStudents.clear();

      for (final student in studentRows) {
        final id = student['id'].toString();

        attendanceStatus[id] = null;

        _priorAbsenceStreak[id] = 0;
      }

      for (final row in attendanceRows) {
        final studentId = row['student_id'].toString();

        if (!visibleIds.contains(studentId)) {
          continue;
        }

        attendanceStatus[studentId] = row['status']?.toString();
      }

      final historyByStudent = <String, List<Map<String, dynamic>>>{};

      for (final rawRow in historyRows) {
        final row = Map<String, dynamic>.from(rawRow);

        final studentId = row['student_id']?.toString();

        if (studentId == null || !visibleIds.contains(studentId)) {
          continue;
        }

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

        _classLevel = classLevel;

        _teacherSubjectCode = teacherSubject;

        isLoading = false;

        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Teacher attendance load error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;

        errorMessage =
            'Unable to load students and attendance. '
            'Check your connection and try again.';
      });
    }
  }

  void _setStatus(String studentId, String status) {
    setState(() {
      attendanceStatus[studentId] = status;

      modifiedStudents.add(studentId);
    });
  }

  void _markAll(String status) {
    setState(() {
      for (final student in students) {
        final id = student['id'].toString();

        attendanceStatus[id] = status;

        modifiedStudents.add(id);
      }
    });
  }

  Future<void> _openAddStudentDialog() async {
    if (hasUnsavedChanges) {
      _showMessage(
        'Please save the current attendance changes before adding a new student.',
        error: true,
      );

      return;
    }

    final classLevel = _classLevel;

    if (classLevel == null) {
      _showMessage('Class information is unavailable.', error: true);

      return;
    }

    final groupCodes = studentGroupCodesForClass(classLevel);

    String? selectedGroupCode;

    // Group subject teacher ho to
    // relevant group automatically select.
    if (_teacherSubjectCode != null &&
        groupCodes.contains(_teacherSubjectCode)) {
      selectedGroupCode = _teacherSubjectCode;
    }

    final nameController = TextEditingController();

    String? dialogError;

    final request = await showDialog<_NewAttendanceStudentDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final subjects = selectedGroupCode == null
                ? <String>[]
                : studentSubjectsForGroup(classLevel, selectedGroupCode!);

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    color: AppTheme.fgNavyBlue,
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Text('Add New Student')),
                ],
              ),

              content: SizedBox(
                width: 490,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.batchName,
                        style: const TextStyle(
                          color: AppTheme.fgNavyBlue,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        'Class $classLevel',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      if (_teacherSubjectCode != null) ...[
                        const SizedBox(height: 8),

                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.fgNavyBlue.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Your teaching subject: '
                            '${_subjectLabel(_teacherSubjectCode!)}',
                            style: const TextStyle(
                              color: AppTheme.fgNavyBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Student Name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text(
                        classLevel <= 10
                            ? 'Choose Student Group'
                            : 'Choose HSSC Group',
                        style: const TextStyle(
                          color: AppTheme.fgNavyBlue,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        classLevel <= 10
                            ? 'Choose Computer or Biology. All required subjects will be added automatically.'
                            : 'Choose FCS, Pre-Engineering or Pre-Medical. All correct subjects will be added automatically.',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 11),

                      Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: groupCodes.map((code) {
                          return ChoiceChip(
                            selected: selectedGroupCode == code,
                            avatar: Icon(
                              selectedGroupCode == code
                                  ? Icons.check_circle_rounded
                                  : Icons.school_outlined,
                              size: 18,
                            ),
                            label: Text(
                              studentGroupLabel(classLevel, code),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onSelected: (selected) {
                              if (!selected) {
                                return;
                              }

                              setDialogState(() {
                                selectedGroupCode = code;

                                dialogError = null;
                              });
                            },
                          );
                        }).toList(),
                      ),

                      if (subjects.isNotEmpty) ...[
                        const SizedBox(height: 20),

                        const Text(
                          'Subjects Added Automatically',
                          style: TextStyle(
                            color: AppTheme.fgNavyBlue,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: subjects.map((code) {
                            return Chip(
                              avatar: const Icon(
                                Icons.check_circle_rounded,
                                size: 17,
                                color: AppTheme.success,
                              ),
                              label: Text(
                                _subjectLabel(code),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 18),

                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: AppTheme.success.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              color: AppTheme.success,
                            ),

                            SizedBox(width: 9),

                            Expanded(
                              child: Text(
                                'On save:\n'
                                '• Student will be enrolled\n'
                                '• Today attendance will be Present\n'
                                '• Current month fee will be Unpaid\n'
                                '• Correct group subjects will be added automatically',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.55,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (dialogError != null) ...[
                        const SizedBox(height: 12),

                        Text(
                          dialogError!,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),

                ElevatedButton.icon(
                  onPressed: () {
                    final name = nameController.text.trim();

                    if (name.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Student name is required.';
                      });

                      return;
                    }

                    if (selectedGroupCode == null) {
                      setDialogState(() {
                        dialogError = classLevel <= 10
                            ? 'Please choose Computer or Biology.'
                            : 'Please choose FCS, Pre-Engineering or Pre-Medical.';
                      });

                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _NewAttendanceStudentDraft(
                        name: name,
                        groupSubject: selectedGroupCode!,
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add Student'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();

    if (request == null || !mounted) {
      return;
    }

    await _addNewStudent(request);
  }

  Future<void> _addNewStudent(_NewAttendanceStudentDraft request) async {
    setState(() {
      _isAddingStudent = true;
    });

    try {
      await supabase.rpc(
        'portal_add_student_from_attendance',
        params: {
          'p_name': request.name,
          'p_batch_id': widget.batchId,
          'p_group_subject': request.groupSubject,
        },
      );

      if (!mounted) return;

      _showMessage(
        '${request.name} added successfully. '
        'Today attendance is Present and current month fee is Unpaid.',
      );

      await fetchStudentsAndAttendance();
    } catch (e) {
      debugPrint('Teacher add student error: $e');

      if (!mounted) return;

      var message = 'Could not add student. Please try again.';

      final raw = e.toString().toLowerCase();

      if (raw.contains('already exists')) {
        message = 'A student with this name already exists in this batch.';
      } else if (raw.contains('not allowed')) {
        message = 'You are not allowed to add a student to this batch.';
      }

      _showMessage(message, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isAddingStudent = false;
        });
      }
    }
  }

  Future<bool> _confirmSubmit() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Confirm Attendance'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ConfirmationRow(label: 'Batch', value: widget.batchName),

                  _ConfirmationRow(label: 'Present', value: '$presentCount'),

                  _ConfirmationRow(label: 'Absent', value: '$absentCount'),

                  _ConfirmationRow(
                    label: 'Changed',
                    value: '${modifiedStudents.length}',
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Please verify the class count before saving.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),

                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Save Attendance'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _submitAttendance() async {
    if (modifiedStudents.isEmpty) {
      _showMessage('No attendance changes to save.');

      return;
    }

    if (unmarkedCount > 0) {
      _showMessage(
        '$unmarkedCount student(s) are still unmarked. '
        'Mark everyone Present or Absent before submitting.',
        error: true,
      );

      return;
    }

    final confirmed = await _confirmSubmit();

    if (!confirmed || !mounted) {
      return;
    }

    final payload = <Map<String, dynamic>>[];

    for (final studentId in modifiedStudents) {
      final status = attendanceStatus[studentId];

      if (status == null) continue;

      payload.add({
        'student_id': studentId,
        'batch_id': widget.batchId,
        'date': todayDate,
        'status': status,
      });
    }

    if (payload.isEmpty) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await supabase
          .from('attendance')
          .upsert(payload, onConflict: 'student_id, date');

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

      _showMessage(
        'Could not save attendance. '
        'Check your connection and try again.',
        error: true,
      );
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Unsaved Attendance'),
            content: Text(
              '${modifiedStudents.length} attendance change(s) '
              'have not been saved. Leave and discard them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Stay'),
              ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard & Leave'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _attemptBack() async {
    if (hasUnsavedChanges) {
      final discard = await _confirmDiscardChanges();

      if (!discard || !mounted) {
        return;
      }
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
    final date = DateTime.parse(todayDate);

    return PopScope(
      canPop: !hasUnsavedChanges,
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
              tooltip: 'Add New Student',
              onPressed: isSaving || _isAddingStudent
                  ? null
                  : _openAddStudentDialog,
              icon: _isAddingStudent
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
            ),

            IconButton(
              tooltip: 'Refresh',
              onPressed: isSaving || _isAddingStudent
                  ? null
                  : fetchStudentsAndAttendance,
              icon: const Icon(Icons.refresh_rounded),
            ),

            const SizedBox(width: 4),
          ],
        ),

        body: AcademyBackground(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage != null
              ? ErrorStateView(
                  message: errorMessage!,
                  onRetry: fetchStudentsAndAttendance,
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 7),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppTheme.fgNavyBlue.withValues(
                                        alpha: 0.07,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.today_rounded,
                                      color: AppTheme.fgNavyBlue,
                                    ),
                                  ),

                                  const SizedBox(width: 11),

                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          DateFormat('EEEE').format(date),
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),

                                        Text(
                                          DateFormat(
                                            'dd MMM yyyy',
                                          ).format(date),
                                          style: const TextStyle(
                                            color: AppTheme.fgNavyBlue,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const Divider(height: 22),

                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  _TeacherCountBadge(
                                    label: 'Total',
                                    value: students.length,
                                    color: AppTheme.info,
                                  ),

                                  _TeacherCountBadge(
                                    label: 'Present',
                                    value: presentCount,
                                    color: AppTheme.success,
                                  ),

                                  _TeacherCountBadge(
                                    label: 'Absent',
                                    value: absentCount,
                                    color: AppTheme.danger,
                                  ),

                                  _TeacherCountBadge(
                                    label: 'Unmarked',
                                    value: unmarkedCount < 0
                                        ? 0
                                        : unmarkedCount,
                                    color: AppTheme.warning,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 13),

                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isSaving
                                          ? null
                                          : () => _markAll('present'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.success,
                                      ),
                                      icon: const Icon(Icons.done_all_rounded),
                                      label: const Text('All Present'),
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isSaving
                                          ? null
                                          : () => _markAll('absent'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.danger,
                                      ),
                                      icon: const Icon(Icons.close_rounded),
                                      label: const Text('All Absent'),
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
                      child: students.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.groups_outlined,
                                    color: AppTheme.textSecondary,
                                    size: 50,
                                  ),

                                  const SizedBox(height: 12),

                                  const Text(
                                    'No students found in this batch.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  ElevatedButton.icon(
                                    onPressed: _openAddStudentDialog,
                                    icon: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                    ),
                                    label: const Text('Add First Student'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                4,
                                12,
                                110,
                              ),
                              itemCount: students.length,
                              itemBuilder: (context, index) {
                                final student = students[index];

                                final id = student['id'].toString();

                                final status = attendanceStatus[id];

                                final absenceStreak = _absenceStreakFor(id);

                                final needsFollowUp = _needsParentFollowUp(id);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: needsFollowUp
                                          ? AppTheme.danger.withValues(
                                              alpha: 0.55,
                                            )
                                          : AppTheme.border,
                                      width: needsFollowUp ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
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
                                              fontSize: 13,
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
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: needsFollowUp
                                                      ? AppTheme.danger
                                                      : AppTheme.textPrimary,
                                                ),
                                              ),

                                              if (needsFollowUp) ...[
                                                const SizedBox(height: 3),

                                                Text(
                                                  'Absent $absenceStreak consecutive attendance days • Parent follow-up',
                                                  style: const TextStyle(
                                                    color: AppTheme.danger,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),

                                        _TeacherStatusButton(
                                          label: 'P',
                                          selected: status == 'present',
                                          color: AppTheme.success,
                                          onTap: isSaving
                                              ? null
                                              : () => _setStatus(id, 'present'),
                                        ),

                                        const SizedBox(width: 7),

                                        _TeacherStatusButton(
                                          label: 'A',
                                          selected: status == 'absent',
                                          color: AppTheme.danger,
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

        bottomNavigationBar: !hasUnsavedChanges
            ? null
            : SafeArea(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : _submitAttendance,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cloud_done_outlined),
                    label: Text(
                      isSaving ? 'Saving Attendance…' : 'Submit Attendance',
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _NewAttendanceStudentDraft {
  final String name;

  final String groupSubject;

  const _NewAttendanceStudentDraft({
    required this.name,
    required this.groupSubject,
  });
}

class _TeacherCountBadge extends StatelessWidget {
  final String label;

  final int value;

  final Color color;

  const _TeacherCountBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              fontSize: 16,
            ),
          ),

          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherStatusButton extends StatelessWidget {
  final String label;

  final bool selected;

  final Color color;

  final VoidCallback? onTap;

  const _TeacherStatusButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : AppTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 50,
          height: 43,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: selected ? color : AppTheme.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmationRow extends StatelessWidget {
  final String label;

  final String value;

  const _ConfirmationRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ),

          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
