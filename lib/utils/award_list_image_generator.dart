import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AwardListShareStudent {
  final int serialNo;
  final String name;
  final double? marks;
  final bool isAbsent;

  const AwardListShareStudent({
    required this.serialNo,
    required this.name,
    required this.marks,
    required this.isAbsent,
  });
}

class AwardListShareData {
  final String academyName;
  final String batchName;
  final String subjectName;
  final String testLabel;
  final DateTime? testDate;
  final double maxMarks;
  final String preparedBy;

  final List<AwardListShareStudent> students;

  const AwardListShareData({
    required this.academyName,
    required this.batchName,
    required this.subjectName,
    required this.testLabel,
    required this.testDate,
    required this.maxMarks,
    required this.preparedBy,
    required this.students,
  });
}

class AwardListImageGenerator {
  static const double _pageWidth = 1240;

  static Future<Uint8List> generate(AwardListShareData data) async {
    const double margin = 28;

    const double titleHeight = 116;

    const double metaHeight = 118;

    const double tableHeaderHeight = 62;

    const double studentRowHeight = 50;

    const double footerHeight = 60;

    final double pageHeight =
        margin +
        titleHeight +
        metaHeight +
        tableHeaderHeight +
        (data.students.length * studentRowHeight) +
        footerHeight +
        margin;

    final recorder = ui.PictureRecorder();

    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, _pageWidth, pageHeight),
    );

    final backgroundPaint = Paint()..color = Colors.white;

    final outerBorderPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final borderPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, _pageWidth, pageHeight),
      backgroundPaint,
    );

    final contentLeft = margin;

    final contentTop = margin;

    final contentWidth = _pageWidth - (margin * 2);

    final contentHeight = pageHeight - (margin * 2);

    canvas.drawRect(
      Rect.fromLTWH(contentLeft, contentTop, contentWidth, contentHeight),
      outerBorderPaint,
    );

    double y = contentTop;

    // ========================================================
    // TITLE
    // ========================================================

    canvas.drawRect(
      Rect.fromLTWH(contentLeft, y, contentWidth, titleHeight),
      borderPaint,
    );

    _drawCenteredText(
      canvas,
      text: data.academyName,
      rect: Rect.fromLTWH(contentLeft + 10, y + 8, contentWidth - 20, 42),
      fontSize: 30,
      fontWeight: FontWeight.w900,
    );

    _drawCenteredText(
      canvas,
      text:
          'Class: '
          '${data.batchName} '
          'Award Sheet',
      rect: Rect.fromLTWH(contentLeft + 10, y + 54, contentWidth - 20, 44),
      fontSize: 25,
      fontWeight: FontWeight.w900,
    );

    y += titleHeight;

    // ========================================================
    // META
    // ========================================================

    canvas.drawRect(
      Rect.fromLTWH(contentLeft, y, contentWidth, metaHeight),
      borderPaint,
    );

    const firstMetaRowHeight = 56.0;

    final splitX = contentLeft + (contentWidth * 0.62);

    canvas.drawLine(
      Offset(contentLeft, y + firstMetaRowHeight),
      Offset(contentLeft + contentWidth, y + firstMetaRowHeight),
      borderPaint,
    );

    canvas.drawLine(
      Offset(splitX, y + firstMetaRowHeight),
      Offset(splitX, y + metaHeight),
      borderPaint,
    );

    _drawLabelValue(
      canvas,
      left: contentLeft + 16,
      top: y + 9,
      label: 'SUBJECT:',
      value: data.subjectName,
      labelWidth: 175,
      availableWidth: contentWidth - 450,
      valueFontSize: 23,
    );

    _drawLabelValue(
      canvas,
      left: contentLeft + contentWidth - 300,
      top: y + 9,
      label: 'Test:',
      value: data.testLabel,
      labelWidth: 90,
      availableWidth: 180,
      valueFontSize: 23,
    );

    _drawLabelValue(
      canvas,
      left: contentLeft + 16,
      top: y + firstMetaRowHeight + 9,
      label: 'Date:',
      value: data.testDate == null
          ? '-'
          : DateFormat('dd/MM/yy').format(data.testDate!),
      labelWidth: 110,
      availableWidth: (splitX - contentLeft) - 150,
      valueFontSize: 22,
    );

    _drawLabelValue(
      canvas,
      left: splitX + 16,
      top: y + firstMetaRowHeight + 9,
      label: 'Total Marks:',
      value: _formatMarks(data.maxMarks),
      labelWidth: 180,
      availableWidth: (contentLeft + contentWidth - splitX) - 215,
      valueFontSize: 22,
    );

    y += metaHeight;

    // ========================================================
    // TABLE
    // ========================================================

    const serialWidth = 90.0;

    const marksWidth = 200.0;

    final nameWidth = contentWidth - serialWidth - marksWidth;

    final tableTop = y;

    final tableHeight =
        tableHeaderHeight + (data.students.length * studentRowHeight);

    canvas.drawRect(
      Rect.fromLTWH(contentLeft, tableTop, contentWidth, tableHeight),
      borderPaint,
    );

    final serialDivider = contentLeft + serialWidth;

    final marksDivider = serialDivider + nameWidth;

    canvas.drawLine(
      Offset(serialDivider, tableTop),
      Offset(serialDivider, tableTop + tableHeight),
      borderPaint,
    );

    canvas.drawLine(
      Offset(marksDivider, tableTop),
      Offset(marksDivider, tableTop + tableHeight),
      borderPaint,
    );

    _drawCenteredText(
      canvas,
      text: '#',
      rect: Rect.fromLTWH(
        contentLeft,
        tableTop,
        serialWidth,
        tableHeaderHeight,
      ),
      fontSize: 21,
      fontWeight: FontWeight.w900,
    );

    _drawCenteredText(
      canvas,
      text: 'NAME OF STUDENTS',
      rect: Rect.fromLTWH(
        serialDivider,
        tableTop,
        nameWidth,
        tableHeaderHeight,
      ),
      fontSize: 23,
      fontWeight: FontWeight.w900,
    );

    _drawCenteredText(
      canvas,
      text: 'Obt Marks',
      rect: Rect.fromLTWH(
        marksDivider,
        tableTop,
        marksWidth,
        tableHeaderHeight,
      ),
      fontSize: 21,
      fontWeight: FontWeight.w900,
    );

    canvas.drawLine(
      Offset(contentLeft, tableTop + tableHeaderHeight),
      Offset(contentLeft + contentWidth, tableTop + tableHeaderHeight),
      borderPaint,
    );

    y = tableTop + tableHeaderHeight;

    for (final student in data.students) {
      _drawCenteredText(
        canvas,
        text: student.serialNo.toString(),
        rect: Rect.fromLTWH(contentLeft, y, serialWidth, studentRowHeight),
        fontSize: 19,
        fontWeight: FontWeight.w700,
      );

      _drawLeftText(
        canvas,
        text: student.name,
        rect: Rect.fromLTWH(
          serialDivider + 13,
          y,
          nameWidth - 26,
          studentRowHeight,
        ),
        fontSize: 19,
        fontWeight: FontWeight.w600,
      );

      final resultText = student.isAbsent
          ? 'A'
          : student.marks == null
          ? ''
          : _formatMarks(student.marks!);

      _drawCenteredText(
        canvas,
        text: resultText,
        rect: Rect.fromLTWH(marksDivider, y, marksWidth, studentRowHeight),
        fontSize: student.isAbsent ? 22 : 21,
        fontWeight: FontWeight.w900,
      );

      y += studentRowHeight;

      canvas.drawLine(
        Offset(contentLeft, y),
        Offset(contentLeft + contentWidth, y),
        borderPaint,
      );
    }

    // ========================================================
    // FOOTER
    // ========================================================

    canvas.drawRect(
      Rect.fromLTWH(contentLeft, y, contentWidth, footerHeight),
      borderPaint,
    );

    _drawLeftText(
      canvas,
      text:
          'Prepared By: '
          '${data.preparedBy}',
      rect: Rect.fromLTWH(
        contentLeft + 14,
        y,
        contentWidth * 0.56,
        footerHeight,
      ),
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );

    _drawRightText(
      canvas,
      text:
          'Generated from '
          'FG Academy Portal',
      rect: Rect.fromLTWH(
        contentLeft + (contentWidth * 0.52),
        y,
        (contentWidth * 0.48) - 14,
        footerHeight,
      ),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    final picture = recorder.endRecording();

    final image = await picture.toImage(_pageWidth.toInt(), pageHeight.ceil());

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    picture.dispose();

    if (byteData == null) {
      throw StateError(
        'Could not generate '
        'award list PNG.',
      );
    }

    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }

  static String _formatMarks(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  static void _drawLabelValue(
    Canvas canvas, {
    required double left,
    required double top,
    required String label,
    required String value,
    required double labelWidth,
    required double availableWidth,
    required double valueFontSize,
  }) {
    _drawLeftText(
      canvas,
      text: label,
      rect: Rect.fromLTWH(left, top, labelWidth, 38),
      fontSize: 20,
      fontWeight: FontWeight.w900,
    );

    _drawLeftText(
      canvas,
      text: value,
      rect: Rect.fromLTWH(left + labelWidth, top, availableWidth, 38),
      fontSize: valueFontSize,
      fontWeight: FontWeight.w700,
    );
  }

  static void _drawCenteredText(
    Canvas canvas, {
    required String text,
    required Rect rect,
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.15,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    );

    painter.layout(maxWidth: rect.width);

    final dx = rect.left + ((rect.width - painter.width) / 2);

    final dy = rect.top + ((rect.height - painter.height) / 2);

    painter.paint(canvas, Offset(dx, dy));
  }

  static void _drawLeftText(
    Canvas canvas, {
    required String text,
    required Rect rect,
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.15,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.left,
      maxLines: 2,
      ellipsis: '…',
    );

    painter.layout(maxWidth: rect.width);

    final dy = rect.top + ((rect.height - painter.height) / 2);

    painter.paint(canvas, Offset(rect.left, dy));
  }

  static void _drawRightText(
    Canvas canvas, {
    required String text,
    required Rect rect,
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black87,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.15,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.right,
      maxLines: 1,
      ellipsis: '…',
    );

    painter.layout(maxWidth: rect.width);

    final dx = rect.left + rect.width - painter.width;

    final dy = rect.top + ((rect.height - painter.height) / 2);

    painter.paint(canvas, Offset(dx, dy));
  }
}
