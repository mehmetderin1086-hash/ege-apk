import 'dart:ui';

import 'theme_kagit.dart';

enum KagitToolCategory {
  duzenle,
  sayfa,
  tarama,
  donustur,
  guvenlik,
  ogretmen,
  yapay,
}

extension KagitToolCategoryMeta on KagitToolCategory {
  String get title {
    switch (this) {
      case KagitToolCategory.duzenle:
        return 'Düzenle ve İşaretle';
      case KagitToolCategory.sayfa:
        return 'Sayfa İşlemleri';
      case KagitToolCategory.tarama:
        return 'Tarama ve OCR';
      case KagitToolCategory.donustur:
        return 'Dönüştür ve Aktar';
      case KagitToolCategory.guvenlik:
        return 'Güvenlik ve Gizlilik';
      case KagitToolCategory.ogretmen:
        return 'Öğretmen Stüdyosu';
      case KagitToolCategory.yapay:
        return 'Yapay Zekâ';
    }
  }

  Color get color {
    switch (this) {
      case KagitToolCategory.duzenle:
        return KagitTema.vurgu;
      case KagitToolCategory.sayfa:
        return KagitTema.murekkepMavi;
      case KagitToolCategory.tarama:
        return KagitTema.camYesili;
      case KagitToolCategory.donustur:
        return KagitTema.yaprakYesili;
      case KagitToolCategory.guvenlik:
        return const Color(0xFF4F5D75);
      case KagitToolCategory.ogretmen:
        return KagitTema.altinMuhur;
      case KagitToolCategory.yapay:
        return KagitTema.morOkuma;
    }
  }
}

enum KagitToolId {
  goruntuleVeNot,
  imzaEkle,
  duzlestir,
  bosPdfOlustur,
  birlestir,
  bol,
  sayfaDuzenle,
  nUpYerlesim,
  kitapcikBasim,
  sayfaBoyutlandir,
  kenarKirp,
  filigranEkle,
  sayfaNumarasi,
  sikistir,
  kameraTara,
  gorseldenPdf,
  ocrMetinTanima,
  wordOlarakKaydet,
  excelPuanTablosu,
  epubOlustur,
  markdownVeHtml,
  sayfalariGorseleCevir,
  piiKarartma,
  belgeKarsilastir,
  metaTemizle,
  sinavYiginiBol,
  abKitapcik,
  okulBasligiEkle,
  puanToplaVeExcel,
  aiOzetle,
  aiCevir,
  aiSohbet,
  aiSoruUret,
}

class KagitTool {
  const KagitTool({
    required this.id,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.iconName,
    this.requiresDoc = true,
  });

  final KagitToolId id;
  final KagitToolCategory category;
  final String title;
  final String subtitle;
  final String iconName;
  final bool requiresDoc;
}

