import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fee_models.dart';
import '../models/portal_user.dart';

class AwardProgressTest {
  final String id;
  final int testNo;
  final DateTime? testDate;
  final double maxMarks;

  const AwardProgressTest({
    required this.id,
    required this.testNo,
    required this.testDate,
    required this.maxMarks,
  });

  String get label => 'T$testNo';
}

class AwardProgressResult {
  final double? marks;
  final bool isAbsent;

  const AwardProgressResult({required this.marks, required this.isAbsent});
}

class AwardProgressStudent {
  final String id;
  final String name;

  final Map<String, AwardProgressResult> results;

  const AwardProgressStudent({
    required this.id,
    required this.name,
    required this.results,
  });
}

class AwardProgressBundle {
  final String batchName;
  final String subjectCode;
  final String subjectName;
  final String preparedBy;

  final List<AwardProgressTest> tests;

  final List<AwardProgressStudent> students;

  const AwardProgressBundle({
    required this.batchName,
    required this.subjectCode,
    required this.subjectName,
    required this.preparedBy,
    required this.tests,
    required this.students,
  });
}

class AwardProgressService {
  Future<AwardProgressBundle> load({
    required SupabaseClient supabase,
    required PortalUser? user,
    required Map<String, dynamic> batch,
    required String subjectCode,
    required List<Map<String, dynamic>> tests,
  }) async {
    if (tests.isEmpty) {
      throw StateError('No tests are available.');
    }

    final parsedTests = tests.map((test) {
      return AwardProgressTest(
        id: test['id'].toString(),
        testNo: (test['test_no'] as num?)?.toInt() ?? 0,
        testDate: DateTime.tryParse(test['test_date']?.toString() ?? ''),
        maxMarks: (test['max_marks'] as num?)?.toDouble() ?? 0,
      );
    }).toList()..sort((a, b) => a.testNo.compareTo(b.testNo));

    final testIds = parsedTests.map((test) => test.id).toList();

    final batchId = batch['id'].toString();

    final results = await Future.wait<dynamic>([
      supabase
          .from('students')
          .select('id, name, stream')
          .eq('batch_id', batchId)
          .order('name', ascending: true),

      supabase
          .from('award_marks')
          .select(
            'test_id, '
            'student_id, '
            'marks, '
            'is_absent',
          )
          .inFilter('test_id', testIds),
    ]);

    final rawStudents = results[0] as List;

    final rawMarks = results[1] as List;

    final resultsByStudent = <String, Map<String, AwardProgressResult>>{};

    for (final raw in rawMarks) {
      final row = Map<String, dynamic>.from(raw);

      final studentId = row['student_id']?.toString();

      final testId = row['test_id']?.toString();

      if (studentId == null || testId == null) {
        continue;
      }

      resultsByStudent.putIfAbsent(
        studentId,
        () => {},
      )[testId] = AwardProgressResult(
        marks: (row['marks'] as num?)?.toDouble(),
        isAbsent: row['is_absent'] == true,
      );
    }

    final students = <AwardProgressStudent>[];

    for (final raw in rawStudents) {
      final row = Map<String, dynamic>.from(raw);

      final stream = row['stream'] is List
          ? (row['stream'] as List).map((item) => item.toString()).toList()
          : <String>[];

      if (!stream.contains(subjectCode)) {
        continue;
      }

      final id = row['id'].toString();

      students.add(
        AwardProgressStudent(
          id: id,
          name: row['name']?.toString() ?? 'Student',
          results: resultsByStudent[id] ?? const {},
        ),
      );
    }

    students.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final teacherName = user?.fullName.trim();

    return AwardProgressBundle(
      batchName: batch['name']?.toString() ?? 'Batch',
      subjectCode: subjectCode,
      subjectName: feeSubjectLabel(subjectCode),
      preparedBy: teacherName != null && teacherName.isNotEmpty
          ? teacherName
          : 'FG Academy',
      tests: parsedTests,
      students: students,
    );
  }
}
