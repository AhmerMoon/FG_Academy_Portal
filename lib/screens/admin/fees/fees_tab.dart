import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'fee_setup_screen.dart';
import '../../../app_theme.dart';
import '../../../models/fee_models.dart';
import '../../../services/fee_service.dart';
import '../../../utils/dashboard_section_header.dart';
import '../../../utils/error_state_view.dart';
import '../../../utils/fee_month.dart';
import '../../../utils/fee_pdf_generator.dart';
import 'fee_audit_dashboard.dart';

class FeesTab extends StatefulWidget {
  const FeesTab({super.key});

  @override
  State<FeesTab> createState() => _FeesTabState();
}

class _FeesTabState extends State<FeesTab> {
  int _selectedSection = 0;

  int _reportRevision = 0;

  void _financialDataChanged() {
    setState(() {
      _reportRevision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return Column(
      children: [
        if (!isMobile)
          const DashboardSectionHeader(
            title: 'Fee Management',
            subtitle: 'Fee collection, reports and financial setup',
          ),

        Padding(
          padding: isMobile
              ? const EdgeInsets.fromLTRB(8, 5, 8, 5)
              : const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Fee Collection'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.analytics_outlined),
                  label: Text('Audit Reports'),
                ),
                ButtonSegment<int>(
                  value: 2,
                  icon: Icon(Icons.tune_rounded),
                  label: Text('Fee Setup'),
                ),
              ],
              selected: {_selectedSection},
              onSelectionChanged: (selection) {
                setState(() {
                  _selectedSection = selection.first;
                });
              },
            ),
          ),
        ),

        Expanded(
          child: IndexedStack(
            index: _selectedSection,
            children: [
              FeeCollectionPanel(onDataChanged: _financialDataChanged),
              FeeAuditDashboard(key: ValueKey(_reportRevision)),
              FeeSetupScreen(onDataChanged: _financialDataChanged),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FEE COLLECTION
// ============================================================================

class FeeCollectionPanel extends StatefulWidget {
  final VoidCallback? onDataChanged;

  const FeeCollectionPanel({super.key, this.onDataChanged});

  @override
  State<FeeCollectionPanel> createState() => _FeeCollectionPanelState();
}

class _FeeCollectionPanelState extends State<FeeCollectionPanel> {
  final FeeService _service = FeeService();

  final NumberFormat _moneyFormat = NumberFormat('#,##0.00');

  List<FeeBatch> _batches = [];

  List<String> _months = [];

  List<FeeStudentEntry> _entries = [];

  final Map<String, String> _draftAmounts = {};

  final Map<String, String> _draftRemarks = {};

  final Set<String> _savingStudentIds = {};

  Set<String> _presentStudentIdsForMonth = {};

  String? _selectedBatchId;

  String? _selectedMonth;

  bool _initialLoading = true;

  bool _loadingEntries = false;

  bool _initializingMonth = false;

  bool _addingStudent = false;

  bool _mobileFiltersExpanded = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _bootstrap();
  }

  String _money(double value) {
    return 'Rs ${_moneyFormat.format(value)}';
  }

  Future<void> _bootstrap() async {
    try {
      final batches = await _service.fetchBatches();

      var months = await _service.fetchAvailableMonths();

      if (months.isEmpty) {
        await _service.initializeMonth(FeeMonth.fromDate(DateTime.now()));

        months = await _service.fetchAvailableMonths();
      }

      final selectedBatch = batches.isNotEmpty ? batches.first.id : null;

      final selectedMonth = months.isNotEmpty ? months.first : null;

      List<FeeStudentEntry> entries = [];
      Set<String> presentStudentIds = {};

      if (selectedBatch != null && selectedMonth != null) {
        final results = await Future.wait<dynamic>([
          _service.fetchCollectionEntries(
            batchId: selectedBatch,
            paymentMonth: selectedMonth,
          ),
          _service.fetchPresentStudentIdsForMonth(
            batchId: selectedBatch,
            paymentMonth: selectedMonth,
          ),
        ]);

        entries = results[0] as List<FeeStudentEntry>;

        presentStudentIds = results[1] as Set<String>;
      }

      if (!mounted) return;

      setState(() {
        _batches = batches;

        _months = months;

        _selectedBatchId = selectedBatch;

        _selectedMonth = selectedMonth;

        _entries = entries;

        _presentStudentIdsForMonth = presentStudentIds;

        _resetDraftAmounts(entries);

        _initialLoading = false;

        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('Fee bootstrap error: $e');

      if (!mounted) return;

      setState(() {
        _initialLoading = false;

        _errorMessage =
            'Unable to load fee collection data. '
            'Please check your connection and try again.';
      });
    }
  }

  void _resetDraftAmounts(List<FeeStudentEntry> entries) {
    _draftAmounts.clear();
    _draftRemarks.clear();

    for (final entry in entries) {
      final value = entry.isPaid ? entry.amountPaid : entry.defaultFee;

      _draftAmounts[entry.studentId] = _editableAmount(value);

      _draftRemarks[entry.studentId] = entry.remarks;
    }
  }

  String _editableAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  FeeBatch? get _selectedBatch {
    final id = _selectedBatchId;

    if (id == null) return null;

    for (final batch in _batches) {
      if (batch.id == id) {
        return batch;
      }
    }

    return null;
  }

  bool _feeDueDatePassed(String paymentMonth) {
    final month = FeeMonth.parse(paymentMonth);

    if (month == null) {
      return false;
    }

    final duePassedAt = DateTime(month.year, month.month, 6);

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    return !today.isBefore(duePassedAt);
  }

  bool _isFeeDefaulter(FeeStudentEntry entry) {
    if (entry.isPaid) {
      return false;
    }

    if (!_feeDueDatePassed(entry.paymentMonth)) {
      return false;
    }

    return _presentStudentIdsForMonth.contains(entry.studentId);
  }

  Future<void> _loadEntries() async {
    final batchId = _selectedBatchId;

    final month = _selectedMonth;

    if (batchId == null || month == null) {
      return;
    }

    setState(() {
      _loadingEntries = true;

      _errorMessage = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _service.fetchCollectionEntries(batchId: batchId, paymentMonth: month),
        _service.fetchPresentStudentIdsForMonth(
          batchId: batchId,
          paymentMonth: month,
        ),
      ]);

      final entries = results[0] as List<FeeStudentEntry>;

      final presentStudentIds = results[1] as Set<String>;

      if (!mounted) return;

      setState(() {
        _entries = entries;

        _presentStudentIdsForMonth = presentStudentIds;

        _resetDraftAmounts(entries);

        _loadingEntries = false;
      });
    } catch (e) {
      debugPrint('Fee collection load error: $e');

      if (!mounted) return;

      setState(() {
        _loadingEntries = false;

        _errorMessage =
            'Unable to load student fee records. '
            'Please try again.';
      });
    }
  }

  double? _draftAmountFor(FeeStudentEntry entry) {
    final text = _draftAmounts[entry.studentId]?.trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return double.tryParse(text);
  }

  Future<bool> _confirmMarkUnpaid(FeeStudentEntry entry) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Mark Fee Unpaid?'),
              content: Text(
                '${entry.name} is currently marked '
                'as paid for '
                '${entry.paymentMonth}.\n\n'
                'This will set the received amount '
                'to Rs 0.00.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Mark Unpaid'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _togglePayment(FeeStudentEntry entry, bool markPaid) async {
    if (_savingStudentIds.contains(entry.studentId)) {
      return;
    }

    double amount = 0;

    if (markPaid) {
      final draftAmount = _draftAmountFor(entry);

      if (draftAmount == null || draftAmount <= 0) {
        _showMessage('Please enter a valid received amount.', error: true);

        return;
      }

      amount = draftAmount;
    } else {
      final confirmed = await _confirmMarkUnpaid(entry);

      if (!confirmed) return;
    }

    await _savePayment(entry: entry, paid: markPaid, amount: amount);
  }

  Future<void> _savePaidAmount(FeeStudentEntry entry) async {
    if (!entry.isPaid) return;

    final amount = _draftAmountFor(entry);

    if (amount == null || amount <= 0) {
      _showMessage('Please enter a valid amount.', error: true);

      return;
    }

    if ((amount - entry.amountPaid).abs() < 0.005) {
      _showMessage('No amount change to save.');

      return;
    }

    await _savePayment(entry: entry, paid: true, amount: amount);
  }

  Future<void> _saveRemarks(FeeStudentEntry entry) async {
    if (_savingStudentIds.contains(entry.studentId)) {
      return;
    }

    final remarks = (_draftRemarks[entry.studentId] ?? entry.remarks).trim();

    if (remarks == entry.remarks.trim()) {
      _showMessage('No remarks change to save.');
      return;
    }

    setState(() {
      _savingStudentIds.add(entry.studentId);
    });

    try {
      await _service.saveStudentFeeRemarks(
        studentId: entry.studentId,
        remarks: remarks,
      );

      if (!mounted) return;

      final index = _entries.indexWhere(
        (item) => item.studentId == entry.studentId,
      );

      if (index != -1) {
        setState(() {
          _entries[index] = entry.copyWith(remarks: remarks);

          _draftRemarks[entry.studentId] = remarks;
        });
      }

      _showMessage('${entry.name} remarks saved.');
    } catch (e) {
      debugPrint('Fee remarks save error: $e');

      _showMessage('Unable to save remarks.\n$e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _savingStudentIds.remove(entry.studentId);
        });
      }
    }
  }

  Future<void> _savePayment({
    required FeeStudentEntry entry,
    required bool paid,
    required double amount,
  }) async {
    final month = _selectedMonth;

    if (month == null) return;

    setState(() {
      _savingStudentIds.add(entry.studentId);
    });

    try {
      final paymentId = await _service.savePayment(
        studentId: entry.studentId,
        paymentMonth: month,
        paid: paid,
        amount: amount,
      );

      if (!mounted) return;

      final index = _entries.indexWhere(
        (item) => item.studentId == entry.studentId,
      );

      if (index != -1) {
        final updated = entry.copyWith(
          paymentId: paymentId,
          status: paid ? 'paid' : 'unpaid',
          amountPaid: paid ? amount : 0,
          paymentMonth: month,
        );

        setState(() {
          _entries[index] = updated;

          _draftAmounts[entry.studentId] = _editableAmount(
            paid ? amount : entry.defaultFee,
          );
        });
      }

      widget.onDataChanged?.call();

      _showMessage(
        paid
            ? '${entry.name} fee saved successfully.'
            : '${entry.name} marked unpaid.',
      );
    } catch (e) {
      debugPrint('Fee save error: $e');

      _showMessage('Unable to save fee record.\n$e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _savingStudentIds.remove(entry.studentId);
        });
      }
    }
  }

  // ==========================================================================
  // ADD STUDENT
  // ==========================================================================

  Future<void> _showAddStudentDialog() async {
    final currentBatch = _selectedBatch;

    final paymentMonth = _selectedMonth;

    if (currentBatch == null || paymentMonth == null) {
      _showMessage('Select a batch and fee month first.', error: true);

      return;
    }

    FeeBatch dialogBatch = currentBatch;

    final nameController = TextEditingController();

    final feeController = TextEditingController(
      text: dialogBatch.classLevel <= 10 ? '5500' : '6000',
    );

    Set<String> selectedBaseSubjects = {};
    late String selectedChoiceSubject;

    void resetSubjectsForBatch(FeeBatch batch) {
      if (batch.classLevel <= 10) {
        selectedBaseSubjects = {'Phy', 'Chem', 'Math', 'Eng'};
        selectedChoiceSubject = 'Comp';
      } else {
        selectedBaseSubjects = {'Phy', 'Math', 'Eng'};
        selectedChoiceSubject = 'Chem';
      }
    }

    resetSubjectsForBatch(dialogBatch);

    String? dialogError;

    final request = await showDialog<_NewFeeStudentRequest>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            const subjectOrder = ['Phy', 'Chem', 'Math', 'Eng', 'Comp', 'Bio'];

            final selectedSubjects = <String>{
              ...selectedBaseSubjects,
              selectedChoiceSubject,
            };

            final subjects = subjectOrder
                .where(selectedSubjects.contains)
                .toList();

            final baseSubjects = dialogBatch.classLevel <= 10
                ? const ['Phy', 'Chem', 'Math', 'Eng']
                : const ['Phy', 'Math', 'Eng'];

            final choiceSubjects = dialogBatch.classLevel <= 10
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
                value: checked,
                title: Text(feeSubjectLabel(code)),
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
              title: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.fgNavyBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1,
                      color: AppTheme.fgNavyBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Add New Student')),
                ],
              ),
              content: SizedBox(
                width: 470,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey(dialogBatch.id),
                        initialValue: dialogBatch.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Batch',
                          prefixIcon: Icon(Icons.class_outlined),
                        ),
                        items: _batches
                            .map(
                              (batch) => DropdownMenuItem(
                                value: batch.id,
                                child: Text(batch.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          final newBatch = _batches.firstWhere(
                            (batch) => batch.id == value,
                          );

                          setDialogState(() {
                            dialogBatch = newBatch;

                            feeController.text = newBatch.classLevel <= 10
                                ? '5500'
                                : '6000';

                            resetSubjectsForBatch(newBatch);

                            dialogError = null;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Student Name',
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: feeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Default Monthly Fee',
                          prefixText: 'Rs ',
                          helperText: dialogBatch.classLevel <= 10
                              ? 'SSC suggested fee: Rs 5,500'
                              : 'HSSC suggested fee: Rs 6,000',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Core Subjects',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.fgNavyBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth >= 440
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
                      const SizedBox(height: 12),
                      Text(
                        dialogBatch.classLevel <= 10
                            ? 'Choose Biology / Computer'
                            : 'Choose Group Subject',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.fgNavyBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth >= 440
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
                      const SizedBox(height: 16),
                      const Text(
                        'Subjects',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.fgNavyBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: subjects
                            .map(
                              (subject) =>
                                  Chip(label: Text(feeSubjectLabel(subject))),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.green,
                              size: 19,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'On save: student will be created, today\'s attendance will be marked Present, and the selected fee month will start as Unpaid.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          dialogError!,
                          style: const TextStyle(
                            color: Colors.red,
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
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Student'),
                  onPressed: () {
                    final name = nameController.text.trim();

                    final fee = double.tryParse(feeController.text.trim());

                    if (name.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Student name is required.';
                      });

                      return;
                    }

                    if (fee == null || fee <= 0) {
                      setDialogState(() {
                        dialogError = 'Enter a valid default fee.';
                      });

                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _NewFeeStudentRequest(
                        name: name,
                        batch: dialogBatch,
                        defaultFee: fee,
                        subjects: subjects,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();

    feeController.dispose();

    if (request == null) return;

    await _addStudent(request);
  }

  Future<void> _addStudent(_NewFeeStudentRequest request) async {
    final month = _selectedMonth;

    if (month == null) return;

    setState(() {
      _addingStudent = true;
    });

    try {
      await _service.addStudent(
        name: request.name,
        batchId: request.batch.id,
        defaultFee: request.defaultFee,
        subjects: request.subjects,
        paymentMonth: month,
      );

      if (!mounted) return;

      setState(() {
        _selectedBatchId = request.batch.id;
      });

      await _loadEntries();

      widget.onDataChanged?.call();

      _showMessage(
        '${request.name} added successfully. '
        'Today attendance is Present and '
        '$month fee is Unpaid.',
      );
    } catch (e) {
      debugPrint('Add fee student error: $e');

      _showMessage('Unable to add student.\n$e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _addingStudent = false;
        });
      }
    }
  }

  // ==========================================================================
  // MONTH INITIALIZATION
  // ==========================================================================

  Future<void> _showInitializeMonthDialog() async {
    final now = DateTime.now();

    int selectedMonth = now.month;

    int selectedYear = now.year;

    final years = List<int>.generate(6, (index) => now.year - 1 + index);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Initialize Fee Month'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      key: ValueKey('month-$selectedMonth'),
                      initialValue: selectedMonth,
                      decoration: const InputDecoration(
                        labelText: 'Month',
                        prefixIcon: Icon(Icons.calendar_month),
                      ),
                      items: List.generate(
                        12,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text(FeeMonth.fullNames[index]),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          selectedMonth = value;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      key: ValueKey('year-$selectedYear'),
                      initialValue: selectedYear,
                      decoration: const InputDecoration(
                        labelText: 'Year',
                        prefixIcon: Icon(Icons.event),
                      ),
                      items: years
                          .map(
                            (year) => DropdownMenuItem(
                              value: year,
                              child: Text(year.toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          selectedYear = value;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'All active students will receive an Unpaid fee record. Existing records will not be overwritten.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      FeeMonth.fromParts(selectedYear, selectedMonth),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Initialize'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    await _initializeMonth(result);
  }

  Future<void> _initializeMonth(String month) async {
    setState(() {
      _initializingMonth = true;
    });

    try {
      final created = await _service.initializeMonth(month);

      final months = await _service.fetchAvailableMonths();

      if (!mounted) return;

      setState(() {
        _months = months;

        _selectedMonth = month;

        _initializingMonth = false;
      });

      await _loadEntries();

      widget.onDataChanged?.call();

      _showMessage(
        created > 0
            ? '$month initialized for $created students.'
            : '$month already exists. Existing records were kept.',
      );
    } catch (e) {
      debugPrint('Initialize fee month error: $e');

      if (!mounted) return;

      setState(() {
        _initializingMonth = false;
      });

      _showMessage('Unable to initialize fee month.', error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _batches.isEmpty) {
      return ErrorStateView(message: _errorMessage!, onRetry: _bootstrap);
    }

    final paidCount = _entries.where((entry) => entry.isPaid).length;

    final unpaidCount = _entries.length - paidCount;

    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return Column(
      children: [
        isMobile
            ? _buildMobileFilters(
                paidCount: paidCount,
                unpaidCount: unpaidCount,
              )
            : _buildFilters(paidCount: paidCount, unpaidCount: unpaidCount),
        Expanded(child: _buildStudentList()),
      ],
    );
  }

  Widget _buildMobileFilters({
    required int paidCount,
    required int unpaidCount,
  }) {
    final batchName = _selectedBatch?.name ?? 'Select batch';

    final monthName = _selectedMonth ?? 'Select month';

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    batchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  monthName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: 'Show fee filters',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _mobileFiltersExpanded = !_mobileFiltersExpanded;
                    });
                  },
                  icon: Icon(
                    _mobileFiltersExpanded ? Icons.expand_less : Icons.tune,
                  ),
                ),
              ],
            ),
            if (_mobileFiltersExpanded)
              _buildFiltersContent(
                paidCount: paidCount,
                unpaidCount: unpaidCount,
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatusBadge(
                    icon: Icons.check_circle,
                    label: 'Paid',
                    value: paidCount,
                    color: Colors.green,
                  ),
                  _StatusBadge(
                    icon: Icons.pending,
                    label: 'Unpaid',
                    value: unpaidCount,
                    color: Colors.orange,
                  ),
                  _StatusBadge(
                    icon: Icons.people,
                    label: 'Total',
                    value: _entries.length,
                    color: Colors.blueGrey,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters({required int paidCount, required int unpaidCount}) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: _buildFiltersContent(
        paidCount: paidCount,
        unpaidCount: unpaidCount,
      ),
    );
  }

  Widget _buildFiltersContent({
    required int paidCount,
    required int unpaidCount,
  }) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: constraints.maxWidth > 700 ? 280 : constraints.maxWidth,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('fee-batch-$_selectedBatchId'),
                  initialValue: _selectedBatchId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Batch',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  items: _batches
                      .map(
                        (batch) => DropdownMenuItem(
                          value: batch.id,
                          child: Text(batch.name),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingEntries
                      ? null
                      : (value) async {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _selectedBatchId = value;
                          });

                          await _loadEntries();
                        },
                ),
              ),
              SizedBox(
                width: constraints.maxWidth > 700 ? 220 : constraints.maxWidth,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('fee-month-$_selectedMonth'),
                  initialValue: _selectedMonth,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Fee Month',
                    prefixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  items: _months
                      .map(
                        (month) =>
                            DropdownMenuItem(value: month, child: Text(month)),
                      )
                      .toList(),
                  onChanged: _loadingEntries
                      ? null
                      : (value) async {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _selectedMonth = value;
                          });

                          await _loadEntries();
                        },
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addingStudent || _loadingEntries
                    ? null
                    : _showAddStudentDialog,
                icon: _addingStudent
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_add_alt_1),
                label: const Text('Add Student'),
              ),
              ElevatedButton.icon(
                onPressed: _initializingMonth || _loadingEntries
                    ? null
                    : _showInitializeMonthDialog,
                icon: _initializingMonth
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_circle_outline),
                label: const Text('New Month'),
              ),
              OutlinedButton.icon(
                onPressed: _loadingEntries ? null : _loadEntries,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              _StatusBadge(
                icon: Icons.people,
                label: 'Total',
                value: _entries.length,
                color: Colors.blueGrey,
              ),
              _StatusBadge(
                icon: Icons.check_circle,
                label: 'Paid',
                value: paidCount,
                color: Colors.green,
              ),
              _StatusBadge(
                icon: Icons.pending,
                label: 'Unpaid',
                value: unpaidCount,
                color: Colors.orange,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStudentList() {
    if (_loadingEntries) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ErrorStateView(message: _errorMessage!, onRetry: _loadEntries);
    }

    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadEntries,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.people_outline, size: 52, color: Colors.black38),
            SizedBox(height: 12),
            Center(child: Text('No students found for this batch.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          return _buildStudentCard(_entries[index]);
        },
      ),
    );
  }

  Widget _buildStudentCard(FeeStudentEntry entry) {
    final saving = _savingStudentIds.contains(entry.studentId);

    final isMobile = MediaQuery.sizeOf(context).width < 700;

    final isDefaulter = _isFeeDefaulter(entry);

    final statusColor = isDefaulter
        ? AppTheme.danger
        : entry.isPaid
        ? Colors.green
        : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;

            final identity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.name,
                        style: TextStyle(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w800,
                          color: isDefaulter
                              ? AppTheme.danger
                              : AppTheme.fgNavyBlue,
                        ),
                      ),
                    ),
                    if (isDefaulter)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.danger.withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Text(
                          'FEE OVERDUE',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                if (isDefaulter) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Attendance recorded this month • Fee unpaid after 5th',
                    style: TextStyle(
                      color: AppTheme.danger,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  'Default Fee: '
                  '${_money(entry.defaultFee)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: entry.subjects
                      .map(
                        (subject) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.fgNavyBlue.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            feeSubjectLabel(subject),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.fgNavyBlue,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            );

            final controls = _buildStudentControls(entry, saving);

            if (wide) {
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 20),
                  controls,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const Divider(height: 24), controls],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStudentControls(FeeStudentEntry entry, bool saving) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        SizedBox(
          width: 165,
          child: TextFormField(
            key: ValueKey(
              '${entry.studentId}-'
              '${entry.status}-'
              '${entry.amountPaid}',
            ),
            initialValue:
                _draftAmounts[entry.studentId] ??
                _editableAmount(entry.defaultFee),
            enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: entry.isPaid ? 'Amount Paid' : 'Fee Amount',
              prefixText: 'Rs ',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 15),
            onChanged: (value) {
              _draftAmounts[entry.studentId] = value;
            },
          ),
        ),
        if (entry.isPaid)
          IconButton(
            tooltip: 'Save changed amount',
            onPressed: saving ? null : () => _savePaidAmount(entry),
            icon: const Icon(Icons.save_outlined),
            color: AppTheme.fgNavyBlue,
          ),
        SizedBox(
          width: 300,
          child: TextFormField(
            key: ValueKey('${entry.studentId}-remarks-${entry.remarks}'),
            initialValue: _draftRemarks[entry.studentId] ?? entry.remarks,
            enabled: !saving,
            minLines: 1,
            maxLines: 2,
            inputFormatters: [LengthLimitingTextInputFormatter(500)],
            decoration: InputDecoration(
              labelText: 'Remarks',
              hintText: 'e.g. Orphan / sibling concession',
              isDense: true,
              prefixIcon: const Icon(Icons.notes_rounded),
              suffixIcon: IconButton(
                tooltip: 'Save remarks',
                onPressed: saving ? null : () => _saveRemarks(entry),
                icon: const Icon(Icons.save_outlined),
              ),
            ),
            onChanged: (value) {
              _draftRemarks[entry.studentId] = value;
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (entry.isPaid ? Colors.green : Colors.orange).withValues(
              alpha: 0.10,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            entry.isPaid ? 'PAID' : 'UNPAID',
            style: TextStyle(
              color: entry.isPaid ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        if (saving)
          const SizedBox(
            width: 32,
            height: 32,
            child: Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Switch.adaptive(
            value: entry.isPaid,
            activeTrackColor: Colors.green,
            onChanged: (value) {
              _togglePayment(entry, value);
            },
          ),
      ],
    );
  }
}

// ============================================================================
// FINANCIAL DASHBOARD
// ============================================================================

class FinancialDashboardPanel extends StatefulWidget {
  const FinancialDashboardPanel({super.key});

  @override
  State<FinancialDashboardPanel> createState() =>
      _FinancialDashboardPanelState();
}

class _FinancialDashboardPanelState extends State<FinancialDashboardPanel> {
  final FeeService _service = FeeService();

  final NumberFormat _moneyFormat = NumberFormat('#,##0.00');

  List<String> _months = [];

  List<FeeSummaryRow> _rows = [];

  String? _selectedMonth;

  bool _loading = true;

  bool _exporting = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _bootstrap();
  }

  String _money(double value) {
    return 'Rs ${_moneyFormat.format(value)}';
  }

  Future<void> _bootstrap() async {
    try {
      final months = await _service.fetchAvailableMonths();

      final selected = months.isNotEmpty ? months.first : null;

      List<FeeSummaryRow> rows = [];

      if (selected != null) {
        rows = await _service.fetchFinancialSummary(selected);
      }

      if (!mounted) return;

      setState(() {
        _months = months;

        _selectedMonth = selected;

        _rows = rows;

        _loading = false;

        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('Fee dashboard bootstrap error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;

        _errorMessage = 'Unable to load financial dashboard.';
      });
    }
  }

  Future<void> _loadReport() async {
    final month = _selectedMonth;

    if (month == null) return;

    setState(() {
      _loading = true;

      _errorMessage = null;
    });

    try {
      final rows = await _service.fetchFinancialSummary(month);

      if (!mounted) return;

      setState(() {
        _rows = rows;

        _loading = false;
      });
    } catch (e) {
      debugPrint('Fee dashboard load error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;

        _errorMessage = 'Unable to load financial report.';
      });
    }
  }

  Future<void> _exportPdf() async {
    final month = _selectedMonth;

    if (month == null || _rows.isEmpty) {
      return;
    }

    setState(() {
      _exporting = true;
    });

    try {
      final bytes = await FeePdfGenerator.buildReport(
        paymentMonth: month,
        rows: _rows,
      );

      final filename =
          'FG_Academy_Fee_Report_'
          '${month.replaceAll('-', '_')}.pdf';

      final shared = await Printing.sharePdf(bytes: bytes, filename: filename);

      if (!shared) {
        await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
      }
    } catch (e) {
      debugPrint('Fee PDF export error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to export PDF report.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  List<FeeSummaryRow> _rowsFor({required String section, String? groupName}) {
    final values = _rows.where((row) {
      if (row.section != section) {
        return false;
      }

      if (groupName != null && row.groupName != groupName) {
        return false;
      }

      return true;
    }).toList();

    values.sort((first, second) => first.sortOrder.compareTo(second.sortOrder));

    return values;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _months.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _months.isEmpty) {
      return ErrorStateView(message: _errorMessage!, onRetry: _bootstrap);
    }

    return Column(
      children: [
        _buildDashboardToolbar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? ErrorStateView(message: _errorMessage!, onRetry: _loadReport)
              : _buildReport(),
        ),
      ],
    );
  }

  Widget _buildDashboardToolbar() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                key: ValueKey('legacy-report-$_selectedMonth'),
                initialValue: _selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'Report Month',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                items: _months
                    .map(
                      (month) =>
                          DropdownMenuItem(value: month, child: Text(month)),
                    )
                    .toList(),
                onChanged: _loading
                    ? null
                    : (value) async {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _selectedMonth = value;
                        });

                        await _loadReport();
                      },
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadReport,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            ElevatedButton.icon(
              onPressed: _exporting || _rows.isEmpty ? null : _exportPdf,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_exporting ? 'Preparing...' : 'Export PDF'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport() {
    if (_rows.isEmpty) {
      return const Center(child: Text('No financial report data available.'));
    }

    final collectionRows = _rowsFor(section: 'collection');

    final sscTeacherRows = _rowsFor(section: 'teacher', groupName: 'SSC');

    final hsscTeacherRows = _rowsFor(section: 'teacher', groupName: 'HSSC');

    final fundRows = _rowsFor(section: 'fund');

    return RefreshIndicator(
      onRefresh: _loadReport,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 30),
        children: [
          const _ReportSectionTitle(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Total Collection Summary',
            subtitle: 'Collection values are calculated by Supabase.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: collectionRows
                .map(
                  (row) => _CollectionSummaryCard(
                    row: row,
                    formattedAmount: _money(row.amount),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
          const _ReportSectionTitle(
            icon: Icons.school_outlined,
            title: 'Teacher Payouts',
            subtitle:
                'Subject payouts are read directly from Supabase financial views.',
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 850;

              final ssc = _TeacherPayoutCard(
                title: 'SSC - Classes 9 & 10',
                rows: sscTeacherRows,
                moneyFormatter: _money,
              );

              final hssc = _TeacherPayoutCard(
                title: 'HSSC - Classes 11 & 12',
                rows: hsscTeacherRows,
                moneyFormatter: _money,
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ssc),
                    const SizedBox(width: 12),
                    Expanded(child: hssc),
                  ],
                );
              }

              return Column(children: [ssc, const SizedBox(height: 12), hssc]);
            },
          ),
          const SizedBox(height: 24),
          const _ReportSectionTitle(
            icon: Icons.account_balance_outlined,
            title: 'Fund Payouts',
            subtitle: 'Admin, NTS, Building, ECC and Organizer funds.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: fundRows
                .map(
                  (row) => _FundPayoutCard(
                    row: row,
                    formattedAmount: _money(row.amount),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PRIVATE REQUEST MODEL
// ============================================================================

class _NewFeeStudentRequest {
  final String name;

  final FeeBatch batch;

  final double defaultFee;

  final List<String> subjects;

  const _NewFeeStudentRequest({
    required this.name,
    required this.batch,
    required this.defaultFee,
    required this.subjects,
  });
}

// ============================================================================
// REUSABLE UI
// ============================================================================

class _StatusBadge extends StatelessWidget {
  final IconData icon;

  final String label;

  final int value;

  final Color color;

  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportSectionTitle extends StatelessWidget {
  final IconData icon;

  final String title;

  final String subtitle;

  const _ReportSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.fgNavyBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppTheme.fgNavyBlue),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.fgNavyBlue,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CollectionSummaryCard extends StatelessWidget {
  final FeeSummaryRow row;

  final String formattedAmount;

  const _CollectionSummaryCard({
    required this.row,
    required this.formattedAmount,
  });

  @override
  Widget build(BuildContext context) {
    final isTotal = row.groupName == 'ALL';

    return Container(
      width: 300,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: isTotal
            ? const LinearGradient(
                colors: [AppTheme.fgNavyBlue, Color(0xFF174A86)],
              )
            : null,
        color: isTotal ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTotal
              ? Colors.transparent
              : AppTheme.fgNavyBlue.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.itemName,
            style: TextStyle(
              color: isTotal ? Colors.white70 : Colors.black54,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formattedAmount,
              style: TextStyle(
                color: isTotal ? Colors.white : AppTheme.fgNavyBlue,
                fontWeight: FontWeight.w800,
                fontSize: 25,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniCount(
                label: 'Paid',
                value: row.paidStudents,
                color: isTotal ? Colors.white : Colors.green,
              ),
              const SizedBox(width: 14),
              _MiniCount(
                label: 'Unpaid',
                value: row.unpaidStudents,
                color: isTotal ? Colors.white : Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniCount extends StatelessWidget {
  final String label;

  final int value;

  final Color color;

  const _MiniCount({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
    );
  }
}

class _TeacherPayoutCard extends StatelessWidget {
  final String title;

  final List<FeeSummaryRow> rows;

  final String Function(double) moneyFormatter;

  const _TeacherPayoutCard({
    required this.title,
    required this.rows,
    required this.moneyFormatter,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin_outlined, color: AppTheme.fgGold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.fgNavyBlue,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            for (int index = 0; index < rows.length; index++) ...[
              _TeacherPayoutRow(
                row: rows[index],
                moneyFormatter: moneyFormatter,
              ),
              if (index != rows.length - 1) const Divider(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeacherPayoutRow extends StatelessWidget {
  final FeeSummaryRow row;

  final String Function(double) moneyFormatter;

  const _TeacherPayoutRow({required this.row, required this.moneyFormatter});

  @override
  Widget build(BuildContext context) {
    final total = row.itemName == 'Total Teacher Share';

    final label = total ? row.itemName : feeSubjectLabel(row.itemName);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: total ? FontWeight.w800 : FontWeight.w600,
              color: total ? AppTheme.fgNavyBlue : Colors.black87,
            ),
          ),
        ),
        if (!total)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Text(
              '${row.paidStudents} students',
              style: const TextStyle(color: Colors.black45, fontSize: 11),
            ),
          ),
        Text(
          moneyFormatter(row.amount),
          style: TextStyle(
            fontWeight: total ? FontWeight.w800 : FontWeight.w700,
            color: total ? Colors.green.shade800 : AppTheme.fgNavyBlue,
          ),
        ),
      ],
    );
  }
}

class _FundPayoutCard extends StatelessWidget {
  final FeeSummaryRow row;

  final String formattedAmount;

  const _FundPayoutCard({required this.row, required this.formattedAmount});

  IconData get _icon {
    if (row.itemName.startsWith('NTS')) {
      return Icons.assessment_outlined;
    }

    if (row.itemName.startsWith('Building')) {
      return Icons.apartment_outlined;
    }

    if (row.itemName.startsWith('Admin')) {
      return Icons.admin_panel_settings_outlined;
    }

    if (row.itemName.startsWith('Organizer')) {
      return Icons.groups_outlined;
    }

    return Icons.auto_awesome_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 245,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.fgGold.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: AppTheme.fgGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_icon, color: AppTheme.fgNavyBlue),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.itemName,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formattedAmount,
                    style: const TextStyle(
                      color: AppTheme.fgNavyBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