const List<KagitTool> kagitToolsCatalog = [
  // Düzenle
  KagitTool(
    id: KagitToolId.goruntuleVeNot,
    category: KagitToolCategory.duzenle,
    title: 'Oku, Çiz ve İşaretle',
    subtitle: 'Vurgula, serbest çizim yap, metin ve damga ekle',
    iconName: 'edit_note',
  ),
  KagitTool(
    id: KagitToolId.imzaEkle,
    category: KagitToolCategory.duzenle,
    title: 'İmza At',
    subtitle: 'Kaydedilmiş el yazısı imzanı doğrudan sayfaya yerleştir',
    iconName: 'draw',
  ),
  KagitTool(
    id: KagitToolId.duzlestir,
    category: KagitToolCategory.duzenle,
    title: 'Düzleştir ve Kalıcı Yap',
    subtitle: 'Tüm çizim, imza ve puan damgalarını yeni PDF’e yak',
    iconName: 'layers_clear',
  ),
  KagitTool(
    id: KagitToolId.bosPdfOlustur,
    category: KagitToolCategory.duzenle,
    title: 'Boş Not Defteri Oluştur',
    subtitle: 'Çizgili, kareli, noktalı, müzik dizeği veya boş PDF',
    iconName: 'note_add',
    requiresDoc: false,
  ),

  // Sayfa İşlemleri
  KagitTool(
    id: KagitToolId.birlestir,
    category: KagitToolCategory.sayfa,
    title: 'PDF Birleştir',
    subtitle: 'Birden çok belgeyi sıralayıp tek dosyada topla',
    iconName: 'merge',
    requiresDoc: false,
  ),
  KagitTool(
    id: KagitToolId.bol,
    category: KagitToolCategory.sayfa,
    title: 'PDF Böl / Ayır',
    subtitle: 'Sayfa aralığı seç veya her sayfayı ayrı dosya yap',
    iconName: 'call_split',
  ),
  KagitTool(
    id: KagitToolId.sayfaDuzenle,
    category: KagitToolCategory.sayfa,
    title: 'Sayfaları Düzenle',
    subtitle: 'Sürükle-bırak sırala, 90° döndür, sil veya boş sayfa ekle',
    iconName: 'view_agenda',
  ),
  KagitTool(
    id: KagitToolId.nUpYerlesim,
    category: KagitToolCategory.sayfa,
    title: 'N-up Çoklu Sayfa',
    subtitle: 'Kağıt tasarrufu için yaprağa 2, 4, 6 veya 9 sayfa sığdır',
    iconName: 'grid_view',
  ),
  KagitTool(
    id: KagitToolId.kitapcikBasim,
    category: KagitToolCategory.sayfa,
    title: 'Kitapçık Basım Düzeni',
    subtitle: 'Katlayıp zımbalamaya hazır A4/A5 sırt sırta imposition',
    iconName: 'menu_book',
  ),
  KagitTool(
    id: KagitToolId.sayfaBoyutlandir,
    category: KagitToolCategory.sayfa,
    title: 'Boyut ve Kenarlık',
    subtitle: 'A4, A5 veya US Letter standardına ölçekle',
    iconName: 'aspect_ratio',
  ),
  KagitTool(
    id: KagitToolId.kenarKirp,
    category: KagitToolCategory.sayfa,
    title: 'Kenar Boşluğu Kırp',
    subtitle: 'Sayfa çevresindeki fazla beyaz boşluğu otomatik temizle',
    iconName: 'crop',
  ),
  KagitTool(
    id: KagitToolId.filigranEkle,
    category: KagitToolCategory.sayfa,
    title: 'Filigran Bas',
    subtitle: 'Yarı saydam çapraz veya döşeli taslak/okul mührü',
    iconName: 'water_drop',
  ),
  KagitTool(
    id: KagitToolId.sayfaNumarasi,
    category: KagitToolCategory.sayfa,
    title: 'Numara & Üst/Alt Bilgi',
    subtitle: 'Özel başlık, alt not ve sayfa numarası ekle',
    iconName: 'format_list_numbered',
  ),
  KagitTool(
    id: KagitToolId.sikistir,
    category: KagitToolCategory.sayfa,
    title: 'PDF Sıkıştır',
    subtitle: 'E-posta/WhatsApp paylaşımı için dosya boyutunu küçült',
    iconName: 'compress',
  ),

  // Tarama ve OCR
  KagitTool(
    id: KagitToolId.kameraTara,
    category: KagitToolCategory.tarama,
    title: 'Kamerayla Tara',
    subtitle: 'Belge fotoğrafı çek, siyah-beyaz netleştir ve PDF yap',
    iconName: 'document_scanner',
    requiresDoc: false,
  ),
  KagitTool(
    id: KagitToolId.gorseldenPdf,
    category: KagitToolCategory.tarama,
    title: 'Görsellerden PDF',
    subtitle: 'Galeriden seçtiğin görselleri tek belgede birleştir',
    iconName: 'photo_library',
    requiresDoc: false,
  ),
  KagitTool(
    id: KagitToolId.ocrMetinTanima,
    category: KagitToolCategory.tarama,
    title: 'OCR Metin Çıkar',
    subtitle: 'İnternetsiz ML Kit ile taranmış sayfadaki metni çöz',
    iconName: 'text_fields',
  ),

  // Dönüştür
  KagitTool(
    id: KagitToolId.wordOlarakKaydet,
    category: KagitToolCategory.donustur,
    title: 'PDF → Word (.docx)',
    subtitle: 'Sayfa metinlerini düzenlenebilir Word dosyasına dönüştür',
    iconName: 'description',
  ),
  KagitTool(
    id: KagitToolId.excelPuanTablosu,
    category: KagitToolCategory.donustur,
    title: 'Puan Tablosu (.xlsx)',
    subtitle: 'Öğrenci notlarını ve ortalamayı Excel dosyası yap',
    iconName: 'table_chart',
    requiresDoc: false,
  ),
  KagitTool(
    id: KagitToolId.epubOlustur,
    category: KagitToolCategory.donustur,
    title: 'PDF → EPUB E-Kitap',
    subtitle: 'Okuyuculara uygun bölümlü .epub paketi üret',
    iconName: 'auto_stories',
  ),
  KagitTool(
    id: KagitToolId.markdownVeHtml,
    category: KagitToolCategory.donustur,
    title: 'Markdown / HTML / TXT',
    subtitle: 'Çıkarılan metni web, not veya metin dosyası olarak kaydet',
    iconName: 'code',
  ),
  KagitTool(
    id: KagitToolId.sayfalariGorseleCevir,
    category: KagitToolCategory.donustur,
    title: 'Sayfaları PNG Olarak Aktar',
    subtitle: 'Tüm sayfaları yüksek çözünürlüklü ZIP görsel paketi yap',
    iconName: 'image',
  ),

  // Güvenlik
  KagitTool(
    id: KagitToolId.piiKarartma,
    category: KagitToolCategory.guvenlik,
    title: 'Otomatik PII Karartma',
    subtitle: 'T.C. Kimlik, IBAN, telefon, e-posta ve tarihleri siyahla gizle',
    iconName: 'visibility_off',
  ),
  KagitTool(
    id: KagitToolId.belgeKarsilastir,
    category: KagitToolCategory.guvenlik,
    title: 'Belge Karşılaştır',
    subtitle: 'İki PDF arasındaki satır ve sayfa farklarını bul',
    iconName: 'compare',
  ),
  KagitTool(
    id: KagitToolId.metaTemizle,
    category: KagitToolCategory.guvenlik,
    title: 'Üstveri (Metadata) Temizle',
    subtitle: 'Gizli yazar/cihaz bilgilerini silip temiz kopya üret',
    iconName: 'cleaning_services',
  ),

  // Öğretmen
  KagitTool(
    id: KagitToolId.sinavYiginiBol,
    category: KagitToolCategory.ogretmen,
    title: 'Sınav Yığınını Böl',
    subtitle: 'Taranmış PDF’i X’er sayfa veya sınıf listesine göre dağıt',
    iconName: 'folder_copy',
  ),
  KagitTool(
    id: KagitToolId.abKitapcik,
    category: KagitToolCategory.ogretmen,
    title: 'A / B Kitapçığı Üret',
    subtitle: 'Soruları SplitMix64 ile karıştırıp iki kitapçık ve anahtar yap',
    iconName: 'shuffle',
    requiresDoc: false,
  ),
  KagitTool(
    id: KagitToolId.okulBasligiEkle,
    category: KagitToolCategory.ogretmen,
    title: 'Okul Sınav Başlığı Ekle',
    subtitle: 'İlk sayfaya resmi okul adı, tarih, süre ve Ad-No kutusu bas',
    iconName: 'school',
  ),
  KagitTool(
    id: KagitToolId.puanToplaVeExcel,
    category: KagitToolCategory.ogretmen,
    title: 'Puan Topla → Excel',
    subtitle: 'Belgeye basılan puan damgalarını toplayıp sınıf raporu üret',
    iconName: 'calculate',
    requiresDoc: false,
  ),

  // Yapay Zekâ
  KagitTool(
    id: KagitToolId.aiOzetle,
    category: KagitToolCategory.yapay,
    title: 'Belgeyi Özetle',
    subtitle: 'CLIProxyAPI üzerinden tüm modellerle akıllı özet',
    iconName: 'summarize',
  ),
  KagitTool(
    id: KagitToolId.aiCevir,
    category: KagitToolCategory.yapay,
    title: 'Akıcı Çeviri (TR ↔ EN)',
    subtitle: 'Sayfa yapısını ve terimleri koruyarak çevir',
    iconName: 'translate',
  ),
  KagitTool(
    id: KagitToolId.aiSohbet,
    category: KagitToolCategory.yapay,
    title: 'Belgeyle Sohbet Et',
    subtitle: 'Sayfa numarası kaynaklı soru-cevap asistanı',
    iconName: 'chat',
  ),
  KagitTool(
    id: KagitToolId.aiSoruUret,
    category: KagitToolCategory.yapay,
    title: 'Sınav Sorusu Üret',
    subtitle: 'Çoktan seçmeli, doğru-yanlış ve açık uçlu sınav PDF’i oluştur',
    iconName: 'quiz',
    requiresDoc: false,
  ),
];

