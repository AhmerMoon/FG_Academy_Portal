import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

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
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'schedule-preview-${identityHashCode(this)}';
    final previewUri = widget.documentUri.replace(
      path: widget.documentUri.path.replaceFirst(
        RegExp(r'/edit/?$'),
        '/preview',
      ),
      query: '',
    );
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final frame = web.HTMLIFrameElement()
        ..src = previewUri.toString()
        ..title = widget.fileName;
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%';
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
