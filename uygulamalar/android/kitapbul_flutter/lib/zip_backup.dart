import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import 'book_images.dart';
import 'catalog_store.dart';
import 'inventory_session.dart';
import 'loan_settings.dart';
import 'iphone_archive.dart' show walkStoredZipFile;
import 'member_store.dart';
import 'student_store.dart';

/// Büyük katalog için Android ZIP yedeği.
///
/// JSON yedeği kapakları satır içine gömdüğü için 50 MB sınırına takılır;
/// binlerce kapaklı iPhone kataloğu bu yüzden JSON olarak kaydedilemez. ZIP
/// yedeği kataloğu görsel referanslarıyla (`file:<sha256>.<uzantı>`) tutar,
/// görselleri ve saklanan iPhone tarama kayıtlarını ayrı kayıtlar olarak
/// ekler. Her kayıt `manifest.json` içinde SHA-256 ve boyutla listelenir.
/// Kayıtlar sıkıştırılmadan saklanır (görseller zaten sıkıştırılmıştır) ve
/// dosyadan tek tek okunur; arşiv belleğe bütün olarak alınmaz.
const zipBackupFormat = 'kitapbul-android-zip';
const zipBackupVersion = 1;

/// Kotlin'in önbelleğe kopyalama sınırıyla aynı.
const maxZipBackupBytes = 512 * 1024 * 1024;
const maxZipCatalogBytes = 64 * 1024 * 1024;
const maxZipPreservedFileBytes = 64 * 1024 * 1024;
const maxZipPreservedTotalBytes = 128 * 1024 * 1024;
const maxZipManifestBytes = 8 * 1024 * 1024;

const zipCatalogEntry = 'catalog.json';
const zipManifestEntry = 'manifest.json';
const zipPreservedDir = 'iphone-preserved';
const zipPreservedIndex = 'index.json';

final _imageEntry = RegExp(r'^book-images/([0-9a-f]{64})\.(png|jpg|gif)$');
final _preservedEntry = RegExp(
  r'^iphone-preserved/([A-Za-z0-9][A-Za-z0-9._-]{0,200})$',
);

Set<String> bookImageRefsOf(List<dynamic> books) => {
  for (final book in books)
    if (book is Map)
      for (final key in bookImageKeys)
        if (BookImageStore.isRef(book[key])) book[key] as String,
};

typedef ZipBackupSummary = ({
  int books,
  int images,
  int preservedFiles,
  int bytes,
});

/// [catalogJson], `encodeAndroidBackup` çıktısıdır (görseller referans
/// olarak kalır). Arşiv önce `.part` dosyasına yazılır, sonra baştan okunup
/// doğrulanır; ancak doğrulanırsa [outPath] adına taşınır.
Future<ZipBackupSummary> writeZipBackup({
  required String catalogJson,
  required String docsPath,
  required String outPath,
  DateTime? now,
}) async {
  final catalogValue = jsonDecode(catalogJson);
  if (catalogValue is! Map || catalogValue['books'] is! List) {
    throw const FormatException('Katalog biçimi geçersiz');
  }
  final books = catalogValue['books'] as List;
  final refs = bookImageRefsOf(books).toList()..sort();
  final images = BookImageStore(Directory('$docsPath/book-images'));
  final preservedDir = Directory('$docsPath/$zipPreservedDir');
  final files = <Map<String, dynamic>>[];
  final part = File('$outPath.part');
  if (part.existsSync()) part.deleteSync();
  final encoder = ZipFileEncoder()..create(part.path);
  var closed = false;
  void add(String name, Uint8List data) {
    final file = ArchiveFile(name, data.length, data)..compress = false;
    encoder.addArchiveFile(file);
    files.add({
      'name': name,
      'sha256': sha256.convert(data).toString(),
      'size': data.length,
    });
  }

  try {
    final catalogBytes = Uint8List.fromList(utf8.encode(catalogJson));
    if (catalogBytes.length > maxZipCatalogBytes) {
      throw const FormatException('Katalog kaydı çok büyük');
    }
    add(zipCatalogEntry, catalogBytes);
    for (final ref in refs) {
      final data = images.bytesOf(ref);
      if (data == null) {
        throw FormatException('Görsel dosyası eksik veya bozuk: $ref');
      }
      add('book-images/${ref.substring('file:'.length)}', data);
    }
    var preserved = 0;
    if (preservedDir.existsSync()) {
      final entries =
          preservedDir.listSync(followLinks: false).whereType<File>().where(
            (f) => !f.path.endsWith('.tmp'),
          ).toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      var preservedTotal = 0;
      for (final file in entries) {
        final name = '$zipPreservedDir/${file.uri.pathSegments.last}';
        if (!_preservedEntry.hasMatch(name)) {
          throw FormatException('Saklanan kayıt adı desteklenmiyor: $name');
        }
        // Boyut sınırı okumadan önce uygulanır; bozuk dev bir dosya belleği
        // tüketmeden kontrollü biçimde reddedilir.
        final length = file.lengthSync();
        preservedTotal += length;
        if (length > maxZipPreservedFileBytes ||
            preservedTotal > maxZipPreservedTotalBytes) {
          throw FormatException('Saklanan kayıt çok büyük: $name');
        }
        add(name, file.readAsBytesSync());
        preserved++;
      }
    }
    final manifest = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': zipBackupFormat,
          'version': zipBackupVersion,
          'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
          'counts': {
            'books': books.length,
            'images': refs.length,
            'preservedFiles': preserved,
          },
          'files': files,
        }),
      ),
    );
    encoder.addArchiveFile(
      ArchiveFile(zipManifestEntry, manifest.length, manifest)
        ..compress = false,
    );
    await encoder.close();
    closed = true;
    // Yazılan arşiv kendi okuyucumuzla baştan doğrulanır.
    final check = verifyZipBackup(part.path);
    if (check.books.length != books.length ||
        check.imageRefs.length != refs.length ||
        check.preserved.length != preserved) {
      throw const FormatException('Yazılan yedek doğrulanamadı');
    }
    final out = File(outPath);
    if (out.existsSync()) out.deleteSync();
    part.renameSync(outPath);
    return (
      books: books.length,
      images: refs.length,
      preservedFiles: preserved,
      bytes: out.lengthSync(),
    );
  } catch (_) {
    if (!closed) {
      try {
        await encoder.close();
      } catch (_) {}
    }
    if (part.existsSync()) part.deleteSync();
    rethrow;
  }
}

