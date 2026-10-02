import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/fee_month.dart';

class StudentAlertService {
  final SupabaseClient _client;

  StudentAlertService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// Returns students whose latest consecutive RECORDED attendance
  /// contains at least [threshold] absences.
  ///
  /// threshold = 4 means:
  /// more than 3 consecutive absences -> alert.
  Future<Set<String>> fetchLongAbsenceStudentIds({
    required String batchId,
    required DateTime asOfDate,
    int threshold = 4,
  }) async {
    final date = DateTime(
      asOfDate.year,
      asOfDate.month,
      asOfDate.day,
    ).toIso8601String().split('T').first;

    final rows = await _client
        .from('attendance')
        .select('student_id, date, status')
        .eq('batch_id', batchId)
        .lte('date', date)
        .order('date', ascending: false);

    final history = <String, List<Map<String, dynamic>>>{};

    for (final rawRow in rows) {
      final row = Map<String, dynamic>.from(rawRow);

      final studentId = row['student_id']?.toString();

      if (studentId == null || studentId.isEmpty) {
        continue;
      }

      history.putIfAbsent(studentId, () => []).add(row);
    }

    final result = <String>{};

    for (final entry in history.entries) {
      var streak = 0;

      // Rows are already newest -> oldest.
      for (final row in entry.value) {
        final status = row['status']?.toString();

        if (status == 'absent') {
          streak++;

          if (streak >= threshold) {
            result.add(entry.key);
            break;
          }

          continue;
        }

        // First recorded present day breaks the absence streak.
        if (status == 'present') {
          break;
        }
      }
    }

    return result;
  }

  /// Returns students who:
  /// 1. have at least one PRESENT attendance record in selected fee month, and
  /// 2. the fee due date (5th) has passed.
  ///
  /// Payment status is checked by the Fees UI itself.
  Future<Set<String>> fetchOverduePresentStudentIds({
    required String batchId,
    required String paymentMonth,
  }) async {
    final monthStart = FeeMonth.parse(paymentMonth);

    if (monthStart == null) {
      return <String>{};
    }

    final now = DateTime.now();

    // Fee remains normal through the 5th.
    // From the 6th onward it becomes overdue.
    final alertStarts = DateTime(monthStart.year, monthStart.month, 6);

    if (now.isBefore(alertStarts)) {
      return <String>{};
    }

    final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);

    String dateOnly(DateTime date) => date.toIso8601String().split('T').first;

    final rows = await _client
        .from('attendance')
        .select('student_id')
        .eq('batch_id', batchId)
        .eq('status', 'present')
        .gte('date', dateOnly(monthStart))
        .lt('date', dateOnly(nextMonth));

    return rows
        .map((row) => row['student_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }
}
