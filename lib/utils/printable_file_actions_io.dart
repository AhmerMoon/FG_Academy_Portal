import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

Future<PlatformFile?> pickPrintableFile() => FilePicker.pickFile(
  type: FileType.custom,
  allowedExtensions: const ['pdf', 'doc', 'docx'],
);

Future<bool> savePrintable(
  Uint8List bytes,
  String name,
  String mimeType, {
  List<String> folders = const [],
}) async {
  if (Platform.isWindows) {
    final appDirectory = File(Platform.resolvedExecutable).parent;
    final safeFolders = folders
        .map(_safePathPart)
        .where((part) => part.isNotEmpty)
        .toList();
    final directory = Directory(
      [
        appDirectory.path,
        'Academy Portal Data',
        'Printables',
        ...safeFolders,
      ].join(Platform.pathSeparator),
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_safeFileName(name)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return true;
  }
  final path = await FilePicker.saveFile(
    dialogTitle: 'Save printable',
    fileName: name,
    bytes: bytes,
    mimeType: mimeType,
  );
  return path != null;
}

String _safePathPart(String value) => value
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'[. ]+$'), '')
    .trim();

String _safeFileName(String value) {
  final safe = _safePathPart(value);
  return safe.isEmpty ? 'printable' : safe;
}

Future<void> openPrintableWord(
  Uint8List bytes,
  String name,
  String mimeType,
) async {
  final root = await getTemporaryDirectory();
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}academy_printables',
  );
  await directory.create(recursive: true);
  // Reap only this feature's previous temporary files, never user downloads.
  await for (final entry in directory.list()) {
    if (entry is File &&
        (await entry.lastModified()).isBefore(
          DateTime.now().subtract(const Duration(days: 1)),
        )) {
      try {
        await entry.delete();
      } catch (_) {
        /* A viewer may still hold it. */
      }
    }
  }
  final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final file = File(
    '${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$safeName',
  );
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(file.path, type: mimeType);
  if (result.type != ResultType.done) {
    throw StateError(
      'Install Word or a compatible document viewer, or download the file.',
    );
  }
}
