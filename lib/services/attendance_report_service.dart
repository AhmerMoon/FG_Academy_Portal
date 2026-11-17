import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/attendance_report_models.dart';
import '../utils/list_sorting.dart';

class AttendanceReportService {
  final SupabaseClient _supabase;

  AttendanceReportService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  Future<AttendanceReportData> loadBatchMonth({
    required String batchId,
    required String batchName,
    required DateTime month,
  }) async {
    final normalizedMonth = DateTime(month.year, month.month);
    final firstDay = _dateOnly(normalizedMonth);
    final lastDay = _dateOnly(
      DateTime(normalizedMonth.year, normalizedMonth.month + 1, 0),
    );

    final results = await Future.wait<dynamic>([
      _supabase
          .from('students')
          .select('id, name')
          .eq('batch_id', batchId)
          .eq('is_archived', false)
          .order('name'),
      _supabase
          .from('attendance')
          .select('student_id, date, status')
          .eq('batch_id', batchId)
          .gte('date', firstDay)
          .lte('date', lastDay),
    ]);

    final students = sortStudents(results[0] as List);
    final attendance = results[1] as List;
    final statuses = <String, Map<int, String>>{};

    for (final raw in attendance) {
      final studentId = raw['student_id']?.toString();
      final date = DateTime.tryParse(raw['date']?.toString() ?? '');
      final status = raw['status']?.toString();
      if (studentId == null || date == null) continue;
      if (status != 'present' && status != 'absent' && status != 'leave') {
        continue;
      }
      statuses.putIfAbsent(studentId, () => {})[date.day] = status!;
    }

    final lastDayNumber = DateTime(
      normalizedMonth.year,
      normalizedMonth.month + 1,
      0,
    ).day;
    final validDays = <int>[
      for (var day = 1; day <= lastDayNumber; day++)
        if (DateTime(
              normalizedMonth.year,
              normalizedMonth.month,
              day,
            ).weekday !=
            DateTime.sunday)
          day,
    ];

    return AttendanceReportData(
      batchId: batchId,
      batchName: batchName,
      month: normalizedMonth,
      attendanceDays: validDays,
      rows: [
        for (final student in students)
          AttendanceReportRow(
            studentId: student['id'].toString(),
            studentName: student['name']?.toString() ?? 'Student',
            statusByDay: statuses[student['id'].toString()] ?? const {},
          ),
      ],
    );
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
