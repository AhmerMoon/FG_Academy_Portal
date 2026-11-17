class TestSessionTest {
  final String id;
  final String batchId;
  final String subjectCode;
  final int testNo;
  final DateTime testDate;
  final double maxMarks;
  final String status;
  final String createdBy;

  const TestSessionTest({
    required this.id,
    required this.batchId,
    required this.subjectCode,
    required this.testNo,
    required this.testDate,
    required this.maxMarks,
    required this.status,
    required this.createdBy,
  });

  bool get finalized => status == 'finalized';

  factory TestSessionTest.fromJson(Map<String, dynamic> json) =>
      TestSessionTest(
        id: json['id'].toString(),
        batchId: json['batch_id'].toString(),
        subjectCode: json['subject_code'].toString(),
        testNo: (json['test_no'] as num?)?.toInt() ?? 0,
        testDate:
            DateTime.tryParse(json['test_date']?.toString() ?? '') ??
            DateTime.now(),
        maxMarks: (json['max_marks'] as num?)?.toDouble() ?? 0,
        status: json['status']?.toString() ?? 'draft',
        createdBy: json['created_by']?.toString() ?? '',
      );
}

class TestSessionMark {
  final double? marks;
  final bool absent;

  const TestSessionMark({this.marks, this.absent = false});

  factory TestSessionMark.fromJson(Map<String, dynamic> json) =>
      TestSessionMark(
        marks: (json['marks'] as num?)?.toDouble(),
        absent: json['is_absent'] == true,
      );
}

class TestSessionReportColumn {
  final String key;
  final String label;
  final List<String> subjectCodes;
  final double? maxMarks;

  const TestSessionReportColumn({
    required this.key,
    required this.label,
    required this.subjectCodes,
    this.maxMarks,
  });
}

class TestSessionReportRow {
  final String name;
  final Map<String, String> cells;

  const TestSessionReportRow({required this.name, required this.cells});
}

class TestSessionReportData {
  final String batchName;
  final int classLevel;
  final int testNo;
  final String title;
  final bool incomplete;
  final int completedSubjects;
  final int requiredSubjects;
  final List<TestSessionReportColumn> columns;
  final List<TestSessionReportRow> rows;

  const TestSessionReportData({
    required this.batchName,
    required this.classLevel,
    required this.testNo,
    required this.title,
    required this.incomplete,
    required this.completedSubjects,
    required this.requiredSubjects,
    required this.columns,
    required this.rows,
  });
}
