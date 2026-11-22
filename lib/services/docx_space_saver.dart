import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

class DocxSpaceSaverResult {
  const DocxSpaceSaverResult({
    required this.bytes,
    required this.fileName,
    required this.wasCompacted,
    required this.detectedPages,
    required this.optionGroupsCompacted,
    required this.blankLinesRemoved,
  });

  final Uint8List bytes;
  final String fileName;
  final bool wasCompacted;
  final int detectedPages;
  final int optionGroupsCompacted;
  final int blankLinesRemoved;
}

Future<DocxSpaceSaverResult> compactDocx(
  Uint8List bytes,
  String fileName,
) async {
  if (!fileName.toLowerCase().endsWith('.docx')) {
    throw StateError(
      'Automatic space saving supports DOCX files only. Open this file in Word and save it as DOCX first.',
    );
  }
  late final Map<String, Object> result;
  try {
    result = await compute(_compactPayload, <String, Object>{
      'bytes': bytes,
      'fileName': fileName,
    });
  } catch (_) {
    throw StateError(
      'This DOCX could not be compacted safely. The original is unchanged; use Download or open the original in Word.',
    );
  }
  return DocxSpaceSaverResult(
    bytes: result['bytes']! as Uint8List,
    fileName: result['fileName']! as String,
    wasCompacted: result['wasCompacted']! as bool,
    detectedPages: result['detectedPages']! as int,
    optionGroupsCompacted: result['optionGroupsCompacted']! as int,
    blankLinesRemoved: result['blankLinesRemoved']! as int,
  );
}

Map<String, Object> _compactPayload(Map<String, Object> input) {
  final bytes = input['bytes']! as Uint8List;
  final fileName = input['fileName']! as String;
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final expandedSize = archive.files.fold<int>(
    0,
    (total, file) => total + file.size,
  );
  if (expandedSize > 100 * 1024 * 1024) {
    throw StateError('This DOCX expands beyond the safe processing limit.');
  }

  final documentFile = archive.files
      .where((file) => file.name == 'word/document.xml' && file.isFile)
      .firstOrNull;
  if (documentFile == null) {
    throw StateError('This file is not a valid editable DOCX document.');
  }

  final document = XmlDocument.parse(
    utf8.decode(documentFile.content, allowMalformed: false),
  );
  final body = document.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'body')
      .firstOrNull;
  if (body == null) {
    throw StateError('The DOCX document body could not be read.');
  }

  final detectedPages = _detectPageCount(archive, document);
  if (detectedPages <= 1) {
    return <String, Object>{
      'bytes': bytes,
      'fileName': fileName,
      'wasCompacted': false,
      'detectedPages': 1,
      'optionGroupsCompacted': 0,
      'blankLinesRemoved': 0,
    };
  }

  _normalizeMetadataWraps(body);
  _compactPageMargins(body);
  final blankLinesRemoved = _collapseBlankParagraphs(body);
  final optionGroupsCompacted =
      _compactInlineOptionGroups(body) + _compactOptionGroups(body);
  _compactParagraphFormatting(document);
  _compactTableMargins(document);

  final output = Archive();
  for (final file in archive.files) {
    if (!file.isFile) {
      output.add(ArchiveFile.directory(file.name));
      continue;
    }
    final content = switch (file.name) {
      'word/document.xml' => Uint8List.fromList(
        utf8.encode(document.toXmlString()),
      ),
      'word/styles.xml' => _compactStyles(file.content),
      _ when RegExp(r'^word/(?:header|footer)\d*\.xml$').hasMatch(file.name) =>
        _compactHeaderOrFooter(file.content),
      _ => file.content,
    };
    final copy = ArchiveFile.bytes(file.name, content)
      ..compression = file.compression
      ..lastModTime = file.lastModTime
      ..mode = file.mode;
    output.add(copy);
  }
  final encoded = Uint8List.fromList(ZipEncoder().encode(output));
  final base = fileName.substring(0, fileName.length - 5);
  return <String, Object>{
    'bytes': encoded,
    'fileName': '${base}_SPACE_SAVED.docx',
    'wasCompacted': true,
    'detectedPages': detectedPages,
    'optionGroupsCompacted': optionGroupsCompacted,
    'blankLinesRemoved': blankLinesRemoved,
  };
}

