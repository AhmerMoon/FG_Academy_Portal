import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';
import 'package:web/web.dart' as web;

Future<PlatformFile?> pickPrintableFile() {
  final result = Completer<PlatformFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept =
        '.pdf,.doc,.docx,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  input.dataset['printablePicker'] = 'true';
  // iOS Safari can refuse a synthetic click on a display:none file input.
  input.style
    ..position = 'fixed'
    ..left = '-1000px'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0';

  void finish(PlatformFile? file, [Object? error]) {
    input.remove();
    if (result.isCompleted) return;
    if (error == null) {
      result.complete(file);
    } else {
      result.completeError(error);
    }
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        finish(null);
        return;
      }
      if (file.size > 20 * 1024 * 1024) {
        finish(null, ArgumentError('File must be 20 MB or smaller.'));
        return;
      }
      final reader = web.FileReader();
      reader.addEventListener(
        'loadend',
        ((web.Event _) {
          final buffer = (reader.result as JSArrayBuffer?)?.toDart;
          if (buffer == null) {
            finish(
              null,
              StateError(
                'Could not read the selected file. Choose a local copy.',
              ),
            );
            return;
          }
          final bytes = buffer.asUint8List();
          finish(
            WebPlatformFile(
              name: file.name,
              uri: Uri.parse('about:blank'),
              bytesLength: bytes.length,
              bytes: bytes,
            ),
          );
        }).toJS,
      );
      reader.addEventListener(
        'error',
        ((web.Event _) {
          finish(
            null,
            StateError(
              'Could not read the selected file. Choose a local copy.',
            ),
          );
        }).toJS,
      );
      reader.readAsArrayBuffer(file);
    }).toJS,
  );
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  web.document.body!.append(input);
  try {
    input.click();
  } catch (error) {
    finish(null, error);
  }
  return result.future;
}

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
