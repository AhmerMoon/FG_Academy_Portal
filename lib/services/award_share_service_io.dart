import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fee_models.dart';
import '../models/portal_user.dart';
import '../utils/award_list_image_generator.dart';

class PreparedAwardShare {
  final Uint8List pngBytes;
  final String fileName;
  final String shareText;

  const PreparedAwardShare({
    required this.pngBytes,
    required this.fileName,
    required this.shareText,
  });
}

class AwardShareService {
  Future<PreparedAwardShare> prepareAwardList({
    required SupabaseClient supabase,
    required PortalUser? user,
    required Map<String, dynamic> batch,
    required Map<String, dynamic> test,
    required String subjectCode,
  }) async {
    final batchId = batch['id'].toString();

    final testId = test['id'].toString();

    final results = await Future.wait<dynamic>([
      supabase
          .from('students')
          .select('id, name, stream')
          .eq('batch_id', batchId)
          .order('name', ascending: true),

      supabase
          .from('award_marks')
          .select(
            'student_id, '
            'marks, '
            'is_absent',
          )
          .eq('test_id', testId),
    ]);

    final rawStudents = results[0] as List;

    final rawMarks = results[1] as List;

    final marksByStudent = <String, double>{};

    final absentByStudent = <String, bool>{};

    for (final raw in rawMarks) {
      final row = Map<String, dynamic>.from(raw);

      final studentId = row['student_id']?.toString();

      if (studentId == null) {
        continue;
      }

      final isAbsent = row['is_absent'] == true;

      absentByStudent[studentId] = isAbsent;

      final marks = (row['marks'] as num?)?.toDouble();

      if (marks != null) {
        marksByStudent[studentId] = marks;
      }
    }

    final students = <AwardListShareStudent>[];

    var serialNo = 1;

    for (final raw in rawStudents) {
      final row = Map<String, dynamic>.from(raw);

      final studentId = row['id'].toString();

      final studentName = row['name']?.toString() ?? 'Student';

      final rawStream = row['stream'];

      final stream = rawStream is List
          ? rawStream.map((item) => item.toString()).toList()
          : <String>[];

      if (!stream.contains(subjectCode)) {
        continue;
      }

      students.add(
        AwardListShareStudent(
          serialNo: serialNo,
          name: studentName,
          marks: marksByStudent[studentId],
          isAbsent: absentByStudent[studentId] ?? false,
        ),
      );

      serialNo++;
    }

    if (students.isEmpty) {
      throw StateError(
        'No students were found '
        'for this award list.',
      );
    }

    final testNo = (test['test_no'] as num?)?.toInt() ?? 0;

    final maxMarks = (test['max_marks'] as num?)?.toDouble() ?? 0;

    final testDate = DateTime.tryParse(test['test_date']?.toString() ?? '');

    final teacherName = user?.fullName.trim();

    final data = AwardListShareData(
      academyName: 'FGEIs ECC Wah',
      batchName: batch['name']?.toString() ?? 'Batch',
      subjectName: feeSubjectLabel(subjectCode),
      testLabel: 'T$testNo',
      testDate: testDate,
      maxMarks: maxMarks,
      preparedBy: teacherName != null && teacherName.isNotEmpty
          ? teacherName
          : 'FG Academy',
      students: students,
    );

    final pngBytes = await AwardListImageGenerator.generate(data);

    final fileName =
        'FG_Award_'
        '${_safeFileName(data.batchName)}_'
        '${_safeFileName(subjectCode)}_'
        'T$testNo.png';

    final shareText =
        'Award List\n'
        '${data.batchName} • '
        '${data.subjectName} • '
        '${data.testLabel}';

    return PreparedAwardShare(
      pngBytes: pngBytes,
      fileName: fileName,
      shareText: shareText,
    );
  }

  Future<void> sharePreparedAwardList(PreparedAwardShare prepared) async {
    final tempDirectory = await getTemporaryDirectory();

    final file = File(
      '${tempDirectory.path}/'
      '${prepared.fileName}',
    );

    await file.writeAsBytes(prepared.pngBytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: prepared.shareText,
        subject: prepared.shareText,
      ),
    );
  }

  Future<void> shareAwardList({
    required SupabaseClient supabase,
    required PortalUser? user,
    required Map<String, dynamic> batch,
    required Map<String, dynamic> test,
    required String subjectCode,
  }) async {
    final prepared = await prepareAwardList(
      supabase: supabase,
      user: user,
      batch: batch,
      test: test,
      subjectCode: subjectCode,
    );

    await sharePreparedAwardList(prepared);
  }

  String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return cleaned.isEmpty ? 'award' : cleaned;
  }
}
