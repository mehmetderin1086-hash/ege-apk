// Pure-Dart web utilities for JARVIS: page fetching & readable-text
// extraction, media discovery, web search (DuckDuckGo HTML with Wikipedia
// fallback), Wikipedia summaries, weather (Open-Meteo), currency
// (Frankfurter) and news (Google News RSS).
//
// Every network function accepts an optional [http.Client] so tests can inject
// a `MockClient`. Public APIs never throw for network errors; they return
// null / empty results or a result object carrying a Turkish `error` message.
// Anti-bot / CAPTCHA challenge pages are treated as failed fetches.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

class WebLink {
  final String text;
  final String url;
  const WebLink(this.text, this.url);

  @override
  String toString() => text.isEmpty ? url : '$text <$url>';
}

class MediaCandidate {
  final String url;

  /// 'video' | 'audio' | 'image' | 'file'
  final String kind;
  final String label;

  /// 'direct' | 'og' | 'video-tag' | 'source-tag' | 'json-ld' | 'link' | 'twitter'
  final String source;
  final String? mimeHint;

  const MediaCandidate({
    required this.url,
    required this.kind,
    this.label = '',
    this.source = 'link',
    this.mimeHint,
  });

  @override
  String toString() => 'MediaCandidate($kind, $source, $url)';
}

class WebPage {
  final String url;
  final String finalUrl;
  final int statusCode;
  final String contentType;
  final String title;
  final String description;
  final String siteName;
  final String? ogImage;

  /// Cleaned main readable text (paragraphs separated by blank lines).
  final String text;

  /// Markdown rendering of the main content.
  final String markdown;
  final List<String> headings;
  final List<WebLink> links;
  final List<String> images;
  final List<MediaCandidate> media;
  final List<String> emails;
  final List<String> phones;
  final int byteLength;
  final String? error;

  bool get ok => error == null;

  const WebPage({
    required this.url,
    this.finalUrl = '',
    this.statusCode = 0,
    this.contentType = '',
    this.title = '',
    this.description = '',
    this.siteName = '',
    this.ogImage,
    this.text = '',
    this.markdown = '',
    this.headings = const [],
    this.links = const [],
    this.images = const [],
    this.media = const [],
    this.emails = const [],
    this.phones = const [],
    this.byteLength = 0,
    this.error,
  });

  factory WebPage.failure(String url, String error) =>
      WebPage(url: url, finalUrl: url, error: error);
}

class SearchResult {
  final String title;
  final String url;
  final String snippet;

  /// 'duckduckgo' | 'wikipedia'
  final String source;

  const SearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
    this.source = 'duckduckgo',
  });

  @override
  String toString() => 'SearchResult($title, $url)';
}

class WeatherDay {
  final DateTime date;
  final double maxC;
  final double minC;
  final int code;
  final double precipitationMm;
  final int precipitationProb;

  const WeatherDay({
    required this.date,
    required this.maxC,
    required this.minC,
    required this.code,
    this.precipitationMm = 0,
    this.precipitationProb = 0,
  });

  String get description => WebTools.weatherDescription(code);
}

class WeatherReport {
  final String place;
  final double lat;
  final double lon;
  final double temperatureC;
  final double apparentC;
  final int humidity;
  final double windKmh;
  final int weatherCode;

  /// Turkish WMO description.
  final String description;

  /// Up to 7 days.
  final List<WeatherDay> days;

  const WeatherReport({
    required this.place,
    required this.lat,
    required this.lon,
    required this.temperatureC,
    required this.apparentC,
    required this.humidity,
    required this.windKmh,
    required this.weatherCode,
    required this.description,
    this.days = const [],
  });

  String toTurkishSummary() {
    final sb = StringBuffer(
      '$place: ${temperatureC.round()}°C (hissedilen ${apparentC.round()}°C), '
      '$description, nem %$humidity, rüzgar ${windKmh.round()} km/s.',
    );
    if (days.isNotEmpty) {
      final d = days.first;
      sb.write(' Bugün: ${d.minC.round()}°/${d.maxC.round()}°');
      if (d.precipitationProb > 0) {
        sb.write(', %${d.precipitationProb} yağış ihtimali');
      }
      sb.write('.');
    }
    if (days.length > 1) {
      final d = days[1];
      sb.write(' Yarın: ${d.minC.round()}°/${d.maxC.round()}°, '
          '${WebTools.weatherDescription(d.code)}');
      if (d.precipitationProb > 0) {
        sb.write(', %${d.precipitationProb} yağış ihtimali');
      }
      sb.write('.');
    }
    return sb.toString();
  }
}

class NewsItem {
  final String title;
  final String link;
  final String source;
  final DateTime? published;

  const NewsItem({
    required this.title,
    required this.link,
    this.source = '',
    this.published,
  });

  @override
  String toString() => source.isEmpty ? title : '$title ($source)';
}

class CurrencyQuote {
  final String from;
  final String to;
  final double rate;
  final double amount;
  final double converted;
  final DateTime? date;

  const CurrencyQuote({
    required this.from,
    required this.to,
    required this.rate,
    required this.amount,
    required this.converted,
    this.date,
  });

  static String _fmt(double v) {
    final digits = v.abs() >= 1 || v == 0 ? 2 : 4;
    return v.toStringAsFixed(digits).replaceAll('.', ',');
  }

  /// e.g. "100 USD = 3.215,40 TRY" (Turkish decimal comma, no grouping).
  String toTurkishSummary() => '${_fmt(amount)} $from = ${_fmt(converted)} $to';
}

/// Internal block element produced while converting HTML to text/markdown.
class _Block {
  final String type; // 'p' | 'h' | 'li' | 'tr'
  final int level;
  final String text;
  final List<String> cells;
  const _Block(this.type, {this.level = 0, this.text = '', this.cells = const []});
}

// ---------------------------------------------------------------------------
// WebTools
// ---------------------------------------------------------------------------

class WebTools {
  WebTools._();

  static const userAgent = 'Mozilla/5.0 (Linux; Android 14) JARVIS-Mobile/2.0';
  static const Map<String, String> defaultHeaders = {
    'User-Agent': userAgent,
    'Accept-Language': 'tr-TR,tr;q=0.9,en;q=0.8',
  };
  static const _htmlAccept =
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
  static const _jsonAccept = 'application/json,*/*;q=0.5';
  static const _maxTextChars = 60000;

  // Attribute list pattern that tolerates '>' inside quoted values.
  static const _attrsPat = r'''((?:[^>"']|"[^"]*"|'[^']*')*)''';

  static const _videoExt = {'mp4', 'webm', 'mkv', 'mov', 'm4v', '3gp', 'avi'};
  static const _audioExt = {'mp3', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'flac'};
  static const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
  static const _fileExt = {
    'pdf', 'zip', 'apk', 'rar', '7z', 'doc', 'docx', 'xls', 'xlsx', 'ppt', //
    'pptx', 'txt', 'csv', 'epub',
  };
  static const _streamExt = {'m3u8', 'mpd'};

  static const _commonTlds = {
    'com', 'net', 'org', 'io', 'tr', 'gov', 'edu', 'co', 'me', 'tv', 'app', //
    'dev', 'ai', 'info', 'biz', 'xyz', 'us', 'uk', 'de', 'fr', 'ru', 'nl',
    'it', 'es', 'eu', 'ly', 'gl', 'gg', 'to', 'fm', 'so', 'sh', 'cc', 'in',
    'jp', 'cn', 'br', 'ca', 'au', 'ch', 'at', 'be', 'se', 'no', 'dk', 'fi',
    'pl', 'gr', 'az', 'kz', 'online', 'site', 'store', 'tech', 'blog', 'news',
    'live', 'link', 'page', 'cloud', 'pro', 'mobi', 'int', 'mil', 'gd', 'ws',
  };

  // Extensions that are never TLDs when a bare "name.ext" is given.
  static const _notTlds = {
    'txt', 'pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'mp3', 'mp4', 'doc',
    'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'exe', 'apk', 'zip', 'rar', 'dart',
    'html', 'htm', 'php', 'json', 'csv', 'wav', 'mov', 'mkv', 'avi', 'js',
    'py', 'java', 'kt', 'yaml', 'yml', 'xml', 'md', 'log', 'ini', 'bat',
  };

  static const Map<String, String> _mimeExt = {
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/quicktime': 'mov',
    'video/x-matroska': 'mkv',
    'video/3gpp': '3gp',
    'video/x-msvideo': 'avi',
    'audio/mpeg': 'mp3',
    'audio/mp3': 'mp3',
    'audio/mp4': 'm4a',
    'audio/x-m4a': 'm4a',
    'audio/aac': 'aac',
    'audio/ogg': 'ogg',
    'audio/opus': 'opus',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/flac': 'flac',
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/svg+xml': 'svg',
    'application/pdf': 'pdf',
    'application/zip': 'zip',
    'application/x-zip-compressed': 'zip',
    'application/vnd.android.package-archive': 'apk',
    'application/x-rar-compressed': 'rar',
    'application/vnd.rar': 'rar',
    'application/x-7z-compressed': '7z',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        'docx',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/vnd.ms-powerpoint': 'ppt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        'pptx',
    'application/epub+zip': 'epub',
    'application/json': 'json',
    'text/plain': 'txt',
    'text/csv': 'csv',
    'text/html': 'html',
  };