int _detectPageCount(Archive archive, XmlDocument document) {
  final appProperties = archive.files
      .where((file) => file.name == 'docProps/app.xml' && file.isFile)
      .firstOrNull;
  if (appProperties != null) {
    try {
      final properties = XmlDocument.parse(utf8.decode(appProperties.content));
      final pages = properties.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'Pages')
          .map((element) => int.tryParse(element.innerText.trim()))
          .whereType<int>()
          .firstOrNull;
      if (pages != null && pages > 0) return pages;
    } catch (_) {
      // Fall through to layout markers and the conservative estimate.
    }
  }

  var renderedBreaks = 0;
  var manualPageBreaks = 0;
  for (final element in document.descendants.whereType<XmlElement>()) {
    if (element.name.local == 'lastRenderedPageBreak' ||
        element.name.local == 'pageBreakBefore') {
      renderedBreaks++;
    } else if (element.name.local == 'br' &&
        _attribute(element, 'type') == 'page') {
      manualPageBreaks++;
    }
  }
  final markedPages = renderedBreaks + manualPageBreaks + 1;
  if (markedPages > 1) return markedPages;

  var layoutLines = 0.0;
  for (final paragraph in document.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'p',
  )) {
    final text = _paragraphText(paragraph).trim();
    final wrappedLines = text.isEmpty
        ? 0.55
        : (text.length / 90).ceilToDouble();
    final manualLines = paragraph.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'br')
        .length;
    layoutLines += wrappedLines + manualLines + 0.18;
  }
  final images = document.descendants
      .whereType<XmlElement>()
      .where(
        (element) =>
            element.name.local == 'drawing' || element.name.local == 'pict',
      )
      .length;
  final tableRows = document.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'tr')
      .length;
  layoutLines += images * 9 + tableRows * 0.45;
  return (layoutLines / 54).ceil().clamp(1, 1000);
}

Uint8List _compactHeaderOrFooter(Uint8List bytes) {
  try {
    final document = XmlDocument.parse(utf8.decode(bytes));
    for (final paragraph in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'p',
    )) {
      if (_paragraphText(paragraph).trim().isNotEmpty) {
        _setParagraphSpacing(paragraph, before: 0, after: 10, line: 220);
      }
    }
    _compactTableMargins(document);
    return Uint8List.fromList(utf8.encode(document.toXmlString()));
  } catch (_) {
    return bytes;
  }
}

void _normalizeMetadataWraps(XmlElement body) {
  final pattern = RegExp(
    r'^\s*(Subject\s*:\s*.*?)\s{2,}(Time\s*(?:Allotted|Allowed|Alloted)\s*:\s*.*?)\s*$',
    caseSensitive: false,
  );
  for (final paragraph in body.children.whereType<XmlElement>().toList()) {
    if (paragraph.name.local != 'p' || _hasLineBreak(paragraph)) continue;
    final match = pattern.firstMatch(_paragraphText(paragraph));
    if (match == null) continue;
    _replaceParagraph(paragraph, [
      _textParagraphFrom(paragraph, match.group(1)!.trim()),
      _textParagraphFrom(paragraph, match.group(2)!.trim()),
    ]);
  }
}

void _compactPageMargins(XmlElement body) {
  final sections = body.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'sectPr',
  );
  for (final section in sections) {
    final margins =
        _directChild(section, 'pgMar') ??
        _append(section, XmlElement.tag('w:pgMar'));
    _setAttribute(margins, 'top', '500');
    _setAttribute(margins, 'bottom', '500');
    _setAttribute(margins, 'left', '650');
    _setAttribute(margins, 'right', '650');
    _setAttribute(margins, 'header', '300');
    _setAttribute(margins, 'footer', '300');
    _setAttribute(margins, 'gutter', '0');
  }
}

int _collapseBlankParagraphs(XmlElement body) {
  var removed = 0;
  var previousBlank = false;
  for (final node in body.children.whereType<XmlElement>().toList()) {
    if (node.name.local != 'p') {
      previousBlank = false;
      continue;
    }
    final blank =
        _paragraphText(node).trim().isEmpty && !_hasProtectedContent(node);
    if (!blank) {
      previousBlank = false;
      continue;
    }
    if (previousBlank) {
      node.remove();
      removed++;
      continue;
    }
    previousBlank = true;
    _setParagraphSpacing(node, before: 0, after: 0, line: 120);
  }
  return removed;
}

