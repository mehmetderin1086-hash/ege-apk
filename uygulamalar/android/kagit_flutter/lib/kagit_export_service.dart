import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

import 'kagit_models.dart';

enum PiiKind { tcKimlik, telefon, eposta, iban, tarih }

extension PiiKindLabel on PiiKind {
  String get title {
    switch (this) {
      case PiiKind.tcKimlik:
        return 'T.C. Kimlik No';
      case PiiKind.telefon:
        return 'Telefon';
      case PiiKind.eposta:
        return 'E-posta';
      case PiiKind.iban:
        return 'IBAN';
      case PiiKind.tarih:
        return 'Tarih';
    }
  }
}

class PiiMatch {
  const PiiMatch({required this.kind, required this.value});
  final PiiKind kind;
  final String value;
}

/// Türkçe kişisel veri (PII) doğrulayıcı ve karartma motoru.
class PiiRedactor {
  static final RegExp _tcRegex = RegExp(r'(?<!\d)[1-9]\d{10}(?!\d)');
  static final RegExp _phoneRegex = RegExp(
    r'(?<!\d)(?:\+?90[\s.\-]?|0)?\(?[2-5]\d{2}\)?[\s.\-]?\d{3}[\s.\-]?\d{2}[\s.\-]?\d{2}(?!\d)',
  );
  static final RegExp _emailRegex = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
  static final RegExp _ibanRegex = RegExp(r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){3,7}(?:\s?[A-Z0-9]{1,3})?\b');
  static final RegExp _dateRegex = RegExp(
    r'(?<!\d)(?:0?[1-9]|[12]\d|3[01])[./\-](?:0?[1-9]|1[0-2])[./\-](?:19|20)?\d{2}(?!\d)',
  );

  /// 11 haneli T.C. Kimlik Numarası mod-10/11 sağlama algoritması.
  static bool tcGecerli(String raw) {
    if (raw.length != 11 || raw.startsWith('0')) return false;
    final digits = raw.codeUnits.map((c) => c - 48).toList();
    if (digits.any((d) => d < 0 || d > 9)) return false;
    final oddSum = digits[0] + digits[2] + digits[4] + digits[6] + digits[8];
    final evenSum = digits[1] + digits[3] + digits[5] + digits[7];
    final d10 = ((oddSum * 7 - evenSum) % 10 + 10) % 10;
    if (digits[9] != d10) return false;
    final sum10 = digits.take(10).fold<int>(0, (a, b) => a + b);
    return digits[10] == sum10 % 10;
  }

