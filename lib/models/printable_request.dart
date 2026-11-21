/// All retention dates use Pakistan time, regardless of the device timezone.
DateTime pakistanToday([DateTime? instant]) {
  final now = (instant ?? DateTime.now()).toUtc().add(const Duration(hours: 5));
  return DateTime(now.year, now.month, now.day);
}

DateTime printableExpiry(DateTime testDate) => DateTime.utc(
  testDate.year,
  testDate.month,
  testDate.day + 2,
).subtract(const Duration(hours: 5));

const printableMaxBytes = 20 * 1024 * 1024;
const printableExtensions = ['pdf', 'doc', 'docx'];
const printablePaperNormal = 'normal';
const printablePaperTestSession = 'test_session';

String inferPrintablePaperType(String fileName) {
  final name = fileName.toLowerCase();
  final sessionPattern = RegExp(
    r'(?:test[\s_-]*session)|(?:^|[^a-z])(?:test|week)[\s_-]*(?:no\.?[\s_-]*)?\d+(?:[^0-9]|$)',
  );
  return sessionPattern.hasMatch(name)
      ? printablePaperTestSession
      : printablePaperNormal;
}

int? printableTestNumber(String fileName) {
  final match = RegExp(
    r'(?:^|[^a-z])(?:test|week)[\s_-]*(?:no\.?[\s_-]*)?(\d+)(?:[^0-9]|$)',
    caseSensitive: false,
  ).firstMatch(fileName);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String printableExtension(String name) => name.split('.').last.toLowerCase();

String printableMimeType(String name) {
  switch (printableExtension(name)) {
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    default:
      throw ArgumentError('Choose a PDF or Word (.doc / .docx) file.');
  }
}

String? validatePrintableFile(String name, int size) {
  if (!printableExtensions.contains(printableExtension(name))) {
    return 'Choose a PDF or Word (.doc / .docx) file.';
  }
  if (size <= 0) return 'The selected file is empty.';
  if (size > printableMaxBytes) return 'The file must be 20 MB or smaller.';
  return null;
}

class PrintableRequest {
  final String id;
  final String teacherName;
  final String batchName;
  final String subjectCode;
  final String title;
  final DateTime testDate;
  final int copies;
  final String notes;
  final String fileName;
  final String filePath;
  final String paperType;
  final String status;
  final DateTime expiresAt;

  const PrintableRequest({
    required this.id,
    required this.teacherName,
    required this.batchName,
    required this.subjectCode,
    required this.title,
    required this.testDate,
    required this.copies,
    required this.notes,
    required this.fileName,
    required this.filePath,
    this.paperType = printablePaperNormal,
    required this.status,
    required this.expiresAt,
  });

  bool get isPdf => printableExtension(fileName) == 'pdf';
  bool get isTestSession => paperType == printablePaperTestSession;
  bool get isPrinted => status == 'printed';
  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  factory PrintableRequest.fromJson(Map<String, dynamic> row) =>
      PrintableRequest(
        id: row['id'] as String,
        teacherName: row['teacher_name'] as String,
        batchName: row['batch_name'] as String,
        subjectCode: row['subject_code'] as String,
        title: row['title'] as String,
        testDate: DateTime.parse(row['test_date'] as String),
        copies: (row['copies'] as num).toInt(),
        notes: row['notes'] as String? ?? '',
        fileName: row['file_name'] as String,
        filePath: row['file_path'] as String,
        paperType:
            row['paper_type']?.toString() ??
            inferPrintablePaperType(row['file_name'] as String),
        status: row['status'] as String,
        expiresAt: DateTime.parse(row['expires_at'] as String).toUtc(),
      );
}