int _compactOptionGroups(XmlElement body) {
  var compacted = 0;
  var index = 0;
  while (true) {
    final children = body.children.whereType<XmlElement>().toList();
    if (index >= children.length) break;
    final first = children[index];
    final firstOption = first.name.local == 'p' ? _option(first) : null;
    if (firstOption == null || firstOption.letter != 'a') {
      index++;
      continue;
    }
    final paragraphs = <XmlElement>[first];
    final options = <_Option>[firstOption];
    for (
      var next = index + 1;
      next < children.length && options.length < 4;
      next++
    ) {
      final paragraph = children[next];
      if (paragraph.name.local != 'p') break;
      final option = _option(paragraph);
      final expected = String.fromCharCode('a'.codeUnitAt(0) + options.length);
      if (option == null || option.letter != expected) break;
      paragraphs.add(paragraph);
      options.add(option);
    }
    if (options.length < 2) {
      index++;
      continue;
    }

    final columns = _optionColumns(options);
    if (columns == 1) {
      index += options.length;
      continue;
    }

    final replacements = <XmlElement>[];
    for (var start = 0; start < options.length; start += columns) {
      final end = (start + columns).clamp(0, options.length);
      replacements.add(_optionRow(options.sublist(start, end), columns));
    }
    first.replace(replacements.first);
    for (final replacement in replacements.skip(1)) {
      replacements.first.parent!.children.insert(
        replacements.first.parent!.children.indexOf(replacements.first) + 1,
        replacement,
      );
    }
    for (final paragraph in paragraphs.skip(1)) {
      paragraph.remove();
    }
    compacted++;
    index += replacements.length;
  }
  return compacted;
}

int _compactInlineOptionGroups(XmlElement body) {
  var compacted = 0;
  for (final paragraph in body.children.whereType<XmlElement>().toList()) {
    if (paragraph.name.local != 'p' || !_hasLineBreak(paragraph)) continue;
    if (_hasProtectedContent(
      paragraph,
      allowLineBreaks: true,
      allowTabs: true,
      allowTextHyperlinks: true,
    )) {
      continue;
    }
    final lines = _paragraphTextWithBreaks(paragraph)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2 || lines.length > 5) continue;
    final firstOptionIndex = lines.indexWhere(
      (line) => _optionText(line) != null,
    );
    if (firstOptionIndex < 0 || firstOptionIndex > 1) continue;
    final question = firstOptionIndex == 1 ? lines.first : null;
    final optionLines = lines.sublist(firstOptionIndex);
    if (optionLines.length < 2 || optionLines.length > 4) continue;
    final options = optionLines.map(_optionText).toList();
    if (options.any((option) => option == null)) continue;
    final parsed = options.cast<_Option>();
    if (parsed.first.letter != 'a') continue;
    var sequential = true;
    for (var index = 0; index < parsed.length; index++) {
      if (parsed[index].letter !=
          String.fromCharCode('a'.codeUnitAt(0) + index)) {
        sequential = false;
        break;
      }
    }
    if (!sequential) continue;
    final columns = _optionColumns(parsed);
    if (columns == 1) continue;
    final replacements = <XmlElement>[
      if (question != null) _textParagraphFrom(paragraph, question),
    ];
    for (var start = 0; start < parsed.length; start += columns) {
      final end = (start + columns).clamp(0, parsed.length);
      replacements.add(_optionRow(parsed.sublist(start, end), columns));
    }
    _replaceParagraph(paragraph, replacements);
    compacted++;
  }
  return compacted;
}

_Option? _option(XmlElement paragraph) {
  if (_hasProtectedContent(
    paragraph,
    allowTabs: true,
    allowTextHyperlinks: true,
  )) {
    return null;
  }
  final text = _paragraphText(paragraph).trim();
  final parsed = _optionText(text);
  if (parsed == null) return null;
  final runProperties = paragraph.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'rPr')
      .firstOrNull
      ?.copy();
  return _Option(
    letter: parsed.letter,
    text: parsed.text,
    runProperties: runProperties,
  );
}

_Option? _optionText(String text) {
  final match = RegExp(
    r'^\s*(?:\(([a-dA-D])\)|([a-dA-D])[\).:\-])\s*(\S.*)$',
  ).firstMatch(text);
  if (match == null) return null;
  final letter = (match.group(1) ?? match.group(2))!.toLowerCase();
  return _Option(
    letter: letter,
    text: '(${letter.toUpperCase()}) ${match.group(3)!.trim()}',
    runProperties: null,
  );
}

