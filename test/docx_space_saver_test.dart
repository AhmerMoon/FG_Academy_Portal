import 'dart:convert';
import 'dart:typed_data';

import 'package:academy_portal/services/docx_space_saver.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Uint8List _docx(
  String documentXml, {
  String? stylesXml,
  String? headerXml,
  int pages = 2,
}) {
  final archive = Archive()
    ..add(ArchiveFile.string('word/document.xml', documentXml))
    ..add(
      ArchiveFile.string(
        '[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '</Types>',
      ),
    )
    ..add(
      ArchiveFile.string(
        'docProps/app.xml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
            '<Pages>$pages</Pages></Properties>',
      ),
    );
  if (stylesXml != null) {
    archive.add(ArchiveFile.string('word/styles.xml', stylesXml));
  }
  if (headerXml != null) {
    archive.add(ArchiveFile.string('word/header1.xml', headerXml));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _paragraph(String text) =>
    '<w:p><w:r><w:t>${const HtmlEscape().convert(text)}</w:t></w:r></w:p>';

void main() {
  test('leaves a saved one-page DOCX byte-for-byte unchanged', () async {
    final input = _docx(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>${_paragraph('A short one-page paper.')}<w:sectPr/></w:body>'
      '</w:document>',
      pages: 1,
    );
    final result = await compactDocx(input, 'short.docx');
    expect(result.wasCompacted, isFalse);
    expect(result.detectedPages, 1);
    expect(result.fileName, 'short.docx');
    expect(result.bytes, orderedEquals(input));
  });

  test(
    'compacts safe MCQ options while preserving a presentable heading',
    () async {
      final input = _docx(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>'
        '${_paragraph('FG ACADEMY TEST')}'
        '${_paragraph('1. Choose the correct answer.')}'
        '${_paragraph('(A) One')}'
        '${_paragraph('(B) Two')}'
        '${_paragraph('(C) Three')}'
        '${_paragraph('(D) Four')}'
        '${_paragraph('')}${_paragraph('')}'
        '<w:sectPr><w:pgMar w:top="1440" w:left="1440" w:right="1440" w:bottom="1440"/></w:sectPr>'
        '</w:body></w:document>',
      );

      final result = await compactDocx(input, 'Physics Test 1.docx');
      expect(result.fileName, 'Physics Test 1_SPACE_SAVED.docx');
      expect(result.optionGroupsCompacted, 1);
      expect(result.blankLinesRemoved, 1);

      final archive = ZipDecoder().decodeBytes(result.bytes);
      final xml = XmlDocument.parse(
        utf8.decode(
          archive.files
              .singleWhere((f) => f.name == 'word/document.xml')
              .content,
        ),
      );
      final text = xml.innerText;
      for (final value in ['FG ACADEMY TEST', '(A) One', '(D) Four']) {
        expect(text, contains(value));
      }
      final margin = xml.descendants.whereType<XmlElement>().singleWhere(
        (element) => element.name.local == 'pgMar',
      );
      expect(
        margin.attributes.singleWhere((a) => a.name.local == 'left').value,
        '650',
      );
      final heading = xml.descendants.whereType<XmlElement>().firstWhere(
        (element) =>
            element.name.local == 'p' &&
            element.innerText.contains('FG ACADEMY TEST'),
      );
      expect(
        heading.descendants.whereType<XmlElement>().any(
          (element) => element.name.local == 'b',
        ),
        isTrue,
      );
    },
  );

  test('does not merge option paragraphs containing drawings', () async {
    final input = _docx(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>'
      '<w:p><w:r><w:t>(A) Diagram</w:t><w:drawing/></w:r></w:p>'
      '${_paragraph('(B) Text')}'
      '<w:sectPr/>'
      '</w:body></w:document>',
    );
    final result = await compactDocx(input, 'paper.docx');
    expect(result.optionGroupsCompacted, 0);
  });

  test('compacts options separated with manual Word line breaks', () async {
    final input = _docx(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body><w:p><w:r>'
      '<w:t>1. Which colour is shown?</w:t><w:br/><w:tab/>'
      '<w:t>A) Red</w:t><w:br/><w:tab/><w:t>B) Blue</w:t><w:br/>'
      '<w:tab/><w:t>C) Green</w:t><w:br/><w:tab/></w:r>'
      '<w:hyperlink><w:r><w:t>D) Black [1]</w:t></w:r></w:hyperlink>'
      '</w:p><w:sectPr/>'
      '</w:body></w:document>',
    );
    final result = await compactDocx(input, 'paper.docx');
    expect(result.optionGroupsCompacted, 1);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final xml = XmlDocument.parse(
      utf8.decode(
        archive.files.singleWhere((f) => f.name == 'word/document.xml').content,
      ),
    );
    expect(
      xml.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'tab')
          .length,
      6,
    );
    expect(xml.innerText, contains('1. Which colour is shown?'));
  });

  test(
    'separates subject and time fields that relied on space wrapping',
    () async {
      final input = _docx(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>'
        '${_paragraph('Subject: Chemistry       Time Alloted: 20 min')}'
        '<w:sectPr/></w:body></w:document>',
      );
      final result = await compactDocx(input, 'chemistry.docx');
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final xml = XmlDocument.parse(
        utf8.decode(
          archive.files
              .singleWhere((f) => f.name == 'word/document.xml')
              .content,
        ),
      );
      final paragraphs = xml.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'p')
          .map((element) => element.innerText)
          .toList();
      expect(
        paragraphs,
        containsAllInOrder(['Subject: Chemistry', 'Time Alloted: 20 min']),
      );
    },
  );

  test('reduces only 12-point body text to 11-point', () async {
    final input = _docx(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body><w:p><w:r><w:rPr><w:sz w:val="24"/><w:szCs w:val="24"/>'
      '</w:rPr><w:t>Regular body sentence.</w:t></w:r></w:p>'
      '<w:sectPr/></w:body></w:document>',
    );
    final result = await compactDocx(input, 'body.docx');
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final xml = XmlDocument.parse(
      utf8.decode(
        archive.files.singleWhere((f) => f.name == 'word/document.xml').content,
      ),
    );
    final sizes = xml.descendants
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'sz' || element.name.local == 'szCs',
        )
        .expand((element) => element.attributes)
        .where((attribute) => attribute.name.local == 'val')
        .map((attribute) => attribute.value);
    expect(sizes, everyElement('22'));
  });

  test('aligns questions and compacted options to the same left edge', () async {
    final input = _docx(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body><w:p><w:pPr><w:ind w:left="720" w:hanging="360"/>'
      '<w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr>'
      '<w:r><w:tab/><w:t>1. Which option is correct?</w:t></w:r></w:p>'
      '${_paragraph('A) First')}${_paragraph('B) Second')}'
      '${_paragraph('C) Third')}${_paragraph('D) Fourth')}'
      '<w:sectPr/></w:body></w:document>',
    );
    final result = await compactDocx(input, 'aligned.docx');
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final xml = XmlDocument.parse(
      utf8.decode(
        archive.files.singleWhere((f) => f.name == 'word/document.xml').content,
      ),
    );
    final question = xml.descendants.whereType<XmlElement>().firstWhere(
      (element) =>
          element.name.local == 'p' &&
          element.innerText.contains('Which option is correct?'),
    );
    final questionIndent = question.descendants
        .whereType<XmlElement>()
        .firstWhere((element) => element.name.local == 'ind');
    expect(
      questionIndent.attributes
          .singleWhere((a) => a.name.local == 'left')
          .value,
      '0',
    );
    expect(
      question.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'tab',
      ),
      isEmpty,
    );
    final options = xml.descendants.whereType<XmlElement>().firstWhere(
      (element) =>
          element.name.local == 'p' && element.innerText.contains('(A) First'),
    );
    final optionIndent = options.descendants.whereType<XmlElement>().firstWhere(
      (element) => element.name.local == 'ind',
    );
    expect(
      optionIndent.attributes.singleWhere((a) => a.name.local == 'left').value,
      '0',
    );
  });

  test('tightens text spacing in real Word header parts', () async {
    final input = _docx(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>${_paragraph('Two-page paper body')}<w:sectPr/></w:body>'
      '</w:document>',
      headerXml:
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '${_paragraph('FG Academy Examination')}</w:hdr>',
    );
    final result = await compactDocx(input, 'header.docx');
    expect(result.wasCompacted, isTrue);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final header = XmlDocument.parse(
      utf8.decode(
        archive.files.singleWhere((f) => f.name == 'word/header1.xml').content,
      ),
    );
    final spacing = header.descendants.whereType<XmlElement>().singleWhere(
      (element) => element.name.local == 'spacing',
    );
    expect(
      spacing.attributes.singleWhere((a) => a.name.local == 'after').value,
      '10',
    );
  });
}