enum KitapSortOrder { recent, name, size, pages }

enum ReadingTint { normal, sepia, night }

enum BlankPaperPattern { blank, lined, grid, dot, music }

extension BlankPaperPatternLabel on BlankPaperPattern {
  String get title {
    switch (this) {
      case BlankPaperPattern.blank:
        return 'Düz Boş';
      case BlankPaperPattern.lined:
        return 'Çizgili';
      case BlankPaperPattern.grid:
        return 'Kareli';
      case BlankPaperPattern.dot:
        return 'Noktalı';
      case BlankPaperPattern.music:
        return 'Müzik (Porte)';
    }
  }
}

class Klasor {
  const Klasor({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final String id;
  final String name;
  final int colorValue;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'colorValue': colorValue};

  factory Klasor.fromJson(Map<String, dynamic> json) => Klasor(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Klasör',
        colorValue: json['colorValue'] as int? ?? 0xFFDB3D33,
      );
}

class KitaplikOgesi {
  KitaplikOgesi({
    required this.id,
    required this.title,
    required this.path,
    required this.pageCount,
    required this.fileSize,
    required this.createdAt,
    required this.modifiedAt,
    this.lastOpenedAt,
    this.folderId,
    this.isStarred = false,
    this.inTrash = false,
    this.lastPage = 0,
    this.tags = const [],
    this.cachedOcrText,
  });