int _optionColumns(List<_Option> options) {
  final totalLength = options.fold<int>(
    0,
    (sum, option) => sum + option.text.length,
  );
  final longest = options.fold<int>(
    0,
    (value, option) => option.text.length > value ? option.text.length : value,
  );
  if (options.length >= 3 && totalLength <= 92 && longest <= 28) {
    return options.length;
  }
  if (totalLength <= 170 && longest <= 62) return 2;
  return 1;
}

XmlElement _optionRow(List<_Option> options, int columns) {
  final paragraphProperties = XmlElement.tag('w:pPr');
  paragraphProperties.children.add(
    XmlElement.tag(
      'w:ind',
      attributes: [
        _wAttribute('left', '0'),
        _wAttribute('right', '0'),
        _wAttribute('firstLine', '0'),
      ],
    ),
  );
  paragraphProperties.children.add(
    XmlElement.tag(
      'w:spacing',
      attributes: [
        _wAttribute('before', '0'),
        _wAttribute('after', '0'),
        _wAttribute('line', '240'),
        _wAttribute('lineRule', 'auto'),
      ],
    ),
  );
  if (options.length > 1) {
    final positions = columns >= 3 ? const [2200, 4400, 6600] : const [4500];
    paragraphProperties.children.add(
      XmlElement.tag(
        'w:tabs',
        children: positions
            .take(options.length - 1)
            .map(
              (position) => XmlElement.tag(
                'w:tab',
                attributes: [
                  _wAttribute('val', 'left'),
                  _wAttribute('pos', '$position'),
                ],
              ),
            ),
      ),
    );
  }
  final children = <XmlNode>[paragraphProperties];
  for (var index = 0; index < options.length; index++) {
    if (index > 0) {
      children.add(XmlElement.tag('w:r', children: [XmlElement.tag('w:tab')]));
    }
    final option = options[index];
    children.add(
      XmlElement.tag(
        'w:r',
        children: [
          if (option.runProperties != null) option.runProperties!.copy(),
          XmlElement.tag(
            'w:t',
            attributes: [XmlAttribute(XmlName('space', 'xml'), 'preserve')],
            children: [XmlText(option.text)],
            isSelfClosing: false,
          ),
        ],
      ),
    );
  }
  return XmlElement.tag('w:p', children: children, isSelfClosing: false);
}

XmlElement _textParagraphFrom(XmlElement source, String text) {
  final paragraphProperties = _directChild(source, 'pPr')?.copy();
  final runProperties = source.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'rPr')
      .firstOrNull
      ?.copy();
  return XmlElement.tag(
    'w:p',
    children: [
      ?paragraphProperties,
      XmlElement.tag(
        'w:r',
        children: [
          ?runProperties,
          XmlElement.tag(
            'w:t',
            attributes: [XmlAttribute(XmlName('space', 'xml'), 'preserve')],
            children: [XmlText(text)],
            isSelfClosing: false,
          ),
        ],
      ),
    ],
    isSelfClosing: false,
  );
}

void _replaceParagraph(XmlElement paragraph, List<XmlElement> replacements) {
  if (replacements.isEmpty) return;
  paragraph.replace(replacements.first);
  var anchor = replacements.first;
  for (final replacement in replacements.skip(1)) {
    final siblings = anchor.parent!.children;
    siblings.insert(siblings.indexOf(anchor) + 1, replacement);
    anchor = replacement;
  }
}

void _compactParagraphFormatting(XmlDocument document) {
  final paragraphs = document.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'p',
  );
  for (final paragraph in paragraphs) {
    final text = _paragraphText(paragraph).trim();
    if (text.isEmpty) continue;
    final question = _isQuestion(text) || _hasNumbering(paragraph);
    if (question) {
      _setParagraphSpacing(paragraph, before: 45, after: 10, line: 240);
      _ensureParagraphFlag(paragraph, 'keepNext');
      _resetQuestionAlignment(paragraph);
      _shrinkTwelvePointRuns(paragraph);
    } else if (_isHeading(paragraph, text)) {
      _setParagraphSpacing(paragraph, before: 70, after: 45, line: 240);
      _ensureParagraphFlag(paragraph, 'keepNext');
      _ensureHeadingRuns(paragraph, prominent: _isProminentHeading(text));
    } else {
      _setParagraphSpacing(paragraph, before: 0, after: 20, line: 240);
      _shrinkTwelvePointRuns(paragraph);
    }
  }
}

