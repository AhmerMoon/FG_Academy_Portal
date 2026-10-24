import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/fee_models.dart';
import '../models/portal_user.dart';
import '../services/auth_service.dart';
import '../services/award_draft_store.dart';
import '../utils/dashboard_section_header.dart';
import '../utils/error_state_view.dart';
import '../utils/list_sorting.dart';
import '../utils/student_group_helper.dart';
import '../widgets/add_student_dialog.dart';
import '../widgets/student_subject_selector.dart';
import 'award_history_screen.dart';
import 'award_list_preview_screen.dart';

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

  final Map<String, TextEditingController> _markControllers = {};
  final Map<String, FocusNode> _markFocusNodes = {};
  final Map<String, String> _savedMarkTexts = {};
  final Map<String, String> _pendingMarkDrafts = {};

  String? _selectedBatchId;
  String? _selectedSubject;
  String? _selectedTestId;

  bool _loading = true;
  bool _loadingTests = false;
  bool _loadingStudents = false;
  bool _saving = false;
  bool _creatingTest = false;
  bool _addingStudent = false;
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

    for (final row in _batches) {
      if (row['id'].toString() == id) return row;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedTest {
    final id = _selectedTestId;
    if (id == null) return null;

    for (final row in _tests) {
      if (row['id'].toString() == id) return row;
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
    _clearMarkInputs();
    super.dispose();
  }

  void _clearMarkInputs() {
    for (final controller in _markControllers.values) {
      controller.dispose();
    }
    for (final focus in _markFocusNodes.values) {
      focus.dispose();
    }
    _markControllers.clear();
    _markFocusNodes.clear();
    _savedMarkTexts.clear();
    _pendingMarkDrafts.clear();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = await _authService.loadCurrentUser();

      if (user == null) {
        throw StateError('Portal profile unavailable.');
      }

      final rows = await _supabase
          .from('batches')
          .select('id, name, class_level')
          .order('class_level', ascending: true)
          .order('name', ascending: true);

      var batches = rows.map((row) => Map<String, dynamic>.from(row)).toList();

      if (!user.isAdmin) {
        final allowed = user.classLevels.toSet();
        batches = batches.where((batch) {
          final level = (batch['class_level'] as num?)?.toInt();
          return allowed.contains(level);
        }).toList();
      }

      batches = sortBatches(
        batches,
      ).map((row) => Map<String, dynamic>.from(row)).toList();

      final first = batches.isEmpty ? null : batches.first;
      final level = (first?['class_level'] as num?)?.toInt() ?? 0;

      final subjects = _subjectsFor(user: user, classLevel: level);

      if (!mounted) return;

      setState(() {
        _user = user;
        _batches = batches;
        _selectedBatchId = first?['id']?.toString();
        _selectedSubject = subjects.isEmpty ? null : subjects.first;
        _loading = false;
      });

      await _loadTests();
    } catch (e) {
      debugPrint('Award bootstrap error: $e');

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
    if (classLevel < 9 || classLevel > 12) {
      return const [];
    }

    if (user.isAdmin) {
      return List<String>.from(_subjectOrder);
    }

    final allowed = user.assignments
        .where((a) => a.classLevel == classLevel)
        .map((a) => a.subjectCode)
        .toSet();

    return _subjectOrder.where(allowed.contains).toList();
  }

  List<String> get _availableSubjects {
    final user = _user;
    if (user == null) return const [];

    return _subjectsFor(user: user, classLevel: _selectedClassLevel);
  }

  Future<void> _changeBatch(String id) async {
    await _persistMarkDrafts();

    final user = _user;
    if (user == null || !mounted) return;

    final batch = _batches.firstWhere((row) => row['id'].toString() == id);

    final level = (batch['class_level'] as num?)?.toInt() ?? 0;
    final subjects = _subjectsFor(user: user, classLevel: level);

    _clearMarkInputs();

    setState(() {
      _selectedBatchId = id;
      _selectedSubject = subjects.isEmpty ? null : subjects.first;
      _selectedTestId = null;
      _tests = [];
      _students = [];
    });

    await _loadTests();
  }

  Future<void> _changeSubject(String subject) async {
    await _persistMarkDrafts();

    if (!mounted) return;

    _clearMarkInputs();

    setState(() {
      _selectedSubject = subject;
      _selectedTestId = null;
      _tests = [];
      _students = [];
    });

    await _loadTests();
  }

  Future<void> _changeTest(String id) async {
    await _persistMarkDrafts();

    if (!mounted) return;

    setState(() {
      _selectedTestId = id;
      _students = [];
    });

    await _loadTestStudents();
  }

  Future<void> _loadTests({String? selectTestId}) async {
    final batchId = _selectedBatchId;
    final subject = _selectedSubject;

    if (batchId == null || subject == null) {
      if (mounted) {
        setState(() {
          _tests = [];
          _students = [];
          _selectedTestId = null;
        });
      }
      return;
    }

    setState(() => _loadingTests = true);

    try {
      final response = await _supabase
          .from('award_tests')
          .select(
            'id,batch_id,subject_code,test_no,'
            'test_date,max_marks,created_by,created_at',
          )
          .eq('batch_id', batchId)
          .eq('subject_code', subject)
          .order('test_no', ascending: false);

      final tests = response
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      String? selectedId = selectTestId ?? _selectedTestId;

      if (!tests.any((row) => row['id'].toString() == selectedId)) {
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
      debugPrint('Award test fetch error: $e');

      if (!mounted) return;

      setState(() => _loadingTests = false);
      _showMessage('Could not load tests.', error: true);
    }
  }

  String _formatNumber(double number) {
    if (number == number.roundToDouble()) {
      return number.toStringAsFixed(0);
    }
    return number.toStringAsFixed(2);
  }

  Future<void> _loadTestStudents() async {
    final test = _selectedTest;
    final subject = _selectedSubject;

    if (test == null || subject == null) {
      _clearMarkInputs();

      if (mounted) {
        setState(() {
          _students = [];
          _loadingStudents = false;
        });
      }
      return;
    }

    setState(() => _loadingStudents = true);

    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('students')
            .select('id,name,stream')
            .eq('batch_id', test['batch_id'].toString())
            .eq('is_archived', false)
            .order('name', ascending: true),

        _supabase
            .from('award_marks')
            .select('student_id,marks,is_absent')
            .eq('test_id', test['id'].toString()),
      ]);

      final marksById = <String, double>{};
      final absentsById = <String, bool>{};

      for (final row in results[1] as List) {
        final id = row['student_id']?.toString();
        if (id == null) continue;

        marksById[id] =
            (row['marks'] as num?)?.toDouble() ?? marksById[id] ?? 0;
        absentsById[id] = row['is_absent'] == true;

        if (row['marks'] == null) {
          marksById.remove(id);
        }
      }

      final eligible = <_AwardStudentRow>[];

      for (final raw in results[0] as List) {
        final row = Map<String, dynamic>.from(raw);
        final stream = row['stream'] is List
            ? (row['stream'] as List).map((v) => v.toString()).toList()
            : <String>[];

        if (!stream.contains(subject)) continue;

        final id = row['id'].toString();

        eligible.add(
          _AwardStudentRow(
            id: id,
            name: row['name']?.toString() ?? 'Student',
            savedMarks: marksById[id],
            isAbsent: absentsById[id] ?? false,
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
      debugPrint('Award students fetch error: $e');

      if (!mounted) return;

      setState(() => _loadingStudents = false);
      _showMessage('Could not load students and marks.', error: true);
    }
  }

  void _syncMarkInputs(List<_AwardStudentRow> students) {
    final visibleIds = students.map((student) => student.id).toSet();

    for (final id
        in _markControllers.keys
            .where((id) => !visibleIds.contains(id))
            .toList()) {
      _markControllers.remove(id)?.dispose();
      _markFocusNodes.remove(id)?.dispose();
    }

    final userId = _supabase.auth.currentUser?.id;
    final testId = _selectedTestId;

    final stored = userId != null && testId != null
        ? AwardDraftStore.load(userId: userId, testId: testId)
        : <String, String>{};

    _savedMarkTexts.clear();
    _pendingMarkDrafts.clear();

    for (final student in students) {
      final saved = student.isAbsent
          ? 'A'
          : student.savedMarks == null
          ? ''
          : _formatNumber(student.savedMarks!);

      final local = stored[student.id];
      final display = local != null && local != saved ? local : saved;

      _savedMarkTexts[student.id] = saved;

      if (local != null && local != saved) {
        _pendingMarkDrafts[student.id] = local;
      }

      final controller = _markControllers.putIfAbsent(
        student.id,
        () => TextEditingController(),
      );

      controller.value = TextEditingValue(
        text: display,
        selection: TextSelection.collapsed(offset: display.length),
      );

      _markFocusNodes.putIfAbsent(student.id, () => FocusNode());
    }
  }

  Future<void> _persistMarkDrafts() async {
    final userId = _supabase.auth.currentUser?.id;
    final testId = _selectedTestId;

    if (userId == null || testId == null) return;

    try {
      await AwardDraftStore.save(
        userId: userId,
        testId: testId,
        marks: Map<String, String>.from(_pendingMarkDrafts),
      );
    } catch (e) {
      debugPrint('Award local draft error: $e');

      if (mounted) {
        _showMessage('Local marks draft could not be saved.', error: true);
      }
    }
  }

  void _recordMarkDraft(String id, String text) {
    final value = text.trim().toUpperCase();
    final saved = _savedMarkTexts[id] ?? '';
    final wasEmpty = _pendingMarkDrafts.isEmpty;

    if (value == saved) {
      _pendingMarkDrafts.remove(id);
    } else {
      _pendingMarkDrafts[id] = value;
    }

    unawaited(_persistMarkDrafts());

    if (mounted && wasEmpty != _pendingMarkDrafts.isEmpty) {
      setState(() {});
    }
  }

  void _focusNextStudent(String id) {
    final current = _students.indexWhere((student) => student.id == id);

    if (current < 0) return;

    if (current == _students.length - 1) {
      _markFocusNodes[id]?.unfocus();
      return;
    }

    final next = _students[current + 1].id;

    Future<void>.delayed(const Duration(milliseconds: 70), () {
      if (!mounted) return;

      _markFocusNodes[next]?.requestFocus();

      final controller = _markControllers[next];

      if (controller != null) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      }
    });
  }

  void _markAbsent(_AwardStudentRow student) {
    final controller = _markControllers[student.id];
    if (controller == null) return;

    controller.value = const TextEditingValue(
      text: 'A',
      selection: TextSelection.collapsed(offset: 1),
    );

    _recordMarkDraft(student.id, 'A');
    _focusNextStudent(student.id);
  }

  void _handleMarksChanged(_AwardStudentRow student, String value) {
    _recordMarkDraft(student.id, value);

    final clean = value.trim();

    if (clean.length != 2 || clean.contains('.') || _selectedMaxMarks >= 100) {
      return;
    }

    final number = double.tryParse(clean);

    if (number != null && number >= 0 && number <= _selectedMaxMarks) {
      _focusNextStudent(student.id);
    }
  }

  Future<void> _addStudentFromAwards() async {
    if (_addingStudent || _saving) return;

    final batchId = _selectedBatchId;
    final subject = _selectedSubject;
    final level = _selectedClassLevel;

    if (batchId == null || subject == null || level <= 0) {
      _showMessage('Select batch and subject first.', error: true);
      return;
    }

    final batch = FeeBatch(
      id: batchId,
      name: _selectedBatch?['name']?.toString() ?? 'Selected Batch',
      classLevel: level,
    );

    final request = await showAcademyAddStudentDialog(
      context: context,
      batches: [batch],
      initialBatch: batch,
      paymentMonth: '',
      lockBatch: true,
      requiredSubject: subject,
    );

    if (!mounted || request == null) return;

    setState(() => _addingStudent = true);

    try {
      await _persistMarkDrafts();

      await _supabase.rpc(
        'portal_add_student_simple',
        params: {
          'p_name': request.name,
          'p_batch_id': batchId,
          'p_group_code': request.groupCode,
        },
      );

      if (!mounted) return;

      await _loadTestStudents();

      _showMessage(
        '${request.name} added successfully. '
        'Existing marks preserved.',
      );
    } catch (e) {
      debugPrint('Award Add Student error: $e');

      _showMessage('Student could not be added.\n$e', error: true);
    } finally {
      if (mounted) {
        setState(() => _addingStudent = false);
      }
    }
  }

  Future<void> _editAwardStudent(_AwardStudentRow student) async {
    try {
      final response = await _supabase
          .from('students')
          .select('name,stream')
          .eq('id', student.id)
          .single();

      if (!mounted) return;

      String name = response['name']?.toString() ?? '';

      var subjects = normalizeStudentSubjects(
        _selectedClassLevel,
        (response['stream'] as List).map((v) => v.toString()),
      );

      String? error;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, update) {
              return AlertDialog(
                title: const Text('Edit Student'),
                content: SizedBox(
                  width: 470,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          initialValue: name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Student Name',
                          ),
                          onChanged: (value) => name = value,
                        ),
                        const SizedBox(height: 14),
                        StudentSubjectSelector(
                          classLevel: _selectedClassLevel,
                          selectedSubjects: subjects,
                          onChanged: (value) {
                            update(() {
                              subjects = value;
                              error = null;
                            });
                          },
                          onValidationError: (message) {
                            update(() => error = message);
                          },
                        ),
                        if (error != null)
                          Text(
                            error!,
                            style: const TextStyle(color: AppTheme.danger),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final validation = studentSubjectSelectionError(
                        _selectedClassLevel,
                        subjects,
                      );

                      if (name.trim().isEmpty || validation != null) {
                        update(() {
                          error = validation ?? 'Enter student name.';
                        });
                        return;
                      }

                      Navigator.pop(dialogContext, true);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (!mounted || confirmed != true) return;

      await _persistMarkDrafts();

      await _supabase.rpc(
        'portal_edit_award_student',
        params: {
          'p_student_id': student.id,
          'p_name': name.trim(),
          'p_subjects': subjects,
        },
      );

      await _loadTestStudents();

      _showMessage('Student updated.');
    } catch (e) {
      _showMessage('Student edit failed.\n$e', error: true);
    }
  }

  Future<void> _archiveAwardStudent(_AwardStudentRow student) async {
    if (!_isAdmin) {
      _showMessage('Only Admin can archive students.', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Archive Student?'),
          content: Text(
            'Archive "${student.name}"?\n\n'
            'Attendance and award marks will be '
            'preserved. The student will disappear '
            'from active lists.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    try {
      await _persistMarkDrafts();

      await _supabase.rpc(
        'archive_student',
        params: {
          'p_student_id': student.id,
          'p_reason': 'Archived from Award Lists',
        },
      );

      _pendingMarkDrafts.remove(student.id);
      await _persistMarkDrafts();

      await _loadTestStudents();

      _showMessage('Student archived. Historical records preserved.');
    } catch (e) {
      _showMessage('Student could not be archived.\n$e', error: true);
    }
  }

  Future<void> _createTest() async {
    final batchId = _selectedBatchId;
    final subject = _selectedSubject;

    if (batchId == null || subject == null) {
      _showMessage('Select batch and subject first.', error: true);
      return;
    }

    DateTime selectedDate = DateTime.now();
    final marksController = TextEditingController(text: '20');

    String? dialogError;

    final request = await showDialog<_NewAwardTest>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, update) {
            Future<void> chooseDate() async {
              final date = await showDatePicker(
                context: dialogContext,
                initialDate: selectedDate,
                firstDate: DateTime(2025, 1, 1),
                lastDate: DateTime.now(),
              );

              if (date != null) {
                update(() => selectedDate = date);
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
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Test Date'),
                      subtitle: Text(
                        DateFormat('dd MMM yyyy').format(selectedDate),
                      ),
                      onTap: chooseDate,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: marksController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Total Marks',
                      ),
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
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final marks = double.tryParse(marksController.text.trim());

                    if (marks == null || marks <= 0) {
                      update(() {
                        dialogError = 'Enter valid total marks.';
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _NewAwardTest(date: selectedDate, maxMarks: marks),
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

    marksController.dispose();

    if (request == null) return;

    setState(() => _creatingTest = true);

    try {
      await _persistMarkDrafts();

      final result = await _supabase.rpc(
        'create_award_test',
        params: {
          'p_batch_id': batchId,
          'p_subject_code': subject,
          'p_test_date': DateFormat('yyyy-MM-dd').format(request.date),
          'p_max_marks': request.maxMarks,
        },
      );

      final id = result?.toString();

      if (id == null || id.isEmpty) {
        throw StateError('Test could not be created.');
      }

      await _loadTests(selectTestId: id);

      _showMessage('New test created successfully.');
    } catch (e) {
      debugPrint('Create Award Test error: $e');
      _showMessage(_friendlyError(e), error: true);
    } finally {
      if (mounted) {
        setState(() => _creatingTest = false);
      }
    }
  }

  Future<void> _saveMarks() async {
    if (_saving || _pendingMarkDrafts.isEmpty) return;

    final test = _selectedTest;
    if (test == null) return;

    final maxMarks = (test['max_marks'] as num?)?.toDouble() ?? 0;

    final payload = <Map<String, dynamic>>[];
    final submitted = <String>[];

    for (final student in _students) {
      if (!_pendingMarkDrafts.containsKey(student.id)) {
        continue;
      }

      final value =
          (_markControllers[student.id]?.text ??
                  _pendingMarkDrafts[student.id] ??
                  '')
              .trim()
              .toUpperCase();

      if (value.isEmpty) {
        _showMessage(
          '${student.name}: enter marks or A. '
          'Use Clear Saved Mark to remove an old mark.',
          error: true,
        );
        return;
      }

      if (value == 'A') {
        payload.add({
          'student_id': student.id,
          'marks': null,
          'is_absent': true,
        });
        submitted.add(student.id);
        continue;
      }

      final number = double.tryParse(value);

      if (number == null || number < 0 || number > maxMarks) {
        _showMessage(
          '${student.name}: marks must be '
          '0 to ${_formatNumber(maxMarks)}.',
          error: true,
        );

        _markFocusNodes[student.id]?.requestFocus();
        return;
      }

      payload.add({
        'student_id': student.id,
        'marks': number,
        'is_absent': false,
      });
      submitted.add(student.id);
    }

    if (payload.isEmpty) {
      _showMessage('No marks to save.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _saving = true);

    try {
      final result = await _supabase.rpc(
        'save_award_marks',
        params: {'p_test_id': test['id'].toString(), 'p_marks': payload},
      );

      for (final id in submitted) {
        _pendingMarkDrafts.remove(id);
      }

      await _persistMarkDrafts();
      await _loadTestStudents();

      if (!mounted) return;

      await _showSavedSuccessSheet(
        savedCount: result is num ? result.toInt() : submitted.length,
      );
    } catch (e) {
      debugPrint('Award Save Marks error: $e');

      _showMessage(
        'Marks could not be uploaded.\n'
        'Local draft is still available.\n$e',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showSavedSuccessSheet({required int savedCount}) async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 27,
                  backgroundColor: AppTheme.success,
                  child: Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 13),
                const Text(
                  'Award List Saved',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text('$savedCount mark(s) saved.'),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _previewCurrentTest();
                        },
                        child: const Text('Preview & Share'),
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

  Future<void> _clearMark(_AwardStudentRow student) async {
    final test = _selectedTest;
    if (test == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Saved Mark?'),
        content: Text('Clear saved mark for ${student.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.rpc(
        'clear_award_mark',
        params: {
          'p_test_id': test['id'].toString(),
          'p_student_id': student.id,
        },
      );

      _pendingMarkDrafts.remove(student.id);
      await _persistMarkDrafts();
      await _loadTestStudents();

      _showMessage('Saved mark cleared.');
    } catch (e) {
      _showMessage(_friendlyError(e), error: true);
    }
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
          tests: _tests.map((row) => Map<String, dynamic>.from(row)).toList(),
        ),
      ),
    );

    if (changed == true && mounted) {
      await _loadTests();
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('not assigned')) {
      return 'Teacher is not assigned to this subject.';
    }

    if (message.contains('archived')) {
      return 'Student is archived. Ask Admin to restore.';
    }

    if (message.contains('does not belong')) {
      return 'Student does not belong to this batch or subject.';
    }

    return 'Operation failed. Check selected class, '
        'subject and marks.\n$error';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
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

    final phone = MediaQuery.sizeOf(context).width < 700;

    if (phone && _tests.isNotEmpty) {
      return Column(
        children: [
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, scrolled) => [
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(child: _buildFilters()),
                SliverToBoxAdapter(child: _buildTestSelector()),
              ],
              body: _loadingStudents
                  ? const Center(child: CircularProgressIndicator())
                  : _students.isEmpty
                  ? const Center(
                      child: Text('No active students for this subject.'),
                    )
                  : _buildStudentsList(),
            ),
          ),
          if (_students.isNotEmpty) _buildSaveBar(),
        ],
      );
    }

    return Column(
      children: [
        _buildHeader(),
        _buildFilters(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildHeader() {
    return DashboardSectionHeader(
      title: 'Award Lists',
      subtitle: _isAdmin
          ? 'Manage tests, marks and award lists'
          : 'Enter marks for your assigned classes',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Add Student',
            color: Colors.white,
            onPressed:
                _addingStudent ||
                    _saving ||
                    _selectedBatchId == null ||
                    _selectedSubject == null
                ? null
                : _addStudentFromAwards,
            icon: _addingStudent
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
          ),
          IconButton(
            tooltip: 'History',
            color: Colors.white,
            onPressed: _tests.isEmpty ? null : _openHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            color: Colors.white,
            onPressed: _loadingTests
                ? null
                : () async {
                    await _persistMarkDrafts();
                    await _loadTests();
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final subjects = _availableSubjects;

    final batchSelector = DropdownButtonFormField<String>(
      key: ValueKey('batch-$_selectedBatchId'),
      initialValue: _selectedBatchId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Batch',
        prefixIcon: Icon(Icons.class_outlined),
      ),
      items: _batches.map((batch) {
        return DropdownMenuItem<String>(
          value: batch['id'].toString(),
          child: Text(
            batch['name']?.toString() ?? 'Batch',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: _loadingTests
          ? null
          : (value) {
              if (value != null) _changeBatch(value);
            },
    );

    final subjectSelector = DropdownButtonFormField<String>(
      key: ValueKey('subject-$_selectedBatchId-$_selectedSubject'),
      initialValue: subjects.contains(_selectedSubject)
          ? _selectedSubject
          : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Subject',
        prefixIcon: Icon(Icons.menu_book_outlined),
      ),
      items: subjects.map((subject) {
        return DropdownMenuItem<String>(
          value: subject,
          child: Text(feeSubjectLabel(subject)),
        );
      }).toList(),
      onChanged: _loadingTests
          ? null
          : (value) {
              if (value != null) _changeSubject(value);
            },
    );

    final createButton = ElevatedButton.icon(
      onPressed: _creatingTest || _selectedSubject == null ? null : _createTest,
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

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  batchSelector,
                  const SizedBox(height: 10),
                  subjectSelector,
                  const SizedBox(height: 10),
                  createButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: batchSelector),
                const SizedBox(width: 12),
                Expanded(child: subjectSelector),
                const SizedBox(width: 12),
                createButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_selectedSubject == null) {
      return const Center(child: Text('No subject assignment for this class.'));
    }

    if (_loadingTests) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tests.isEmpty) {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.assignment_add,
                  size: 48,
                  color: AppTheme.fgNavyBlue,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No Tests Yet',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _createTest,
                  icon: const Icon(Icons.add),
                  label: const Text('Create First Test'),
                ),
              ],
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
                  child: Text('No active students for this subject.'),
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
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final selector = DropdownButtonFormField<String>(
              key: ValueKey('test-$_selectedTestId-${_tests.length}'),
              initialValue: _selectedTestId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Test',
                prefixIcon: Icon(Icons.assignment_outlined),
              ),
              items: _tests.map((row) {
                final no = (row['test_no'] as num?)?.toInt() ?? 0;
                final date = DateTime.tryParse(
                  row['test_date']?.toString() ?? '',
                );

                return DropdownMenuItem<String>(
                  value: row['id'].toString(),
                  child: Text(
                    'T$no  •  '
                    '${date == null ? '-' : DateFormat('dd MMM yyyy').format(date)}',
                  ),
                );
              }).toList(),
              onChanged: _loadingStudents
                  ? null
                  : (value) {
                      if (value != null) _changeTest(value);
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
                        text: 'Total: ${_formatNumber(_selectedMaxMarks)}',
                      ),
                      _TestBadge(
                        icon: Icons.people_outline,
                        text: '${_students.length} Students',
                      ),
                      OutlinedButton.icon(
                        onPressed: _previewCurrentTest,
                        icon: const FaIcon(
                          FontAwesomeIcons.whatsapp,
                          color: Color(0xFF25D366),
                          size: 15,
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
                SizedBox(width: 340, child: selector),
                const SizedBox(width: 12),
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
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
      itemCount: _students.length,
      itemBuilder: (context, index) {
        final student = _students[index];
        final controller = _markControllers[student.id]!;
        final focusNode = _markFocusNodes[student.id]!;
        final isLast = index == _students.length - 1;

        final savedText = student.isAbsent
            ? 'Saved: Absent'
            : student.savedMarks == null
            ? 'Mark not entered'
            : 'Saved: ${_formatNumber(student.savedMarks!)}'
                  ' / ${_formatNumber(maxMarks)}';

        final savedColor = student.isAbsent
            ? AppTheme.danger
            : student.savedMarks == null
            ? AppTheme.textSecondary
            : AppTheme.success;

        final markInput = TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          maxLength: 6,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: 'Marks',
            suffixText: '/ ${_formatNumber(maxMarks)}',
            counterText: '',
            isDense: true,
          ),
          onTap: () {
            if (controller.text.toUpperCase() == 'A') {
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
          onChanged: (value) {
            _handleMarksChanged(student, value);
          },
          onFieldSubmitted: (_) {
            if (isLast) {
              focusNode.unfocus();
            } else {
              _focusNextStudent(student.id);
            }
          },
        );

        final absentButton = ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final absent = value.text.trim().toUpperCase() == 'A';

            return SizedBox(
              width: 49,
              height: 48,
              child: OutlinedButton(
                onPressed: _saving ? null : () => _markAbsent(student),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: absent
                      ? AppTheme.danger.withValues(alpha: 0.10)
                      : null,
                  side: BorderSide(
                    color: absent ? AppTheme.danger : AppTheme.border,
                  ),
                ),
                child: Text(
                  'A',
                  style: TextStyle(
                    color: absent ? AppTheme.danger : AppTheme.fgNavyBlue,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          },
        );

        final inputs = Row(
          children: [
            Expanded(child: markInput),
            const SizedBox(width: 7),
            absentButton,
            if (student.savedMarks != null || student.isAbsent)
              IconButton(
                tooltip: 'Clear saved result',
                onPressed: _saving ? null : () => _clearMark(student),
                color: AppTheme.danger,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        );

        final studentInfo = Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.fgNavyBlue.withValues(alpha: 0.08),
              foregroundColor: AppTheme.fgNavyBlue,
              child: Text(
                '${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
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
                  const SizedBox(height: 3),
                  Text(
                    savedText,
                    style: TextStyle(fontSize: 12, color: savedColor),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Student actions',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) {
                if (action == 'edit') {
                  _editAwardStudent(student);
                } else if (action == 'archive') {
                  _archiveAwardStudent(student);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Text('Edit Student'),
                ),
                if (_isAdmin)
                  const PopupMenuItem<String>(
                    value: 'archive',
                    child: Text('Archive Student'),
                  ),
              ],
            ),
          ],
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [studentInfo, const SizedBox(height: 10), inputs],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: studentInfo),
                    const SizedBox(width: 12),
                    SizedBox(width: 270, child: inputs),
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
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_students.length} students'
                '${_pendingMarkDrafts.isEmpty ? '' : ' • Unsaved changes'}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _saving || _pendingMarkDrafts.isEmpty
                  ? null
                  : _saveMarks,
              icon: _saving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
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