  final String id;
  String title;
  String path;
  int pageCount;
  int fileSize;
  final DateTime createdAt;
  DateTime modifiedAt;
  DateTime? lastOpenedAt;
  String? folderId;
  bool isStarred;
  bool inTrash;
  int lastPage;
  List<String> tags;
  String? cachedOcrText;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'path': path,
        'pageCount': pageCount,
        'fileSize': fileSize,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt?.toIso8601String(),
        'folderId': folderId,
        'isStarred': isStarred,
        'inTrash': inTrash,
        'lastPage': lastPage,
        'tags': tags,
        'cachedOcrText': cachedOcrText,
      };

  factory KitaplikOgesi.fromJson(Map<String, dynamic> json) => KitaplikOgesi(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Belge',
        path: json['path'] as String? ?? '',
        pageCount: (json['pageCount'] as num?)?.toInt() ?? 1,
        fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? '') ?? DateTime.now(),
        lastOpenedAt: json['lastOpenedAt'] != null ? DateTime.tryParse(json['lastOpenedAt'] as String) : null,
        folderId: json['folderId'] as String?,
        isStarred: json['isStarred'] as bool? ?? false,
        inTrash: json['inTrash'] as bool? ?? false,
        lastPage: (json['lastPage'] as num?)?.toInt() ?? 0,
        tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
        cachedOcrText: json['cachedOcrText'] as String?,
      );
}

enum AnnotationKind { ink, highlight, text, signature, stamp, redact, puan }

class NormPoint {
  const NormPoint(this.x, this.y);
  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory NormPoint.fromJson(Map<String, dynamic> j) =>
      NormPoint((j['x'] as num?)?.toDouble() ?? 0, (j['y'] as num?)?.toDouble() ?? 0);
}

class PdfAnnotation {
  PdfAnnotation({
    required this.id,
    required this.pageIndex,
    required this.kind,
    required this.colorValue,
    this.points = const [],
    this.x = 0.1,
    this.y = 0.1,
    this.w = 0.15,
    this.h = 0.04,
    this.strokeWidth = 0.004,
    this.fontSize = 0.024,
    this.text = '',
  });

  final String id;
  final int pageIndex;
  final AnnotationKind kind;
  final int colorValue;
  final List<NormPoint> points;
  double x;
  double y;
  double w;
  double h;
  final double strokeWidth;
  final double fontSize;
  String text;

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'kind': kind.name,
        'color': colorValue,
        'points': points.map((p) => p.toJson()).toList(),
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'strokeWidth': strokeWidth,
        'fontSize': fontSize,
        'text': text,
      };

  factory PdfAnnotation.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String? ?? 'ink';
    final k = AnnotationKind.values.firstWhere(
      (e) => e.name == kindStr,
      orElse: () => AnnotationKind.ink,
    );
    return PdfAnnotation(
      id: json['id'] as String? ?? '',
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      kind: k,
      colorValue: (json['color'] as num?)?.toInt() ?? 0xFFDB3D33,
      points: (json['points'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(NormPoint.fromJson)
              .toList() ??
          const [],
      x: (json['x'] as num?)?.toDouble() ?? 0.1,
      y: (json['y'] as num?)?.toDouble() ?? 0.1,
      w: (json['w'] as num?)?.toDouble() ?? 0.15,
      h: (json['h'] as num?)?.toDouble() ?? 0.04,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0.004,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 0.024,
      text: json['text'] as String? ?? '',
    );
  }
}

