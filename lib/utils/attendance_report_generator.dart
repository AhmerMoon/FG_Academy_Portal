import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_report_models.dart';

class AttendanceReportGenerator {
  AttendanceReportGenerator._();

  static Future<Uint8List> generatePng(AttendanceReportData data) async {
    const margin = 26.0;
    const serialWidth = 58.0;
    const nameWidth = 300.0;
    const dayWidth = 48.0;
    const titleHeight = 126.0;
    const headerHeight = 58.0;
    const rowHeight = 45.0;
    const footerHeight = 58.0;
    final tableWidth =
        serialWidth + nameWidth + data.attendanceDays.length * dayWidth;
    final width = tableWidth + margin * 2;
    final height =
        margin * 2 +
        titleHeight +
        headerHeight +
        data.rows.length * rowHeight +
        footerHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );
    final navy = Paint()..color = const Color(0xFF092A57);
    final gold = Paint()..color = const Color(0xFFD6B247);
    final border = Paint()
      ..color = const Color(0xFF26384D)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    var y = margin;

    canvas.drawRect(Rect.fromLTWH(margin, y, tableWidth, titleHeight), navy);
    _text(
      canvas,
      'FGEIs Evening Coaching Classes',
      Rect.fromLTWH(margin + 18, y + 17, tableWidth - 36, 40),
      size: 27,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
    _text(
      canvas,
      'Attendance Report for ${DateFormat('MMMM yyyy').format(data.month)}',
      Rect.fromLTWH(margin + 18, y + 60, tableWidth - 36, 30),
      size: 21,
      color: const Color(0xFFFFE28A),
      weight: FontWeight.w800,
      align: TextAlign.center,
    );
    _text(
      canvas,
      data.batchName,
      Rect.fromLTWH(margin + 18, y + 92, tableWidth - 36, 24),
      size: 17,
      color: Colors.white,
      weight: FontWeight.w700,
      align: TextAlign.center,
    );
    y += titleHeight;

    canvas.drawRect(Rect.fromLTWH(margin, y, tableWidth, headerHeight), gold);
    _cell(
      canvas,
      '#',
      margin,
      y,
      serialWidth,
      headerHeight,
      border,
      bold: true,
    );
    _cell(
      canvas,
      'Name of Student',
      margin + serialWidth,
      y,
      nameWidth,
      headerHeight,
      border,
      bold: true,
      left: true,
    );
    for (var index = 0; index < data.attendanceDays.length; index++) {
      _cell(
        canvas,
        '${data.attendanceDays[index]}',
        margin + serialWidth + nameWidth + index * dayWidth,
        y,
        dayWidth,
        headerHeight,
        border,
        bold: true,
      );
    }
    y += headerHeight;

    for (var rowIndex = 0; rowIndex < data.rows.length; rowIndex++) {
      final row = data.rows[rowIndex];
      if (rowIndex.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(margin, y, tableWidth, rowHeight),
          Paint()..color = const Color(0xFFF4F7FA),
        );
      }
      _cell(
        canvas,
        '${rowIndex + 1}',
        margin,
        y,
        serialWidth,
        rowHeight,
        border,
      );
      _cell(
        canvas,
        row.studentName,
        margin + serialWidth,
        y,
        nameWidth,
        rowHeight,
        border,
        left: true,
        bold: true,
      );
      for (
        var dayIndex = 0;
        dayIndex < data.attendanceDays.length;
        dayIndex++
      ) {
        final day = data.attendanceDays[dayIndex];
        final status = row.statusByDay[day];
        final value = switch (status) {
          'present' => 'P',
          'absent' => 'A',
          'leave' => 'L',
          _ => '',
        };
        final background = switch (status) {
          'present' => const Color(0xFFDCFCE7),
          'absent' => const Color(0xFFFEE2E2),
          'leave' => const Color(0xFFFFF4CC),
          _ => null,
        };
        _cell(
          canvas,
          value,
          margin + serialWidth + nameWidth + dayIndex * dayWidth,
          y,
          dayWidth,
          rowHeight,
          border,
          bold: value.isNotEmpty,
          background: background,
          color: status == 'absent'
              ? const Color(0xFF991B1B)
              : status == 'present'
              ? const Color(0xFF166534)
              : const Color(0xFF725400),
        );
      }
      y += rowHeight;
    }

    _text(
      canvas,
      'P = Present   |   A = Absent   |   L = Leave   |   Blank = Not marked',
      Rect.fromLTWH(margin + 10, y + 14, tableWidth - 20, 30),
      size: 13,
      color: const Color(0xFF536173),
      weight: FontWeight.w600,
      align: TextAlign.center,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) throw StateError('Could not generate attendance PNG.');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }

  static Future<Uint8List> generateCombinedPdf(
    List<MapEntry<AttendanceReportData, Uint8List>> reports,
  ) async {
    if (reports.isEmpty) {
      throw StateError('No attendance reports are available for this month.');
    }
    final document = pw.Document();
    for (final report in reports) {
      final image = pw.MemoryImage(report.value);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a3.landscape,
          margin: const pw.EdgeInsets.all(18),
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    return document.save();
  }

  static void _cell(
    Canvas canvas,
    String value,
    double x,
    double y,
    double width,
    double height,
    Paint border, {
    bool bold = false,
    bool left = false,
    Color? background,
    Color color = const Color(0xFF142038),
  }) {
    final rect = Rect.fromLTWH(x, y, width, height);
    if (background != null) {
      canvas.drawRect(rect, Paint()..color = background);
    }
    canvas.drawRect(rect, border);
    _text(
      canvas,
      value,
      Rect.fromLTWH(
        x + (left ? 11 : 4),
        y + 4,
        width - (left ? 16 : 8),
        height - 8,
      ),
      size: left ? 14 : 15,
      color: color,
      weight: bold ? FontWeight.w800 : FontWeight.w600,
      align: left ? TextAlign.left : TextAlign.center,
    );
  }

  static void _text(
    Canvas canvas,
    String value,
    Rect rect, {
    required double size,
    required Color color,
    required FontWeight weight,
    required TextAlign align,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textAlign: align,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);
    final dx = align == TextAlign.center
        ? rect.left + (rect.width - painter.width) / 2
        : rect.left;
    final dy = rect.top + (rect.height - painter.height) / 2;
    painter.paint(canvas, Offset(dx, dy));
  }
}
