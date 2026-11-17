class AttendanceReportRow {
  final String studentId;
  final String studentName;
  final Map<int, String> statusByDay;

  const AttendanceReportRow({
    required this.studentId,
    required this.studentName,
    required this.statusByDay,
  });
}

class AttendanceReportData {
  final String batchId;
  final String batchName;
  final DateTime month;
  final List<int> attendanceDays;
  final List<AttendanceReportRow> rows;

  const AttendanceReportData({
    required this.batchId,
    required this.batchName,
    required this.month,
    required this.attendanceDays,
    required this.rows,
  });
}
