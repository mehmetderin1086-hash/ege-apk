import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jarvis_mobile/services/research_service.dart';
import 'package:jarvis_mobile/services/web_tools.dart';

http.Response _res(String body, {int status = 200, String type = 'text/html; charset=utf-8', Map<String, String>? headers}) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': type, ...?headers});

http.Response _json(Object body, {int status = 200}) =>
    _res(jsonEncode(body), status: status, type: 'application/json; charset=utf-8');

const _articleHtml = '''
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8">
  <title>Yedek Başlık</title>
  <meta property="og:title" content="Çağdaş Şehir Rehberi &amp; İpuçları">
  <meta property="og:description" content="İstanbul&#39;un gizli köşeleri">
  <meta name="description" content="Meta açıklama">
  <meta property="og:site_name" content="Gezi Blog">
  <meta property="og:image" content="/img/kapak.jpg">
  <meta property="og:video" content="https://cdn.example.com/video/tanitim.mp4">
  <meta property="og:video:type" content="video/mp4">
  <script>var secret = "SCRIPT_GIZLI"; document.write('<p>x</p>');</script>
  <style>.a { color: red; }</style>
  <script type="application/ld+json">{"@type":"VideoObject","contentUrl":"https:\\/\\/cdn.example.com\\/ld\\/klip.webm","embedUrl":"https://player.example.com/embed/1"}</script>
</head>
<body>
  <header><nav><a href="/menu">Menü</a></nav></header>
  <!-- yorum GIZLI_YORUM -->
  <article>
    <h1>Çağdaş Şehir Rehberi &amp; İpuçları</h1>
    <p>&Ccedil;ok g&uuml;zel bir g&uuml;n. &ouml;zel &#351;ehir &#x11F;ezintisi &amp; daha fazlası.</p>
    <h2>Gezilecek Yerler</h2>
    <ul><li>Galata Kulesi</li><li>Kız Kulesi</li></ul>
    <p>Detaylar için <a href="/rehber/detay?id=5">detay sayfası</a> ve <a href="../dosyalar/harita.pdf">PDF harita</a>.</p>
    <table><tr><th>Yer</th><th>Saat</th></tr><tr><td>Galata</td><td>09:00</td></tr></table>
    <video controls poster="/p.jpg"><source src="/media/klip.mp4" type="video/mp4"><source src="klip2.webm" type="video/webm"></video>
    <img src="resimler/foto.png" alt="foto">
    <img src="data:image/gif;base64,AAA" data-src="/lazy.webp">
  </article>
  <footer>İletişim: info@gezi.com.tr — Tel: +90 532 123 45 67 / 0212 555 66 77 logo@2x.png</footer>
</body>
</html>
''';

const _ddgHtml = '''
<html><body>
<div class="serp__results">
<div class="result results_links results_links_deep result--ad ">
  <div class="links_main links_deep result__body">
    <h2 class="result__title"><a rel="nofollow" class="result__a" href="https://duckduckgo.com/y.js?ad_domain=reklam.com&amp;ad_provider=bing&amp;u3=x">Reklam Başlığı</a></h2>
    <a class="result__snippet" href="https://duckduckgo.com/y.js?ad_domain=reklam.com">Reklam metni</a>
  </div>
</div>
<div class="result results_links results_links_deep web-result ">
  <div class="links_main links_deep result__body">
    <h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fflutter%3Fa%3D1%26b%3D%C3%A7&amp;rut=abc">Flutter &amp; Dart Rehberi</a></h2>
    <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fflutter">Flutter <b>öğrenmek</b> için kapsamlı rehber.</a>
  </div>
</div>
<div class="result results_links results_links_deep web-result ">
  <div class="links_main links_deep result__body">
    <h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdocs.flutter.dev%2F&amp;rut=def">Flutter Docs</a></h2>
    <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdocs.flutter.dev%2F">Resmi belgeler.</a>
  </div>
</div>
</div>
</body></html>
''';

