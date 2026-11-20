import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/asistan_models.dart';

enum ScrapedMediaType { image, video, audio, document, other }

class ScrapedMediaItem {
  final String id;
  final String url;
  final String title;
  final ScrapedMediaType type;
  final String extension;
  final String mimeType;
  final String? thumbnailUrl;
  final int? sizeBytes;
  final String sourceLabel;
  bool selected;
  bool downloaded;
  String? savedPath;

  ScrapedMediaItem({
    required this.id,
    required this.url,
    required this.title,
    required this.type,
    required this.extension,
    required this.mimeType,
    this.thumbnailUrl,
    this.sizeBytes,
    this.sourceLabel = 'Web',
    this.selected = true,
    this.downloaded = false,
    this.savedPath,
  });

  String get typeBadge => switch (type) {
    ScrapedMediaType.image => '🖼️ Resim',
    ScrapedMediaType.video => '🎬 Video',
    ScrapedMediaType.audio => '🎵 Ses',
    ScrapedMediaType.document => '📄 Belge',
    ScrapedMediaType.other => '📦 Dosya',
  };

  String get subFolder => switch (type) {
    ScrapedMediaType.image => 'Asistan/Resimler',
    ScrapedMediaType.video => 'Asistan/Videolar',
    ScrapedMediaType.audio => 'Asistan/Sesler',
    ScrapedMediaType.document => 'Asistan/Belgeler',
    ScrapedMediaType.other => 'Asistan/Dosyalar',
  };
}

class WebScrapeResult {
  final String queryOrUrl;
  final bool isUrlScrape;
  final String pageTitle;
  final String cleanText;
  final List<ScrapedMediaItem> items;
  final DateTime timestamp;

  WebScrapeResult({
    required this.queryOrUrl,
    required this.isUrlScrape,
    required this.pageTitle,
    required this.cleanText,
    required this.items,
    required this.timestamp,
  });

  int countByType(ScrapedMediaType t) => items.where((e) => e.type == t).length;
}

typedef NativeDownloadSaver = Future<Map<String, dynamic>> Function({
  required String fileName,
  required String subFolder,
  required String mimeType,
  required Uint8List bytes,
});

