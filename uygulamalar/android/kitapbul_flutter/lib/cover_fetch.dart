import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'book_images.dart';
import 'book_lookup.dart';
import 'catalog_store.dart';
import 'data_quality.dart';
import 'isbn.dart';

const allowedCoverSources = {
  'Open Library',
  'Google Books',
  'Amazon',
  'Kitapyurdu',
};

/// Imported iPhone field locks remain authoritative; malformed metadata fails closed.
bool coverFieldLocked(Map<String, dynamic> book) {
  final manualLock = book['coverAutoLocked'];
  if (manualLock != null && manualLock is! bool) return true;
  if (manualLock == true) return true;
  final original = book['iphoneOriginal'];
  final metadata =
      book['fieldMetadata'] ??
      (original is Map ? original['fieldMetadata'] : null);
  if (metadata == null || metadata == '') return false;
  if (metadata is! String) return true;
  try {
    final parsed = jsonDecode(metadata);
    if (parsed is! Map) return true;
    for (final value in parsed.values) {
      if (value is! Map ||
          value['source'] is! String ||
          value['isLocked'] is! bool ||
          (value['confidence'] != null && value['confidence'] is! num)) {
        return true;
      }
    }
    final cover = parsed['coverData'];
    return cover is Map && cover['isLocked'] == true;
  } catch (_) {
    return true;
  }
}

bool eligibleForCover(
  Map<String, dynamic> book, {
  bool allowTitleLookup = false,
}) {
  if (!missingQualityField(book, DataQualityField.cover) ||
      coverFieldLocked(book)) {
    return false;
  }
  final isbn = (book['isbn'] ?? '').toString().trim();
  if (isbn.isNotEmpty && isValidIsbn(isbn)) return true;
  if (!allowTitleLookup) return false;
  final title = (book['title'] ?? '').toString().trim();
  final author = (book['author'] ?? '').toString().trim();
  final publisher = (book['publisher'] ?? '').toString().trim();
  return title.isNotEmpty && (author.isNotEmpty || publisher.isNotEmpty);
}

class DownloadedCover {
  const DownloadedCover(this.bytes, this.source);
  final Uint8List bytes;
  final String source;
}

typedef CoverSource = Future<Uint8List?> Function(String isbn);

/// Missing is distinct from a service failure; the next source is always tried.
Future<DownloadedCover?> fetchCoverFromSources(
  String isbn, {
  CoverSource? amazon,
  required CoverSource openLibrary,
  required CoverSource googleBooks,
}) async {
  Object? failure;
  if (amazon != null) {
    try {
      final cover = await amazon(isbn);
      if (cover != null) return DownloadedCover(cover, 'Amazon');
    } catch (error) {
      failure ??= error;
    }
  }
  try {
    final cover = await openLibrary(isbn);
    if (cover != null) return DownloadedCover(cover, 'Open Library');
  } catch (error) {
    failure ??= error;
  }
  try {
    final cover = await googleBooks(isbn);
    if (cover != null) return DownloadedCover(cover, 'Google Books');
  } catch (error) {
    failure ??= error;
  }
  if (failure != null) throw failure;
  return null;
}

Future<DownloadedCover?> fetchBestCover(String isbn) => fetchCoverFromSources(
  isbn,
  amazon: fetchAmazonCover,
  openLibrary: fetchOpenLibraryCover,
  googleBooks: fetchGoogleBooksCover,
);

/// Fetches the best cover for a catalog book using ISBN (Amazon, Open Library, Google Books)
/// and falling back to Kitapyurdu (title + author + publisher).
Future<DownloadedCover?> fetchBestCoverForBook(
  Map<String, dynamic> book,
) async {
  Object? failure;
  final isbn = (book['isbn'] ?? '').toString().trim();
  if (isbn.isNotEmpty && isValidIsbn(isbn)) {
    try {
      final byIsbn = await fetchBestCover(isbn);
      if (byIsbn != null) return byIsbn;
    } catch (error) {
      failure ??= error;
    }
  }
  final title = (book['title'] ?? '').toString().trim();
  final author = (book['author'] ?? '').toString().trim();
  final publisher = (book['publisher'] ?? '').toString().trim();
  if (title.isNotEmpty && (author.isNotEmpty || publisher.isNotEmpty)) {
    try {
      final kyBytes = await fetchKitapyurduCover(
        title: title,
        author: author,
        publisher: publisher,
        expectedIsbn: isbn.isNotEmpty && isValidIsbn(isbn) ? isbn : null,
      );
      if (kyBytes != null) return DownloadedCover(kyBytes, 'Kitapyurdu');
    } catch (error) {
      failure ??= error;
    }
  }
  if (failure != null) throw failure;
  return null;
}

