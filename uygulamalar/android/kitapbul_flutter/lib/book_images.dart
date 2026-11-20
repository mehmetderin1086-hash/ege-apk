import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class _PackSlice {
  const _PackSlice(this.shard, this.offset, this.length);
  final int shard;
  final int offset;
  final int length;
}

/// Kitap görselleri için içerik adresli dosya deposu + paket (pack) okuyucusu.
///
/// Görsel alanları (`coverBase64`, `backCoverBase64`, `imprintBase64`) ya
/// eskisi gibi satır içi base64 ya da `file:<sha256>.<png|jpg|gif>` referansı
/// taşır. Binlerce kapak `books.json` içine gömülünce dosya yüzlerce MB'a
/// çıkıyordu; referansla katalog küçük kalır. Tekil dosyaların yanında toplu
/// aktarılmış `iphone_images_*.pack` arşiv dilimleri de şeffafça okunur.
class BookImageStore {
  BookImageStore(this.directory);

  final Directory directory;

  /// Uygulama açılışında belgeler dizinine bağlanır; testlerde elle verilir.
  static BookImageStore? instance;

  static final refPattern = RegExp(r'^file:([0-9a-f]{64})\.(png|jpg|gif)$');

  Map<String, _PackSlice>? _packEntries;
  List<String>? _packShards;
  DateTime? _indexMtime;

  static bool isRef(Object? value) =>
      value is String && refPattern.hasMatch(value);

  /// Görselin uzantısını imzasından bulur; PNG/JPEG/GIF değilse null.
  static String? extensionOf(Uint8List data) {
    const pngMagic = [137, 80, 78, 71, 13, 10, 26, 10];
    if (data.length >= 8) {
      var png = true;
      for (var i = 0; i < 8; i++) {
        if (data[i] != pngMagic[i]) {
          png = false;
          break;
        }
      }
      if (png) return 'png';
    }
    if (data.length >= 3 &&
        data[0] == 0xff &&
        data[1] == 0xd8 &&
        data[2] == 0xff) {
      return 'jpg';
    }
    // iPhone arşivinde .png adıyla duran GIF kapaklar var; içerik korunur.
    if (data.length >= 6 &&
        data[0] == 0x47 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x38 &&
        (data[4] == 0x37 || data[4] == 0x39) &&
        data[5] == 0x61) {
      return 'gif';
    }
    return null;
  }

  /// Yazmadan, içeriğin alacağı referansı hesaplar (doğrulama turu için).
  static String refFor(Uint8List data) {
    final ext = extensionOf(data);
    if (ext == null) throw const FormatException('Görsel biçimi desteklenmiyor');
    return 'file:${sha256.convert(data)}.$ext';
  }

  File fileOf(String ref) {
    final match = refPattern.firstMatch(ref);
    if (match == null) throw const FormatException('Görsel referansı geçersiz');
    return File('${directory.path}/${match.group(1)}.${match.group(2)}');
  }

  Directory get _parentDir => directory.parent;

  void invalidatePackCache() {
    _packEntries = null;
    _packShards = null;
    _indexMtime = null;
  }

  Map<String, _PackSlice> _ensurePackIndex() {
    final indexFile = File('${_parentDir.path}/iphone_images_index.json');
    if (!indexFile.existsSync()) {
      _packEntries = const {};
      _packShards = const [];
      return _packEntries!;
    }
    try {
      final stat = indexFile.statSync();
      if (_packEntries != null &&
          _indexMtime != null &&
          _indexMtime == stat.modified) {
        return _packEntries!;
      }
      final raw = jsonDecode(indexFile.readAsStringSync());
      if (raw is! Map || raw['shards'] is! List || raw['entries'] is! Map) {
        _packEntries = const {};
        _packShards = const [];
        return _packEntries!;
      }
      final shards = (raw['shards'] as List)
          .whereType<String>()
          .toList(growable: false);
      final entries = <String, _PackSlice>{};
      for (final item in (raw['entries'] as Map).entries) {
        final k = item.key;
        final v = item.value;
        if (k is String &&
            v is List &&
            v.length == 3 &&
            v[0] is int &&
            v[1] is int &&
            v[2] is int) {
          final shardIdx = v[0] as int;
          final offset = v[1] as int;
          final length = v[2] as int;
          if (shardIdx >= 0 &&
              shardIdx < shards.length &&
              offset >= 0 &&
              length > 0) {
            entries[k] = _PackSlice(shardIdx, offset, length);
          }
        }
      }
      _packShards = shards;
      _packEntries = entries;
      _indexMtime = stat.modified;
      return entries;
    } catch (_) {
      _packEntries = const {};
      _packShards = const [];
      return _packEntries!;
    }
  }

