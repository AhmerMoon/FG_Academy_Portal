import 'package:academy_portal/models/test_session_models.dart';
import 'package:academy_portal/utils/test_session_report_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('combined Test Session report generates a valid PNG', () async {
    const data = TestSessionReportData(
      batchName: '11th Boys',
      classLevel: 11,
      testNo: 1,
      title: 'Combined Class Report',
      incomplete: true,
      completedSubjects: 4,
      requiredSubjects: 6,
      columns: [
        TestSessionReportColumn(
          key: 'Phy',
          label: 'Physics',
          subjectCodes: ['Phy'],
          maxMarks: 40,
        ),
        TestSessionReportColumn(
          key: 'elective',
          label: 'Computer / Biology',
          subjectCodes: ['Comp', 'Bio'],
        ),
      ],
      rows: [
        TestSessionReportRow(
          name: 'Ali Ahmed',
          cells: {'Phy': '32/40', 'elective': 'C: 30/40'},
        ),
        TestSessionReportRow(
          name: 'Hamza Khan',
          cells: {'Phy': 'A', 'elective': 'B: 35/40'},
        ),
      ],
    );

    final bytes = await TestSessionReportGenerator.generate(data);
    expect(bytes.length, greaterThan(1000));
    expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
