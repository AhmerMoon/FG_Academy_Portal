import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/fee_models.dart';
import '../models/portal_user.dart';
import '../services/auth_service.dart';
import 'award_list_preview_screen.dart';
import '../utils/dashboard_section_header.dart';
import '../utils/error_state_view.dart';
import '../utils/list_sorting.dart';
import 'award_history_screen.dart';

class AwardListsScreen extends StatefulWidget {
  final String userRole;

  const AwardListsScreen({super.key, required this.userRole});

  @override
  State<AwardListsScreen> createState() => _AwardListsScreenState();
}

class _AwardListsScreenState extends State<AwardListsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();

  PortalUser? _user;

  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _tests = [];
  List<_AwardStudentRow> _students = [];

  final Map<String, String> _draftMarks = {};
  final Map<String, TextEditingController> _markControllers = {};

  final Map<String, FocusNode> _markFocusNodes = {};

  String? _selectedBatchId;
  String? _selectedSubject;
  String? _selectedTestId;

  bool _loading = true;
  bool _loadingTests = false;
  bool _loadingStudents = false;
  bool _creatingTest = false;
  bool _saving = false;

  String? _error;

  static const List<String> _subjectOrder = [
    'Phy',
    'Chem',
    'Math',
    'Eng',
    'Comp',
    'Bio',
  ];

  bool get _isAdmin => _user?.isAdmin ?? widget.userRole == 'admin';

  Map<String, dynamic>? get _selectedBatch {
    final id = _selectedBatchId;
    if (id == null) return null;

    for (final batch in _batches) {
      if (batch['id'].toString() == id) {
        return batch;
      }
    }

    return null;
  }

  Map<String, dynamic>? get _selectedTest {
    final id = _selectedTestId;
    if (id == null) return null;

    for (final test in _tests) {
      if (test['id'].toString() == id) {
        return test;
      }
    }

    return null;
  }

  int get _selectedClassLevel =>
      (_selectedBatch?['class_level'] as num?)?.toInt() ?? 0;

  double get _selectedMaxMarks =>
      (_selectedTest?['max_marks'] as num?)?.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final controller in _markControllers.values) {
      controller.dispose();
    }

    for (final focusNode in _markFocusNodes.values) {
      focusNode.dispose();
    }

    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final user = await _authService.loadCurrentUser();

      if (user == null) {
        throw StateError('Authenticated portal profile unavailable.');
      }

      final batchRows = await _supabase
          .from('batches')
          .select('id, name, class_level')
          .order('class_level', ascending: true)
          .order('name', ascending: true);

      var batches = batchRows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (!user.isAdmin) {
        final allowedLevels = user.classLevels.toSet();

        batches = batches.where((batch) {
          return allowedLevels.contains(
            (batch['class_level'] as num?)?.toInt(),
          );
        }).toList();
      }

      batches = sortBatches(
        batches,
      ).map((row) => Map<String, dynamic>.from(row)).toList();

      final firstBatch = batches.isEmpty ? null : batches.first;

      final firstClassLevel =
          (firstBatch?['class_level'] as num?)?.toInt() ?? 0;

      final firstSubjects = _subjectsFor(
        user: user,
        classLevel: firstClassLevel,
      );

      if (!mounted) return;

      setState(() {
        _user = user;
        _batches = batches;
        _selectedBatchId = firstBatch?['id']?.toString();
        _selectedSubject = firstSubjects.isEmpty ? null : firstSubjects.first;
        _loading = false;
        _error = null;
      });

      await _loadTests();
    } catch (e) {
      debugPrint('Award list bootstrap error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load Award Lists.';
      });
    }
  }

  List<String> _subjectsFor({
    required PortalUser user,
    required int classLevel,
  }) {
    if (classLevel <= 0) {
      return const [];
    }

    if (user.isAdmin) {
      return List<String>.from(_subjectOrder);
    }

    final allowed = user.assignments
        .where((assignment) => assignment.classLevel == classLevel)
        .map((assignment) => assignment.subjectCode)
        .toSet();

    return _subjectOrder.where(allowed.contains).toList();
  }

  List<String> get _availableSubjects {
    final user = _user;
    if (user == null) return const [];
    return _subjectsFor(user: user, classLevel: _selectedClassLevel);
  }

  Future<void> _changeBatch(String batchId) async {
    final user = _user;
    if (user == null) return;

    final batch = _batches.firstWhere(
      (item) => item['id'].toString() == batchId,
    );

    final classLevel = (batch['class_level'] as num?)?.toInt() ?? 0;

    final subjects = _subjectsFor(user: user, classLevel: classLevel);

    setState(() {
      _selectedBatchId = batchId;
      _selectedSubject = subjects.isEmpty ? null : subjects.first;
      _selectedTestId = null;
      _tests = [];
      _students = [];
      _draftMarks.clear();
    });

    await _loadTests();
  }

  Future<void> _changeSubject(String subject) async {
    setState(() {
      _selectedSubject = subject;
      _selectedTestId = null;
      _tests = [];
      _students = [];
      _draftMarks.clear();
    });

    await _loadTests();
  }

  Future<void> _loadTests({String? selectTestId}) async {
    final batchId = _selectedBatchId;
    final subject = _selectedSubject;

    if (batchId == null || subject == null) {
      if (mounted) {
        setState(() {
          _tests = [];
          _selectedTestId = null;
          _students = [];
          _draftMarks.clear();
        });
      }

      return;
    }

    setState(() {
      _loadingTests = true;
    });

    try {
      final response = await _supabase
          .from('award_tests')
          .select(
            'id, batch_id, subject_code, test_no, test_date, '
            'max_marks, created_by, created_at',
          )
          .eq('batch_id', batchId)
          .eq('subject_code', subject)
          .order('test_no', ascending: false);

      final tests = response
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      String? selectedId = selectTestId;

      if (selectedId == null ||
          !tests.any((test) => test['id'].toString() == selectedId)) {
        selectedId = tests.isEmpty ? null : tests.first['id'].toString();
      }

      if (!mounted) return;

      setState(() {
        _tests = tests;
        _selectedTestId = selectedId;
        _loadingTests = false;
      });

      await _loadTestStudents();
    } catch (e) {
      debugPrint('Award tests load error: $e');

      if (!mounted) return;

      setState(() {
        _loadingTests = false;
      });

      _showMessage('Could not load tests.', error: true);
    }
  }

  Future<void> _loadTestStudents() async {
    final test = _selectedTest;

    final subject = _selectedSubject;

    if (test == null || subject == null) {
      if (mounted) {
        setState(() {
          _students = [];
          _draftMarks.clear();
        });
      }

      _clearMarkInputs();

      return;
    }

    final batchId = test['batch_id'].toString();

    final testId = test['id'].toString();

    setState(() {
      _loadingStudents = true;
    });

    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('students')
            .select('id, name, stream')
            .eq('batch_id', batchId)
            .order('name', ascending: true),

        _supabase
            .from('award_marks')
            .select(
              'student_id, '
              'marks, '
              'is_absent',
            )
            .eq('test_id', testId),
      ]);

      final rawStudents = results[0] as List;

      final marks = results[1] as List;

      final marksByStudent = <String, double>{};

      final absentByStudent = <String, bool>{};

      for (final row in marks) {
        final studentId = row['student_id']?.toString();

        if (studentId == null) {
          continue;
        }

        absentByStudent[studentId] = row['is_absent'] == true;

        final value = (row['marks'] as num?)?.toDouble();

        if (value != null) {
          marksByStudent[studentId] = value;
        }
      }

      final eligible = <_AwardStudentRow>[];

      for (final raw in rawStudents) {
        final student = Map<String, dynamic>.from(raw);

        final id = student['id'].toString();

        final rawStream = student['stream'];

        final stream = rawStream is List
            ? rawStream.map((item) => item.toString()).toList()
            : <String>[];

        if (!stream.contains(subject)) {
          continue;
        }

        eligible.add(
          _AwardStudentRow(
            id: id,
            name: student['name']?.toString() ?? 'Student',
            savedMarks: marksByStudent[id],
            isAbsent: absentByStudent[id] ?? false,
          ),
        );
      }

      _syncMarkInputs(eligible);

      if (!mounted) return;

      setState(() {
        _students = eligible;

        _loadingStudents = false;
      });
    } catch (e) {
      debugPrint('Award students load error: $e');

      if (!mounted) return;

      setState(() {
        _loadingStudents = false;
      });

      _showMessage(
        'Could not load '
        'test students.',
        error: true,
      );
    }
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  void _clearMarkInputs() {
    for (final controller in _markControllers.values) {
      controller.dispose();
    }

    for (final focusNode in _markFocusNodes.values) {
      focusNode.dispose();
    }

    _markControllers.clear();

    _markFocusNodes.clear();
  }

  void _syncMarkInputs(List<_AwardStudentRow> students) {
    final activeIds = students.map((student) => student.id).toSet();

    final removedControllerIds = _markControllers.keys
        .where((id) => !activeIds.contains(id))
        .toList();

    for (final id in removedControllerIds) {
      _markControllers.remove(id)?.dispose();
    }

    final removedFocusIds = _markFocusNodes.keys
        .where((id) => !activeIds.contains(id))
        .toList();

    for (final id in removedFocusIds) {
      _markFocusNodes.remove(id)?.dispose();
    }

    _draftMarks.clear();

    for (final student in students) {
      final value = student.isAbsent
          ? 'A'
          : student.savedMarks == null
          ? ''
          : _formatNumber(student.savedMarks!);

      final controller = _markControllers.putIfAbsent(
        student.id,
        () => TextEditingController(),
      );

      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );

      _markFocusNodes.putIfAbsent(student.id, () => FocusNode());

      _draftMarks[student.id] = value;
    }
  }

  void _focusNextStudent(String currentStudentId) {
    final currentIndex = _students.indexWhere(
      (student) => student.id == currentStudentId,
    );

    if (currentIndex < 0) {
      return;
    }

    final nextIndex = currentIndex + 1;

    if (nextIndex >= _students.length) {
      _markFocusNodes[currentStudentId]?.unfocus();

      return;
    }

    final nextStudent = _students[nextIndex];

    final nextFocus = _markFocusNodes[nextStudent.id];

    if (nextFocus == null) {
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 70), () {
      if (!mounted) return;

      nextFocus.requestFocus();

      final controller = _markControllers[nextStudent.id];

      if (controller != null) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      }
    });
  }

  bool _shouldAutoAdvance({required String value, required double maxMarks}) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return false;
    }

    // Decimal marks are still supported,
    // but we do not auto-jump while
    // someone may still be typing .5.
    if (clean.contains('.')) {
      return false;
    }

    // For a 100+ marks paper we cannot
    // assume two digits means finished.
    if (maxMarks >= 100) {
      return false;
    }

    if (clean.length != 2) {
      return false;
    }

    final marks = double.tryParse(clean);

    if (marks == null) {
      return false;
    }

    return marks >= 0 && marks <= maxMarks;
  }

  void _handleMarkChanged(
    _AwardStudentRow student,
    String value,
    double maxMarks,
  ) {
    final clean = value.trim();

    _draftMarks[student.id] = clean;

    if (_shouldAutoAdvance(value: clean, maxMarks: maxMarks)) {
      _focusNextStudent(student.id);
    }
  }

  void _markStudentAbsent(_AwardStudentRow student) {
    final controller = _markControllers[student.id];

    if (controller == null) {
      return;
    }

    controller.value = const TextEditingValue(
      text: 'A',
      selection: TextSelection.collapsed(offset: 1),
    );

    _draftMarks[student.id] = 'A';

    _focusNextStudent(student.id);
  }

  Future<void> _createTest() async {
    final batchId = _selectedBatchId;
    final subject = _selectedSubject;

    if (batchId == null || subject == null) {
      _showMessage('Select a batch and subject first.', error: true);
      return;
    }

    DateTime selectedDate = DateTime.now();

    final maxMarksController = TextEditingController(text: '20');
    String? dialogError;

    final request = await showDialog<_NewAwardTest>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> chooseDate() async {
              final date = await showDatePicker(
                context: dialogContext,
                initialDate: selectedDate,
                firstDate: DateTime(2026, 1, 1),
                lastDate: DateTime.now(),
              );

              if (date != null) {
                setDialogState(() {
                  selectedDate = date;
                  dialogError = null;
                });
              }
            }

            return AlertDialog(
              title: Text('New ${feeSubjectLabel(subject)} Test'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.calendar_month_outlined,
                        color: AppTheme.fgNavyBlue,
                      ),
                      title: const Text('Test Date'),
                      subtitle: Text(
                        DateFormat('EEEE, dd MMM yyyy').format(selectedDate),
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: chooseDate,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: maxMarksController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Total Marks',
                        prefixIcon: Icon(Icons.score_outlined),
                        hintText: '20',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.fgNavyBlue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Text(
                        'Test date is for record only. '
                        'All students studying this subject will appear '
                        'regardless of attendance.',
                        style: TextStyle(fontSize: 13.5, height: 1.45),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final maxMarks = double.tryParse(
                      maxMarksController.text.trim(),
                    );

                    if (maxMarks == null || maxMarks <= 0) {
                      setDialogState(() {
                        dialogError = 'Enter valid total marks.';
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _NewAwardTest(date: selectedDate, maxMarks: maxMarks),
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create Test'),
                ),
              ],
            );
          },
        );
      },
    );

    maxMarksController.dispose();

    if (request == null) return;

    setState(() {
      _creatingTest = true;
    });

    try {
      final result = await _supabase.rpc(
        'create_award_test',
        params: {
          'p_batch_id': batchId,
          'p_subject_code': subject,
          'p_test_date': DateFormat('yyyy-MM-dd').format(request.date),
          'p_max_marks': request.maxMarks,
        },
      );

      final testId = result?.toString();

      if (testId == null || testId.isEmpty) {
        throw StateError('Test could not be created.');
      }

      await _loadTests(selectTestId: testId);

      _showMessage('New test created successfully.');
    } catch (e) {
      debugPrint('Create award test error: $e');
      _showMessage(_friendlyError(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _creatingTest = false;
        });
      }
    }
  }

  Future<void> _saveMarks() async {
    final test = _selectedTest;

    if (test == null) {
      return;
    }

    final maxMarks = (test['max_marks'] as num).toDouble();

    final payload = <Map<String, dynamic>>[];

    for (final student in _students) {
      final controller = _markControllers[student.id];

      final value = (controller?.text ?? _draftMarks[student.id] ?? '')
          .trim()
          .toUpperCase();

      if (value.isEmpty) {
        continue;
      }

      if (value == 'A') {
        payload.add({
          'student_id': student.id,
          'marks': null,
          'is_absent': true,
        });

        continue;
      }

      final marks = double.tryParse(value);

      if (marks == null) {
        _showMessage(
          'Invalid marks for '
          '${student.name}.',
          error: true,
        );

        return;
      }

      if (marks < 0 || marks > maxMarks) {
        _showMessage(
          '${student.name}: '
          'marks must be between '
          '0 and '
          '${_formatNumber(maxMarks)}.',
          error: true,
        );

        _markFocusNodes[student.id]?.requestFocus();

        return;
      }

      payload.add({
        'student_id': student.id,
        'marks': marks,
        'is_absent': false,
      });
    }

    if (payload.isEmpty) {
      _showMessage(
        'Enter at least one '
        'student mark.',
        error: true,
      );

      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
    });

    try {
      final result = await _supabase.rpc(
        'save_award_marks',
        params: {'p_test_id': test['id'].toString(), 'p_marks': payload},
      );

      await _loadTestStudents();

      if (!mounted) {
        return;
      }

      await _showSavedSuccessSheet(
        savedCount: result is num ? result.toInt() : payload.length,
      );
    } catch (e) {
      debugPrint('Save award marks error: $e');

      _showMessage(_friendlyError(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _showSavedSuccessSheet({required int savedCount}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 16),
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.success,
                  child: Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Award List Saved',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '$savedCount mark(s) saved successfully.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(sheetContext);

                          await _previewCurrentTest();
                        },
                        icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
                        label: const Text('Preview & Share'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _previewCurrentTest() async {
    final batch = _selectedBatch;
    final test = _selectedTest;
    final subject = _selectedSubject;

    if (batch == null || test == null || subject == null) {
      _showMessage('Select a test first.', error: true);

      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AwardListPreviewScreen(
          supabase: _supabase,
          user: _user,
          batch: batch,
          test: test,
          subjectCode: subject,
        ),
      ),
    );
  }

  Future<void> _openHistory() async {
    final batch = _selectedBatch;
    final subject = _selectedSubject;

    if (batch == null || subject == null) {
      _showMessage('Select a batch and subject first.', error: true);
      return;
    }

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AwardHistoryScreen(
          supabase: _supabase,
          user: _user,
          batch: batch,
          subjectCode: subject,
          tests: _tests.map((item) => Map<String, dynamic>.from(item)).toList(),
        ),
      ),
    );

    if (changed == true && mounted) {
      await _loadTests();
    }
  }

  Future<void> _clearMark(_AwardStudentRow student) async {
    final test = _selectedTest;
    if (test == null) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Clear Saved Mark?'),
              content: Text('Remove the saved mark for ${student.name}?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Clear'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      await _supabase.rpc(
        'clear_award_mark',
        params: {
          'p_test_id': test['id'].toString(),
          'p_student_id': student.id,
        },
      );

      await _loadTestStudents();

      _showMessage('Saved mark cleared.');
    } catch (e) {
      _showMessage(_friendlyError(e), error: true);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('no students were found')) {
      return 'No students were found for this batch and subject.';
    }

    if (message.contains('not assigned')) {
      return 'This teacher is not assigned to that subject/class.';
    }

    if (message.contains('does not belong')) {
      return 'Student does not belong to this batch or subject.';
    }

    return 'Operation failed. Please check the selected batch, '
        'subject, date and marks.';
  }

  void _showMessage(String value, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  Widget _buildAwardHeader() {
    return DashboardSectionHeader(
      title: 'Award Lists',
      subtitle: _isAdmin
          ? 'View, edit and share tests for every batch and subject'
          : 'Enter marks and share award lists for your assigned classes',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'History',
            color: Colors.white,
            onPressed: _tests.isEmpty ? null : _openHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            color: Colors.white,
            onPressed: _loadingTests ? null : _loadTests,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    // No test yet / loading:
    // keep normal layout because there is no marks list
    // to scroll anyway.
    if (_selectedSubject == null || _loadingTests || _tests.isEmpty) {
      return Column(
        children: [
          _buildAwardHeader(),
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(child: _buildAwardHeader()),
                SliverToBoxAdapter(child: _buildFilters()),
                SliverToBoxAdapter(child: _buildTestSelector()),
              ];
            },
            body: _loadingStudents
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(
                        height: 320,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  )
                : _students.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(
                        height: 300,
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No students found for this subject.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildStudentsList(),
          ),
        ),

        // Save remains reachable.
        if (_students.isNotEmpty) _buildSaveBar(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ErrorStateView(message: _error!, onRetry: _bootstrap);
    }

    if (_batches.isEmpty) {
      return const Center(child: Text('No assigned batches available.'));
    }

    final isPhone = MediaQuery.sizeOf(context).width < 700;

    if (isPhone) {
      return _buildPhoneLayout();
    }

    return Column(
      children: [
        _buildAwardHeader(),
        _buildFilters(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildFilters() {
    final subjects = _availableSubjects;

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;

            final batch = DropdownButtonFormField<String>(
              key: ValueKey('award-batch-$_selectedBatchId'),
              initialValue: _selectedBatchId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Batch',
                prefixIcon: Icon(Icons.class_outlined),
              ),
              items: _batches
                  .map(
                    (batch) => DropdownMenuItem(
                      value: batch['id'].toString(),
                      child: Text(batch['name']?.toString() ?? 'Batch'),
                    ),
                  )
                  .toList(),
              onChanged: _loadingTests
                  ? null
                  : (value) {
                      if (value != null) {
                        _changeBatch(value);
                      }
                    },
            );

            final subject = DropdownButtonFormField<String>(
              key: ValueKey(
                'award-subject-$_selectedBatchId-$_selectedSubject',
              ),
              initialValue: subjects.contains(_selectedSubject)
                  ? _selectedSubject
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Subject',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
              items: subjects
                  .map(
                    (code) => DropdownMenuItem(
                      value: code,
                      child: Text(feeSubjectLabel(code)),
                    ),
                  )
                  .toList(),
              onChanged: _loadingTests
                  ? null
                  : (value) {
                      if (value != null) {
                        _changeSubject(value);
                      }
                    },
            );

            final addButton = ElevatedButton.icon(
              onPressed: _creatingTest || _selectedSubject == null
                  ? null
                  : _createTest,
              icon: _creatingTest
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.add_rounded),
              label: const Text('New Test'),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  batch,
                  const SizedBox(height: 10),
                  subject,
                  const SizedBox(height: 10),
                  addButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: batch),
                const SizedBox(width: 12),
                Expanded(child: subject),
                const SizedBox(width: 12),
                addButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_selectedSubject == null) {
      return const Center(
        child: Text('No subject assignment is available for this class.'),
      );
    }

    if (_loadingTests) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tests.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.assignment_add,
                    color: AppTheme.fgNavyBlue,
                    size: 54,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'No Tests Yet',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Create the first ${feeSubjectLabel(_selectedSubject!)} test for this batch.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _createTest,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create T1'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildTestSelector(),
        Expanded(
          child: _loadingStudents
              ? const Center(child: CircularProgressIndicator())
              : _students.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No students found for this subject.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildStudentsList(),
        ),
        if (_students.isNotEmpty) _buildSaveBar(),
      ],
    );
  }

  Widget _buildTestSelector() {
    final test = _selectedTest;

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final selector = DropdownButtonFormField<String>(
              key: ValueKey('award-test-$_selectedTestId-${_tests.length}'),
              initialValue: _selectedTestId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Test',
                prefixIcon: Icon(Icons.assignment_outlined),
              ),
              items: _tests.map((item) {
                final no = (item['test_no'] as num?)?.toInt() ?? 0;
                final date = DateTime.tryParse(item['test_date'].toString());

                return DropdownMenuItem(
                  value: item['id'].toString(),
                  child: Text(
                    'T$no  •  ${date == null ? item['test_date'] : DateFormat('dd MMM yyyy').format(date)}',
                  ),
                );
              }).toList(),
              onChanged: _loadingStudents
                  ? null
                  : (value) async {
                      if (value == null) return;

                      setState(() {
                        _selectedTestId = value;
                      });

                      await _loadTestStudents();
                    },
            );

            final details = test == null
                ? const SizedBox.shrink()
                : Wrap(
                    spacing: 9,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _TestBadge(
                        icon: Icons.score_outlined,
                        text:
                            'Total: ${_formatNumber((test['max_marks'] as num).toDouble())}',
                      ),
                      _TestBadge(
                        icon: Icons.people_outline,
                        text: 'Students: ${_students.length}',
                      ),
                      _TestBadge(
                        icon: Icons.menu_book_outlined,
                        text: feeSubjectLabel(_selectedSubject!),
                      ),
                      OutlinedButton.icon(
                        onPressed: _previewCurrentTest,
                        icon: const FaIcon(
                          FontAwesomeIcons.whatsapp,
                          size: 15,
                          color: Color(0xFF25D366),
                        ),
                        label: const Text('Preview & Share'),
                      ),
                    ],
                  );

            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [selector, const SizedBox(height: 10), details],
              );
            }

            return Row(
              children: [
                SizedBox(width: 360, child: selector),
                const SizedBox(width: 14),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStudentsList() {
    final maxMarks = _selectedMaxMarks;

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,

      padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),

      itemCount: _students.length,

      itemBuilder: (context, index) {
        final student = _students[index];

        final controller = _markControllers[student.id]!;

        final focusNode = _markFocusNodes[student.id]!;

        final isLast = index == _students.length - 1;

        Widget markField() {
          return TextFormField(
            controller: controller,

            focusNode: focusNode,

            enabled: !_saving,

            textAlign: TextAlign.center,

            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: false,
            ),

            textInputAction: isLast
                ? TextInputAction.done
                : TextInputAction.next,

            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],

            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),

            decoration: InputDecoration(
              labelText: 'Marks',
              hintText: '0',
              suffixText:
                  '/ '
                  '${_formatNumber(maxMarks)}',
              isDense: true,
              counterText: '',
            ),

            maxLength: 6,

            onTap: () {
              // If this was marked A,
              // first numeric key should
              // replace A immediately.
              if (controller.text.trim().toUpperCase() == 'A') {
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              }
            },

            onChanged: (value) {
              _handleMarkChanged(student, value, maxMarks);
            },

            onFieldSubmitted: (_) {
              if (isLast) {
                focusNode.unfocus();
              } else {
                _focusNextStudent(student.id);
              }
            },
          );
        }

        Widget absentButton() {
          return ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,

            builder: (context, value, child) {
              final selected = value.text.trim().toUpperCase() == 'A';

              return SizedBox(
                width: 52,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,

                    backgroundColor: selected
                        ? AppTheme.danger.withValues(alpha: 0.10)
                        : null,

                    side: BorderSide(
                      color: selected ? AppTheme.danger : AppTheme.border,
                      width: selected ? 1.8 : 1,
                    ),
                  ),

                  onPressed: _saving
                      ? null
                      : () {
                          _markStudentAbsent(student);
                        },

                  child: Text(
                    'A',
                    style: TextStyle(
                      color: selected ? AppTheme.danger : AppTheme.fgNavyBlue,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            },
          );
        }

        final savedText = student.isAbsent
            ? 'Saved: Absent'
            : student.savedMarks == null
            ? 'Mark not entered'
            : 'Saved: '
                  '${_formatNumber(student.savedMarks!)}'
                  ' / '
                  '${_formatNumber(maxMarks)}';

        final savedColor = student.isAbsent
            ? AppTheme.danger
            : student.savedMarks == null
            ? AppTheme.textSecondary
            : AppTheme.success;

        return Card(
          margin: const EdgeInsets.only(bottom: 9),

          child: Padding(
            padding: const EdgeInsets.all(12),

            child: LayoutBuilder(
              builder: (context, constraints) {
                final mobile = constraints.maxWidth < 520;

                final studentInfo = Row(
                  children: [
                    CircleAvatar(
                      radius: 20,

                      backgroundColor: AppTheme.fgNavyBlue.withValues(
                        alpha: 0.08,
                      ),

                      foregroundColor: AppTheme.fgNavyBlue,

                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),

                    const SizedBox(width: 11),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            student.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 2),

                          Text(
                            savedText,
                            style: TextStyle(
                              color: savedColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final inputRow = Row(
                  children: [
                    Expanded(child: markField()),

                    const SizedBox(width: 7),

                    absentButton(),

                    if (student.savedMarks != null || student.isAbsent) ...[
                      const SizedBox(width: 3),

                      IconButton(
                        tooltip: 'Clear saved result',

                        onPressed: _saving
                            ? null
                            : () {
                                _clearMark(student);
                              },

                        color: AppTheme.danger,

                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ],
                );

                if (mobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,

                    children: [
                      studentInfo,

                      const SizedBox(height: 10),

                      inputRow,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: studentInfo),

                    const SizedBox(width: 12),

                    SizedBox(width: 270, child: inputRow),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_students.length} student(s)',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _saving ? null : _saveMarks,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Marks'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AwardStudentRow {
  final String id;

  final String name;

  final double? savedMarks;

  final bool isAbsent;

  const _AwardStudentRow({
    required this.id,
    required this.name,
    required this.savedMarks,
    required this.isAbsent,
  });
}

class _NewAwardTest {
  final DateTime date;
  final double maxMarks;

  const _NewAwardTest({required this.date, required this.maxMarks});
}

class _TestBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TestBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppTheme.fgNavyBlue),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