  Uint8List? _readFromPackSync(String ref) {
    final match = refPattern.firstMatch(ref);
    if (match == null) return null;
    final entries = _ensurePackIndex();
    final slice = entries[ref];
    final shards = _packShards;
    if (slice == null || shards == null || slice.shard >= shards.length) {
      return null;
    }
    final packFile = File('${_parentDir.path}/${shards[slice.shard]}');
    if (!packFile.existsSync()) return null;
    RandomAccessFile? raf;
    try {
      raf = packFile.openSync(mode: FileMode.read);
      raf.setPositionSync(slice.offset);
      final data = raf.readSync(slice.length);
      if (data.length != slice.length) return null;
      if (sha256.convert(data).toString() != match.group(1)) return null;
      return data;
    } catch (_) {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  Future<Uint8List?> _readFromPackAsync(String ref) async {
    final match = refPattern.firstMatch(ref);
    if (match == null) return null;
    final entries = _ensurePackIndex();
    final slice = entries[ref];
    final shards = _packShards;
    if (slice == null || shards == null || slice.shard >= shards.length) {
      return null;
    }
    final packFile = File('${_parentDir.path}/${shards[slice.shard]}');
    if (!await packFile.exists()) return null;
    RandomAccessFile? raf;
    try {
      raf = await packFile.open(mode: FileMode.read);
      await raf.setPosition(slice.offset);
      final data = await raf.read(slice.length);
      if (data.length != slice.length) return null;
      return data;
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  /// Görseli kaydeder ve referansını döndürür. Aynı içerik zaten varsa ve
  /// içeriği doğrulanırsa yeniden yazılmaz; bozuksa yerine doğrusu yazılır.
  String put(Uint8List data) {
    final ref = refFor(data);
    final target = fileOf(ref);
    if (target.existsSync() && _matches(target, ref)) return ref;
    if (_readFromPackSync(ref) != null) return ref;
    directory.createSync(recursive: true);
    final temp = File('${target.path}.tmp');
    temp.writeAsBytesSync(data, flush: true);
    temp.renameSync(target.path);
    return ref;
  }

  bool _matches(File file, String ref) {
    try {
      final digest = sha256.convert(file.readAsBytesSync()).toString();
      return refPattern.firstMatch(ref)!.group(1) == digest;
    } catch (_) {
      return false;
    }
  }

  /// Hızlı varlık kontrolü (arayüz rozetleri için SHA-256 hesaplamadan).
  bool hasFast(String ref) {
    if (!isRef(ref)) return false;
    final file = fileOf(ref);
    if (file.existsSync()) return true;
    return _ensurePackIndex().containsKey(ref);
  }

  /// Referansın dosyası veya paketi var ve içeriği adıyla uyuşuyor mu?
  bool hasValid(String ref) {
    final file = fileOf(ref);
    if (file.existsSync() && _matches(file, ref)) return true;
    return _readFromPackSync(ref) != null;
  }

  /// Referans ya da base64 değerin baytları; dosya eksik/bozuksa null.
  Uint8List? bytesOf(String value) {
    if (!isRef(value)) return base64Decode(value);
    final file = fileOf(value);
    if (file.existsSync()) {
      final data = file.readAsBytesSync();
      if (sha256.convert(data).toString() ==
          refPattern.firstMatch(value)!.group(1)) {
        return data;
      }
    }
    return _readFromPackSync(value);
  }

  /// Arayüzde kaydırma sırasında ana iş parçacığını bloklamadan bayt okur.
  Future<Uint8List?> bytesOfAsync(String value) async {
    if (!isRef(value)) {
      try {
        return base64Decode(value);
      } catch (_) {
        return null;
      }
    }
    final file = fileOf(value);
    if (await file.exists()) {
      try {
        return await file.readAsBytes();
      } catch (_) {}
    }
    return _readFromPackAsync(value);
  }
}

/// Görsel alanının baytları (UI ve OCR için). Satır içi base64 her zaman,
/// referans yalnız depo bağlıysa ve dosya sağlamsa çözülür.
Uint8List? bookImageBytes(String value) {
  if (!BookImageStore.isRef(value)) return base64Decode(value);
  return BookImageStore.instance?.bytesOf(value);
}

const bookImageKeys = ['coverBase64', 'backCoverBase64', 'imprintBase64'];

/// Dışa aktarım için referansları satır içi base64'e çevirir. Eksik dosya
/// sessizce atlanmaz; açık hata verir.
List<Map<String, dynamic>> inlineBookImages(
  List<Map<String, dynamic>> books,
  BookImageStore? store,
) {
  return [
    for (final book in books)
      if (!bookImageKeys.any((k) => BookImageStore.isRef(book[k])))
        book
      else
        {
          ...book,
          for (final key in bookImageKeys)
            if (BookImageStore.isRef(book[key]))
              key: () {
                final data = store?.bytesOf(book[key] as String);
                if (data == null) {
                  throw FormatException(
                    '"${book['title'] ?? book['id']}" görsel dosyası eksik',
                  );
                }
                return base64Encode(data);
              }(),
        },
  ];
}
