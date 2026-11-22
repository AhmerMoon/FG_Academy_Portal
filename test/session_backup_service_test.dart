import 'dart:convert';
import 'dart:typed_data';

import 'package:academy_portal/services/session_backup_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a readable ZIP with nested reports and data files', () {
    final bytes = buildSessionBackupZip([
      SessionBackupFile.text('README.txt', 'Session backup'),
      SessionBackupFile.text(
        'Data/students_active.csv',
        '\uFEFF"id","name"\r\n"1","Ayan"',
      ),
      SessionBackupFile(
        'Reports/Award Lists/9th Boys/Physics/T1.png',
        Uint8List.fromList([137, 80, 78, 71]),
      ),
    ]);

    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.files.map((file) => file.name),
      containsAll([
        'README.txt',
        'Data/students_active.csv',
        'Reports/Award Lists/9th Boys/Physics/T1.png',
      ]),
    );
    final readme = archive.files.singleWhere(
      (file) => file.name == 'README.txt',
    );
    expect(utf8.decode(readme.content), 'Session backup');
    final png = archive.files.singleWhere((file) => file.name.endsWith('.png'));
    expect(png.content, orderedEquals([137, 80, 78, 71]));
  });
}
