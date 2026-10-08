import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/award_progress_service.dart';

class AwardProgressImageGenerator {
  static Future<Uint8List> generate(AwardProgressBundle data) async {
    const margin = 28.0;
    const serialWidth = 64.0;
    const testWidth = 118.0;

    const titleHeight = 105.0;
    const infoHeight = 58.0;
    const headerHeight = 78.0;
    const rowHeight = 50.0;
    const footerHeight = 78.0;

    final nameWidth = _calculateNameWidth(data.students);

    final tableWidth =
        serialWidth + nameWidth + (data.tests.length * testWidth);

    final pageWidth = tableWidth + (margin * 2);

    final pageHeight =
        margin +
        titleHeight +
        infoHeight +
        headerHeight +
        (data.students.length * rowHeight) +
        footerHeight +
        margin;

    final recorder = ui.PictureRecorder();

    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, pageWidth, pageHeight));

    final blackBorder = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final outerBorder = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, pageWidth, pageHeight),
      Paint()..color = Colors.white,
    );

    final left = margin;

    var y = margin;

    canvas.drawRect(
      Rect.fromLTWH(left, y, tableWidth, pageHeight - (margin * 2)),
      outerBorder,
    );

    // ========================================================
    // TITLE
    // ========================================================

    _centerText(
      canvas,
      'FGEIs ECC Wah',
      Rect.fromLTWH(left, y + 8, tableWidth, 36),
      fontSize: 27,
      weight: FontWeight.w900,
    );

    _centerText(
      canvas,
      '${data.batchName} • '
      '${data.subjectName} '
      'Progress Sheet',
      Rect.fromLTWH(left + 10, y + 49, tableWidth - 20, 38),
      fontSize: 23,
      weight: FontWeight.w900,
    );

    y += titleHeight;

    canvas.drawLine(Offset(left, y), Offset(left + tableWidth, y), blackBorder);

    // ========================================================
    // INFO
    // ========================================================

    _leftText(
      canvas,
      'Tests: ${data.tests.length}',
      Rect.fromLTWH(left + 14, y, tableWidth * 0.30, infoHeight),
      fontSize: 16,
      weight: FontWeight.w700,
    );

    _centerText(
      canvas,
      'Students: ${data.students.length}',
      Rect.fromLTWH(
        left + (tableWidth * 0.30),
        y,
        tableWidth * 0.30,
        infoHeight,
      ),
      fontSize: 16,
      weight: FontWeight.w700,
    );

    _rightText(
      canvas,
      'Prepared By: '
      '${data.preparedBy}',
      Rect.fromLTWH(
        left + (tableWidth * 0.58),
        y,
        (tableWidth * 0.42) - 14,
        infoHeight,
      ),
      fontSize: 15,
      weight: FontWeight.w700,
    );

    y += infoHeight;

    // ========================================================
    // TABLE HEADER
    // ========================================================

    final tableTop = y;

    final tableHeight = headerHeight + (data.students.length * rowHeight);

    // Header labels
    _centerText(
      canvas,
      '#',
      Rect.fromLTWH(left, y, serialWidth, headerHeight),
      fontSize: 19,
      weight: FontWeight.w900,
    );

    _centerText(
      canvas,
      'STUDENT',
      Rect.fromLTWH(left + serialWidth, y, nameWidth, headerHeight),
      fontSize: 20,
      weight: FontWeight.w900,
    );

    for (var i = 0; i < data.tests.length; i++) {
      final test = data.tests[i];

      final x = left + serialWidth + nameWidth + (i * testWidth);

      _centerText(
        canvas,
        test.label,
        Rect.fromLTWH(x, y + 5, testWidth, 25),
        fontSize: 18,
        weight: FontWeight.w900,
      );

      _centerText(
        canvas,
        test.testDate == null ? '' : DateFormat('dd/MM').format(test.testDate!),
        Rect.fromLTWH(x, y + 30, testWidth, 20),
        fontSize: 12,
        weight: FontWeight.w600,
      );

      _centerText(
        canvas,
        '/${_number(test.maxMarks)}',
        Rect.fromLTWH(x, y + 50, testWidth, 21),
        fontSize: 13,
        weight: FontWeight.w700,
      );
    }

    y += headerHeight;

    // ========================================================
    // STUDENT ROWS
    // ========================================================

    for (var rowIndex = 0; rowIndex < data.students.length; rowIndex++) {
      final student = data.students[rowIndex];

      _centerText(
        canvas,
        '${rowIndex + 1}',
        Rect.fromLTWH(left, y, serialWidth, rowHeight),
        fontSize: 17,
        weight: FontWeight.w700,
      );

      _leftText(
        canvas,
        student.name,
        Rect.fromLTWH(left + serialWidth + 10, y, nameWidth - 20, rowHeight),
        fontSize: 18,
        weight: FontWeight.w600,
      );

      for (var testIndex = 0; testIndex < data.tests.length; testIndex++) {
        final test = data.tests[testIndex];

        final result = student.results[test.id];

        final x = left + serialWidth + nameWidth + (testIndex * testWidth);

        final cellRect = Rect.fromLTWH(
          x + 1.5,
          y + 1.5,
          testWidth - 3,
          rowHeight - 3,
        );

        final fill = _resultColor(result, test.maxMarks);

        if (fill != null) {
          canvas.drawRect(cellRect, Paint()..color = fill);
        }

        final text = result == null
            ? '—'
            : result.isAbsent
            ? 'A'
            : result.marks == null
            ? '—'
            : _number(result.marks!);

        _centerText(
          canvas,
          text,
          Rect.fromLTWH(x, y, testWidth, rowHeight),
          fontSize: result?.isAbsent == true ? 19 : 17,
          weight: FontWeight.w800,
        );
      }

      y += rowHeight;
    }

    // ========================================================
    // GRID
    // ========================================================

    final serialX = left + serialWidth;

    final nameX = serialX + nameWidth;

    canvas.drawRect(
      Rect.fromLTWH(left, tableTop, tableWidth, tableHeight),
      blackBorder,
    );

    canvas.drawLine(
      Offset(serialX, tableTop),
      Offset(serialX, tableTop + tableHeight),
      blackBorder,
    );

    canvas.drawLine(
      Offset(nameX, tableTop),
      Offset(nameX, tableTop + tableHeight),
      blackBorder,
    );

    for (var i = 1; i < data.tests.length; i++) {
      final x = nameX + (i * testWidth);

      canvas.drawLine(
        Offset(x, tableTop),
        Offset(x, tableTop + tableHeight),
        blackBorder,
      );
    }

    canvas.drawLine(
      Offset(left, tableTop + headerHeight),
      Offset(left + tableWidth, tableTop + headerHeight),
      blackBorder,
    );

    for (var i = 1; i <= data.students.length; i++) {
      final lineY = tableTop + headerHeight + (i * rowHeight);

      canvas.drawLine(
        Offset(left, lineY),
        Offset(left + tableWidth, lineY),
        blackBorder,
      );
    }

    // ========================================================
    // LEGEND
    // ========================================================

    final footerY = tableTop + tableHeight;

    _legendItem(
      canvas,
      x: left + 14,
      y: footerY + 17,
      color: const Color(0xFFD9EAD3),
      text: '70%+',
    );

    _legendItem(
      canvas,
      x: left + 130,
      y: footerY + 17,
      color: const Color(0xFFFFF2CC),
      text: '50–69%',
    );

    _legendItem(
      canvas,
      x: left + 270,
      y: footerY + 17,
      color: const Color(0xFFF4CCCC),
      text: '<50%',
    );

    _legendItem(
      canvas,
      x: left + 390,
      y: footerY + 17,
      color: const Color(0xFFE7E6E6),
      text: 'A = Absent',
    );

    _rightText(
      canvas,
      'Generated from '
      'FG Academy Portal',
      Rect.fromLTWH(left + tableWidth - 320, footerY + 13, 300, 36),
      fontSize: 12,
      weight: FontWeight.w600,
    );

    final picture = recorder.endRecording();

    final image = await picture.toImage(pageWidth.ceil(), pageHeight.ceil());

    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    picture.dispose();

    if (bytes == null) {
      throw StateError(
        'Could not generate '
        'progress PNG.',
      );
    }

    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }

  static double _calculateNameWidth(List<AwardProgressStudent> students) {
    double longest = 0;

    for (final student in students) {
      final painter = TextPainter(
        text: TextSpan(
          text: student.name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      );

      painter.layout();

      if (painter.width > longest) {
        longest = painter.width;
      }
    }

    return (longest + 34).clamp(210.0, 430.0).toDouble();
  }

  static Color? _resultColor(AwardProgressResult? result, double maxMarks) {
    if (result == null) {
      return null;
    }

    if (result.isAbsent) {
      return const Color(0xFFE7E6E6);
    }

    final marks = result.marks;

    if (marks == null || maxMarks <= 0) {
      return null;
    }

    final ratio = marks / maxMarks;

    if (ratio >= 0.70) {
      return const Color(0xFFD9EAD3);
    }

    if (ratio >= 0.50) {
      return const Color(0xFFFFF2CC);
    }

    return const Color(0xFFF4CCCC);
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(1);
  }

  static void _legendItem(
    Canvas canvas, {
    required double x,
    required double y,
    required Color color,
    required String text,
  }) {
    canvas.drawRect(Rect.fromLTWH(x, y, 24, 24), Paint()..color = color);

    canvas.drawRect(
      Rect.fromLTWH(x, y, 24, 24),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    _leftText(
      canvas,
      text,
      Rect.fromLTWH(x + 31, y - 3, 95, 30),
      fontSize: 12,
      weight: FontWeight.w700,
    );
  }

  static void _centerText(
    Canvas canvas,
    String text,
    Rect rect, {
    required double fontSize,
    required FontWeight weight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: weight,
          height: 1.1,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    );

    painter.layout(maxWidth: rect.width);

    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  static void _leftText(
    Canvas canvas,
    String text,
    Rect rect, {
    required double fontSize,
    required FontWeight weight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: weight,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );

    painter.layout(maxWidth: rect.width);

    painter.paint(
      canvas,
      Offset(rect.left, rect.top + (rect.height - painter.height) / 2),
    );
  }

  static void _rightText(
    Canvas canvas,
    String text,
    Rect rect, {
    required double fontSize,
    required FontWeight weight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black87,
          fontSize: fontSize,
          fontWeight: weight,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );

    painter.layout(maxWidth: rect.width);

    painter.paint(
      canvas,
      Offset(
        rect.right - painter.width,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }
}
