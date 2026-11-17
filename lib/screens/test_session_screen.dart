import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/portal_user.dart';
import '../models/test_session_models.dart';
import '../services/auth_service.dart';
import '../services/test_session_service.dart';
import '../utils/dashboard_section_header.dart';
import '../utils/error_state_view.dart';
import '../utils/student_group_helper.dart';
import '../utils/test_session_report_generator.dart';
import 'test_session_report_preview_screen.dart';

class TestSessionScreen extends StatefulWidget {
  final String userRole;

  const TestSessionScreen({super.key, required this.userRole});

  @override
  State<TestSessionScreen> createState() => _TestSessionScreenState();
}

class _TestSessionScreenState extends State<TestSessionScreen> {
  final TestSessionService _service = TestSessionService();
  final AuthService _auth = AuthService();
  final TextEditingController _search = TextEditingController();
  final Map<String, TextEditingController> _markControllers = {};

  PortalUser? _user;
  List<Map<String, dynamic>> _batches = [];
  List<TestSessionTest> _tests = [];
  List<Map<String, dynamic>> _students = [];
  Map<String, TestSessionMark> _marks = {};
  Map<String, TestSessionTest> _roundTests = {};
  Set<String> _requiredRoundSubjects = {};
  String? _batchId;
  String? _subject;
  String? _testId;
  String? _editingStudentId;
  String _filter = 'All';
  String _query = '';
  bool _loading = true;
  bool _loadingTest = false;
  bool _creating = false;
  bool _finalizing = false;
  bool _reporting = false;
  final Set<String> _saving = {};
  String? _error;

  bool get _isAdmin => _user?.isAdmin ?? widget.userRole == 'admin';

  Map<String, dynamic>? get _batch {
    for (final value in _batches) {
      if (value['id'].toString() == _batchId) return value;
    }
    return null;
  }

  TestSessionTest? get _test {
    for (final value in _tests) {
      if (value.id == _testId) return value;
    }
    return null;
  }

  int get _classLevel => (_batch?['class_level'] as num?)?.toInt() ?? 0;

  List<String> get _availableSubjects {
    final all = studentSubjectCodesForClass(_classLevel);
    final user = _user;
    if (user == null || user.isAdmin) return all;
    final allowed = user.assignments
        .where((assignment) => assignment.classLevel == _classLevel)
        .map((assignment) => assignment.subjectCode)
        .toSet();
    return all.where(allowed.contains).toList();
  }

