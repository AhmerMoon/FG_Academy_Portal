import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fee_audit_models.dart';
import '../models/fee_models.dart';
import '../utils/fee_month.dart';

class FeeService {
  final SupabaseClient _client;

  FeeService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<FeeBatch>> fetchBatches() async {
    final response = await _client
        .from('batches')
        .select('id, name, class_level')
        .order('class_level', ascending: true)
        .order('name', ascending: true);

    return response
        .where((row) => row['class_level'] != null)
        .map((row) => FeeBatch.fromJson(Map<String, dynamic>.from(row)))
        .where((batch) => batch.classLevel >= 9 && batch.classLevel <= 12)
        .toList();
  }

  Future<List<String>> fetchAvailableMonths() async {
    final response = await _client
        .from('fee_summary_totals')
        .select('payment_month, month_start')
        .eq('section', 'collection')
        .eq('group_name', 'ALL')
        .order('month_start', ascending: false);

    final months = response
        .map((row) => row['payment_month']?.toString())
        .whereType<String>();

    return FeeMonth.newestFirst(months);
  }

  Future<int> initializeMonth(String paymentMonth) async {
    final result = await _client.rpc(
      'admin_initialize_fee_month',
      params: {'p_payment_month': paymentMonth},
    );

    if (result is num) {
      return result.toInt();
    }

    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  Future<Set<String>> fetchPresentStudentIdsForMonth({
    required String batchId,
    required String paymentMonth,
  }) async {
    final monthStart = FeeMonth.parse(paymentMonth);

    if (monthStart == null) {
      return <String>{};
    }

    final nextMonth = DateTime(monthStart.year, monthStart.month + 1);

    String isoDate(DateTime value) {
      return DateTime(
        value.year,
        value.month,
        value.day,
      ).toIso8601String().split('T').first;
    }

    final rows = await _client
        .from('attendance')
        .select('student_id')
        .eq('batch_id', batchId)
        .eq('status', 'present')
        .gte('date', isoDate(monthStart))
        .lt('date', isoDate(nextMonth));

    return rows
        .map((row) => row['student_id']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<List<FeeStudentEntry>> fetchCollectionEntries({
    required String batchId,
    required String paymentMonth,
  }) async {
    final studentsResponse = await _client
        .from('students')
        .select(
          'id, name, batch_id, '
          'default_fee, stream',
        )
        .eq('batch_id', batchId)
        .order('name', ascending: true);

    final paymentsResponse = await _client
        .from('fee_payments')
        .select(
          'id, student_id, batch_id, '
          'amount_paid, status, '
          'payment_month, updated_at',
        )
        .eq('batch_id', batchId)
        .eq('payment_month', paymentMonth);

    final paymentsByStudent = <String, Map<String, dynamic>>{};

    for (final row in paymentsResponse) {
      final payment = Map<String, dynamic>.from(row);

      final studentId = payment['student_id']?.toString();

      if (studentId != null) {
        paymentsByStudent[studentId] = payment;
      }
    }

    final entries = studentsResponse.map((row) {
      final student = Map<String, dynamic>.from(row);

      final studentId = student['id'].toString();

      return FeeStudentEntry.fromRows(
        student: student,
        payment: paymentsByStudent[studentId],
        paymentMonth: paymentMonth,
      );
    }).toList();

    entries.sort(
      (first, second) => first.name.trim().toLowerCase().compareTo(
        second.name.trim().toLowerCase(),
      ),
    );

    return entries;
  }

  Future<String> savePayment({
    required String studentId,
    required String paymentMonth,
    required bool paid,
    required double amount,
  }) async {
    if (paid && amount <= 0) {
      throw ArgumentError('Paid fee amount must be greater than zero.');
    }

    final result = await _client.rpc(
      'admin_set_fee_payment_status',
      params: {
        'p_student_id': studentId,
        'p_payment_month': paymentMonth,
        'p_status': paid ? 'paid' : 'unpaid',
        'p_amount_paid': paid ? amount : 0,
      },
    );

    if (result == null) {
      throw StateError('Fee payment could not be saved.');
    }

    return result.toString();
  }

  Future<String> addStudent({
    required String name,
    required String batchId,
    required double defaultFee,
    required List<String> subjects,
    required String paymentMonth,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Student name is required.');
    }

    if (defaultFee <= 0) {
      throw ArgumentError('Default fee must be greater than zero.');
    }

    if (subjects.isEmpty) {
      throw ArgumentError('Student subjects are required.');
    }

    final result = await _client.rpc(
      'admin_add_fee_student',
      params: {
        'p_name': name.trim(),
        'p_batch_id': batchId,
        'p_default_fee': defaultFee,
        'p_stream': subjects,
        'p_payment_month': paymentMonth,
      },
    );

    if (result == null) {
      throw StateError('Student could not be created.');
    }

    return result.toString();
  }

  Future<void> setStaffPayment({
    required String paymentMonth,
    required String staffName,
    required double amount,
  }) async {
    if (paymentMonth.trim().isEmpty) {
      throw ArgumentError('Payment month is required.');
    }

    if (staffName.trim().isEmpty) {
      throw ArgumentError('Staff name is required.');
    }

    if (amount < 0) {
      throw ArgumentError('Staff payment cannot be negative.');
    }

    await _client.rpc(
      'admin_set_fee_staff_payment',
      params: {
        'p_payment_month': paymentMonth.trim(),
        'p_staff_name': staffName.trim(),
        'p_amount': amount,
      },
    );
  }

  Future<void> resetStaffPayment({
    required String paymentMonth,
    required String staffName,
  }) async {
    if (paymentMonth.trim().isEmpty) {
      throw ArgumentError('Payment month is required.');
    }

    if (staffName.trim().isEmpty) {
      throw ArgumentError('Staff name is required.');
    }

    await _client.rpc(
      'admin_reset_fee_staff_payment',
      params: {
        'p_payment_month': paymentMonth.trim(),
        'p_staff_name': staffName.trim(),
      },
    );
  }

  Future<List<FeeSummaryRow>> fetchFinancialSummary(String paymentMonth) async {
    final response = await _client
        .from('fee_summary_totals')
        .select(
          'payment_month, month_start, '
          'section, group_name, item_name, '
          'amount, paid_students, '
          'unpaid_students, sort_order',
        )
        .eq('payment_month', paymentMonth)
        .order('sort_order', ascending: true);

    return response
        .map((row) => FeeSummaryRow.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<FeeAuditReportBundle> fetchAuditReport(String paymentMonth) async {
    final classRowsFuture = _client
        .from('fee_audit_class_student_rows')
        .select()
        .eq('payment_month', paymentMonth)
        .order('class_code', ascending: true)
        .order('group_order', ascending: true)
        .order('group_sr_no', ascending: true);

    final classTotalsFuture = _client
        .from('fee_audit_class_totals')
        .select()
        .eq('payment_month', paymentMonth)
        .order('class_level', ascending: true)
        .order('class_code', ascending: true);

    final sscSubjectFuture = _client
        .from('fee_audit_ssc_subject_summary')
        .select()
        .eq('payment_month', paymentMonth)
        .order('display_order', ascending: true);

    final hsscSubjectFuture = _client
        .from('fee_audit_hssc_subject_summary')
        .select()
        .eq('payment_month', paymentMonth)
        .order('display_order', ascending: true);

    final finalSummaryFuture = _client
        .from('fee_audit_final_summary')
        .select()
        .eq('payment_month', paymentMonth)
        .order('display_order', ascending: true);

    final staffFuture = _client
        .from('fee_audit_staff_summary')
        .select()
        .eq('payment_month', paymentMonth)
        .order('display_order', ascending: true);

    final metaFuture = _client
        .from('fee_audit_ecc_balance')
        .select()
        .eq('payment_month', paymentMonth)
        .maybeSingle();

    final results = await Future.wait<dynamic>([
      classRowsFuture,
      classTotalsFuture,
      sscSubjectFuture,
      hsscSubjectFuture,
      finalSummaryFuture,
      staffFuture,
      metaFuture,
    ]);

    final rawClassRows = results[0] as List;
    final rawClassTotals = results[1] as List;
    final rawSscSubjects = results[2] as List;
    final rawHsscSubjects = results[3] as List;
    final rawFinalSummary = results[4] as List;
    final rawStaff = results[5] as List;
    final rawMeta = results[6];

    if (rawMeta == null) {
      throw StateError(
        'Audit metadata is unavailable '
        'for $paymentMonth.',
      );
    }

    return FeeAuditReportBundle(
      paymentMonth: paymentMonth,
      students: rawClassRows
          .map(
            (row) => FeeAuditClassStudentRow.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(),
      classTotals: rawClassTotals
          .map(
            (row) =>
                FeeAuditClassTotal.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      sscSubjects: rawSscSubjects
          .map(
            (row) => FeeAuditSubjectRow.fromSsc(Map<String, dynamic>.from(row)),
          )
          .toList(),
      hsscSubjects: rawHsscSubjects
          .map(
            (row) =>
                FeeAuditSubjectRow.fromHssc(Map<String, dynamic>.from(row)),
          )
          .toList(),
      finalSummary: rawFinalSummary
          .map(
            (row) => FeeAuditFinalRow.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      staff: rawStaff
          .map(
            (row) => FeeAuditStaffRow.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      meta: FeeAuditMeta.fromJson(Map<String, dynamic>.from(rawMeta)),
    );
  }
}
