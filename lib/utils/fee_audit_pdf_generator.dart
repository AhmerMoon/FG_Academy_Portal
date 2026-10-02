import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/fee_audit_models.dart';
import '../models/fee_models.dart';

class FeeAuditPdfGenerator {
  FeeAuditPdfGenerator._();

  static final NumberFormat _money = NumberFormat('#,##0.00');

  static String money(double value) {
    return _money.format(value);
  }

  static String fileName({
    required FeeAuditReportBundle report,
    required String sheetKey,
  }) {
    final sheet = sheetKey.replaceAll(' ', '_').replaceAll('/', '_');

    final month = report.paymentMonth.replaceAll('-', '_');

    return 'FG_Academy_${sheet}_$month.pdf';
  }

  static Future<Uint8List> buildSheet({
    required FeeAuditReportBundle report,
    required String sheetKey,
  }) async {
    final pdf = pw.Document(
      title: 'FG Academy $sheetKey ${report.paymentMonth}',
      author: 'FG Academy Portal',
      creator: 'FG Academy Portal',
    );

    if (report.availableClassCodes.contains(sheetKey)) {
      _addClassSheet(pdf, report, sheetKey);
    } else if (sheetKey == 'SSC Summary') {
      _addLevelSummary(pdf, report, 'SSC');
    } else if (sheetKey == 'HSSC Summary') {
      _addLevelSummary(pdf, report, 'HSSC');
    } else if (sheetKey == 'Final Summary') {
      _addFinalSummary(pdf, report);
    } else {
      throw ArgumentError('Unknown sheet: $sheetKey');
    }

    return pdf.save();
  }

  // ===========================================================================
  // CLASS SHEET - SINGLE PAGE GUARANTEED
  // ===========================================================================

  static void _addClassSheet(
    pw.Document pdf,
    FeeAuditReportBundle report,
    String classCode,
  ) {
    final total = report.totalForClass(classCode);

    if (total == null) {
      throw StateError('Report unavailable for $classCode');
    }

    final students = report.studentsForClass(classCode);

    final groups = <String, List<FeeAuditClassStudentRow>>{};

    for (final student in students) {
      groups.putIfAbsent(student.subjectGroup, () => []).add(student);
    }

    final content = <pw.Widget>[];

    for (final entry in groups.entries) {
      content.add(_compactGroupHeading(entry.key));

      content.add(pw.SizedBox(height: 2));

      content.add(_studentTable(total, entry.value));

      content.add(pw.SizedBox(height: 4));
    }

    content.add(_classTotals(total));

    content.add(pw.SizedBox(height: 8));

    content.add(_twoSignatures());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(6, 6, 6, 7),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(
                'ECC FEE RECORD - ${total.batchName.toUpperCase()}',
                report.paymentMonth,
              ),

              pw.Expanded(
                child: pw.FittedBox(
                  fit: pw.BoxFit.contain,
                  alignment: pw.Alignment.topCenter,
                  child: pw.SizedBox(
                    width: 810,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: content,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static pw.Widget _studentTable(
    FeeAuditClassTotal total,
    List<FeeAuditClassStudentRow> rows,
  ) {
    return pw.TableHelper.fromTextArray(
      headers: [
        'Sr',
        'Name',
        'Fee',
        total.levelGroup == 'SSC' ? 'Teacher 60%' : 'Teacher 63%',
        'NTS',
        'Building',
        'Admin',
        'Org',
        'ECC',
        'Math',
        'Phy',
        'Comp',
        'Chem',
        'Eng',
        'Bio',
      ],
      data: rows
          .map(
            (row) => [
              row.groupSrNo.toString(),
              row.studentName,
              money(row.amountPaid),
              money(row.teacherShare),
              money(row.nts),
              money(row.building),
              money(row.admin),
              money(row.organizer),
              money(row.ecc),
              money(row.math),
              money(row.physics),
              money(row.computer),
              money(row.chemistry),
              money(row.english),
              money(row.biology),
            ],
          )
          .toList(),

      columnWidths: {
        0: const pw.FixedColumnWidth(21),
        1: const pw.FixedColumnWidth(122),
        2: const pw.FixedColumnWidth(50),
        3: const pw.FixedColumnWidth(57),
        4: const pw.FixedColumnWidth(44),
        5: const pw.FixedColumnWidth(52),
        6: const pw.FixedColumnWidth(47),
        7: const pw.FixedColumnWidth(43),
        8: const pw.FixedColumnWidth(43),
        9: const pw.FixedColumnWidth(47),
        10: const pw.FixedColumnWidth(47),
        11: const pw.FixedColumnWidth(47),
        12: const pw.FixedColumnWidth(47),
        13: const pw.FixedColumnWidth(47),
        14: const pw.FixedColumnWidth(47),
      },

      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 6.4,
        fontWeight: pw.FontWeight.bold,
      ),

      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),

      cellStyle: const pw.TextStyle(fontSize: 6.15),

      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.8),

      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.32),
    );
  }

