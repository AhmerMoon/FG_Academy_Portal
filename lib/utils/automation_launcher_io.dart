import 'dart:io';

bool get isWindowsPlatform => Platform.isWindows;

Future<bool> launchAutomation({String? batchId}) async {
  if (!Platform.isWindows) return false;

  try {
    final exeDirectory = File(Platform.resolvedExecutable).parent;

    final batchFile = File('${exeDirectory.path}\\FGEI_Backend\\main.bat');

    if (!batchFile.existsSync()) {
      return false;
    }

    final args = <String>['/c', 'start', '', batchFile.path];

    if (batchId != null && batchId.trim().isNotEmpty) {
      args.addAll(['--batch-id', batchId.trim()]);
    }

    await Process.start(
      'cmd.exe',
      args,
      workingDirectory: batchFile.parent.path,
    );

    return true;
  } catch (e) {
    return false;
  }
}
