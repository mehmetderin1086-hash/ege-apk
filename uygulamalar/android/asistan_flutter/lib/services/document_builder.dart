import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/asistan_models.dart';

class DocumentBuilder {
  static Future<Directory> _outputDir() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/asistan_atolye');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      final tmp = Directory('${Directory.systemTemp.path}/asistan_atolye');
      if (!await tmp.exists()) {
        await tmp.create(recursive: true);
      }
      return tmp;
    }
  }

  static String _safeFileName(String title, String ext) {
    final clean = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final stem = clean.isEmpty ? 'Asistan_Belge' : clean;
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    return '${stem}_$stamp.$ext';
  }

  static Future<GeneratedArtifact> createOfficeDocument({
    required String title,
    required String content,
    required String format,
  }) async {
    final cleanFormat = format.trim().toLowerCase().replaceAll('.', '');
    final dir = await _outputDir();
    late final Uint8List bytes;
    late final String ext;
    late final String mime;

    switch (cleanFormat) {
      case 'pdf':
        ext = 'pdf';
        mime = 'application/pdf';
        bytes = buildPdfBytes(title: title, content: content);
        break;
      case 'docx':
      case 'word':
      case 'doc':
        ext = 'docx';
        mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        bytes = buildDocxBytes(title: title, content: content);
        break;
      case 'xlsx':
      case 'excel':
      case 'xls':
        ext = 'xlsx';
        mime =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        bytes = buildXlsxBytes(title: title, content: content);
        break;
      case 'pptx':
      case 'sunum':
      case 'powerpoint':
        ext = 'pptx';
        mime = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        bytes = buildPptxBytes(title: title, content: content);
        break;
      case 'html':
        ext = 'html';
        mime = 'text/html';
        bytes = Uint8List.fromList(
          utf8.encode(_buildStyledHtml(title: title, content: content)),
        );
        break;
      case 'csv':
        ext = 'csv';
        mime = 'text/csv';
        bytes = Uint8List.fromList(
          utf8.encode(_buildCsvString(title: title, content: content)),
        );
        break;
      case 'json':
        ext = 'json';
        mime = 'application/json';
        bytes = Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent('  ').convert({
              'title': title,
              'createdAt': DateTime.now().toIso8601String(),
              'lines': content
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty)
                  .toList(),
              'rawContent': content,
            }),
          ),
        );
        break;
      case 'md':
      case 'markdown':
        ext = 'md';
        mime = 'text/markdown';
        bytes = Uint8List.fromList(utf8.encode('# $title\n\n$content\n'));
        break;
      default:
        ext = 'txt';
        mime = 'text/plain';
        bytes = Uint8List.fromList(
          utf8.encode('$title\n${'=' * title.length}\n\n$content\n'),
        );
        break;
    }

    final fileName = _safeFileName(title, ext);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    return GeneratedArtifact(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      filePath: file.path,
      format: ext,
      mimeType: mime,
      contentPreview: content.length > 500
          ? '${content.substring(0, 500)}...'
          : content,
      createdAt: DateTime.now(),
      sizeBytes: bytes.length,
    );
  }

  static Future<GeneratedArtifact> saveImageArtifact({
    required String prompt,
    Uint8List? imageBytes,
    String style = 'Siber Holografik',
  }) async {
    final dir = await _outputDir();
    final bytes =
        imageBytes ??
        await renderProceduralArtworkPng(prompt: prompt, style: style);
    final shortTitle = prompt.length > 32
        ? prompt.substring(0, 32).trim()
        : prompt;
    final fileName = _safeFileName(
      shortTitle.isEmpty ? 'AI_Gorsel' : shortTitle,
      'png',
    );
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    return GeneratedArtifact(
      id: 'img_${DateTime.now().microsecondsSinceEpoch}',
      title: shortTitle.isEmpty ? 'AI Görsel Tasarım' : shortTitle,
      filePath: file.path,
      format: 'png',
      mimeType: 'image/png',
      contentPreview: 'Stil: $style • İstem: $prompt',
      createdAt: DateTime.now(),
      sizeBytes: bytes.length,
    );
  }

  // ─── REAL PDF 1.4 GENERATOR ──────────────────────────────────────────────

  static String _pdfEscape(String input) {
    final map = <String, String>{
      'ğ': 'g',
      'Ğ': 'G',
      'ü': 'u',
      'Ü': 'U',
      'ş': 's',
      'Ş': 'S',
      'ı': 'i',
      'İ': 'I',
      'ö': 'o',
      'Ö': 'O',
      'ç': 'c',
      'Ç': 'C',
      '•': '-',
      '—': '-',
      '–': '-',
      '“': '"',
      '”': '"',
      '’': "'",
      '‘': "'",
    };
    final sb = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      if (map.containsKey(ch)) {
        sb.write(map[ch]);
      } else if (ch.codeUnitAt(0) >= 32 && ch.codeUnitAt(0) <= 126) {
        if (ch == '(' || ch == ')' || ch == '\\') {
          sb.write('\\$ch');
        } else {
          sb.write(ch);
        }
      } else {
        sb.write(' ');
      }
    }
    return sb.toString();
  }

  static List<String> _wrapText(String text, int maxCols) {
    final wrapped = <String>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        wrapped.add('');
        continue;
      }
      final words = line.split(RegExp(r'\s+'));
      var current = '';
      for (final word in words) {
        if (current.isEmpty) {
          current = word;
        } else if (current.length + 1 + word.length <= maxCols) {
          current = '$current $word';
        } else {
          wrapped.add(current);
          current = word;
        }
      }
      if (current.isNotEmpty) {
        wrapped.add(current);
      }
    }
    return wrapped;
  }

  static Uint8List buildPdfBytes({
    required String title,
    required String content,
  }) {
    final allLines = <String>[
      title.toUpperCase(),
      'Asistan AI Stüdyosu - ${DateTime.now().toIso8601String().substring(0, 10)}',
      '------------------------------------------------------------------------',
      '',
      ..._wrapText(content, 78),
    ];

    const linesPerPage = 44;
    final pageChunks = <List<String>>[];
    for (int i = 0; i < allLines.length; i += linesPerPage) {
      pageChunks.add(
        allLines.sublist(i, math.min(i + linesPerPage, allLines.length)),
      );
    }
    if (pageChunks.isEmpty) {
      pageChunks.add([title]);
    }

    final objects = <String>[];
    // Obj 1: Catalog
    objects.add('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');
    // Obj 2: Pages placeholder
    objects.add('');
    // Obj 3: Font
    objects.add(
      '3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
    );

    final pageIds = <int>[];
    var nextId = 4;
    for (final chunk in pageChunks) {
      final pageObjId = nextId++;
      final contentObjId = nextId++;
      pageIds.add(pageObjId);

      final streamBuf = StringBuffer();
      streamBuf.writeln('BT');
      streamBuf.writeln('/F1 11 Tf');
      streamBuf.writeln('50 780 Td');
      streamBuf.writeln('16 TL');
      for (final line in chunk) {
        streamBuf.writeln('(${_pdfEscape(line)}) Tj T*');
      }
      streamBuf.writeln('ET');
      final streamStr = streamBuf.toString();

      objects.add(
        '$pageObjId 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 3 0 R >> >> /Contents $contentObjId 0 R >>\nendobj\n',
      );
      objects.add(
        '$contentObjId 0 obj\n<< /Length ${streamStr.length} >>\nstream\n$streamStr\nendstream\nendobj\n',
      );
    }

    final kids = pageIds.map((id) => '$id 0 R').join(' ');
    objects[1] =
        '2 0 obj\n<< /Type /Pages /Kids [$kids] /Count ${pageIds.length} >>\nendobj\n';

    final pdf = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    for (final obj in objects) {
      offsets.add(pdf.length);
      pdf.write(obj);
    }
    final xrefStart = pdf.length;
    pdf.writeln('xref');
    pdf.writeln('0 ${objects.length + 1}');
    pdf.writeln('0000000000 65535 f ');
    for (int i = 1; i < offsets.length; i++) {
      pdf.writeln('${offsets[i].toString().padLeft(10, '0')} 00000 n ');
    }
    pdf.writeln('trailer');
    pdf.writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>');
    pdf.writeln('startxref');
    pdf.writeln('$xrefStart');
    pdf.writeln('%%EOF');

    return Uint8List.fromList(latin1.encode(pdf.toString()));
  }

  // ─── REAL WORD (DOCX) OPENXML GENERATOR ──────────────────────────────────

  static String _xmlEscape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static Uint8List buildDocxBytes({
    required String title,
    required String content,
  }) {
    final archive = Archive();

    const contentTypes =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final bodyBuf = StringBuffer();
    bodyBuf.writeln(
      '<w:p><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t>${_xmlEscape(title)}</w:t></w:r></w:p>',
    );
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        final clean = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
        bodyBuf.writeln(
          '<w:p><w:r><w:rPr><w:b/><w:sz w:val="26"/></w:rPr><w:t>${_xmlEscape(clean)}</w:t></w:r></w:p>',
        );
      } else {
        bodyBuf.writeln(
          '<w:p><w:r><w:rPr><w:sz w:val="22"/></w:rPr><w:t>${_xmlEscape(line)}</w:t></w:r></w:p>',
        );
      }
    }

    final docXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $bodyBuf
  </w:body>