class VerifiedZipBackup {
  VerifiedZipBackup._({
    required this.catalogJson,
    required this.books,
    required this.students,
    required this.members,
    required this.supplement,
    required this.inventorySession,
    required this.inventoryHistory,
    required this.imageRefs,
    required this.preserved,
    required this.digests,
    required this.createdAt,
    required this.loanSettings,
    required this.preservedIndex,
  });

  final String catalogJson;
  final List<Map<String, dynamic>> books;
  final List<Student>? students;
  final List<Member>? members;
  final Map<String, dynamic>? supplement;
  final InventorySession? inventorySession;
  final List<InventoryArchive> inventoryHistory;
  final Set<String> imageRefs;

  /// `iphone-preserved/` altındaki dosya adı -> SHA-256.
  final Map<String, String> preserved;

  /// Arşivdeki her kaydın (manifest dahil) SHA-256'sı; yazma turu aynı
  /// arşivle çalıştığını bununla kanıtlar.
  final Map<String, String> digests;
  final String createdAt;

  /// Ek veriden önceden çözülmüş ödünç ayarları; geçersizse doğrulama
  /// aşamasında reddedilir, katalog kaydedilmeden önce.
  final LoanSettings loanSettings;

  /// Doğrulanmış `index.json` girdileri (yoksa boş).
  final List<Map<String, dynamic>> preservedIndex;
}

