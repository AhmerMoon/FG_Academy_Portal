import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fee_models.dart';
import '../models/portal_user.dart';
import '../models/test_session_models.dart';
import '../utils/award_list_image_generator.dart';
import '../utils/student_group_helper.dart';
import '../utils/test_session_report_generator.dart';
import 'test_session_service.dart';

typedef SessionBackupProgress = void Function(String message);

class SessionBackupResult {
  final Uint8List bytes;
  final String fileName;
  final int activeStudents;
  final int awardReports;
  final int testSessionReports;
  final List<String> warnings;

  const SessionBackupResult({
    required this.bytes,
    required this.fileName,
    required this.activeStudents,
    required this.awardReports,
    required this.testSessionReports,
    required this.warnings,
  });
}

class SessionBackupFile {
  final String path;
  final Uint8List bytes;

  const SessionBackupFile(this.path, this.bytes);

  factory SessionBackupFile.text(String path, String contents) =>
      SessionBackupFile(path, Uint8List.fromList(utf8.encode(contents)));
}

class SessionBackupService {
  final SupabaseClient _client;

  SessionBackupService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _pages(
    Future<List<Map<String, dynamic>>> Function(int start, int end) fetch,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await fetch(offset, offset + 499);
      rows.addAll(page);
      if (page.length < 500) return rows;
    }
  }

  Future<List<Map<String, dynamic>>> _table(String name) => _pages(
    (start, end) async => (await _client.from(name).select().range(start, end))
        .map((row) => Map<String, dynamic>.from(row))
        .toList(),
  );

  Future<SessionBackupResult> create({
    required PortalUser? preparedBy,
    SessionBackupProgress? onProgress,
  }) async {
    onProgress?.call('Reading session records from Supabase...');
    final responses = await Future.wait<List<Map<String, dynamic>>>([
      _table('batches'),
      _table('students'),
      _table('attendance'),
      _table('award_tests'),
      _table('award_marks'),
      _table('test_session_tests'),
      _table('test_session_marks'),
    ]);
    final tables = <String, List<Map<String, dynamic>>>{
      'batches': responses[0],
      'students': responses[1],
      'attendance': responses[2],
      'award_tests': responses[3],
      'award_marks': responses[4],
      'test_session_tests': responses[5],
      'test_session_marks': responses[6],
    };
    final batches = {
      for (final row in tables['batches']!) row['id'].toString(): row,
    };
    final files = <SessionBackupFile>[];
    final warnings = <String>[];

    onProgress?.call('Generating Award List reports...');
    var awardReportCount = 0;
    for (final test in tables['award_tests']!) {
      try {
        final batch = batches[test['batch_id'].toString()];
        if (batch == null) throw StateError('Batch not found');
        final file = await _awardReport(
          batch: batch,
          test: test,
          students: tables['students']!,
          marks: tables['award_marks']!,
          preparedBy: preparedBy,
        );
        files.add(file);
        awardReportCount++;
      } catch (error) {
        warnings.add('Award test ${test['id'] ?? 'unknown'} report: $error');
      }
    }

    onProgress?.call('Generating Test Session reports...');
    var testSessionReportCount = 0;
    final testService = TestSessionService(client: _client);
    final rounds = <String>{};
    for (final row in tables['test_session_tests']!) {
      try {
        final test = TestSessionTest.fromJson(row);
        final batch = batches[test.batchId];
        if (batch == null) throw StateError('Batch not found');
        final data = await testService.subjectReport(batch: batch, test: test);
        final png = await TestSessionReportGenerator.generate(data);
        final batchName = _safe(batch['name']?.toString() ?? 'Batch');
        final subject = _safe(studentSubjectLabel(test.subjectCode));
        files.add(
          SessionBackupFile(
            'Reports/Test Session/$batchName/Test ${test.testNo}/'
            '$subject.png',
            png,
          ),
        );
        testSessionReportCount++;
        rounds.add('${test.batchId}|${test.testNo}');
      } catch (error) {
        warnings.add(
          'Test Session test ${row['id'] ?? 'unknown'} report: $error',
        );
      }
    }
    for (final round in rounds) {
      final parts = round.split('|');
      final batch = batches[parts[0]];
      final testNo = int.tryParse(parts[1]);
      if (batch == null || testNo == null) continue;
      try {
        final data = await testService.combinedReport(
          batch: batch,
          testNo: testNo,
        );
        final png = await TestSessionReportGenerator.generate(data);
        final batchName = _safe(batch['name']?.toString() ?? 'Batch');
        files.add(
          SessionBackupFile(
            'Reports/Test Session/$batchName/Test $testNo/'
            'Combined Class Report.png',
            png,
          ),
        );
        testSessionReportCount++;
      } catch (error) {
        warnings.add(
          'Test Session combined ${batch['name']} Test $testNo: $error',
        );
      }
    }

    onProgress?.call('Packing data and reports into ZIP...');
    final now = DateTime.now();
    final activeStudents = tables['students']!
        .where((row) => row['is_archived'] != true)
        .toList();
    final archivedStudents = tables['students']!
        .where((row) => row['is_archived'] == true)
        .toList();
    final metadata = <String, dynamic>{
      'created_at': now.toIso8601String(),
      'prepared_by': preparedBy?.fullName ?? 'Admin',
      'scope': 'Pre-session-end snapshot',
      'counts': {
        for (final entry in tables.entries) entry.key: entry.value.length,
      },
      'generated_reports': {
        'award_list_png': awardReportCount,
        'test_session_png': testSessionReportCount,
      },
      'report_warnings': warnings,
    };
    files.addAll([
      SessionBackupFile.text(
        'README.txt',
        _readme(
          metadata: metadata,
          activeStudents: activeStudents.length,
          archivedStudents: archivedStudents.length,
          attendanceRows: tables['attendance']!.length,
          warnings: warnings,
        ),
      ),
      SessionBackupFile.text(
        'Data/metadata.json',
        const JsonEncoder.withIndent('  ').convert(metadata),
      ),
      SessionBackupFile.text(
        'Data/session_data.json',
        const JsonEncoder.withIndent('  ').convert(tables),
      ),
      SessionBackupFile.text('Data/batches.csv', _csv(tables['batches']!)),
      SessionBackupFile.text('Data/students_active.csv', _csv(activeStudents)),
      SessionBackupFile.text(
        'Data/students_archived.csv',
        _csv(archivedStudents),
      ),
      SessionBackupFile.text(
        'Data/attendance_available.csv',
        _csv(tables['attendance']!),
      ),
      SessionBackupFile.text(
        'Data/award_tests.csv',
        _csv(tables['award_tests']!),
      ),
      SessionBackupFile.text(
        'Data/award_marks.csv',
        _csv(tables['award_marks']!),
      ),
      SessionBackupFile.text(
        'Data/test_session_tests.csv',
        _csv(tables['test_session_tests']!),
      ),
      SessionBackupFile.text(
        'Data/test_session_marks.csv',
        _csv(tables['test_session_marks']!),
      ),
    ]);
    if (warnings.isNotEmpty) {
      files.add(
        SessionBackupFile.text(
          'Report generation warnings.txt',
          warnings.join('\r\n'),
        ),
      );
    }
    final bytes = buildSessionBackupZip(files);
    final stamp = DateFormat('yyyy-MM-dd_HH-mm').format(now);
    return SessionBackupResult(
      bytes: bytes,
      fileName: 'FG_Academy_Session_Backup_$stamp.zip',
      activeStudents: activeStudents.length,
      awardReports: awardReportCount,
      testSessionReports: testSessionReportCount,
      warnings: warnings,
    );
  }

  Future<SessionBackupFile> _awardReport({
    required Map<String, dynamic> batch,
    required Map<String, dynamic> test,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> marks,
    required PortalUser? preparedBy,
  }) async {
    final batchId = batch['id'].toString();
    final testId = test['id'].toString();
    final subjectCode = test['subject_code'].toString();
    final markByStudent = <String, Map<String, dynamic>>{
      for (final row in marks.where(
        (row) => row['test_id'].toString() == testId,
      ))
        row['student_id'].toString(): row,
    };
    final eligible =
        students.where((student) {
          final stream = (student['stream'] as List? ?? const []).map(
            (value) => value.toString(),
          );
          return student['is_archived'] != true &&
              student['batch_id'].toString() == batchId &&
              stream.contains(subjectCode);
        }).toList()..sort(
          (a, b) => (a['name']?.toString() ?? '').toLowerCase().compareTo(
            (b['name']?.toString() ?? '').toLowerCase(),
          ),
        );
    if (eligible.isEmpty) throw StateError('No active eligible students');
    final data = AwardListShareData(
      academyName: 'FGEIs ECC Wah',
      batchName: batch['name']?.toString() ?? 'Batch',
      subjectName: feeSubjectLabel(subjectCode),
      testLabel: 'T${(test['test_no'] as num?)?.toInt() ?? 0}',
      testDate: DateTime.tryParse(test['test_date']?.toString() ?? ''),
      maxMarks: (test['max_marks'] as num?)?.toDouble() ?? 0,
      preparedBy: preparedBy?.fullName.trim().isNotEmpty == true
          ? preparedBy!.fullName.trim()
          : 'FG Academy',
      students: [
        for (var index = 0; index < eligible.length; index++)
          AwardListShareStudent(
            serialNo: index + 1,
            name: eligible[index]['name']?.toString() ?? 'Student',
            marks:
                (markByStudent[eligible[index]['id'].toString()]?['marks']
                        as num?)
                    ?.toDouble(),
            isAbsent:
                markByStudent[eligible[index]['id'].toString()]?['is_absent'] ==
                true,
          ),
      ],
    );
    final png = await AwardListImageGenerator.generate(data);
    final testNo = (test['test_no'] as num?)?.toInt() ?? 0;
    final date = test['test_date']?.toString() ?? 'No date';
    return SessionBackupFile(
      'Reports/Award Lists/${_safe(data.batchName)}/'
      '${_safe(data.subjectName)}/T$testNo - ${_safe(date)}.png',
      png,
    );
  }

  static String _safe(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return safe.isEmpty ? 'Unknown' : safe;
  }

  static String _csv(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '\uFEFF';
    final columns = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (!columns.contains(key)) columns.add(key);
      }
    }
    String cell(dynamic value) {
      final text = value is List || value is Map
          ? jsonEncode(value)
          : value?.toString() ?? '';
      return '"${text.replaceAll('"', '""')}"';
    }

    final lines = <String>[
      columns.map(cell).join(','),
      ...rows.map((row) => columns.map((key) => cell(row[key])).join(',')),
    ];
    return '\uFEFF${lines.join('\r\n')}';
  }

  static String _readme({
    required Map<String, dynamic> metadata,
    required int activeStudents,
    required int archivedStudents,
    required int attendanceRows,
    required List<String> warnings,
  }) =>
      'FG ACADEMY - PRE-SESSION-END BACKUP\r\n'
      'Created: ${metadata['created_at']}\r\n'
      'Prepared by: ${metadata['prepared_by']}\r\n\r\n'
      'CONTENTS\r\n'
      '- $activeStudents active students and $archivedStudents already archived students\r\n'
      '- Award List raw records and one PNG per test\r\n'
      '- Test Session raw records, subject PNGs and combined class PNGs\r\n'
      '- $attendanceRows attendance rows currently still available in Supabase\r\n'
      '- CSV files for Excel and a complete JSON snapshot for recovery/audit\r\n\r\n'
      'IMPORTANT ATTENDANCE NOTE\r\n'
      'Attendance deleted during earlier monthly cleanup is no longer in Supabase '
      'and therefore cannot be included here. Keep the monthly PDFs you already archive.\r\n\r\n'
      'REPORT WARNINGS: ${warnings.length}\r\n'
      '${warnings.isEmpty ? 'None' : 'See Report generation warnings.txt'}\r\n';
}

Uint8List buildSessionBackupZip(List<SessionBackupFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.add(ArchiveFile.bytes(file.path, file.bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
