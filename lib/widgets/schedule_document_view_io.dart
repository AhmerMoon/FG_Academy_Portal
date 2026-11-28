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
        return const _SchedulePreviewLoader();
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

class _SchedulePreviewLoader extends StatelessWidget {
  const _SchedulePreviewLoader();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16092A57),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 16),
          Text(
            'Preparing latest schedule…',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 5),
          Text(
            'This usually takes a few seconds.',
            style: TextStyle(color: Color(0xFF536173)),
          ),
        ],
      ),
    ),
  );
}