bool _httpsDefaultPort(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443);

bool _trustedGoogleCover(Uri uri) =>
    _httpsDefaultPort(uri) &&
    (uri.host == 'books.google.com' ||
        uri.host == 'books.googleusercontent.com' ||
        uri.host.endsWith('.googleusercontent.com'));

bool _trustedOpenLibraryCover(Uri uri) =>
    _httpsDefaultPort(uri) &&
    (uri.host == 'covers.openlibrary.org' ||
        uri.host == 'archive.org' ||
        uri.host.endsWith('.archive.org'));

bool _trustedAmazonCover(Uri uri) =>
    _httpsDefaultPort(uri) &&
    (uri.host == 'm.media-amazon.com' ||
        uri.host == 'images-na.ssl-images-amazon.com' ||
        uri.host == 'images-eu.ssl-images-amazon.com');

bool _trustedKitapyurduCover(Uri uri) =>
    _httpsDefaultPort(uri) && uri.host == 'img.kitapyurdu.com';

bool trustedAnyCoverHost(Uri uri) =>
    _trustedGoogleCover(uri) ||
    _trustedOpenLibraryCover(uri) ||
    _trustedAmazonCover(uri) ||
    _trustedKitapyurduCover(uri);

/// Only the specified ISBN/edition can supply a cover; unknown hosts are ignored.
List<Uri> googleCoverUrls(String response, String isbn) {
  final wanted = canonicalIsbn(isbn);
  if (wanted == null) throw const FormatException('Geçersiz ISBN');
  final data = jsonDecode(response);
  if (data is! Map || (data['items'] != null && data['items'] is! List)) {
    throw const FormatException('Google Books yanıtı geçersiz');
  }
  final result = <Uri>[];
  for (final item in (data['items'] as List?) ?? []) {
    if (item is! Map || item['volumeInfo'] is! Map) continue;
    final info = item['volumeInfo'] as Map;
    final identifiers = info['industryIdentifiers'];
    if (identifiers is! List ||
        !identifiers.any(
          (entry) =>
              entry is Map &&
              entry['identifier'] is String &&
              canonicalIsbn(entry['identifier'] as String) == wanted,
        )) {
      continue;
    }
    final links = info['imageLinks'];
    if (links is! Map) continue;
    for (final key in [
      'extraLarge',
      'large',
      'medium',
      'small',
      'thumbnail',
      'smallThumbnail',
    ]) {
      final raw = links[key];
      if (raw is! String) continue;
      var uri = Uri.tryParse(raw);
      if (uri == null) continue;
      if (uri.scheme == 'http' &&
          (uri.host == 'books.google.com' ||
              uri.host == 'books.googleusercontent.com' ||
              uri.host.endsWith('.googleusercontent.com'))) {
        uri = uri.replace(scheme: 'https');
      }
      if (_trustedGoogleCover(uri) && !result.contains(uri)) result.add(uri);
    }
  }
  return result;
}

Future<Uint8List?> _getBounded(
  HttpClient client,
  Uri uri,
  bool Function(Uri) trusted,
  int maxBytes,
) async {
  for (var redirects = 0; redirects < 5; redirects++) {
    if (!trusted(uri)) {
      throw const FormatException('Kapak adresi güvenilir değil');
    }
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'image/jpeg,image/png,*/*;q=0.8');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) throw const FormatException('Yönlendirme geçersiz');
      uri = uri.resolve(location);
      continue;
    }
    if (response.statusCode == 404) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('Kitap servisi HTTP ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('Servis yanıtı çok büyük');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
  throw const FormatException('Çok fazla yönlendirme');
}

bool _supportedImage(Uint8List bytes) =>
    bytes.length >= 8 &&
    ((bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) ||
        ([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ].asMap().entries.every((e) => bytes[e.key] == e.value)));

bool _isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    bytes[0] == 0x52 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x46 &&
    bytes[8] == 0x57 &&
    bytes[9] == 0x45 &&
    bytes[10] == 0x42 &&
    bytes[11] == 0x50;