bool _hasNumbering(XmlElement paragraph) {
  final properties = _directChild(paragraph, 'pPr');
  return _directChild(properties, 'numPr') != null;
}

void _resetQuestionAlignment(XmlElement paragraph) {
  final properties = _paragraphProperties(paragraph);
  _directChild(properties, 'tabs')?.remove();
  final indentation =
      _directChild(properties, 'ind') ??
      _append(properties, XmlElement.tag('w:ind'));
  _removeAttribute(indentation, 'hanging');
  _setAttribute(indentation, 'left', '0');
  _setAttribute(indentation, 'right', '0');
  _setAttribute(indentation, 'firstLine', '0');

  var reachedText = false;
  for (final element
      in paragraph.descendants.whereType<XmlElement>().toList()) {
    if (element.name.local == 't' && element.innerText.trim().isNotEmpty) {
      reachedText = true;
    } else if (!reachedText && element.name.local == 'tab') {
      element.remove();
    }
  }
}

void _shrinkTwelvePointRuns(XmlElement paragraph) {
  for (final properties in paragraph.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'rPr',
  )) {
    for (final sizeName in ['sz', 'szCs']) {
      final size = _directChild(properties, sizeName);
      if (_attribute(size, 'val') == '24') {
        _setAttribute(size!, 'val', '22');
      }
    }
  }
}

Uint8List _compactStyles(Uint8List bytes) {
  try {
    final styles = XmlDocument.parse(utf8.decode(bytes));
    final targets = <XmlElement>[];
    for (final style in styles.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'style',
    )) {
      final id = (_attribute(style, 'styleId') ?? '').toLowerCase();
      if (id == 'normal') targets.add(style);
    }
    targets.addAll(
      styles.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'docDefaults',
      ),
    );
    for (final target in targets) {
      for (final size in target.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'sz' || element.name.local == 'szCs',
      )) {
        if (_attribute(size, 'val') == '24') {
          _setAttribute(size, 'val', '22');
        }
      }
    }
    return Uint8List.fromList(utf8.encode(styles.toXmlString()));
  } catch (_) {
    return bytes;
  }
}

void _compactTableMargins(XmlDocument document) {
  final cells = document.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'tc',
  );
  for (final cell in cells) {
    final properties =
        _directChild(cell, 'tcPr') ?? _prepend(cell, XmlElement.tag('w:tcPr'));
    final margins =
        _directChild(properties, 'tcMar') ??
        _append(properties, XmlElement.tag('w:tcMar'));
    for (final side in ['top', 'bottom', 'left', 'right']) {
      final margin =
          _directChild(margins, side) ??
          _append(margins, XmlElement.tag('w:$side'));
      _setAttribute(
        margin,
        'w',
        side == 'left' || side == 'right' ? '70' : '35',
      );
      _setAttribute(margin, 'type', 'dxa');
    }
  }
}

void _setParagraphSpacing(
  XmlElement paragraph, {
  required int before,
  required int after,
  required int line,
}) {
  final properties = _paragraphProperties(paragraph);
  final spacing =
      _directChild(properties, 'spacing') ??
      _append(properties, XmlElement.tag('w:spacing'));
  _setAttribute(spacing, 'before', '$before');
  _setAttribute(spacing, 'after', '$after');
  _setAttribute(spacing, 'line', '$line');
  _setAttribute(spacing, 'lineRule', 'auto');
  _setAttribute(spacing, 'beforeAutospacing', '0');
  _setAttribute(spacing, 'afterAutospacing', '0');
}

void _ensureParagraphFlag(XmlElement paragraph, String name) {
  final properties = _paragraphProperties(paragraph);
  if (_directChild(properties, name) == null) {
    properties.children.add(XmlElement.tag('w:$name'));
  }
}

void _ensureHeadingRuns(XmlElement paragraph, {required bool prominent}) {
  final minimum = prominent ? 28 : 22;
  for (final run in paragraph.children.whereType<XmlElement>().where(
    (element) => element.name.local == 'r',
  )) {
    final properties =
        _directChild(run, 'rPr') ?? _prepend(run, XmlElement.tag('w:rPr'));
    if (_directChild(properties, 'b') == null) {
      properties.children.add(XmlElement.tag('w:b'));
    }
    for (final sizeName in ['sz', 'szCs']) {
      final size =
          _directChild(properties, sizeName) ??
          _append(properties, XmlElement.tag('w:$sizeName'));
      final current = int.tryParse(_attribute(size, 'val') ?? '') ?? 0;
      if (current < minimum) _setAttribute(size, 'val', '$minimum');
    }
  }
}

