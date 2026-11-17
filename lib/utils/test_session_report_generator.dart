import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/test_session_models.dart';

class TestSessionReportGenerator {
  TestSessionReportGenerator._();

  static Future<Uint8List> generate(TestSessionReportData data) async {
    final combined = data.columns.length > 1;
    final width = combined ? 1680.0 : 1120.0;
    const margin = 28.0;
    const titleHeight = 138.0;
    const headerHeight = 72.0;
    const rowHeight = 48.0;
    const footerHeight = 64.0;
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
    final border = Paint()
      ..color = const Color(0xFF25364D)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final navy = Paint()..color = const Color(0xFF092A57);
    final gold = Paint()..color = const Color(0xFFD6B247);
    final contentWidth = width - margin * 2;
    var y = margin;

    canvas.drawRect(Rect.fromLTWH(margin, y, contentWidth, titleHeight), navy);
    _text(
      canvas,
      'FGEIs ECC WAH',
      Rect.fromLTWH(margin + 20, y + 14, contentWidth - 40, 38),
      size: 28,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
    _text(
      canvas,
      '${data.batchName} · TEST ${data.testNo} · ${data.title}',
      Rect.fromLTWH(margin + 20, y + 55, contentWidth - 40, 40),
      size: 23,
      color: const Color(0xFFFFE28A),
      weight: FontWeight.w800,
      align: TextAlign.center,
    );
    _text(
      canvas,
      '${data.completedSubjects}/${data.requiredSubjects} required subjects finalized',
      Rect.fromLTWH(margin + 20, y + 99, contentWidth - 40, 28),
      size: 14,
      color: Colors.white70,
      weight: FontWeight.w600,
      align: TextAlign.center,
    );
    y += titleHeight;

    const serialWidth = 62.0;
    final nameWidth = combined ? 350.0 : 650.0;
    final resultWidth =
        (contentWidth - serialWidth - nameWidth) / data.columns.length;
    canvas.drawRect(Rect.fromLTWH(margin, y, contentWidth, headerHeight), gold);
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
      'Student Name',
      margin + serialWidth,
      y,
      nameWidth,
      headerHeight,
      border,
      bold: true,
    );
    for (var index = 0; index < data.columns.length; index++) {
      final column = data.columns[index];
      final total = column.maxMarks == null
          ? ''
          : '\n/${_number(column.maxMarks!)}';
      _cell(
        canvas,
        '${column.label}$total',
        margin + serialWidth + nameWidth + index * resultWidth,
        y,
        resultWidth,
        headerHeight,
        border,
        bold: true,
        fontSize: combined ? 14 : 17,
      );
    }
    y += headerHeight;

    for (var rowIndex = 0; rowIndex < data.rows.length; rowIndex++) {
      final row = data.rows[rowIndex];
      if (rowIndex.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(margin, y, contentWidth, rowHeight),
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
        row.name,
        margin + serialWidth,
        y,
        nameWidth,
        rowHeight,
        border,
        left: true,
        bold: true,
      );
      for (
        var columnIndex = 0;
        columnIndex < data.columns.length;
        columnIndex++
      ) {
        final column = data.columns[columnIndex];
        _cell(
          canvas,
          row.cells[column.key] ?? '—',
          margin + serialWidth + nameWidth + columnIndex * resultWidth,
          y,
          resultWidth,
          rowHeight,
          border,
          fontSize: combined ? 14 : 17,
        );
      }
      y += rowHeight;
    }

    _text(
      canvas,
      'A = Absent  ·  — = Not applicable / not entered  ·  Generated from Academy Portal',
      Rect.fromLTWH(margin + 12, y + 15, contentWidth - 24, 30),
      size: 13,
      color: const Color(0xFF536173),
      weight: FontWeight.w600,
      align: TextAlign.center,
    );

    if (data.incomplete) {
      canvas.save();
      canvas.translate(width / 2, height / 2);
      canvas.rotate(-0.32);
      _text(
        canvas,
        'INCOMPLETE REPORT',
        Rect.fromCenter(center: Offset.zero, width: width * 0.75, height: 100),
        size: 54,
        color: const Color(0x55C63B4B),
        weight: FontWeight.w900,
        align: TextAlign.center,
      );
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) throw StateError('Could not generate report PNG.');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
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
    double fontSize = 15,
  }) {
    final rect = Rect.fromLTWH(x, y, width, height);
    canvas.drawRect(rect, border);
    _text(
      canvas,
      value,
      Rect.fromLTWH(
        x + (left ? 12 : 5),
        y + 4,
        width - (left ? 18 : 10),
        height - 8,
      ),
      size: fontSize,
      color: const Color(0xFF142038),
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
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);
    final dx = align == TextAlign.center
        ? rect.left + (rect.width - painter.width) / 2
        : rect.left;
    final dy = rect.top + (rect.height - painter.height) / 2;
    painter.paint(canvas, Offset(dx, dy));
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
