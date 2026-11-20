import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'catalog_search.dart' show foldTurkish;
import 'isbn.dart';

enum BookLookupSource {
  auto('Otomatik (Tüm Kaynaklar)'),
  amazon('Amazon (ISBN)'),
  kitapyurdu('Kitapyurdu'),
  googleBooks('Google Books'),
  openLibrary('Open Library');

  const BookLookupSource(this.label);
  final String label;
}

class KitapyurduCandidate {
  const KitapyurduCandidate({
    required this.productId,
    required this.title,
    required this.author,
    required this.publisher,
    required this.detailUrl,
    this.coverUrl = '',
  });

  final String productId;
  final String title;
  final String author;
  final String publisher;
  final String detailUrl;
  final String coverUrl;
}

const _namedHtmlEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'rlm': '',
  'lrm': '',
  'zwj': '',
  'zwnj': '',
  'ndash': '–',
  'mdash': '—',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'hellip': '…',
  'bull': '•',
  'copy': '©',
  'reg': '®',
  'Uuml': 'Ü',
  'uuml': 'ü',
  'Ouml': 'Ö',
  'ouml': 'ö',
  'Ccedil': 'Ç',
  'ccedil': 'ç',
  'Icirc': 'Î',
  'icirc': 'î',
  'Acirc': 'Â',
  'acirc': 'â',
  'Ucirc': 'Û',
  'ucirc': 'û',
  'Eacute': 'É',
  'eacute': 'é',
  'Egrave': 'È',
  'egrave': 'è',
  'Aacute': 'Á',
  'aacute': 'á',
};

/// Decodes HTML entities, strips markup and directional characters, and normalizes whitespace.
String decodeHtmlText(String input) {
  if (input.isEmpty) return '';
  var text = input
      .replaceAll(
        RegExp(r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>',
            dotAll: true, caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
    final token = m.group(1)!;
    if (token.startsWith('#x') || token.startsWith('#X')) {
      final code = int.tryParse(token.substring(2), radix: 16);
      if (code != null && code > 0 && code <= 0x10FFFF) {
        return String.fromCharCode(code);
      }
      return '';
    }
    if (token.startsWith('#')) {
      final code = int.tryParse(token.substring(1));
      if (code != null && code > 0 && code <= 0x10FFFF) {
        return String.fromCharCode(code);
      }
      return '';
    }
    return _namedHtmlEntities[token] ?? m.group(0)!;
  });
  return text
      .replaceAll(RegExp(r'[\u200E\u200F\u202A-\u202E\uFEFF]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizeLanguage(String raw) {
  final clean = raw.trim();
  if (clean.isEmpty) return '';
  final folded = foldTurkish(clean);
  return switch (folded) {
    'tr' || 'tur' || 'turkce' || 'türkçe' || 'turkish' => 'Türkçe',
    'en' || 'eng' || 'ingilizce' || 'english' => 'İngilizce',
    'de' || 'ger' || 'deu' || 'almanca' || 'german' => 'Almanca',
    'fr' || 'fre' || 'fra' || 'fransızca' || 'fransizca' || 'french' =>
      'Fransızca',
    'ar' || 'ara' || 'arapça' || 'arapca' || 'arabic' => 'Arapça',
    'es' || 'spa' || 'ispanyolca' || 'spanish' => 'İspanyolca',
    'ru' || 'rus' || 'rusça' || 'rusca' || 'russian' => 'Rusça',
    _ => clean,
  };
}

String _normalizePublisherCase(String raw) {
  final clean = raw.trim();
  if (clean.isEmpty) return '';
  // Convert ALL-CAPS Turkish publisher names (e.g. "KAPRA YAYINCILIK") to readable Title Case
  // unless it is a short acronym like "YKY" or "TÜBİTAK".
  if (clean.length > 6 && clean == clean.toUpperCase() && clean.contains(' ')) {
    return clean
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          final lower = foldTurkish(word);
          final first = word[0];
          return '$first${lower.substring(1)}';
        })
        .join(' ');
  }
  return clean;
}

Map<String, String>? parseGoogleBooks(String response, String isbn) {
  final wanted = canonicalIsbn(isbn);
  final normalized = cleanIsbnInput(isbn);
  final data = jsonDecode(response);
  if (data is! Map || (data['items'] != null && data['items'] is! List)) {
    throw const FormatException('Geçersiz yanıt');
  }
  for (final item in (data['items'] as List?) ?? []) {
    if (item is! Map || item['volumeInfo'] is! Map) continue;
    final info = item['volumeInfo'] as Map;
    final identifiers = info['industryIdentifiers'];
    if (identifiers is! List ||
        !identifiers.any((x) {
          if (x is! Map || x['identifier'] == null) return false;
          final rawId = cleanIsbnInput(x['identifier'].toString());
          if (rawId == normalized) return true;
          return wanted != null && canonicalIsbn(rawId) == wanted;
        })) {
      continue;
    }
    String text(String key) =>
        info[key] is String ? (info[key] as String).trim() : '';
    final authors = info['authors'] is List
        ? (info['authors'] as List).whereType<String>().join(', ')
        : '';
    final category = info['categories'] is List
        ? (info['categories'] as List).whereType<String>().join(', ')
        : '';
    final date = text('publishedDate');
    String coverUrl = '';
    if (info['imageLinks'] is Map) {
      final links = info['imageLinks'] as Map;
      for (final key in [
        'extraLarge',
        'large',
        'medium',
        'small',
        'thumbnail',
        'smallThumbnail',
      ]) {
        if (links[key] is String && (links[key] as String).trim().isNotEmpty) {
          coverUrl = (links[key] as String).trim().replaceFirst(
            RegExp(r'^http://'),
            'https://',
          );
          break;
        }
      }
    }
    return {
      'source': 'Google Books',
      'title': text('title'),
      'author': authors,
      'publisher': text('publisher'),
      'category': category,
      'publicationYear': date.length >= 4 ? date.substring(0, 4) : date,
      'pageCount': info['pageCount'] is int ? info['pageCount'].toString() : '',
      'language': _normalizeLanguage(text('language')),
      if (wanted != null) 'isbn': wanted,
      if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
    };
  }
  return null;
}

