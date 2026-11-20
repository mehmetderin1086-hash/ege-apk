import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'catalog_search.dart';
import 'isbn.dart';
import 'loan_model.dart';

String _xlsxColumnName(int zeroBasedIndex) {
  var n = zeroBasedIndex + 1;
  final chars = <int>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    chars.add(65 + rem);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(chars.reversed);
}

int _xlsxColumnIndex(String colLetters) {
  var idx = 0;
  for (final code in colLetters.toUpperCase().codeUnits) {
    if (code < 65 || code > 90) break;
    idx = idx * 26 + (code - 64);
  }
  return idx - 1;
}

String _escapeXml(String input) {
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

String _decodeXmlEntities(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&')
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
        final v = int.tryParse(m.group(1)!, radix: 16);
        return v != null ? String.fromCharCode(v) : '';
      })
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final v = int.tryParse(m.group(1)!);
        return v != null ? String.fromCharCode(v) : '';
      });
}

class _XlsxCell {
  const _XlsxCell.text(this.text, {this.alert = false}) : number = null;
  const _XlsxCell.num(int this.number, {this.alert = false}) : text = '';

  final String text;
  final int? number;
  final bool alert;
}

String _buildWorksheetXml({
  required List<String> headers,
  required List<int> widths,
  required List<List<_XlsxCell>> rows,
}) {
  final sb = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetViews><sheetView workbookViewId="0">'
    '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
    '</sheetView></sheetViews><cols>',
  );
  for (var i = 0; i < headers.length; i++) {
    final w = i < widths.length ? widths[i] : 18;
    sb.write(
      '<col min="${i + 1}" max="${i + 1}" width="$w" customWidth="1"/>',
    );
  }
  sb.write('</cols><sheetData>');

  // Header row (style s="1" -> Indigo header with white bold text)
  sb.write('<row r="1" ht="26" customHeight="1">');
  for (var c = 0; c < headers.length; c++) {
    final ref = '${_xlsxColumnName(c)}1';
    sb.write(
      '<c r="$ref" t="inlineStr" s="1"><is><t xml:space="preserve">${_escapeXml(headers[c])}</t></is></c>',
    );
  }
  sb.write('</row>');

  // Data rows (style 2 = white row, style 3 = zebra tinted row, style 4 = alert row)
  for (var r = 0; r < rows.length; r++) {
    final rowNum = r + 2;
    final rowCells = rows[r];
    final rowHasAlert = rowCells.any((c) => c.alert);
    final baseStyle = rowHasAlert ? 4 : (r.isOdd ? 3 : 2);
    sb.write('<row r="$rowNum" ht="21" customHeight="1">');
    for (var c = 0; c < rowCells.length; c++) {
      final ref = '${_xlsxColumnName(c)}$rowNum';
      final cell = rowCells[c];
      if (cell.number != null) {
        sb.write('<c r="$ref" s="$baseStyle"><v>${cell.number}</v></c>');
      } else {
        sb.write(
          '<c r="$ref" t="inlineStr" s="$baseStyle"><is><t xml:space="preserve">${_escapeXml(cell.text)}</t></is></c>',
        );
      }
    }
    sb.write('</row>');
  }

  final lastCol = _xlsxColumnName(headers.length - 1);
  final lastRow = rows.length + 1;
  sb.write(
    '</sheetData><autoFilter ref="A1:$lastCol$lastRow"/></worksheet>',
  );
  return sb.toString();
}

