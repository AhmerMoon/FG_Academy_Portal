import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../utils/error_state_view.dart';
import '../utils/list_sorting.dart';
import '../widgets/academy_background.dart';

class TeacherAttendanceHistoryScreen extends StatefulWidget {
  final String batchId;
  final String batchName;

  final int? classLevel;
  final String? teacherSubjectCode;

  const TeacherAttendanceHistoryScreen({
    super.key,
    required this.batchId,
    required this.batchName,
    this.classLevel,
    this.teacherSubjectCode,
  });

  @override
  State<TeacherAttendanceHistoryScreen> createState() =>
      _TeacherAttendanceHistoryScreenState();
}

class _TeacherAttendanceHistoryScreenState
    extends State<TeacherAttendanceHistoryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  List<dynamic> _students = [];

  final Map<String, String> _attendance = {};

  bool _loading = true;
  String? _error;

  String get _dateString => _selectedDate.toIso8601String().split('T').first;

  int get _present =>
      _attendance.values.where((value) => value == 'present').length;

  int get _absent =>
      _attendance.values.where((value) => value == 'absent').length;

  int get _unmarked => _students.length - _present - _absent;

  @override
  void initState() {
    super.initState();

    _load();
  }

  bool get _filterBySubject {
    final classLevel = widget.classLevel;

    final subject = widget.teacherSubjectCode;

    if (classLevel == null || subject == null) {
      return false;
    }

    return classLevel >= 9 && classLevel <= 12;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('students')
            .select('id, name, stream')
            .eq('batch_id', widget.batchId)
            .order('name', ascending: true),

        _supabase
            .from('attendance')
            .select('student_id, status')
            .eq('batch_id', widget.batchId)
            .eq('date', _dateString),
      ]);

      final rawStudents = results[0] as List;

      final subject = widget.teacherSubjectCode;

      final filteredStudents = rawStudents.where((raw) {
        if (!_filterBySubject) {
          return true;
        }

        final stream = raw['stream'];

        if (stream is! List) {
          return false;
        }

        return stream.map((item) => item.toString()).contains(subject);
      }).toList();

      final students = sortStudents(filteredStudents);

      final visibleIds = students
          .map((student) => student['id'].toString())
          .toSet();

      final rows = results[1] as List;

      final attendance = <String, String>{};

      for (final row in rows) {
        final id = row['student_id']?.toString();

        final status = row['status']?.toString();

        if (id == null || status == null || !visibleIds.contains(id)) {
          continue;
        }

        attendance[id] = status;
      }

      if (!mounted) return;

      setState(() {
        _students = students;

        _attendance
          ..clear()
          ..addAll(attendance);

        _loading = false;
      });
    } catch (e) {
      debugPrint('Teacher attendance history error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load attendance history.';
      });
    }
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = selected;
    });

    await _load();
  }

  Future<void> _moveDay(int days) async {
    final candidate = _selectedDate.add(Duration(days: days));

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    if (candidate.isAfter(today)) {
      return;
    }

    setState(() {
      _selectedDate = candidate;
    });

    await _load();
  }

  Widget _stat(String label, int value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('${widget.batchName} History'),
        actions: [
          IconButton(
            tooltip: 'Choose Date',
            onPressed: _loading ? null : _chooseDate,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: AcademyBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ErrorStateView(message: _error!, onRetry: _load)
            : Column(
                children: [
                  Card(
                    margin: const EdgeInsets.all(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous Day',
                                onPressed: () => _moveDay(-1),
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: _chooseDate,
                                  child: Column(
                                    children: [
                                      Text(
                                        DateFormat(
                                          'EEEE',
                                        ).format(_selectedDate),
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        DateFormat(
                                          'dd MMMM yyyy',
                                        ).format(_selectedDate),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.fgNavyBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next Day',
                                onPressed: () => _moveDay(1),
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              _stat('Present', _present, AppTheme.success),
                              _stat('Absent', _absent, AppTheme.danger),
                              _stat('Unmarked', _unmarked, AppTheme.warning),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];

                          final id = student['id'].toString();

                          final name = student['name']?.toString() ?? 'Student';

                          final status = _attendance[id];

                          final present = status == 'present';

                          final absent = status == 'absent';

                          final color = present
                              ? AppTheme.success
                              : absent
                              ? AppTheme.danger
                              : AppTheme.warning;

                          final text = present
                              ? 'Present'
                              : absent
                              ? 'Absent'
                              : 'Unmarked';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.10),
                                foregroundColor: color,
                                child: Icon(
                                  present
                                      ? Icons.check_circle_rounded
                                      : absent
                                      ? Icons.cancel_rounded
                                      : Icons.help_outline_rounded,
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: Text(
                                text,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
