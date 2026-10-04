import 'dart:convert';
import 'dart:io';

bool get isExcelFeeBridgeSupported => Platform.isWindows;

Directory _findBackendDirectory() {
  final separator = Platform.pathSeparator;

  final startingPoints = <Directory>[
    File(Platform.resolvedExecutable).parent,
    Directory.current,
  ];

  final visited = <String>{};

  for (final start in startingPoints) {
    var current = start;

    for (var depth = 0; depth < 7; depth++) {
      final normalized = current.absolute.path.toLowerCase();

      if (visited.add(normalized)) {
        final candidate = Directory(
          '${current.path}'
          '$separator'
          'FGEI_Backend',
        );

        final bridge = File(
          '${candidate.path}'
          '$separator'
          'fee_excel_bridge.py',
        );

        if (bridge.existsSync()) {
          return candidate;
        }
      }

      final parent = current.parent;

      if (parent.path == current.path) {
        break;
      }

      current = parent;
    }
  }

  throw StateError(
    'FGEI_Backend was not found. '
    'Make sure fee_excel_bridge.py '
    'exists inside FGEI_Backend.',
  );
}

Directory _resolveFeeDataDirectory(Directory backend) {
  final separator = Platform.pathSeparator;

  final dataDir = Directory(
    '${backend.parent.path}'
    '$separator'
    'Fee_Data',
  );

  if (!dataDir.existsSync()) {
    dataDir.createSync(recursive: true);
  }

  return dataDir;
}

String _extractBridgeError(String stdoutText, String stderrText) {
  if (stdoutText.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(stdoutText);

      if (decoded is Map) {
        final error = decoded['error']?.toString();

        if (error != null && error.trim().isNotEmpty) {
          return error;
        }
      }
    } catch (_) {
      // Fall through.
    }
  }

  if (stderrText.trim().isNotEmpty) {
    return stderrText.trim();
  }

  return 'Excel fee bridge failed.';
}

Future<String> _runBridge(List<String> arguments) async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Excel fee reports are '
      'Windows-only.',
    );
  }

  final separator = Platform.pathSeparator;

  final backend = _findBackendDirectory();

  final dataDir = _resolveFeeDataDirectory(backend);

  final python = File(
    '${backend.path}'
    '$separator'
    '.venv'
    '$separator'
    'Scripts'
    '$separator'
    'python.exe',
  );

  final bridge = File(
    '${backend.path}'
    '$separator'
    'fee_excel_bridge.py',
  );

  if (!python.existsSync()) {
    throw StateError(
      'Python environment not found. '
      'Run FGEI_Backend\\'
      'setup_backend.bat first.',
    );
  }

  if (!bridge.existsSync()) {
    throw StateError(
      'fee_excel_bridge.py '
      'was not found.',
    );
  }

  final result = await Process.run(python.path, [
    bridge.path,
    ...arguments,
    '--data-dir',
    dataDir.path,
  ], workingDirectory: backend.path);

  final stdoutText = result.stdout.toString().trim();

  final stderrText = result.stderr.toString().trim();

  if (result.exitCode != 0) {
    throw StateError(_extractBridgeError(stdoutText, stderrText));
  }

  if (stdoutText.isEmpty) {
    throw StateError(
      'Excel bridge returned '
      'no data.',
    );
  }

  return stdoutText;
}

Future<String> listExcelFeeWorkbooksJson() {
  return _runBridge(const ['list']);
}

Future<String> readExcelFeeWorkbookJson(String fileName) {
  return _runBridge(['read', '--file', fileName]);
}
