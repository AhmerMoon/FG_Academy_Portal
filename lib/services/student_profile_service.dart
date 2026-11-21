import 'package:supabase_flutter/supabase_flutter.dart';

DateTime studentProfileToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5));
  return DateTime(now.year, now.month, now.day);
}

class StudentTestResult {
  final Map<String, dynamic> test;
  final double? marks;
  final bool absent;

  const StudentTestResult({
    required this.test,
    this.marks,
    this.absent = false,
  });
  String get subject => test['subject_code'].toString();
  bool get pending => marks == null && !absent;
  double get maximum => (test['max_marks'] as num?)?.toDouble() ?? 0;
  double get obtained => absent ? 0 : marks ?? 0;
}

class StudentResultTotals {
  final List<StudentTestResult> results;
  const StudentResultTotals(this.results);
  Iterable<StudentTestResult> get included =>
      results.where((r) => !r.pending && !r.absent && r.maximum > 0);
  int get graded => included.length;
  int get absent => results.where((r) => r.absent).length;
  int get pending => results.where((r) => r.pending).length;
  double get maximum => included.fold(0.0, (sum, r) => sum + r.maximum);
  double get obtained => included.fold(0.0, (sum, r) => sum + r.obtained);
  double? get percentage => maximum > 0 ? obtained * 100 / maximum : null;
}

class StudentProfileData {
  final Map<String, dynamic> student;
  final Map<String, dynamic> batch;
  final List<Map<String, dynamic>> attendance;
  final List<StudentTestResult> results;
  final bool canEditContact;

  const StudentProfileData({
    required this.student,
    required this.batch,
    required this.attendance,
    required this.results,
    required this.canEditContact,
  });

  List<String> get subjects => {
    ...((student['stream'] as List?) ?? []).map((s) => s.toString()),
    ...results.map((r) => r.subject),
  }.toList()..sort();

  List<Map<String, dynamic>> attendanceFor(DateTime month) => attendance.where((
    row,
  ) {
    final date = DateTime.tryParse(row['date'].toString());
    return date != null && date.year == month.year && date.month == month.month;
  }).toList();
}

class StudentProfileService {
  final SupabaseClient _client;
  StudentProfileService({SupabaseClient? client})
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

  Future<StudentProfileData> load(String studentId) async {
    // '*' keeps contact_number optional until its additive SQL has been run.
    final student = await _client
        .from('students')
        .select()
        .eq('id', studentId)
        .maybeSingle();
    if (student == null) {
      throw StateError('Student not found or access is unavailable.');
    }
    final batchId = student['batch_id'].toString();
    final userId = _client.auth.currentUser?.id;
    final profile = userId == null
        ? null
        : await _client
              .from('user_profiles')
              .select('role,is_active')
              .eq('user_id', userId)
              .maybeSingle();
    final today = studentProfileToday();
    final monthStart = DateTime(
      today.year,
      today.month,
    ).toIso8601String().split('T').first;
    final nextMonth = DateTime(
      today.year,
      today.month + 1,
    ).toIso8601String().split('T').first;

    final responses = await Future.wait<dynamic>([
      _client.from('batches').select().eq('id', batchId).maybeSingle(),
      _pages(
        (start, end) async => await _client
            .from('attendance')
            .select('id,date,status,batch_id')
            .eq('student_id', studentId)
            .gte('date', monthStart)
            .lt('date', nextMonth)
            .order('date')
            .order('id')
            .range(start, end),
      ),
      _pages(
        (start, end) async => await _client
            .from('award_marks')
            .select(
              'id,test_id,marks,is_absent,award_tests(id,batch_id,subject_code,test_no,test_date,max_marks)',
            )
            .eq('student_id', studentId)
            .order('id')
            .range(start, end),
      ),
      _pages(
        (start, end) async => await _client
            .from('award_tests')
            .select('id,batch_id,subject_code,test_no,test_date,max_marks')
            .eq('batch_id', batchId)
            .order('id')
            .range(start, end),
      ),
    ]);
    final marks = responses[2] as List<Map<String, dynamic>>;
    final tests = <String, Map<String, dynamic>>{};
    final subjects = ((student['stream'] as List?) ?? [])
        .map((s) => s.toString())
        .toSet();
    final created = DateTime.tryParse(
      student['created_at']?.toString() ?? '',
    )?.toUtc().add(const Duration(hours: 5));
    final joined = created == null
        ? null
        : DateTime(created.year, created.month, created.day);
    for (final test in responses[3] as List<Map<String, dynamic>>) {
      final date = DateTime.tryParse(test['test_date'].toString());
      if (subjects.contains(test['subject_code']) &&
          (joined == null || date == null || !date.isBefore(joined))) {
        tests[test['id'].toString()] = test;
      }
    }
    final marksByTest = <String, Map<String, dynamic>>{};
    for (final row in marks) {
      final test = row['award_tests'];
      // Preserve recorded results from any previous batch as well.
      if (test is Map) {
        tests[row['test_id'].toString()] = Map<String, dynamic>.from(test);
      }
      marksByTest[row['test_id'].toString()] = row;
    }
    final results =
        tests.entries.map((entry) {
          final mark = marksByTest[entry.key];
          return StudentTestResult(
            test: entry.value,
            marks: (mark?['marks'] as num?)?.toDouble(),
            absent: mark?['is_absent'] == true,
          );
        }).toList()..sort((a, b) {
          final date = b.test['test_date'].toString().compareTo(
            a.test['test_date'].toString(),
          );
          return date != 0 ? date : a.subject.compareTo(b.subject);
        });
    return StudentProfileData(
      student: student,
      batch: (responses[0] as Map<String, dynamic>?) ?? {},
      attendance: responses[1] as List<Map<String, dynamic>>,
      results: results,
      canEditContact:
          profile?['role'] == 'admin' && profile?['is_active'] == true,
    );
  }

  Future<void> saveContact(String studentId, String? contact) async {
    await _client.rpc(
      'admin_set_student_contact',
      params: {'p_student_id': studentId, 'p_contact': contact},
    );
  }

  Future<List<Map<String, dynamic>>> fetchBatches() async => await _client
      .from('batches')
      .select('id,name,class_level')
      .order('class_level')
      .order('name');

  Future<void> saveProfile({
    required String studentId,
    required String name,
    required String batchId,
    required String status,
    required List<String> subjects,
    required String? contact,
  }) async {
    await _client.rpc(
      'admin_save_student_profile',
      params: {
        'p_student_id': studentId,
        'p_name': name,
        'p_batch_id': batchId,
        'p_status': status,
        'p_stream': subjects,
        'p_contact': contact,
      },
    );
  }
}
