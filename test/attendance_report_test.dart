import 'package:academy_portal/models/attendance_report_models.dart';
import 'package:academy_portal/utils/attendance_report_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = AttendanceReportData(
    batchId: 'batch-1',
    batchName: '9th Boys',
    month: DateTime(2026, 11),
    attendanceDays: const [1, 2, 3, 4, 5],
    rows: const [
      AttendanceReportRow(
        studentId: 'student-1',
        studentName: 'Ali Student',
        statusByDay: {1: 'present', 2: 'absent'},
      ),
      AttendanceReportRow(
        studentId: 'student-2',
        studentName: 'Ahmed Student',
        statusByDay: {1: 'present', 2: 'present'},
      ),
    ],
  );

  test('generates a valid monthly attendance PNG', () async {
    final bytes = await AttendanceReportGenerator.generatePng(report);
    expect(bytes.length, greaterThan(100));
    expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('combines attendance reports into a PDF', () async {
    final png = await AttendanceReportGenerator.generatePng(report);
    final pdf = await AttendanceReportGenerator.generateCombinedPdf([
      MapEntry(report, png),
      MapEntry(report, png),
    ]);
    expect(pdf.length, greaterThan(100));
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });
}
