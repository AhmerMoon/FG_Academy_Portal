import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

class ScheduleDocumentView extends StatefulWidget {
  final Uri documentUri;
  final String fileName;

  const ScheduleDocumentView({
    super.key,
    required this.documentUri,
    required this.fileName,
  });

  @override
  State<ScheduleDocumentView> createState() => _ScheduleDocumentViewState();
}

class _ScheduleDocumentViewState extends State<ScheduleDocumentView> {
  late Future<Uint8List> _pdf = _loadPdf();

  Uri get _pdfUri {
    final path = widget.documentUri.path.replaceFirst(
      RegExp(r'/edit/?$'),
      '/export',
    );
    return widget.documentUri.replace(
      path: path,
      queryParameters: const {'format': 'pdf'},
    );
  }

  Future<Uint8List> _loadPdf() async {
    final response = await http.get(_pdfUri);
    final contentType = response.headers['content-type'] ?? '';
    if (response.statusCode != 200 || !contentType.contains('pdf')) {
      throw StateError('Google did not return a public PDF.');
    }
    return response.bodyBytes;
  }

  void _retry() => setState(() => _pdf = _loadPdf());

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _pdf,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || snapshot.data == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'Schedule preview could not be loaded. Make sure Google '
                  'Docs General access is set to Anyone with the link.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      final bytes = snapshot.data!;
      return PdfPreview(
        build: (_) async => bytes,
        pdfFileName: widget.fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        dynamicLayout: false,
      );
    },
  );
}
