import 'package:flutter/material.dart';

import '../widgets/schedule_document_view.dart';

class ScheduleDocumentPreviewScreen extends StatelessWidget {
  final String title;
  final Uri documentUri;

  const ScheduleDocumentPreviewScreen({
    super.key,
    required this.title,
    required this.documentUri,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ScheduleDocumentView(
      documentUri: documentUri,
      fileName: '${title.replaceAll(' ', '_')}.pdf',
    ),
  );
}
