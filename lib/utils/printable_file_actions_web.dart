import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';
import 'package:web/web.dart' as web;

Future<PlatformFile?> pickPrintableFile() => FilePicker.pickFile(
  type: FileType.custom,
  allowedExtensions: const ['pdf', 'doc', 'docx'],
  webOptions: const FilePickerWebOptions(
    // Use the browser's actual change/cancel event, not a focus timeout.
    cancelUploadOnWindowBlur: false,
    // Check the size before reading the file into memory.
    // ignore: deprecated_member_use
    withData: false,
  ),
);

Future<bool> savePrintable(
  Uint8List bytes,
  String name,
  String mimeType, {
  List<String> folders = const [],
}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser time to consume the object URL before releasing it.
  Future<void>.delayed(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(url),
  );
  return true;
}

Future<void> openPrintableWord(
  Uint8List bytes,
  String name,
  String mimeType,
) async {
  await savePrintable(bytes, name, mimeType);
}
