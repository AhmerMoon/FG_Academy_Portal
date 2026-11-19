import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> shareAttendancePng(
  Uint8List bytes,
  String fileName,
  String title,
) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
      text: title,
      subject: title,
      downloadFallbackEnabled: true,
    ),
  );
}

Future<void> shareAttendanceLink(String link, String title) async {
  await SharePlus.instance.share(
    ShareParams(text: '$title has been updated.\n$link', subject: title),
  );
}
