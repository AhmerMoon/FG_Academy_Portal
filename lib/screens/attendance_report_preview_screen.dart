import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../app_theme.dart';
import '../utils/attendance_report_actions.dart';

class AttendanceReportPreviewScreen extends StatefulWidget {
  final Uint8List pngBytes;
  final String title;
  final String fileName;

  const AttendanceReportPreviewScreen({
    super.key,
    required this.pngBytes,
    required this.title,
    required this.fileName,
  });

  @override
  State<AttendanceReportPreviewScreen> createState() =>
      _AttendanceReportPreviewScreenState();
}

class _AttendanceReportPreviewScreenState
    extends State<AttendanceReportPreviewScreen> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await shareAttendancePng(widget.pngBytes, widget.fileName, widget.title);
    } catch (error) {
      if (mounted) _message('Could not share attendance PNG.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      final document = pw.Document();
      final image = pw.MemoryImage(widget.pngBytes);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a3.landscape,
          margin: const pw.EdgeInsets.all(16),
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
      await Printing.layoutPdf(
        name: widget.fileName.replaceAll('.png', '.pdf'),
        onLayout: (_) => document.save(),
      );
    } catch (error) {
      if (mounted) _message('Could not print attendance report.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFE4E8EC),
    appBar: AppBar(title: Text(widget.title)),
    body: Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            minScale: 0.25,
            maxScale: 5,
            boundaryMargin: const EdgeInsets.all(180),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Image.memory(widget.pngBytes, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _print,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: _busy
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.share_outlined),
                    label: const Text('Share PNG'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