  static const Map<String, String> _entities = {
    'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
    'ccedil': 'ç', 'Ccedil': 'Ç', 'ouml': 'ö', 'Ouml': 'Ö', 'uuml': 'ü',
    'Uuml': 'Ü', 'gbreve': 'ğ', 'Gbreve': 'Ğ', 'scedil': 'ş', 'Scedil': 'Ş',
    'Idot': 'İ', 'inodot': 'ı', 'imath': 'ı', 'acirc': 'â', 'Acirc': 'Â',
    'icirc': 'î', 'Icirc': 'Î', 'ucirc': 'û', 'Ucirc': 'Û', 'auml': 'ä',
    'Auml': 'Ä', 'eacute': 'é', 'Eacute': 'É', 'egrave': 'è', 'aacute': 'á',
    'iacute': 'í', 'oacute': 'ó', 'uacute': 'ú', 'agrave': 'à', 'ntilde': 'ñ',
    'szlig': 'ß', 'hellip': '…', 'mdash': '—', 'ndash': '–', 'lsquo': '‘',
    'rsquo': '’', 'ldquo': '“', 'rdquo': '”', 'sbquo': '‚', 'bdquo': '„',
    'laquo': '«', 'raquo': '»', 'copy': '©', 'reg': '®', 'trade': '™',
    'euro': '€', 'pound': '£', 'yen': '¥', 'cent': '¢', 'deg': '°',
    'middot': '·', 'bull': '•', 'times': '×', 'divide': '÷', 'sect': '§',
    'para': '¶', 'plusmn': '±', 'frac12': '½', 'frac14': '¼', 'frac34': '¾',
    'sup2': '²', 'sup3': '³', 'micro': 'µ', 'larr': '←', 'rarr': '→',
    'uarr': '↑', 'darr': '↓', 'ensp': ' ', 'emsp': ' ', 'thinsp': ' ',
    'zwnj': '', 'zwj': '', 'shy': '', 'lrm': '', 'rlm': '', 'iexcl': '¡',
    'iquest': '¿', 'prime': '′', 'Prime': '″', 'tilde': '˜', 'circ': 'ˆ',
  };