Map<String, String>? parseOpenLibrary(String response, String isbn) {
  final normalized = cleanIsbnInput(isbn);
  final wanted = canonicalIsbn(isbn);
  final data = jsonDecode(response);
  if (data is! Map) throw const FormatException('Geçersiz yanıt');
  final entry =
      data['ISBN:$isbn'] ??
      data['ISBN:$normalized'] ??
      (wanted != null ? data['ISBN:$wanted'] : null);
  if (entry == null) return null;
  if (entry is! Map) throw const FormatException('Geçersiz kitap kaydı');
  String text(String key) =>
      entry[key] is String ? (entry[key] as String).trim() : '';
  String names(String key) => entry[key] is List
      ? (entry[key] as List)
            .whereType<Map>()
            .map((item) => item['name'])
            .whereType<String>()
            .join(', ')
      : '';
  final date = text('publish_date');
  final year =
      RegExp(r'\b(?:1[5-9]|20)\d{2}\b').firstMatch(date)?.group(0) ?? '';
  String coverUrl = '';
  if (entry['cover'] is Map) {
    final cover = entry['cover'] as Map;
    for (final key in ['large', 'medium', 'small']) {
      if (cover[key] is String && (cover[key] as String).trim().isNotEmpty) {
        coverUrl = (cover[key] as String).trim();
        break;
      }
    }
  }
  return {
    'source': 'Open Library',
    'title': text('title'),
    'author': names('authors'),
    'publisher': names('publishers'),
    'category': names('subjects').split(', ').take(2).join(', '),
    'publicationYear': year,
    'pageCount': entry['number_of_pages'] is int
        ? entry['number_of_pages'].toString()
        : '',
    if (wanted != null) 'isbn': wanted,
    if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
  };
}