  /// ISO 7064 Mod-97 IBAN sağlama algoritması (64-bit taşma yapmaz).
  static bool ibanGecerli(String raw) {
    final cleaned = raw.replaceAll(' ', '').toUpperCase();
    if (cleaned.length < 15 || cleaned.length > 34) return false;
    final rotated = cleaned.substring(4) + cleaned.substring(0, 4);
    int rem = 0;
    for (int i = 0; i < rotated.length; i++) {
      final code = rotated.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        rem = (rem * 10 + (code - 48)) % 97;
      } else if (code >= 65 && code <= 90) {
        final val = code - 55; // A=10 .. Z=35
        rem = (rem * 100 + val) % 97;
      } else {
        return false;
      }
    }
    return rem == 1;
  }

  static List<PiiMatch> detect(
    String text, {
    Set<PiiKind> enabledKinds = const {
      PiiKind.tcKimlik,
      PiiKind.telefon,
      PiiKind.eposta,
      PiiKind.iban,
      PiiKind.tarih,
    },
  }) {
    final found = <PiiMatch>[];
    if (enabledKinds.contains(PiiKind.tcKimlik)) {
      for (final m in _tcRegex.allMatches(text)) {
        final v = m.group(0)!;
        if (tcGecerli(v)) found.add(PiiMatch(kind: PiiKind.tcKimlik, value: v));
      }
    }
    if (enabledKinds.contains(PiiKind.iban)) {
      for (final m in _ibanRegex.allMatches(text)) {
        final v = m.group(0)!;
        if (ibanGecerli(v)) found.add(PiiMatch(kind: PiiKind.iban, value: v));
      }
    }
    if (enabledKinds.contains(PiiKind.eposta)) {
      for (final m in _emailRegex.allMatches(text)) {
        found.add(PiiMatch(kind: PiiKind.eposta, value: m.group(0)!));
      }
    }
    if (enabledKinds.contains(PiiKind.telefon)) {
      for (final m in _phoneRegex.allMatches(text)) {
        found.add(PiiMatch(kind: PiiKind.telefon, value: m.group(0)!));
      }
    }
    if (enabledKinds.contains(PiiKind.tarih)) {
      for (final m in _dateRegex.allMatches(text)) {
        found.add(PiiMatch(kind: PiiKind.tarih, value: m.group(0)!));
      }
    }
    return found;
  }

  static String maskText(String text, {Set<PiiKind>? enabledKinds}) {
    final kinds = enabledKinds ?? PiiKind.values.toSet();
    var out = text;
    for (final m in detect(text, enabledKinds: kinds)) {
      out = out.replaceAll(m.value, '[${m.kind.title.toUpperCase()} GİZLENDİ]');
    }
    return out;
  }

  /// OCR koordinat kutuları üzerinden PDF sayfasına karartma anotasyonları üretir.
  static List<PdfAnnotation> buildRedactionAnnotations({
    required int pageIndex,
    required List<OcrBlockBox> blocks,
    Set<PiiKind>? enabledKinds,
  }) {
    final kinds = enabledKinds ?? PiiKind.values.toSet();
    final anns = <PdfAnnotation>[];
    int i = 0;
    for (final b in blocks) {
      final matches = detect(b.text, enabledKinds: kinds);
      if (matches.isEmpty) continue;
      anns.add(
        PdfAnnotation(
          id: 'pii_${pageIndex}_${i++}',
          pageIndex: pageIndex,
          kind: AnnotationKind.redact,
          colorValue: 0xFF000000,
          x: b.x,
          y: b.y,
          w: b.w.clamp(0.05, 0.9),
          h: b.h.clamp(0.02, 0.35),
          text: matches.map((m) => m.kind.title).toSet().join(', '),
        ),
      );
    }
    return anns;
  }
}

/// SplitMix64Deterministik A/B Kitapçığı üretici (KagitKit `Kitapcik.swift` ile uyumlu).
class KitapcikSonucu {
  const KitapcikSonucu({
    required this.aMetni,
    required this.bMetni,
    required this.cevapAnahtariMetni,
    required this.bOrderToA,
  });

  final String aMetni;
  final String bMetni;
  final String cevapAnahtariMetni;
  final List<int> bOrderToA; // bIndex -> 0-based aIndex
}

