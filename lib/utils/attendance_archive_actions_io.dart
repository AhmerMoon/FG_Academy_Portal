import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';

bool get supportsAttendanceArchive => Platform.isWindows;

Future<String?> saveAttendanceArchivePdf(
  Uint8List bytes,
  String fileName,
) async {
  if (!Platform.isWindows) return null;
  final box = Hive.box('settings');
  var folder = box.get('attendance_archive_folder')?.toString();
  if (folder == null || folder.isEmpty || !Directory(folder).existsSync()) {
    folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose attendance archive folder',
    );
    if (folder == null) return null;
    await box.put('attendance_archive_folder', folder);
  }
  final separator = Platform.pathSeparator;
  final path = folder.endsWith(separator)
      ? '$folder$fileName'
      : '$folder$separator$fileName';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