  static final _entityRe = RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});');
  static final _wsRe = RegExp(r'[\s\u00A0\u200B\uFEFF]+');
  static final _attrRe = RegExp(
      r'''([a-zA-Z_:@][-a-zA-Z0-9_:.@]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''');
  static final _aRe = RegExp('<a\\b$_attrsPat>([\\s\\S]*?)</a\\s*>', caseSensitive: false);
  static final _emailRe = RegExp(r'(?<![\w.+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
  static final _trPhoneRe = RegExp(
      r'(?<![\d+])(?:\+90|0090|0)[\s.-]?\(?[2-5]\d{2}\)?[\s.-]?\d{3}[\s.-]?\d{2}[\s.-]?\d{2}(?!\d)');
  static final _intlPhoneRe = RegExp(
      r'(?<![\d+])\+\d{1,3}[\s.-]?(?:\(\d{1,4}\)[\s.-]?)?\d{2,4}(?:[\s.-]?\d{2,4}){1,4}(?!\d)');

  // -------------------------------------------------------------------------
  // URL helpers
  // -------------------------------------------------------------------------

  static String _trimUrlPunctuation(String input) {
    var s = input;
    s = s.replaceFirst(RegExp(r'''^[<("'\[«“]+'''), '');
    while (s.isNotEmpty) {
      final last = s[s.length - 1];
      if ('.,;:!?>"\'»”'.contains(last)) {
        s = s.substring(0, s.length - 1);
        continue;
      }
      if (last == ')' && '('.allMatches(s).length < ')'.allMatches(s).length) {
        s = s.substring(0, s.length - 1);
        continue;
      }
      if (last == ']' && '['.allMatches(s).length < ']'.allMatches(s).length) {
        s = s.substring(0, s.length - 1);
        continue;
      }
      break;
    }
    return s;
  }

  /// Adds https:// when missing; returns null when [raw] is not a URL.
  static String? normalizeUrl(String raw) {
    var s = _trimUrlPunctuation(raw.trim());
    if (s.isEmpty || RegExp(r'\s').hasMatch(s)) return null;
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final u = Uri.tryParse(s);
      if (u == null || u.host.isEmpty) return null;
      return u.toString();
    }
    if (s.startsWith('//')) s = s.substring(2);
    // Another scheme (mailto:, ftp:, javascript: ...) but not "host:port".
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(s) &&
        !RegExp(r'^[^/:]+\.[^/:]+:\d+').hasMatch(s)) {
      return null;
    }
    final m = RegExp(r'^((?:[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?\.)+(\p{L}{2,}))(:\d{1,5})?([/?#].*)?$',
            unicode: true)
        .firstMatch(s);
    if (m == null) return null;
    final host = m.group(1)!.toLowerCase();
    final tld = m.group(2)!.toLowerCase();
    if (_notTlds.contains(tld) && !host.startsWith('www.')) return null;
    final u = Uri.tryParse('https://$s');
    if (u == null || u.host.isEmpty) return null;
    return u.toString();
  }

  static final _urlInTextRe = RegExp(
      r'''(?:https?://[^\s<>"'`]+)|(?<![@\w.\-/])(?:www\.)?(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d{2,5})?(?:[/?#][^\s<>"'`]*)?''',
      caseSensitive: false);

  /// Extracts http(s) URLs and bare domains like 'youtube.com/watch?v=..'.
  /// Results are normalized (https:// added) and deduplicated.
  static List<String> extractUrls(String text) {
    final out = <String>[];
    final seen = <String>{};
    for (final m in _urlInTextRe.allMatches(text)) {
      final s = _trimUrlPunctuation(m.group(0)!);
      if (s.isEmpty) continue;
      final lower = s.toLowerCase();
      if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
        final host = lower.split(RegExp(r'[/:?#]')).first;
        final tld = host.split('.').last;
        if (!host.startsWith('www.') && !_commonTlds.contains(tld)) continue;
        // Skip e-mail addresses (the part after '@' is excluded by regex).
        final end = m.end;
        if (end < text.length && text[end] == '@') continue;
      }
      final n = normalizeUrl(s);
      if (n != null && seen.add(n)) out.add(n);
    }
    return out;
  }

  static String _extOf(String url) {
    final u = Uri.tryParse(url.trim());
    final path = u?.path ?? url;
    final seg = path.split('/').last;
    final dot = seg.lastIndexOf('.');
    if (dot < 0 || dot == seg.length - 1) return '';
    return seg.substring(dot + 1).toLowerCase();
  }

  /// True when the URL path ends with a known media/document extension.
  static bool looksLikeDirectMedia(String url) {
    final e = _extOf(url);
    if (e.isEmpty) return false;
    return _videoExt.contains(e) ||
        _audioExt.contains(e) ||
        _imageExt.contains(e) ||
        _fileExt.contains(e);
  }

  static bool _isStream(String url) => _streamExt.contains(_extOf(url));

  /// 'video' | 'audio' | 'image' | 'file'
  static String kindForUrl(String url) {
    final e = _extOf(url);
    if (_videoExt.contains(e) || _streamExt.contains(e)) return 'video';
    if (_audioExt.contains(e)) return 'audio';
    if (_imageExt.contains(e) || e == 'svg' || e == 'bmp') return 'image';
    return 'file';
  }

  static String? _kindForMime(String contentType) {
    final ct = contentType.toLowerCase();
    if (ct.startsWith('video/') || ct.contains('mpegurl') || ct.contains('dash+xml')) return 'video';
    if (ct.startsWith('audio/')) return 'audio';
    if (ct.startsWith('image/')) return 'image';
    if (ct.isNotEmpty) return 'file';
    return null;
  }

  static String? _fileNameFromDisposition(String cd) {
    final star = RegExp(r'''filename\*\s*=\s*([^']*)'[^']*'([^;]+)''', caseSensitive: false)
        .firstMatch(cd);
    if (star != null) {
      final v = star.group(2)!.trim().replaceAll('"', '');
      try {
        final charset = star.group(1)!.trim().toLowerCase();
        if (charset == 'iso-8859-1' || charset == 'latin1') {
          return Uri.decodeComponent(v.replaceAll('+', '%2B'));
        }
        return Uri.decodeComponent(v);
      } catch (_) {
        return v;
      }
    }
    final q = RegExp(r'filename\s*=\s*"((?:[^"\\]|\\.)*)"', caseSensitive: false).firstMatch(cd);
    if (q != null) return q.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    final p = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(cd);
    if (p != null) return p.group(1)!.trim();
    return null;
  }

  /// Repairs UTF-8 bytes that were mis-decoded as Latin-1 (common for headers).
  static String _repairMojibake(String s) {
    if (!s.codeUnits.any((c) => c >= 0x80) || s.codeUnits.any((c) => c > 0xFF)) {
      return s;
    }
    try {
      return utf8.decode(latin1.encode(s));
    } catch (_) {
      return s;
    }
  }

  /// Sanitized file name; the extension is inferred from [contentType] when
  /// the name has none.
  static String guessFileName(String url, {String? contentDisposition, String? contentType}) {
    String? name;
    if (contentDisposition != null && contentDisposition.trim().isNotEmpty) {
      name = _fileNameFromDisposition(contentDisposition);
      if (name != null) name = _repairMojibake(name);
    }
    if (name == null || name.trim().isEmpty) {
      final u = Uri.tryParse(url.trim());
      final segs = (u?.pathSegments ?? const <String>[]).where((e) => e.isNotEmpty).toList();
      if (segs.isNotEmpty) {
        name = segs.last;
        try {
          name = Uri.decodeComponent(name);
        } catch (_) {
          // keep the raw segment
        }
      }
    }
    name ??= '';
    // Keep only the base name (strip any path the server might send).
    name = name.split(RegExp(r'[\\/]')).last;
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');

    final ct = (contentType ?? '').split(';').first.trim().toLowerCase();
    final hasExt = RegExp(r'\.[A-Za-z0-9]{1,5}$').hasMatch(name);
    if (name.isEmpty) name = 'indirilen_dosya';
    if (!hasExt) {
      final ext = _mimeExt[ct];
      if (ext != null) name = '$name.$ext';
    }
    if (name.length > 150) {
      final m = RegExp(r'\.[A-Za-z0-9]{1,5}$').firstMatch(name);
      final ext = m?.group(0) ?? '';
      name = name.substring(0, 150 - ext.length) + ext;
    }
    return name;
  }

  // -------------------------------------------------------------------------
  // Text helpers
  // -------------------------------------------------------------------------

  /// Decodes named (common) and numeric HTML entities.
  static String decodeEntities(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(_entityRe, (m) {
      final e = m.group(1)!;
      if (e.startsWith('#')) {
        final isHex = e.length > 1 && (e[1] == 'x' || e[1] == 'X');
        final cp = int.tryParse(isHex ? e.substring(2) : e.substring(1), radix: isHex ? 16 : 10);
        if (cp == null || cp <= 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
          return m.group(0)!;
        }
        if (cp == 0xA0) return ' ';
        return String.fromCharCode(cp);
      }
      return _entities[e] ?? m.group(0)!;
    });
  }

  static String _collapse(String s) => s.replaceAll(_wsRe, ' ').trim();

  static String _stripTags(String s, {String replacement = ' '}) =>
      s.replaceAll(RegExp(r'<[^>]*>'), replacement);

  static String _inlineText(String html) => _collapse(decodeEntities(_stripTags(html)));

  static Map<String, String> _attrs(String inner) {
    final out = <String, String>{};
    for (final m in _attrRe.allMatches(inner)) {
      final k = m.group(1)!.toLowerCase();
      out.putIfAbsent(k, () => m.group(2) ?? m.group(3) ?? m.group(4) ?? '');
    }
    return out;
  }

  static RegExp _openTag(String name) => RegExp('<$name(?=[\\s/>])$_attrsPat>', caseSensitive: false);

  static String _removeBlocks(String html, List<String> tags) {
    var s = html;
    for (final t in tags) {
      s = s.replaceAll(
          RegExp('<$t(?=[\\s/>])$_attrsPat>[\\s\\S]*?</$t\\s*>', caseSensitive: false), ' ');
      // Self-closing or unclosed leftovers.
      s = s.replaceAll(RegExp('</?$t(?=[\\s/>])$_attrsPat>', caseSensitive: false), ' ');
    }
    return s;
  }

  static String? _resolve(Uri base, String raw) {
    final s = decodeEntities(raw).trim();
    if (s.isEmpty || s.startsWith('#')) return null;
    final l = s.toLowerCase();
    if (l.startsWith('javascript:') ||
        l.startsWith('data:') ||
        l.startsWith('mailto:') ||
        l.startsWith('tel:') ||
        l.startsWith('about:') ||
        l.startsWith('blob:')) {
      return null;
    }
    try {
      final u = base.resolve(s);
      if ((u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) return null;
      return u.removeFragment().toString();
    } catch (_) {
      return null;
    }
  }

  static String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

  static const _inlineTags = {
    'a', 'b', 'i', 'em', 'strong', 'span', 'code', 'sup', 'sub', 'small', //
    'mark', 'abbr', 'u', 's', 'time', 'label', 'font', 'q', 'cite', 'kbd',
    'var', 'samp', 'bdi', 'bdo', 'del', 'ins', 'big', 'tt', 'wbr', 'data',
  };

  static String _flatten(String html) => html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('\n', ' ');

  static List<_Block> _toBlocks(String region) {
    var s = region.replaceAll(RegExp(r'\s+'), ' ');
    // Table rows -> marker + cells.
    s = s.replaceAllMapped(RegExp(r'<tr\b[^>]*>([\s\S]*?)</tr\s*>', caseSensitive: false), (m) {
      final inner = m.group(1)!;
      final cells = RegExp(r'<t[dh]\b[^>]*>([\s\S]*?)</t[dh]\s*>', caseSensitive: false)
          .allMatches(inner)
          .map((c) => _flatten(c.group(1)!))
          .toList();
      final row = cells.isEmpty ? _flatten(inner) : cells.join('\uE004');
      return '\n\uE003$row\n';
    });
    // Headings.
    s = s.replaceAllMapped(RegExp(r'<h([1-6])\b[^>]*>([\s\S]*?)</h\1\s*>', caseSensitive: false),
        (m) => '\n\n\uE000${m.group(1)}${_flatten(m.group(2)!)}\n\n');
    s = s.replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n\uE002');
    s = s.replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(
        RegExp(
            r'</?(?:p|div|section|article|main|blockquote|pre|ul|ol|dl|dt|dd|table|thead|tbody|tfoot|figure|figcaption|hr|address|details|summary|center|caption|header|footer|nav|aside|body|html)\b[^>]*>',
            caseSensitive: false),
        '\n\n');
    s = s.replaceAllMapped(RegExp(r'</?([a-zA-Z][a-zA-Z0-9-]*)\b[^>]*>'),
        (m) => _inlineTags.contains(m.group(1)!.toLowerCase()) ? '' : ' ');
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = decodeEntities(s);

    final blocks = <_Block>[];
    final para = <String>[];
    var pendingLi = false;
    void flush() {
      if (para.isNotEmpty) {
        blocks.add(_Block('p', text: para.join('\n')));
        para.clear();
      }
    }

    final markerRe = RegExp('[\uE000-\uE004]');
    for (final rawLine in s.split('\n')) {
      final line = _collapse(rawLine);
      if (line.isEmpty) {
        flush();
        continue;
      }
      final c0 = line.codeUnitAt(0);
      if (c0 == 0xE000 && line.length >= 2) {
        flush();
        pendingLi = false;
        final lvl = int.tryParse(line[1]) ?? 2;
        final t = _collapse(line.substring(2).replaceAll(markerRe, ''));
        if (t.isNotEmpty) blocks.add(_Block('h', level: lvl, text: t));
        continue;
      }
      if (c0 == 0xE002) {
        flush();
        final t = _collapse(line.substring(1).replaceAll(markerRe, ''));
        if (t.isEmpty) {
          pendingLi = true;
        } else {
          blocks.add(_Block('li', text: t));
          pendingLi = false;
        }
        continue;
      }
      if (c0 == 0xE003) {
        flush();
        pendingLi = false;
        final cells = line
            .substring(1)
            .split('\uE004')
            .map((e) => _collapse(e.replaceAll(markerRe, '')))
            .where((e) => e.isNotEmpty)
            .toList();
        if (cells.isNotEmpty) blocks.add(_Block('tr', text: cells.join(' | '), cells: cells));
        continue;
      }
      final t = _collapse(line.replaceAll(markerRe, ''));
      if (t.isEmpty) continue;
      if (pendingLi) {
        flush();
        blocks.add(_Block('li', text: t));
        pendingLi = false;
        continue;
      }
      para.add(t);
    }
    flush();

    // Drop consecutive duplicates.
    final out = <_Block>[];
    for (final b in blocks) {
      if (out.isNotEmpty && out.last.type == b.type && out.last.text == b.text) continue;
      out.add(b);
    }
    return out;
  }

  static bool _tight(_Block? prev, _Block cur) =>
      prev != null && prev.type == cur.type && (cur.type == 'li' || cur.type == 'tr');

  static String _blocksToText(List<_Block> blocks) {
    final sb = StringBuffer();
    _Block? prev;
    for (final b in blocks) {
      if (prev != null) sb.write(_tight(prev, b) ? '\n' : '\n\n');
      sb.write(b.type == 'li' ? '• ${b.text}' : b.text);
      prev = b;
    }
    return sb.toString();
  }

  static String _blocksToMarkdown(List<_Block> blocks, String title) {
    final sb = StringBuffer();
    _Block? prev;
    var skippedTitle = false;
    for (final b in blocks) {
      String chunk;
      switch (b.type) {
        case 'h':
          if (!skippedTitle && b.text == title) {
            skippedTitle = true;
            continue;
          }
          chunk = '${b.level <= 2 ? '##' : '###'} ${b.text}';
          break;
        case 'li':
          chunk = '- ${b.text}';
          break;
        case 'tr':
          final cells = b.cells.map((c) => c.replaceAll('|', r'\|')).toList();
          chunk = '| ${cells.join(' | ')} |';
          if (prev == null || prev.type != 'tr') {
            chunk += '\n|${List.filled(cells.length, ' --- |').join()}';
          }
          break;
        default:
          chunk = b.text.replaceAll('\n', '  \n');
      }
      if (sb.isNotEmpty) sb.write(_tight(prev, b) ? '\n' : '\n\n');
      sb.write(chunk);
      prev = b;
    }
    return sb.toString();
  }

  static String _phoneDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static void _addPhones(String text, List<String> out, Set<String> seen) {
    for (final m in _trPhoneRe.allMatches(text)) {
      if (out.length >= 20) return;
      final raw = m.group(0)!;
      final d = _phoneDigits(raw);
      if (d.length < 10) continue;
      final ten = d.substring(d.length - 10);
      if (!seen.add(ten)) continue;
      final intl = raw.startsWith('+') || raw.startsWith('00');
      final f = '${ten.substring(0, 3)} ${ten.substring(3, 6)} ${ten.substring(6, 8)} ${ten.substring(8)}';
      out.add(intl ? '+90 $f' : '0$f');
    }
    for (final m in _intlPhoneRe.allMatches(text)) {
      if (out.length >= 20) return;
      final raw = _collapse(m.group(0)!);
      final d = _phoneDigits(raw);
      if (d.length < 8 || d.length > 15) continue;
      final key = d.length >= 10 ? d.substring(d.length - 10) : d;
      if (!seen.add(key)) continue;
      out.add(raw);
    }
  }

  static void _addEmail(String raw, List<String> out, Set<String> seen) {
    if (out.length >= 20) return;
    final e = raw.trim().replaceAll(RegExp(r'^mailto:', caseSensitive: false), '').split('?').first;
    if (!RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$').hasMatch(e)) return;
    if (RegExp(r'\.(png|jpe?g|gif|webp|svg|bmp|ico|avif)$', caseSensitive: false).hasMatch(e)) return;
    if (seen.add(e.toLowerCase())) out.add(e);
  }

  // -------------------------------------------------------------------------
  // HTML parsing
  // -------------------------------------------------------------------------

  /// Pure HTML -> [WebPage] conversion (no network).
  static WebPage parseHtml(String html,
          {required String url, String finalUrl = '', int statusCode = 200, String contentType = 'text/html'}) =>
      _parse(html,
          url: url,
          finalUrl: finalUrl,
          statusCode: statusCode,
          contentType: contentType,
          byteLength: html.length);

  static WebPage _parse(String html,
      {required String url,
      required String finalUrl,
      required int statusCode,
      required String contentType,
      required int byteLength}) {
    final fu = finalUrl.isNotEmpty ? finalUrl : url;
    var base = Uri.tryParse(fu) ?? Uri();
    final doc = html.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');

    final baseTag = _openTag('base').firstMatch(doc);
    if (baseTag != null) {
      final href = _attrs(baseTag.group(1)!)['href'];
      if (href != null && href.trim().isNotEmpty) {
        try {
          base = base.resolve(decodeEntities(href.trim()));
        } catch (_) {
          // keep previous base
        }
      }
    }

    // Meta tags.
    final metas = <(String, String)>[];
    for (final m in _openTag('meta').allMatches(doc)) {
      final a = _attrs(m.group(1)!);
      final key = (a['property'] ?? a['name'] ?? a['itemprop'] ?? '').toLowerCase().trim();
      final content = a['content'];
      if (key.isEmpty || content == null) continue;
      metas.add((key, _collapse(decodeEntities(content))));
    }
    String? meta(String k) {
      for (final e in metas) {
        if (e.$1 == k && e.$2.isNotEmpty) return e.$2;
      }
      return null;
    }

    final media = <MediaCandidate>[];
    final mediaSeen = <String>{};
    void addMedia(String? raw, String kind, String source, {String label = '', String? mime}) {
      if (raw == null) return;
      final u = _resolve(base, raw);
      if (u == null || !mediaSeen.add(u)) return;
      media.add(MediaCandidate(
          url: u, kind: kind, label: label, source: source, mimeHint: (mime == null || mime.isEmpty) ? null : mime));
    }

    // JSON-LD (before scripts are stripped).
    final jsonLdUrls = <String>[];
    for (final m in RegExp(r'''<script\b[^>]*application/ld\+json[^>]*>([\s\S]*?)</script\s*>''',
            caseSensitive: false)
        .allMatches(doc)) {
      for (final v in RegExp(r'''"(?:contentUrl|embedUrl)"\s*:\s*"((?:[^"\\]|\\.)*)"''').allMatches(m.group(1)!)) {
        var raw = v.group(1)!;
        try {
          raw = jsonDecode('"$raw"') as String;
        } catch (_) {
          raw = raw.replaceAll(r'\/', '/');
        }
        jsonLdUrls.add(raw);
      }
    }

    final clean = _removeBlocks(doc, const ['script', 'style', 'noscript', 'svg', 'template', 'iframe', 'object', 'canvas']);

    // Title / description / site name.
    final titleTag = RegExp(r'<title\b[^>]*>([\s\S]*?)</title\s*>', caseSensitive: false).firstMatch(clean);
    final h1 = RegExp(r'<h1\b[^>]*>([\s\S]*?)</h1\s*>', caseSensitive: false).firstMatch(clean);
    var title = meta('og:title') ?? '';
    if (title.isEmpty && titleTag != null) title = _inlineText(titleTag.group(1)!);
    if (title.isEmpty && h1 != null) title = _inlineText(h1.group(1)!);
    final description = meta('og:description') ?? meta('description') ?? meta('twitter:description') ?? '';
    var host = base.host;
    if (host.startsWith('www.')) host = host.substring(4);
    final siteName = meta('og:site_name') ?? host;
    final ogImageRaw = meta('og:image') ?? meta('og:image:url') ?? meta('og:image:secure_url') ?? meta('twitter:image');
    final ogImage = ogImageRaw == null ? null : _resolve(base, ogImageRaw);

    // Meta media.
    final videoType = meta('og:video:type');
    final audioType = meta('og:audio:type');
    for (final e in metas) {
      switch (e.$1) {
        case 'og:video':
        case 'og:video:url':
        case 'og:video:secure_url':
          addMedia(e.$2, 'video', 'og', label: title, mime: videoType);
          break;
        case 'og:audio':
        case 'og:audio:url':
        case 'og:audio:secure_url':
          addMedia(e.$2, 'audio', 'og', label: title, mime: audioType);
          break;
        case 'twitter:player:stream':
          addMedia(e.$2, 'video', 'twitter', label: title, mime: meta('twitter:player:stream:content_type'));
          break;
      }
    }

    // <video>/<audio> elements.
    final sourceTagCandidates = <(String, String, String?)>[];
    for (final m in RegExp('<(video|audio)\\b$_attrsPat>([\\s\\S]*?)</\\1\\s*>', caseSensitive: false)
        .allMatches(clean)) {
      final kind = m.group(1)!.toLowerCase();
      final a = _attrs(m.group(2)!);
      addMedia(a['src'] ?? a['data-src'], kind, 'video-tag', label: title, mime: a['type']);
      for (final s in _openTag('source').allMatches(m.group(3)!)) {
        final sa = _attrs(s.group(1)!);
        final src = sa['src'] ?? sa['data-src'];
        if (src != null) sourceTagCandidates.add((src, kind, sa['type']));
      }
    }
    for (final m in RegExp('<(video|audio)\\b$_attrsPat>', caseSensitive: false).allMatches(clean)) {
      final a = _attrs(m.group(2)!);
      addMedia(a['src'] ?? a['data-src'], m.group(1)!.toLowerCase(), 'video-tag', label: title, mime: a['type']);
    }
    for (final s in sourceTagCandidates) {
      addMedia(s.$1, s.$2, 'source-tag', label: title, mime: s.$3);
    }
    for (final raw in jsonLdUrls) {
      final u = _resolve(base, raw);
      if (u != null && (looksLikeDirectMedia(u) || _isStream(u))) {
        addMedia(u, kindForUrl(u), 'json-ld', label: title);
      }
    }

    // Links, e-mails, phones.
    final links = <WebLink>[];
    final linkSeen = <String>{};
    final emails = <String>[];
    final emailSeen = <String>{};
    final phones = <String>[];
    final phoneSeen = <String>{};
    final linkMedia = <(String, String)>[];
    for (final m in _aRe.allMatches(clean)) {
      final a = _attrs(m.group(1)!);
      final href = a['href'];
      if (href == null) continue;
      final hl = href.trim().toLowerCase();
      if (hl.startsWith('mailto:')) {
        _addEmail(Uri.decodeFull(decodeEntities(href.trim()).replaceAll('%40', '@')), emails, emailSeen);
        continue;
      }
      if (hl.startsWith('tel:')) {
        _addPhones(decodeEntities(href.trim().substring(4)), phones, phoneSeen);
        continue;
      }
      final u = _resolve(base, href);
      if (u == null) continue;
      var text = _inlineText(m.group(2)!);
      if (text.isEmpty) text = _collapse(decodeEntities(a['title'] ?? a['aria-label'] ?? ''));
      if (looksLikeDirectMedia(u)) linkMedia.add((u, text));
      if (links.length < 200 && linkSeen.add(u)) links.add(WebLink(text, u));
    }
    for (final lm in linkMedia) {
      addMedia(lm.$1, kindForUrl(lm.$1), 'link', label: lm.$2.isNotEmpty ? lm.$2 : guessFileName(lm.$1));
    }

    // Images.
    final images = <String>[];
    final imgSeen = <String>{};
    for (final m in _openTag('img').allMatches(clean)) {
      if (images.length >= 60) break;
      final a = _attrs(m.group(1)!);
      var src = a['src'];
      if (src == null || src.trim().isEmpty || src.trim().toLowerCase().startsWith('data:')) {
        src = a['data-src'] ?? a['data-lazy-src'] ?? a['data-original'];
      }
      if (src == null) continue;
      final u = _resolve(base, src);
      if (u != null && imgSeen.add(u)) {
        images.add(u);
        addMedia(u, 'image', 'img-tag', label: a['alt'] ?? a['title'] ?? '');
      }
    }

    // Main readable content.
    final mainHtml = _removeBlocks(clean, const ['nav', 'footer', 'header', 'aside', 'form', 'button', 'select', 'dialog']);
    String bodyOf(String s) {
      final bm = RegExp(r'<body\b[^>]*>', caseSensitive: false).firstMatch(s);
      if (bm == null) {
        return s.replaceAll(RegExp(r'<head\b[\s\S]*?</head\s*>', caseSensitive: false), ' ');
      }
      final rest = s.substring(bm.end);
      final end = rest.toLowerCase().lastIndexOf('</body');
      return end >= 0 ? rest.substring(0, end) : rest;
    }

    final body = bodyOf(mainHtml);
    String? region;
    final art = RegExp(r'<article\b[^>]*>([\s\S]*)</article\s*>', caseSensitive: false).firstMatch(body);
    if (art != null) {
      region = art.group(1);
    } else {
      final mn = RegExp(r'<main\b[^>]*>([\s\S]*)</main\s*>', caseSensitive: false).firstMatch(body);
      if (mn != null) region = mn.group(1);
    }
    var blocks = _toBlocks(region ?? body);
    var text = _blocksToText(blocks);
    if (region != null && text.length < 200) {
      final bodyBlocks = _toBlocks(body);
      final bodyText = _blocksToText(bodyBlocks);
      if (bodyText.length > text.length) {
        blocks = bodyBlocks;
        text = bodyText;
      }
    }
    final headings = blocks.where((b) => b.type == 'h').map((b) => b.text).take(50).toList();
    text = _truncate(text, _maxTextChars);

    final md = StringBuffer();
    if (title.isNotEmpty) md.write('# $title\n\n');
    if (description.isNotEmpty) md.write('> $description\n\n');
    md.write(_truncate(_blocksToMarkdown(blocks, title), _maxTextChars + 10000));

    // E-mails / phones from the whole visible page (footers included).
    final fullText = _collapse(decodeEntities(_stripTags(bodyOf(clean))));
    for (final m in _emailRe.allMatches(fullText)) {
      _addEmail(m.group(0)!, emails, emailSeen);
    }
    _addPhones(fullText, phones, phoneSeen);

    return WebPage(
      url: url,
      finalUrl: fu,
      statusCode: statusCode,
      contentType: contentType,
      title: title,
      description: description,
      siteName: siteName,
      ogImage: ogImage,
      text: text,
      markdown: md.toString().trim(),
      headings: headings,
      links: links,
      images: images,
      media: media,
      emails: emails,
      phones: phones,
      byteLength: byteLength,
    );
  }

  // -------------------------------------------------------------------------
  // Networking helpers
  // -------------------------------------------------------------------------

  static Future<T> _using<T>(http.Client? client, Future<T> Function(http.Client c) body) async {
    final c = client ?? http.Client();
    try {
      return await body(c);
    } finally {
      if (client == null) c.close();
    }
  }

  static Future<({int status, String body})?> _getText(http.Client c, Uri uri,
      {String accept = '*/*', Duration timeout = const Duration(seconds: 15)}) async {
    try {
      final res = await c.get(uri, headers: {...defaultHeaders, 'Accept': accept}).timeout(timeout);
      return (status: res.statusCode, body: utf8.decode(res.bodyBytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  static Future<Object?> _getJson(http.Client c, Uri uri) async {
    final r = await _getText(c, uri, accept: _jsonAccept);
    if (r == null || r.status != 200) return null;
    try {
      return jsonDecode(r.body);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _discard(http.StreamedResponse res) async {
    try {
      await res.stream.listen((_) {}).cancel().timeout(const Duration(seconds: 3));
    } catch (_) {
      return;
    }
  }

  static Future<Uint8List> _readLimited(Stream<List<int>> stream, int maxBytes) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      final remaining = maxBytes - b.length;
      if (chunk.length >= remaining) {
        if (remaining > 0) b.add(chunk.sublist(0, remaining));
        break;
      }
      b.add(chunk);
    }
    return b.takeBytes();
  }

  static const Map<int, int> _cp1254 = {
    0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
    0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
    0x8B: 0x2039, 0x8C: 0x0152, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
    0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
    0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9F: 0x0178,
    0xD0: 0x011E, 0xDD: 0x0130, 0xDE: 0x015E, 0xF0: 0x011F, 0xFD: 0x0131,
    0xFE: 0x015F,
  };

  /// UTF-8 (allowMalformed) by default. Only when the bytes are NOT valid
  /// UTF-8 and the page declares a Turkish/Latin single-byte charset is a
  /// single-byte decoding used.
  static String _decodeBytes(List<int> bytes, String contentType) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      // fall through
    }
    var cs = RegExp(r'charset\s*=\s*"?([\w-]+)', caseSensitive: false).firstMatch(contentType)?.group(1);
    if (cs == null) {
      final head = latin1.decode(bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes, allowInvalid: true);
      cs = RegExp(r'''<meta[^>]+charset\s*=\s*["']?\s*([\w-]+)''', caseSensitive: false).firstMatch(head)?.group(1);
    }
    final c = (cs ?? '').toLowerCase();
    const turkish = {'iso-8859-9', 'iso8859-9', 'windows-1254', 'cp1254', 'latin5', 'x-cp1254'};
    const western = {'iso-8859-1', 'iso8859-1', 'windows-1252', 'cp1252', 'latin1'};
    if (turkish.contains(c) || western.contains(c)) {
      final sb = StringBuffer();
      final tr = turkish.contains(c);
      for (final b in bytes) {
        final mapped = _cp1254[b];
        if (mapped != null && (tr || (b >= 0x80 && b <= 0x9F))) {
          sb.writeCharCode(mapped);
        } else {
          sb.writeCharCode(b);
        }
      }
      return sb.toString();
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static bool _sniffHtml(String body) {
    final head = body.length > 1024 ? body.substring(0, 1024) : body;
    final l = head.trimLeft().toLowerCase();
    return l.startsWith('<!doctype html') || l.startsWith('<html') || l.contains('<body') || l.contains('<head');
  }

  static const _challengeMarkers = [
    'g-recaptcha', 'h-captcha', 'hcaptcha.com', 'cf-challenge', 'challenge-platform', //
    'cf-turnstile', 'captcha-delivery', 'verify you are human', 'are you a robot',
    'unusual traffic', 'anomaly-modal', 'just a moment...', 'robot olmadığınızı',
  ];

  static bool _looksLikeChallenge(String html, String text) {
    if (text.length > 1500) return false;
    final l = (html.length > 200000 ? html.substring(0, 200000) : html).toLowerCase();
    return _challengeMarkers.any(l.contains);
  }

  static String _errText(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  // -------------------------------------------------------------------------
  // Page fetching / probing / media
  // -------------------------------------------------------------------------

  static Future<WebPage> fetchPage(String url, {http.Client? client, int maxBytes = 4000000}) async {
    final norm = normalizeUrl(url);
    if (norm == null) return WebPage.failure(url, 'Geçersiz web adresi: $url');
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final req = http.Request('GET', Uri.parse(norm))
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers.addAll({...defaultHeaders, 'Accept': _htmlAccept});
      final res = await c.send(req).timeout(const Duration(seconds: 20));
      final finalUrl = res.request?.url.toString() ?? norm;
      final ct = res.headers['content-type'] ?? '';
      final ctl = ct.toLowerCase();
      if (res.statusCode >= 400) {
        await _discard(res);
        final blocked = res.statusCode == 403 || res.statusCode == 429;
        return WebPage(
          url: norm,
          finalUrl: finalUrl,
          statusCode: res.statusCode,
          contentType: ct,
          error: blocked
              ? 'Site erişimi engelledi (HTTP ${res.statusCode}); sayfa okunamadı.'
              : 'Sayfa alınamadı (HTTP ${res.statusCode}).',
        );
      }
      var host = Uri.tryParse(finalUrl)?.host ?? '';
      if (host.startsWith('www.')) host = host.substring(4);
      final isHtml = ctl.contains('html') || ctl.contains('xml');
      final isText = ctl.startsWith('text/') || ctl.contains('json') || ctl.contains('javascript');
      if (!isHtml && !isText && (ctl.isNotEmpty || looksLikeDirectMedia(finalUrl))) {
        await _discard(res);
        final name = guessFileName(finalUrl, contentDisposition: res.headers['content-disposition'], contentType: ct);
        final kind = _kindForMime(ctl) ?? kindForUrl(name);
        final kindFinal = (kind == 'file' && kindForUrl(name) != 'file') ? kindForUrl(name) : kind;
        return WebPage(
          url: norm,
          finalUrl: finalUrl,
          statusCode: res.statusCode,
          contentType: ct,
          title: name,
          siteName: host,
          markdown: '# $name',
          media: [
            MediaCandidate(
                url: finalUrl,
                kind: kindFinal,
                label: name,
                source: 'direct',
                mimeHint: ct.isEmpty ? null : ct.split(';').first.trim()),
          ],
          byteLength: res.contentLength ?? 0,
        );
      }
      final bytes = await _readLimited(res.stream, maxBytes).timeout(const Duration(seconds: 25));
      final body = _decodeBytes(bytes, ct);
      if (isHtml || (!isText && _sniffHtml(body))) {
        final page = _parse(body,
            url: norm, finalUrl: finalUrl, statusCode: res.statusCode, contentType: ct, byteLength: bytes.length);
        if (_looksLikeChallenge(body, page.text)) {
          return WebPage(
            url: norm,
            finalUrl: finalUrl,
            statusCode: res.statusCode,
            contentType: ct,
            title: page.title,
            byteLength: bytes.length,
            error: 'Site bir robot doğrulaması (CAPTCHA) istedi; sayfa okunamadı.',
          );
        }
        return page;
      }
      // Plain text / JSON.
      final name = guessFileName(finalUrl, contentType: ct);
      final text = _truncate(body.trim(), _maxTextChars);
      final isJson = ctl.contains('json');
      final emails = <String>[];
      final phones = <String>[];
      for (final m in _emailRe.allMatches(text)) {
        _addEmail(m.group(0)!, emails, <String>{});
      }
      _addPhones(text, phones, <String>{});
      return WebPage(
        url: norm,
        finalUrl: finalUrl,
        statusCode: res.statusCode,
        contentType: ct,
        title: name,
        siteName: host,
        text: text,
        markdown: isJson ? '# $name\n\n```json\n$text\n```' : '# $name\n\n$text',
        emails: emails.toSet().toList(),
        phones: phones,
        byteLength: bytes.length,
      );
    } on TimeoutException {
      return WebPage.failure(norm, 'Sayfa zaman aşımına uğradı.');
    } catch (e) {
      return WebPage.failure(norm, 'Sayfa alınamadı: ${_errText(e)}');
    } finally {
      if (own) c.close();
    }
  }

  /// HEAD request, falling back to a ranged GET (Range: bytes=0-0).
  static Future<({bool ok, String finalUrl, String contentType, int? length, String fileName, String? error})>
      probeUrl(String url, {http.Client? client}) async {
    final norm = normalizeUrl(url);
    if (norm == null) {
      return (
        ok: false,
        finalUrl: url,
        contentType: '',
        length: null,
        fileName: guessFileName(url),
        error: 'Geçersiz web adresi.'
      );
    }
    return _using(client, (c) async {
      var lastError = '';
      try {
        final req = http.Request('HEAD', Uri.parse(norm))
          ..followRedirects = true
          ..maxRedirects = 5
          ..headers.addAll({...defaultHeaders, 'Accept': '*/*'});
        final res = await c.send(req).timeout(const Duration(seconds: 15));
        await _discard(res);
        if (res.statusCode < 400) {
          final fu = res.request?.url.toString() ?? norm;
          final ct = res.headers['content-type'] ?? '';
          var len = int.tryParse(res.headers['content-length'] ?? '') ?? res.contentLength;
          if (len != null && len <= 0) len = null;
          return (
            ok: true,
            finalUrl: fu,
            contentType: ct,
            length: len,
            fileName: guessFileName(fu, contentDisposition: res.headers['content-disposition'], contentType: ct),
            error: null
          );
        }
        lastError = 'HTTP ${res.statusCode}';
      } on TimeoutException {
        lastError = 'zaman aşımı';
      } catch (e) {
        lastError = _errText(e);
      }
      try {
        final req = http.Request('GET', Uri.parse(norm))
          ..followRedirects = true
          ..maxRedirects = 5
          ..headers.addAll({...defaultHeaders, 'Accept': '*/*', 'Range': 'bytes=0-0'});
        final res = await c.send(req).timeout(const Duration(seconds: 15));
        await _discard(res);
        final fu = res.request?.url.toString() ?? norm;
        final ct = res.headers['content-type'] ?? '';
        int? len;
        final cr = res.headers['content-range'];
        if (cr != null) len = int.tryParse(RegExp(r'/(\d+)').firstMatch(cr)?.group(1) ?? '');
        if (len == null && res.statusCode == 200) {
          len = int.tryParse(res.headers['content-length'] ?? '') ?? res.contentLength;
        }
        if (len != null && len <= 0) len = null;
        final name = guessFileName(fu, contentDisposition: res.headers['content-disposition'], contentType: ct);
        if (res.statusCode < 400) {
          return (ok: true, finalUrl: fu, contentType: ct, length: len, fileName: name, error: null);
        }
        return (
          ok: false,
          finalUrl: fu,
          contentType: ct,
          length: null,
          fileName: name,
          error: 'Dosyaya erişilemedi (HTTP ${res.statusCode}).'
        );
      } on TimeoutException {
        lastError = 'zaman aşımı';
      } catch (e) {
        lastError = _errText(e);
      }
      return (
        ok: false,
        finalUrl: norm,
        contentType: '',
        length: null,
        fileName: guessFileName(norm),
        error: 'Dosyaya erişilemedi: $lastError'
      );
    });
  }

  /// Direct media URL -> single 'direct' candidate; otherwise the media
  /// candidates discovered on the fetched page.
  static Future<List<MediaCandidate>> findMedia(String url, {http.Client? client}) async {
    final norm = normalizeUrl(url);
    if (norm == null) return const [];
    if (looksLikeDirectMedia(norm)) {
      final name = guessFileName(norm);
      return [MediaCandidate(url: norm, kind: kindForUrl(norm), label: name, source: 'direct')];
    }
    final page = await fetchPage(norm, client: client);
    return page.media;
  }

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------

  static Future<List<SearchResult>> search(String query, {http.Client? client, int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty || limit <= 0) return const [];
    try {
      return await _using(client, (c) async {
        var results = <SearchResult>[];
        final r = await _getText(c, Uri.https('html.duckduckgo.com', '/html/', {'q': q, 'kl': 'tr-tr'}),
            accept: _htmlAccept);
        if (r != null && r.status == 200) results = parseDuckDuckGo(r.body, limit: limit);
        if (results.isEmpty) results = await _wikiSearch(c, q, limit);
        return results;
      });
    } catch (_) {
      return const [];
    }
  }

  static String? _ddgHref(String raw) {
    var h = decodeEntities(raw).trim();
    if (h.startsWith('//')) {
      h = 'https:$h';
    } else if (h.startsWith('/')) {
      h = 'https://duckduckgo.com$h';
    }
    try {
      final u = Uri.parse(h);
      if (u.host.endsWith('duckduckgo.com')) {
        if (u.path.contains('y.js')) return null;
        final target = u.queryParameters['uddg'];
        if (target == null || target.isEmpty) return null;
        h = target;
      }
      final t = Uri.parse(h);
      if ((t.scheme != 'http' && t.scheme != 'https') || t.host.isEmpty) return null;
      return h;
    } catch (_) {
      return null;
    }
  }

  /// Parses a DuckDuckGo HTML results page (ads are skipped).
  static List<SearchResult> parseDuckDuckGo(String html, {int limit = 8}) {
    final containers = RegExp(r'''class\s*=\s*["'](result(?:\s[^"']*)?)["']''')
        .allMatches(html)
        .map((m) => (pos: m.start, cls: m.group(1)!))
        .toList();
    String containerClassAt(int pos) {
      var cls = '';
      for (final c in containers) {
        if (c.pos >= pos) break;
        cls = c.cls;
      }
      return cls;
    }

    final events = <({int pos, bool isTitle, Map<String, String> attrs, String inner})>[];
    final titleCls = RegExp(r'(^|\s)result__a(\s|$)');
    final snippetCls = RegExp(r'(^|\s)result__snippet(\s|$)');
    for (final m in _aRe.allMatches(html)) {
      final attrs = _attrs(m.group(1)!);
      final cls = attrs['class'] ?? '';
      if (titleCls.hasMatch(cls)) {
        events.add((pos: m.start, isTitle: true, attrs: attrs, inner: m.group(2)!));
      } else if (snippetCls.hasMatch(cls)) {
        events.add((pos: m.start, isTitle: false, attrs: attrs, inner: m.group(2)!));
      }
    }
    // Some layouts render the snippet in a <div>/<td>/<span>.
    for (final m in RegExp('<(div|td|span)\\b(?=[^>]*result__snippet)$_attrsPat>([\\s\\S]*?)</\\1\\s*>',
            caseSensitive: false)
        .allMatches(html)) {
      final attrs = _attrs(m.group(2)!);
      if (snippetCls.hasMatch(attrs['class'] ?? '')) {
        events.add((pos: m.start, isTitle: false, attrs: attrs, inner: m.group(3)!));
      }
    }
    events.sort((a, b) => a.pos.compareTo(b.pos));

    final out = <SearchResult>[];
    final seen = <String>{};
    String? curTitle;
    String? curUrl;
    String curSnippet = '';
    var curSkip = true;
    void flush() {
      if (!curSkip && curUrl != null && curTitle != null && curTitle!.isNotEmpty && seen.add(curUrl!)) {
        out.add(SearchResult(title: curTitle!, url: curUrl!, snippet: curSnippet, source: 'duckduckgo'));
      }
      curTitle = null;
      curUrl = null;
      curSnippet = '';
      curSkip = true;
    }

    for (final e in events) {
      if (e.isTitle) {
        flush();
        final href = e.attrs['href'] ?? '';
        final cls = containerClassAt(e.pos);
        final isAd = cls.contains('result--ad') ||
            href.contains('y.js') ||
            href.contains('ad_provider') ||
            href.contains('ad_domain');
        curTitle = _inlineText(e.inner);
        curUrl = isAd ? null : _ddgHref(href);
        curSkip = isAd || curUrl == null;
      } else if (curTitle != null && curSnippet.isEmpty) {
        curSnippet = _inlineText(e.inner);
      }
      if (out.length >= limit) break;
    }
    flush();
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  static String _wikiUrl(String lang, String title) =>
      Uri.https('$lang.wikipedia.org', '/wiki/${title.replaceAll(' ', '_')}').toString();

  static Future<List<SearchResult>> _wikiSearch(http.Client c, String q, int limit, {String lang = 'tr'}) async {
    final j = await _getJson(
        c,
        Uri.https('$lang.wikipedia.org', '/w/api.php', {
          'action': 'query',
          'list': 'search',
          'srsearch': q,
          'format': 'json',
          'srlimit': '$limit',
          'utf8': '1',
        }));
    if (j is! Map) return const [];
    final query = j['query'];
    if (query is! Map) return const [];
    final list = query['search'];
    if (list is! List) return const [];
    final out = <SearchResult>[];
    for (final item in list) {
      if (item is! Map) continue;
      final title = (item['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      out.add(SearchResult(
        title: title,
        url: _wikiUrl(lang, title),
        snippet: _inlineText((item['snippet'] ?? '').toString()),
        source: 'wikipedia',
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  static Future<({String title, String extract, String url})?> _wikiSummaryFetch(
      http.Client c, String lang, String title) async {
    final path = Uri.encodeComponent(title.trim().replaceAll(' ', '_'));
    final j = await _getJson(c, Uri.parse('https://$lang.wikipedia.org/api/rest_v1/page/summary/$path'));
    if (j is! Map) return null;
    if ((j['type'] ?? '') == 'disambiguation') return null;
    final extract = (j['extract'] ?? '').toString().trim();
    if (extract.isEmpty) return null;
    final t = (j['title'] ?? title).toString();
    String? url;
    final cu = j['content_urls'];
    if (cu is Map && cu['desktop'] is Map) url = (cu['desktop'] as Map)['page']?.toString();
    return (title: t, extract: extract, url: url ?? _wikiUrl(lang, t));
  }

  static Future<List<String>> _wikiResolveTitles(http.Client c, String lang, String q) async {
    final titles = <String>[];
    final os = await _getJson(
        c,
        Uri.https('$lang.wikipedia.org', '/w/api.php',
            {'action': 'opensearch', 'search': q, 'limit': '3', 'namespace': '0', 'format': 'json'}));
    if (os is List && os.length > 1 && os[1] is List) {
      for (final t in os[1] as List) {
        final s = t.toString().trim();
        if (s.isNotEmpty && !titles.contains(s)) titles.add(s);
      }
    }
    if (titles.isEmpty) {
      for (final r in await _wikiSearch(c, q, 3, lang: lang)) {
        if (!titles.contains(r.title)) titles.add(r.title);
      }
    }
    return titles;
  }

  static Future<({String title, String extract, String url})?> wikipediaSummary(String query,
      {String lang = 'tr', http.Client? client}) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    try {
      return await _using(client, (c) async {
        final direct = await _wikiSummaryFetch(c, lang, q);
        if (direct != null) return direct;
        final titles = await _wikiResolveTitles(c, lang, q);
        var tries = 0;
        for (final t in titles) {
          if (t.toLowerCase() == q.toLowerCase()) continue;
          final s = await _wikiSummaryFetch(c, lang, t);
          if (s != null) return s;
          if (++tries >= 2) break;
        }
        return null;
      });
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Weather (Open-Meteo)
  // -------------------------------------------------------------------------

  static const Map<int, String> _wmo = {
    0: 'açık',
    1: 'çoğunlukla açık',
    2: 'parçalı bulutlu',
    3: 'kapalı',
    45: 'sisli',
    48: 'kırağılı sis',
    51: 'hafif çisenti',
    53: 'çisenti',
    55: 'yoğun çisenti',
    56: 'hafif dondurucu çisenti',
    57: 'yoğun dondurucu çisenti',
    61: 'hafif yağmurlu',
    63: 'yağmurlu',
    65: 'şiddetli yağmurlu',
    66: 'hafif dondurucu yağmur',
    67: 'şiddetli dondurucu yağmur',
    71: 'hafif kar yağışlı',
    73: 'kar yağışlı',
    75: 'yoğun kar yağışlı',
    77: 'kar taneli',
    80: 'hafif sağanak yağışlı',
    81: 'sağanak yağışlı',
    82: 'şiddetli sağanak yağışlı',
    85: 'hafif kar sağanağı',
    86: 'yoğun kar sağanağı',
    95: 'gök gürültülü fırtına',
    96: 'hafif dolulu gök gürültülü fırtına',
    99: 'şiddetli dolulu gök gürültülü fırtına',
  };

  /// Turkish description for a WMO weather code.
  static String weatherDescription(int code) => _wmo[code] ?? 'bilinmeyen hava durumu';

  static double _toD(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _toI(Object? v) {
    if (v is num) return v.round();
    if (v is String) return (double.tryParse(v) ?? 0).round();
    return 0;
  }

  static Object? _at(Object? list, int i) => (list is List && i < list.length) ? list[i] : null;

  static Future<WeatherReport?> weather({String? city, double? lat, double? lon, http.Client? client}) async {
    try {
      return await _using(client, (c) async {
        var place = 'Konumunuz';
        var la = lat;
        var lo = lon;
        final cityName = city?.split(RegExp("['’]")).first.trim();
        if (cityName != null && cityName.isNotEmpty) {
          final g = await _getJson(
              c,
              Uri.https('geocoding-api.open-meteo.com', '/v1/search',
                  {'name': cityName, 'count': '1', 'language': 'tr', 'format': 'json'}));
          final results = g is Map ? g['results'] : null;
          if (results is List && results.isNotEmpty && results.first is Map) {
            final r0 = results.first as Map;
            la = _toD(r0['latitude']);
            lo = _toD(r0['longitude']);
            final name = (r0['name'] ?? cityName).toString();
            final admin = (r0['admin1'] ?? '').toString();
            place = (admin.isNotEmpty && admin != name) ? '$name, $admin' : name;
          } else if (la == null || lo == null) {
            return null;
          }
        }
        if (la == null || lo == null) return null;
        final f = await _getJson(
            c,
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': la.toStringAsFixed(4),
              'longitude': lo.toStringAsFixed(4),
              'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m',
              'daily':
                  'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max',
              'timezone': 'auto',
              'forecast_days': '7',
            }));
        if (f is! Map) return null;
        final cur = f['current'];
        if (cur is! Map) return null;
        final days = <WeatherDay>[];
        final daily = f['daily'];
        if (daily is Map && daily['time'] is List) {
          final times = daily['time'] as List;
          for (var i = 0; i < times.length && days.length < 7; i++) {
            final d = DateTime.tryParse(times[i].toString());
            if (d == null) continue;
            days.add(WeatherDay(
              date: d,
              maxC: _toD(_at(daily['temperature_2m_max'], i)),
              minC: _toD(_at(daily['temperature_2m_min'], i)),
              code: _toI(_at(daily['weather_code'], i)),
              precipitationMm: _toD(_at(daily['precipitation_sum'], i)),
              precipitationProb: _toI(_at(daily['precipitation_probability_max'], i)),
            ));
          }
        }
        final code = _toI(cur['weather_code']);
        return WeatherReport(
          place: place,
          lat: la,
          lon: lo,
          temperatureC: _toD(cur['temperature_2m']),
          apparentC: _toD(cur['apparent_temperature']),
          humidity: _toI(cur['relative_humidity_2m']),
          windKmh: _toD(cur['wind_speed_10m']),
          weatherCode: code,
          description: weatherDescription(code),
          days: days,
        );
      });
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Currency (Frankfurter)
  // -------------------------------------------------------------------------

  static Future<CurrencyQuote?> convertCurrency(
      {double amount = 1, required String from, String to = 'TRY', http.Client? client}) async {
    final f = from.trim().toUpperCase();
    final t = to.trim().toUpperCase();
    final codeRe = RegExp(r'^[A-Z]{3}$');
    if (!codeRe.hasMatch(f) || !codeRe.hasMatch(t)) return null;
    if (f == t) {
      return CurrencyQuote(from: f, to: t, rate: 1, amount: amount, converted: amount, date: DateTime.now());
    }
    final amt = amount == amount.roundToDouble() ? amount.toInt().toString() : amount.toString();
    try {
      return await _using(client, (c) async {
        final j = await _getJson(c, Uri.https('api.frankfurter.app', '/latest', {'amount': amt, 'from': f, 'to': t}));
        if (j is! Map) return null;
        final rates = j['rates'];
        if (rates is! Map) return null;
        final v = rates[t];
        if (v is! num) return null;
        final converted = v.toDouble();
        final rate = amount == 0 ? 0.0 : converted / amount;
        return CurrencyQuote(
          from: f,
          to: t,
          rate: rate,
          amount: amount,
          converted: converted,
          date: DateTime.tryParse((j['date'] ?? '').toString()),
        );
      });
    } catch (_) {
      return null;
    }
  }

  static const _isoCodes = {
    'USD', 'EUR', 'GBP', 'JPY', 'CHF', 'RUB', 'SAR', 'CNY', 'TRY', 'AUD', //
    'CAD', 'SEK', 'NOK', 'DKK', 'AZN', 'KWD', 'AED', 'QAR', 'BGN', 'PLN',
    'CZK', 'HUF', 'RON', 'INR', 'KRW', 'BRL', 'MXN', 'ZAR', 'NZD', 'SGD',
    'HKD', 'ILS', 'ISK', 'IDR', 'MYR', 'PHP', 'THB',
  };

  /// Maps a Turkish currency word (also suffixed: "doların", "euro'yu") to an
  /// ISO code. Returns null for unsupported (e.g. bitcoin) or unknown words.
  static String? currencyCodeFromTurkish(String word) {
    final raw = word.trim();
    if (raw.isEmpty) return null;
    final upper = raw.toUpperCase();
    if (_isoCodes.contains(upper)) return upper;
    switch (raw) {
      case r'$':
        return 'USD';
      case '€':
        return 'EUR';
      case '£':
        return 'GBP';
      case '₺':
        return 'TRY';
      case '¥':
        return 'JPY';
    }
    var w = raw.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    w = w.split(RegExp("['’]")).first.trim();
    if (w.isEmpty) return null;
    if (w.contains('bitcoin') || w == 'btc' || w.contains('ethereum') || w.contains('kripto')) return null;
    if (w.contains('kanada')) return 'CAD';
    if (w.contains('avustralya')) return 'AUD';
    if (w.contains('azerbaycan') || w.startsWith('manat')) return 'AZN';
    if (w.contains('kuveyt') || w.startsWith('dinar')) return 'KWD';
    if (w.contains('isveç') || w.startsWith('kron')) return 'SEK';
    if (w.contains('dirhem')) return 'AED';
    if (w.contains('japon') || w == 'yen' || w == 'yenler') return 'JPY';
    if (w.contains('isviçre') || w.startsWith('frank')) return 'CHF';
    if (w.contains('türk lira') || w == 'tl' || w.startsWith('lira') || w.startsWith('tl ')) return 'TRY';
    if (w.contains('amerikan') || w.startsWith('dolar') || w == 'usd') return 'USD';
    if (w.startsWith('euro') || w.startsWith('avro') || w.startsWith('yuro') || w.startsWith('öro')) return 'EUR';
    if (w.contains('ingiliz') || w.startsWith('sterlin') || w.startsWith('pound')) return 'GBP';
    if (w.startsWith('rubl') || w.contains('rus ')) return 'RUB';
    if (w.startsWith('riyal') || w.contains('suudi')) return 'SAR';
    if (w.startsWith('yuan') || w.contains('çin ') || w.startsWith('renminbi')) return 'CNY';
    return null;
  }

  // -------------------------------------------------------------------------
  // News (Google News RSS)
  // -------------------------------------------------------------------------

  static Future<List<NewsItem>> news({String? topic, http.Client? client, int limit = 10}) async {
    final t = topic?.trim() ?? '';
    final uri = t.isEmpty
        ? Uri.parse('https://news.google.com/rss?hl=tr&gl=TR&ceid=TR:tr')
        : Uri.parse('https://news.google.com/rss/search?q=${Uri.encodeQueryComponent(t)}&hl=tr&gl=TR&ceid=TR:tr');
    try {
      return await _using(client, (c) async {
        final r = await _getText(c, uri, accept: 'application/rss+xml,application/xml;q=0.9,*/*;q=0.5');
        if (r == null || r.status != 200) return const <NewsItem>[];
        return parseRss(r.body, limit: limit);
      });
    } catch (_) {
      return const [];
    }
  }

  static String _xmlText(String s) {
    final cdata = s.replaceAllMapped(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), (m) => m.group(1)!);
    // Entities may encode markup (e.g. &lt;b&gt;); decode, then strip tags.
    return _collapse(_stripTags(decodeEntities(_stripTags(cdata))));
  }

  static String? _xmlTag(String block, String tag) {
    final m = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag\\s*>', caseSensitive: false).firstMatch(block);
    return m?.group(1);
  }

  /// Parses RSS 2.0 items (Google News style).
  static List<NewsItem> parseRss(String xml, {int limit = 10}) {
    final out = <NewsItem>[];
    for (final m in RegExp(r'<item\b[^>]*>([\s\S]*?)</item\s*>', caseSensitive: false).allMatches(xml)) {
      if (out.length >= limit) break;
      final block = m.group(1)!;
      var title = _xmlText(_xmlTag(block, 'title') ?? '');
      if (title.isEmpty) continue;
      final link = _xmlText(_xmlTag(block, 'link') ?? _xmlTag(block, 'guid') ?? '');
      var source = _xmlText(_xmlTag(block, 'source') ?? '');
      final idx = title.lastIndexOf(' - ');
      if (idx > 0) {
        final suffix = title.substring(idx + 3).trim();
        if (source.isEmpty && suffix.isNotEmpty && suffix.length <= 60) {
          source = suffix;
          title = title.substring(0, idx).trim();
        } else if (suffix == source) {
          title = title.substring(0, idx).trim();
        }
      }
      final pub = _xmlTag(block, 'pubDate') ?? _xmlTag(block, 'dc:date') ?? '';
      out.add(NewsItem(title: title, link: link, source: source, published: parseRfc822(_xmlText(pub))));
    }
    return out;
  }

  /// Tolerant RFC 822 / ISO-8601 date parser (returns UTC for RFC 822).
  static DateTime? parseRfc822(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso;
    final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,5})?')
        .firstMatch(t);
    if (m == null) return null;
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final mon = months[m.group(2)!.toLowerCase()];
    if (mon == null) return null;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    final dt = DateTime.utc(year, mon, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!),
        int.tryParse(m.group(6) ?? '') ?? 0);
    final z = (m.group(7) ?? '').toUpperCase();
    var offset = 0;
    if (z.startsWith('+') || z.startsWith('-')) {
      final hh = int.parse(z.substring(1, 3));
      final mm = int.parse(z.substring(3, 5));
      offset = (z.startsWith('-') ? -1 : 1) * (hh * 60 + mm);
    } else {
      const named = {
        'EST': -300, 'EDT': -240, 'CST': -360, 'CDT': -300, //
        'MST': -420, 'MDT': -360, 'PST': -480, 'PDT': -420,
      };
      offset = named[z] ?? 0;
    }
    return dt.subtract(Duration(minutes: offset));
  }
}