Future<Uint8List?> _validateCover(Uint8List? data) async {
  if (data == null) return null;
  final webp = _isWebp(data);
  if (!_supportedImage(data) && !webp) {
    throw const FormatException('Kapak görseli geçersiz');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(data);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width < 50 || descriptor.height < 50) return null;
      if (descriptor.width > 4096 ||
          descriptor.height > 4096 ||
          descriptor.width * descriptor.height > 12000000) {
        throw const FormatException('Kapak çözünürlüğü çok büyük');
      }
      if (webp) {
        final codec = await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          try {
            final png = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (png == null) return null;
            final converted = png.buffer.asUint8List();
            return converted.length <= maxBookImageBytes ? converted : null;
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
      final codec = await descriptor.instantiateCodec(
        targetWidth: 50,
        targetHeight: 50,
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
  return data;
}

/// Downloads and validates a cover image from any trusted book cover CDN URL.
Future<Uint8List?> fetchCoverBytesFromUrl(String rawUrl) async {
  var uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return null;
  if (uri.scheme == 'http' &&
      (uri.host == 'books.google.com' ||
          uri.host == 'books.googleusercontent.com' ||
          uri.host.endsWith('.googleusercontent.com'))) {
    uri = uri.replace(scheme: 'https');
  }
  if (!trustedAnyCoverHost(uri)) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final bytes = await _getBounded(
      client,
      uri,
      trustedAnyCoverHost,
      maxBookImageBytes,
    );
    return await _validateCover(bytes);
  } finally {
    client.close(force: true);
  }
}

/// Encodes validated cover bytes for catalog storage (file ref when BookImageStore is mounted, else base64).
String storeCoverBytes(Uint8List bytes) =>
    BookImageStore.instance?.put(bytes) ?? base64Encode(bytes);

Future<Uint8List?> fetchAmazonCover(String isbn) async {
  final normalized = cleanIsbnInput(isbn);
  if (normalized.isEmpty || !isValidIsbn(normalized)) {
    throw const FormatException('Geçersiz ISBN');
  }
  final info = await lookupAmazonIsbn(normalized);
  final coverUrl = (info?['coverUrl'] ?? '').trim();
  if (coverUrl.isEmpty) return null;
  return await fetchCoverBytesFromUrl(coverUrl);
}

Future<Uint8List?> fetchKitapyurduCover({
  required String title,
  String author = '',
  String publisher = '',
  String? expectedIsbn,
}) async {
  final info = await lookupKitapyurduFirstMatch(
    title: title,
    author: author,
    publisher: publisher,
    expectedIsbn: expectedIsbn,
  );
  final coverUrl = (info?['coverUrl'] ?? '').trim();
  if (coverUrl.isEmpty) return null;
  return await fetchCoverBytesFromUrl(coverUrl);
}

Future<Uint8List?> fetchOpenLibraryCover(String isbn) async {
  final normalized = cleanIsbnInput(isbn);
  if (normalized.isEmpty || !isValidIsbn(normalized)) {
    throw const FormatException('Geçersiz ISBN');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final uri = Uri.https(
      'covers.openlibrary.org',
      '/b/isbn/$normalized-L.jpg',
      {'default': 'false'},
    );
    final bytes = await _getBounded(
      client,
      uri,
      _trustedOpenLibraryCover,
      maxBookImageBytes,
    );
    return await _validateCover(bytes);
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List?> fetchGoogleBooksCover(String isbn) async {
  final normalized = cleanIsbnInput(isbn);
  if (canonicalIsbn(normalized) == null) {
    throw const FormatException('Geçersiz ISBN');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': 'isbn:$normalized',
      'maxResults': '10',
    });
    final json = await _getBounded(
      client,
      uri,
      (u) => _httpsDefaultPort(u) && u.host == 'www.googleapis.com',
      2 * 1024 * 1024,
    );
    if (json == null) return null;
    final candidates = googleCoverUrls(utf8.decode(json), normalized);
    Object? failure;
    for (final cover in candidates) {
      try {
        final data = await _validateCover(
          await _getBounded(
            client,
            cover,
            _trustedGoogleCover,
            maxBookImageBytes,
          ),
        );
        if (data != null) return data;
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Applies only the exact, still eligible record; caller saves the result atomically.
List<Map<String, dynamic>>? withDownloadedCover(
  List<Map<String, dynamic>> books,
  String id,
  String isbn,
  Uint8List bytes, {
  String source = 'Open Library',
  bool allowTitleLookup = false,
}) {
  if (bytes.length > maxBookImageBytes ||
      !_supportedImage(bytes) ||
      !allowedCoverSources.contains(source)) {
    return null;
  }
  final index = books.indexWhere((b) => b['id'] == id);
  if (index < 0 ||
      (books[index]['isbn'] ?? '') != isbn ||
      !eligibleForCover(books[index], allowTitleLookup: allowTitleLookup)) {
    return null;
  }
  final updated = [...books];
  updated[index] = {
    ...updated[index],
    'coverBase64': storeCoverBytes(bytes),
    'coverSource': source,
  };
  return updated;
}