class OgrenciKaydi {
  const OgrenciKaydi({
    required this.id,
    required this.no,
    required this.adSoyad,
  });

  final String id;
  final String no;
  final String adSoyad;

  Map<String, dynamic> toJson() => {'id': id, 'no': no, 'adSoyad': adSoyad};

  factory OgrenciKaydi.fromJson(Map<String, dynamic> j) => OgrenciKaydi(
        id: j['id'] as String? ?? '',
        no: j['no'] as String? ?? '',
        adSoyad: j['adSoyad'] as String? ?? '',
      );
}

class SinifGrubu {
  SinifGrubu({
    required this.id,
    required this.name,
    this.students = const [],
  });

  final String id;
  String name;
  List<OgrenciKaydi> students;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'students': students.map((s) => s.toJson()).toList(),
      };

  factory SinifGrubu.fromJson(Map<String, dynamic> j) => SinifGrubu(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Sınıf',
        students: (j['students'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(OgrenciKaydi.fromJson)
                .toList() ??
            const [],
      );
}

class OkulBasligi {
  OkulBasligi({
    this.okulAdi = 'T.C. MİLLÎ EĞİTİM BAKANLIĞI',
    this.dersAdi = 'Türk Dili ve Edebiyatı',
    this.sinavTuru = '1. Dönem 1. Yazılı Yoklama',
    this.tarih = '',
    this.sure = '40 dk',
  });

  String okulAdi;
  String dersAdi;
  String sinavTuru;
  String tarih;
  String sure;

  Map<String, dynamic> toJson() => {
        'okulAdi': okulAdi,
        'dersAdi': dersAdi,
        'sinavTuru': sinavTuru,
        'tarih': tarih,
        'sure': sure,
      };

  factory OkulBasligi.fromJson(Map<String, dynamic> j) => OkulBasligi(
        okulAdi: j['okulAdi'] as String? ?? 'T.C. MİLLÎ EĞİTİM BAKANLIĞI',
        dersAdi: j['dersAdi'] as String? ?? 'Ders',
        sinavTuru: j['sinavTuru'] as String? ?? 'Yazılı Yoklama',
        tarih: j['tarih'] as String? ?? '',
        sure: j['sure'] as String? ?? '40 dk',
      );
}

class KagitAyarlari {
  KagitAyarlari({
    this.isDark = false,
    this.otomatikKaydet = true,
    this.yazarAdi = 'Öğretmen',
    this.readingTint = ReadingTint.normal,
    OkulBasligi? okulBasligi,
  }) : okulBasligi = okulBasligi ?? OkulBasligi();

  bool isDark;
  bool otomatikKaydet;
  String yazarAdi;
  ReadingTint readingTint;
  OkulBasligi okulBasligi;

  Map<String, dynamic> toJson() => {
        'isDark': isDark,
        'otomatikKaydet': otomatikKaydet,
        'yazarAdi': yazarAdi,
        'readingTint': readingTint.name,
        'okulBasligi': okulBasligi.toJson(),
      };

  factory KagitAyarlari.fromJson(Map<String, dynamic> j) {
    final tintName = j['readingTint'] as String? ?? 'normal';
    return KagitAyarlari(
      isDark: j['isDark'] as bool? ?? false,
      otomatikKaydet: j['otomatikKaydet'] as bool? ?? true,
      yazarAdi: j['yazarAdi'] as String? ?? 'Öğretmen',
      readingTint: ReadingTint.values.firstWhere(
        (e) => e.name == tintName,
        orElse: () => ReadingTint.normal,
      ),
      okulBasligi: j['okulBasligi'] is Map<String, dynamic>
          ? OkulBasligi.fromJson(j['okulBasligi'] as Map<String, dynamic>)
          : OkulBasligi(),
    );
  }
}

class OcrBlockBox {
  const OcrBlockBox({
    required this.text,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final String text;
  final double x;
  final double y;
  final double w;
  final double h;

  factory OcrBlockBox.fromJson(Map<String, dynamic> j) => OcrBlockBox(
        text: j['text'] as String? ?? '',
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 0,
        h: (j['h'] as num?)?.toDouble() ?? 0,
      );
}
