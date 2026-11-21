import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_theme.dart';
import '../../models/fee_models.dart';
import '../../services/student_creation_service.dart';
import '../../services/student_profile_service.dart';
import '../../utils/error_state_view.dart';
import '../../utils/list_sorting.dart';
import '../../utils/student_group_helper.dart';
import '../../widgets/academy_background.dart';
import '../../widgets/add_student_dialog.dart';
import '../../widgets/student_subject_selector.dart';
import '../../widgets/student_profile_link.dart';
import '../../widgets/student_profile_edit_dialog.dart';
import '../../widgets/student_stream_badge.dart';
import '../../widgets/student_tracking_badges.dart';
import 'archive_students_view.dart';

// ============================================================
// ADMIN STUDENTS: ACTIVE BATCHES + ARCHIVE
// ============================================================

class StudentsTab extends StatefulWidget {
  final Function(Widget screen)? onNavigate;
  final VoidCallback? onBack;

  const StudentsTab({super.key, this.onNavigate, this.onBack});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> batches = [];
  List<dynamic> students = [];
  Set<String> _longAbsenceStudentIds = {};
  bool isLoading = true;
  bool _addingStudent = false;
  String? errorMessage;
  bool _archiveMode = false;
  String? _selectedBatchId;
  String _selectedFilter = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    fetchBatches();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetchAttendanceSince(String startDate) async {
    final rows = <dynamic>[];
    for (var offset = 0; ; offset += 1000) {
      final page = await supabase
          .from('attendance')
          .select('student_id,date,status')
          .gte('date', startDate)
          .order('date', ascending: false)
          .range(offset, offset + 999);
      rows.addAll(page);
      if (page.length < 1000) return rows;
    }
  }

