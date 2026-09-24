import 'dart:io';

bool get isWindowsPlatform => Platform.isWindows;

Future<bool> launchAutomation() async {
  if (!Platform.isWindows) return false;

  final batchFile = File('${Directory.current.path}\\FGEI_Backend\\main.bat');
  if (!batchFile.existsSync()) return false;

  try {
    final result = await Process.run('cmd', [
      '/c',
      'start',
      '',
      batchFile.path,
    ]);
    return result.exitCode == 0;
  } catch (e) {
    return false;
  }
}