/// Hiçbir şey yazmadan arşivi doğrular: yol, boyut, CRC, manifest SHA-256,
/// görsel içeriği/adı uyumu ve katalog (sürüm 6, tüm alanlar) çözümlemesi.
VerifiedZipBackup verifyZipBackup(String path) {
  final digests = <String, String>{};
  final sizes = <String, int>{};
  Uint8List? catalog;
  Uint8List? manifestBytes;
  final imageRefs = <String>{};
  final preserved = <String, String>{};
  Uint8List? indexBytes;
  var preservedTotal = 0;
  walkStoredZipFile(
    path,
    maxZipBackupBytes,
    (name, size) {
      if (name == zipCatalogEntry) {
        if (size > maxZipCatalogBytes) {
          throw const FormatException('Katalog kaydı çok büyük');
        }
      } else if (name == zipManifestEntry) {
        if (size > maxZipManifestBytes) {
          throw const FormatException('Manifest çok büyük');
        }
      } else if (_imageEntry.hasMatch(name)) {
        if (size > maxBookImageBytes) {
          throw const FormatException('Görsel çok büyük');
        }
      } else if (_preservedEntry.hasMatch(name)) {
        preservedTotal += size;
        if (size > maxZipPreservedFileBytes ||
            preservedTotal > maxZipPreservedTotalBytes) {
          throw const FormatException('Saklanan kayıt çok büyük');
        }
      } else {
        throw FormatException('Yedekte beklenmeyen kayıt: $name');
      }
    },
    (name, data) {
      final digest = sha256.convert(data).toString();
      digests[name] = digest;
      sizes[name] = data.length;
      final image = _imageEntry.firstMatch(name);
      if (name == zipCatalogEntry) {
        catalog = data;
      } else if (name == zipManifestEntry) {
        manifestBytes = data;
      } else if (image != null) {
        if (image.group(1) != digest ||
            BookImageStore.extensionOf(data) != image.group(2)) {
          throw FormatException('Görsel içeriği adıyla uyuşmuyor: $name');
        }
        imageRefs.add('file:${image.group(1)}.${image.group(2)}');
      } else {
        final fileName = name.substring('$zipPreservedDir/'.length);
        preserved[fileName] = digest;
        if (fileName == zipPreservedIndex) indexBytes = data;
      }
    },
  );
  if (manifestBytes == null || catalog == null) {
    throw const FormatException('Yedekte katalog veya manifest eksik');
  }
  final manifest = jsonDecode(utf8.decode(manifestBytes!));
  if (manifest is! Map ||
      manifest['format'] != zipBackupFormat ||
      manifest['version'] != zipBackupVersion ||
      manifest['files'] is! List ||
      manifest['createdAt'] is! String) {
    throw const FormatException('Desteklenmeyen ZIP yedeği');
  }
  final listed = <String>{};
  for (final item in manifest['files'] as List) {
    if (item is! Map ||
        item['name'] is! String ||
        item['sha256'] is! String ||
        item['size'] is! int ||
        !listed.add(item['name'] as String) ||
        digests[item['name']] != item['sha256'] ||
        sizes[item['name']] != item['size']) {
      throw const FormatException('Manifest ile arşiv uyuşmuyor');
    }
  }
  final payload = digests.keys.toSet()..remove(zipManifestEntry);
  if (listed.length != payload.length || !listed.containsAll(payload)) {
    throw const FormatException('Manifest ile arşiv uyuşmuyor');
  }
  final catalogJson = utf8.decode(catalog!);
  final value = jsonDecode(catalogJson);
  if (value is! Map || value['version'] != 6) {
    throw const FormatException('ZIP yedeğindeki katalog sürümü desteklenmiyor');
  }
  final books = parseAndroidBackup(catalogJson, availableImageRefs: imageRefs);
  final referenced = bookImageRefsOf(value['books'] as List);
  if (!imageRefs.containsAll(referenced)) {
    throw const FormatException('Yedekteki görsel dosyası eksik');
  }
  final counts = manifest['counts'];
  if (counts is! Map ||
      counts['books'] != books.length ||
      counts['images'] != imageRefs.length ||
      counts['preservedFiles'] != preserved.length) {
    throw const FormatException('Manifest sayıları uyuşmuyor');
  }
  if (preserved.isNotEmpty && indexBytes == null) {
    throw const FormatException('Saklanan tarama dizini eksik');
  }
  final preservedIndex = indexBytes == null
      ? <Map<String, dynamic>>[]
      : _parsePreservedIndex(indexBytes!, preserved, sizes);
  final supplement = value['iphoneSupplement'] == null
      ? null
      : validateIPhoneSupplement(value['iphoneSupplement']);
  final loanSettings = LoanSettings.fromSupplement(supplement);
  return VerifiedZipBackup._(
    catalogJson: catalogJson,
    books: books,
    students: value['students'] == null
        ? null
        : decodeStudents(jsonEncode(value['students'])),
    members: value['members'] == null
        ? null
        : decodeMembers(jsonEncode(value['members'])),
    supplement: supplement,
    inventorySession: value['inventorySession'] == null
        ? null
        : InventorySession.fromJson(value['inventorySession']),
    inventoryHistory: parseInventoryHistory(value['inventoryHistory']),
    imageRefs: imageRefs,
    preserved: preserved,
    digests: digests,
    createdAt: manifest['createdAt'] as String,
    loanSettings: loanSettings,
    preservedIndex: preservedIndex,
  );
}