  Future<void> fetchBatches() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }
    try {
      final historyStart = DateTime.now()
          .subtract(const Duration(days: 21))
          .toIso8601String()
          .split('T')
          .first;
      final results = await Future.wait<dynamic>([
        supabase.from('batches').select('id, name, class_level'),
        supabase
            .from('students')
            .select(
              'id,name,batch_id,stream,status,default_fee,'
              'created_at,contact_number',
            )
            .eq('is_archived', false),
        _fetchAttendanceSince(historyStart),
      ]);

      final batchRows = results[0];
      final studentRows = results[1];
      final attendanceRows = results[2];

      final counts = <String, int>{};
      final history = <String, List<Map<String, dynamic>>>{};

      for (final student in studentRows) {
        final id = student['batch_id']?.toString();

        if (id != null) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }

      for (final rawRow in attendanceRows) {
        final row = Map<String, dynamic>.from(rawRow as Map);
        final studentId = row['student_id']?.toString();
        if (studentId == null) continue;
        history.putIfAbsent(studentId, () => []).add(row);
      }

      final longAbsences = <String>{};
      for (final entry in history.entries) {
        entry.value.sort(
          (a, b) => b['date'].toString().compareTo(a['date'].toString()),
        );
        var streak = 0;
        for (final row in entry.value) {
          final status = row['status']?.toString();
          if (status == 'absent') {
            streak++;
            if (streak >= 4) {
              longAbsences.add(entry.key);
              break;
            }
          } else if (status == 'present') {
            break;
          }
        }
      }

      final mapped = batchRows.map((batch) {
        final copy = Map<String, dynamic>.from(batch);
        copy['student_count'] = counts[batch['id'].toString()] ?? 0;
        return copy;
      }).toList();

      if (!mounted) return;

      setState(() {
        batches = sortBatches(mapped);
        students = sortStudents(studentRows);
        _longAbsenceStudentIds = longAbsences;
        if (_selectedBatchId != null &&
            !batches.any(
              (batch) => batch['id'].toString() == _selectedBatchId,
            )) {
          _selectedBatchId = null;
        }
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Student batches error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = 'Unable to load students.';
      });
    }
  }

  List<String> _subjects(dynamic raw) =>
      raw is List ? raw.map((item) => item.toString()).toList() : const [];

  Map<String, dynamic>? _batchForStudent(dynamic student) {
    final batchId = student['batch_id']?.toString();
    for (final rawBatch in batches) {
      if (rawBatch['id'].toString() == batchId) {
        return Map<String, dynamic>.from(rawBatch as Map);
      }
    }
    return null;
  }

  bool _isNewAdmission(dynamic student) {
    final created = DateTime.tryParse(
      student['created_at']?.toString() ?? '',
    )?.toLocal();
    if (created == null) return false;
    final now = DateTime.now();
    final age = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(created.year, created.month, created.day)).inDays;
    return age >= 0 && age < 7;
  }

  bool _matchesFilter(dynamic student) {
    if (_selectedFilter == 'All') return true;
    final subjects = _subjects(student['stream']);
    final batch = _batchForStudent(student);
    final classLevel = (batch?['class_level'] as num?)?.toInt() ?? 0;
    final groupCode = inferStudentGroupCode(classLevel, subjects);

    return switch (_selectedFilter) {
      'New Admissions' => _isNewAdmission(student),
      'Missing Contact' =>
        (student['contact_number']?.toString().trim() ?? '').isEmpty,
      'Attendance Alert' => _longAbsenceStudentIds.contains(
        student['id']?.toString(),
      ),
      'Computer / FCS' => groupCode == 'Comp',
      'Biology / Pre-Med' => groupCode == 'Bio',
      'Pre-Engineering' => groupCode == 'Chem',
      'Custom / Single Subject' => groupCode == null,
      _ => true,
    };
  }

  bool _matchesSearch(dynamic student) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final text = '${student['name']} ${student['contact_number'] ?? ''}'
        .toLowerCase();
    return text.contains(query);
  }

  List<dynamic> _studentsForBatch(String batchId) => students.where((student) {
    return student['batch_id']?.toString() == batchId &&
        _matchesFilter(student) &&
        _matchesSearch(student);
  }).toList();

  String _tabLabel(dynamic batch) {
    final name = batch['name']?.toString() ?? '';
    return name.replaceAll('th Boys', 'B').replaceAll('th Girls', 'G');
  }

  Future<void> _chooseFilter() async {
    const filters = [
      'All',
      'New Admissions',
      'Missing Contact',
      'Attendance Alert',
      'Computer / FCS',
      'Biology / Pre-Med',
      'Pre-Engineering',
      'Custom / Single Subject',
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: RadioGroup<String>(
          groupValue: _selectedFilter,
          onChanged: (value) => Navigator.pop(sheetContext, value),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            children: [
              const ListTile(
                title: Text(
                  'Filter students',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Filters stay out of the main screen until used.',
                ),
              ),
              for (final filter in filters)
                RadioListTile<String>(value: filter, title: Text(filter)),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedFilter = selected);
    }
  }

  Future<void> _addStudent() async {
    if (_addingStudent || batches.isEmpty) return;
    final available = batches.map((raw) {
      return FeeBatch(
        id: raw['id'].toString(),
        name: raw['name']?.toString() ?? 'Batch',
        classLevel: (raw['class_level'] as num?)?.toInt() ?? 0,
      );
    }).toList();
    final initial = _selectedBatchId == null
        ? available.first
        : available.firstWhere(
            (batch) => batch.id == _selectedBatchId,
            orElse: () => available.first,
          );
    final request = await showAcademyAddStudentDialog(
      context: context,
      batches: available,
      initialBatch: initial,
      paymentMonth: '',
      lockBatch: _selectedBatchId != null,
    );
    if (!mounted || request == null) return;

    setState(() => _addingStudent = true);
    try {
      await StudentCreationService(supabase).create(
        name: request.name,
        batchId: request.batch.id,
        groupCode: request.groupCode,
        contact: request.contact,
      );
      _searchController.clear();
      _searchQuery = '';
      await fetchBatches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${request.name} added successfully.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to add student.\n$error'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _addingStudent = false);
    }
  }

  Future<void> _archiveStudent(dynamic student) async {
    final name = student['name']?.toString() ?? 'Student';
    String reason = 'Left academy';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive Student?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Archive "$name"? Historical records will be preserved.'),
            const SizedBox(height: 14),
            TextField(
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Left academy',
              ),
              onChanged: (value) => reason = value,
            ),
          ],
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
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase.rpc(
        'archive_student',
        params: {
          'p_student_id': student['id'],
          'p_reason': reason.trim().isEmpty ? 'Left academy' : reason.trim(),
        },
      );
      await fetchBatches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student archived. Historical records preserved.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive failed: $error'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _editStudent(dynamic student) async {
    final batchRows = batches
        .map((batch) => Map<String, dynamic>.from(batch as Map))
        .toList();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudentProfileEditDialog(
        student: Map<String, dynamic>.from(student as Map),
        batches: batchRows,
        service: StudentProfileService(client: supabase),
      ),
    );
    if (saved == true && mounted) {
      await fetchBatches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student updated.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return ErrorStateView(message: errorMessage!, onRetry: fetchBatches);
    }

    final visibleBatches = _selectedBatchId == null
        ? batches
        : batches
              .where((batch) => batch['id'].toString() == _selectedBatchId)
              .toList();
    final hasActiveFilter = _selectedFilter != 'All';
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final groups = <({dynamic batch, List<dynamic> students})>[];
    for (final batch in visibleBatches) {
      final rows = _studentsForBatch(batch['id'].toString());
      if (rows.isNotEmpty || (!hasSearch && !hasActiveFilter)) {
        groups.add((batch: batch, students: rows));
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: _archiveMode
                    ? const Text(
                        'Archived Students',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() {
                          _searchQuery = value;
                        }),
                        decoration: InputDecoration(
                          hintText: 'Search all students',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          isDense: true,
                        ),
                      ),
              ),
              const SizedBox(width: 4),
              if (!_archiveMode)
                IconButton.filledTonal(
                  tooltip: hasActiveFilter
                      ? 'Filter: $_selectedFilter'
                      : 'Filter students',
                  onPressed: _chooseFilter,
                  color: hasActiveFilter
                      ? AppTheme.fgNavyBlue
                      : AppTheme.textSecondary,
                  icon: Icon(
                    hasActiveFilter
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_outlined,
                  ),
                ),
              if (!_archiveMode)
                IconButton.filled(
                  tooltip: 'Add student',
                  onPressed: _addingStudent ? null : _addStudent,
                  icon: _addingStudent
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                ),
              IconButton(
                tooltip: _archiveMode ? 'Show active students' : 'Show archive',
                onPressed: () => setState(() => _archiveMode = !_archiveMode),
                icon: Icon(
                  _archiveMode
                      ? Icons.groups_2_rounded
                      : Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
        ),
        if (!_archiveMode)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _selectedBatchId == null,
                    onSelected: (_) => setState(() => _selectedBatchId = null),
                  ),
                ),
                for (final batch in batches)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      tooltip: batch['name']?.toString(),
                      label: Text(_tabLabel(batch)),
                      selected: _selectedBatchId == batch['id'].toString(),
                      onSelected: (_) => setState(
                        () => _selectedBatchId = batch['id'].toString(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (!_archiveMode && hasActiveFilter)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 3),
              child: InputChip(
                visualDensity: VisualDensity.compact,
                label: Text(_selectedFilter),
                avatar: const Icon(Icons.filter_alt_rounded, size: 17),
                onDeleted: () => setState(() => _selectedFilter = 'All'),
              ),
            ),
          ),
        Expanded(
          child: _archiveMode
              ? ArchiveStudentsView(
                  onRestored: fetchBatches,
                  onBack: () => setState(() => _archiveMode = false),
                )
              : RefreshIndicator(
                  onRefresh: fetchBatches,
                  child: groups.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          children: const [
                            SizedBox(height: 70),
                            Icon(
                              Icons.person_search_rounded,
                              size: 54,
                              color: AppTheme.textSecondary,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No matching students found.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            for (final group in groups) ...[
                              SliverToBoxAdapter(
                                child: Container(
                                  margin: const EdgeInsets.fromLTRB(
                                    10,
                                    10,
                                    10,
                                    5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.fgNavyBlue.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.groups_2_rounded,
                                        size: 20,
                                        color: AppTheme.fgNavyBlue,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          group.batch['name']?.toString() ??
                                              'Class',
                                          style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${group.students.length}',
                                        style: const TextStyle(
                                          color: AppTheme.fgNavyBlue,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (group.students.isEmpty)
                                const SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(24, 5, 24, 10),
                                    child: Text(
                                      'No active students in this class.',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  sliver: SliverList.builder(
                                    itemCount: group.students.length,
                                    itemBuilder: (context, index) {
                                      final student = group.students[index];
                                      final classLevel =
                                          (group.batch['class_level'] as num?)
                                              ?.toInt();
                                      return Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          leading: CircleAvatar(
                                            radius: 18,
                                            backgroundColor: AppTheme.fgNavyBlue
                                                .withValues(alpha: 0.10),
                                            child: Text(
                                              '${index + 1}',
                                              style: const TextStyle(
                                                color: AppTheme.fgNavyBlue,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          title: StudentProfileLink(
                                            studentId: student['id'].toString(),
                                            name:
                                                student['name']?.toString() ??
                                                'Student',
                                            style: const TextStyle(
                                              color: AppTheme.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: StudentTrackingBadges(
                                            student: student,
                                            classLevel: classLevel,
                                            longAbsent: _longAbsenceStudentIds
                                                .contains(
                                                  student['id']?.toString(),
                                                ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Edit student',
                                                onPressed: () =>
                                                    _editStudent(student),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 20,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Archive student',
                                                onPressed: () =>
                                                    _archiveStudent(student),
                                                icon: const Icon(
                                                  Icons.archive_outlined,
                                                  size: 21,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 24),
                            ),
                          ],
                        ),
                ),
        ),
      ],
    );
  }
}

// ============================================================
// INDIVIDUAL BATCH STUDENTS
// ============================================================

class BatchStudentsScreen extends StatefulWidget {
  final String batchId;
  final String batchName;
  final int classLevel;
  final VoidCallback? onBack;

  const BatchStudentsScreen({
    super.key,
    required this.batchId,
    required this.batchName,
    required this.classLevel,
    this.onBack,
  });

  @override
  State<BatchStudentsScreen> createState() => _BatchStudentsScreenState();
}

class _BatchStudentsScreenState extends State<BatchStudentsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<dynamic> students = [];
  Set<String> _longAbsenceStudentIds = {};
  bool isLoading = true;
  String? errorMessage;

  String selectedFilter = 'All';

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  bool _showSearch = false;
  bool _addingStudent = false;

  @override
  void initState() {
    super.initState();
    fetchStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get filters {
    if (widget.classLevel == 9 || widget.classLevel == 10) {
      return const [
        'All',
        'New Admissions',
        'Missing Contact',
        'Attendance Alert',
        'Computer',
        'Biology',
        'Single Subject',
      ];
    }

    if (widget.classLevel == 11 || widget.classLevel == 12) {
      return const [
        'All',
        'New Admissions',
        'Missing Contact',
        'Attendance Alert',
        'Computer',
        'Biology',
        'Chemistry',
        'Single Subject',
      ];
    }

    return const ['All'];
  }

  List<String> _subjects(dynamic raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).toList();
    }
    return [];
  }

  bool _matchesFilter(dynamic student) {
    if (selectedFilter == 'All') return true;

    final subjects = _subjects(student['stream']);

    switch (selectedFilter) {
      case 'New Admissions':
        return _isNewAdmission(student);
      case 'Missing Contact':
        return _isContactMissing(student);
      case 'Attendance Alert':
        return _longAbsenceStudentIds.contains(student['id']?.toString());
      case 'Computer':
        return subjects.contains('Comp');
      case 'Biology':
        return subjects.contains('Bio');
      case 'Chemistry':
        return subjects.contains('Chem');
      case 'Single Subject':
        return subjects.length == 1;
      default:
        return true;
    }
  }

  bool _isNewAdmission(dynamic student) {
    final created = DateTime.tryParse(
      student['created_at']?.toString() ?? '',
    )?.toLocal();
    if (created == null) return false;

    final now = DateTime.now();
    final createdDay = DateTime(created.year, created.month, created.day);
    final today = DateTime(now.year, now.month, now.day);
    final ageInDays = today.difference(createdDay).inDays;
    return ageInDays >= 0 && ageInDays < 7;
  }

  bool _isContactMissing(dynamic student) =>
      (student['contact_number']?.toString().trim() ?? '').isEmpty;

  List<Widget> _trackingBadges(dynamic student) {
    final badges = <Widget>[];

    if (_isNewAdmission(student)) {
      badges.add(
        const _StudentTrackingBadge(
          label: 'NEW',
          icon: Icons.fiber_new_rounded,
          color: AppTheme.info,
          tooltip: 'New admission: joined within the last 7 days',
        ),
      );
    }
    if (_isContactMissing(student)) {
      badges.add(
        const _StudentTrackingBadge(
          label: 'NO CONTACT',
          icon: Icons.phone_disabled_outlined,
          color: AppTheme.warning,
          tooltip: 'Parent or guardian contact number is missing',
        ),
      );
    }
    if (_longAbsenceStudentIds.contains(student['id']?.toString())) {
      badges.add(
        const _StudentTrackingBadge(
          label: '4+ ABSENT',
          icon: Icons.warning_amber_rounded,
          color: AppTheme.danger,
          tooltip: 'Latest recorded attendance has 4 or more absences in a row',
        ),
      );
    }

    return badges;
  }

  List<dynamic> get visibleStudents {
    final query = _searchQuery.trim().toLowerCase();

    return students.where((student) {
      if (!_matchesFilter(student)) return false;

      if (query.isEmpty) return true;

      final studentName =
          student['name']?.toString().trim().toLowerCase() ?? '';

      return studentName.contains(query);
    }).toList();
  }

  Future<void> fetchStudents() async {
    try {
      final historyStart = DateTime.now()
          .subtract(const Duration(days: 60))
          .toIso8601String()
          .split('T')
          .first;
      final results = await Future.wait([
        supabase
            .from('students')
            .select(
              'id, name, stream, status, default_fee, '
              'created_at, contact_number',
            )
            .eq('batch_id', widget.batchId)
            .eq('is_archived', false)
            .order('name', ascending: true),
        supabase
            .from('attendance')
            .select('student_id, date, status')
            .eq('batch_id', widget.batchId)
            .gte('date', historyStart)
            .order('date', ascending: false),
      ]);

      final response = results[0];
      final activeIds = response
          .map((student) => student['id']?.toString())
          .whereType<String>()
          .toSet();
      final history = <String, List<Map<String, dynamic>>>{};

      for (final rawRow in results[1]) {
        final row = Map<String, dynamic>.from(rawRow);
        final id = row['student_id']?.toString();
        if (id == null || !activeIds.contains(id)) continue;
        history.putIfAbsent(id, () => []).add(row);
      }

      final longAbsences = <String>{};
      for (final entry in history.entries) {
        var streak = 0;
        for (final row in entry.value) {
          final status = row['status']?.toString();
          if (status == 'absent') {
            streak++;
            if (streak >= 4) {
              longAbsences.add(entry.key);
              break;
            }
          } else if (status == 'present') {
            break;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        students = sortStudents(response);
        _longAbsenceStudentIds = longAbsences;
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint('Students load error: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = 'Unable to load students.';
      });
    }
  }

  // ==========================================================
  // ADD STUDENT - COMPACT FORM / MANDATORY STREAM
  // ==========================================================

  Future<void> _addStudentFromStudentsTab() async {
    if (_addingStudent) return;

    final batch = FeeBatch(
      id: widget.batchId,
      name: widget.batchName,
      classLevel: widget.classLevel,
    );

    final request = await showAcademyAddStudentDialog(
      context: context,
      batches: [batch],
      initialBatch: batch,
      paymentMonth: '',
      lockBatch: true,
    );

    if (!mounted || request == null) return;

    setState(() => _addingStudent = true);

    try {
      await StudentCreationService(supabase).create(
        name: request.name,
        batchId: request.batch.id,
        groupCode: request.groupCode,
        contact: request.contact,
      );

      if (!mounted) return;

      _searchController.clear();

      setState(() {
        _searchQuery = '';
        _showSearch = false;
        selectedFilter = 'All';
      });

      await fetchStudents();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${request.name} added successfully.\n'
            'Today attendance: Present\n'
            'Student is ready for attendance.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      debugPrint('Students add error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to add student.\n$e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _addingStudent = false);
      }
    }
  }

  // ==========================================================
  // EDIT STUDENT - EXISTING SUBJECT EDITING PRESERVED
  // ==========================================================

  Future<void> _editStudent(Map<String, dynamic> student) async {
    final controller = TextEditingController(
      text: student['name']?.toString() ?? '',
    );
    final contactController = TextEditingController(
      text: student['contact_number']?.toString() ?? '',
    );

    var selectedSubjects = normalizeStudentSubjects(
      widget.classLevel,
      _subjects(student['stream']),
    );

    String status = student['status']?.toString() == 'trial'
        ? 'trial'
        : 'enrolled';

    String? dialogError;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Student'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: controller,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Student Name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: contactController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Parent Contact (optional)',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'enrolled',
                            child: Text('Enrolled'),
                          ),
                          DropdownMenuItem(
                            value: 'trial',
                            child: Text('Trial'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;

                          setDialogState(() {
                            status = value;
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      StudentSubjectSelector(
                        classLevel: widget.classLevel,
                        selectedSubjects: selectedSubjects,
                        onChanged: (subjects) {
                          setDialogState(() {
                            selectedSubjects = subjects;
                            dialogError = null;
                          });
                        },
                        onValidationError: (message) {
                          setDialogState(() {
                            dialogError = message;
                          });
                        },
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
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (controller.text.trim().isEmpty) {
                      setDialogState(() {
                        dialogError = 'Student name is required.';
                      });
                      return;
                    }

                    final contact = contactController.text.trim().replaceAll(
                      RegExp(r'[\s()\-]'),
                      '',
                    );
                    if (contact.isNotEmpty &&
                        !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(contact)) {
                      setDialogState(() {
                        dialogError = 'Please enter a valid contact number.';
                      });
                      return;
                    }

                    final validation = studentSubjectSelectionError(
                      widget.classLevel,
                      selectedSubjects,
                    );

                    if (validation != null) {
                      setDialogState(() {
                        dialogError = validation;
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    final name = controller.text.trim();
    final contact = contactController.text.trim().replaceAll(
      RegExp(r'[\s()\-]'),
      '',
    );
    controller.dispose();
    contactController.dispose();

    if (confirmed != true) return;

    setState(() => isLoading = true);

    try {
      await StudentProfileService(client: supabase).saveProfile(
        studentId: student['id'].toString(),
        name: name,
        batchId: widget.batchId,
        status: status,
        subjects: selectedSubjects,
        contact: contact.isEmpty ? null : contact,
      );

      await fetchStudents();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student updated.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      debugPrint('Student update error: $e');

      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update student.\n$e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  // ==========================================================
  // ARCHIVE INSTEAD OF PERMANENT DELETE
  // ==========================================================

  Future<void> _archiveStudent(dynamic student) async {
    final name = student['name']?.toString() ?? 'Student';
    String reason = 'Left academy';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Archive Student?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Archive "$name"?\n\n'
                  'Historical attendance and award marks '
                  'will be preserved.',
                ),
                const SizedBox(height: 14),
                TextField(
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'Left academy',
                  ),
                  onChanged: (value) => reason = value,
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await supabase.rpc(
        'archive_student',
        params: {
          'p_student_id': student['id'],
          'p_reason': reason.trim().isEmpty ? 'Left academy' : reason.trim(),
        },
      );

      if (!mounted) return;

      await fetchStudents();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student archived. Historical records preserved.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archive failed: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  // ==========================================================
  // STUDENTS LIST UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final visible = visibleStudents;
    final narrow = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.batchName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: _showSearch
                ? 'Close student search'
                : 'Search student by name',
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;

                if (!_showSearch) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Add Student',
            onPressed: _addingStudent ? null : _addStudentFromStudentsTab,
            icon: _addingStudent
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
          ),
          if (!narrow)
            IconButton(
              tooltip: 'Refresh Students',
              onPressed: fetchStudents,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: AcademyBackground(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
            ? ErrorStateView(message: errorMessage!, onRetry: fetchStudents)
            : RefreshIndicator(
                onRefresh: fetchStudents,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (_showSearch)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(9, 8, 9, 0),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Search student by name',
                                isDense: true,
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _searchQuery.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        onPressed: () {
                                          _searchController.clear();

                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(9, 8, 9, 5),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: narrow
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          key: ValueKey(selectedFilter),
                                          initialValue: selectedFilter,
                                          decoration: const InputDecoration(
                                            labelText: 'Filter Students',
                                            prefixIcon: Icon(
                                              Icons.filter_alt_outlined,
                                            ),
                                            isDense: true,
                                          ),
                                          items: filters
                                              .map(
                                                (filter) => DropdownMenuItem(
                                                  value: filter,
                                                  child: Text(filter),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) {
                                            if (value == null) {
                                              return;
                                            }

                                            setState(() {
                                              selectedFilter = value;
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 55,
                                        ),
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.fgGold.withValues(
                                            alpha: 0.16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          '${visible.length}',
                                          style: const TextStyle(
                                            color: AppTheme.fgNavyBlue,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text(
                                            'Student Filter',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${visible.length} of ${students.length}',
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 9),
                                      Wrap(
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: filters
                                            .map(
                                              (filter) => FilterChip(
                                                selected:
                                                    filter == selectedFilter,
                                                label: Text(filter),
                                                onSelected: (_) {
                                                  setState(() {
                                                    selectedFilter = filter;
                                                  });
                                                },
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (visible.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _searchQuery.trim().isNotEmpty
                                  ? 'No matching student found in ${widget.batchName}.'
                                  : 'No students match this filter.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(9, 5, 9, 25),
                        sliver: SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final student = visible[index];

                            final subjects = _subjects(student['stream']);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppTheme.fgNavyBlue.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: AppTheme.fgNavyBlue,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 5,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                StudentProfileLink(
                                                  studentId: student['id']
                                                      .toString(),
                                                  name:
                                                      student['name']
                                                          ?.toString() ??
                                                      'Student',
                                                  style: const TextStyle(
                                                    color: AppTheme.textPrimary,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                StudentStreamBadge(
                                                  classLevel: widget.classLevel,
                                                  subjects: subjects,
                                                ),
                                                ..._trackingBadges(student),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              subjects
                                                  .map(studentSubjectLabel)
                                                  .join(' • '),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit',
                                        onPressed: () => _editStudent(
                                          Map<String, dynamic>.from(student),
                                        ),
                                        icon: const Icon(Icons.edit_outlined),
                                        color: AppTheme.fgNavyBlue,
                                      ),
                                      IconButton(
                                        tooltip: 'Archive',
                                        onPressed: () =>
                                            _archiveStudent(student),
                                        icon: const Icon(
                                          Icons.archive_outlined,
                                        ),
                                        color: AppTheme.danger,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _StudentTrackingBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String tooltip;

  const _StudentTrackingBadge({
    required this.label,
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.25,
            ),
          ),
        ],
      ),
    ),
  );
}
