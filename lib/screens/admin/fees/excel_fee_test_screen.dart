import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/excel_fee_models.dart';
import '../../../services/excel_fee_service.dart';
import '../../../utils/dashboard_section_header.dart';
import '../../../utils/error_state_view.dart';

class ExcelFeeTestScreen extends StatefulWidget {
  final VoidCallback onBack;

  const ExcelFeeTestScreen({super.key, required this.onBack});

  @override
  State<ExcelFeeTestScreen> createState() => _ExcelFeeTestScreenState();
}

class _ExcelFeeTestScreenState extends State<ExcelFeeTestScreen> {
  final ExcelFeeService _service = ExcelFeeService();

  final NumberFormat _numberFormat = NumberFormat('#,##0.##');

  ExcelFeeCatalog? _catalog;

  ExcelFeeWorkbook? _workbook;

  String? _selectedFileName;

  int _selectedSheetIndex = 0;

  bool _loading = true;

  bool _loadingWorkbook = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _bootstrap();
  }

  ExcelFeeSheet? get _selectedSheet {
    final workbook = _workbook;

    if (workbook == null || workbook.sheets.isEmpty) {
      return null;
    }

    if (_selectedSheetIndex < 0 ||
        _selectedSheetIndex >= workbook.sheets.length) {
      return workbook.sheets.first;
    }

    return workbook.sheets[_selectedSheetIndex];
  }

  Future<void> _bootstrap() async {
    await _reloadEverything();
  }

  Future<void> _reloadEverything({String? preferredFile}) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!_service.isSupported) {
        throw StateError(
          'Excel Fees Test is '
          'available only on Windows.',
        );
      }

      final catalog = await _service.fetchCatalog();

      String? selected = preferredFile ?? _selectedFileName;

      if (selected == null ||
          !catalog.files.any((file) => file.fileName == selected)) {
        selected = catalog.files.isEmpty ? null : catalog.files.first.fileName;
      }

      ExcelFeeWorkbook? workbook;

      if (selected != null) {
        workbook = await _service.fetchWorkbook(selected);
      }

      if (!mounted) return;

      setState(() {
        _catalog = catalog;

        _selectedFileName = selected;

        _workbook = workbook;

        _selectedSheetIndex = 0;

        _loading = false;
        _loadingWorkbook = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Excel fee test load error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _loadingWorkbook = false;

        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _selectWorkbook(String fileName) async {
    if (fileName == _selectedFileName) {
      return;
    }

    setState(() {
      _selectedFileName = fileName;

      _loadingWorkbook = true;

      _selectedSheetIndex = 0;

      _error = null;
    });

    try {
      final workbook = await _service.fetchWorkbook(fileName);

      if (!mounted) return;

      setState(() {
        _workbook = workbook;

        _loadingWorkbook = false;

        _selectedSheetIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingWorkbook = false;

        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    final value = error.toString().replaceFirst('Bad state: ', '');

    if (value.contains('Invalid class string')) {
      return 'Microsoft Excel '
          'could not be started.';
    }

    return value;
  }

  String _cellText(Object? value) {
    if (value == null) {
      return '';
    }

    if (value is num) {
      return _numberFormat.format(value);
    }

    return value.toString();
  }

  String _normalize(Object? value) {
    return _cellText(value).replaceAll('\n', ' ').trim().toLowerCase();
  }

  bool _isTitleRow(List<Object?> row, int index) {
    if (index > 1) {
      return false;
    }

    final populated = row
        .where((value) => _cellText(value).trim().isNotEmpty)
        .length;

    return populated == 1;
  }

  bool _looksLikeHeader(List<Object?> row) {
    const keywords = {
      'class',
      'subject',
      'subjects',
      'name',
      'name of teacher',
      'teacher name',
      'fees',
      'total collection',
      'designation',
      'desgination',
      'signature',
      'remarks',
      'sr. no.',
      'sr. no',
    };

    var hits = 0;

    for (final value in row) {
      final normalized = _normalize(value);

      if (keywords.contains(normalized)) {
        hits++;
      }
    }

    return hits >= 2;
  }

  bool _isTotalRow(List<Object?> row) {
    final first = row
        .map(_normalize)
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    return first == 'total' ||
        first == 'grand total' ||
        first.startsWith('total teacher') ||
        first.startsWith('total coll');
  }

  Map<int, TableColumnWidth> _columnWidths(ExcelFeeSheet sheet) {
    final widths = <int, TableColumnWidth>{};

    for (var column = 0; column < sheet.columnCount; column++) {
      var maxLength = 0;

      for (final row in sheet.rows.take(50)) {
        if (column >= row.length) {
          continue;
        }

        final text = _cellText(row[column]);

        if (text.length > maxLength) {
          maxLength = text.length;
        }
      }

      final width = (70.0 + maxLength.clamp(0, 20) * 6.5).clamp(95.0, 220.0);

      widths[column] = FixedColumnWidth(width);
    }

    return widths;
  }

  Widget _buildTestBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 3, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.45)),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, color: AppTheme.warning, size: 27),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'TEST MODE • LOCAL EXCEL\n'
              'Existing Supabase Fees '
              'system is untouched. '
              'Save the Excel file before '
              'pressing Refresh.',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkbookSelector() {
    final catalog = _catalog;

    if (catalog == null) {
      return const SizedBox.shrink();
    }

    if (catalog.files.isEmpty) {
      return Card(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No Excel fee file found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 9),

              const Text(
                'Put a workbook in this '
                'folder using the name '
                'Fee_YYYY-MM.xlsx.',
                style: TextStyle(fontSize: 14),
              ),

              const SizedBox(height: 10),

              SelectableText(
                catalog.dataDir,
                style: const TextStyle(
                  color: AppTheme.fgNavyBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Example: '
                'Fee_2026-09.xlsx',
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final selector = DropdownButtonFormField<String>(
              key: ValueKey(_selectedFileName),
              initialValue: _selectedFileName,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Excel Fee Month',
                prefixIcon: Icon(Icons.table_chart_outlined),
              ),
              items: catalog.files
                  .map(
                    (file) => DropdownMenuItem(
                      value: file.fileName,
                      child: Text(file.label),
                    ),
                  )
                  .toList(),
              onChanged: _loadingWorkbook
                  ? null
                  : (value) {
                      if (value != null) {
                        _selectWorkbook(value);
                      }
                    },
            );

            final path = SelectableText(
              catalog.dataDir,
              maxLines: 2,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
              ),
            );

            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [selector, const SizedBox(height: 9), path],
              );
            }

            return Row(
              children: [
                SizedBox(width: 330, child: selector),

                const SizedBox(width: 15),

                Expanded(child: path),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetrics(ExcelFeeWorkbook workbook) {
    if (workbook.keyMetrics.isEmpty) {
      return const SizedBox.shrink();
    }

    const order = [
      'collection',
      'teacher',
      'nts',
      'building',
      'admin',
      'organizer',
      'ecc',
    ];

    const labels = {
      'collection': 'Total Collection',
      'teacher': 'Teacher Payment',
      'nts': 'NTS',
      'building': 'Building',
      'admin': 'Admin',
      'organizer': 'Organizer',
      'ecc': 'ECC',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 1, 10, 9),
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          for (final key in order)
            if (workbook.keyMetrics.containsKey(key))
              _MetricTile(
                label: labels[key] ?? key,
                value: _numberFormat.format(workbook.keyMetrics[key]),
              ),
        ],
      ),
    );
  }

  Widget _buildSheetSelector(ExcelFeeWorkbook workbook) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Row(
        children: [
          for (var index = 0; index < workbook.sheets.length; index++) ...[
            ChoiceChip(
              label: Text(workbook.sheets[index].name),
              selected: index == _selectedSheetIndex,
              onSelected: (_) {
                setState(() {
                  _selectedSheetIndex = index;
                });
              },
            ),

            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(ExcelFeeSheet sheet) {
    final widths = _columnWidths(sheet);

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            color: AppTheme.surfaceSoft,
            child: Row(
              children: [
                const Icon(Icons.grid_on_rounded, color: AppTheme.fgNavyBlue),

                const SizedBox(width: 9),

                Expanded(
                  child: Text(
                    sheet.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

                Text(
                  '${sheet.rowCount} rows'
                  ' • '
                  '${sheet.columnCount} cols',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: widths,
                  border: TableBorder.all(color: AppTheme.border, width: 0.7),
                  children: [
                    for (
                      var rowIndex = 0;
                      rowIndex < sheet.rows.length;
                      rowIndex++
                    )
                      _buildTableRow(
                        sheet.rows[rowIndex],
                        rowIndex,
                        sheet.columnCount,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(List<Object?> rawRow, int rowIndex, int columnCount) {
    final row = [
      ...rawRow,
      ...List<Object?>.filled(
        (columnCount - rawRow.length).clamp(0, columnCount),
        null,
      ),
    ];

    final title = _isTitleRow(row, rowIndex);

    final header = !title && _looksLikeHeader(row);

    final total = !title && !header && _isTotalRow(row);

    Color background = Colors.white;

    Color foreground = AppTheme.textPrimary;

    FontWeight weight = FontWeight.w500;

    if (title) {
      background = AppTheme.fgNavyBlue;

      foreground = Colors.white;

      weight = FontWeight.w800;
    } else if (header) {
      background = AppTheme.goldSoft;

      foreground = AppTheme.fgNavyBlue;

      weight = FontWeight.w800;
    } else if (total) {
      background = AppTheme.surfaceSoft;

      weight = FontWeight.w800;
    }

    return TableRow(
      decoration: BoxDecoration(color: background),
      children: [
        for (var column = 0; column < columnCount; column++)
          Container(
            constraints: const BoxConstraints(minHeight: 43),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            alignment: Alignment.centerLeft,
            child: SelectableText(
              column < row.length ? _cellText(row[column]) : '',
              style: TextStyle(
                color: foreground,
                fontSize: title ? 14 : 12.5,
                fontWeight: weight,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Expanded(
        child: ErrorStateView(message: _error!, onRetry: _bootstrap),
      );
    }

    final catalog = _catalog;

    if (catalog == null) {
      return const Expanded(
        child: Center(child: Text('Excel catalog unavailable.')),
      );
    }

    if (catalog.files.isEmpty) {
      return Expanded(child: ListView(children: [_buildWorkbookSelector()]));
    }

    if (_loadingWorkbook) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    final workbook = _workbook;

    if (workbook == null) {
      return const Expanded(child: Center(child: Text('Workbook not loaded.')));
    }

    final sheet = _selectedSheet;

    if (sheet == null) {
      return const Expanded(
        child: Center(child: Text('No report sheets found.')),
      );
    }

    return Expanded(
      child: Column(
        children: [
          _buildMetrics(workbook),

          _buildSheetSelector(workbook),

          Expanded(child: _buildGrid(sheet)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DashboardSectionHeader(
          title: 'Excel Fees • Test',
          subtitle:
              'Local Excel financial '
              'source — Supabase fees '
              'remain unchanged',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Refresh Excel',
                color: Colors.white,
                onPressed: _loading || _loadingWorkbook
                    ? null
                    : () {
                        _reloadEverything(preferredFile: _selectedFileName);
                      },
                icon: const Icon(Icons.refresh_rounded),
              ),

              IconButton(
                tooltip: 'Back',
                color: Colors.white,
                onPressed: widget.onBack,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),

        _buildTestBanner(),

        if (!_loading && _error == null) _buildWorkbookSelector(),

        _buildBody(),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 155),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            value,
            style: const TextStyle(
              color: AppTheme.fgNavyBlue,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
