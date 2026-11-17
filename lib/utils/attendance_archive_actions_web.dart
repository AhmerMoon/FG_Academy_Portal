import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

bool get supportsAttendanceArchive =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

Future<String?> saveAttendanceArchivePdf(
  Uint8List bytes,
  String fileName,
) async {
  if (!supportsAttendanceArchive) return null;
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body?.appendChild(anchor);
    try {
      anchor.click();
    } finally {
      anchor.remove();
    }
  } finally {
    await Future<void>.delayed(const Duration(seconds: 1));
    web.URL.revokeObjectURL(url);
  }
  return 'Downloads/$fileName';
}
