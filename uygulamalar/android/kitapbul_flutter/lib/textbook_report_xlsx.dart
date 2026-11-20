import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'textbook_report.dart';

/// Builds a real XLSX with string cells, so user-entered text cannot be a formula.
Uint8List textbookReportXlsx(List<TextbookReportRow> rows) {
  if (rows.length > 10000) throw const FormatException('Çizelge çok büyük');
  String xml(String input) {
    final clean = String.fromCharCodes(
      input.runes.where(
        (c) =>
            c == 9 ||
            c == 10 ||
            c == 13 ||
            (c >= 32 && c <= 0xD7FF) ||
            (c >= 0xE000 && c <= 0xFFFD) ||
            (c >= 0x10000 && c <= 0x10FFFF),
      ),
    );
    return clean
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  final sheet = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="13" width="24" customWidth="1"/></cols><sheetData>',
  );
  final table = [textbookReportHeaders, ...rows.map((r) => r.fields)];
  for (var r = 0; r < table.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < table[r].length; c++) {
      final ref = '${String.fromCharCode(65 + c)}${r + 1}';
      sheet.write(
        '<c r="$ref" t="inlineStr"${r == 0 ? ' s="1"' : ''}><is><t xml:space="preserve">${xml(table[r][c])}</t></is></c>',
      );
    }
    sheet.write('</row>');
  }
  sheet.write(
    '</sheetData><autoFilter ref="A1:M${table.length}"/></worksheet>',
  );
  final files = <String, String>{
    '[Content_Types].xml':
        '''<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''',
    '_rels/.rels':
        '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
    'xl/workbook.xml':
        '''<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Ders Kitabı" sheetId="1" r:id="rId1"/></sheets></workbook>''',
    'xl/_rels/workbook.xml.rels':
        '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''',
    'xl/styles.xml':
        '''<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  };
  final archive = Archive();
  for (final entry in files.entries) {
    final data = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, data.length, data));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null || encoded.length > 25 * 1024 * 1024)
    throw const FormatException('Çizelge çok büyük');
  return Uint8List.fromList(encoded);
}
