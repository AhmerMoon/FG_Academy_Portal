import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveSessionBackup(Uint8List bytes, String fileName) async {
  final path = await FilePicker.saveFile(
    dialogTitle: 'Save session backup before continuing',
    fileName: fileName,
    bytes: bytes,
    mimeType: 'application/zip',
  );
  return path != null;
}