  List<Map<String, dynamic>> get _visibleStudents {
    final query = _query.trim().toLowerCase();
    return _students.where((student) {
      final id = student['id'].toString();
      final mark = _marks[id];
      final matchesFilter = switch (_filter) {
        'Remaining' => mark == null,
        'Entered' => mark != null && !mark.absent,
        'Absent' => mark?.absent == true,
        _ => true,
      };
      if (!matchesFilter) return false;
      return query.isEmpty ||
          (student['name']?.toString().toLowerCase() ?? '').contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    for (final controller in _markControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final responses = await Future.wait<dynamic>([
        _auth.loadCurrentUser(),
        _service.fetchBatches(),
      ]);
      final user = responses[0] as PortalUser?;
      var batches = responses[1] as List<Map<String, dynamic>>;
      if (user == null) throw StateError('Portal profile unavailable.');
      if (!user.isAdmin) {
        final levels = user.classLevels.toSet();
        batches = batches
            .where(
              (batch) =>
                  levels.contains((batch['class_level'] as num?)?.toInt()),
            )
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _user = user;
        _batches = batches;
        _batchId = batches.isEmpty ? null : batches.first['id'].toString();
        _loading = false;
      });
      _resetSubject();
      await _loadTests();
    } catch (error) {
      debugPrint('Test Session bootstrap: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load Test Session.';
        });
      }
    }
  }

  void _resetSubject() {
    final values = _availableSubjects;
    _subject = values.contains(_subject)
        ? _subject
        : values.isEmpty
        ? null
        : values.first;
  }

  Future<void> _changeBatch(String id) async {
    setState(() {
      _batchId = id;
      _testId = null;
      _tests = [];
      _students = [];
      _marks = {};
      _editingStudentId = null;
      _resetSubject();
    });
    await _loadTests();
  }

  Future<void> _changeSubject(String code) async {
    setState(() {
      _subject = code;
      _testId = null;
      _tests = [];
      _students = [];
      _marks = {};
      _editingStudentId = null;
    });
    await _loadTests();
  }

  Future<void> _loadTests({String? selectId}) async {
    final batchId = _batchId;
    final subject = _subject;
    if (batchId == null || subject == null) return;
    setState(() => _loadingTest = true);
    try {
      final tests = await _service.fetchTests(
        batchId: batchId,
        subjectCode: subject,
      );
      var selected = selectId ?? _testId;
      if (!tests.any((test) => test.id == selected)) {
        selected = tests.isEmpty ? null : tests.first.id;
      }
      if (!mounted) return;
      setState(() {
        _tests = tests;
        _testId = selected;
      });
      await _loadRoster();
    } catch (error) {
      if (mounted) _message(_friendly(error), error: true);
    } finally {
      if (mounted) setState(() => _loadingTest = false);
    }
  }

  Future<void> _loadRoster() async {
    final test = _test;
    if (test == null) {
      setState(() {
        _students = [];
        _marks = {};
        _roundTests = {};
        _requiredRoundSubjects = {};
      });
      return;
    }
    final responses = await Future.wait<dynamic>([
      _service.fetchEligibleStudents(
        batchId: test.batchId,
        subjectCode: test.subjectCode,
        testDate: test.testDate,
      ),
      _service.fetchMarks(test.id),
      if (_isAdmin)
        _service.fetchRoundStatus(batchId: test.batchId, testNo: test.testNo),
    ]);
    if (!mounted) return;
    setState(() {
      _students = responses[0] as List<Map<String, dynamic>>;
      _marks = responses[1] as Map<String, TestSessionMark>;
      if (_isAdmin) {
        final round =
            responses[2]
                as ({Set<String> required, Map<String, TestSessionTest> tests});
        _requiredRoundSubjects = round.required;
        _roundTests = round.tests;
      }
      _editingStudentId = null;
    });
  }

  Future<void> _createTest() async {
    final batchId = _batchId;
    final subject = _subject;
    if (batchId == null || subject == null) return;
    final no = TextEditingController(
      text:
          '${_tests.isEmpty ? 1 : _tests.map((test) => test.testNo).reduce((a, b) => a > b ? a : b) + 1}',
    );
    final total = TextEditingController(text: '40');
    var date = DateTime.now();
    String? dialogError;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Start Test Session Test'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: no,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Test / Week Number',
                    prefixIcon: Icon(Icons.numbers_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: total,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Total Marks',
                    prefixIcon: Icon(Icons.score_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Test Date'),
                  subtitle: Text(DateFormat('dd MMM yyyy').format(date)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: date,
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) update(() => date = picked);
                  },
                ),
                if (dialogError != null)
                  Text(
                    dialogError!,
                    style: const TextStyle(color: AppTheme.danger),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final number = int.tryParse(no.text);
                final max = double.tryParse(total.text);
                if (number == null || number < 1 || number > 99) {
                  update(() => dialogError = 'Enter Test Number from 1 to 99.');
                  return;
                }
                if (max == null || max <= 0 || max > 1000) {
                  update(() => dialogError = 'Enter valid total marks.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Start Draft'),
            ),
          ],
        ),
      ),
    );
    final confirmed = await Navigator.of(context).push(route);
    await route.completed;
    final testNo = int.tryParse(no.text);
    final maxMarks = double.tryParse(total.text);
    no.dispose();
    total.dispose();
    if (confirmed != true || testNo == null || maxMarks == null || !mounted) {
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await _service.createTest(
        batchId: batchId,
        subjectCode: subject,
        testNo: testNo,
        testDate: date,
        maxMarks: maxMarks,
      );
      await _loadTests(selectId: id);
      if (mounted) _message('Test $testNo draft ready.');
    } catch (error) {
      if (mounted) _message(_friendly(error), error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openMark(Map<String, dynamic> student) {
    if (_test?.finalized == true) return;
    final id = student['id'].toString();
    final mark = _marks[id];
    final controller = _markControllers.putIfAbsent(
      id,
      () => TextEditingController(),
    );
    controller.text = mark?.marks == null ? '' : _number(mark!.marks!);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    setState(() => _editingStudentId = _editingStudentId == id ? null : id);
  }

  Future<void> _saveMark(
    Map<String, dynamic> student, {
    bool absent = false,
  }) async {
    final test = _test;
    if (test == null || test.finalized) return;
    final id = student['id'].toString();
    final value = _markControllers[id]?.text.trim() ?? '';
    final marks = absent ? null : double.tryParse(value);
    if (!absent && (marks == null || marks < 0 || marks > test.maxMarks)) {
      _message(
        'Enter marks from 0 to ${_number(test.maxMarks)}, or tap A.',
        error: true,
      );
      return;
    }
    setState(() => _saving.add(id));
    try {
      await _service.saveMark(
        testId: test.id,
        studentId: id,
        marks: marks,
        absent: absent,
      );
      if (!mounted) return;
      setState(() {
        _marks[id] = TestSessionMark(marks: marks, absent: absent);
        _editingStudentId = null;
      });
    } catch (error) {
      if (mounted) _message(_friendly(error), error: true);
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  Future<void> _clearMark(Map<String, dynamic> student) async {
    final test = _test;
    if (test == null || test.finalized) return;
    final id = student['id'].toString();
    setState(() => _saving.add(id));
    try {
      await _service.clearMark(testId: test.id, studentId: id);
      if (mounted) setState(() => _marks.remove(id));
    } catch (error) {
      if (mounted) _message(_friendly(error), error: true);
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  Future<void> _finalize() async {
    final test = _test;
    if (test == null) return;
    final missing = _students.length - _marks.length;
    if (missing > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Finalize Results?'),
          content: Text(
            '$missing unmarked student result(s) will automatically be marked '
            'Absent. Entered numeric marks, including 0, will stay unchanged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Review'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Finalize & Mark Absent'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _finalizing = true);
    try {
      await _service.finalize(test.id);
      await _loadTests(selectId: test.id);
      if (mounted) _message('Subject results finalized.');
    } catch (error) {
      if (mounted) _message(_friendly(error), error: true);
    } finally {
      if (mounted) setState(() => _finalizing = false);
    }
  }

  Future<void> _reopen() async {
    final test = _test;
    if (test == null) return;
    try {
      await _service.reopen(test.id);
      await _loadTests(selectId: test.id);
      if (mounted) _message('Test reopened for correction.');
    } catch (error) {
      if (mounted) _message(_friendly(error), error: true);
    }
  }

  Future<void> _delete() async {
    final test = _test;
    if (test == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Test ${test.testNo}?'),
        content: const Text(
          'This permanently deletes this Test Session test and all its marks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.delete(test.id);
      _testId = null;
      await _loadTests();
      if (mounted) _message('Test deleted.');
    } catch (error) {
      if (mounted) _message(_friendly(error), error: true);
    }
  }

  Future<void> _subjectReport() async {
    final batch = _batch;
    final test = _test;
    if (batch == null || test == null) return;
    await _generateReport(
      () => _service.subjectReport(batch: batch, test: test),
      'Test_${test.testNo}_${test.subjectCode}_${batch['name']}.png',
    );
  }

  Future<void> _combinedReport() async {
    final batch = _batch;
    final test = _test;
    if (batch == null || test == null) {
      _message('Select any subject test for the required Test Number.');
      return;
    }
    await _generateReport(
      () => _service.combinedReport(batch: batch, testNo: test.testNo),
      'Test_${test.testNo}_Combined_${batch['name']}.png',
    );
  }

  Future<void> _generateReport(
    Future<TestSessionReportData> Function() load,
    String fileName,
  ) async {
    setState(() => _reporting = true);
    try {
      final data = await load();
      final bytes = await TestSessionReportGenerator.generate(data);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TestSessionReportPreviewScreen(
            pngBytes: bytes,
            title: '${data.batchName} · Test ${data.testNo}',
            fileName: fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_'),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _message(_friendly(error), error: true);
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  String _friendly(Object error) {
    if (error is PostgrestException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  void _message(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorStateView(message: _error!, onRetry: _bootstrap);
    }
    return Column(
      children: [
        DashboardSectionHeader(
          title: 'Test Session',
          subtitle: _isAdmin
              ? 'Monitor weekly tests and generate class reports'
              : 'Enter and finalize your weekly subject results',
          trailing: IconButton(
            tooltip: 'Refresh',
            color: Colors.white,
            onPressed: _loadingTest ? null : _loadTests,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() => RefreshIndicator(
    onRefresh: _loadTests,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 30),
      children: [
        _filters(),
        const SizedBox(height: 10),
        if (_test == null) _emptyTest() else ...[_summary(), _roster()],
      ],
    ),
  );

  Widget _filters() => Card(
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 720;
          final controls = [
            DropdownButtonFormField<String>(
              initialValue: _batchId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Class',
                prefixIcon: Icon(Icons.groups_outlined),
                isDense: true,
              ),
              items: _batches
                  .map(
                    (batch) => DropdownMenuItem(
                      value: batch['id'].toString(),
                      child: Text(batch['name']?.toString() ?? 'Batch'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) _changeBatch(value);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _subject,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Subject',
                prefixIcon: Icon(Icons.menu_book_outlined),
                isDense: true,
              ),
              items: _availableSubjects
                  .map(
                    (code) => DropdownMenuItem(
                      value: code,
                      child: Text(studentSubjectLabel(code)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) _changeSubject(value);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _testId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Test / Week',
                prefixIcon: Icon(Icons.assignment_outlined),
                isDense: true,
              ),
              items: _tests
                  .map(
                    (test) => DropdownMenuItem(
                      value: test.id,
                      child: Text(
                        'Test ${test.testNo} · ${test.finalized ? 'Final' : 'Draft'}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                setState(() => _testId = value);
                await _loadRoster();
              },
            ),
          ];
          if (narrow) {
            return Column(
              children: [
                for (var i = 0; i < controls.length; i++) ...[
                  controls[i],
                  if (i < controls.length - 1) const SizedBox(height: 9),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _creating ? null : _createTest,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Start New Test'),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              for (final control in controls) ...[
                Expanded(child: control),
                const SizedBox(width: 10),
              ],
              ElevatedButton.icon(
                onPressed: _creating ? null : _createTest,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Test'),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _emptyTest() => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(
            Icons.assignment_add,
            size: 50,
            color: AppTheme.fgNavyBlue,
          ),
          const SizedBox(height: 12),
          const Text(
            'No Test Session test selected',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start a draft to enter marks. Normal Award Lists remain separate.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _summary() {
    final test = _test!;
    final entered = _marks.length;
    final total = _students.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text('Test ${test.testNo}')),
                Chip(
                  label: Text(DateFormat('dd MMM yyyy').format(test.testDate)),
                ),
                Chip(label: Text('Total ${_number(test.maxMarks)}')),
                Chip(
                  avatar: Icon(
                    test.finalized ? Icons.verified_rounded : Icons.edit_note,
                    size: 18,
                  ),
                  label: Text(test.finalized ? 'FINALIZED' : 'DRAFT'),
                ),
                Chip(label: Text('$entered/$total entered')),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: total == 0 ? 0 : entered / total,
              minHeight: 7,
              borderRadius: BorderRadius.circular(10),
            ),
            if (_isAdmin && _requiredRoundSubjects.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Class round completion',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _requiredRoundSubjects.map((code) {
                  final subjectTest = _roundTests[code];
                  final finalized = subjectTest?.finalized == true;
                  final draft = subjectTest != null && !finalized;
                  final color = finalized
                      ? AppTheme.success
                      : draft
                      ? AppTheme.warning
                      : AppTheme.danger;
                  return Chip(
                    avatar: Icon(
                      finalized
                          ? Icons.check_circle_outline
                          : draft
                          ? Icons.edit_note
                          : Icons.pending_outlined,
                      color: color,
                      size: 17,
                    ),
                    label: Text(
                      '${studentSubjectLabel(code)}: ${finalized
                          ? 'Final'
                          : draft
                          ? 'Draft'
                          : 'Pending'}',
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _reporting ? null : _subjectReport,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Subject PNG'),
                ),
                if (_isAdmin)
                  OutlinedButton.icon(
                    onPressed: _reporting ? null : _combinedReport,
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Combined Class PNG'),
                  ),
                if (test.finalized)
                  OutlinedButton.icon(
                    onPressed: _reopen,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Reopen'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _finalizing ? null : _finalize,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Finalize Results'),
                  ),
                OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roster() {
    final visible = _visibleStudents;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search student',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 9),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Remaining', 'Entered', 'Absent']
                    .map(
                      (value) => Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: FilterChip(
                          selected: _filter == value,
                          label: Text(value),
                          onSelected: (_) => setState(() => _filter = value),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const Divider(),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No students match this filter.'),
              ),
            for (var index = 0; index < visible.length; index++)
              _studentRow(visible[index], index),
          ],
        ),
      ),
    );
  }

  Widget _studentRow(Map<String, dynamic> student, int index) {
    final id = student['id'].toString();
    final mark = _marks[id];
    final editing = _editingStudentId == id;
    final saving = _saving.contains(id);
    final locked = _test?.finalized == true;
    final result = mark == null
        ? 'Not entered'
        : mark.absent
        ? 'A'
        : '${_number(mark.marks ?? 0)}/${_number(_test!.maxMarks)}';
    final color = mark == null
        ? AppTheme.textSecondary
        : mark.absent
        ? AppTheme.danger
        : AppTheme.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: editing
            ? AppTheme.fgNavyBlue.withValues(alpha: 0.04)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: editing ? AppTheme.navy500 : AppTheme.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: locked ? null : () => _openMark(student),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 31,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      student['name']?.toString() ?? 'Student',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (saving)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      result,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(width: 5),
                  Icon(
                    locked
                        ? Icons.lock_outline
                        : editing
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (editing)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _markControllers[id],
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Marks',
                        suffixText: '/ ${_number(_test!.maxMarks)}',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saveMark(student),
                    ),
                  ),
                  const SizedBox(width: 7),
                  OutlinedButton(
                    onPressed: saving
                        ? null
                        : () => _saveMark(student, absent: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                    ),
                    child: const Text('A'),
                  ),
                  const SizedBox(width: 7),
                  FilledButton(
                    onPressed: saving ? null : () => _saveMark(student),
                    child: const Icon(Icons.check_rounded),
                  ),
                  if (mark != null)
                    IconButton(
                      tooltip: 'Clear result',
                      onPressed: saving ? null : () => _clearMark(student),
                      color: AppTheme.danger,
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
