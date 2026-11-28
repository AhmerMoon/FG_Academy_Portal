import 'dart:js_interop';
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
  bool _registered = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'schedule-preview-${identityHashCode(this)}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registered) return;
    _registered = true;
    final fitScale = MediaQuery.sizeOf(context).width < 600 ? 0.62 : 1.0;
    final previewUri = widget.documentUri.replace(
      path: widget.documentUri.path.replaceFirst(
        RegExp(r'/edit/?$'),
        '/preview',
      ),
      query: '',
    );
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final frame = web.HTMLIFrameElement()..title = widget.fileName;
      frame.addEventListener(
        'load',
        ((web.Event _) {
          if (mounted && !_loaded) setState(() => _loaded = true);
        }).toJS,
      );
      frame.style
        ..border = '0'
        ..width = '${100 / fitScale}%'
        ..height = '${100 / fitScale}%'
        ..transform = 'scale($fitScale)'
        ..transformOrigin = 'top left';
      frame.src = previewUri.toString();
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      HtmlElementView(viewType: _viewType),
      if (!_loaded) const _SchedulePreviewLoader(),
    ],
  );
}

class _SchedulePreviewLoader extends StatelessWidget {
  const _SchedulePreviewLoader();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Center(
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
    ),
  );
}