bool _isHeading(XmlElement paragraph, String text) {
  final style = _directChild(_directChild(paragraph, 'pPr'), 'pStyle');
  final styleName = (_attribute(style, 'val') ?? '').toLowerCase();
  if (styleName.contains('heading') || styleName.contains('title')) return true;
  if (text.length > 100) return false;
  return RegExp(
        r'^(academy|school|college|test|class|subject|name|roll\s*no|time|total\s*marks|marks|date|section|part|instructions?|attempt)\b',
        caseSensitive: false,
      ).hasMatch(text) ||
      (text.length <= 65 &&
          text.contains(RegExp(r'[A-Z]')) &&
          text == text.toUpperCase() &&
          text.contains(RegExp(r'[A-Z]{3}')));
}

bool _isProminentHeading(String text) =>
    RegExp(
      r'^(academy|school|college|test|examination|exam)\b|\b(academy|school|test|examination|exam)\b.*$',
      caseSensitive: false,
    ).hasMatch(text.trim()) &&
    text.length <= 80;

bool _isQuestion(String text) => RegExp(
  r'^(?:q(?:uestion)?\s*\.?\s*\d+|\d+[\).])\s*',
  caseSensitive: false,
).hasMatch(text);

bool _hasProtectedContent(
  XmlElement paragraph, {
  bool allowLineBreaks = false,
  bool allowTabs = false,
  bool allowTextHyperlinks = false,
}) => paragraph.descendants.whereType<XmlElement>().any(
  (element) => {
    'drawing',
    'pict',
    'object',
    'oMath',
    'oMathPara',
    'fldChar',
    'instrText',
    if (!allowTextHyperlinks) 'hyperlink',
    if (!allowLineBreaks) 'br',
    if (!allowTabs) 'tab',
    'sym',
    'pageBreakBefore',
  }.contains(element.name.local),
);

bool _hasLineBreak(XmlElement paragraph) => paragraph.descendants
    .whereType<XmlElement>()
    .any((element) => element.name.local == 'br');

String _paragraphTextWithBreaks(XmlElement paragraph) {
  final buffer = StringBuffer();
  for (final element in paragraph.descendants.whereType<XmlElement>()) {
    if (element.name.local == 't') {
      buffer.write(element.innerText);
    } else if (element.name.local == 'br') {
      buffer.writeln();
    } else if (element.name.local == 'tab') {
      buffer.write(' ');
    }
  }
  return buffer.toString();
}

String _paragraphText(XmlElement paragraph) => paragraph.descendants
    .whereType<XmlElement>()
    .where((element) => element.name.local == 't')
    .map((element) => element.innerText)
    .join();

XmlElement _paragraphProperties(XmlElement paragraph) =>
    _directChild(paragraph, 'pPr') ??
    _prepend(paragraph, XmlElement.tag('w:pPr'));

XmlElement? _directChild(XmlElement? parent, String localName) {
  if (parent == null) return null;
  return parent.children.whereType<XmlElement>().firstWhereOrNull(
    (element) => element.name.local == localName,
  );
}

XmlElement _append(XmlElement parent, XmlElement child) {
  parent.children.add(child);
  return child;
}

XmlElement _prepend(XmlElement parent, XmlElement child) {
  parent.children.insert(0, child);
  return child;
}

void _setAttribute(XmlElement element, String localName, String value) {
  final existing = element.attributes.firstWhereOrNull(
    (attribute) => attribute.name.local == localName,
  );
  if (existing == null) {
    element.attributes.add(_wAttribute(localName, value));
  } else {
    existing.value = value;
  }
}

void _removeAttribute(XmlElement element, String localName) {
  final attribute = element.attributes.firstWhereOrNull(
    (candidate) => candidate.name.local == localName,
  );
  if (attribute != null) element.attributes.remove(attribute);
}

String? _attribute(XmlElement? element, String localName) => element?.attributes
    .firstWhereOrNull((attribute) => attribute.name.local == localName)
    ?.value;

XmlAttribute _wAttribute(String localName, String value) =>
    XmlAttribute(XmlName(localName, 'w'), value);

class _Option {
  const _Option({
    required this.letter,
    required this.text,
    required this.runProperties,
  });

  final String letter;
  final String text;
  final XmlElement? runProperties;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;

  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