/// `index.json` içeriğini doğrular: liste olmalı, her girdi arşivdeki bir
/// saklanan dosyayı ad, SHA-256 ve boyutla göstermeli.
List<Map<String, dynamic>> _parsePreservedIndex(
  Uint8List bytes,
  Map<String, String> preserved,
  Map<String, int> sizes,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    throw const FormatException('Saklanan tarama dizini okunamadı');
  }
  if (decoded is! List) {
    throw const FormatException('Saklanan tarama dizini okunamadı');
  }
  final result = <Map<String, dynamic>>[];
  for (final entry in decoded) {
    if (entry is! Map ||
        entry['file'] is! String ||
        entry['sha256'] is! String ||
        entry['size'] is! int) {
      throw const FormatException('Saklanan tarama dizini okunamadı');
    }
    final file = entry['file'] as String;
    if (file == zipPreservedIndex ||
        preserved[file] != entry['sha256'] ||
        sizes['$zipPreservedDir/$file'] != entry['size']) {
      throw FormatException('Tarama dizini arşivle uyuşmuyor: $file');
    }
    result.add(Map<String, dynamic>.from(entry));
  }
  return result;
}

/// Doğrulanmış arşivin görsellerini ve saklanan kayıtlarını cihaza ekler.
/// Hiçbir mevcut dosya silinmez veya farklı içerikle üzerine yazılmaz:
/// görseller içerik adreslidir, saklanan tarama dosyaları ad+özetle
/// eşleşmeli, `index.json` girdileri birleştirilir. Katalog yazılmaz; onu
/// çağıran, ön kopyayı aldıktan sonra kaydeder.
void installZipBackupFiles(String path, String docsPath, VerifiedZipBackup v) {
  final images = BookImageStore(Directory('$docsPath/book-images'));
  final preservedDir = Directory('$docsPath/$zipPreservedDir');
  // Mevcut dizin hiçbir dosya yazılmadan önce okunur; bozuksa geri yükleme
  // yan etki bırakmadan durur.
  final indexFile = File('${preservedDir.path}/$zipPreservedIndex');
  final Object? existing;
  try {
    existing = indexFile.existsSync()
        ? jsonDecode(indexFile.readAsStringSync())
        : <dynamic>[];
  } catch (_) {
    throw const FormatException('Cihazdaki tarama dizini okunamadı');
  }
  if (existing is! List) {
    throw const FormatException('Cihazdaki tarama dizini okunamadı');
  }
  final seen = <String>{};
  walkStoredZipFile(path, maxZipBackupBytes, null, (name, data) {
    final digest = sha256.convert(data).toString();
    if (v.digests[name] != digest) {
      throw const FormatException('Yedek doğrulamadan sonra değişti');
    }
    seen.add(name);
    if (_imageEntry.hasMatch(name)) {
      // Adı içeriğiyle uyuşmayan (bozuk) yerel dosya silinmez; kenara alınır,
      // yerine doğru içerik yazılır.
      final local = File('$docsPath/$name');
      if (local.existsSync() &&
          sha256.convert(local.readAsBytesSync()).toString() != digest) {
        local.renameSync(
          '${local.path}.bozuk-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      final ref = images.put(data);
      if ('book-images/${ref.substring('file:'.length)}' != name) {
        throw const FileSystemException('Görsel kaydedilemedi');
      }
    } else if (_preservedEntry.hasMatch(name)) {
      final fileName = name.substring('$zipPreservedDir/'.length);
      if (fileName == zipPreservedIndex) return;
      preservedDir.createSync(recursive: true);
      final target = File('${preservedDir.path}/$fileName');
      if (target.existsSync()) {
        if (sha256.convert(target.readAsBytesSync()).toString() != digest) {
          throw FileSystemException(
            'Cihazdaki saklanan kayıt yedektekinden farklı',
            target.path,
          );
        }
        return;
      }
      final temp = File('${target.path}.tmp');
      temp.writeAsBytesSync(data, flush: true);
      temp.renameSync(target.path);
      if (sha256.convert(target.readAsBytesSync()).toString() != digest) {
        throw const FileSystemException('Saklanan kayıt doğrulanamadı');
      }
    }
  });
  if (seen.length != v.digests.length) {
    throw const FormatException('Yedek doğrulamadan sonra değişti');
  }
  for (final ref in v.imageRefs) {
    if (!images.hasValid(ref)) {
      throw const FileSystemException('Görsel kaydedilemedi');
    }
  }
  if (v.preservedIndex.isNotEmpty) {
    final incoming = v.preservedIndex;
    final known = {for (final e in existing) jsonEncode(e)};
    final merged = [
      ...existing,
      for (final e in incoming)
        if (!known.contains(jsonEncode(e))) e,
    ];
    final temp = File('${indexFile.path}.tmp');
    temp.writeAsStringSync(jsonEncode(merged), flush: true);
    temp.renameSync(indexFile.path);
  }
}