String _ddgPage(List<(String, String, String)> results) {
  final sb = StringBuffer('<html><body>');
  for (final r in results) {
    sb.write('<div class="result results_links web-result"><div class="links_main result__body">'
        '<h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg='
        '${Uri.encodeComponent(r.$2)}&amp;rut=x">${r.$1}</a></h2>'
        '<a class="result__snippet" href="#">${r.$3}</a></div></div>');
  }
  sb.write('</body></html>');
  return sb.toString();
}

String _longArticle(String title, String topic) {
  final para = List.filled(6, '$topic hakkında ayrıntılı ve uzun bir paragraf metni burada yer alıyor; '
      'okunabilir içerik çıkarımı için yeterli uzunlukta olmalı.').join(' ');
  return '<html><head><title>$title</title></head><body><nav>menü</nav>'
      '<article><h1>$title</h1><p>$para</p><p>İkinci paragraf: $topic performansı.</p></article></body></html>';
}

void main() {
  group('URL helpers', () {
    test('normalizeUrl', () {
      expect(WebTools.normalizeUrl('example.com/x'), 'https://example.com/x');
      expect(WebTools.normalizeUrl('https://Example.com/a?b=1'), startsWith('https://example.com/a?b=1'));
      expect(WebTools.normalizeUrl('http://foo.org'), 'http://foo.org');
      expect(WebTools.normalizeUrl('www.google.com.tr'), 'https://www.google.com.tr');
      expect(WebTools.normalizeUrl('  <youtube.com/watch?v=abc>. '), 'https://youtube.com/watch?v=abc');
      expect(WebTools.normalizeUrl('merhaba dünya'), isNull);
      expect(WebTools.normalizeUrl('dosya.txt'), isNull);
      expect(WebTools.normalizeUrl('3.14'), isNull);
      expect(WebTools.normalizeUrl('mailto:a@b.com'), isNull);
      expect(WebTools.normalizeUrl(''), isNull);
    });

    test('extractUrls finds http(s) and bare domains', () {
      final urls = WebTools.extractUrls(
          'Şuna bak: youtube.com/watch?v=dQw4w9WgXcQ, ayrıca https://ornek.com.tr/haber/1. '
          'Mail: ali.veli@gmail.com ve (www.wikipedia.org) ile dosya.txt değil.');
      expect(urls, contains('https://youtube.com/watch?v=dQw4w9WgXcQ'));
      expect(urls, contains('https://ornek.com.tr/haber/1'));
      expect(urls, contains('https://www.wikipedia.org'));
      expect(urls.any((u) => u.contains('gmail')), isFalse);
      expect(urls.any((u) => u.contains('dosya.txt')), isFalse);
      expect(urls.length, 3);
    });

    test('looksLikeDirectMedia / kindForUrl', () {
      expect(WebTools.looksLikeDirectMedia('https://x.com/a/video.MP4?token=1'), isTrue);
      expect(WebTools.looksLikeDirectMedia('https://x.com/belge.pdf'), isTrue);
      expect(WebTools.looksLikeDirectMedia('https://x.com/sayfa.html'), isFalse);
      expect(WebTools.looksLikeDirectMedia('https://youtube.com/watch?v=1'), isFalse);
      expect(WebTools.kindForUrl('https://x.com/a.mkv'), 'video');
      expect(WebTools.kindForUrl('https://x.com/a.opus'), 'audio');
      expect(WebTools.kindForUrl('https://x.com/a.webp'), 'image');
      expect(WebTools.kindForUrl('https://x.com/a.apk'), 'file');
    });

    test('guessFileName', () {
      expect(
          WebTools.guessFileName('https://x.com/dl?id=1',
              contentDisposition: "attachment; filename*=UTF-8''%C3%87ok%20G%C3%BCzel%20Rapor.pdf"),
          'Çok Güzel Rapor.pdf');
      expect(WebTools.guessFileName('https://x.com/dl', contentDisposition: 'attachment; filename="yıllık:rapor?.xlsx"'),
          'yıllık_rapor_.xlsx');
      expect(WebTools.guessFileName('https://x.com/files/m%C3%BCzik.mp3'), 'müzik.mp3');
      expect(WebTools.guessFileName('https://x.com/indir/12345', contentType: 'video/mp4; codecs=avc1'), '12345.mp4');
      expect(WebTools.guessFileName('https://x.com/', contentType: 'application/pdf'), 'indirilen_dosya.pdf');
    });
  });

  group('parseHtml', () {
    final page = WebTools.parseHtml(_articleHtml, url: 'https://gezi.example.com/blog/yazi', statusCode: 200);

    test('title, description, site name, og image', () {
      expect(page.ok, isTrue);
      expect(page.title, 'Çağdaş Şehir Rehberi & İpuçları');
      expect(page.description, "İstanbul'un gizli köşeleri");
      expect(page.siteName, 'Gezi Blog');
      expect(page.ogImage, 'https://gezi.example.com/img/kapak.jpg');
    });

    test('article text, entities, stripping', () {
      expect(page.text, contains('Çok güzel bir gün. özel şehir ğezintisi & daha fazlası.'));
      expect(page.text, contains('• Galata Kulesi'));
      expect(page.text, contains('Yer | Saat'));
      expect(page.text, isNot(contains('SCRIPT_GIZLI')));
      expect(page.text, isNot(contains('GIZLI_YORUM')));
      expect(page.text, isNot(contains('color: red')));
      expect(page.text, isNot(contains('Menü')));
      expect(page.text, isNot(contains('İletişim')));
      expect(page.headings, containsAll(['Çağdaş Şehir Rehberi & İpuçları', 'Gezilecek Yerler']));
    });

    test('markdown', () {
      expect(page.markdown, startsWith('# Çağdaş Şehir Rehberi & İpuçları'));
      expect(page.markdown, contains("> İstanbul'un gizli köşeleri"));
      expect(page.markdown, contains('## Gezilecek Yerler'));
      expect(page.markdown, contains('- Kız Kulesi'));
      expect(page.markdown, contains('| Yer | Saat |'));
      expect(page.markdown, contains('| --- | --- |'));
    });

    test('links and images resolved', () {
      final urls = page.links.map((l) => l.url).toList();
      expect(urls, contains('https://gezi.example.com/rehber/detay?id=5'));
      expect(urls, contains('https://gezi.example.com/dosyalar/harita.pdf'));
      expect(page.links.firstWhere((l) => l.url.endsWith('detay?id=5')).text, 'detay sayfası');
      expect(page.images, contains('https://gezi.example.com/blog/resimler/foto.png'));
      expect(page.images, contains('https://gezi.example.com/lazy.webp'));
    });

    test('media candidates', () {
      final byUrl = {for (final m in page.media) m.url: m};
      expect(byUrl['https://cdn.example.com/video/tanitim.mp4']?.source, 'og');
      expect(byUrl['https://cdn.example.com/video/tanitim.mp4']?.mimeHint, 'video/mp4');
      expect(byUrl['https://gezi.example.com/media/klip.mp4']?.source, 'source-tag');
      expect(byUrl['https://gezi.example.com/blog/klip2.webm']?.kind, 'video');
      expect(byUrl['https://cdn.example.com/ld/klip.webm']?.source, 'json-ld');
      expect(byUrl.containsKey('https://player.example.com/embed/1'), isFalse);
      final pdf = byUrl['https://gezi.example.com/dosyalar/harita.pdf'];
      expect(pdf?.source, 'link');
      expect(pdf?.kind, 'file');
      expect(page.media.map((m) => m.url).toSet().length, page.media.length);
    });

    test('emails and phones', () {
      expect(page.emails, ['info@gezi.com.tr']);
      expect(page.phones.length, 2);
      expect(page.phones.any((p) => p.replaceAll(RegExp(r'\D'), '').endsWith('5321234567')), isTrue);
      expect(page.phones.any((p) => p.replaceAll(RegExp(r'\D'), '').endsWith('2125556677')), isTrue);
    });
  });

  group('fetchPage', () {
    test('decodes UTF-8 bytes and follows final url', () async {
      final client = MockClient((req) async => _res(_longArticle('Türkçe Sayfa', 'Şırnak')));
      final p = await WebTools.fetchPage('ornek.com/sayfa', client: client);
      expect(p.ok, isTrue);
      expect(p.title, 'Türkçe Sayfa');
      expect(p.text, contains('Şırnak hakkında'));
      expect(p.finalUrl, startsWith('https://ornek.com/sayfa'));
    });

    test('direct file -> media candidate, no body parsing', () async {
      final client = MockClient((req) async => http.Response.bytes([0, 1, 2], 200,
          headers: {'content-type': 'video/mp4', 'content-disposition': 'attachment; filename="klip.mp4"'}));
      final p = await WebTools.fetchPage('https://cdn.x.com/get?id=9', client: client);
      expect(p.ok, isTrue);
      expect(p.title, 'klip.mp4');
      expect(p.media.single.kind, 'video');
      expect(p.media.single.source, 'direct');
    });

    test('captcha page is a failed fetch', () async {
      final client = MockClient((req) async =>
          _res('<html><head><title>Just a moment...</title></head><body><div class="cf-turnstile"></div></body></html>'));
      final p = await WebTools.fetchPage('https://korunan.com', client: client);
      expect(p.ok, isFalse);
      expect(p.error, contains('CAPTCHA'));
    });

    test('network error -> failure, no throw', () async {
      final client = MockClient((req) async => throw http.ClientException('bağlantı yok'));
      final p = await WebTools.fetchPage('https://x.com', client: client);
      expect(p.ok, isFalse);
    });

    test('findMedia on direct url needs no network', () async {
      final client = MockClient((req) async => fail('should not be called'));
      final m = await WebTools.findMedia('x.com/a/b/muzik.m4a', client: client);
      expect(m.single.kind, 'audio');
      expect(m.single.source, 'direct');
    });

    test('probeUrl falls back to ranged GET', () async {
      final client = MockClient((req) async {
        if (req.method == 'HEAD') return http.Response('', 405);
        expect(req.headers['Range'], 'bytes=0-0');
        return http.Response.bytes([0], 206,
            headers: {'content-type': 'application/pdf', 'content-range': 'bytes 0-0/123456'});
      });
      final r = await WebTools.probeUrl('https://x.com/dosya/rapor', client: client);
      expect(r.ok, isTrue);
      expect(r.length, 123456);
      expect(r.fileName, 'rapor.pdf');
    });
  });

  group('search', () {
    test('parses DuckDuckGo HTML, decodes uddg, skips ads', () async {
      Uri? asked;
      final client = MockClient((req) async {
        asked = req.url;
        return _res(_ddgHtml);
      });
      final results = await WebTools.search('flutter öğren', client: client);
      expect(asked?.host, 'html.duckduckgo.com');
      expect(asked?.queryParameters['q'], 'flutter öğren');
      expect(asked?.queryParameters['kl'], 'tr-tr');
      expect(results.length, 2);
      expect(results[0].title, 'Flutter & Dart Rehberi');
      expect(results[0].url, 'https://example.com/flutter?a=1&b=ç');
      expect(results[0].snippet, 'Flutter öğrenmek için kapsamlı rehber.');
      expect(results[0].source, 'duckduckgo');
      expect(results[1].url, 'https://docs.flutter.dev/');
      expect(results.any((r) => r.title.contains('Reklam')), isFalse);
    });

    test('falls back to Wikipedia when DDG has no results', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'html.duckduckgo.com') {
          return _res('<html><body><div class="anomaly-modal">Lütfen doğrulayın</div></body></html>');
        }
        if (req.url.host == 'tr.wikipedia.org' && req.url.path == '/w/api.php') {
          expect(req.url.queryParameters['list'], 'search');
          return _json({
            'query': {
              'search': [
                {'title': 'Mustafa Kemal Atatürk', 'snippet': '<span class="searchmatch">Atatürk</span> Türk asker'},
                {'title': 'Anıtkabir', 'snippet': 'Ankara&#039;da anıt mezar'},
              ]
            }
          });
        }
        return _res('', status: 404);
      });
      final results = await WebTools.search('atatürk', client: client);
      expect(results.length, 2);
      expect(results.first.source, 'wikipedia');
      expect(results.first.title, 'Mustafa Kemal Atatürk');
      expect(results.first.url, startsWith('https://tr.wikipedia.org/wiki/Mustafa_Kemal_Atat'));
      expect(results.first.snippet, 'Atatürk Türk asker');
      expect(results[1].snippet, "Ankara'da anıt mezar");
    });
  });

  group('APIs', () {
    test('wikipediaSummary resolves title on 404', () async {
      final client = MockClient((req) async {
        final p = req.url.path;
        if (p.startsWith('/api/rest_v1/page/summary/')) {
          final title = Uri.decodeComponent(p.split('/').last);
          if (title == 'Flutter_(yazılım)') {
            return _json({
              'type': 'standard',
              'title': 'Flutter (yazılım)',
              'extract': 'Flutter, Google tarafından geliştirilen açık kaynaklı bir UI yazılım geliştirme kitidir.',
              'content_urls': {
                'desktop': {'page': 'https://tr.wikipedia.org/wiki/Flutter_(yaz%C4%B1l%C4%B1m)'}
              },
            });
          }
          return _json({'type': 'https://mediawiki.org/wiki/HyperSwitch/errors/not_found'}, status: 404);
        }
        if (p == '/w/api.php' && req.url.queryParameters['action'] == 'opensearch') {
          return _json([
            'flutter',
            ['Flutter (yazılım)'],
            [''],
            ['https://tr.wikipedia.org/wiki/Flutter_(yaz%C4%B1l%C4%B1m)']
          ]);
        }
        return _res('', status: 404);
      });
      final s = await WebTools.wikipediaSummary('flutter', client: client);
      expect(s, isNotNull);
      expect(s!.title, 'Flutter (yazılım)');
      expect(s.extract, contains('Google'));
      expect(s.url, contains('wikipedia.org/wiki/Flutter'));
    });

    test('weather with geocoding + forecast', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'geocoding-api.open-meteo.com') {
          expect(req.url.queryParameters['name'], 'Kadıköy');
          expect(req.url.queryParameters['language'], 'tr');
          return _json({
            'results': [
              {'name': 'Kadıköy', 'latitude': 40.99, 'longitude': 29.03, 'admin1': 'İstanbul', 'country': 'Türkiye'}
            ]
          });
        }
        if (req.url.host == 'api.open-meteo.com') {
          expect(req.url.queryParameters['latitude'], '40.9900');
          expect(req.url.queryParameters['forecast_days'], '7');
          return _json({
            'current': {
              'temperature_2m': 18.4,
              'relative_humidity_2m': 60,
              'apparent_temperature': 17.2,
              'weather_code': 2,
              'wind_speed_10m': 12.3,
            },
            'daily': {
              'time': ['2026-11-16', '2026-11-17', '2026-11-18'],
              'weather_code': [2, 61, 0],
              'temperature_2m_max': [20.1, 21.0, 19.0],
              'temperature_2m_min': [12.0, 14.2, 11.0],
              'precipitation_sum': [0.0, 4.5, 0.0],
              'precipitation_probability_max': [10, 30, null],
            },
          });
        }
        return _res('', status: 404);
      });
      final w = await WebTools.weather(city: "Kadıköy'de", client: client);
      expect(w, isNotNull);
      expect(w!.place, 'Kadıköy, İstanbul');
      expect(w.description, 'parçalı bulutlu');
      expect(w.humidity, 60);
      expect(w.days.length, 3);
      expect(w.days[1].description, 'hafif yağmurlu');
      expect(w.days[2].precipitationProb, 0);
      final s = w.toTurkishSummary();
      expect(s, contains('Kadıköy, İstanbul'));
      expect(s, contains('18°C'));
      expect(s, contains('hissedilen 17°C'));
      expect(s, contains('Yarın: 14°/21°'));
      expect(s, contains('%30 yağış ihtimali'));
    });

    test('weather with coordinates uses "Konumunuz"', () async {
      final client = MockClient((req) async => _json({
            'current': {
              'temperature_2m': 5,
              'relative_humidity_2m': 80,
              'apparent_temperature': 2,
              'weather_code': 73,
              'wind_speed_10m': 20
            },
          }));
      final w = await WebTools.weather(lat: 39.9, lon: 32.8, client: client);
      expect(w?.place, 'Konumunuz');
      expect(w?.description, 'kar yağışlı');
    });

    test('convertCurrency with Frankfurter JSON', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'api.frankfurter.app');
        expect(req.url.queryParameters, {'amount': '100', 'from': 'USD', 'to': 'TRY'});
        return _json({
          'amount': 100.0,
          'base': 'USD',
          'date': '2026-11-13',
          'rates': {'TRY': 3215.4}
        });
      });
      final q = await WebTools.convertCurrency(amount: 100, from: 'usd', client: client);
      expect(q, isNotNull);
      expect(q!.converted, closeTo(3215.4, 1e-9));
      expect(q.rate, closeTo(32.154, 1e-9));
      expect(q.date, DateTime(2026, 11, 13));
      expect(q.toTurkishSummary(), '100,00 USD = 3215,40 TRY');
    });

    test('convertCurrency failure -> null', () async {
      final client = MockClient((req) async => _json({'message': 'not found'}, status: 404));
      expect(await WebTools.convertCurrency(from: 'SAR', client: client), isNull);
    });

    test('currencyCodeFromTurkish', () {
      expect(WebTools.currencyCodeFromTurkish('dolar'), 'USD');
      expect(WebTools.currencyCodeFromTurkish('Doların'), 'USD');
      expect(WebTools.currencyCodeFromTurkish("euro'yu"), 'EUR');
      expect(WebTools.currencyCodeFromTurkish('avro'), 'EUR');
      expect(WebTools.currencyCodeFromTurkish('sterlin'), 'GBP');
      expect(WebTools.currencyCodeFromTurkish('pound'), 'GBP');
      expect(WebTools.currencyCodeFromTurkish('yen'), 'JPY');
      expect(WebTools.currencyCodeFromTurkish('frank'), 'CHF');
      expect(WebTools.currencyCodeFromTurkish('ruble'), 'RUB');
      expect(WebTools.currencyCodeFromTurkish('riyal'), 'SAR');
      expect(WebTools.currencyCodeFromTurkish('yuan'), 'CNY');
      expect(WebTools.currencyCodeFromTurkish('TL'), 'TRY');
      expect(WebTools.currencyCodeFromTurkish('lira'), 'TRY');
      expect(WebTools.currencyCodeFromTurkish('bitcoin'), isNull);
      expect(WebTools.currencyCodeFromTurkish('elma'), isNull);
    });

    test('news parses RSS with CDATA and " - Source" split', () async {
      const rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Google Haberler</title>
<item>
  <title><![CDATA[Merkez Bankası faiz kararını açıkladı - Anadolu Ajansı]]></title>
  <link>https://news.google.com/rss/articles/abc?oc=5</link>
  <pubDate>Mon, 16 Nov 2026 07:30:00 GMT</pubDate>
</item>
<item>
  <title>Fenerbahçe &amp; Galatasaray derbisi - NTV</title>
  <link>https://news.google.com/rss/articles/def</link>
  <pubDate>Sun, 15 Nov 2026 21:00:00 +0300</pubDate>
  <source url="https://www.ntv.com.tr">NTV</source>
</item>
<item>
  <title>Bozuk tarihli haber</title>
  <link>https://news.google.com/rss/articles/ghi</link>
  <pubDate>dün akşam</pubDate>
</item>
</channel></rss>''';
      Uri? asked;
      final client = MockClient((req) async {
        asked = req.url;
        return _res(rss, type: 'application/rss+xml; charset=utf-8');
      });
      final items = await WebTools.news(topic: 'ekonomi', client: client);
      expect(asked.toString(), contains('/rss/search?q=ekonomi'));
      expect(items.length, 3);
      expect(items[0].title, 'Merkez Bankası faiz kararını açıkladı');
      expect(items[0].source, 'Anadolu Ajansı');
      expect(items[0].published, DateTime.utc(2026, 11, 16, 7, 30));
      expect(items[1].title, 'Fenerbahçe & Galatasaray derbisi');
      expect(items[1].source, 'NTV');
      expect(items[1].published, DateTime.utc(2026, 11, 15, 18, 0));
      expect(items[2].published, isNull);
      expect(items[2].source, '');
    });
  });

  group('DeepResearchService', () {
    test('parseQueries handles fenced JSON, objects and bullets', () {
      expect(DeepResearchService.parseQueries('```json\n["a sorgu", "b query"]\n```', fallback: 'x'),
          ['a sorgu', 'b query']);
      expect(DeepResearchService.parseQueries('İşte: {"queries": ["bir", "iki", "üç"]}', fallback: 'x', max: 2),
          ['bir', 'iki']);
      expect(DeepResearchService.parseQueries('Sorgular:\n- flutter nedir\n* "flutter vs react native"\n2) dart dili',
          fallback: 'x'), ['flutter nedir', 'flutter vs react native', 'dart dili']);
      expect(DeepResearchService.parseQueries('1. birinci\n2. ikinci\n2. ikinci', fallback: 'x'), ['birinci', 'ikinci']);
      expect(DeepResearchService.parseQueries('', fallback: 'soru'), ['soru']);
    });

    test('normalizeUrlKey strips utm, fragments, trailing slash, www', () {
      expect(DeepResearchService.normalizeUrlKey('https://www.a.com/x/?utm_source=t&id=2#frag'),
          DeepResearchService.normalizeUrlKey('http://a.com/x?id=2'));
    });

    test('run end-to-end with fake llm and mock web', () async {
      final prompts = <String>[];
      Future<String> llm(String prompt) async {
        prompts.add(prompt);
        if (prompt.contains('arama sorgusu')) {
          return '["flutter nedir", "flutter vs react native", "flutter performance"]';
        }
        return '# Flutter Araştırması\n\n## Kısa Özet (TL;DR)\nFlutter çapraz platform bir UI kitidir [1].\n\n'
            '## Ana Bulgular\n- Performans iyidir [2].\n\n## Kaynaklar\n[1] uydurma kaynak';
      }

      final fetched = <String>[];
      final client = MockClient((req) async {
        final u = req.url;
        if (u.host == 'html.duckduckgo.com') {
          final q = u.queryParameters['q'] ?? '';
          if (q == 'flutter nedir') {
            return _res(_ddgPage([
              ('Flutter Nedir', 'https://blog.example.com/flutter-nedir?utm_source=x', 'Giriş'),
              ('Flutter Nedir Kopya', 'https://blog.example.com/flutter-nedir/', 'Aynı sayfa'),
              ('Flutter Wiki', 'https://tr.wikipedia.org/wiki/Flutter_(yaz%C4%B1l%C4%B1m)', 'wiki'),
            ]));
          }
          if (q == 'flutter vs react native') {
            return _res(_ddgPage([
              ('Karşılaştırma', 'https://compare.example.org/flutter-vs-rn', 'kıyas'),
              ('Blog 2', 'https://blog.example.com/ikinci', 'iki'),
              ('Blog 3', 'https://blog.example.com/ucuncu', 'üç'),
            ]));
          }
          return _res(_ddgPage([
            ('Performance', 'https://perf.example.net/flutter', 'perf'),
            ('Bozuk', 'https://broken.example.net/x', 'hata'),
          ]));
        }
        if (u.path.startsWith('/api/rest_v1/page/summary/')) {
          return _json({
            'type': 'standard',
            'title': 'Flutter (yazılım)',
            'extract': 'Flutter, Google tarafından geliştirilen açık kaynaklı bir kullanıcı arayüzü yazılım '
                'geliştirme kitidir ve çok sayıda platform için uygulama geliştirmeye olanak tanır.',
            'content_urls': {
              'desktop': {'page': 'https://tr.wikipedia.org/wiki/Flutter_(yaz%C4%B1l%C4%B1m)'}
            },
          });
        }
        if (u.host == 'tr.wikipedia.org' && u.path.startsWith('/wiki/')) {
          fetched.add(u.toString());
          return _res(_longArticle('Flutter (yazılım)', 'Flutter'));
        }
        if (u.host == 'broken.example.net') return _res('hata', status: 500);
        if (u.host.endsWith('example.com') || u.host.endsWith('example.org') || u.host.endsWith('example.net')) {
          fetched.add(u.toString());
          return _res(_longArticle('Sayfa ${u.path}', 'Flutter ${u.host}'));
        }
        return _res('', status: 404);
      });

      final progress = <ResearchProgress>[];
      final report = await DeepResearchService.run(
        question: 'Flutter nedir?',
        llm: llm,
        client: client,
        maxSources: 6,
        onProgress: progress.add,
      );

      expect(report.ok, isTrue, reason: report.error);
      expect(report.queries, ['flutter nedir', 'flutter vs react native', 'flutter performance']);
      expect(report.sources, isNotEmpty);
      expect(report.sources.first.url, contains('wikipedia.org'));
      expect(report.sources.first.excerpt, isNotEmpty);
      final urls = report.sources.map((s) => s.url).toList();
      // Deduped (utm / trailing slash variant + wiki duplicate removed).
      expect(urls.where((u) => u.contains('flutter-nedir')).length, 1);
      expect(urls.where((u) => u.contains('wikipedia')).length, 1);
      // Max 2 per domain while other domains are available.
      expect(urls.where((u) => u.contains('blog.example.com')).length, lessThanOrEqualTo(2));
      expect(urls.any((u) => u.contains('broken')), isFalse);
      expect(report.markdown, contains('## Kaynaklar'));
      expect('## Kaynaklar'.allMatches(report.markdown).length, 1);
      expect(report.markdown, isNot(contains('uydurma kaynak')));
      expect(report.markdown, contains('[1] Flutter (yazılım) — https://tr.wikipedia.org/wiki/'));
      expect(report.markdown, contains('https://compare.example.org/flutter-vs-rn'));
      expect(progress.last.stage, 'done');
      expect(progress.last.fraction, 1.0);
      expect(progress.map((p) => p.stage).toSet(), containsAll(['plan', 'search', 'read', 'write', 'done']));
      expect(prompts.length, 2);
      expect(prompts.last, contains('[1] Flutter (yazılım)'));
      expect(prompts.last, contains('YALNIZCA'));
    });

    test('run marks unverified answer when nothing can be read', () async {
      Future<String> llm(String prompt) async =>
          prompt.contains('arama sorgusu') ? 'geçersiz çıktı' : '# Yanıt\n\nGenel bilgi.';
      final client = MockClient((req) async => throw http.ClientException('çevrimdışı'));
      final report = await DeepResearchService.run(question: 'Kuantum bilgisayar nedir?', llm: llm, client: client);
      expect(report.ok, isTrue);
      expect(report.sources, isEmpty);
      expect(report.markdown, contains('kaynak doğrulanamadı'));
      expect(report.markdown, contains('## Kaynaklar'));
    });

    test('run honours cancellation', () async {
      var calls = 0;
      final report = await DeepResearchService.run(
        question: 'test',
        llm: (p) async => '["a"]',
        client: MockClient((req) async => _res('')),
        isCancelled: () => ++calls > 1,
      );
      expect(report.ok, isFalse);
      expect(report.error, 'İptal edildi');
    });
  });
}
