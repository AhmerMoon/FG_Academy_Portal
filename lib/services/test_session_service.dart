import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/test_session_models.dart';
import '../utils/list_sorting.dart';
import '../utils/student_group_helper.dart';

class TestSessionService {
  final SupabaseClient _client;

  TestSessionService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchBatches() async {
    final rows = await _client
        .from('batches')
        .select('id,name,class_level')
        .order('class_level')
        .order('name');
    return sortBatches(
      rows,
    ).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<TestSessionTest>> fetchTests({
    required String batchId,
    required String subjectCode,
  }) async {
    final rows = await _client
        .from('test_session_tests')
        .select(
          'id,batch_id,subject_code,test_no,test_date,max_marks,'
          'status,created_by',
        )
        .eq('batch_id', batchId)
        .eq('subject_code', subjectCode)
        .order('test_no', ascending: false);
    return rows
        .map((row) => TestSessionTest.fromJson(row))
        .toList(growable: false);
  }

  Future<List<TestSessionTest>> fetchAllTests() async {
    const pageSize = 500;
    final tests = <TestSessionTest>[];
    for (var offset = 0; ; offset += pageSize) {
      final rows = await _client
          .from('test_session_tests')
          .select(
            'id,batch_id,subject_code,test_no,test_date,max_marks,'
            'status,created_by',
          )
          .order('test_no', ascending: false)
          .order('id')
          .range(offset, offset + pageSize - 1);
      tests.addAll(rows.map((row) => TestSessionTest.fromJson(row)));
      if (rows.length < pageSize) break;
    }
    return tests;
  }

  Future<List<Map<String, dynamic>>> fetchEligibleStudents({
    required String batchId,
    required String subjectCode,
    required DateTime testDate,
  }) async {
    final rows = await _client
        .from('students')
        .select('id,name,stream,created_at')
        .eq('batch_id', batchId)
        .eq('is_archived', false)
        .order('name');

    final date = DateTime(testDate.year, testDate.month, testDate.day);
    return rows
        .where((row) {
          final subjects = ((row['stream'] as List?) ?? [])
              .map((value) => value.toString())
              .toSet();
          if (!subjects.contains(subjectCode)) return false;
          final joined = DateTime.tryParse(row['created_at']?.toString() ?? '');
          if (joined == null) return true;
          final local = joined.toLocal();
          return !DateTime(local.year, local.month, local.day).isAfter(date);
        })
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, TestSessionMark>> fetchMarks(String testId) async {
    final rows = await _client
        .from('test_session_marks')
        .select('student_id,marks,is_absent')
        .eq('test_id', testId);
    return {
      for (final row in rows)
        row['student_id'].toString(): TestSessionMark.fromJson(row),
    };
  }

  Future<String> createTest({
    required String batchId,
    required String subjectCode,
    required int testNo,
    required DateTime testDate,
    required double maxMarks,
  }) async {
    final result = await _client.rpc(
      'test_session_upsert_test',
      params: {
        'p_batch_id': batchId,
        'p_subject_code': subjectCode,
        'p_test_no': testNo,
        'p_test_date': testDate.toIso8601String().split('T').first,
        'p_max_marks': maxMarks,
      },
    );
    return result.toString();
  }

  Future<void> saveMark({
    required String testId,
    required String studentId,
    double? marks,
    required bool absent,
  }) async {
    await _client.rpc(
      'test_session_save_mark',
      params: {
        'p_test_id': testId,
        'p_student_id': studentId,
        'p_marks': marks,
        'p_is_absent': absent,
      },
    );
  }

  Future<void> clearMark({
    required String testId,
    required String studentId,
  }) async {
    await _client.rpc(
      'test_session_clear_mark',
      params: {'p_test_id': testId, 'p_student_id': studentId},
    );
  }

  Future<void> finalize(String testId) async {
    await _client.rpc(
      'test_session_finalize_test',
      params: {'p_test_id': testId},
    );
  }

  Future<void> reopen(String testId) async {
    await _client.rpc(
      'test_session_reopen_test',
      params: {'p_test_id': testId},
    );
  }

  Future<void> delete(String testId) async {
    await _client.rpc(
      'test_session_delete_test',
      params: {'p_test_id': testId},
    );
  }

  Future<TestSessionReportData> subjectReport({
    required Map<String, dynamic> batch,
    required TestSessionTest test,
  }) async {
    final students = await fetchEligibleStudents(
      batchId: test.batchId,
      subjectCode: test.subjectCode,
      testDate: test.testDate,
    );
    final marks = await fetchMarks(test.id);
    return TestSessionReportData(
      batchName: batch['name']?.toString() ?? 'Batch',
      classLevel: (batch['class_level'] as num?)?.toInt() ?? 0,
      testNo: test.testNo,
      title: '${studentSubjectLabel(test.subjectCode)} Subject Report',
      incomplete: !test.finalized,
      completedSubjects: test.finalized ? 1 : 0,
      requiredSubjects: 1,
      columns: [
        TestSessionReportColumn(
          key: test.subjectCode,
          label: studentSubjectLabel(test.subjectCode),
          subjectCodes: [test.subjectCode],
          maxMarks: test.maxMarks,
        ),
      ],
      rows: students.map((student) {
        final mark = marks[student['id'].toString()];
        return TestSessionReportRow(
          name: student['name']?.toString() ?? 'Student',
          cells: {test.subjectCode: _markText(mark, test.maxMarks)},
        );
      }).toList(),
    );
  }

  Future<TestSessionReportData> combinedReport({
    required Map<String, dynamic> batch,
    required int testNo,
  }) async {
    final batchId = batch['id'].toString();
    final classLevel = (batch['class_level'] as num?)?.toInt() ?? 0;
    final responses = await Future.wait<dynamic>([
      _client
          .from('students')
          .select('id,name,stream,created_at')
          .eq('batch_id', batchId)
          .eq('is_archived', false)
          .order('name'),
      _client
          .from('test_session_tests')
          .select(
            'id,batch_id,subject_code,test_no,test_date,max_marks,'
            'status,created_by',
          )
          .eq('batch_id', batchId)
          .eq('test_no', testNo),
    ]);
    final students = (responses[0] as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final tests = (responses[1] as List)
        .map((row) => TestSessionTest.fromJson(row))
        .toList();
    final testBySubject = {for (final test in tests) test.subjectCode: test};
    final testIds = tests.map((test) => test.id).toList();
    final rawMarks = testIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
              .from('test_session_marks')
              .select('test_id,student_id,marks,is_absent')
              .inFilter('test_id', testIds);
    final marks = <String, TestSessionMark>{};
    for (final row in rawMarks) {
      marks['${row['test_id']}:${row['student_id']}'] =
          TestSessionMark.fromJson(row);
    }

    final required = <String>{};
    for (final student in students) {
      required.addAll(
        ((student['stream'] as List?) ?? []).map((value) => value.toString()),
      );
    }
    final completed = required
        .where((code) => testBySubject[code]?.finalized == true)
        .length;
    final columns = classLevel <= 10
        ? const [
            TestSessionReportColumn(
              key: 'Phy',
              label: 'Physics',
              subjectCodes: ['Phy'],
            ),
            TestSessionReportColumn(
              key: 'Chem',
              label: 'Chemistry',
              subjectCodes: ['Chem'],
            ),
            TestSessionReportColumn(
              key: 'Math',
              label: 'Mathematics',
              subjectCodes: ['Math'],
            ),
            TestSessionReportColumn(
              key: 'Eng',
              label: 'English',
              subjectCodes: ['Eng'],
            ),
            TestSessionReportColumn(
              key: 'Comp',
              label: 'Computer',
              subjectCodes: ['Comp'],
            ),
            TestSessionReportColumn(
              key: 'Bio',
              label: 'Biology',
              subjectCodes: ['Bio'],
            ),
          ]
        : const [
            TestSessionReportColumn(
              key: 'Phy',
              label: 'Physics',
              subjectCodes: ['Phy'],
            ),
            TestSessionReportColumn(
              key: 'Chem',
              label: 'Chemistry',
              subjectCodes: ['Chem'],
            ),
            TestSessionReportColumn(
              key: 'Math',
              label: 'Mathematics',
              subjectCodes: ['Math'],
            ),
            TestSessionReportColumn(
              key: 'Eng',
              label: 'English',
              subjectCodes: ['Eng'],
            ),
            TestSessionReportColumn(
              key: 'elective',
              label: 'Computer / Biology',
              subjectCodes: ['Comp', 'Bio'],
            ),
          ];

    final reportColumns = columns.map((column) {
      final maxima = column.subjectCodes
          .map((code) => testBySubject[code]?.maxMarks)
          .whereType<double>()
          .toSet();
      return TestSessionReportColumn(
        key: column.key,
        label: column.label,
        subjectCodes: column.subjectCodes,
        maxMarks: maxima.length == 1 ? maxima.first : null,
      );
    }).toList();

    return TestSessionReportData(
      batchName: batch['name']?.toString() ?? 'Batch',
      classLevel: classLevel,
      testNo: testNo,
      title: 'Combined Class Report',
      incomplete: completed < required.length,
      completedSubjects: completed,
      requiredSubjects: required.length,
      columns: reportColumns,
      rows: students.map((student) {
        final studentSubjects = ((student['stream'] as List?) ?? [])
            .map((value) => value.toString())
            .toSet();
        final cells = <String, String>{};
        for (final column in reportColumns) {
          final studied = column.subjectCodes
              .where(studentSubjects.contains)
              .toList();
          if (studied.isEmpty) {
            cells[column.key] = '—';
            continue;
          }
          final code = studied.first;
          final test = testBySubject[code];
          if (test == null) {
            cells[column.key] = 'Pending';
            continue;
          }
          final mark = marks['${test.id}:${student['id']}'];
          final prefix = column.key == 'elective'
              ? '${code == 'Comp' ? 'C' : 'B'}: '
              : '';
          cells[column.key] = '$prefix${_markText(mark, test.maxMarks)}';
        }
        return TestSessionReportRow(
          name: student['name']?.toString() ?? 'Student',
          cells: cells,
        );
      }).toList(),
    );
  }

  static String _markText(TestSessionMark? mark, double maxMarks) {
    if (mark == null) return '—';
    if (mark.absent) return 'A';
    final value = mark.marks;
    if (value == null) return '—';
    return '${_number(value)}/${_number(maxMarks)}';
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