class ScraperDownloaderService {
  static const Map<String, String> _browserHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 AsistanAI/5.0',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  static bool looksLikeUrl(String input) {
    final t = input.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return true;
    if (RegExp(r'^[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}(/.*)?$').hasMatch(t) &&
        !t.contains(' ')) {
      return true;
    }
    return false;
  }

  static Future<WebScrapeResult> scrapeOrSearch(
    String rawInput, {
    String mediaFilter = 'all', // all, image, audio, video, document
  }) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return WebScrapeResult(
        queryOrUrl: '',
        isUrlScrape: false,
        pageTitle: 'Arama Boş',
        cleanText: '',
        items: [],
        timestamp: DateTime.now(),
      );
    }

    if (looksLikeUrl(trimmed)) {
      final normalizedUrl = trimmed.startsWith('http')
          ? trimmed
          : 'https://$trimmed';
      return _scrapeWebUrl(normalizedUrl);
    } else {
      return _searchCommonsAndArchiveMedia(trimmed, mediaFilter: mediaFilter);
    }
  }

  // ─── 1. DIRECT URL / WEB PAGE SCRAPER ───────────────────────────────────

  static Future<WebScrapeResult> _scrapeWebUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return WebScrapeResult(
        queryOrUrl: url,
        isUrlScrape: true,
        pageTitle: 'Geçersiz URL',
        cleanText: 'Girilen bağlantı geçerli bir web adresi değil: $url',
        items: [],
        timestamp: DateTime.now(),
      );
    }

    // Check if the URL itself looks like a direct file link
    final directInfo = _classifyUrl(url);
    try {
      final resp = await http
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 18));
      final contentType = (resp.headers['content-type'] ?? '').toLowerCase();

      if (!contentType.contains('html') &&
          !contentType.contains('xml') &&
          !contentType.contains('text/plain') &&
          (directInfo != null ||
              contentType.startsWith('image/') ||
              contentType.startsWith('video/') ||
              contentType.startsWith('audio/') ||
              contentType.contains('pdf') ||
              contentType.contains('octet-stream') ||
              contentType.contains('zip'))) {
        final info = directInfo ?? _classifyByContentType(url, contentType);
        final item = ScrapedMediaItem(
          id: 'direct_${DateTime.now().millisecondsSinceEpoch}',
          url: url,
          title: _extractNameFromUrl(url),
          type: info.type,
          extension: info.ext,
          mimeType: info.mime,
          thumbnailUrl: info.type == ScrapedMediaType.image ? url : null,
          sizeBytes: resp.bodyBytes.length,
          sourceLabel: uri.host,
        );
        return WebScrapeResult(
          queryOrUrl: url,
          isUrlScrape: true,
          pageTitle: 'Doğrudan Dosya Bağlantısı (${uri.host})',
          cleanText:
              'Bu bağlantı doğrudan indirilebilir bir ${item.typeBadge} dosyasıdır.\nBoyut: ${(resp.bodyBytes.length / 1024).toStringAsFixed(1)} KB',
          items: [item],
          timestamp: DateTime.now(),
        );
      }

      // Parse HTML page
      final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final titleMatch = RegExp(
        r'<title[^>]*>([\s\S]*?)</title>',
        caseSensitive: false,
      ).firstMatch(html);
      final pageTitle = _decodeHtmlEntities(
        titleMatch?.group(1)?.trim() ?? uri.host,
      );

      final cleanText = _extractCleanArticleText(html, pageTitle, url);
      final items = _extractAllMediaFromHtml(html, uri);

      return WebScrapeResult(
        queryOrUrl: url,
        isUrlScrape: true,
        pageTitle: pageTitle,
        cleanText: cleanText,
        items: items,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      // Even if GET failed or timed out, if it's a direct media link let user try downloading it
      if (directInfo != null) {
        return WebScrapeResult(
          queryOrUrl: url,
          isUrlScrape: true,
          pageTitle: _extractNameFromUrl(url),
          cleanText: 'Doğrudan medya bağlantısı hazır: $url',
          items: [
            ScrapedMediaItem(
              id: 'direct_fallback_${DateTime.now().millisecondsSinceEpoch}',
              url: url,
              title: _extractNameFromUrl(url),
              type: directInfo.type,
              extension: directInfo.ext,
              mimeType: directInfo.mime,
              thumbnailUrl: directInfo.type == ScrapedMediaType.image
                  ? url
                  : null,
              sourceLabel: uri.host,
            ),
          ],
          timestamp: DateTime.now(),
        );
      }
      return WebScrapeResult(
        queryOrUrl: url,
        isUrlScrape: true,
        pageTitle: 'Sayfa Kazıma Hatası',
        cleanText: 'Bağlantı okunurken hata oluştu: $e',
        items: [],
        timestamp: DateTime.now(),
      );
    }
  }

  static List<ScrapedMediaItem> _extractAllMediaFromHtml(
    String html,
    Uri baseUri,
  ) {
    final seenUrls = <String>{};
    final items = <ScrapedMediaItem>[];

    void addCandidate(
      String rawUrl, {
      String? customTitle,
      ScrapedMediaType? forcedType,
    }) {
      var u = _decodeHtmlEntities(rawUrl.trim());
      if (u.isEmpty ||
          u.startsWith('data:') ||
          u.startsWith('javascript:') ||
          u.startsWith('mailto:') ||
          u.startsWith('#')) {
        return;
      }
      if (u.startsWith('//')) {
        u = '${baseUri.scheme}:$u';
      }
      final resolved = baseUri.resolve(u).toString();
      if (seenUrls.contains(resolved)) return;

      // Filter obvious tiny icons/trackers
      final lower = resolved.toLowerCase();
      if (lower.contains('1x1') ||
          lower.contains('pixel.') ||
          lower.contains('spacer.gif') ||
          lower.endsWith('.svg')) {
        return;
      }

      final info = _classifyUrl(resolved, forcedType: forcedType);
      if (info == null) return;

      seenUrls.add(resolved);
      final name = (customTitle != null && customTitle.trim().isNotEmpty)
          ? customTitle.trim()
          : _extractNameFromUrl(resolved);

      items.add(
        ScrapedMediaItem(
          id: 'item_${items.length}_${DateTime.now().microsecondsSinceEpoch}',
          url: resolved,
          title: name,
          type: info.type,
          extension: info.ext,
          mimeType: info.mime,
          thumbnailUrl: info.type == ScrapedMediaType.image ? resolved : null,
          sourceLabel: baseUri.host,
        ),
      );
    }

    // 1. Meta og:image, og:video, og:audio, twitter:image
    final metaRegex = RegExp(
      r'''<meta[^>]+(?:property|name)=["'](og:image|og:video|og:audio|twitter:image)["'][^>]+content=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final m in metaRegex.allMatches(html)) {
      final prop = (m.group(1) ?? '').toLowerCase();
      final content = m.group(2) ?? '';
      if (prop.contains('video')) {
        addCandidate(content, forcedType: ScrapedMediaType.video);
      } else if (prop.contains('audio')) {
        addCandidate(content, forcedType: ScrapedMediaType.audio);
      } else {
        addCandidate(content, forcedType: ScrapedMediaType.image);
      }
    }

    // 2. <img ... src / data-src / data-original / srcset>
    final imgTagRegex = RegExp(r'<img\b[^>]*>', caseSensitive: false);
    for (final m in imgTagRegex.allMatches(html)) {
      final tag = m.group(0) ?? '';
      final altMatch = RegExp(
        r'''alt=["']([^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(tag);
      final alt = altMatch?.group(1);

      for (final attr in [
        'data-original',
        'data-src',
        'data-lazy-src',
        'src',
      ]) {
        final attrMatch = RegExp(
          '$attr=["\']([^"\']+)["\']',
          caseSensitive: false,
        ).firstMatch(tag);
        if (attrMatch != null) {
          addCandidate(
            attrMatch.group(1)!,
            customTitle: alt,
            forcedType: ScrapedMediaType.image,
          );
        }
      }

      final srcsetMatch = RegExp(
        r'''srcset=["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(tag);
      if (srcsetMatch != null) {
        final parts = srcsetMatch.group(1)!.split(',');
        if (parts.isNotEmpty) {
          final bestUrl = parts.last.trim().split(RegExp(r'\s+')).first;
          addCandidate(
            bestUrl,
            customTitle: alt,
            forcedType: ScrapedMediaType.image,
          );
        }
      }
    }

    // 3. <video>, <audio>, <source>
    final mediaTagRegex = RegExp(
      r'<(video|audio|source)\b[^>]*src=["\x27]([^"\x27]+)["\x27][^>]*>',
      caseSensitive: false,
    );
    for (final m in mediaTagRegex.allMatches(html)) {
      final tagType = (m.group(1) ?? '').toLowerCase();
      final src = m.group(2) ?? '';
      if (tagType == 'video') {
        addCandidate(src, forcedType: ScrapedMediaType.video);
      } else if (tagType == 'audio') {
        addCandidate(src, forcedType: ScrapedMediaType.audio);
      } else {
        addCandidate(src);
      }
    }

    // 4. <a href="..."> pointing to media or office/archive documents
    final aTagRegex = RegExp(
      r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );
    for (final m in aTagRegex.allMatches(html)) {
      final href = m.group(1) ?? '';
      final innerText = _stripHtmlTags(m.group(2) ?? '').trim();
      if (_classifyUrl(href) != null) {
        addCandidate(href, customTitle: innerText);
      }
    }

    // 5. Raw direct media links embedded in scripts/JSON (mp4, mp3, wav, pdf, jpg, png, webp)
    final rawMediaRegex = RegExp(
      r'''https?://[^\s"'<>\\]+\.(?:mp4|webm|mp3|wav|m4a|ogg|pdf|docx|xlsx|pptx|zip|jpg|jpeg|png|webp)''',
      caseSensitive: false,
    );
    for (final m in rawMediaRegex.allMatches(html)) {
      addCandidate(m.group(0)!);
      if (items.length >= 120) break;
    }

    return items;
  }

  // ─── 2. TOPIC-BASED BULK MEDIA SEARCH (COMMONS + INTERNET ARCHIVE + WIKI) ─

  static Future<WebScrapeResult> _searchCommonsAndArchiveMedia(
    String topic, {
    String mediaFilter = 'all',
  }) async {
    final items = <ScrapedMediaItem>[];
    final textBuffer = StringBuffer();
    final seenUrls = <String>{};

    // Determine Wikimedia Commons search queries based on mediaFilter
    final searchQueries = <String>[];
    switch (mediaFilter) {
      case 'image':
        searchQueries.add('$topic filetype:bitmap');
        break;
      case 'audio':
        searchQueries.add('$topic filetype:audio');
        break;
      case 'video':
        searchQueries.add('$topic filetype:video');
        break;
      case 'document':
        searchQueries.add('$topic filetype:office');
        break;
      default:
        searchQueries.add(topic);
        searchQueries.add('$topic filetype:audio');
        searchQueries.add('$topic filetype:video');
        searchQueries.add('$topic filetype:office');
        break;
    }

    // Run Wikimedia Commons searches + Wikipedia summary + Internet Archive search in parallel
    final futures = <Future<void>>[];

    for (final q in searchQueries) {
      futures.add(() async {
        try {
          final uri = Uri.parse(
            'https://commons.wikimedia.org/w/api.php'
            '?action=query&generator=search'
            '&gsrsearch=${Uri.encodeComponent(q)}'
            '&gsrnamespace=6&gsrlimit=24'
            '&prop=imageinfo&iiprop=url|mime|size'
            '&iiurlwidth=480&format=json',
          );
          final res = await http
              .get(uri, headers: _browserHeaders)
              .timeout(const Duration(seconds: 12));
          if (res.statusCode == 200) {
            final data = jsonDecode(utf8.decode(res.bodyBytes));
            final pages = data['query']?['pages'] as Map<String, dynamic>?;
            if (pages != null) {
              for (final entry in pages.values) {
                final map = entry as Map<String, dynamic>;
                final rawTitle = (map['title']?.toString() ?? '').replaceFirst(
                  RegExp(r'^File:', caseSensitive: false),
                  '',
                );
                final iiList = map['imageinfo'] as List<dynamic>?;
                if (iiList == null || iiList.isEmpty) continue;
                final ii = iiList.first as Map<String, dynamic>;
                final fileUrl = ii['url']?.toString() ?? '';
                if (fileUrl.isEmpty || seenUrls.contains(fileUrl)) continue;

                final mime = (ii['mime']?.toString() ?? '').toLowerCase();
                final thumbUrl = ii['thumburl']?.toString();
                final size = (ii['size'] as num?)?.toInt();

                final info = _classifyByContentType(fileUrl, mime);
                if (mediaFilter == 'image' &&
                    info.type != ScrapedMediaType.image) {
                  continue;
                }
                if (mediaFilter == 'audio' &&
                    info.type != ScrapedMediaType.audio) {
                  continue;
                }
                if (mediaFilter == 'video' &&
                    info.type != ScrapedMediaType.video) {
                  continue;
                }
                if (mediaFilter == 'document' &&
                    info.type != ScrapedMediaType.document) {
                  continue;
                }

                seenUrls.add(fileUrl);
                items.add(
                  ScrapedMediaItem(
                    id: 'commons_${items.length}_${DateTime.now().microsecondsSinceEpoch}',
                    url: fileUrl,
                    title: rawTitle.isEmpty
                        ? _extractNameFromUrl(fileUrl)
                        : rawTitle,
                    type: info.type,
                    extension: info.ext,
                    mimeType: info.mime,
                    thumbnailUrl: info.type == ScrapedMediaType.image
                        ? (thumbUrl ?? fileUrl)
                        : thumbUrl,
                    sizeBytes: size,
                    sourceLabel: 'Wikimedia Commons',
                  ),
                );
              }
            }
          }
        } catch (_) {}
      }());
    }

    // Also search Internet Archive for audio/video/pdf items matching topic
    futures.add(() async {
      try {
        final mediaClause = switch (mediaFilter) {
          'audio' => ' AND mediatype:(audio)',
          'video' => ' AND mediatype:(movies)',
          'document' => ' AND mediatype:(texts)',
          'image' => ' AND mediatype:(image)',
          _ => ' AND mediatype:(audio OR movies OR texts OR image)',
        };
        final iaQuery = '($topic)$mediaClause';
        final iaUri = Uri.parse(
          'https://archive.org/advancedsearch.php'
          '?q=${Uri.encodeComponent(iaQuery)}'
          '&fl[]=identifier&fl[]=title&fl[]=mediatype'
          '&rows=10&page=1&output=json',
        );
        final res = await http
            .get(iaUri, headers: _browserHeaders)
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final docs = data['response']?['docs'] as List<dynamic>? ?? const [];
          for (final d in docs.take(6)) {
            final map = d as Map<String, dynamic>;
            final id = map['identifier']?.toString() ?? '';
            final title = map['title']?.toString() ?? id;
            final mType = map['mediatype']?.toString() ?? '';
            if (id.isEmpty) continue;

            // Fetch metadata files for this archive item
            try {
              final metaRes = await http
                  .get(
                    Uri.parse('https://archive.org/metadata/$id/files'),
                    headers: _browserHeaders,
                  )
                  .timeout(const Duration(seconds: 7));
              if (metaRes.statusCode == 200) {
                final metaJson = jsonDecode(utf8.decode(metaRes.bodyBytes));
                final files = metaJson['result'] as List<dynamic>? ?? const [];
                for (final f in files) {
                  final fMap = f as Map<String, dynamic>;
                  final fName = fMap['name']?.toString() ?? '';
                  if (fName.isEmpty ||
                      fName.endsWith('.xml') ||
                      fName.endsWith('.sqlite') ||
                      fName.endsWith('.torrent') ||
                      fName.contains('_thumb')) {
                    continue;
                  }
                  final directUrl =
                      'https://archive.org/download/$id/${Uri.encodeComponent(fName)}';
                  final info = _classifyUrl(directUrl);
                  if (info == null) continue;
                  if (mediaFilter == 'audio' &&
                      info.type != ScrapedMediaType.audio) {
                    continue;
                  }
                  if (mediaFilter == 'video' &&
                      info.type != ScrapedMediaType.video) {
                    continue;
                  }
                  if (mediaFilter == 'document' &&
                      info.type != ScrapedMediaType.document) {
                    continue;
                  }
                  if (mediaFilter == 'image' &&
                      info.type != ScrapedMediaType.image) {
                    continue;
                  }
                  if (seenUrls.contains(directUrl)) continue;
                  seenUrls.add(directUrl);
                  final fSize = int.tryParse(fMap['size']?.toString() ?? '');
                  items.add(
                    ScrapedMediaItem(
                      id: 'ia_${items.length}_${DateTime.now().microsecondsSinceEpoch}',
                      url: directUrl,
                      title: '$title - $fName',
                      type: info.type,
                      extension: info.ext,
                      mimeType: info.mime,
                      thumbnailUrl: info.type == ScrapedMediaType.image
                          ? directUrl
                          : 'https://archive.org/services/img/$id',
                      sizeBytes: fSize,
                      sourceLabel: 'Internet Archive ($mType)',
                    ),
                  );
                  break; // Take the primary downloadable file per Archive item
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }());

    // Fetch Wikipedia TR + EN overview text so the user also gets a full text summary
    futures.add(() async {
      for (final lang in ['tr', 'en']) {
        try {
          final searchUri = Uri.parse(
            'https://$lang.wikipedia.org/w/api.php?action=query&list=search'
            '&srsearch=${Uri.encodeComponent(topic)}&utf8=&format=json&srlimit=3',
          );
          final res = await http
              .get(searchUri, headers: _browserHeaders)
              .timeout(const Duration(seconds: 8));
          if (res.statusCode == 200) {
            final data = jsonDecode(utf8.decode(res.bodyBytes));
            final list = data['query']?['search'] as List<dynamic>? ?? [];
            for (final item in list.take(2)) {
              final title = item['title']?.toString() ?? '';
              if (title.isEmpty) continue;
              final sumUri = Uri.parse(
                'https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
              );
              final sumRes = await http
                  .get(sumUri, headers: _browserHeaders)
                  .timeout(const Duration(seconds: 7));
              if (sumRes.statusCode == 200) {
                final sumData = jsonDecode(utf8.decode(sumRes.bodyBytes));
                final extract = sumData['extract']?.toString() ?? '';
                final origImg =
                    sumData['originalimage']?['source']?.toString() ?? '';
                if (extract.isNotEmpty) {
                  textBuffer.writeln(
                    '## $title (${lang.toUpperCase()} Wikipedia)',
                  );
                  textBuffer.writeln(extract);
                  textBuffer.writeln();
                }
                if (origImg.isNotEmpty && !seenUrls.contains(origImg)) {
                  final info = _classifyUrl(
                    origImg,
                    forcedType: ScrapedMediaType.image,
                  );
                  if (info != null) {
                    seenUrls.add(origImg);
                    items.insert(
                      0,
                      ScrapedMediaItem(
                        id: 'wiki_${DateTime.now().microsecondsSinceEpoch}',
                        url: origImg,
                        title: '$title.${info.ext}',
                        type: ScrapedMediaType.image,
                        extension: info.ext,
                        mimeType: info.mime,
                        thumbnailUrl: origImg,
                        sourceLabel: 'Wikipedia ${lang.toUpperCase()}',
                      ),
                    );
                  }
                }
              }
            }
          }
        } catch (_) {}
      }
    }());

    await Future.wait(futures);

    final summaryText = textBuffer.toString().trim().isEmpty
        ? '"$topic" konusu için toplam ${items.length} adet doğrudan indirilebilir medya dosyası (Resim, Ses, Video, Belge) bulundu. İstediğiniz dosyaları seçip tek tuşla veya toplu (Bulk) olarak telefonunuzun İndirilenler/Asistan klasörüne kaydedebilirsiniz.'
        : textBuffer.toString().trim();

    return WebScrapeResult(
      queryOrUrl: topic,
      isUrlScrape: false,
      pageTitle:
          '"$topic" Medya & Dosya Arama Sonuçları (${items.length} Dosya)',
      cleanText: summaryText,
      items: items,
      timestamp: DateTime.now(),
    );
  }

  // ─── 3. DOWNLOAD SINGLE OR BULK ITEM TO PHONE ───────────────────────────

  static Future<GeneratedArtifact?> downloadMediaItem({
    required ScrapedMediaItem item,
    required NativeDownloadSaver nativeSaver,
  }) async {
    try {
      final uri = Uri.parse(item.url);
      final resp = await http
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 35));
      if (resp.statusCode < 200 ||
          resp.statusCode >= 400 ||
          resp.bodyBytes.isEmpty) {
        return null;
      }

      final bytes = resp.bodyBytes;
      final safeBase = item.title
          .replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,5}$'), '')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(RegExp(r'\s+'), '_')
          .trim();
      final stem = safeBase.isEmpty
          ? 'Asistan_Indirilen_${DateTime.now().millisecondsSinceEpoch % 10000}'
          : (safeBase.length > 48 ? safeBase.substring(0, 48) : safeBase);
      final ext = item.extension.isEmpty ? 'bin' : item.extension;
      final fileName =
          '${stem}_${DateTime.now().millisecondsSinceEpoch % 10000}.$ext';

      // Save to local app directory first
      Directory localDir;
      try {
        final base = await getApplicationDocumentsDirectory();
        localDir = Directory('${base.path}/asistan_atolye');
      } catch (_) {
        localDir = Directory('${Directory.systemTemp.path}/asistan_atolye');
      }
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }
      final localFile = File('${localDir.path}/$fileName');
      await localFile.writeAsBytes(bytes, flush: true);

      // Save to Android public Downloads folder (/storage/emulated/0/Download/Asistan/...)
      final saveRes = await nativeSaver(
        fileName: fileName,
        subFolder: item.subFolder,
        mimeType: item.mimeType,
        bytes: bytes,
      );

      final finalPath = saveRes['path']?.toString().isNotEmpty == true
          ? saveRes['path'].toString()
          : localFile.path;
      final displayPath =
          saveRes['displayPath']?.toString() ??
          'İndirilenler/${item.subFolder}/$fileName';

      item.downloaded = true;
      item.savedPath = finalPath;

      return GeneratedArtifact(
        id: 'dl_${DateTime.now().microsecondsSinceEpoch}',
        title: item.title,
        filePath: finalPath,
        format: ext,
        mimeType: item.mimeType,
        contentPreview:
            '${item.typeBadge} • $displayPath • Kaynak: ${item.sourceLabel}',
        createdAt: DateTime.now(),
        sizeBytes: bytes.length,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────

  static ({ScrapedMediaType type, String ext, String mime})? _classifyUrl(
    String url, {
    ScrapedMediaType? forcedType,
  }) {
    final clean = url.split('?').first.split('#').first.toLowerCase();
    final dotIdx = clean.lastIndexOf('.');
    final ext = (dotIdx != -1 && dotIdx < clean.length - 1)
        ? clean.substring(dotIdx + 1)
        : '';

    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return (type: ScrapedMediaType.image, ext: 'jpg', mime: 'image/jpeg');
      case 'png':
        return (type: ScrapedMediaType.image, ext: 'png', mime: 'image/png');
      case 'webp':
        return (type: ScrapedMediaType.image, ext: 'webp', mime: 'image/webp');
      case 'gif':
        return (type: ScrapedMediaType.image, ext: 'gif', mime: 'image/gif');
      case 'bmp':
        return (type: ScrapedMediaType.image, ext: 'bmp', mime: 'image/bmp');
      case 'mp4':
      case 'm4v':
        return (type: ScrapedMediaType.video, ext: 'mp4', mime: 'video/mp4');
      case 'webm':
        return (type: ScrapedMediaType.video, ext: 'webm', mime: 'video/webm');
      case 'mov':
        return (
          type: ScrapedMediaType.video,
          ext: 'mov',
          mime: 'video/quicktime',
        );
      case 'mkv':
        return (
          type: ScrapedMediaType.video,
          ext: 'mkv',
          mime: 'video/x-matroska',
        );
      case 'ogv':
        return (type: ScrapedMediaType.video, ext: 'ogv', mime: 'video/ogg');
      case 'mp3':
        return (type: ScrapedMediaType.audio, ext: 'mp3', mime: 'audio/mpeg');
      case 'wav':
        return (type: ScrapedMediaType.audio, ext: 'wav', mime: 'audio/wav');
      case 'm4a':
      case 'aac':
        return (type: ScrapedMediaType.audio, ext: 'm4a', mime: 'audio/mp4');
      case 'ogg':
      case 'oga':
      case 'opus':
        return (type: ScrapedMediaType.audio, ext: 'ogg', mime: 'audio/ogg');
      case 'flac':
        return (type: ScrapedMediaType.audio, ext: 'flac', mime: 'audio/flac');
      case 'pdf':
        return (
          type: ScrapedMediaType.document,
          ext: 'pdf',
          mime: 'application/pdf',
        );
      case 'docx':
        return (
          type: ScrapedMediaType.document,
          ext: 'docx',
          mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      case 'doc':
        return (
          type: ScrapedMediaType.document,
          ext: 'doc',
          mime: 'application/msword',
        );
      case 'xlsx':
        return (
          type: ScrapedMediaType.document,
          ext: 'xlsx',
          mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      case 'xls':
        return (
          type: ScrapedMediaType.document,
          ext: 'xls',
          mime: 'application/vnd.ms-excel',
        );
      case 'pptx':
        return (
          type: ScrapedMediaType.document,
          ext: 'pptx',
          mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        );
      case 'csv':
        return (type: ScrapedMediaType.document, ext: 'csv', mime: 'text/csv');
      case 'txt':
      case 'md':
        return (type: ScrapedMediaType.document, ext: ext, mime: 'text/plain');
      case 'epub':
        return (
          type: ScrapedMediaType.document,
          ext: 'epub',
          mime: 'application/epub+zip',
        );
      case 'zip':
      case 'rar':
      case '7z':
      case 'apk':
        return (
          type: ScrapedMediaType.other,
          ext: ext,
          mime: 'application/octet-stream',
        );
    }

    if (forcedType != null) {
      return switch (forcedType) {
        ScrapedMediaType.image => (
          type: ScrapedMediaType.image,
          ext: 'jpg',
          mime: 'image/jpeg',
        ),
        ScrapedMediaType.video => (
          type: ScrapedMediaType.video,
          ext: 'mp4',
          mime: 'video/mp4',
        ),
        ScrapedMediaType.audio => (
          type: ScrapedMediaType.audio,
          ext: 'mp3',
          mime: 'audio/mpeg',
        ),
        ScrapedMediaType.document => (
          type: ScrapedMediaType.document,
          ext: 'pdf',
          mime: 'application/pdf',
        ),
        ScrapedMediaType.other => (
          type: ScrapedMediaType.other,
          ext: 'bin',
          mime: 'application/octet-stream',
        ),
      };
    }

    return null;
  }

  static ({ScrapedMediaType type, String ext, String mime})
  _classifyByContentType(String url, String contentType) {
    final fromUrl = _classifyUrl(url);
    if (fromUrl != null) return fromUrl;
    final ct = contentType.toLowerCase();
    if (ct.contains('image/png')) {
      return (type: ScrapedMediaType.image, ext: 'png', mime: 'image/png');
    }
    if (ct.contains('image/webp')) {
      return (type: ScrapedMediaType.image, ext: 'webp', mime: 'image/webp');
    }
    if (ct.contains('image/gif')) {
      return (type: ScrapedMediaType.image, ext: 'gif', mime: 'image/gif');
    }
    if (ct.startsWith('image/')) {
      return (type: ScrapedMediaType.image, ext: 'jpg', mime: 'image/jpeg');
    }
    if (ct.contains('video/webm')) {
      return (type: ScrapedMediaType.video, ext: 'webm', mime: 'video/webm');
    }
    if (ct.startsWith('video/')) {
      return (type: ScrapedMediaType.video, ext: 'mp4', mime: 'video/mp4');
    }
    if (ct.contains('audio/wav')) {
      return (type: ScrapedMediaType.audio, ext: 'wav', mime: 'audio/wav');
    }
    if (ct.contains('audio/ogg') || ct.contains('application/ogg')) {
      return (type: ScrapedMediaType.audio, ext: 'ogg', mime: 'audio/ogg');
    }
    if (ct.startsWith('audio/')) {
      return (type: ScrapedMediaType.audio, ext: 'mp3', mime: 'audio/mpeg');
    }
    if (ct.contains('pdf')) {
      return (
        type: ScrapedMediaType.document,
        ext: 'pdf',
        mime: 'application/pdf',
      );
    }
    return (
      type: ScrapedMediaType.other,
      ext: 'bin',
      mime: 'application/octet-stream',
    );
  }

  static String _extractNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      if (segs.isNotEmpty) {
        return Uri.decodeComponent(segs.last);
      }
      return uri.host;
    } catch (_) {
      return 'Medya_Dosyasi';
    }
  }

  static String _extractCleanArticleText(
    String html,
    String title,
    String sourceUrl,
  ) {
    var cleaned = html
        .replaceAll(
          RegExp(
            r'<(script|style|noscript|svg|header|footer|nav)[^>]*>[\s\S]*?</\1>',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');

    final paragraphs = <String>[];
    final pRegex = RegExp(
      r'<(h1|h2|h3|p|li|blockquote)\b[^>]*>([\s\S]*?)</\1>',
      caseSensitive: false,
    );
    for (final m in pRegex.allMatches(cleaned)) {
      final tag = (m.group(1) ?? 'p').toLowerCase();
      final text = _decodeHtmlEntities(_stripHtmlTags(m.group(2) ?? ''))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.length < 18) continue;
      if (tag.startsWith('h')) {
        paragraphs.add('\n## $text');
      } else if (tag == 'li') {
        paragraphs.add('• $text');
      } else {
        paragraphs.add(text);
      }
      if (paragraphs.length >= 90) break;
    }

    if (paragraphs.isEmpty) {
      final plain = _decodeHtmlEntities(_stripHtmlTags(cleaned))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return '# $title\nKaynak: $sourceUrl\n\n${plain.length > 4000 ? plain.substring(0, 4000) : plain}';
    }

    return '# $title\nKaynak: $sourceUrl\n\n${paragraphs.join('\n\n')}';
  }

  static String _stripHtmlTags(String input) {
    return input.replaceAll(RegExp(r'<[^>]*>'), ' ');
  }

  static String _decodeHtmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }
}
