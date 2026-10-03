import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../app_theme.dart';
import '../../../models/fee_audit_models.dart';
import '../../../models/fee_models.dart';
import '../../../services/fee_service.dart';
import '../../../utils/error_state_view.dart';
import '../../../utils/fee_audit_pdf_generator.dart';

const Set<String> _editableFixedStaffNames = {
  'Mr. Zahid Rehman',
  'Mr. Shahid',
  'Mr. Tariq Khan',
  'Mr. Ahmer Moon',
  'Ms. Samina',
  'Mr. Rafaqt',
};

class FeeAuditDashboard extends StatefulWidget {
  const FeeAuditDashboard({super.key});

  @override
  State<FeeAuditDashboard> createState() => _FeeAuditDashboardState();
}

class _FeeAuditDashboardState extends State<FeeAuditDashboard> {
  final FeeService _service = FeeService();

  List<String> _months = [];

  String? _selectedMonth;

  FeeAuditReportBundle? _report;

  int _selectedSheetIndex = 0;

  bool _loading = true;

  bool _printing = false;

  bool _staffSaving = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _bootstrap();
  }

  List<String> _sheets(FeeAuditReportBundle report) {
    return [
      ...report.availableClassCodes,
      'SSC Summary',
      'HSSC Summary',
      'Final Summary',
    ];
  }

  String _currentSheet(FeeAuditReportBundle report) {
    final values = _sheets(report);

    if (_selectedSheetIndex < 0 || _selectedSheetIndex >= values.length) {
      return values.first;
    }

    return values[_selectedSheetIndex];
  }

  Future<void> _bootstrap() async {
    try {
      final months = await _service.fetchAvailableMonths();

      if (months.isEmpty) {
        throw StateError('No fee months found.');
      }

      final month = months.first;

      final report = await _service.fetchAuditReport(month);

      if (!mounted) return;

      setState(() {
        _months = months;
        _selectedMonth = month;
        _report = report;

        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Audit load error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load audit report.';
      });
    }
  }

  Future<void> _loadSelectedMonth() async {
    final month = _selectedMonth;

    if (month == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final report = await _service.fetchAuditReport(month);

      if (!mounted) return;

      setState(() {
        _report = report;
        _selectedSheetIndex = 0;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Audit refresh error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to refresh audit report.';
      });
    }
  }

  Future<void> _reloadCurrentReportKeepingSheet() async {
    final month = _selectedMonth;

    if (month == null) return;

    final report = await _service.fetchAuditReport(month);

    if (!mounted) return;

    setState(() {
      _report = report;
      _error = null;
    });
  }

  Future<void> _editStaffPayment(FeeAuditStaffRow row) async {
    if (row.sourceType != 'nts' ||
        row.isTotal ||
        !_editableFixedStaffNames.contains(row.name) ||
        _staffSaving) {
      return;
    }

    final currentAmount = row.ntsPayment ?? row.totalPayment;

    final controller = TextEditingController(
      text: currentAmount.toStringAsFixed(2),
    );

    String? dialogError;

    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final raw = controller.text.trim().replaceAll(',', '');
              final parsed = double.tryParse(raw);

              if (parsed == null || parsed < 0) {
                setDialogState(() {
                  dialogError = 'Enter a valid amount of zero or greater.';
                });
                return;
              }

              Navigator.of(dialogContext).pop(parsed);
            }

            return AlertDialog(
              title: Text('Edit ${row.name} Payment'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      row.designation,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: const InputDecoration(
                        labelText: 'Payment Amount',
                        prefixText: 'Rs ',
                        helperText:
                            'This change applies only to the selected fee month.',
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Payment'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (amount == null) return;

    final month = _selectedMonth;
    if (month == null) return;

    setState(() {
      _staffSaving = true;
    });

    try {
      await _service.setStaffPayment(
        paymentMonth: month,
        staffName: row.name,
        amount: amount,
      );

      await _reloadCurrentReportKeepingSheet();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${row.name} payment updated for $month.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      debugPrint('Staff payment update error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update staff payment.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _staffSaving = false;
        });
      }
    }
  }

  Future<void> _resetStaffPayment(FeeAuditStaffRow row) async {
    if (row.sourceType != 'nts' ||
        row.isTotal ||
        !_editableFixedStaffNames.contains(row.name) ||
        _staffSaving) {
      return;
    }

    final month = _selectedMonth;
    if (month == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset Staff Payment'),
          content: Text(
            'Reset ${row.name} for $month to the default planned amount?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _staffSaving = true;
    });

    try {
      await _service.resetStaffPayment(
        paymentMonth: month,
        staffName: row.name,
      );

      await _reloadCurrentReportKeepingSheet();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${row.name} reset to the default amount for $month.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      debugPrint('Staff payment reset error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to reset staff payment.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _staffSaving = false;
        });
      }
    }
  }

  Future<void> _printCurrentSheet() async {
    final report = _report;

    if (report == null) {
      return;
    }

    final sheet = _currentSheet(report);

    setState(() {
      _printing = true;
    });

    try {
      final bytes = await FeeAuditPdfGenerator.buildSheet(
        report: report,
        sheetKey: sheet,
      );

      await Printing.layoutPdf(
        name: FeeAuditPdfGenerator.fileName(report: report, sheetKey: sheet),
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      debugPrint('Audit print error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to prepare PDF.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _printing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _report == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _report == null) {
      return ErrorStateView(message: _error!, onRetry: _bootstrap);
    }

    final report = _report;

    if (report == null) {
      return const Center(child: Text('No audit data available.'));
    }

    return Column(
      children: [
        _toolbar(report),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ErrorStateView(message: _error!, onRetry: _loadSelectedMonth)
              : _tabs(report),
        ),
      ],
    );
  }

  Widget _toolbar(FeeAuditReportBundle report) {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Wrap(
          spacing: 10,
          runSpacing: 9,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: ValueKey(_selectedMonth),
                initialValue: _selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'Audit Month',
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

                        await _loadSelectedMonth();
                      },
              ),
            ),

            ElevatedButton.icon(
              onPressed: _printing ? null : _printCurrentSheet,
              icon: _printing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.print_outlined),
              label: Text(_printing ? 'Preparing…' : 'Print Sheet'),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.fgGold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _currentSheet(report),
                style: const TextStyle(
                  color: AppTheme.fgNavyBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs(FeeAuditReportBundle report) {
    final classes = report.availableClassCodes;

    final sheets = _sheets(report);

    return DefaultTabController(
      key: ValueKey('${report.paymentMonth}-${sheets.length}'),
      length: sheets.length,
      initialIndex: _selectedSheetIndex,
      child: Column(
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.94),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppTheme.fgNavyBlue,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.fgGold,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              onTap: (index) {
                setState(() {
                  _selectedSheetIndex = index;
                });
              },
              tabs: sheets.map((value) => Tab(text: value)).toList(),
            ),
          ),

          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ...classes.map(
                  (code) => _ClassSheet(report: report, code: code),
                ),

                _LevelSheet(report: report, level: 'SSC'),

                _LevelSheet(report: report, level: 'HSSC'),

                _FinalSheet(
                  report: report,
                  staffSaving: _staffSaving,
                  onEditStaff: _editStaffPayment,
                  onResetStaff: _resetStaffPayment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CLASS
// =============================================================================

class _ClassSheet extends StatelessWidget {
  final FeeAuditReportBundle report;

  final String code;

  const _ClassSheet({required this.report, required this.code});

  @override
  Widget build(BuildContext context) {
    final total = report.totalForClass(code);

    if (total == null) {
      return const Center(child: Text('Class report unavailable.'));
    }

    final groups = <String, List<FeeAuditClassStudentRow>>{};

    for (final student in report.studentsForClass(code)) {
      groups.putIfAbsent(student.subjectGroup, () => []).add(student);
    }

    return ListView(
      padding: const EdgeInsets.all(9),
      children: [
        _ReportHeader(
          title: 'ECC FEE RECORD - ${total.batchName.toUpperCase()}',
          subtitle: report.paymentMonth,
          collection: total.collection,
          paid: total.paidStudents,
          unpaid: total.unpaidStudents,
        ),

        const SizedBox(height: 12),

        ...groups.entries.expand(
          (entry) => [
            _SectionHeader(entry.key),

            const SizedBox(height: 6),

            _ClassTable(total: total, rows: entry.value),

            const SizedBox(height: 16),
          ],
        ),

        _ClassTotals(total: total),

        const SizedBox(height: 28),

        const _SignaturePair(),
      ],
    );
  }
}

class _ClassTable extends StatelessWidget {
  final FeeAuditClassTotal total;

  final List<FeeAuditClassStudentRow> rows;

  const _ClassTable({required this.total, required this.rows});

  static final NumberFormat _money = NumberFormat('#,##0.00');

  String n(double value) => _money.format(value);

  @override
  Widget build(BuildContext context) {
    return _ReadableTable(
      minWidth: 1770,
      headers: [
        'Sr',
        'Student Name',
        'Fee',
        total.levelGroup == 'SSC' ? 'Teacher 60%' : 'Teacher 63%',
        'NTS',
        'Building',
        'Admin',
        'Organizer',
        'ECC',
        'Math',
        'Physics',
        'Computer',
        'Chemistry',
        'English',
        'Biology',
      ],
      widths: const [
        60,
        260,
        115,
        135,
        100,
        115,
        105,
        115,
        100,
        105,
        110,
        115,
        115,
        105,
        105,
      ],
      rows: rows
          .map(
            (row) => [
              row.groupSrNo.toString(),
              row.studentName,
              n(row.amountPaid),
              n(row.teacherShare),
              n(row.nts),
              n(row.building),
              n(row.admin),
              n(row.organizer),
              n(row.ecc),
              n(row.math),
              n(row.physics),
              n(row.computer),
              n(row.chemistry),
              n(row.english),
              n(row.biology),
            ],
          )
          .toList(),
    );
  }
}

class _ClassTotals extends StatelessWidget {
  final FeeAuditClassTotal total;

  const _ClassTotals({required this.total});

  static final NumberFormat _money = NumberFormat('#,##0.00');

  String m(double value) => 'Rs ${_money.format(value)}';

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Collection', m(total.collection)),
      ('Teacher', m(total.teacherShare)),
      ('NTS', m(total.nts)),
      ('Building', m(total.building)),
      ('Admin', m(total.admin)),
      ('Organizer', m(total.organizer)),
      ('ECC', m(total.ecc)),
      ('100% Verify', m(total.totalDistributed)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Wrap(
          spacing: 9,
          runSpacing: 9,
          children: items.map((item) {
            return Container(
              width: 190,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$1,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    item.$2,
                    style: const TextStyle(
                      color: AppTheme.fgNavyBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// =============================================================================
// LEVEL
// =============================================================================

class _LevelSheet extends StatelessWidget {
  final FeeAuditReportBundle report;

  final String level;

  const _LevelSheet({required this.report, required this.level});

  static final NumberFormat _money = NumberFormat('#,##0.00');

  String n(double value) => _money.format(value);

  @override
  Widget build(BuildContext context) {
    final ssc = level == 'SSC';

    final codes = ssc
        ? const ['9B', '9G', '10B', '10G']
        : const ['XIB', 'XIG', 'XIIB', 'XIIG'];

    final subjects = ssc ? report.sscSubjects : report.hsscSubjects;

    final summary = report.summaryFor(level);

    final subjectRows = <List<String>>[];

    subjectRows.add([
      'Total Collection',
      ...codes.map((code) => n(report.totalForClass(code)?.collection ?? 0)),
      n(summary?.collection ?? 0),
      '',
      '',
    ]);

    for (final subject in subjects) {
      subjectRows.add([
        feeSubjectLabel(subject.subjectCode),
        ...codes.map((code) => n(subject.classAmounts[code] ?? 0)),
        n(subject.totalAmount),
        subject.teacherName,
        '________________',
      ]);
    }

    subjectRows.add([
      'Total Teacher Share',
      ...codes.map((code) => n(report.totalForClass(code)?.teacherShare ?? 0)),
      n(summary?.teacher ?? 0),
      '',
      '',
    ]);

    final funds = codes.map((code) {
      final item = report.totalForClass(code);

      return [
        code,
        n(item?.collection ?? 0),
        n(item?.teacherShare ?? 0),
        n(item?.nts ?? 0),
        n(item?.building ?? 0),
        n(item?.admin ?? 0),
        n(item?.organizer ?? 0),
        n(item?.ecc ?? 0),
        n(item?.totalDistributed ?? 0),
      ];
    }).toList();

    if (summary != null) {
      funds.add([
        'TOTAL',
        n(summary.collection),
        n(summary.teacher),
        n(summary.nts),
        n(summary.building),
        n(summary.admin),
        n(summary.organizer),
        n(summary.ecc),
        n(summary.total),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.all(9),
      children: [
        _ReportHeader(
          title: '$level SUBJECT WISE SUMMARY',
          subtitle: report.paymentMonth,
          collection: summary?.collection ?? 0,
          paid: summary?.paidStudents ?? 0,
          unpaid: summary?.unpaidStudents ?? 0,
        ),

        const SizedBox(height: 13),

        const _SectionHeader('Teacher Subject Payments'),

        const SizedBox(height: 6),

        _ReadableTable(
          minWidth: 1300,
          headers: ['Subject', ...codes, 'Total', 'Teacher Name', 'Signature'],
          widths: const [180, 135, 135, 135, 135, 150, 240, 190],
          rows: subjectRows,
        ),

        const SizedBox(height: 20),

        _SectionHeader('$level Fund Breakdown'),

        const SizedBox(height: 6),

        _ReadableTable(
          minWidth: 1200,
          headers: const [
            'Class',
            'Collection',
            'Teacher',
            'NTS',
            'Building',
            'Admin',
            'Organizer',
            'ECC',
            '100%',
          ],
          widths: const [110, 150, 145, 120, 130, 120, 135, 120, 140],
          rows: funds,
        ),

        const SizedBox(height: 30),

        const _SignaturePair(),
      ],
    );
  }
}

// =============================================================================
// FINAL
// =============================================================================

class _FinalSheet extends StatelessWidget {
  final FeeAuditReportBundle report;
  final bool staffSaving;
  final Future<void> Function(FeeAuditStaffRow row) onEditStaff;
  final Future<void> Function(FeeAuditStaffRow row) onResetStaff;

  const _FinalSheet({
    required this.report,
    required this.staffSaving,
    required this.onEditStaff,
    required this.onResetStaff,
  });

  static final NumberFormat _money = NumberFormat('#,##0.00');

  String n(double value) => _money.format(value);

  @override
  Widget build(BuildContext context) {
    final total = report.summaryFor('TOTAL');

    final editableStaff = report.staff
        .where(
          (row) =>
              row.sourceType == 'nts' &&
              !row.isTotal &&
              _editableFixedStaffNames.contains(row.name),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(9),
      children: [
        _ReportHeader(
          title: 'FGEIs Evening Coaching Classes Wah Cantt.',
          subtitle: report.meta.reportTitle,
          collection: total?.collection ?? 0,
          paid: total?.paidStudents ?? 0,
          unpaid: total?.unpaidStudents ?? 0,
        ),

        const SizedBox(height: 13),

        const _SectionHeader('Final Financial Breakdown'),

        const SizedBox(height: 6),

        _ReadableTable(
          minWidth: 1200,
          headers: const [
            'Class',
            'Collection',
            'Teacher',
            'NTS',
            'Building',
            'Admin',
            'Organizer',
            'ECC',
            '100%',
          ],
          widths: const [110, 150, 145, 120, 130, 120, 135, 120, 140],
          rows: report.finalSummary
              .map(
                (row) => [
                  row.groupName == 'TOTAL' ? 'TOTAL' : row.groupName,
                  n(row.collection),
                  n(row.teacher),
                  n(row.nts),
                  n(row.building),
                  n(row.admin),
                  n(row.organizer),
                  n(row.ecc),
                  n(row.total),
                ],
              )
              .toList(),
        ),

        const SizedBox(height: 20),

        const _SectionHeader('Admin & NTS Staff Payment Summary'),

        const SizedBox(height: 6),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.fgGold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        color: AppTheme.fgNavyBlue,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Editable Fixed Staff Payments',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'These amounts are saved only for this selected month. Administrator and Organizer shares remain automatically calculated.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (staffSaving)
                      const Padding(
                        padding: EdgeInsets.only(left: 10, top: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 14),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    final cardWidth = wide
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: editableStaff.map((row) {
                        final amount = row.ntsPayment ?? row.totalPayment;

                        return SizedBox(
                          width: cardWidth,
                          child: Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  row.designation,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                Text(
                                  'Rs ${n(amount)}',
                                  style: const TextStyle(
                                    color: AppTheme.fgNavyBlue,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: staffSaving
                                          ? null
                                          : () => onEditStaff(row),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Edit'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: staffSaving
                                          ? null
                                          : () => onResetStaff(row),
                                      icon: const Icon(
                                        Icons.restart_alt_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Reset Default'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        _ReadableTable(
          minWidth: 1450,
          headers: const [
            'Name',
            'Designation',
            'Admin / Organizer',
            'NTS',
            'Total Payment',
            'Signature',
            'Remarks',
          ],
          widths: const [200, 260, 180, 140, 170, 180, 320],
          rows: report.staff
              .map(
                (row) => [
                  row.name,
                  row.designation,
                  row.sharePayment == null ? '' : n(row.sharePayment!),
                  row.ntsPayment == null ? '' : n(row.ntsPayment!),
                  n(row.totalPayment),
                  row.isTotal ? '' : '________________',
                  row.remarks ?? '',
                ],
              )
              .toList(),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}

// =============================================================================
// TABLE WIDGET
// =============================================================================

class _ReadableTable extends StatefulWidget {
  final List<String> headers;

  final List<List<String>> rows;

  final List<double> widths;

  final double minWidth;

  const _ReadableTable({
    required this.headers,
    required this.rows,
    required this.widths,
    required this.minWidth,
  });

  @override
  State<_ReadableTable> createState() => _ReadableTableState();
}

class _ReadableTableState extends State<_ReadableTable> {
  final ScrollController controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widths = <int, TableColumnWidth>{};

    for (int i = 0; i < widget.widths.length; i++) {
      widths[i] = FixedColumnWidth(widget.widths[i]);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: widget.minWidth,
              child: Table(
                columnWidths: widths,
                border: TableBorder.all(color: AppTheme.border, width: 0.8),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: AppTheme.fgNavyBlue.withValues(alpha: 0.10),
                    ),
                    children: widget.headers
                        .map((value) => _cell(value, header: true))
                        .toList(),
                  ),

                  ...widget.rows.map(
                    (row) => TableRow(
                      children: row.map((value) => _cell(value)).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(String value, {bool header = false}) {
    return Container(
      constraints: BoxConstraints(minHeight: header ? 54 : 52),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: header ? AppTheme.fgNavyBlue : AppTheme.textPrimary,
          fontSize: header ? 14 : 13.5,
          fontWeight: header ? FontWeight.w800 : FontWeight.w600,
          height: 1.25,
        ),
      ),
    );
  }
}

// =============================================================================
// COMMON REPORT UI
// =============================================================================

class _ReportHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final double collection;
  final int paid;
  final int unpaid;

  const _ReportHeader({
    required this.title,
    required this.subtitle,
    required this.collection,
    required this.paid,
    required this.unpaid,
  });

  static final NumberFormat _money = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.fgGold.withValues(alpha: 0.50)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.fgGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          Wrap(
            spacing: 8,
            children: [
              _HeaderStat(
                label: 'Collection',
                value: 'Rs ${_money.format(collection)}',
              ),
              _HeaderStat(label: 'Paid', value: '$paid'),
              _HeaderStat(label: 'Unpaid', value: '$unpaid'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;

  final String value;

  const _HeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),

          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.fgGold.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.fgNavyBlue,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SignaturePair extends StatelessWidget {
  const _SignaturePair();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _SignatureLine(title: 'Administrator')),
        SizedBox(width: 50),
        Expanded(child: _SignatureLine(title: 'Organizer')),
      ],
    );
  }
}

class _SignatureLine extends StatelessWidget {
  final String title;

  const _SignatureLine({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 36,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black45)),
          ),
        ),

        const SizedBox(height: 5),

        Text(
          title,
          style: const TextStyle(
            color: AppTheme.fgNavyBlue,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