/// Builds a multi-sheet styled Excel (.xlsx) workbook for the library catalog:
/// 1) Kitap Listesi, 2) Ödünçteki Kitaplar, 3) Raf ve Kategori Özeti.
Uint8List buildCatalogXlsx(List<Map<String, dynamic>> books) {
  final activeBooks = books.where((b) => b['deletedAt'] == null).toList();
  if (activeBooks.length > 25000) {
    throw const FormatException('Katalog Excel sınırı aşıldı');
  }

  final catalogHeaders = <String>[
    'Sıra',
    'Demirbaş No',
    'Kitap Adı',
    'Yazar',
    'Yayınevi',
    'ISBN',
    'Kategori',
    'Raf / Konum',
    'Seri',
    'Cilt',
    'Yayın Yılı',
    'Baskı',
    'Sayfa',
    'Dil',
    'Okuma Düzeyi',
    'Toplam Nüsha',
    'Rafta',
    'Ödünçte',
    'Kayıp',
    'Durum',
    'Ödünç Alanlar',
    'Notlar',
  ];
  const catalogWidths = <int>[
    7,
    15,
    34,
    24,
    22,
    17,
    20,
    15,
    18,
    8,
    11,
    12,
    9,
    12,
    14,
    13,
    10,
    10,
    9,
    16,
    28,
    26,
  ];

  final catalogRows = <List<_XlsxCell>>[];
  final loanRows = <List<_XlsxCell>>[];
  final shelfStats = <String, ({int titles, int total, int avail, int loaned})>{};

  for (var i = 0; i < activeBooks.length; i++) {
    final b = activeBooks[i];
    final loans = activeLoans(b);
    final qty = (b['quantity'] as int?) ?? 1;
    final avail = availableCopies(b);
    final lost = (b['lostCount'] as int?) ?? 0;
    final hasOverdue = loans.any(isOverdue);
    final withdrawn = b['isWithdrawn'] == true;

    final copyCodes = ((b['copies'] as List?) ?? [])
        .whereType<Map>()
        .map((c) => (c['accessionCode'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final accession = (b['accessionCode'] ?? '').toString().trim().isNotEmpty
        ? (b['accessionCode'] ?? '').toString().trim()
        : copyCodes.join(', ');

    final statusLabel = withdrawn
        ? 'Düşüldü'
        : hasOverdue
        ? 'Gecikmiş Ödünç'
        : (avail > 0 ? 'Rafta Mevcut' : 'Tamamı Ödünçte');

    final borrowerSummary = loans.map((l) {
      final cls = (l['studentClass'] ?? '').toString().trim();
      return '${l['name'] ?? ''}${cls.isEmpty ? '' : ' ($cls)'}';
    }).join(', ');

    final pageNum = int.tryParse((b['pageCount'] ?? '').toString().trim());
    final yearNum = int.tryParse((b['publicationYear'] ?? '').toString().trim());
    final volNum = b['volume'] is int
        ? b['volume'] as int
        : int.tryParse((b['volume'] ?? '').toString().trim());

    catalogRows.add([
      _XlsxCell.num(i + 1, alert: hasOverdue),
      _XlsxCell.text(accession, alert: hasOverdue),
      _XlsxCell.text('${b['title'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['author'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['publisher'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['isbn'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['category'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['shelf'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['series'] ?? ''}', alert: hasOverdue),
      volNum != null
          ? _XlsxCell.num(volNum, alert: hasOverdue)
          : _XlsxCell.text('', alert: hasOverdue),
      yearNum != null
          ? _XlsxCell.num(yearNum, alert: hasOverdue)
          : _XlsxCell.text('${b['publicationYear'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['edition'] ?? ''}', alert: hasOverdue),
      pageNum != null
          ? _XlsxCell.num(pageNum, alert: hasOverdue)
          : _XlsxCell.text('${b['pageCount'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['language'] ?? ''}', alert: hasOverdue),
      _XlsxCell.text('${b['readingLevel'] ?? ''}', alert: hasOverdue),
      _XlsxCell.num(qty, alert: hasOverdue),
      _XlsxCell.num(avail, alert: hasOverdue),
      _XlsxCell.num(loans.length, alert: hasOverdue),
      _XlsxCell.num(lost, alert: hasOverdue),
      _XlsxCell.text(statusLabel, alert: hasOverdue),
      _XlsxCell.text(borrowerSummary, alert: hasOverdue),
      _XlsxCell.text('${b['notes'] ?? ''}', alert: hasOverdue),
    ]);

    for (final l in loans) {
      final overdue = isOverdue(l);
      final due = DateTime.tryParse('${l['due'] ?? ''}');
      final dueStr = due == null
          ? ''
          : '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')}.${due.year}';
      loanRows.add([
        _XlsxCell.text('${b['title'] ?? ''}', alert: overdue),
        _XlsxCell.text('${b['author'] ?? ''}', alert: overdue),
        _XlsxCell.text('${b['isbn'] ?? ''}', alert: overdue),
        _XlsxCell.text('${b['shelf'] ?? ''}', alert: overdue),
        _XlsxCell.text('${l['name'] ?? ''}', alert: overdue),
        _XlsxCell.text('${l['studentClass'] ?? ''}', alert: overdue),
        _XlsxCell.text(dueStr, alert: overdue),
        _XlsxCell.text(overdue ? 'GECİKMİŞ' : 'Normal', alert: overdue),
      ]);
    }

    if (!withdrawn) {
      final shelfKey = (b['shelf'] ?? '').toString().trim().isEmpty
          ? '(Raf Belirtilmemiş)'
          : (b['shelf'] as String).trim();
      final prev =
          shelfStats[shelfKey] ?? (titles: 0, total: 0, avail: 0, loaned: 0);
      shelfStats[shelfKey] = (
        titles: prev.titles + 1,
        total: prev.total + qty,
        avail: prev.avail + avail,
        loaned: prev.loaned + loans.length,
      );
    }
  }

  final sortedShelfKeys = shelfStats.keys.toList()..sort();
  final summaryRows = <List<_XlsxCell>>[
    for (final k in sortedShelfKeys)
      [
        _XlsxCell.text(k),
        _XlsxCell.num(shelfStats[k]!.titles),
        _XlsxCell.num(shelfStats[k]!.total),
        _XlsxCell.num(shelfStats[k]!.avail),
        _XlsxCell.num(shelfStats[k]!.loaned),
      ],
  ];

  final sheet1Xml = _buildWorksheetXml(
    headers: catalogHeaders,
    widths: catalogWidths,
    rows: catalogRows,
  );
  final sheet2Xml = _buildWorksheetXml(
    headers: const [
      'Kitap Adı',
      'Yazar',
      'ISBN',
      'Raf / Konum',
      'Ödünç Alan Kişi',
      'Sınıf / Şube',
      'Teslim Tarihi',
      'Durum',
    ],
    widths: const [32, 22, 16, 15, 24, 14, 15, 14],
    rows: loanRows,
  );
  final sheet3Xml = _buildWorksheetXml(
    headers: const [
      'Raf / Konum',
      'Çeşit (Başlık) Sayısı',
      'Toplam Nüsha',
      'Raftaki Nüsha',
      'Ödünçteki Nüsha',
    ],
    widths: const [26, 20, 16, 16, 16],
    rows: summaryRows,
  );

  const stylesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="4">
    <font><sz val="11"/><color rgb="FF1F2937"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FF991B1B"/><name val="Calibri"/></font>
  </fonts>
  <fills count="5">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF4338CA"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF5F7FF"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFFEE2E2"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFE2E8F0"/></left>
      <right style="thin"><color rgb="FFE2E8F0"/></right>
      <top style="thin"><color rgb="FFE2E8F0"/></top>
      <bottom style="thin"><color rgb="FFE2E8F0"/></bottom>
      <diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="5">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment vertical="center"/>
    </xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">
      <alignment vertical="center"/>
    </xf>
    <xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment vertical="center"/>
    </xf>
    <xf numFmtId="0" fontId="2" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment vertical="center"/>
    </xf>
  </cellXfs>
  <cellStyles count="1">
    <cellStyle name="Normal" xfId="0" builtinId="0"/>
  </cellStyles>
</styleSheet>''';

  final files = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>'
        '<sheet name="Kitap Listesi" sheetId="1" r:id="rId1"/>'
        '<sheet name="Ödünçteki Kitaplar" sheetId="2" r:id="rId2"/>'
        '<sheet name="Raf Özeti" sheetId="3" r:id="rId3"/>'
        '</sheets>'
        '</workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>'
        '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml': stylesXml,
    'xl/worksheets/sheet1.xml': sheet1Xml,
    'xl/worksheets/sheet2.xml': sheet2Xml,
    'xl/worksheets/sheet3.xml': sheet3Xml,
  };

  final archive = Archive();
  for (final entry in files.entries) {
    final data = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, data.length, data));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null || encoded.length > 25 * 1024 * 1024) {
    throw const FormatException('Excel dosyası çok büyük');
  }
  return Uint8List.fromList(encoded);
}

/// Parses an Excel (.xlsx) workbook's first worksheet into incoming book maps.
List<Map<String, dynamic>> parseCatalogXlsx(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
    throw const FormatException('Excel dosyası geçersiz veya çok büyük');
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
  } catch (_) {
    throw const FormatException('Geçerli bir .xlsx Excel dosyası seçin');
  }

  String? readArchiveXml(String path) {
    final f = archive.findFile(path);
    if (f == null) return null;
    final content = f.content;
    if (content is List<int>) {
      if (content.length > 35 * 1024 * 1024) {
        throw const FormatException('Excel çalışma sayfası çok büyük');
      }
      return utf8.decode(content, allowMalformed: true);
    }
    return null;
  }

  // Parse sharedStrings.xml if present
  final sharedStrings = <String>[];
  final sstXml = readArchiveXml('xl/sharedStrings.xml');
  if (sstXml != null) {
    for (final si in RegExp(
      r'<si\b[^>]*>(.*?)</si>',
      dotAll: true,
    ).allMatches(sstXml)) {
      final buf = StringBuffer();
      for (final t in RegExp(
        r'<t\b[^>]*>(.*?)</t>',
        dotAll: true,
      ).allMatches(si.group(1)!)) {
        buf.write(_decodeXmlEntities(t.group(1)!));
      }
      sharedStrings.add(buf.toString());
    }
  }

  final sheetXml =
      readArchiveXml('xl/worksheets/sheet1.xml') ??
      archive.files
          .where(
            (f) =>
                f.name.startsWith('xl/worksheets/sheet') &&
                f.name.endsWith('.xml'),
          )
          .map((f) => utf8.decode(f.content as List<int>, allowMalformed: true))
          .firstOrNull;
  if (sheetXml == null) {
    throw const FormatException('Excel içinde çalışma sayfası bulunamadı');
  }

  final parsedRows = <List<String>>[];
  for (final rowMatch in RegExp(
    r'<row\b[^>]*>(.*?)</row>',
    dotAll: true,
  ).allMatches(sheetXml)) {
    final rowBody = rowMatch.group(1)!;
    final cells = <int, String>{};
    var maxCol = -1;
    var sequentialCol = 0;

    for (final cMatch in RegExp(
      r'<c\b([^>]*)(?:/>|>(.*?)</c>)',
      dotAll: true,
    ).allMatches(rowBody)) {
      final attrs = cMatch.group(1) ?? '';
      final inner = cMatch.group(2) ?? '';
      final refMatch = RegExp(r'\br="([A-Za-z]+)\d+"').firstMatch(attrs);
      final colIdx = refMatch != null
          ? _xlsxColumnIndex(refMatch.group(1)!)
          : sequentialCol;
      sequentialCol = colIdx + 1;
      if (colIdx > maxCol) maxCol = colIdx;

      final typeMatch = RegExp(r'\bt="([^"]+)"').firstMatch(attrs);
      final cellType = typeMatch?.group(1) ?? '';
      String textVal = '';
      if (cellType == 'inlineStr') {
        final buf = StringBuffer();
        for (final t in RegExp(
          r'<t\b[^>]*>(.*?)</t>',
          dotAll: true,
        ).allMatches(inner)) {
          buf.write(_decodeXmlEntities(t.group(1)!));
        }
        textVal = buf.toString();
      } else {
        final vMatch = RegExp(
          r'<v\b[^>]*>(.*?)</v>',
          dotAll: true,
        ).firstMatch(inner);
        final rawV = vMatch != null ? _decodeXmlEntities(vMatch.group(1)!) : '';
        if (cellType == 's') {
          final sstIdx = int.tryParse(rawV.trim());
          if (sstIdx != null && sstIdx >= 0 && sstIdx < sharedStrings.length) {
            textVal = sharedStrings[sstIdx];
          }
        } else {
          textVal = rawV;
        }
      }
      cells[colIdx] = textVal.trim();
    }
    if (maxCol >= 0) {
      parsedRows.add([
        for (var i = 0; i <= maxCol && i < 64; i++) cells[i] ?? '',
      ]);
    }
  }

  if (parsedRows.length < 2) {
    throw const FormatException('Excel dosyasında aktarılacak kitap satırı yok');
  }

  // Locate header row (first non-empty row containing a recognizable title column)
  var headerRowIndex = 0;
  Map<String, int> columnMap = {};

  String? canonicalFieldForHeader(String rawHeader) {
    final h = foldTurkish(rawHeader.trim())
        .replaceAll(RegExp(r'[^\wçğıöşü\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return switch (h) {
      'kitap adı' ||
      'kitap adi' ||
      'kitap' ||
      'başlık' ||
      'baslik' ||
      'eser adı' ||
      'eser adi' ||
      'title' ||
      'book title' ||
      'name' => 'title',
      'yazar' || 'yazar adı' || 'yazar adi' || 'author' => 'author',
      'yayınevi' ||
      'yayinevi' ||
      'yayıncı' ||
      'yayinci' ||
      'publisher' => 'publisher',
      'isbn' || 'ısbn' || 'isbn 13' || 'ısbn 13' || 'barkod' => 'isbn',
      'kategori' || 'tür' || 'tur' || 'konu' || 'category' => 'category',
      'raf' ||
      'raf konum' ||
      'dolap raf' ||
      'konum' ||
      'shelf' ||
      'location' => 'shelf',
      'demirbaş' ||
      'demirbas' ||
      'demirbaş no' ||
      'demirbas no' ||
      'accession' => 'accessionCode',
      'seri' || 'dizi' || 'series' => 'series',
      'cilt' || 'volume' => 'volume',
      'yayın yılı' ||
      'yayin yili' ||
      'yıl' ||
      'yil' ||
      'basım yılı' ||
      'year' => 'publicationYear',
      'baskı' || 'baski' || 'edition' => 'edition',
      'sayfa' || 'sayfa sayısı' || 'sayfa sayisi' || 'pages' => 'pageCount',
      'dil' || 'language' => 'language',
      'okuma düzeyi' ||
      'okuma duzeyi' ||
      'okuma yaşı' ||
      'seviye' => 'readingLevel',
      'toplam nüsha' ||
      'toplam nusha' ||
      'nüsha' ||
      'nusha' ||
      'nüsha sayısı' ||
      'adet' ||
      'miktar' ||
      'quantity' => 'quantity',
      'notlar' || 'not' || 'açıklama' || 'aciklama' || 'notes' => 'notes',
      _ => null,
    };
  }

  for (var r = 0; r < parsedRows.length && r < 10; r++) {
    final candidate = <String, int>{};
    for (var c = 0; c < parsedRows[r].length; c++) {
      final field = canonicalFieldForHeader(parsedRows[r][c]);
      if (field != null && !candidate.containsKey(field)) {
        candidate[field] = c;
      }
    }
    if (candidate.containsKey('title')) {
      headerRowIndex = r;
      columnMap = candidate;
      break;
    }
  }

  if (!columnMap.containsKey('title')) {
    throw const FormatException(
      'Excel başlık satırında "Kitap Adı" sütunu bulunamadı.',
    );
  }

  String cellAt(List<String> row, String field) {
    final idx = columnMap[field];
    if (idx == null || idx < 0 || idx >= row.length) return '';
    return row[idx].trim();
  }

  final nowMicros = DateTime.now().microsecondsSinceEpoch;
  final results = <Map<String, dynamic>>[];

  for (var r = headerRowIndex + 1; r < parsedRows.length; r++) {
    final row = parsedRows[r];
    final title = cellAt(row, 'title');
    if (title.isEmpty) continue;

    final rawIsbn = cleanIsbnInput(cellAt(row, 'isbn'));
    final validIsbn = rawIsbn.isNotEmpty && isValidIsbn(rawIsbn) ? rawIsbn : '';
    final qtyParsed = int.tryParse(cellAt(row, 'quantity'));
    final quantity = (qtyParsed != null && qtyParsed > 0 && qtyParsed <= 10000)
        ? qtyParsed
        : 1;
    final volParsed = int.tryParse(cellAt(row, 'volume'));

    results.add(
      normalizeBook({
        'id': 'xlsx_${nowMicros}_$r',
        'title': title,
        'author': cellAt(row, 'author'),
        'publisher': cellAt(row, 'publisher'),
        'isbn': validIsbn,
        'category': cellAt(row, 'category'),
        'shelf': cellAt(row, 'shelf'),
        'accessionCode': cellAt(row, 'accessionCode'),
        'series': cellAt(row, 'series'),
        if (volParsed != null && volParsed >= 0) 'volume': volParsed,
        'publicationYear': cellAt(row, 'publicationYear'),
        'edition': cellAt(row, 'edition'),
        'pageCount': cellAt(row, 'pageCount'),
        'language': cellAt(row, 'language'),
        'readingLevel': cellAt(row, 'readingLevel'),
        'notes': cellAt(row, 'notes'),
        'quantity': quantity,
        'isTextbook': false,
        'loans': <Map<String, dynamic>>[],
      }),
    );
  }

  if (results.isEmpty) {
    throw const FormatException('Excel dosyasında geçerli kitap kaydı bulunamadı.');
  }
  return results;
}
