import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> saveSessionBackup(Uint8List bytes, String fileName) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/zip'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(url),
  );
  return true;
}