  static pw.Widget _classTotals(FeeAuditClassTotal total) {
    return pw.TableHelper.fromTextArray(
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
      data: [
        [
          total.classCode,
          money(total.collection),
          money(total.teacherShare),
          money(total.nts),
          money(total.building),
          money(total.admin),
          money(total.organizer),
          money(total.ecc),
          money(total.totalDistributed),
        ],
      ],
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 6.6,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellPadding: const pw.EdgeInsets.all(2.6),
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.35),
    );
  }

  // ===========================================================================
  // SSC / HSSC
  // ===========================================================================

  static void _addLevelSummary(
    pw.Document pdf,
    FeeAuditReportBundle report,
    String level,
  ) {
    final ssc = level == 'SSC';

    final codes = ssc
        ? ['9B', '9G', '10B', '10G']
        : ['XIB', 'XIG', 'XIIB', 'XIIG'];

    final subjects = ssc ? report.sscSubjects : report.hsscSubjects;

    final summary = report.summaryFor(level);

    final subjectRows = <List<String>>[];

    subjectRows.add([
      'Total Collection',
      ...codes.map(
        (code) => money(report.totalForClass(code)?.collection ?? 0),
      ),
      money(summary?.collection ?? 0),
      '',
      '',
    ]);

    for (final subject in subjects) {
      subjectRows.add([
        feeSubjectLabel(subject.subjectCode),
        ...codes.map((code) => money(subject.classAmounts[code] ?? 0)),
        money(subject.totalAmount),
        subject.teacherName,
        '________________',
      ]);
    }

    subjectRows.add([
      'Total Teacher Share',
      ...codes.map(
        (code) => money(report.totalForClass(code)?.teacherShare ?? 0),
      ),
      money(summary?.teacher ?? 0),
      '',
      '',
    ]);

    final fundRows = codes.map((code) {
      final row = report.totalForClass(code);

      return [
        code,
        money(row?.collection ?? 0),
        money(row?.teacherShare ?? 0),
        money(row?.nts ?? 0),
        money(row?.building ?? 0),
        money(row?.admin ?? 0),
        money(row?.organizer ?? 0),
        money(row?.ecc ?? 0),
        money(row?.totalDistributed ?? 0),
      ];
    }).toList();

    if (summary != null) {
      fundRows.add([
        'TOTAL',
        money(summary.collection),
        money(summary.teacher),
        money(summary.nts),
        money(summary.building),
        money(summary.admin),
        money(summary.organizer),
        money(summary.ecc),
        money(summary.total),
      ]);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(12),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(
                'FGEIs Evening Coaching Classes - $level Subject Wise Summary',
                report.paymentMonth,
              ),

              _sectionTitle('Teacher Subject Payments'),

              pw.SizedBox(height: 5),

              pw.TableHelper.fromTextArray(
                headers: [
                  'Subject',
                  ...codes,
                  'Total',
                  'Teacher Name',
                  'Signature',
                ],
                data: subjectRows,
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey900,
                ),
                cellStyle: const pw.TextStyle(fontSize: 7.1),
                cellPadding: const pw.EdgeInsets.all(3.8),
                border: pw.TableBorder.all(
                  color: PdfColors.grey500,
                  width: 0.35,
                ),
              ),

              pw.SizedBox(height: 11),

              _sectionTitle('$level Fund Breakdown'),

              pw.SizedBox(height: 5),

              pw.TableHelper.fromTextArray(
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
                data: fundRows,
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 6.9,
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey800,
                ),
                cellStyle: const pw.TextStyle(fontSize: 6.8),
                cellPadding: const pw.EdgeInsets.all(3.5),
                border: pw.TableBorder.all(
                  color: PdfColors.grey500,
                  width: 0.35,
                ),
              ),

              pw.Spacer(),

              _twoSignatures(),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // FINAL SUMMARY - PORTRAIT
  // ===========================================================================

  static void _addFinalSummary(pw.Document pdf, FeeAuditReportBundle report) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(16, 16, 16, 18),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(
                'FGEIs Evening Coaching Classes Wah Cantt.',
                report.meta.reportTitle,
              ),

              _sectionTitle('Final Financial Summary'),

              pw.SizedBox(height: 5),

              pw.TableHelper.fromTextArray(
                headers: const [
                  'Group',
                  'Collection',
                  'Teacher',
                  'NTS',
                  'Build.',
                  'Admin',
                  'Org.',
                  'ECC',
                  '100%',
                ],
                data: report.finalSummary
                    .map(
                      (row) => [
                        row.groupName == 'TOTAL' ? 'TOTAL' : row.groupName,
                        money(row.collection),
                        money(row.teacher),
                        money(row.nts),
                        money(row.building),
                        money(row.admin),
                        money(row.organizer),
                        money(row.ecc),
                        money(row.total),
                      ],
                    )
                    .toList(),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 5.9,
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey900,
                ),
                cellStyle: const pw.TextStyle(fontSize: 5.8),
                cellPadding: const pw.EdgeInsets.all(3),
                border: pw.TableBorder.all(
                  color: PdfColors.grey500,
                  width: 0.35,
                ),
              ),

              pw.SizedBox(height: 12),

              _sectionTitle('Admin & NTS Staff Payment Summary'),

              pw.SizedBox(height: 5),

              pw.TableHelper.fromTextArray(
                headers: const [
                  'Name',
                  'Designation',
                  'Admin / Org.',
                  'NTS',
                  'Total',
                  'Signature',
                  'Remarks',
                ],
                data: report.staff
                    .map(
                      (row) => [
                        row.name,
                        row.designation,
                        row.sharePayment == null
                            ? ''
                            : money(row.sharePayment!),
                        row.ntsPayment == null ? '' : money(row.ntsPayment!),
                        money(row.totalPayment),
                        row.isTotal ? '' : '____________',
                        row.remarks ?? '',
                      ],
                    )
                    .toList(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.25),
                  1: const pw.FlexColumnWidth(1.45),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(0.8),
                  4: const pw.FlexColumnWidth(0.9),
                  5: const pw.FlexColumnWidth(1),
                  6: const pw.FlexColumnWidth(1.7),
                },
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 6,
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey800,
                ),
                cellStyle: const pw.TextStyle(fontSize: 5.8),
                cellPadding: const pw.EdgeInsets.all(3),
                border: pw.TableBorder.all(
                  color: PdfColors.grey500,
                  width: 0.35,
                ),
              ),

              pw.SizedBox(height: 11),

              _sectionTitle('ECC Balance'),

              pw.SizedBox(height: 5),

              pw.TableHelper.fromTextArray(
                headers: const ['Item', 'Amount'],
                data: [
                  [
                    'Previous ECC Balance',
                    money(report.meta.previousEccBalance),
                  ],
                  [
                    'Current ECC Collection',
                    money(report.meta.currentEccCollection),
                  ],
                  ['Total ECC Balance', money(report.meta.totalEccBalance)],
                  [report.meta.expensesLabel, money(report.meta.expenses)],
                  [
                    report.meta.closingBalanceLabel,
                    money(report.meta.closingEccBalance),
                  ],
                ],
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 6.8,
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey800,
                ),
                cellStyle: const pw.TextStyle(fontSize: 6.8),
                cellPadding: const pw.EdgeInsets.all(3.5),
                border: pw.TableBorder.all(
                  color: PdfColors.grey500,
                  width: 0.35,
                ),
              ),

              if (report.meta.sopRemark.trim().isNotEmpty) ...[
                pw.SizedBox(height: 9),

                _note(report.meta.sopRemark),
              ],

              if (report.meta.approvalNote.trim().isNotEmpty) ...[
                pw.SizedBox(height: 6),

                _note(report.meta.approvalNote),
              ],

              pw.Spacer(),

              _portraitSignatures(),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // PDF COMMON
  // ===========================================================================

  static pw.Widget _header(String title, String subtitle) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              title,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),

          pw.SizedBox(width: 8),

          pw.Text(
            subtitle,
            style: const pw.TextStyle(color: PdfColors.amber200, fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  static pw.Widget _compactGroupHeading(String value) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      color: PdfColors.grey200,
      child: pw.Text(
        value,
        style: pw.TextStyle(
          color: PdfColors.blueGrey900,
          fontSize: 6.6,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _sectionTitle(String value) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      color: PdfColors.grey200,
      child: pw.Text(
        value,
        style: pw.TextStyle(
          color: PdfColors.blueGrey900,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _note(String value) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.35),
      ),
      child: pw.Text(value, style: const pw.TextStyle(fontSize: 6.2)),
    );
  }

  static pw.Widget _twoSignatures() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [_signature('Administrator'), _signature('Organizer')],
    );
  }

  static pw.Widget _portraitSignatures() {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _signature('Administrator', width: 180),

            _signature('Organizer', width: 180),
          ],
        ),

        pw.SizedBox(height: 22),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _signature('GSO-I\nFGEIs(C/G) Wah Region', width: 180),

            _signature('Regional Director\nFGEIs(C/G) Wah Region', width: 180),
          ],
        ),
      ],
    );
  }

  static pw.Widget _signature(String label, {double width = 130}) {
    return pw.SizedBox(
      width: width,
      child: pw.Column(
        children: [
          pw.Container(
            height: 17,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.45)),
            ),
          ),

          pw.SizedBox(height: 2),

          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 6.2, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