</w:document>''';

    void addXml(String path, String xml) {
      final data = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, data.length, data));
    }

    addXml('[Content_Types].xml', contentTypes);
    addXml('_rels/.rels', rels);
    addXml('word/document.xml', docXml);

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  // ─── REAL EXCEL (XLSX) SPREADSHEETML GENERATOR ───────────────────────────

  static Uint8List buildXlsxBytes({
    required String title,
    required String content,
  }) {
    final archive = Archive();

    const contentTypes =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';

    const rootRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

    final safeSheet = _xmlEscape(
      title.length > 25 ? title.substring(0, 25) : title,
    );
    final workbookXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="$safeSheet" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''';

    const wbRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>''';

    final rowsBuf = StringBuffer();
    int rowIndex = 1;
    rowsBuf.writeln(
      '<row r="$rowIndex"><c r="A$rowIndex" t="inlineStr"><is><t>${_xmlEscape(title)}</t></is></c></row>',
    );
    rowIndex++;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^\|?[\s\-:|]+\|?$').hasMatch(line)) continue;

      List<String> cells;
      if (line.contains('|')) {
        cells = line
            .split('|')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (line.contains('\t')) {
        cells = line.split('\t').map((e) => e.trim()).toList();
      } else if (line.contains(';') || line.contains(',')) {
        final sep = line.contains(';') ? ';' : ',';
        cells = line.split(sep).map((e) => e.trim()).toList();
      } else if (line.contains(':')) {
        final idx = line.indexOf(':');
        cells = [line.substring(0, idx).trim(), line.substring(idx + 1).trim()];
      } else {
        cells = [line];
      }

      rowsBuf.write('<row r="$rowIndex">');
      for (int c = 0; c < math.min(cells.length, 26); c++) {
        final colLetter = String.fromCharCode(65 + c);
        final val = cells[c];
        final numVal = double.tryParse(val.replaceAll(',', '.'));
        if (numVal != null) {
          rowsBuf.write('<c r="$colLetter$rowIndex"><v>$numVal</v></c>');
        } else {
          rowsBuf.write(
            '<c r="$colLetter$rowIndex" t="inlineStr"><is><t>${_xmlEscape(val)}</t></is></c>',
          );
        }
      }
      rowsBuf.writeln('</row>');
      rowIndex++;
    }

    final sheetXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    $rowsBuf
  </sheetData>
</worksheet>''';

    void addXml(String path, String xml) {
      final data = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, data.length, data));
    }

    addXml('[Content_Types].xml', contentTypes);
    addXml('_rels/.rels', rootRels);
    addXml('xl/workbook.xml', workbookXml);
    addXml('xl/_rels/workbook.xml.rels', wbRels);
    addXml('xl/worksheets/sheet1.xml', sheetXml);

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  // ─── REAL MULTI-SLIDE POWERPOINT (PPTX) PRESENTATIONML GENERATOR ─────────

  static Uint8List buildPptxBytes({
    required String title,
    required String content,
  }) {
    final archive = Archive();

    final nonEmptyLines = content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final slideGroups = <List<String>>[];
    const linesPerSlide = 8;
    if (nonEmptyLines.isEmpty) {
      slideGroups.add([title]);
    } else {
      for (
        int i = 0;
        i < nonEmptyLines.length && slideGroups.length < 12;
        i += linesPerSlide
      ) {
        slideGroups.add(
          nonEmptyLines.sublist(
            i,
            math.min(i + linesPerSlide, nonEmptyLines.length),
          ),
        );
      }
    }

    final overrides = StringBuffer();
    final sldIdLst = StringBuffer();
    final presRelsBuf = StringBuffer();

    for (int i = 0; i < slideGroups.length; i++) {
      final slideNum = i + 1;
      final rId = 'rId$slideNum';
      final sldId = 256 + i;
      overrides.writeln(
        '  <Override PartName="/ppt/slides/slide$slideNum.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
      sldIdLst.writeln('    <p:sldId id="$sldId" r:id="$rId"/>');
      presRelsBuf.writeln(
        '  <Relationship Id="$rId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$slideNum.xml"/>',
      );
    }

    final contentTypes =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
$overrides</Types>''';

    const rootRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''';

    final presXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldIdLst>
$sldIdLst  </p:sldIdLst>
  <p:sldSz cx="9144000" cy="6858000"/>
</p:presentation>''';

    final presRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
$presRelsBuf</Relationships>''';

    void addXml(String path, String xml) {
      final data = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, data.length, data));
    }

    addXml('[Content_Types].xml', contentTypes);
    addXml('_rels/.rels', rootRels);
    addXml('ppt/presentation.xml', presXml);
    addXml('ppt/_rels/presentation.xml.rels', presRels);

    for (int i = 0; i < slideGroups.length; i++) {
      final slideNum = i + 1;
      final lines = slideGroups[i];
      final slideTitle = slideGroups.length > 1
          ? '$title (Slayt $slideNum / ${slideGroups.length})'
          : title;

      final paragraphs = StringBuffer();
      paragraphs.writeln(
        '<a:p><a:r><a:rPr lang="tr-TR" sz="2600" b="1"/><a:t>${_xmlEscape(slideTitle)}</a:t></a:r></a:p>',
      );
      for (final line in lines) {
        final clean = line.replaceFirst(RegExp(r'^#+\s*'), '• ');
        paragraphs.writeln(
          '<a:p><a:r><a:rPr lang="tr-TR" sz="1700"/><a:t>${_xmlEscape(clean)}</a:t></a:r></a:p>',
        );
      }

      final slideXml =
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
        <p:spPr/>
        <p:txBody>
          <a:bodyPr/>
          <a:lstStyle/>
          $paragraphs
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';
      addXml('ppt/slides/slide$slideNum.xml', slideXml);
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static String _buildCsvString({
    required String title,
    required String content,
  }) {
    String csvCell(String s) {
      final clean = s.replaceAll('"', '""').trim();
      return '"$clean"';
    }

    final sb = StringBuffer();
    sb.writeln('${csvCell("Başlık")},${csvCell(title)}');
    sb.writeln(
      '${csvCell("Satır No")},${csvCell("Kategori / Anahtar")},${csvCell("İçerik / Değer")}',
    );
    int idx = 1;
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.contains(':')) {
        final p = line.indexOf(':');
        sb.writeln(
          '$idx,${csvCell(line.substring(0, p))},${csvCell(line.substring(p + 1))}',
        );
      } else {
        sb.writeln('$idx,${csvCell("Madde $idx")},${csvCell(line)}');
      }
      idx++;
    }
    return sb.toString();
  }

  static String _buildStyledHtml({
    required String title,
    required String content,
  }) {
    final escapedBody = _xmlEscape(content).replaceAll('\n', '<br/>');
    return '''<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${_xmlEscape(title)}</title>
<style>
  body { background: #070B19; color: #F8FAFC; font-family: system-ui, sans-serif; padding: 32px; line-height: 1.65; }
  .card { max-width: 840px; margin: 0 auto; background: #111827; border: 1px solid #00E5FF44; border-radius: 20px; padding: 28px; box-shadow: 0 16px 40px #00000088; }
  h1 { color: #00E5FF; margin-top: 0; }
</style>
</head>
<body>
  <div class="card">
    <h1>${_xmlEscape(title)}</h1>
    <div>$escapedBody</div>
  </div>
</body>
</html>''';
  }

  // ─── PROCEDURAL 3D HOLOGRAPHIC ARTWORK RENDERER (OFFLINE FALLBACK) ───────

  static Future<Uint8List> renderProceduralArtworkPng({
    required String prompt,
    String style = 'Siber Holografik',
  }) async {
    const size = 900.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    final seed = prompt.codeUnits.fold<int>(
      17,
      (a, b) => (a * 31 + b) & 0x7FFFFFFF,
    );
    final rng = math.Random(seed);

    final palette = switch (style.toLowerCase()) {
      final s when s.contains('siri') || s.contains('aurora') => const [
        Color(0xFF0A041A),
        Color(0xFFFF2E93),
        Color(0xFF8B5CF6),
        Color(0xFF00F0FF),
      ],
      final s when s.contains('altın') || s.contains('sinematik') => const [
        Color(0xFF100B06),
        Color(0xFFF59E0B),
        Color(0xFFEC4899),
        Color(0xFF38BDF8),
      ],
      final s when s.contains('doğa') || s.contains('zümrüt') => const [
        Color(0xFF04120E),
        Color(0xFF10B981),
        Color(0xFF06B6D4),
        Color(0xFFA855F7),
      ],
      _ => const [
        Color(0xFF050816),
        Color(0xFF00E5FF),
        Color(0xFF6366F1),
        Color(0xFFFF2E93),
      ],
    };

    // Deep cosmic background
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(size, size), [
        palette[0],
        const Color(0xFF03050C),
      ]);
    canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), bgPaint);

    // Nebula glow spheres
    for (int i = 0; i < 5; i++) {
      final cx = rng.nextDouble() * size;
      final cy = rng.nextDouble() * size;
      final rad = 180.0 + rng.nextDouble() * 240.0;
      final col = palette[1 + (i % 3)];
      final glow = Paint()
        ..shader = ui.Gradient.radial(Offset(cx, cy), rad, [
          col.withValues(alpha: 0.36),
          Colors.transparent,
        ]);
      canvas.drawCircle(Offset(cx, cy), rad, glow);
    }

    // Starfield
    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (int i = 0; i < 120; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size, rng.nextDouble() * size),
        0.8 + rng.nextDouble() * 1.8,
        starPaint,
      );
    }

    // Sacred 3D geometric mandala / holographic core in the center
    const center = Offset(size / 2, size / 2 - 30);
    for (int ring = 1; ring <= 6; ring++) {
      final r = ring * 46.0;
      final col = palette[1 + (ring % 3)];
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = col.withValues(alpha: 0.55);
      canvas.drawCircle(center, r, p);

      final petals = 6 + ring * 2;
      final path = Path();
      for (int i = 0; i <= petals * 10; i++) {
        final a = (i / (petals * 10)) * math.pi * 2;
        final wave = r + math.sin(a * petals + ring) * 22.0;
        final x = center.dx + math.cos(a) * wave;
        final y = center.dy + math.sin(a) * wave;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, p);
    }

    // Caption bar at bottom
    final barRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(48, size - 150, size - 96, 102),
      const Radius.circular(24),
    );
    canvas.drawRRect(barRect, Paint()..color = const Color(0xCC0B1124));
    canvas.drawRRect(
      barRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette[1].withValues(alpha: 0.6),
    );

    final tpTitle = TextPainter(
      text: TextSpan(
        text: 'ASİSTAN AI • ${style.toUpperCase()}',
        style: TextStyle(
          color: palette[1],
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size - 140);
    tpTitle.paint(canvas, const Offset(72, size - 130));

    final tpPrompt = TextPainter(
      text: TextSpan(
        text: prompt.length > 90 ? '${prompt.substring(0, 90)}...' : prompt,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 21,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: size - 140);
    tpPrompt.paint(canvas, const Offset(72, size - 98));

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
