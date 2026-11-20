import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'device_bridge.dart';

/// Office document builders for the "Çalışmalar" center (Windows JARVIS
/// office_work.py equivalent). Document specs use the same JSON schemas:
///  - Word/PDF: {title, paragraphs[], sections[{heading, paragraphs[], bullets[]}],
///               tables[{headers[], rows[[...]]}]}
///  - Excel:    {sheet, headers[], rows[[...]]}
class OfficeDocs {
  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static List<String> _strings(dynamic v) {
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((e) => e.trim().isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) return [v];
    return const [];
  }

  static List<Map<String, dynamic>> _maps(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  static List<List<String>> _rows(dynamic v) {
    if (v is! List) return const [];
    return v.map<List<String>>((r) {
      if (r is List) return r.map((c) => c?.toString() ?? '').toList();
      if (r is Map) return r.values.map((c) => c?.toString() ?? '').toList();
      return [r?.toString() ?? ''];
    }).toList();
  }

  // ------------------------------------------------------------------ DOCX

  static String _runs(String text, {bool bold = false, String? color, int? size}) {
    final out = StringBuffer();
    final re = RegExp(r'\*\*(.+?)\*\*');
    var last = 0;
    void run(String t, bool b) {
      if (t.isEmpty) return;
      final props = StringBuffer();
      if (b) props.write('<w:b/>');
      if (color != null) props.write('<w:color w:val="$color"/>');
      if (size != null) props.write('<w:sz w:val="$size"/>');
      final rPr = props.isEmpty ? '' : '<w:rPr>$props</w:rPr>';
      out.write('<w:r>$rPr<w:t xml:space="preserve">${_esc(t)}</w:t></w:r>');
    }

    for (final m in re.allMatches(text)) {
      run(text.substring(last, m.start), bold);
      run(m.group(1)!, true);
      last = m.end;
    }
    run(text.substring(last), bold);
    return out.toString();
  }

  static String _para(String text, {String? style, bool bold = false}) {
    final pPr = style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>';
    return '<w:p>$pPr${_runs(text, bold: bold)}</w:p>';
  }

  static String _bullet(String text) =>
      '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/><w:ind w:left="567" w:hanging="283"/></w:pPr>'
      '<w:r><w:t xml:space="preserve">• </w:t></w:r>${_runs(text)}</w:p>';

  static String _table(Map<String, dynamic> t) {
    final headers = _strings(t['headers']);
    final rows = _rows(t['rows']);
    final cols = [headers.length, ...rows.map((r) => r.length)].fold<int>(0, (a, b) => a > b ? a : b);
    if (cols == 0) return '';
    final w = (9638 / cols).floor();
    final b = StringBuffer('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/>'
        '<w:tblBorders>');
    for (final side in const ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
      b.write('<w:$side w:val="single" w:sz="4" w:space="0" w:color="94A3B8"/>');
    }
    b.write('</w:tblBorders></w:tblPr><w:tblGrid>');
    for (var i = 0; i < cols; i++) {
      b.write('<w:gridCol w:w="$w"/>');
    }
    b.write('</w:tblGrid>');
    void row(List<String> cells, bool header) {
      b.write('<w:tr>${header ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}');
      for (var i = 0; i < cols; i++) {
        final v = i < cells.length ? cells[i] : '';
        b.write('<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>'
            '${header ? '<w:shd w:val="clear" w:color="auto" w:fill="0F172A"/>' : ''}</w:tcPr>'
            '<w:p>${header ? _runs(v, bold: true, color: 'FFFFFF') : _runs(v)}</w:p></w:tc>');
      }
      b.write('</w:tr>');
    }

    if (headers.isNotEmpty) row(headers, true);
    for (final r in rows) {
      row(r, false);
    }
    b.write('</w:tbl><w:p/>');
    return b.toString();
  }

  static const _wordStyles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri" w:eastAsia="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="240"/><w:pBdr><w:bottom w:val="single" w:sz="12" w:space="4" w:color="22D3EE"/></w:pBdr></w:pPr><w:rPr><w:b/><w:color w:val="0F172A"/><w:sz w:val="40"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="0F172A"/><w:sz w:val="28"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="60"/></w:pPr></w:style>
<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblCellMar><w:left w:w="80" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>
</w:styles>''';

  static String _coreXml(String title) {
    final now = DateTime.now().toUtc().toIso8601String().split('.').first;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${_esc(title)}</dc:title><dc:creator>JARVIS</dc:creator>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">${now}Z</dcterms:modified></cp:coreProperties>';
  }

  static const _appXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
      '<Application>JARVIS</Application></Properties>';

  static Uint8List buildDocx(Map<String, dynamic> spec) {
    final title = spec['title']?.toString().trim() ?? '';
    final body = StringBuffer();
    if (title.isNotEmpty) body.write(_para(title, style: 'Title'));
    for (final p in _strings(spec['paragraphs'])) {
      body.write(_para(p));
    }
    for (final sec in _maps(spec['sections'])) {
      final h = sec['heading']?.toString().trim() ?? '';
      if (h.isNotEmpty) body.write(_para(h, style: 'Heading1'));
      for (final p in _strings(sec['paragraphs'])) {
        body.write(_para(p));
      }
      for (final b in _strings(sec['bullets'])) {
        body.write(_bullet(b));
      }
      for (final t in _maps(sec['tables'])) {
        body.write(_table(t));
      }
    }
    for (final t in _maps(spec['tables'])) {
      body.write(_table(t));
    }
    if (body.isEmpty) body.write('<w:p/>');
    final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>'
        '$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';
    return _zip({
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
          '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
          '</Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
          '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
          '</Relationships>',
      'word/_rels/document.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>',
      'word/document.xml': document,
      'word/styles.xml': _wordStyles,
      'docProps/core.xml': _coreXml(title.isEmpty ? 'JARVIS Belgesi' : title),
      'docProps/app.xml': _appXml,
    });
  }

  // ------------------------------------------------------------------ XLSX

  static String colName(int index) {
    var n = index + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static final _numRe = RegExp(r'^-?\d{1,15}([.,]\d+)?$');

  static String _cell(String ref, String value, int style) {
    final v = value.trim();
    // Numbers stay numeric (except leading-zero codes like phone numbers).
    if (_numRe.hasMatch(v) && !(v.length > 1 && v.startsWith('0') && !v.startsWith('0,') && !v.startsWith('0.'))) {
      return '<c r="$ref" s="${style == 1 ? 1 : 3}"><v>${v.replaceAll(',', '.')}</v></c>';
    }
    // Inline strings are never evaluated, so "=..." can not become a formula.
    return '<c r="$ref" t="inlineStr" s="$style"><is><t xml:space="preserve">${_esc(value)}</t></is></c>';
  }

  static Uint8List buildXlsx(Map<String, dynamic> spec) {
    var sheetName = (spec['sheet']?.toString() ?? 'Sayfa1')
        .replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ')
        .trim();
    if (sheetName.isEmpty) sheetName = 'Sayfa1';
    if (sheetName.length > 31) sheetName = sheetName.substring(0, 31);
    final headers = _strings(spec['headers']);
    final rows = _rows(spec['rows']);
    final cols = [headers.length, ...rows.map((r) => r.length)].fold<int>(0, (a, b) => a > b ? a : b);
    final widths = List<int>.filled(cols == 0 ? 1 : cols, 10);
    void measure(List<String> r) {
      for (var i = 0; i < r.length && i < widths.length; i++) {
        final l = r[i].length + 2;
        if (l > widths[i]) widths[i] = l > 48 ? 48 : l;
      }
    }

    measure(headers);
    rows.forEach(measure);
    final data = StringBuffer();
    var rowNo = 1;
    if (headers.isNotEmpty) {
      data.write('<row r="1">');
      for (var i = 0; i < headers.length; i++) {
        data.write(_cell('${colName(i)}1', headers[i], 1));
      }
      data.write('</row>');
      rowNo = 2;
    }
    for (final r in rows) {
      data.write('<row r="$rowNo">');
      for (var i = 0; i < r.length; i++) {
        data.write(_cell('${colName(i)}$rowNo', r[i], 2));
      }
      data.write('</row>');
      rowNo++;
    }
    final colsXml = StringBuffer('<cols>');
    for (var i = 0; i < widths.length; i++) {
      colsXml.write('<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" customWidth="1"/>');
    }
    colsXml.write('</cols>');
    final pane = headers.isNotEmpty
        ? '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        : '<sheetViews><sheetView workbookViewId="0"/></sheetViews>';
    final autoFilter = headers.isNotEmpty && cols > 0
        ? '<autoFilter ref="A1:${colName(cols - 1)}${rowNo - 1}"/>'
        : '';
    final sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '$pane$colsXml<sheetData>$data</sheetData>$autoFilter</worksheet>';
    const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF0F172A"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left style="thin"><color rgb="FF94A3B8"/></left><right style="thin"><color rgb="FF94A3B8"/></right>'
        '<top style="thin"><color rgb="FF94A3B8"/></top><bottom style="thin"><color rgb="FF94A3B8"/></bottom><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"><alignment wrapText="1" vertical="top"/></xf>'
        '<xf numFmtId="4" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
    return _zip({
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
          '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
          '</Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
          '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
          '</Relationships>',
      'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="${_esc(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
          '${headers.isNotEmpty && cols > 0 ? '<definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">\'${_esc(sheetName)}\'!\$A\$1:\$${colName(cols - 1)}\$${rowNo - 1}</definedName></definedNames>' : ''}'
          '</workbook>',
      'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>',
      'xl/worksheets/sheet1.xml': sheet,
      'xl/styles.xml': styles,
      'docProps/core.xml': _coreXml(sheetName),
      'docProps/app.xml': _appXml,
    });
  }

  // ------------------------------------------------------------------ TXT / MD

  static String buildText(Map<String, dynamic> spec) {
    final b = StringBuffer();
    final title = spec['title']?.toString().trim() ?? '';
    if (title.isNotEmpty) b.writeln('# $title\n');
    for (final p in _strings(spec['paragraphs'])) {
      b.writeln('$p\n');
    }
    for (final sec in _maps(spec['sections'])) {
      final h = sec['heading']?.toString().trim() ?? '';
      if (h.isNotEmpty) b.writeln('## $h\n');
      for (final p in _strings(sec['paragraphs'])) {
        b.writeln('$p\n');
      }
      for (final x in _strings(sec['bullets'])) {
        b.writeln('- $x');
      }
      b.writeln();
    }
    for (final t in [..._maps(spec['tables'])]) {
      final headers = _strings(t['headers']);
      if (headers.isNotEmpty) {
        b.writeln('| ${headers.join(' | ')} |');
        b.writeln('|${List.filled(headers.length, '---').join('|')}|');
      }
      for (final r in _rows(t['rows'])) {
        b.writeln('| ${r.join(' | ')} |');
      }
      b.writeln();
    }
    return b.toString().trim();
  }

  static Future<Uint8List?> buildPdf(Map<String, dynamic> spec) =>
      DeviceBridge.renderPdf(spec);

  // ------------------------------------------------------------------ ZIP

  static Uint8List projectArchive(dynamic entries) {
    if (entries is! List || entries.isEmpty || entries.length > 48) {
      throw const FormatException('Proje 1–48 dosya içermeli.');
    }
    final files = <String, String>{};
    final names = <String>{};
    var bytes = 0;
    for (final item in entries) {
      if (item is! Map || item['path'] is! String || item['content'] is! String) {
        throw const FormatException('Dosya yolu ve içeriği gerekli.');
      }
      final path = item['path'] as String;
      final parts = path.split('/');
      final key = path.toLowerCase();
      if (path.length > 240 || parts.any((p) => p.isEmpty || p == '.' || p == '..' ||
          RegExp(r'[\\:\x00-\x1f]').hasMatch(p)) ||
          names.any((n) => n == key || n.startsWith('$key/') || key.startsWith('$n/'))) {
        throw const FormatException('Geçersiz veya çakışan proje yolu.');
      }
      final content = item['content'] as String;
      bytes += utf8.encode(content).length;
      if (bytes > 1048576) throw const FormatException('Proje 1 MB sınırını aşıyor.');
      names.add(key);
      files[path] = content;
    }
    return _zip(files);
  }

  static Uint8List _zip(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) {
      archive.addFile(ArchiveFile.bytes(name, utf8.encode(content)));
    });
    return ZipEncoder().encodeBytes(archive);
  }

  static Uint8List zipFiles(List<({String name, Uint8List bytes})> files) {
    final archive = Archive();
    final used = <String>{};
    for (final f in files) {
      var name = f.name.replaceAll('\\', '/').split('/').where((p) => p.isNotEmpty && p != '..').join('/');
      if (name.isEmpty) name = 'dosya';
      var unique = name;
      var i = 2;
      while (!used.add(unique)) {
        final dot = name.lastIndexOf('.');
        unique = dot > 0 ? '${name.substring(0, dot)}-$i${name.substring(dot)}' : '$name-$i';
        i++;
      }
      archive.addFile(ArchiveFile.bytes(unique, f.bytes));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// Safe ZIP extraction: no path traversal, at most [maxEntries] entries and
  /// [maxTotalBytes] uncompressed bytes (Windows JARVIS limits).
  static List<({String name, Uint8List bytes})> unzip(
    Uint8List zipBytes, {
    int maxEntries = 2000,
    int maxTotalBytes = 512 * 1024 * 1024,
  }) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final out = <({String name, Uint8List bytes})>[];
    var total = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (out.length >= maxEntries) {
        throw StateError('Arşivde çok fazla dosya var (en fazla $maxEntries).');
      }
      final parts = f.name.replaceAll('\\', '/').split('/');
      if (parts.any((p) => p == '..') || f.name.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(f.name)) {
        continue; // path traversal attempt
      }
      final data = f.readBytes() ?? Uint8List(0);
      total += data.length;
      if (total > maxTotalBytes) {
        throw StateError('Arşivin açılmış boyutu çok büyük.');
      }
      out.add((name: parts.where((p) => p.isNotEmpty).join('/'), bytes: data));
    }
    return out;
  }

  /// Extracts plain text from a .docx (for summaries / OCR fallbacks).
  static String docxText(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = archive.findFile('word/document.xml');
      if (doc == null) return '';
      final xml = utf8.decode(doc.readBytes() ?? Uint8List(0), allowMalformed: true);
      return xml
          .replaceAll(RegExp(r'</w:p>'), '\n')
          .replaceAll(RegExp(r'<w:tab/>'), '\t')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .trim();
    } catch (_) {
      return '';
    }
  }

  static String mimeFor(String fileName) {
    final l = fileName.toLowerCase();
    if (l.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (l.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (l.endsWith('.pdf')) return 'application/pdf';
    if (l.endsWith('.zip')) return 'application/zip';
    if (l.endsWith('.md')) return 'text/markdown';
    if (l.endsWith('.txt')) return 'text/plain';
    if (l.endsWith('.json')) return 'application/json';
    if (l.endsWith('.m4a')) return 'audio/mp4';
    if (l.endsWith('.webm')) return 'audio/webm';
    if (l.endsWith('.mp4')) return 'video/mp4';
    if (l.endsWith('.mp3')) return 'audio/mpeg';
    if (l.endsWith('.png')) return 'image/png';
    if (l.endsWith('.jpg') || l.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}