class KitapcikGenerator {
  static List<String> parseQuestions(String rawText) {
    final matches = RegExp(r'(?:^|\n)(?=\d+[.)]\s)').allMatches(rawText.trim()).toList();
    if (matches.isEmpty) {
      return rawText
          .split(RegExp(r'\n{2,}'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final result = <String>[];
    for (int i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i + 1 < matches.length ? matches[i + 1].start : rawText.trim().length;
      final chunk = rawText.trim().substring(start, end).trim();
      final stripped = chunk.replaceFirst(RegExp(r'^\d+[.)]\s*'), '');
      if (stripped.isNotEmpty) result.add(stripped);
    }
    return result;
  }

  /// SplitMix64 ile deteriminstik Fisher-Yates permütasyonu üretir.
  static List<int> splitMixPermutation(int count, int seed) {
    final indices = List<int>.generate(count, (i) => i);
    if (count <= 1) return indices;
    final mask = BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);
    var state = BigInt.from(seed) & mask;
    final inc = BigInt.parse('9E3779B97F4A7C15', radix: 16);
    final m1 = BigInt.parse('BF58476D1CE4E5B9', radix: 16);
    final m2 = BigInt.parse('94D049BB133111EB', radix: 16);

    int nextInt(int upper) {
      state = (state + inc) & mask;
      var z = state;
      z = ((z ^ (z >> 30)) * m1) & mask;
      z = ((z ^ (z >> 27)) * m2) & mask;
      z = z ^ (z >> 31);
      return (z % BigInt.from(upper)).toInt();
    }

    for (int i = count - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = indices[i];
      indices[i] = indices[j];
      indices[j] = tmp;
    }
    return indices;
  }

  static KitapcikSonucu generate({
    required List<String> questions,
    required String examTitle,
    int seed = 202611,
    List<String>? aAnswerKeys,
  }) {
    final perm = splitMixPermutation(questions.length, seed);
    final aBuf = StringBuffer();
    final bBuf = StringBuffer();
    final keyBuf = StringBuffer();

    aBuf.writeln('$examTitle — A KİTAPÇIĞI\n');
    bBuf.writeln('$examTitle — B KİTAPÇIĞI\n');
    keyBuf.writeln('$examTitle — KİTAPÇIK EŞLEŞTİRME & CEVAP ANAHTARI (Tohum: $seed)\n');
    keyBuf.writeln('B Soru No | A Karşılığı | Cevap');
    keyBuf.writeln('----------------------------------');

    for (int i = 0; i < questions.length; i++) {
      aBuf.writeln('${i + 1}. ${questions[i]}\n');

      final origIdx = perm[i];
      bBuf.writeln('${i + 1}. ${questions[origIdx]}\n');

      final ans = (aAnswerKeys != null && origIdx < aAnswerKeys.length) ? aAnswerKeys[origIdx] : '—';
      keyBuf.writeln('B-${(i + 1).toString().padLeft(2, '0')}      | A-${(origIdx + 1).toString().padLeft(2, '0')}        | $ans');
    }

    return KitapcikSonucu(
      aMetni: aBuf.toString().trim(),
      bMetni: bBuf.toString().trim(),
      cevapAnahtariMetni: keyBuf.toString().trim(),
      bOrderToA: perm,
    );
  }
}

class OgrenciPuanSatiri {
  const OgrenciPuanSatiri({
    required this.no,
    required this.adSoyad,
    required this.puan,
    this.notlar = '',
  });

  final String no;
  final String adSoyad;
  final double puan;
  final String notlar;
}

class PuanParser {
  static double sumAnnotations(List<PdfAnnotation> annotations) {
    double total = 0;
    for (final a in annotations) {
      if (a.kind != AnnotationKind.puan) continue;
      final m = RegExp(r'([+\-]?\d+(?:[.,]\d+)?)').firstMatch(a.text.replaceAll(',', '.'));
      if (m != null) {
        total += double.tryParse(m.group(1)!) ?? 0;
      }
    }
    return total;
  }

  static (String no, String adSoyad) parseStudentFilename(String title) {
    final clean = title.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').trim();
    final m = RegExp(r'^(\d+)\s+(.+?)(?:\s*-\s*.*)?$').firstMatch(clean);
    if (m != null) {
      return (m.group(1)!, m.group(2)!.trim());
    }
    return ('—', clean);
  }
}

/// Saf Dart + Archive paketleyicileri: gerçek .xlsx, .docx, .epub, .md, .html üretimi.
class KagitDocumentExporters {
  static String _xmlEsc(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Uint8List buildXlsxScores({
    required String title,
    required List<OgrenciPuanSatiri> rows,
  }) {
    final archive = Archive();

    void addUtf8(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addUtf8(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>',
    );

    addUtf8(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>',
    );

    addUtf8(
      'xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="Puanlar" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>',
    );

    addUtf8(
      'xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>',
    );

    String strCell(String ref, String v) =>
        '<c r="$ref" t="inlineStr"><is><t>${_xmlEsc(v)}</t></is></c>';
    String numCell(String ref, num v) => '<c r="$ref"><v>$v</v></c>';

    final sb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
      ..write('<row r="1">${strCell("A1", title)}</row>')
      ..write('<row r="2">${strCell("A2", "Okul No")}${strCell("B2", "Ad Soyad")}${strCell("C2", "Puan")}${strCell("D2", "Açıklama")}</row>');

    double sum = 0;
    for (int i = 0; i < rows.length; i++) {
      final r = i + 3;
      final row = rows[i];
      sum += row.puan;
      sb.write(
        '<row r="$r">'
        '${strCell("A$r", row.no)}'
        '${strCell("B$r", row.adSoyad)}'
        '${numCell("C$r", row.puan)}'
        '${strCell("D$r", row.notlar)}'
        '</row>',
      );
    }

    final avgRow = rows.length + 3;
    final avg = rows.isEmpty ? 0.0 : double.parse((sum / rows.length).toStringAsFixed(2));
    sb
      ..write('<row r="$avgRow">${strCell("A$avgRow", "Ortalama")}${strCell("B$avgRow", "${rows.length} Öğrenci")}${numCell("C$avgRow", avg)}</row>')
      ..write('</sheetData></worksheet>');

    addUtf8('xl/worksheets/sheet1.xml', sb.toString());
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static Uint8List buildDocx({
    required String title,
    required List<String> pages,
  }) {
    final archive = Archive();
    void addUtf8(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addUtf8(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>',
    );

    addUtf8(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>',
    );

    final body = StringBuffer()
      ..write('<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="36"/></w:rPr><w:t>${_xmlEsc(title)}</w:t></w:r></w:p>');

    for (int i = 0; i < pages.length; i++) {
      if (pages.length > 1) {
        body.write('<w:p><w:r><w:rPr><w:b/><w:color w:val="DB3D33"/></w:rPr><w:t>Sayfa ${i + 1}</w:t></w:r></w:p>');
      }
      for (final line in pages[i].split('\n')) {
        body.write('<w:p><w:r><w:t xml:space="preserve">${_xmlEsc(line)}</w:t></w:r></w:p>');
      }
      if (i + 1 < pages.length) {
        body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }

    addUtf8(
      'word/document.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body<w:sectPr/></w:body></w:document>',
    );

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static Uint8List buildEpub({
    required String title,
    required String author,
    required List<String> pages,
  }) {
    final archive = Archive();
    final mimeBytes = utf8.encode('application/epub+zip');
    archive.addFile(ArchiveFile.noCompress('mimetype', mimeBytes.length, mimeBytes));

    void addUtf8(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addUtf8(
      'META-INF/container.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>'
      '</container>',
    );

    final manifest = StringBuffer();
    final spine = StringBuffer();
    final safePages = pages.isEmpty ? ['Boş belge'] : pages;

    for (int i = 0; i < safePages.length; i++) {
      final name = 'page_${i + 1}.xhtml';
      manifest.write('<item id="p${i + 1}" href="$name" media-type="application/xhtml+xml"/>');
      spine.write('<itemref idref="p${i + 1}"/>');

      final paragraphs = safePages[i]
          .split('\n\n')
          .map((p) => '<p>${_xmlEsc(p.trim()).replaceAll('\n', '<br/>')}</p>')
          .join('\n');
      addUtf8(
        'OEBPS/$name',
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>${_xmlEsc(title)}</title></head>'
        '<body><h2>Sayfa ${i + 1}</h2>$paragraphs</body></html>',
      );
    }

    addUtf8(
      'OEBPS/content.opf',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>${_xmlEsc(title)}</dc:title>'
      '<dc:creator>${_xmlEsc(author)}</dc:creator>'
      '<dc:language>tr</dc:language>'
      '<dc:identifier id="bookid">kagit-${DateTime.now().millisecondsSinceEpoch}</dc:identifier>'
      '</metadata>'
      '<manifest>$manifest</manifest>'
      '<spine>$spine</spine>'
      '</package>',
    );

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static String compareDocuments({
    required String firstTitle,
    required String firstText,
    required String secondTitle,
    required String secondText,
  }) {
    final aLines = firstText.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final bLines = secondText.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final aSet = aLines.toSet();
    final bSet = bLines.toSet();
    final removed = aLines.where((l) => !bSet.contains(l)).toList();
    final added = bLines.where((l) => !aSet.contains(l)).toList();
    final common = aLines.where((l) => bSet.contains(l)).length;

    final sb = StringBuffer()
      ..writeln('KARŞILAŞTIRMA RAPORU')
      ..writeln('1. Belge: $firstTitle (${aLines.length} satır)')
      ..writeln('2. Belge: $secondTitle (${bLines.length} satır)')
      ..writeln('Ortak Satır: $common | Çıkarılan: ${removed.length} | Eklenen: ${added.length}')
      ..writeln('');

    if (removed.isEmpty && added.isEmpty) {
      sb.writeln('İki belgenin çıkarılan metin içerikleri birebir aynı görünüyor.');
      return sb.toString();
    }
    if (removed.isNotEmpty) {
      sb.writeln('--- Sadece "$firstTitle" içinde olanlar ---');
      for (final r in removed.take(30)) {
        sb.writeln('- $r');
      }
      sb.writeln('');
    }
    if (added.isNotEmpty) {
      sb.writeln('+++ Sadece "$secondTitle" içinde olanlar +++');
      for (final a in added.take(30)) {
        sb.writeln('+ $a');
      }
    }
    return sb.toString();
  }
}
