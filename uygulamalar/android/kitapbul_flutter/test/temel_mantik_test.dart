import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitapbul_flutter/ai_book_vision_page.dart';
import 'package:kitapbul_flutter/ai_proxy_service.dart';
import 'package:kitapbul_flutter/app_theme_settings.dart';
import 'package:kitapbul_flutter/book_editor_sheet.dart';
import 'package:kitapbul_flutter/book_images.dart';
import 'package:kitapbul_flutter/book_lookup.dart';
import 'package:kitapbul_flutter/book_visuals.dart';
import 'package:kitapbul_flutter/bulk_isbn_importer_page.dart';
import 'package:kitapbul_flutter/catalog_search.dart';
import 'package:kitapbul_flutter/catalog_views.dart';
import 'package:kitapbul_flutter/catalog_xlsx.dart';
import 'package:kitapbul_flutter/circulation_desk_page.dart';
import 'package:kitapbul_flutter/cover_fetch.dart';
import 'package:kitapbul_flutter/inventory_session.dart';
import 'package:kitapbul_flutter/isbn.dart';
import 'package:kitapbul_flutter/library_atmosphere_studio.dart';
import 'package:kitapbul_flutter/library_discovery_page.dart';
import 'package:kitapbul_flutter/library_labels_page.dart';
import 'package:kitapbul_flutter/loan_model.dart';
import 'package:kitapbul_flutter/loan_settings.dart';
import 'package:kitapbul_flutter/member_store.dart';
import 'package:kitapbul_flutter/ocr_extract.dart';
import 'package:kitapbul_flutter/reading_champions_page.dart';
import 'package:kitapbul_flutter/school_automation_hub.dart';
import 'package:kitapbul_flutter/school_duty_roster.dart';
import 'package:kitapbul_flutter/shelf_photo_scanner_page.dart';
import 'package:kitapbul_flutter/student_profile_page.dart';
import 'package:kitapbul_flutter/student_store.dart';
import 'package:kitapbul_flutter/students_directory_page.dart';
import 'package:kitapbul_flutter/voice_assistant_page.dart';