bool _isAmazonBotOrNotFound(String html) {
  if (html.isEmpty) return true;
  final lower = html.toLowerCase();
  if (lower.contains('validatecaptcha') ||
      lower.contains('api-services-support@amazon') ||
      lower.contains('robot check') ||
      lower.contains('automated access to amazon data')) {
    return true;
  }
  final titleMatch = RegExp(
    r'<title[^>]*>(.*?)</title>',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(html);
  final pageTitle = foldTurkish(decodeHtmlText(titleMatch?.group(1) ?? ''));
  return pageTitle == 'sayfa bulunamadı' || pageTitle == 'page not found';
}

/// Extracts candidate 10-character ASINs from Amazon search results HTML.
List<String> parseAmazonSearchAsins(String html) {
  if (_isAmazonBotOrNotFound(html)) return const [];
  final result = <String>[];
  for (final match in RegExp(
    r'data-asin=["\x27]([A-Z0-9]{10})["\x27]',
  ).allMatches(html)) {
    final asin = match.group(1)!;
    if (!result.contains(asin)) result.add(asin);
  }
  return result;
}

bool _trustedAmazonImageHost(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443) &&
    (uri.host == 'm.media-amazon.com' ||
        uri.host == 'images-na.ssl-images-amazon.com' ||
        uri.host == 'images-eu.ssl-images-amazon.com');

String _extractAmazonCoverUrl(String html) {
  for (final imgId in ['landingImage', 'imgBlkFront', 'ebooksImgBlkFront']) {
    final tagMatch = RegExp(
      '<img\\b[^>]*id=["\']$imgId["\'][^>]*>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (tagMatch == null) continue;
    final tag = tagMatch.group(0)!;
    final dynMatch = RegExp(
      r'data-a-dynamic-image=(["\x27])(.*?)\1',
      dotAll: true,
    ).firstMatch(tag);
    if (dynMatch != null) {
      try {
        final decodedJson = decodeHtmlText(dynMatch.group(2)!);
        final map = jsonDecode(decodedJson);
        if (map is Map) {
          String? bestUrl;
          var bestArea = -1;
          for (final entry in map.entries) {
            final urlStr = entry.key.toString().trim();
            final uri = Uri.tryParse(urlStr);
            if (uri == null || !_trustedAmazonImageHost(uri)) continue;
            var area = 0;
            if (entry.value is List && (entry.value as List).length >= 2) {
              final dims = entry.value as List;
              final w = dims[0] is num ? (dims[0] as num).toInt() : 0;
              final h = dims[1] is num ? (dims[1] as num).toInt() : 0;
              area = w * h;
            }
            if (area > bestArea) {
              bestArea = area;
              bestUrl = urlStr;
            }
          }
          if (bestUrl != null) {
            // Upgrade resolution modestly to SL1000 when using standard /images/I/<id>._..._.jpg
            final upgraded = bestUrl.replaceFirstMapped(
              RegExp(r'(/images/I/[A-Za-z0-9%+_-]+)\._[^/]+_\.(jpg|jpeg|png)$',
                  caseSensitive: false),
              (m) => '${m.group(1)}._SL1000_.${m.group(2)}',
            );
            final check = Uri.tryParse(upgraded);
            return check != null && _trustedAmazonImageHost(check)
                ? upgraded
                : bestUrl;
          }
        }
      } catch (_) {
        // Fall through to src attribute.
      }
    }
    final srcMatch = RegExp(
      r'src=(["\x27])(https://[^"\x27]+)\1',
    ).firstMatch(tag);
    if (srcMatch != null) {
      final uri = Uri.tryParse(decodeHtmlText(srcMatch.group(2)!));
      if (uri != null && _trustedAmazonImageHost(uri)) return uri.toString();
    }
  }
  return '';
}

/// Parses an Amazon (.com.tr or .com) book product detail HTML page.
Map<String, String>? parseAmazonProductHtml(
  String html, {
  String? expectedIsbn,
}) {
  if (_isAmazonBotOrNotFound(html)) return null;

  String rawTitle = '';
  for (final pattern in [
    r'<span[^>]*id=["\x27]productTitle["\x27][^>]*>(.*?)</span>',
    r'<span[^>]*id=["\x27]ebooksProductTitle["\x27][^>]*>(.*?)</span>',
  ]) {
    final m = RegExp(pattern, dotAll: true, caseSensitive: false).firstMatch(
      html,
    );
    if (m != null) {
      rawTitle = decodeHtmlText(m.group(1)!);
      if (rawTitle.isNotEmpty) break;
    }
  }
  if (rawTitle.isEmpty) return null;

  // Extract authors from #bylineInfo
  final primaryAuthors = <String>[];
  final fallbackContributors = <String>[];
  final bylineIdx = html.indexOf('id="bylineInfo"');
  if (bylineIdx >= 0) {
    final bylineWindow = html.substring(
      bylineIdx,
      (bylineIdx + 6000).clamp(0, html.length),
    );
    final authorStarts = RegExp(
      r'<span[^>]*class=["\x27][^"\x27]*\bauthor\b[^"\x27]*["\x27][^>]*>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(bylineWindow).toList();
    for (var i = 0; i < authorStarts.length; i++) {
      final start = authorStarts[i].end;
      final end = i + 1 < authorStarts.length
          ? authorStarts[i + 1].start
          : (start + 1200).clamp(0, bylineWindow.length);
      final block = bylineWindow.substring(start, end);
      final linkMatch = RegExp(
        r'<a\b[^>]*>(.*?)</a>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(block);
      final name = decodeHtmlText(linkMatch?.group(1) ?? '');
      if (name.isEmpty) continue;
      final roleMatch = RegExp(
        r'<span[^>]*class=["\x27][^"\x27]*contribution[^"\x27]*["\x27][^>]*>(.*?)(?:</div>|$)',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(block);
      final role = foldTurkish(decodeHtmlText(roleMatch?.group(1) ?? ''));
      final isSecondary = role.contains('çevirmen') ||
          role.contains('cevirmen') ||
          role.contains('translator') ||
          role.contains('editör') ||
          role.contains('editor') ||
          role.contains('resimleyen') ||
          role.contains('illustrator') ||
          role.contains('hazırlayan') ||
          role.contains('önsöz');
      if (!isSecondary) {
        if (!primaryAuthors.contains(name)) primaryAuthors.add(name);
      } else {
        if (!fallbackContributors.contains(name)) {
          fallbackContributors.add(name);
        }
      }
    }
    if (primaryAuthors.isEmpty && fallbackContributors.isEmpty) {
      for (final a in RegExp(
        r'field-author=[^"\x27>]+["\x27][^>]*>(.*?)</a>',
        dotAll: true,
        caseSensitive: false,
      ).allMatches(bylineWindow)) {
        final name = decodeHtmlText(a.group(1)!);
        if (name.isNotEmpty && !primaryAuthors.contains(name)) {
          primaryAuthors.add(name);
        }
      }
    }
  }
  final author = (primaryAuthors.isNotEmpty
          ? primaryAuthors
          : fallbackContributors)
      .join(', ');

  // Extract detail bullets (Product Details / Ürün Bilgileri)
  String publisher = '';
  String publicationYear = '';
  String edition = '';
  String language = '';
  String pageCount = '';
  String readingLevel = '';
  final foundIsbns = <String>{};

  void consumeKeyValue(String rawKey, String rawVal) {
    final key = foldTurkish(rawKey.replaceAll(':', '').trim());
    final val = rawVal.replaceFirst(RegExp(r'^[:：\s]+'), '').trim();
    if (key.isEmpty || val.isEmpty) return;

    if (key == 'yayıncı' ||
        key == 'yayinci' ||
        key == 'yayınevi' ||
        key == 'yayinevi' ||
        key == 'publisher') {
      // Handle e.g. "Can Yayınları; 77. baskı (1 Ocak 2001)"
      var pub = val;
      final parenYear = RegExp(r'\(([^)]*\b(?:1[5-9]|20)\d{2}\b[^)]*)\)')
          .firstMatch(pub);
      if (parenYear != null) {
        if (publicationYear.isEmpty) {
          publicationYear = RegExp(r'\b(?:1[5-9]|20)\d{2}\b')
                  .firstMatch(parenYear.group(1)!)
                  ?.group(0) ??
              '';
        }
        pub = pub.replaceRange(parenYear.start, parenYear.end, '').trim();
      }
      if (pub.contains(';')) {
        final parts = pub.split(';');
        pub = parts.first.trim();
        final rest = parts.sublist(1).join(';').trim();
        if (edition.isEmpty && rest.isNotEmpty) {
          edition = rest;
        }
      }
      if (publisher.isEmpty && pub.isNotEmpty) {
        publisher = _normalizePublisherCase(pub);
      }
    } else if (key.contains('yayınlanma tarihi') ||
        key.contains('yayinlanma tarihi') ||
        key.contains('publication date')) {
      final y = RegExp(r'\b(?:1[5-9]|20)\d{2}\b').firstMatch(val)?.group(0);
      if (y != null && publicationYear.isEmpty) publicationYear = y;
    } else if (key == 'baskı' || key == 'baski' || key == 'edition') {
      if (edition.isEmpty) {
        edition = RegExp(r'^\d+\.?$').hasMatch(val)
            ? '${val.endsWith('.') ? val : '$val.'} Baskı'
            : val;
      }
    } else if (key == 'dil' || key == 'language') {
      if (language.isEmpty) language = _normalizeLanguage(val);
    } else if (key.contains('baskı uzunluğu') ||
        key.contains('baski uzunlugu') ||
        key.contains('print length') ||
        key.contains('sayfa sayısı') ||
        key == 'kağıt kapak' ||
        key == 'kagit kapak' ||
        key == 'karton kapak' ||
        key == 'ciltli' ||
        key == 'paperback' ||
        key == 'hardcover') {
      final p = RegExp(
        r'\b(\d{1,5})\s*(?:sayfa|pages?)\b',
        caseSensitive: false,
      ).firstMatch(val)?.group(1);
      if (p != null && pageCount.isEmpty) pageCount = p;
    } else if (key == 'isbn-10' ||
        key == 'isbn-13' ||
        key == 'isbn' ||
        key == 'ısbn-10' ||
        key == 'ısbn-13' ||
        key == 'ısbn') {
      final canonical = canonicalIsbn(val);
      if (canonical != null) foundIsbns.add(canonical);
    } else if (key.contains('okuma yaşı') ||
        key.contains('okuma yasi') ||
        key.contains('reading age')) {
      if (readingLevel.isEmpty) {
        readingLevel = val
            .replaceFirst(
              RegExp(r'^müşterinin önerdiği yaş\s*:\s*', caseSensitive: false),
              '',
            )
            .trim();
      }
    }
  }

  final bulletsIdx = html.indexOf('detailBullets_feature_div');
  if (bulletsIdx >= 0) {
    final bulletsWindow = html.substring(
      bulletsIdx,
      (bulletsIdx + 14000).clamp(0, html.length),
    );
    for (final li in RegExp(
      r'<li\b[^>]*>(.*?)</li>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(bulletsWindow)) {
      final content = li.group(1)!;
      final bold = RegExp(
        r'<span[^>]*class=["\x27][^"\x27]*a-text-bold[^"\x27]*["\x27][^>]*>(.*?)</span>\s*<span[^>]*>(.*?)</span>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(content);
      if (bold != null) {
        consumeKeyValue(
          decodeHtmlText(bold.group(1)!),
          decodeHtmlText(bold.group(2)!),
        );
      }
    }
  }

  // Also parse Rich Product Information carousel attributes (rpi-attribute-content) as fallback
  for (final rpi in RegExp(
    r'rpi-attribute-label[^>]*>\s*<span[^>]*>(.*?)</span>.*?rpi-attribute-value[^>]*>\s*<span[^>]*>(.*?)</span>',
    dotAll: true,
    caseSensitive: false,
  ).allMatches(html)) {
    consumeKeyValue(
      decodeHtmlText(rpi.group(1)!),
      decodeHtmlText(rpi.group(2)!),
    );
  }

  if (expectedIsbn != null && expectedIsbn.trim().isNotEmpty) {
    final wanted = canonicalIsbn(expectedIsbn);
    if (wanted != null && foundIsbns.isNotEmpty && !foundIsbns.contains(wanted)) {
      // Page explicitly belongs to a different ISBN edition.
      return null;
    }
  }

  // Extract category from breadcrumbs
  String category = '';
  final bcIdx = html.indexOf('wayfinding-breadcrumbs');
  if (bcIdx >= 0) {
    final bcWindow = html.substring(
      bcIdx,
      (bcIdx + 4000).clamp(0, html.length),
    );
    final crumbs = <String>[];
    for (final m in RegExp(
      r'<a\b[^>]*class=["\x27][^"\x27]*a-color-tertiary[^"\x27]*["\x27][^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(bcWindow)) {
      final label = decodeHtmlText(m.group(1)!);
      final lower = foldTurkish(label);
      if (label.isNotEmpty &&
          lower != 'kitap' &&
          lower != 'kitaplar' &&
          lower != 'books' &&
          !crumbs.contains(label)) {
        crumbs.add(label);
      }
    }
    if (crumbs.isNotEmpty) {
      category = crumbs.take(2).join(' › ');
    }
  }

  final coverUrl = _extractAmazonCoverUrl(html);
  final resolvedIsbn = foundIsbns.firstOrNull ??
      (expectedIsbn != null ? canonicalIsbn(expectedIsbn) ?? '' : '');

  return {
    'source': 'Amazon',
    'title': rawTitle,
    'author': author,
    'publisher': publisher,
    'category': category,
    'publicationYear': publicationYear,
    'pageCount': pageCount,
    'edition': edition,
    'language': language,
    'readingLevel': readingLevel,
    if (resolvedIsbn.isNotEmpty) 'isbn': resolvedIsbn,
    if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
  };
}

bool _trustedKitapyurduPage(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443) &&
    (uri.host == 'www.kitapyurdu.com' || uri.host == 'kitapyurdu.com');

bool _trustedKitapyurduCover(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443) &&
    uri.host == 'img.kitapyurdu.com';

String _cleanKitapyurduDetailUrl(String raw) {
  final decoded = decodeHtmlText(raw);
  final base = Uri.https('www.kitapyurdu.com', '/');
  final uri = base.resolve(decoded);
  if (!_trustedKitapyurduPage(uri) || !uri.path.startsWith('/kitap/')) {
    return '';
  }
  return Uri.https('www.kitapyurdu.com', uri.path).toString();
}

String _upgradeKitapyurduCover(String raw) {
  final decoded = decodeHtmlText(raw);
  final uri = Uri.tryParse(decoded);
  if (uri == null || !_trustedKitapyurduCover(uri)) return '';
  return decoded.replaceFirst('/wi:200/', '/wi:500/');
}

/// Parses Kitapyurdu search result product cards (`div.ky-product`).
List<KitapyurduCandidate> parseKitapyurduSearchHtml(String html) {
  if (html.isEmpty) return const [];
  final results = <KitapyurduCandidate>[];
  final seenIds = <String>{};
  final cardStarts = RegExp(
    r'<div\s+class=["\x27]ky-product["\x27][^>]*data-product-id=["\x27](\d+)["\x27][^>]*>',
    caseSensitive: false,
  ).allMatches(html).toList();

  for (var i = 0; i < cardStarts.length; i++) {
    final productId = cardStarts[i].group(1)!;
    if (!seenIds.add(productId)) continue;
    final start = cardStarts[i].start;
    final end = i + 1 < cardStarts.length
        ? cardStarts[i + 1].start
        : (start + 8000).clamp(0, html.length);
    final block = html.substring(start, end);

    final titleMatch = RegExp(
      r'<a\b[^>]*class=["\x27][^"\x27]*ky-product-title[^"\x27]*["\x27][^>]*href=["\x27]([^"\x27]+)["\x27][^>]*>(.*?)</a>|'
      r'<a\b[^>]*href=["\x27]([^"\x27]+)["\x27][^>]*class=["\x27][^"\x27]*ky-product-title[^"\x27]*["\x27][^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(block);
    if (titleMatch == null) continue;
    final rawHref = titleMatch.group(1) ?? titleMatch.group(3) ?? '';
    final rawTitle = titleMatch.group(2) ?? titleMatch.group(4) ?? '';
    final detailUrl = _cleanKitapyurduDetailUrl(rawHref);
    final title = decodeHtmlText(rawTitle);
    if (detailUrl.isEmpty || title.isEmpty) continue;

    final authorMatch = RegExp(
      r'<span[^>]*class=["\x27][^"\x27]*ky-product-author[^"\x27]*["\x27][^>]*>(.*?)</span>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(block);
    final publisherMatch = RegExp(
      r'<span[^>]*class=["\x27][^"\x27]*ky-product-publisher[^"\x27]*["\x27][^>]*>(.*?)</span>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(block);
    final coverMatch = RegExp(
      r'<a\b[^>]*class=["\x27][^"\x27]*ky-product-cover[^"\x27]*["\x27][^>]*>.*?<img\b[^>]*src=["\x27]([^"\x27]+)["\x27]',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(block);

    results.add(
      KitapyurduCandidate(
        productId: productId,
        title: title,
        author: decodeHtmlText(authorMatch?.group(1) ?? ''),
        publisher: _normalizePublisherCase(
          decodeHtmlText(publisherMatch?.group(1) ?? ''),
        ),
        detailUrl: detailUrl,
        coverUrl: _upgradeKitapyurduCover(coverMatch?.group(1) ?? ''),
      ),
    );
  }
  return results;
}

const _publisherAliases = <String, List<String>>{
  'yky': ['yapı kredi', 'yapi kredi'],
  'yapı kredi': ['yky'],
  'iş bankası': ['türkiye iş bankası', 'kültür yayınları'],
  'türkiye iş bankası': ['iş bankası'],
  'meb': ['milli eğitim'],
  'tubitak': ['tübitak'],
  'tübitak': ['tubitak'],
};

List<String> _tokensOf(String text) => foldTurkish(text)
    .replaceAll(RegExp(r'[^\wçğıöşüÇĞİÖŞÜ\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.length >= 2)
    .toList();

bool _fieldMatchesTokens(String candidateField, String queryField, {bool publisherMode = false}) {
  final q = foldTurkish(queryField.trim());
  if (q.isEmpty) return true;
  final c = foldTurkish(candidateField.trim());
  if (c.isEmpty) return false;
  if (c.contains(q) || q.contains(c)) return true;
  if (publisherMode) {
    for (final entry in _publisherAliases.entries) {
      if (q.contains(entry.key) && entry.value.any(c.contains)) return true;
    }
  }
  final tokens = _tokensOf(queryField)
      .where(
        (t) => !{
          'yayınları',
          'yayinlari',
          'yayınevi',
          'yayinevi',
          'yayıncılık',
          'yayincilik',
          'kitap',
          've',
        }.contains(t),
      )
      .toList();
  if (tokens.isEmpty) return c.contains(q);
  final matched = tokens.where(c.contains).length;
  return matched * 2 >= tokens.length;
}

/// Filters and ranks Kitapyurdu search results by title, author, and publisher.
List<KitapyurduCandidate> filterAndRankKitapyurduCandidates(
  List<KitapyurduCandidate> items, {
  String title = '',
  String author = '',
  String publisher = '',
}) {
  final qTitle = foldTurkish(title.trim());
  final qAuthor = foldTurkish(author.trim());
  final qPublisher = foldTurkish(publisher.trim());

  final scored = <({KitapyurduCandidate item, int score})>[];
  for (final item in items) {
    var score = 0;
    final cTitle = foldTurkish(item.title);
    final cAuthor = foldTurkish(item.author);
    final cPub = foldTurkish(item.publisher);

    if (qTitle.isNotEmpty) {
      if (cTitle == qTitle) {
        score += 120;
      } else if (cTitle.startsWith(qTitle)) {
        score += 90;
      } else if (cTitle.contains(qTitle)) {
        score += 70;
      } else if (_fieldMatchesTokens(item.title, title)) {
        score += 40;
      } else {
        score -= 30;
      }
    }

    if (qAuthor.isNotEmpty) {
      if (cAuthor == qAuthor) {
        score += 100;
      } else if (_fieldMatchesTokens(item.author, author)) {
        score += 75;
      } else {
        score -= 50;
      }
    }

    if (qPublisher.isNotEmpty) {
      if (cPub == qPublisher) {
        score += 90;
      } else if (_fieldMatchesTokens(
        item.publisher,
        publisher,
        publisherMode: true,
      )) {
        score += 65;
      } else {
        score -= 35;
      }
    }

    if (item.coverUrl.isNotEmpty) score += 5;
    scored.add((item: item, score: score));
  }

  final positive = scored.where((e) => e.score >= 0).toList();
  final chosen = positive.isNotEmpty ? positive : scored;
  chosen.sort((a, b) => b.score.compareTo(a.score));
  return chosen.map((e) => e.item).toList();
}

/// Parses a Kitapyurdu book detail HTML page (JSON-LD Book schema + attribute table).
Map<String, String>? parseKitapyurduDetailHtml(String html) {
  if (html.isEmpty) return null;
  String title = '';
  String author = '';
  String publisher = '';
  String isbn = '';
  String pageCount = '';
  String publicationYear = '';
  String language = '';
  String category = '';
  String edition = '';
  String coverUrl = '';

  // 1. Parse Schema.org JSON-LD (@type: Book / Product)
  for (final m in RegExp(
    r'<script[^>]*type=["\x27]application/ld\+json["\x27][^>]*>(.*?)</script>',
    dotAll: true,
    caseSensitive: false,
  ).allMatches(html)) {
    try {
      final parsed = jsonDecode(m.group(1)!.trim());
      final nodes = <Map>[];
      void collect(dynamic node) {
        if (node is Map) {
          nodes.add(node);
          if (node['@graph'] is List) {
            for (final child in node['@graph'] as List) {
              collect(child);
            }
          }
        } else if (node is List) {
          for (final child in node) {
            collect(child);
          }
        }
      }

      collect(parsed);
      for (final node in nodes) {
        final type = node['@type'];
        final isBook = type == 'Book' ||
            (type is List && type.contains('Book'));
        final isProduct = type == 'Product' ||
            (type is List && type.contains('Product'));
        if (!isBook && !isProduct) continue;

        if (title.isEmpty && node['name'] is String) {
          title = decodeHtmlText(node['name'] as String);
        }
        if (node['image'] is String && coverUrl.isEmpty) {
          final candidate = _upgradeKitapyurduCover(node['image'] as String);
          if (candidate.isNotEmpty) coverUrl = candidate;
        }
        if (isBook) {
          final rawAuthor = node['author'];
          if (author.isEmpty) {
            if (rawAuthor is Map && rawAuthor['name'] is String) {
              author = decodeHtmlText(rawAuthor['name'] as String);
            } else if (rawAuthor is List) {
              author = rawAuthor
                  .map((a) => a is Map ? a['name'] : a)
                  .whereType<String>()
                  .map(decodeHtmlText)
                  .where((s) => s.isNotEmpty)
                  .join(', ');
            } else if (rawAuthor is String) {
              author = decodeHtmlText(rawAuthor);
            }
          }
          final rawPub = node['publisher'];
          if (publisher.isEmpty) {
            if (rawPub is Map && rawPub['name'] is String) {
              publisher = _normalizePublisherCase(
                decodeHtmlText(rawPub['name'] as String),
              );
            } else if (rawPub is String) {
              publisher = _normalizePublisherCase(decodeHtmlText(rawPub));
            }
          }
          if (isbn.isEmpty && node['isbn'] != null) {
            isbn = canonicalIsbn(node['isbn'].toString()) ??
                cleanIsbnInput(node['isbn'].toString());
          }
          if (pageCount.isEmpty && node['numberOfPages'] != null) {
            final p = int.tryParse(node['numberOfPages'].toString());
            if (p != null && p > 0) pageCount = '$p';
          }
          if (publicationYear.isEmpty && node['datePublished'] is String) {
            publicationYear = RegExp(r'\b(?:1[5-9]|20)\d{2}\b')
                    .firstMatch(node['datePublished'] as String)
                    ?.group(0) ??
                '';
          }
          if (language.isEmpty && node['inLanguage'] is String) {
            language = _normalizeLanguage(node['inLanguage'] as String);
          }
        }
        if (isProduct) {
          if (publisher.isEmpty &&
              node['brand'] is Map &&
              (node['brand'] as Map)['name'] is String) {
            publisher = _normalizePublisherCase(
              decodeHtmlText((node['brand'] as Map)['name'] as String),
            );
          }
          if (isbn.isEmpty && node['gtin13'] != null) {
            isbn = canonicalIsbn(node['gtin13'].toString()) ?? '';
          }
        }
      }
    } catch (_) {
      // Malformed JSON-LD block should not prevent HTML attribute parsing.
    }
  }

  // 2. Parse HTML title / attributes / categories as supplement & fallback
  if (title.isEmpty) {
    final h1 = RegExp(
      r'<h1[^>]*class=["\x27][^"\x27]*ky-pd-title[^"\x27]*["\x27][^>]*>(.*?)</h1>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html);
    if (h1 != null) title = decodeHtmlText(h1.group(1)!);
  }

  for (final item in RegExp(
    r'<div[^>]*class=["\x27][^"\x27]*ky-pd-attributes__item[^"\x27]*["\x27][^>]*>(.*?)</div>',
    dotAll: true,
    caseSensitive: false,
  ).allMatches(html)) {
    final block = item.group(1)!;
    final labelMatch = RegExp(
      r'ky-pd-attributes__label[^>]*>(.*?)</span>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(block);
    final valMatch = RegExp(
      r'ky-pd-attributes__value[^>]*>(.*?)</span>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(block);
    if (labelMatch == null || valMatch == null) continue;
    final key = foldTurkish(
      decodeHtmlText(labelMatch.group(1)!).replaceAll(':', '').trim(),
    );
    final val = decodeHtmlText(valMatch.group(1)!);
    if (val.isEmpty) continue;

    if ((key == 'isbn' || key == 'ısbn') && isbn.isEmpty) {
      isbn = canonicalIsbn(val) ?? (isValidIsbn(val) ? cleanIsbnInput(val) : '');
    } else if (key.contains('sayfa sayısı') || key.contains('sayfa sayisi')) {
      final p = RegExp(r'\d{1,5}').firstMatch(val)?.group(0);
      if (p != null && pageCount.isEmpty) pageCount = p;
    } else if (key.contains('yayın tarihi') || key.contains('yayin tarihi')) {
      final y = RegExp(r'\b(?:1[5-9]|20)\d{2}\b').firstMatch(val)?.group(0);
      if (y != null && publicationYear.isEmpty) publicationYear = y;
    } else if (key == 'dil' && language.isEmpty) {
      language = _normalizeLanguage(val);
    } else if ((key.contains('baskı') || key.contains('baski')) &&
        edition.isEmpty) {
      edition = val;
    }
  }

  // Categories from ky-pd-attributes__categories
  final catIdx = html.indexOf('ky-pd-attributes__categories');
  if (catIdx >= 0) {
    final catWindow = html.substring(
      catIdx,
      (catIdx + 3000).clamp(0, html.length),
    );
    final firstCategoryBlock = RegExp(
      r'<div[^>]*class=["\x27][^"\x27]*ky-pd-attributes__category\b[^"\x27]*["\x27][^>]*>(.*?)</div>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(catWindow);
    if (firstCategoryBlock != null) {
      final items = RegExp(
        r'<span[^>]*class=["\x27][^"\x27]*ky-pd-attributes__category-item[^"\x27]*["\x27][^>]*>(.*?)</span>',
        dotAll: true,
        caseSensitive: false,
      )
          .allMatches(firstCategoryBlock.group(1)!)
          .map((m) => decodeHtmlText(m.group(1)!))
          .where((s) => s.isNotEmpty && foldTurkish(s) != 'kitap')
          .toList();
      if (items.isNotEmpty) {
        category = items.join(' › ');
      }
    }
  }

  if (coverUrl.isEmpty) {
    final imgMatch = RegExp(
      r'id=["\x27]js-book-cover["\x27][^>]*src=["\x27](https://img\.kitapyurdu\.com/[^"\x27]+)["\x27]',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html);
    if (imgMatch != null) {
      coverUrl = _upgradeKitapyurduCover(imgMatch.group(1)!);
    }
  }

  if (title.isEmpty) return null;
  return {
    'source': 'Kitapyurdu',
    'title': title,
    'author': author,
    'publisher': publisher,
    'category': category,
    'publicationYear': publicationYear,
    'pageCount': pageCount,
    'edition': edition,
    'language': language,
    if (isbn.isNotEmpty) 'isbn': isbn,
    if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
  };
}

/// Merges multiple lookup results in priority order, filling empty fields from later sources.
Map<String, String>? mergeLookupMaps(List<Map<String, String>?> records) {
  final valid = records
      .whereType<Map<String, String>>()
      .where((m) => (m['title'] ?? '').trim().isNotEmpty)
      .toList();
  if (valid.isEmpty) return null;
  final merged = <String, String>{};
  final usedSources = <String>[];
  const fields = [
    'title',
    'author',
    'publisher',
    'category',
    'publicationYear',
    'pageCount',
    'edition',
    'language',
    'readingLevel',
    'isbn',
    'coverUrl',
  ];
  for (final record in valid) {
    var contributed = false;
    for (final key in fields) {
      final existing = (merged[key] ?? '').trim();
      final incoming = (record[key] ?? '').trim();
      if (existing.isEmpty && incoming.isNotEmpty) {
        merged[key] = incoming;
        contributed = true;
      }
    }
    final src = (record['source'] ?? '').trim();
    if (contributed && src.isNotEmpty && !usedSources.contains(src)) {
      usedSources.add(src);
    }
  }
  merged['source'] = usedSources.join(' + ');
  return merged;
}

Future<String> _httpGetText(
  HttpClient client,
  Uri uri, {
  required bool Function(Uri) trustedHost,
  bool browserHeaders = false,
  bool mobileUserAgent = false,
  int maxBytes = 4 * 1024 * 1024,
}) async {
  var current = uri;
  for (var redirects = 0; redirects < 5; redirects++) {
    if (!trustedHost(current)) {
      throw const FormatException('Kitap servisi adresi güvenilir değil');
    }
    final request = await client
        .getUrl(current)
        .timeout(const Duration(seconds: 12));
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      browserHeaders
          ? (mobileUserAgent
                ? 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36'
                : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36')
          : 'KitapBulAndroid/1.1',
    );
    if (browserHeaders) {
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) {
        throw const FormatException('Geçersiz yönlendirme');
      }
      current = current.resolve(location);
      continue;
    }
    if (response.statusCode == 404) {
      await response.drain<void>();
      return '';
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('Kitap servisi HTTP ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('Yanıt çok büyük');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }
  throw const FormatException('Çok fazla yönlendirme');
}

bool _trustedAmazonPageHost(Uri u) =>
    u.scheme == 'https' &&
    u.userInfo.isEmpty &&
    (!u.hasPort || u.port == 443) &&
    (u.host == 'www.amazon.com.tr' ||
        u.host == 'amazon.com.tr' ||
        u.host == 'www.amazon.com' ||
        u.host == 'amazon.com');

/// Looks up book metadata and cover URL on Amazon (.com.tr first, then .com) by ISBN.
Future<Map<String, String>?> lookupAmazonIsbn(
  String isbn, {
  HttpClient? sharedClient,
}) async {
  if (isbn.trim().isEmpty || !isValidIsbn(isbn)) {
    throw const FormatException('Geçerli ISBN girin');
  }
  final canonical = canonicalIsbn(isbn)!;
  final isbn10 = isbn10Of(isbn);
  final client =
      sharedClient ??
      (HttpClient()..connectionTimeout = const Duration(seconds: 10));
  var anyHttpCompleted = false;
  Object? firstError;
  try {
    // 1. Direct ISBN-10 ASIN lookup on Amazon.com.tr (fastest & exact for 978 ISBNs)
    if (isbn10 != null) {
      try {
        final trHtml = await _httpGetText(
          client,
          Uri.https('www.amazon.com.tr', '/dp/$isbn10'),
          trustedHost: _trustedAmazonPageHost,
          browserHeaders: true,
        );
        anyHttpCompleted = true;
        final parsed = parseAmazonProductHtml(trHtml, expectedIsbn: canonical);
        if (parsed != null) return parsed;
      } catch (e) {
        firstError ??= e;
      }
    }

    // 2. Search Amazon.com.tr by ISBN-13 (essential for 979 ISBNs whose ASIN is B0...)
    try {
      final searchHtml = await _httpGetText(
        client,
        Uri.https('www.amazon.com.tr', '/s', {
          'k': canonical,
          'i': 'stripbooks',
        }),
        trustedHost: _trustedAmazonPageHost,
        browserHeaders: true,
        mobileUserAgent: true,
      );
      anyHttpCompleted = true;
      final asins = parseAmazonSearchAsins(searchHtml)
          .where((a) => a != isbn10)
          .take(2);
      for (final asin in asins) {
        final dpHtml = await _httpGetText(
          client,
          Uri.https('www.amazon.com.tr', '/dp/$asin'),
          trustedHost: _trustedAmazonPageHost,
          browserHeaders: true,
        );
        final parsed = parseAmazonProductHtml(dpHtml, expectedIsbn: canonical);
        // Require explicit ISBN match when coming from a general search result
        if (parsed != null && canonicalIsbn(parsed['isbn'] ?? '') == canonical) {
          return parsed;
        }
      }
    } catch (e) {
      firstError ??= e;
    }

    // 3. International fallback on Amazon.com for foreign-language ISBN-10s
    if (isbn10 != null) {
      try {
        final comHtml = await _httpGetText(
          client,
          Uri.https('www.amazon.com', '/dp/$isbn10'),
          trustedHost: _trustedAmazonPageHost,
          browserHeaders: true,
        );
        anyHttpCompleted = true;
        final parsed = parseAmazonProductHtml(comHtml, expectedIsbn: canonical);
        if (parsed != null) return parsed;
      } catch (e) {
        firstError ??= e;
      }
    }
    if (!anyHttpCompleted && firstError != null) throw firstError;
    return null;
  } finally {
    if (sharedClient == null) client.close(force: true);
  }
}

/// Searches Kitapyurdu by title, author, and/or publisher and returns ranked candidates.
Future<List<KitapyurduCandidate>> searchKitapyurdu({
  String title = '',
  String author = '',
  String publisher = '',
  int limit = 25,
  HttpClient? sharedClient,
}) async {
  final t = title.trim();
  final a = author.trim();
  final p = publisher.trim();
  if (t.isEmpty && a.isEmpty && p.isEmpty) {
    throw const FormatException(
      'Arama için kitap adı, yazar veya yayınevi girin',
    );
  }

  final queries = <String>[];
  final full = [t, a, p].where((s) => s.isNotEmpty).join(' ');
  queries.add(full);
  if (t.isNotEmpty && a.isNotEmpty && p.isNotEmpty) {
    queries.add('$t $a');
  }
  if (t.isNotEmpty && (a.isNotEmpty || p.isNotEmpty)) {
    queries.add(t);
  }

  final client =
      sharedClient ??
      (HttpClient()..connectionTimeout = const Duration(seconds: 10));
  try {
    final collected = <KitapyurduCandidate>[];
    final seenIds = <String>{};
    Object? lastError;

    for (final q in queries) {
      try {
        final html = await _httpGetText(
          client,
          Uri.https('www.kitapyurdu.com', '/index.php', {
            'route': 'product/list',
            'filter_name': q,
            'filter_in_stock': '0',
          }),
          trustedHost: _trustedKitapyurduPage,
          browserHeaders: true,
        );
        for (final item in parseKitapyurduSearchHtml(html)) {
          if (seenIds.add(item.productId)) collected.add(item);
        }
        if (collected.isNotEmpty) break;
      } catch (e) {
        lastError = e;
      }
    }
    if (collected.isEmpty && lastError != null) throw lastError;
    return filterAndRankKitapyurduCandidates(
      collected,
      title: t,
      author: a,
      publisher: p,
    ).take(limit).toList();
  } finally {
    if (sharedClient == null) client.close(force: true);
  }
}

/// Fetches full book metadata (including ISBN, page count, category, cover URL) from a Kitapyurdu book URL.
Future<Map<String, String>?> fetchKitapyurduDetail(
  String detailUrl, {
  HttpClient? sharedClient,
}) async {
  final cleanUrl = _cleanKitapyurduDetailUrl(detailUrl);
  if (cleanUrl.isEmpty) {
    throw const FormatException('Geçersiz Kitapyurdu kitap bağlantısı');
  }
  final client =
      sharedClient ??
      (HttpClient()..connectionTimeout = const Duration(seconds: 10));
  try {
    final html = await _httpGetText(
      client,
      Uri.parse(cleanUrl),
      trustedHost: _trustedKitapyurduPage,
      browserHeaders: true,
    );
    return parseKitapyurduDetailHtml(html);
  } finally {
    if (sharedClient == null) client.close(force: true);
  }
}

/// Finds the best Kitapyurdu match for title/author/publisher and fetches its full metadata.
Future<Map<String, String>?> lookupKitapyurduFirstMatch({
  String title = '',
  String author = '',
  String publisher = '',
  String? expectedIsbn,
  HttpClient? sharedClient,
}) async {
  final client =
      sharedClient ??
      (HttpClient()..connectionTimeout = const Duration(seconds: 10));
  try {
    final candidates = await searchKitapyurdu(
      title: title,
      author: author,
      publisher: publisher,
      limit: 5,
      sharedClient: client,
    );
    if (candidates.isEmpty) return null;
    final wanted = expectedIsbn == null ? null : canonicalIsbn(expectedIsbn);
    Map<String, String>? firstValid;
    for (final candidate in candidates.take(wanted != null ? 4 : 1)) {
      try {
        final detail = await fetchKitapyurduDetail(
          candidate.detailUrl,
          sharedClient: client,
        );
        if (detail == null) continue;
        firstValid ??= detail;
        if (wanted == null) return detail;
        if (canonicalIsbn(detail['isbn'] ?? '') == wanted) return detail;
      } catch (_) {
        // Try next candidate.
      }
    }
    return wanted == null ? firstValid : null;
  } finally {
    if (sharedClient == null) client.close(force: true);
  }
}

/// Looks up an ISBN across Amazon, Google Books, Open Library (and Kitapyurdu enrichment when needed).
Future<Map<String, String>?> lookupIsbn(
  String isbn, {
  BookLookupSource preferred = BookLookupSource.auto,
}) async {
  if (isbn.trim().isEmpty || !isValidIsbn(isbn)) {
    throw const FormatException('Geçerli ISBN girin');
  }
  final normalized = cleanIsbnInput(isbn);
  final canonical = canonicalIsbn(normalized) ?? normalized;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  Future<Map<String, String>?> tryGoogle() async {
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': 'isbn:$normalized',
      'maxResults': '10',
    });
    final body = await _httpGetText(
      client,
      uri,
      trustedHost: (u) =>
          u.scheme == 'https' &&
          u.host == 'www.googleapis.com' &&
          u.userInfo.isEmpty,
      maxBytes: 2 * 1024 * 1024,
    );
    return body.isEmpty ? null : parseGoogleBooks(body, normalized);
  }

  Future<Map<String, String>?> tryOpenLibrary() async {
    final uri = Uri.https('openlibrary.org', '/api/books', {
      'bibkeys': 'ISBN:$normalized',
      'format': 'json',
      'jscmd': 'data',
    });
    final body = await _httpGetText(
      client,
      uri,
      trustedHost: (u) =>
          u.scheme == 'https' &&
          u.host == 'openlibrary.org' &&
          u.userInfo.isEmpty,
      maxBytes: 2 * 1024 * 1024,
    );
    return body.isEmpty ? null : parseOpenLibrary(body, normalized);
  }

  try {
    if (preferred == BookLookupSource.amazon) {
      return await lookupAmazonIsbn(normalized, sharedClient: client);
    }
    if (preferred == BookLookupSource.googleBooks) {
      return await tryGoogle();
    }
    if (preferred == BookLookupSource.openLibrary) {
      return await tryOpenLibrary();
    }

    // Auto mode: query Amazon, Google Books, and Open Library in parallel for speed,
    // then merge in priority order: Amazon -> Kitapyurdu (verified ISBN) -> Google Books -> Open Library.
    Object? lastFailure;
    var completedSources = 0;
    Future<Map<String, String>?> safeRun(
      Future<Map<String, String>?> Function() fn,
    ) async {
      try {
        final value = await fn();
        completedSources++;
        return value;
      } catch (e) {
        lastFailure ??= e;
        return null;
      }
    }

    final results = await Future.wait([
      safeRun(() => lookupAmazonIsbn(normalized, sharedClient: client)),
      safeRun(tryGoogle),
      safeRun(tryOpenLibrary),
    ]);
    if (completedSources == 0 && lastFailure != null) {
      throw lastFailure!;
    }
    final amazon = results[0];
    final google = results[1];
    final openLib = results[2];

    var combined = mergeLookupMaps([amazon, google, openLib]);

    // If we found title/author via Google/OpenLibrary/Amazon, check Kitapyurdu for any missing
    // Turkish metadata (e.g. publisher, category, pageCount, coverUrl) verified by exact ISBN!
    if (combined != null &&
        ((combined['publisher'] ?? '').isEmpty ||
            (combined['category'] ?? '').isEmpty ||
            (combined['pageCount'] ?? '').isEmpty ||
            (combined['coverUrl'] ?? '').isEmpty)) {
      final ky = await safeRun(
        () => lookupKitapyurduFirstMatch(
          title: combined!['title'] ?? '',
          author: combined['author'] ?? '',
          publisher: combined['publisher'] ?? '',
          expectedIsbn: canonical,
          sharedClient: client,
        ),
      );
      if (ky != null) {
        combined = mergeLookupMaps([amazon, ky, google, openLib]);
      }
    }

    return combined;
  } finally {
    client.close(force: true);
  }
}
