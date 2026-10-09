import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/student_group_helper.dart';
import '../../app_theme.dart';
import '../../utils/dashboard_section_header.dart';
import '../../utils/error_state_view.dart';
import '../../utils/list_sorting.dart';
import '../../widgets/academy_background.dart';
import '../../widgets/student_subject_selector.dart';
import '../../models/fee_models.dart';
import '../../services/fee_service.dart';
import '../../utils/fee_month.dart';
import '../../widgets/add_student_dialog.dart';

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

  final FeeService _feeService = FeeService();

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
      return const ['All', 'Computer', 'Biology', 'Single Subject'];
    }

    if (widget.classLevel == 11 || widget.classLevel == 12) {
      return const [
        'All',
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

    switch (selectedFilter) {
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

  List<dynamic> get visibleStudents {
    final query = _searchQuery.trim().toLowerCase();

    return students.where((student) {
      if (!_matchesFilter(student)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final studentName =
          student['name']?.toString().trim().toLowerCase() ?? '';

      return studentName.contains(query);
    }).toList();
  }

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

  Future<void> _addStudentFromStudentsTab() async {
    if (_addingStudent) return;

    final batch = FeeBatch(
      id: widget.batchId,
      name: widget.batchName,
      classLevel: widget.classLevel,
    );

    final paymentMonth = FeeMonth.fromDate(DateTime.now());

    final request = await showAcademyAddStudentDialog(
      context: context,
      batches: [batch],
      initialBatch: batch,
      paymentMonth: paymentMonth,
      lockBatch: true,
    );

    if (!mounted || request == null) return;

    setState(() {
      _addingStudent = true;
    });

    try {
      await _feeService.addStudent(
        name: request.name,
        batchId: request.batch.id,
        defaultFee: request.defaultFee,
        subjects: request.subjects,
        paymentMonth: paymentMonth,
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
            '$paymentMonth fee: Unpaid',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      debugPrint('Students tab add student error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to add student.\n$e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingStudent = false;
        });
      }
    }
  }

  Future<void> _editStudent(Map<String, dynamic> student) async {
    final controller = TextEditingController(
      text: student['name']?.toString() ?? '',
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
                          if (value == null) {
                            return;
                          }

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
          'p_stream': selectedSubjects,
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
        SnackBar(
          content: Text('Could not update student.\n$e'),
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
                          child: Align(
                            alignment: Alignment.centerLeft,
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
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
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
