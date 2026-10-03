import 'dart:io';

bool get isWindowsPlatform => Platform.isWindows;

Future<bool> launchAutomation() async {
  if (!Platform.isWindows) {
    return false;
  }

  try {
    // Always use the actual Flutter EXE directory,
    // not whatever Windows happens to use as current directory.
    final exeDirectory = File(Platform.resolvedExecutable).parent;

    final batchFile = File('${exeDirectory.path}\\FGEI_Backend\\main.bat');

    if (!batchFile.existsSync()) {
      return false;
    }

    await Process.start('cmd.exe', [
      '/c',
      'start',
      '',
      batchFile.path,
    ], workingDirectory: batchFile.parent.path);

    return true;
  } catch (e) {
    return false;
  }
}
