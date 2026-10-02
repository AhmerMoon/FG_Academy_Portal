import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_theme.dart';
import '../../utils/dashboard_section_header.dart';
import '../../utils/error_state_view.dart';
import '../../utils/list_sorting.dart';
import '../../widgets/academy_background.dart';

class StudentsTab extends StatefulWidget {
  final Function(Widget screen)? onNavigate;
  final VoidCallback? onBack;

  const StudentsTab({super.key, this.onNavigate, this.onBack});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<dynamic> batches = [];

  bool isLoading = true;

  String? errorMessage;

  @override
  void initState() {
    super.initState();

    fetchBatches();
  }

  Future<void> fetchBatches() async {
    try {
      final results = await Future.wait([
        supabase.from('batches').select('id, name, class_level'),

        supabase.from('students').select('batch_id'),
      ]);

      final batchRows = results[0];

      final studentRows = results[1];

      final counts = <String, int>{};

      for (final student in studentRows) {
        final id = student['batch_id']?.toString();

        if (id != null) {
          counts[id] = (counts[id] ?? 0) + 1;
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

  void _openBatch(Map<String, dynamic> batch) {
    final id = batch['id'].toString();

    final name = batch['name']?.toString() ?? 'Batch';

    final classLevel = (batch['class_level'] as num?)?.toInt() ?? 0;

    if (widget.onNavigate != null && widget.onBack != null) {
      widget.onNavigate!(
        BatchStudentsScreen(
          batchId: id,
          batchName: name,
          classLevel: classLevel,
          onBack: widget.onBack,
        ),
      );

      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => BatchStudentsScreen(
              batchId: id,
              batchName: name,
              classLevel: classLevel,
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            fetchBatches();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return ErrorStateView(message: errorMessage!, onRetry: fetchBatches);
    }

    return RefreshIndicator(
      onRefresh: fetchBatches,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: DashboardSectionHeader(
              title: 'Students',
              subtitle: 'Active academy students by batch',
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(9, 6, 9, 24),
            sliver: SliverList.builder(
              itemCount: batches.length,
              itemBuilder: (context, index) {
                final batch = Map<String, dynamic>.from(batches[index]);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openBatch(batch),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: AppTheme.brandGradient,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.groups_2_rounded,
                                color: Colors.white,
                                size: 27,
                              ),
                            ),

                            const SizedBox(width: 13),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    batch['name']?.toString() ?? 'Batch',
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  Text(
                                    '${batch['student_count'] ?? 0} students',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.fgNavyBlue,
                              size: 27,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BATCH STUDENTS SCREEN
// =============================================================================

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

  bool isLoading = true;

  String? errorMessage;

  String selectedFilter = 'All';

  @override
  void initState() {
    super.initState();

    fetchStudents();
  }

  List<String> get filters {
    if (widget.classLevel == 9 || widget.classLevel == 10) {
      return const ['All', 'Computer', 'Biology'];
    }

    if (widget.classLevel == 11) {
      return const ['All', 'FCS', 'Pre-Med', 'Pre-Eng'];
    }

    if (widget.classLevel == 12) {
      return const ['All', 'FCS', 'Pre-Med', 'Pre-Eng', 'Single Subject'];
    }

    return const ['All'];
  }

  List<String> _subjects(dynamic raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).toList();
    }

    return [];
  }

  String _subjectLabel(String code) {
    switch (code) {
      case 'Phy':
        return 'Physics';

      case 'Chem':
        return 'Chemistry';

      case 'Math':
        return 'Math';

      case 'Eng':
        return 'English';

      case 'Comp':
        return 'Computer';

      case 'Bio':
        return 'Biology';

      default:
        return code;
    }
  }

  bool _matchesFilter(dynamic student) {
    if (selectedFilter == 'All') {
      return true;
    }

    final subjects = _subjects(student['stream']);

    if (selectedFilter == 'Single Subject') {
      return subjects.length == 1;
    }

    if (subjects.length == 1) {
      return false;
    }

    switch (selectedFilter) {
      case 'Computer':
      case 'FCS':
        return subjects.contains('Comp');

      case 'Biology':
      case 'Pre-Med':
        return subjects.contains('Bio');

      case 'Pre-Eng':
        return subjects.contains('Chem');

      default:
        return true;
    }
  }

  List<dynamic> get visibleStudents => students.where(_matchesFilter).toList();

  Future<void> fetchStudents() async {
    try {
      final response = await supabase
          .from('students')
          .select('id, name, stream, status, default_fee')
          .eq('batch_id', widget.batchId)
          .order('name', ascending: true);

      if (!mounted) return;

      setState(() {
        students = sortStudents(response);

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

  Future<void> _editStudent(Map<String, dynamic> student) async {
    final controller = TextEditingController(
      text: student['name']?.toString() ?? '',
    );

    final existingSubjects = _subjects(student['stream']);

    Set<String> selectedBaseSubjects = {};
    String? selectedChoiceSubject;

    if (widget.classLevel == 9 || widget.classLevel == 10) {
      selectedBaseSubjects = existingSubjects
          .where(
            (subject) => const {'Phy', 'Chem', 'Math', 'Eng'}.contains(subject),
          )
          .toSet();

      if (existingSubjects.contains('Comp')) {
        selectedChoiceSubject = 'Comp';
      } else if (existingSubjects.contains('Bio')) {
        selectedChoiceSubject = 'Bio';
      }
    } else {
      selectedBaseSubjects = existingSubjects
          .where((subject) => const {'Phy', 'Math', 'Eng'}.contains(subject))
          .toSet();

      if (existingSubjects.contains('Chem')) {
        selectedChoiceSubject = 'Chem';
      } else if (existingSubjects.contains('Comp')) {
        selectedChoiceSubject = 'Comp';
      } else if (existingSubjects.contains('Bio')) {
        selectedChoiceSubject = 'Bio';
      }
    }

    String status = student['status']?.toString() == 'trial'
        ? 'trial'
        : 'enrolled';
    List<String> selectedSubjectsForSave = [];
    String? dialogError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final baseSubjects = widget.classLevel <= 10
                ? const ['Phy', 'Chem', 'Math', 'Eng']
                : const ['Phy', 'Math', 'Eng'];
            final choiceSubjects = widget.classLevel <= 10
                ? const ['Comp', 'Bio']
                : const ['Chem', 'Comp', 'Bio'];

            Widget subjectCheckbox(String code, {required bool exclusive}) {
              final checked = exclusive
                  ? selectedChoiceSubject == code
                  : selectedBaseSubjects.contains(code);

              return CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
                value: checked,
                title: Text(
                  _subjectLabel(code),
                  style: const TextStyle(fontSize: 14),
                ),
                onChanged: (value) {
                  if (exclusive) {
                    if (value == true) {
                      setDialogState(() {
                        selectedChoiceSubject = code;
                        dialogError = null;
                      });
                    }
                    return;
                  }

                  setDialogState(() {
                    if (value == true) {
                      selectedBaseSubjects.add(code);
                    } else {
                      selectedBaseSubjects.remove(code);
                    }

                    dialogError = null;
                  });
                },
              );
            }

            return AlertDialog(
              title: const Text('Edit Student'),
              content: SizedBox(
                width: 430,
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

                      DropdownButtonFormField<String>(
                        key: ValueKey(status),
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
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            status = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.fgNavyBlue.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Core Subjects',
                              style: TextStyle(
                                color: AppTheme.fgNavyBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth >= 520
                                    ? (constraints.maxWidth - 8) / 2
                                    : constraints.maxWidth;

                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 2,
                                  children: baseSubjects
                                      .map(
                                        (code) => SizedBox(
                                          width: width,
                                          child: subjectCheckbox(
                                            code,
                                            exclusive: false,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.classLevel <= 10
                                  ? 'Choose Biology / Computer'
                                  : 'Choose Group Subject',
                              style: const TextStyle(
                                color: AppTheme.fgNavyBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth >= 520
                                    ? (constraints.maxWidth - 8) / 2
                                    : constraints.maxWidth;

                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 2,
                                  children: choiceSubjects
                                      .map(
                                        (code) => SizedBox(
                                          width: width,
                                          child: subjectCheckbox(
                                            code,
                                            exclusive: true,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          dialogError!,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w600,
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

                    const subjectOrder = [
                      'Phy',
                      'Chem',
                      'Math',
                      'Eng',
                      'Comp',
                      'Bio',
                    ];
                    final selectedSubjects = <String>{
                      ...selectedBaseSubjects,
                      if (selectedChoiceSubject != null) selectedChoiceSubject!,
                    };
                    final subjects = subjectOrder
                        .where(selectedSubjects.contains)
                        .toList();

                    if (subjects.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Select at least one subject.';
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, true);

                    selectedSubjectsForSave = subjects;
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
    final subjects = selectedSubjectsForSave;

    controller.dispose();

    if (confirmed != true) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await supabase.rpc(
        'admin_update_student_details',
        params: {
          'p_student_id': student['id'].toString(),
          'p_name': name,
          'p_status': status,
          'p_stream': subjects,
        },
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
      debugPrint('Student update: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update student.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _deleteStudent(dynamic student) async {
    final name = student['name']?.toString() ?? 'Student';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Student?'),
          content: Text(
            'Delete "$name"? Linked attendance and fee records may also be removed.',
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
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await supabase.from('students').delete().eq('id', student['id']);

      await fetchStudents();
    } catch (e) {
      debugPrint('Delete student: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

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
        title: Text(widget.batchName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
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
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'No students match this filter.',
                            style: TextStyle(fontSize: 15),
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
                                            Text(
                                              student['name']?.toString() ??
                                                  'Student',
                                              style: const TextStyle(
                                                color: AppTheme.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),

                                            const SizedBox(height: 4),

                                            Text(
                                              subjects
                                                  .map(_subjectLabel)
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
                                        tooltip: 'Delete',
                                        onPressed: () =>
                                            _deleteStudent(student),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
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