void main() {
  group('ISBN', () {
    test('geçerli ISBN-13 ve ISBN-10 kabul edilir', () {
      expect(isValidIsbn('978-605-09-0000-6'), isFalse);
      expect(isValidIsbn('9789750719387'), isTrue);
      expect(isValidIsbn('0-306-40615-2'), isTrue);
      expect(isValidIsbn(''), isTrue, reason: 'ISBN isteğe bağlıdır');
    });

    test('geçersiz kontrol basamağı reddedilir', () {
      expect(isValidIsbn('9789750719388'), isFalse);
      expect(isValidIsbn('0306406153'), isFalse);
      expect(isValidIsbn('abc'), isFalse);
    });

    test('ISBN-10 karşılık gelen 978 ISBN-13 ile aynı baskıdır', () {
      expect(canonicalIsbn('0306406152'), '9780306406157');
      expect(canonicalIsbn('978-0-306-40615-7'), '9780306406157');
      expect(canonicalIsbn('geçersiz'), isNull);
    });

    test('cleanIsbnInput görünmez yön karakterlerini temizler ve isbn10Of ASIN üretir', () {
      expect(cleanIsbnInput('ISBN-13: \u200E978-975-07-1938-7'), '9789750719387');
      expect(isbn10Of('978-975-07-1938-7'), '9750719387');
      expect(isbn10Of('9780439420891'), '043942089X');
      expect(isbn10Of('0-306-40615-2'), '0306406152');
      // 979 ile başlayan ISBN-13 için ISBN-10 karşılığı yoktur
      expect(isbn10Of('9799753425420'), isNull);
    });
  });

  group('Türkçe arama', () {
    test('I/ı ve İ/i büyük-küçük harf duyarsız eşleşir', () {
      expect(foldTurkish('IŞIK'), 'ışık');
      expect(foldTurkish('İSTANBUL'), 'istanbul');
    });

    test('katalog araması başlık, yazar ve ISBN ile eşleşir', () {
      final book = <String, dynamic>{
        'title': 'Kürk Mantolu Madonna',
        'author': 'Sabahattin Ali',
        'isbn': '9789753638029',
        'shelf': 'A-3',
      };
      expect(matchesCatalog(book, 'KÜRK'), isTrue);
      expect(matchesCatalog(book, 'sabahattin'), isTrue);
      expect(matchesCatalog(book, '978-975-363-802-9'), isTrue);
      expect(matchesCatalog(book, 'a-3'), isTrue);
      expect(matchesCatalog(book, 'Tutunamayanlar'), isFalse);
      expect(matchesCatalog(book, '   '), isTrue);
    });

    test('nüsha demirbaş koduyla da bulunur', () {
      final book = <String, dynamic>{
        'title': 'Simyacı',
        'copies': [
          {'accessionCode': 'DMR-0042'},
        ],
      };
      expect(matchesCatalog(book, 'dmr-0042'), isTrue);
    });
  });

  group('Amazon ISBN ayrıştırma', () {
    const sampleAmazonHtml = '''
<!DOCTYPE html>
<html>
<head><title>Kürk Mantolu Madonna : Sabahattin Ali: Amazon.com.tr: Kitap</title></head>
<body>
  <div id="wayfinding-breadcrumbs_feature_div">
    <a class="a-link-normal a-color-tertiary" href="/b">Kitap</a>
    <a class="a-link-normal a-color-tertiary" href="/b1">Edebiyat ve Kurgu</a>
    <a class="a-link-normal a-color-tertiary" href="/b2">Roman</a>
  </div>
  <span id="productTitle">  Kürk Mantolu Madonna  </span>
  <div id="bylineInfo">
    <span class="author notFaded">
      <a class="a-link-normal" href="/s">Sabahattin Ali</a>
      <span class="contribution"><span class="a-color-secondary">(Eser Sahibi),</span></span>
    </span>
    <span class="author notFaded">
      <a class="a-link-normal" href="/s2">Örnek Çevirmen</a>
      <span class="contribution"><span class="a-color-secondary">(Çevirmen)</span></span>
    </span>
  </div>
  <img id="landingImage"
       data-a-dynamic-image="{&quot;https://m.media-amazon.com/images/I/41testCover._SY445_SX342_.jpg&quot;:[445,342]}"
       src="https://m.media-amazon.com/images/I/41testCover._SY300_.jpg" />
  <div id="detailBullets_feature_div">
    <ul>
      <li><span class="a-list-item"><span class="a-text-bold">Yayıncı &rlm; : &lrm;</span><span>Yapı Kredi Yayınları; 98. baskı (15 Mart 2019)</span></span></li>
      <li><span class="a-list-item"><span class="a-text-bold">Dil &rlm; : &lrm;</span><span>Türkçe</span></span></li>
      <li><span class="a-list-item"><span class="a-text-bold">Baskı Uzunluğu &rlm; : &lrm;</span><span>160 sayfa</span></span></li>
      <li><span class="a-list-item"><span class="a-text-bold">ISBN-10 &rlm; : &lrm;</span><span>9753638027</span></span></li>
      <li><span class="a-list-item"><span class="a-text-bold">ISBN-13 &rlm; : &lrm;</span><span>978-9753638029</span></span></li>
      <li><span class="a-list-item"><span class="a-text-bold">Okuma yaşı &rlm; : &lrm;</span><span>12 yaş ve üzeri</span></span></li>
    </ul>
  </div>
</body>
</html>
''';

    test('ürün sayfasından başlık, asıl yazar, yayınevi, baskı, yıl, sayfa ve kapak çıkarılır', () {
      final parsed = parseAmazonProductHtml(
        sampleAmazonHtml,
        expectedIsbn: '9789753638029',
      );
      expect(parsed, isNotNull);
      expect(parsed!['source'], 'Amazon');
      expect(parsed['title'], 'Kürk Mantolu Madonna');
      expect(parsed['author'], 'Sabahattin Ali');
      expect(parsed['publisher'], 'Yapı Kredi Yayınları');
      expect(parsed['edition'], '98. baskı');
      expect(parsed['publicationYear'], '2019');
      expect(parsed['pageCount'], '160');
      expect(parsed['language'], 'Türkçe');
      expect(parsed['readingLevel'], '12 yaş ve üzeri');
      expect(parsed['category'], 'Edebiyat ve Kurgu › Roman');
      expect(parsed['isbn'], '9789753638029');
      expect(
        parsed['coverUrl'],
        'https://m.media-amazon.com/images/I/41testCover._SL1000_.jpg',
      );
    });

    test('farklı ISBN baskısına ait sayfa veya bot/404 sayfası reddedilir', () {
      expect(
        parseAmazonProductHtml(sampleAmazonHtml, expectedIsbn: '9789750719387'),
        isNull,
      );
      expect(
        parseAmazonProductHtml(
          '<html><head><title>Sayfa Bulunamadı</title></head><body></body></html>',
        ),
        isNull,
      );
      expect(
        parseAmazonProductHtml(
          '<html><body><form action="/errors/validateCaptcha"></form></body></html>',
        ),
        isNull,
      );
    });

    test('arama sonuçlarından tekil ASIN kodları çıkarılır', () {
      const searchHtml = '''
        <div data-asin="9750719387"></div>
        <div data-asin="B08XYZ1234"></div>
        <div data-asin="9750719387"></div>
      ''';
      expect(parseAmazonSearchAsins(searchHtml), ['9750719387', 'B08XYZ1234']);
    });
  });

  group('Kitapyurdu başlık / yazar / yayınevi ayrıştırma ve sıralama', () {
    const searchHtml = '''
      <div class="ky-product" data-product-id="101">
        <a class="ky-product-cover" href="/kitap/kurk-mantolu-madonna/101.html">
          <img src="https://img.kitapyurdu.com/v1/getImage/fn:111/wi:200/wh:true" />
        </a>
        <a class="ky-product-title" href="/kitap/kurk-mantolu-madonna/101.html">Kürk Mantolu Madonna</a>
        <span class="ky-product-author"><a>Sabahattin Ali</a></span>
        <span class="ky-product-publisher"><a>KAPRA YAYINCILIK</a></span>
      </div>
      <div class="ky-product" data-product-id="202">
        <a class="ky-product-cover" href="/kitap/kurk-mantolu-madonna/202.html">
          <img src="https://img.kitapyurdu.com/v1/getImage/fn:222/wi:200/wh:true" />
        </a>
        <a class="ky-product-title" href="/kitap/kurk-mantolu-madonna/202.html">Kürk Mantolu Madonna</a>
        <span class="ky-product-author"><a>Sabahattin Ali</a></span>
        <span class="ky-product-publisher"><a>YAPI KREDİ YAYINLARI</a></span>
      </div>
    ''';

    test('arama kartları ayrıştırılır ve yayınevi kısaltmasıyla (YKY) doğru baskı öne çıkar', () {
      final candidates = parseKitapyurduSearchHtml(searchHtml);
      expect(candidates, hasLength(2));
      expect(candidates[0].publisher, 'Kapra Yayıncılık');
      expect(
        candidates[0].coverUrl,
        'https://img.kitapyurdu.com/v1/getImage/fn:111/wi:500/wh:true',
      );

      final ranked = filterAndRankKitapyurduCandidates(
        candidates,
        title: 'Kürk Mantolu Madonna',
        author: 'Sabahattin Ali',
        publisher: 'YKY',
      );
      expect(ranked.first.productId, '202');
      expect(ranked.first.publisher, 'Yapı Kredi Yayınları');
    });

    test('detay sayfasından JSON-LD Book şeması ve ek künye alanları okunur', () {
      const detailHtml = '''
      <html>
      <body>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Book",
          "name": "Saatleri Ayarlama Enstitüsü",
          "isbn": "9789754706048",
          "numberOfPages": "382",
          "inLanguage": "tr",
          "datePublished": "2017-05-10",
          "image": "https://img.kitapyurdu.com/v1/getImage/fn:999/wi:800/wh:true",
          "author": {"@type": "Person", "name": "Ahmet Hamdi Tanpınar"},
          "publisher": {"@type": "Organization", "name": "DERGAH YAYINLARI"}
        }
        </script>
        <div class="ky-pd-attributes__item">
          <span class="ky-pd-attributes__label">Baskı Sayısı:</span>
          <span class="ky-pd-attributes__value">28. Baskı</span>
        </div>
        <div class="ky-pd-attributes__categories">
          <div class="ky-pd-attributes__category">
            <span class="ky-pd-attributes__category-item">Kitap</span>
            <span class="ky-pd-attributes__category-item">Edebiyat</span>
            <span class="ky-pd-attributes__category-item">Roman (Yerli)</span>
          </div>
        </div>
      </body>
      </html>
      ''';
      final detail = parseKitapyurduDetailHtml(detailHtml);
      expect(detail, isNotNull);
      expect(detail!['source'], 'Kitapyurdu');
      expect(detail['title'], 'Saatleri Ayarlama Enstitüsü');
      expect(detail['author'], 'Ahmet Hamdi Tanpınar');
      expect(detail['publisher'], 'Dergah Yayınları');
      expect(detail['isbn'], '9789754706048');
      expect(detail['pageCount'], '382');
      expect(detail['publicationYear'], '2017');
      expect(detail['language'], 'Türkçe');
      expect(detail['edition'], '28. Baskı');
      expect(detail['category'], 'Edebiyat › Roman (Yerli)');
    });
  });

  group('Çoklu kaynak birleştirme ve kapak kaydı', () {
    test('mergeLookupMaps boş alanları ikincil kaynaktan tamamlar', () {
      final merged = mergeLookupMaps([
        {
          'source': 'Amazon',
          'title': 'Çalıkuşu',
          'author': 'Reşat Nuri Güntekin',
          'publisher': '',
          'pageCount': '544',
        },
        {
          'source': 'Kitapyurdu',
          'title': 'Çalıkuşu',
          'publisher': 'İnkılap Kitabevi',
          'category': 'Edebiyat › Roman',
        },
      ]);
      expect(merged, isNotNull);
      expect(merged!['publisher'], 'İnkılap Kitabevi');
      expect(merged['pageCount'], '544');
      expect(merged['category'], 'Edebiyat › Roman');
      expect(merged['source'], 'Amazon + Kitapyurdu');
    });

    test('withDownloadedCover Amazon ve Kitapyurdu kapaklarını kabul eder', () {
      final validJpeg = Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe0,
        0x00,
        0x10,
        0x4a,
        0x46,
        0x49,
        0x46,
      ]);
      final books = <Map<String, dynamic>>[
        {
          'id': 'b1',
          'title': 'İnce Memed',
          'author': 'Yaşar Kemal',
          'isbn': '',
          'quantity': 1,
          'loans': <Map<String, dynamic>>[],
        },
      ];
      final updated = withDownloadedCover(
        books,
        'b1',
        '',
        validJpeg,
        source: 'Kitapyurdu',
        allowTitleLookup: true,
      );
      expect(updated, isNotNull);
      expect(updated!.single['coverSource'], 'Kitapyurdu');
      expect(updated.single['coverBase64'], isNotEmpty);
    });
  });

  group('Gelişmiş envanter sayımı ve katalog entegrasyonu', () {
    test('özet istatistikler, azaltma ve tanınmayan barkodu kataloğa ekleme çalışır', () {
      final initialBooks = <Map<String, dynamic>>[
        {
          'id': 'k1',
          'title': 'Beyaz Diş',
          'author': 'Jack London',
          'isbn': '9789750719387',
          'shelf': 'A-1',
          'quantity': 2,
          'loans': <Map<String, dynamic>>[],
        },
      ];
      var session = startInventory(
        initialBooks,
        name: 'Güz Sayımı',
        operatorName: 'Mehmet Yılmaz',
        location: 'A-1',
        now: DateTime.utc(2026, 11, 12, 10),
      );
      session = recordInventoryScan(session, '9789750719387');
      session = recordInventoryScan(session, '9789753638029'); // tanınmayan ISBN
      session = recordInventoryScan(session, '9789753638029'); // 2. kez okutma

      final summaryBefore = summarizeInventory(session);
      expect(summaryBefore.expectedTotal, 2);
      expect(summaryBefore.countedTotal, 1);
      expect(summaryBefore.missingCopies, 1);
      expect(summaryBefore.unknownScans, 2);

      // Tanınmayan ISBN sayım içinden kataloğa kaydedildiğinde her iki okutma sayılan nüshaya dönüşür
      final newBook = <String, dynamic>{
        'id': 'k2',
        'title': 'Kürk Mantolu Madonna',
        'author': 'Sabahattin Ali',
        'isbn': '9789753638029',
        'shelf': 'A-1',
        'quantity': 2,
        'loans': <Map<String, dynamic>>[],
      };
      session = integrateRegisteredBookIntoInventory(session, newBook);

      final summaryAfter = summarizeInventory(session);
      expect(summaryAfter.totalTitles, 2);
      expect(summaryAfter.expectedTotal, 4);
      expect(summaryAfter.countedTotal, 3);
      expect(summaryAfter.unknownScans, 0);
      expect(summaryAfter.exactTitles, 1);

      // Azaltma ve JSON serileştirme uyumluluğu
      final decremented = decrementInventoryBook(session, 'k2');
      final roundTrip = InventorySession.fromJson(decremented.toJson());
      expect(summarizeInventory(roundTrip).countedTotal, 2);
    });

    test('tanınmayan demirbaş barkodu silinebilir veya fiziksel nüshayla sayıma bağlanabilir', () {
      var session = startInventory(
        const [],
        name: 'Boş Raf Sayımı',
        operatorName: 'Görevli',
        now: DateTime.utc(2026, 11, 12, 11),
      );
      session = recordInventoryScan(session, 'DMR-1001');
      session = recordInventoryScan(session, 'YANLIS-KOD');
      session = removeUnknownBarcodeEvents(session, 'yanlis-kod');
      expect(summarizeInventory(session).unknownScans, 1);

      final registered = <String, dynamic>{
        'id': 'k9',
        'title': 'Yaban',
        'author': 'Yakup Kadri Karaosmanoğlu',
        'isbn': '',
        'accessionCode': 'DMR-1001',
        'quantity': 1,
        'loans': <Map<String, dynamic>>[],
        'copies': [
          {
            'id': 'k9_c1',
            'bookID': 'k9',
            'accessionCode': 'DMR-1001',
            'condition': 'İyi',
            'status': 'Rafta',
            'note': '',
            'addedAt': '2026-11-12T11:05:00.000Z',
          },
        ],
      };
      session = integrateRegisteredBookIntoInventory(session, registered);
      final summary = summarizeInventory(session);
      expect(summary.unknownScans, 0);
      expect(summary.countedTotal, 1);
      expect(summary.exactTitles, 1);
    });
  });

  group('Excel (.xlsx) kitap listesi dışa ve içe aktarım', () {
    test('buildCatalogXlsx ve parseCatalogXlsx Türkçe karakterleri ve tüm alanları korur', () {
      final sourceBooks = <Map<String, dynamic>>[
        {
          'id': 'x1',
          'title': 'Çalıkuşu & İnce Memed Özel Seçki',
          'author': 'Reşat Nuri Güntekin',
          'publisher': 'İnkılap Kitabevi',
          'isbn': '9789750719387',
          'category': 'Türk Edebiyatı › Roman',
          'shelf': 'B-12',
          'accessionCode': 'DMR-204',
          'publicationYear': '2024',
          'edition': '15. Baskı',
          'pageCount': '544',
          'language': 'Türkçe',
          'readingLevel': 'Lise',
          'notes': 'Özel ciltli <baskı>',
          'quantity': 3,
          'loans': [
            {
              'id': 'l1',
              'name': 'Ayşe Yılmaz',
              'studentClass': '10/A',
              'due': '2026-12-01T00:00:00.000Z',
            },
          ],
        },
        {
          'id': 'x2',
          'title': 'Saatleri Ayarlama Enstitüsü',
          'author': 'Ahmet Hamdi Tanpınar',
          'publisher': 'Dergah Yayınları',
          'isbn': '9789754706048',
          'category': 'Edebiyat',
          'shelf': 'A-04',
          'quantity': 1,
          'loans': <Map<String, dynamic>>[],
        },
      ];

      final xlsxBytes = buildCatalogXlsx(sourceBooks);
      expect(xlsxBytes.length, greaterThan(1000));

      final imported = parseCatalogXlsx(xlsxBytes);
      expect(imported, hasLength(2));

      expect(imported[0]['title'], 'Çalıkuşu & İnce Memed Özel Seçki');
      expect(imported[0]['author'], 'Reşat Nuri Güntekin');
      expect(imported[0]['publisher'], 'İnkılap Kitabevi');
      expect(imported[0]['isbn'], '9789750719387');
      expect(imported[0]['category'], 'Türk Edebiyatı › Roman');
      expect(imported[0]['shelf'], 'B-12');
      expect(imported[0]['accessionCode'], 'DMR-204');
      expect(imported[0]['publicationYear'], '2024');
      expect(imported[0]['edition'], '15. Baskı');
      expect(imported[0]['pageCount'], '544');
      expect(imported[0]['language'], 'Türkçe');
      expect(imported[0]['notes'], 'Özel ciltli <baskı>');
      expect(imported[0]['quantity'], 3);

      expect(imported[1]['title'], 'Saatleri Ayarlama Enstitüsü');
      expect(imported[1]['isbn'], '9789754706048');
      expect(imported[1]['shelf'], 'A-04');
    });
  });

  group('Okul kütüphane otomasyonu ve iPhone paket (pack) görsel deposu', () {
    test('BookImageStore iphone_images_*.pack dilimlerinden görselleri doğrular ve okur', () async {
      final tempRoot = await Directory.systemTemp.createTemp('kitapbul_pack_test_');
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final imagesDir = Directory('${tempRoot.path}/book_images')..createSync();
      final store = BookImageStore(imagesDir);

      final jpegA = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x41, 0x42]);
      final pngB = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0x01, 0x02, 0x03]);
      final refA = BookImageStore.refFor(jpegA);
      final refB = BookImageStore.refFor(pngB);

      // İki görseli tek bir .pack dosyasına ardışık yaz
      final packBytes = BytesBuilder()
        ..add(jpegA)
        ..add(pngB);
      File('${tempRoot.path}/iphone_images_0.pack').writeAsBytesSync(packBytes.toBytes());
      File('${tempRoot.path}/iphone_images_index.json').writeAsStringSync(
        jsonEncode({
          'version': 1,
          'shards': ['iphone_images_0.pack'],
          'entries': {
            refA: [0, 0, jpegA.length],
            refB: [0, jpegA.length, pngB.length],
          },
        }),
      );
      store.invalidatePackCache();

      expect(store.hasFast(refA), isTrue);
      expect(store.hasValid(refA), isTrue);
      expect(store.bytesOf(refA), equals(jpegA));
      expect(await store.bytesOfAsync(refB), equals(pngB));
    });

    test('sırt etiketi yer numarası, Code128 barkod ve Türkçe UTF-8 QR matrisi üretilir', () {
      final book = <String, dynamic>{
        'id': 'b-100',
        'title': 'Devlet-i Aliyye',
        'author': 'Halil İnalcık',
        'category': 'Tarih',
        'shelf': 'N',
        'accessionCode': 'CAL-004057; CAL-004058',
        'isbn': '9786053601906',
      };
      expect(extractAccessionTokens(book), ['CAL-004057', 'CAL-004058']);

      final call = computeCallNumber(book);
      expect(call.top, 'TAR');
      expect(call.bottom, 'İNA');

      final bars = buildCode128Bars('CAL-004057');
      expect(bars, isNotEmpty);

      final qrRows = buildQrMatrixRows('KITAP:b-100|BAŞLIK:Şiir & Öykü Seçkisi');
      expect(qrRows.length, greaterThanOrEqualTo(21));
      expect(qrRows.first.length, qrRows.length);

      final expanded = buildLabelsPayloadItems(
        [book],
        template: LabelTemplateKind.qrCard,
        expandMultipleCopies: true,
      );
      expect(expanded, hasLength(2));
      expect(expanded[0]['accession'], 'CAL-004057');
      expect(expanded[1]['accession'], 'CAL-004058');
    });

    test('CAL- otomatik demirbaş kod atama ve mükerrer kitap birleştirme veri kaybetmez', () {
      final catalog = <Map<String, dynamic>>[
        {
          'id': 'm1',
          'title': 'Kürk Mantolu Madonna',
          'author': 'Sabahattin Ali',
          'isbn': '9789753638029',
          'accessionCode': 'CAL-004059; CAL-004060',
          'quantity': 2,
          'loans': <Map<String, dynamic>>[],
        },
        {
          'id': 'm2',
          'title': 'Kürk Mantolu Madonna',
          'author': 'Sabahattin Ali',
          'isbn': '978-975-363-802-9',
          'publisher': 'Yapı Kredi Yayınları',
          'accessionCode': '',
          'quantity': 2,
          'loans': <Map<String, dynamic>>[],
        },
      ];

      expect(findHighestAccessionNumber(catalog, prefix: 'CAL-'), 4060);
      final assigned = assignMissingAccessionCodes(catalog, prefix: 'CAL-', digits: 6);
      expect(assigned.assignedBooks, 1);
      expect(assigned.assignedCodes, 2);
      expect(assigned.firstCode, 'CAL-004061');
      expect(assigned.lastCode, 'CAL-004062');
      expect(assigned.updatedBooks[1]['accessionCode'], 'CAL-004061; CAL-004062');

      final groups = detectDuplicateBookGroups(assigned.updatedBooks);
      expect(groups, hasLength(1));

      final merged = mergeDuplicateGroup(assigned.updatedBooks, groups.first);
      final activeAfter = merged.where((b) => b['deletedAt'] == null).toList();
      expect(activeAfter, hasLength(1));
      expect(activeAfter.single['quantity'], 4);
      expect(activeAfter.single['publisher'], 'Yapı Kredi Yayınları');
      expect(
        extractAccessionTokens(activeAfter.single),
        containsAll(['CAL-004059', 'CAL-004060', 'CAL-004061', 'CAL-004062']),
      );
    });

    test('Cumhuriyet Kütüphanesi nöbet çizelgesi ve akıllı banko kod çözücü çalışır', () {
      final roster = SchoolDutyRoster(days: defaultCumhuriyetDutySchedule());
      expect(roster.totalAssigned, 12);
      expect(roster.forWeekday(1), hasLength(2));
      expect(roster.forWeekday(3), hasLength(3));

      final day = DateTime(2026, 11, 12);
      final slot = roster.forWeekday(4).first;
      expect(roster.isPresent(day, slot), isFalse);
      final toggled = roster.toggleAttendance(day, slot);
      expect(toggled.isPresent(day, slot), isTrue);

      final roundTrip = SchoolDutyRoster.fromJson(toggled.toJson());
      expect(roundTrip.totalAssigned, 12);
      expect(roundTrip.isPresent(day, slot), isTrue);

      final sampleBooks = <Map<String, dynamic>>[
        {
          'id': 'uuid-abc-1',
          'title': 'Çalıkuşu',
          'author': 'Reşat Nuri Güntekin',
          'isbn': '9789751026125',
          'accessionCode': 'CAL-001780; CAL-001781',
          'quantity': 2,
        },
      ];
      expect(findBookByDeskCode(sampleBooks, 'CAL-001781')?['id'], 'uuid-abc-1');
      expect(findBookByDeskCode(sampleBooks, 'KITAP:uuid-abc-1|DEM:CAL-001780')?['id'], 'uuid-abc-1');
      expect(findBookByDeskCode(sampleBooks, '978-975-102-612-5')?['id'], 'uuid-abc-1');
    });
  });

  group('CLIProxyAPI, 100+ ISBN Toplu Çekme, 4-Sayfa OCR, Raf Sayım ve Sesli Asistan', () {
    test('extractJsonFromModelText <think> ve markdown kod bloğunu temizler, güncel modelleri önceliklendirir', () {
      const raw = '''
<think>Önce sayfadaki künyeyi analiz edelim.</think>
İşte ayrıştırılan sonuç:
```json
{"title": "Tutunamayanlar", "author": "Oğuz Atay", "pageCount": "724"}
```
''';
      final parsed = extractJsonFromModelText(raw) as Map<String, dynamic>;
      expect(parsed['title'], 'Tutunamayanlar');
      expect(parsed['author'], 'Oğuz Atay');
      expect(parsed['pageCount'], '724');

      final models = prioritizeVisionModels([
        'gemini-2.0-flash',
        'gemini-2.5-pro',
        'claude-sonnet-4',
        'gpt-5.4',
        'deepseek-r1',
        'qwen3-coder-plus',
        'gemini-3.5-flash-lite',
        'gemini-3.8-flash',
      ]);
      expect(models, containsAll([
        'gemini-2.0-flash',
        'gemini-2.5-pro',
        'claude-sonnet-4',
        'gpt-5.4',
        'deepseek-r1',
        'qwen3-coder-plus',
      ]));
      expect(models.first, 'gemini-3.8-flash');

      // Kullanıcının seçtiği CLIProxy modeli üzerine yazılmamalıdır
      final restored = AiProxySettings.fromJson({
        'visionModel': 'gemini-2.5-flash',
        'assistantModel': 'claude-opus-4-6',
      });
      expect(restored.visionModel, 'gemini-2.5-flash');
      expect(restored.assistantModel, 'claude-opus-4-6');

      final pool = AiProxyClient.buildCombinedModelPool(
        serverModels: const ['custom-school-model', 'gpt-5.4'],
      );
      expect(pool, contains('custom-school-model'));
      expect(pool, contains('claude-sonnet-4-5-20250929'));
      expect(pool, contains('deepseek-r1'));
      expect(inferAiModelProvider('claude-opus-4-6'), 'Claude');
      expect(inferAiModelProvider('gpt-5.3-codex'), 'GPT / Codex');
      expect(inferAiModelProvider('deepseek-r1'), 'DeepSeek');
      expect(inferAiModelProvider('qwen3-coder-plus'), 'Qwen');
    });

    test('extractBulkIsbnQueue Amazon linklerini, ISBN-10 ve ISBN-13 kopyalarını birleştirir', () {
      const pasted = '''
https://www.amazon.com.tr/dp/9753638027
978-975-363-802-9
9789750719387
9789750719388
0-306-40615-2
''';
      final q = extractBulkIsbnQueue(pasted, defaultShelf: 'Dolap C');
      expect(q.validItems, hasLength(3));
      // 9753638027 (ISBN-10) ve 978-975-363-802-9 aynı kitaptır -> copies = 2!
      expect(q.validItems[0].isbn, '9789753638029');
      expect(q.validItems[0].copies, 2);
      expect(q.validItems[0].targetShelf, 'Dolap C');
      expect(q.validItems[1].isbn, '9789750719387');
      expect(q.validItems[2].isbn, '9780306406157');
      expect(q.invalidTokens, contains('9789750719388'));
    });

    test('extractFourPageLocalMetadata 4 sayfalık kapak, iç künye ve son sayfadan künye çıkarır', () {
      final docs = <BookPhotoSlot, OcrDocument>{
        BookPhotoSlot.frontCover: OcrDocument.fromPlatform({
          'text': 'SAATLERİ AYARLAMA ENSTİTÜSÜ\nAhmet Hamdi Tanpınar',
          'lines': [
            {'text': 'SAATLERİ AYARLAMA ENSTİTÜSÜ', 'height': 48},
            {'text': 'Ahmet Hamdi Tanpınar', 'height': 28},
          ],
        }),
        BookPhotoSlot.insideFront: OcrDocument.fromPlatform(
          'Dergah Yayınları\nISBN: 978-975-995-576-2\n28. Baskı: Mayıs 2021\nÇeviren: Örnek Editör',
        ),
        BookPhotoSlot.beforeBack: OcrDocument.fromPlatform(
          'Bölüm Sonu\n382',
        ),
        BookPhotoSlot.backCover: OcrDocument.fromPlatform(
          'Türk edebiyatının en büyük modern klasiklerinden biri olan bu roman iki uygarlık arasındaki insanı anlatır.',
        ),
      };

      final meta = extractFourPageLocalMetadata(docs);
      expect(meta['isbn'], '9789759955762');
      expect(meta['publicationYear'], '2021');
      expect(meta['pageCount'], '382');
      expect(meta['notes'], contains('modern klasiklerinden'));
    });

    test('parseShelfAiJson ve matchShelfSpinesAgainstCatalog doğru/yanlış dolabı ve eksikleri bulur', () {
      final catalog = <Map<String, dynamic>>[
        {
          'id': 'b-same',
          'title': 'Kürk Mantolu Madonna',
          'author': 'Sabahattin Ali',
          'isbn': '9789753638029',
          'shelf': 'Dolap C',
          'accessionCode': 'CAL-000101',
          'quantity': 1,
          'loans': <Map<String, dynamic>>[],
        },
        {
          'id': 'b-wrong',
          'title': 'Çalıkuşu',
          'author': 'Reşat Nuri Güntekin',
          'isbn': '9789751026125',
          'shelf': 'Dolap A',
          'accessionCode': 'CAL-000202',
          'quantity': 1,
          'loans': <Map<String, dynamic>>[],
        },
        {
          'id': 'b-missing',
          'title': 'Beyaz Gemi',
          'author': 'Cengiz Aytmatov',
          'isbn': '',
          'shelf': 'Dolap C',
          'accessionCode': 'CAL-000303',
          'quantity': 2,
          'loans': <Map<String, dynamic>>[],
        },
      ];

      final aiJson = {
        'total_physical_spines': 5,
        'unreadable_spines': 1,
        'books': [
          {
            'title': 'Kürk Mantolu Madonna',
            'author': 'Sabahattin Ali',
            'copies': 1,
            'box_2d': [100, 50, 900, 110],
          },
          {
            'title': 'Çalıkuşu',
            'author': 'Reşat Nuri Güntekin',
            'copies': 1,
            'box_2d': [110, 120, 900, 180],
          },
          {
            'title': 'Yaban',
            'author': 'Yakup Kadri Karaosmanoğlu',
            'copies': 2,
            'box_2d': [115, 190, 900, 260],
          },
        ],
      };

      final parsed = parseShelfAiJson(aiJson);
      expect(parsed.books, hasLength(3));
      expect(parsed.unreadableSpines, 1);

      final report = matchShelfSpinesAgainstCatalog(
        parsed.books,
        catalog,
        expectedShelf: 'Dolap C',
        unreadableExtraSpines: parsed.unreadableSpines,
      );
      expect(report.physicalTotal, 5);
      expect(report.sameShelfCount, 1);
      expect(report.wrongShelfCount, 1);
      expect(report.newBookCount, 1);
      expect(report.missingBooks, hasLength(1));
      expect(report.missingBooks.single.book['id'], 'b-missing');
      expect(report.missingBooks.single.expectedOnShelf, 2);
    });

    test('Sesli Asistan RAG bağlamı ve sesle kitap ekleme niyeti doğru çalışır', () {
      final draft = parseVoiceAddBookIntent(
        'Kitap ekle: Sinekli Bakkal, Halide Edib Adıvar, Dolap D, 2 adet',
      );
      expect(draft, isNotNull);
      expect(draft!.title, 'Sinekli Bakkal');
      expect(draft.author, 'Halide Edib Adıvar');
      expect(draft.shelf, 'Dolap D');
      expect(draft.quantity, 2);

      final books = <Map<String, dynamic>>[
        {
          'id': 'k1',
          'title': 'Kürk Mantolu Madonna',
          'author': 'Sabahattin Ali',
          'shelf': 'Dolap C',
          'accessionCode': 'CAL-000010',
          'quantity': 3,
          'loans': [
            {
              'id': 'l1',
              'name': 'Ali Veli',
              'studentClass': '9/A',
              'due': '2026-11-01',
            },
          ],
        },
      ];
      final roster = SchoolDutyRoster(days: defaultCumhuriyetDutySchedule());
      final students = const [
        Student(id: 's1', name: 'Ali Veli', className: '9/A', number: '42'),
      ];

      final shelfRag = buildLibraryRagContext(
        'Sabahattin Ali kitapları hangi dolapta?',
        books,
        students,
        roster,
        now: DateTime(2026, 11, 12), // Perşembe
      );
      expect(shelfRag.matchedBooks, hasLength(1));
      expect(shelfRag.offlineAnswer, contains('Dolap C'));

      final overdueRag = buildLibraryRagContext(
        'Geciken ödünç kitapları söyle',
        books,
        students,
        roster,
        now: DateTime(2026, 11, 12),
      );
      expect(overdueRag.offlineAnswer, contains('Ali Veli'));

      final dutyRag = buildLibraryRagContext(
        'Bugün nöbetçi öğrenciler kim?',
        books,
        students,
        roster,
        now: DateTime(2026, 11, 12),
      );
      expect(dutyRag.offlineAnswer, contains('Belinay Kibar'));
    });
  });

  group('Yeni Kütüphane ve Arayüz Özellikleri', () {
    BookActionCallbacks noopActions(List<Map<String, dynamic>> books) =>
        BookActionCallbacks(
          onEdit: (_) {},
          onLoan: (_) {},
          onReturn: (_) {},
          onExtend: (_) {},
          onMarkLost: (_) {},
          onResolveIdentity: (_) {},
          onCopies: (_) {},
          onReservations: (_) {},
          onHistory: (_) {},
          onWithdraw: (_) {},
          onTrash: (_) {},
          onOpenCover: (_, _) {},
          allBooks: books,
        );

    test('Künye metni, benzer kitaplar ve geciken hatırlatma mesajı doğru üretilir', () {
      final catalog = <Map<String, dynamic>>[
        {
          'id': 'b1',
          'title': 'Harry Potter ve Felsefe Taşı',
          'author': 'J.K. Rowling',
          'series': 'Harry Potter',
          'volume': 1,
          'category': 'Fantastik',
          'shelf': 'Dolap A',
          'isbn': '9789750802942',
          'accessionCode': 'CAL-000011',
          'tags': 'büyü; macera',
          'quantity': 1,
          'loans': [
            {
              'id': 'l1',
              'name': 'Zeynep Kaya',
              'studentClass': '7/B',
              'due': '2026-11-05T00:00:00.000',
            },
          ],
        },
        {
          'id': 'b2',
          'title': 'Harry Potter ve Sırlar Odası',
          'author': 'J.K. Rowling',
          'series': 'Harry Potter',
          'volume': 2,
          'category': 'Fantastik',
          'shelf': 'Dolap A',
          'quantity': 1,
          'loans': <Map<String, dynamic>>[],
        },
        {
          'id': 'b3',
          'title': 'Düşülen Kitap',
          'author': 'J.K. Rowling',
          'series': 'Harry Potter',
          'isWithdrawn': true,
          'quantity': 1,
          'loans': <Map<String, dynamic>>[],
        },
      ];

      final bib = formatBookBibliographyText(catalog[0]);
      expect(bib, contains('Harry Potter ve Felsefe Taşı'));
      expect(bib, contains('CAL-000011'));
      expect(bib, contains('Etiketler: büyü; macera'));

      final related = findRelatedBooks(catalog[0], catalog);
      expect(related.map((b) => b['id']), ['b2']);

      final now = DateTime(2026, 11, 10);
      final msg = buildOverdueReminderMessage(
        catalog[0],
        (catalog[0]['loans'] as List).first as Map<String, dynamic>,
        now: now,
      );
      expect(msg, contains('Zeynep Kaya (7/B)'));
      expect(msg, contains('5 gün geçmiştir'));

      final bulk = buildBulkOverdueSummaryText(catalog, now: now);
      expect(bulk, contains('Geciken Kütüphane Kitapları (1)'));
      expect(bulk, contains('Zeynep Kaya (7/B)'));
    });

    test('Keşif yardımcıları (Ne Okusam, Seriler, Yazarlar, Etiketler, Popüler) ve normalizeBook çalışır', () {
      final sampleBooks = <Map<String, dynamic>>[
        normalizeBook({
          'id': 'd1',
          'title': 'Küçük Prens',
          'author': 'Antoine de Saint-Exupery',
          'category': 'Roman',
          'shelf': 'Dolap A',
          'pageCount': '96',
          'rating': 5,
          'isFavorite': true,
          'tags': 'klasik, çocuk; felsefe',
          'quantity': 2,
          'history': [
            {'kind': 'lent', 'date': '2026-10-01'},
            {'kind': 'returned', 'date': '2026-10-10', 'readingCompleted': true},
          ],
        }),
        normalizeBook({
          'id': 'd2',
          'title': 'Sırlar Odası',
          'author': 'J.K. Rowling',
          'series': 'Potter',
          'volume': 2,
          'category': 'Fantastik',
          'shelf': 'Dolap A',
          'pageCount': '310',
          'tags': 'macera, klasik',
          'quantity': 1,
        }),
        normalizeBook({
          'id': 'd3',
          'title': 'Felsefe Taşı',
          'author': 'J.K. Rowling',
          'series': 'Potter',
          'volume': 1,
          'category': 'Fantastik',
          'shelf': 'Dolap B',
          'pageCount': '270',
          'quantity': 1,
        }),
      ];

      expect(sampleBooks.first['isFavorite'], isTrue);
      expect(sampleBooks.first['rating'], 5);

      final shortReads = recommendBooks(
        sampleBooks,
        mood: DiscoveryMood.shortRead,
      );
      expect(shortReads.map((b) => b['id']), ['d1']);

      final topRated = recommendBooks(
        sampleBooks,
        mood: DiscoveryMood.topRated,
      );
      expect(topRated.map((b) => b['id']), ['d1']);

      final hiddenGems = recommendBooks(
        sampleBooks,
        mood: DiscoveryMood.hiddenGem,
      );
      expect(hiddenGems.map((b) => b['id']), containsAll(['d2', 'd3']));

      final series = groupBookSeries(sampleBooks);
      expect(series.keys, ['Potter']);
      expect(series['Potter']!.map((b) => b['id']), ['d3', 'd2']);

      final authors = topAuthorsWithStats(sampleBooks);
      expect(authors.first.author, 'J.K. Rowling');
      expect(authors.first.bookCount, 2);

      final tags = extractTagCounts(sampleBooks);
      expect(tags.first.tag, 'klasik');
      expect(tags.first.count, 2);

      final popular = mostBorrowedBooks(sampleBooks);
      expect(popular, hasLength(1));
      expect(popular.first.borrowCount, 1);

      expect(topFieldSuggestions(sampleBooks, 'shelf'), ['Dolap A', 'Dolap B']);
      expect(studentRankTitle(0), 'Yeni Okur');
      expect(studentRankTitle(6), 'Kitap Kurdu');
      expect(studentRankTitle(20), 'Kütüphane Şampiyonu');
    });

    test('Öğrenci ödünç/gecikme özetleri studentId bazlı hesaplanır', () {
      final books = [
        {
          'id': 'k1',
          'title': 'Deneme',
          'quantity': 2,
          'loans': [
            {
              'id': 'l1',
              'studentId': 's-1',
              'name': 'Ali',
              'due': '2026-10-01T00:00:00.000',
            },
            {
              'id': 'l2',
              'studentId': 's-2',
              'name': 'Ayşe',
              'due': '2026-12-30T00:00:00.000',
            },
          ],
        },
      ];
      final counts = studentLoanCounts(books, now: DateTime(2026, 11, 10));
      expect(counts['S-1']?.loans, 1);
      expect(counts['S-1']?.overdue, 1);
      expect(counts['S-2']?.loans, 1);
      expect(counts['S-2']?.overdue, 0);
    });

    testWidgets('Raf görünümü, Keşfet sayfası, Öğrenci profili (dijital barkod) ve Şampiyonlar sorunsuz çizilir', (tester) async {
      final student = const Student(
        id: '11111111-1111-1111-1111-111111111111',
        name: 'Elif Yılmaz',
        number: '104',
        className: '6/A',
      );
      final books = <Map<String, dynamic>>[
        normalizeBook({
          'id': 'w1',
          'title': 'Simyacı',
          'author': 'Paulo Coelho',
          'shelf': 'A1',
          'series': 'Dünya Klasikleri',
          'volume': 1,
          'isFavorite': true,
          'rating': 5,
          'quantity': 1,
          'history': [
            {
              'kind': 'returned',
              'studentId': student.id,
              'person': student.name,
              'studentClass': student.className,
              'readingCompleted': true,
              'late': false,
              'date': '2026-11-01T10:00:00.000',
            },
          ],
        }),
      ];

      String? toggledId;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogBookshelfView(
              books: books,
              actions: noopActions(books),
              selectedIds: const {'w1'},
              selectionMode: true,
              onToggleSelect: (id) => toggledId = id,
            ),
          ),
        ),
      );
      expect(find.text('Simyacı'), findsWidgets);
      await tester.tap(find.text('Simyacı').first);
      expect(toggledId, 'w1');

      await tester.pumpWidget(
        MaterialApp(
          home: LibraryDiscoveryPage(
            books: books,
            actions: noopActions(books),
          ),
        ),
      );
      expect(find.text('Ne Okusam?'), findsOneWidget);
      expect(find.text('Simyacı'), findsWidgets);

      await tester.pumpWidget(
        MaterialApp(
          home: StudentProfilePage(student: student, books: books),
        ),
      );
      expect(find.text('Okuma Yolcusu'), findsOneWidget);
      expect(find.text('Dijital Öğrenci Barkod Kartı'), findsOneWidget);
      await tester.tap(find.text('Dijital Öğrenci Barkod Kartı'));
      await tester.pump();
      expect(find.textContaining('OGRID11111111'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: ReadingChampionsPage(books: books, students: [student]),
        ),
      );
      expect(find.text('Elif Yılmaz'), findsWidgets);
    });

    testWidgets('Akıllı Banko üye/öğretmen aramayı ve seçili okuyucunun aktif kitaplarını iade etmeyi gösterir', (tester) async {
      final teacher = const Member(
        id: 'm1',
        name: 'Mustafa Demir',
        number: 'T-12',
        kind: 'teacher',
      );
      final books = <Map<String, dynamic>>[
        normalizeBook({
          'id': 'k-desk',
          'title': 'Suç ve Ceza',
          'author': 'Dostoyevski',
          'quantity': 1,
          'loans': [
            {
              'id': 'loan-m1',
              'memberId': teacher.id,
              'name': teacher.name,
              'studentClass': 'Öğretmen',
              'due': '2026-12-01T00:00:00.000',
            },
          ],
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CirculationDeskView(
              books: books,
              students: const [],
              members: [teacher],
              loanSettings: const LoanSettings(),
              dutyRoster: SchoolDutyRoster(
                days: defaultCumhuriyetDutySchedule(),
              ),
              busy: false,
              actions: noopActions(books),
              onSaveBooks: (_) async {},
              onOpenDutyRoster: () {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'Mustafa');
      await tester.pump();
      expect(find.text('Mustafa Demir (Öğretmen)'), findsOneWidget);
      await tester.tap(find.text('Mustafa Demir (Öğretmen)'));
      await tester.pump();
      expect(find.text('Okuyucunun Elindeki Kitaplar (1)'), findsOneWidget);
      expect(find.text('Suç ve Ceza'), findsOneWidget);
    });
  });

  group('Atmosfer Stüdyosu, Dinamik Tema ve Okuma Köşesi', () {
    tearDown(() {
      appThemeNotifier.value = const AppThemeSettings();
    });

    test('AppThemeSettings JSON dönüşümü, paketler ve saat bazlı duvar kağıdı', () {
      const base = AppThemeSettings();
      final ottoman = base.applyPack(AtmospherePack.ottoman);
      expect(ottoman.preset, LibraryThemePreset.ottomanAmber);
      expect(ottoman.wallpaperAsset, 'assets/images/bg_osmanli_kutuphane.webp');
      expect(ottoman.clarity, WallpaperClarity.vivid);
      expect(ottoman.effectIntensity, EffectIntensity.rich);

      final roundTrip = AppThemeSettings.fromJson(ottoman.toJson());
      expect(roundTrip.atmospherePackId, AtmospherePack.ottoman.id);
      expect(roundTrip.preset, LibraryThemePreset.ottomanAmber);
      expect(roundTrip.tapRipplesEnabled, isTrue);
      expect(roundTrip.glassCardsEnabled, isTrue);

      final migrated = AppThemeSettings.fromJson({
        'preset': 'indigo',
        'themeMode': 'dark',
        'wallpaperAsset': 'assets/images/catalog_tools_bg.jpg',
      });
      expect(migrated.wallpaperAsset, kDynamicTimeWallpaper);

      expect(
        resolveWallpaperAsset(kDynamicTimeWallpaper, DateTime(2026, 11, 13, 8)),
        'assets/images/bg_sabah_ferah.webp',
      );
      expect(
        resolveWallpaperAsset(
          kDynamicTimeWallpaper,
          DateTime(2026, 11, 13, 14),
        ),
        'assets/images/bg_sonbahar_okuma.webp',
      );
      expect(
        resolveWallpaperAsset(
          kDynamicTimeWallpaper,
          DateTime(2026, 11, 13, 19),
        ),
        'assets/images/bg_osmanli_kutuphane.webp',
      );
      expect(
        resolveWallpaperAsset(
          kDynamicTimeWallpaper,
          DateTime(2026, 11, 13, 23),
        ),
        'assets/images/bg_yildizli_kutuphane.webp',
      );
    });

    testWidgets('LibraryAtmosphereStudioPage canlı önizleme ve paket seçimi', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryAtmosphereStudioPage(
            totalBooks: 2892,
            onResyncIPhoneSeed: () async {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Atmosfer Stüdyosu'), findsOneWidget);
      expect(find.text('CANLI SAHNE ÖNİZLEMESİ'), findsOneWidget);
      expect(find.text('Tek Dokunuş Atmosfer Paketleri'), findsOneWidget);

      await tester.tap(find.text('Osmanlı Kıraathanesi'));
      await tester.pump();

      expect(
        appThemeNotifier.value.wallpaperAsset,
        'assets/images/bg_osmanli_kutuphane.webp',
      );
      expect(appThemeNotifier.value.preset, LibraryThemePreset.ottomanAmber);
    });

    testWidgets('ReadingSanctuaryPage odak sayacı, öneri ve edebiyat sözü', (
      tester,
    ) async {
      final sampleBooks = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'b1',
          'title': 'Çalıkuşu',
          'author': 'Reşat Nuri Güntekin',
          'category': 'Roman',
          'shelf': 'B-12',
          'quantity': 1,
          'loans': <Map<String, dynamic>>[],
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingSanctuaryPage(books: sampleBooks),
        ),
      );
      await tester.pump();

      expect(find.text('Okuma Köşesi'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Çalıkuşu'), findsWidgets);

      await tester.tap(find.text('15 dk'));
      await tester.pump();
      expect(find.text('15:00'), findsOneWidget);

      await tester.tap(find.text('Başlat'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('14:58'), findsOneWidget);

      await tester.tap(find.text('Sıfırla'));
      await tester.pump();
      expect(find.text('15:00'), findsOneWidget);
    });

    testWidgets('IllustratedSquareMenuCard ve LibraryPulseDial taşmadan çizilir', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: IllustratedSquareMenuCard(
                          title: 'Okuma Köşesi',
                          subtitle: 'Odak & zamanlayıcı',
                          imageAsset: 'assets/images/card_okuma_modu.webp',
                          icon: Icons.nightlight_round,
                          accentColors: const [
                            Color(0xFF312E81),
                            Color(0xFF6366F1),
                          ],
                          badge: 'HUZUR',
                          onTap: () => tapped = true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const LibraryPulseDial(
                        ratio: 0.75,
                        centerValue: '%75',
                        centerCaption: 'rafta',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Okuma Köşesi'), findsOneWidget);
      expect(find.text('%75'), findsOneWidget);

      await tester.tap(find.text('Okuma Köşesi'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
