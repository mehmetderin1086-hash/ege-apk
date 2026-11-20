import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' show InputFileStream;
import 'book_images.dart';
import 'iphone_mapping.dart';
import 'student_store.dart';
import 'member_store.dart';
import 'copy_model.dart';
import 'reservation_model.dart';
import 'loan_model.dart';
import 'loan_settings.dart';
import 'catalog_store.dart' show maxBookImageBytes;

const maxIPhoneArchiveBytes = 25 * 1024 * 1024;
const maxIPhoneImagesBytes = 20 * 1024 * 1024;

/// Dosyadan (akışla) okunan arşivler için üst sınır. Görseller tek tek
/// okunduğundan bellek kullanımı arşiv boyutuna bağlı değildir.
const maxIPhoneFileArchiveBytes = 512 * 1024 * 1024;

/// Bellekte tutulan (görsel dışı) tek kayıt ve toplam sınırı. Gerçek iPhone
/// arşivinde en büyük JSON ~17 MB, toplamı ~28 MB.
const maxIPhoneJsonEntryBytes = 64 * 1024 * 1024;
const maxIPhoneJsonTotalBytes = 128 * 1024 * 1024;

/// Bellekte tutulmayan, gerektiğinde dosyadan okunan görsel dizinleri.
bool isIPhoneImageEntry(String name) =>
    (name.startsWith('kapaklar/') && name.endsWith('.png')) ||
    (name.startsWith('arka/') && name.endsWith('.jpg')) ||
    (name.startsWith('kunye/') && name.endsWith('.jpg'));

/// iPhone tarama kayıtları: Android'de henüz model yok; bayt bayt saklanır.
const iphonePreservedScanFiles = {
  'tarama-makbuzlari.json',
  'tarama-oturumlari.json',
};

/// Validates extracted archive entries before any mapping or persistence.
/// ZIP extraction and import are deliberately not wired to the UI yet.
class IPhoneArchiveSummary {
  const IPhoneArchiveSummary({
    required this.books,
    required this.loans,
    required this.entries,
    this.mappingIssue,
  });
  final int books;
  final int loans;
  final int entries;
  final String? mappingIssue;
}

IPhoneArchiveSummary inspectIPhoneArchive(Map<String, Uint8List> entries) =>
    _inspect(
      entries,
      payloadNames: entries.keys.where((n) => n != 'manifest.json').toSet(),
      digestOf: (name) => sha256.convert(entries[name]!).toString(),
    );

/// [entries] JSON kayıtlarını içerir; görseller [digestOf] ile doğrulanır.
IPhoneArchiveSummary _inspect(
  Map<String, Uint8List> entries, {
  required Set<String> payloadNames,
  required String Function(String name) digestOf,
}) {
  final manifestBytes = entries['manifest.json'];
  if (manifestBytes == null) {
    throw const FormatException('Arşiv manifesti eksik');
  }
  final manifest = jsonDecode(utf8.decode(manifestBytes));
  if (manifest is! Map ||
      manifest['version'] != 2 ||
      manifest['hashes'] is! Map) {
    throw const FormatException('Desteklenmeyen arşiv manifesti');
  }
  final hashes = manifest['hashes'] as Map;
  if (hashes.keys.any((key) => key is! String) ||
      hashes.keys.toSet().length != payloadNames.length ||
      !payloadNames.containsAll(hashes.keys)) {
    throw const FormatException('Arşiv dosyaları manifestle uyuşmuyor');
  }
  for (final name in payloadNames) {
    if (name.startsWith('/') ||
        name.split('/').contains('..') ||
        name.contains('\\')) {
      throw const FormatException('Geçersiz arşiv yolu');
    }
    if (hashes[name] is! String || digestOf(name) != hashes[name]) {
      throw const FormatException('Arşiv bütünlük doğrulaması başarısız');
    }
  }
  List<dynamic> list(String name) {
    final bytes = entries[name];
    if (bytes == null) throw FormatException('$name eksik');
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! List) throw FormatException('$name geçersiz');
    return value;
  }

  final books = list('katalog.json');
  final loans = list('etkin-oduncler.json');
  String? mappingIssue;
  try {
    mapIphoneCatalog(books, loans);
  } on FormatException catch (error) {
    mappingIssue = error.message;
  }
  return IPhoneArchiveSummary(
    mappingIssue: mappingIssue,
    books: books.length,
    loans: loans.length,
    entries: payloadNames.length,
  );
}

/// Read the stored (uncompressed) ZIP format written by iPhone's ZIPWriter.
/// No files are extracted to the filesystem. Limits bound memory usage.
class VerifiedIPhoneArchive {
  VerifiedIPhoneArchive._(
    this.summary,
    this._entries, {
    Map<String, Uint8List Function()> lazy = const {},
    this.fromFile = false,
    void Function()? onClose,
  }) : _lazy = lazy,
       _onClose = onClose;
  final void Function()? _onClose;

  /// Dosyadan okunan arşivin dosya tanıtıcısını kapatır.
  void close() => _onClose?.call();
  final IPhoneArchiveSummary summary;
  final Map<String, Uint8List> _entries;
  final Map<String, Uint8List Function()> _lazy;

  /// Dosyadan okunduysa görsel toplam sınırı (20 MB) uygulanmaz.
  final bool fromFile;

  /// Returns an isolated copy; callers cannot mutate validated bytes.
  /// Lazy entries are re-read and re-verified (CRC + SHA-256) on each call.
  Uint8List? readEntry(String name) {
    final value = _entries[name];
    if (value != null) return Uint8List.fromList(value);
    return _lazy[name]?.call();
  }

  List<String> get entryNames =>
      List.unmodifiable([..._entries.keys, ..._lazy.keys]);
}

IPhoneArchiveSummary inspectIPhoneZip(Uint8List bytes) =>
    readIPhoneZip(bytes).summary;

VerifiedIPhoneArchive readIPhoneZip(Uint8List bytes) {
  const maxBytes = maxIPhoneArchiveBytes;
  if (bytes.length > maxBytes) throw const FormatException('Arşiv çok büyük');
  try {
    final entries = <String, Uint8List>{};
    _walkZip(InputStream(bytes), maxBytes, null, (name, header, data) {
      entries[name] = data;
    });
    final summary = inspectIPhoneArchive(entries);
    return VerifiedIPhoneArchive._(summary, entries);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('ZIP arşivi okunamadı');
  }
}

/// Büyük arşivi diskten okur: JSON kayıtları bellekte tutulur, görseller
/// yalnız doğrulanır (CRC + SHA-256) ve gerektiğinde tek tek yeniden okunur.
VerifiedIPhoneArchive readIPhoneZipFile(String path) {
  final file = File(path);
  final length = file.lengthSync();
  if (length > maxIPhoneFileArchiveBytes) {
    throw const FormatException('Arşiv çok büyük');
  }
  final stream = InputFileStream(path);
  var keepOpen = false;
  try {
    final entries = <String, Uint8List>{};
    final digests = <String, String>{};
    final headers = <String, ZipFileHeader>{};
    var jsonTotal = 0;
    _walkZip(stream, maxIPhoneFileArchiveBytes, (name, size) {
      // Boyut başlıktan okunur ve içerik belleğe alınmadan önce sınanır.
      if (isIPhoneImageEntry(name)) {
        if (size > maxBookImageBytes) {
          throw const FormatException('Görsel çok büyük');
        }
        return;
      }
      jsonTotal += size;
      if (size > maxIPhoneJsonEntryBytes ||
          jsonTotal > maxIPhoneJsonTotalBytes) {
        throw const FormatException('Arşiv kaydı çok büyük');
      }
    }, (name, header, data) {
      if (isIPhoneImageEntry(name)) {
        digests[name] = sha256.convert(data).toString();
        headers[name] = header;
      } else {
        entries[name] = data;
      }
    });
    final summary = _inspect(
      entries,
      payloadNames: {...entries.keys, ...headers.keys}..remove('manifest.json'),
      digestOf: (name) =>
          digests[name] ?? sha256.convert(entries[name]!).toString(),
    );
    final lazy = <String, Uint8List Function()>{
      for (final name in headers.keys)
        name: () {
          final data = _verifiedContent(name, headers[name]!);
          if (sha256.convert(data).toString() != digests[name]) {
            throw const FormatException('Arşiv bütünlük doğrulaması başarısız');
          }
          return data;
        },
    };
    keepOpen = true;
    return VerifiedIPhoneArchive._(
      summary,
      entries,
      lazy: lazy,
      fromFile: true,
      onClose: stream.closeSync,
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('ZIP arşivi okunamadı');
  } finally {
    if (!keepOpen) stream.closeSync();
  }
}

/// Android ZIP yedeği de aynı katı okuyucuyu kullanır: yalnız saklanmış
/// kayıtlar, yinelenmeyen güvenli yollar, CRC ve boyut doğrulaması. Kayıtlar
/// tek tek okunur; görseller belleğe toplu alınmaz.
void walkStoredZipFile(
  String path,
  int maxBytes,
  void Function(String name, int size)? checkSize,
  void Function(String name, Uint8List data) onEntry,
) {
  if (File(path).lengthSync() > maxBytes) {
    throw const FormatException('Arşiv çok büyük');
  }
  final stream = InputFileStream(path);
  try {
    _walkZip(stream, maxBytes, checkSize, (name, _, data) => onEntry(name, data));
  } on FormatException {
    rethrow;
  } on FileSystemException {
    rethrow;
  } catch (_) {
    throw const FormatException('ZIP arşivi okunamadı');
  } finally {
    stream.closeSync();
  }
}

Uint8List _verifiedContent(String name, ZipFileHeader header) {
  final file = header.file;
  if (file == null || file.filename != name) {
    throw const FormatException('ZIP başlıkları uyuşmuyor');
  }
  // Yalnız saklanmış (sıkıştırmasız, şifresiz) kayıtlar kabul edilir; ham
  // içerik okunur, ZipFile içinde önbelleğe alınmaz (bellek sınırlı kalır).
  final raw = file.rawContent;
  if (raw == null) throw const FormatException('ZIP bütünlük hatası');
  final data = Uint8List.fromList(raw.toUint8List());
  if (data.length != header.uncompressedSize ||
      getCrc32(data) != header.crc32) {
    throw const FormatException('ZIP bütünlük hatası');
  }
  return data;
}

void _walkZip(
  InputStreamBase input,
  int maxBytes,
  void Function(String name, int size)? checkSize,
  void Function(String name, ZipFileHeader header, Uint8List data) onEntry,
) {
  final directory = ZipDirectory.read(input);
  if (directory.numberOfThisDisk != 0 ||
      directory.diskWithTheStartOfTheCentralDirectory != 0 ||
      directory.totalCentralDirectoryEntries != directory.fileHeaders.length ||
      directory.totalCentralDirectoryEntriesOnThisDisk !=
          directory.fileHeaders.length) {
    throw const FormatException('Eksik veya çok parçalı ZIP arşivi');
  }
  if (directory.fileHeaders.length > 10000) {
    throw const FormatException('Çok fazla dosya');
  }
  final seen = <String>{};
  var total = 0;
  for (final header in directory.fileHeaders) {
    final name = header.filename;
    final size = header.uncompressedSize;
    if (seen.contains(name) ||
        name.isEmpty ||
        name.startsWith('/') ||
        name.split('/').contains('..') ||
        name.contains('\\') ||
        name.endsWith('/')) {
      throw const FormatException('Geçersiz veya yinelenen arşiv yolu');
    }
    seen.add(name);
    if (header.compressionMethod != 0 ||
        header.generalPurposeBitFlag & 1 != 0 ||
        size == null ||
        size < 0 ||
        header.compressedSize != size) {
      throw const FormatException('Desteklenmeyen ZIP kaydı');
    }
    total += size;
    if (total > maxBytes) throw const FormatException('Arşiv çok büyük');
    checkSize?.call(name, size);
    onEntry(name, header, _verifiedContent(name, header));
  }
}

/// Tarama kayıtlarını bayt bayt saklar. Adlar içerik adreslidir, mevcut
/// dosyalar asla silinmez veya üzerine yazılmaz; `index.json` her aktarımı
/// ekleyerek kaydeder. Saklanan dosya sayısını döndürür.
int preserveIPhoneScanFiles(
  VerifiedIPhoneArchive archive,
  Directory directory, {
  DateTime? now,
}) {
  final names = archive.entryNames
      .where(iphonePreservedScanFiles.contains)
      .toList()
    ..sort();
  if (names.isEmpty) return 0;
  directory.createSync(recursive: true);
  final indexFile = File('${directory.path}/index.json');
  final existing = indexFile.existsSync()
      ? jsonDecode(indexFile.readAsStringSync())
      : <dynamic>[];
  if (existing is! List) {
    throw const FormatException('Saklanan tarama dizini okunamadı');
  }
  final index = [...existing];
  final manifest = archive.readEntry('manifest.json')!;
  final archiveSha = sha256.convert(manifest).toString();
  final importedAt = (now ?? DateTime.now()).toUtc().toIso8601String();
  for (final name in names) {
    final data = archive.readEntry(name)!;
    final digest = sha256.convert(data).toString();
    final stem = name.substring(0, name.length - '.json'.length);
    final target = File('${directory.path}/$stem.$digest.json');
    if (!target.existsSync()) {
      final temp = File('${target.path}.tmp');
      temp.writeAsBytesSync(data, flush: true);
      temp.renameSync(target.path);
    }
    if (sha256.convert(target.readAsBytesSync()).toString() != digest) {
      throw const FileSystemException('Tarama kaydı doğrulanamadı');
    }
    index.add({
      'name': name,
      'file': target.uri.pathSegments.last,
      'sha256': digest,
      'size': data.length,
      'manifestSha256': archiveSha,
      'importedAt': importedAt,
    });
  }
  final temp = File('${indexFile.path}.tmp');
  temp.writeAsStringSync(jsonEncode(index), flush: true);
  temp.renameSync(indexFile.path);
  return names.length;
}

/// Only permits a lossless subset until all archive sections have models.
///
/// [imageSink] verilirse görseller satır içi base64 yerine sink'in döndürdüğü
/// referansla (`file:<sha256>.<ext>`) saklanır ve toplam görsel sınırı
/// uygulanmaz; tek görsel sınırı (4 MB) her durumda geçerlidir. Doğrulama
/// turunda `BookImageStore.refFor`, yazma turunda `store.put` verilir.
List<Map<String, dynamic>> prepareIPhoneCatalogImport(
  VerifiedIPhoneArchive archive, {
  String Function(Uint8List data)? imageSink,
}) {
  const handled = {
    'manifest.json',
    'katalog.json',
    'etkin-oduncler.json',
    'ogrenciler.json',
    'uyeler.json',
    'mezunlar.json',
    'nushalar.json',
    'rezervasyonlar.json',
  };
  const emptyArrays = {'katalog-birlestirme-geri-al.json'};
  const preservedObjects = {'ayarlar.json', 'destek-dosyalari.json'};
  for (final name in archive.entryNames) {
    if (handled.contains(name) ||
        name == 'odunc-gecmisi.json' ||
        isIPhoneImageEntry(name))
      continue;
    if (iphonePreservedScanFiles.contains(name)) {
      // Android'de karşılığı yok; preserveIPhoneScanFiles bayt bayt saklar.
      if (jsonDecode(utf8.decode(archive.readEntry(name)!)) is! List) {
        throw FormatException('$name geçersiz');
      }
      continue;
    }
    if (preservedObjects.contains(name)) {
      _validatePreservedObject(
        jsonDecode(utf8.decode(archive.readEntry(name)!)),
      );
    } else if (emptyArrays.contains(name)) {
      final value = jsonDecode(utf8.decode(archive.readEntry(name)!));
      final empty = value is List && value.isEmpty;
      if (!empty) throw FormatException('$name henüz desteklenmiyor');
    } else {
      throw FormatException('$name henüz desteklenmiyor');
    }
  }
  final books = jsonDecode(utf8.decode(archive.readEntry('katalog.json')!));
  final loans = jsonDecode(
    utf8.decode(archive.readEntry('etkin-oduncler.json')!),
  );
  final students = prepareIPhoneStudents(archive);
  final members = prepareIPhoneMembers(archive);
  final studentIds = {
    for (final student in students ?? <Student>[])
      student.id.toUpperCase(): student.id,
  };
  final memberIds = {
    for (final member in members ?? <Member>[])
      member.id.toUpperCase(): member.id,
  };
  if (books is! List || loans is! List)
    throw const FormatException('Katalog veya ödünç listesi geçersiz');
  for (final book in books) {
    if (book is! Map) {
      throw const FormatException('Kitap kaydı geçersiz');
    }
  }
  for (final loan in loans) {
    if (loan is! Map ||
        (loan['kind'] != null &&
            !['library', 'textbook'].contains(loan['kind'])) ||
        (loan['periodSnapshot'] != null && loan['periodSnapshot'] is! String)) {
      throw const FormatException('Bu ödünç türü henüz desteklenmiyor');
    }
    if (loan['memberID'] != null &&
        (loan['studentID'] != null ||
            loan['memberID'] is! String ||
            !memberIds.containsKey(
              (loan['memberID'] as String).toUpperCase(),
            ))) {
      throw const FormatException('Ödünç kaydının üyesi bulunamadı');
    }
    if (loan['studentID'] != null &&
        (loan['studentID'] is! String ||
            !studentIds.containsKey(
              (loan['studentID'] as String).toUpperCase(),
            ))) {
      throw const FormatException('Ödünç kaydının öğrencisi bulunamadı');
    }
  }
  var mapped = mapIphoneCatalog(books, loans);
  for (final book in mapped) {
    for (final loan in book['loans'] as List) {
      final original = loan['iphoneOriginal'];
      if (original is Map && original['studentID'] is String) {
        loan['studentId'] =
            studentIds[(original['studentID'] as String).toUpperCase()];
      }
      if (original is Map && original['memberID'] is String) {
        loan['memberId'] =
            memberIds[(original['memberID'] as String).toUpperCase()];
      }
    }
  }
  final copyBytes = archive.readEntry('nushalar.json');
  if (copyBytes != null) {
    mapped = prepareIPhoneCopies(mapped, jsonDecode(utf8.decode(copyBytes)));
  } else if (loans.any((loan) => loan is Map && loan['copyID'] != null)) {
    throw const FormatException('Ödünç nüsha kayıtları arşivde eksik');
  }
  final reservationBytes = archive.readEntry('rezervasyonlar.json');
  if (reservationBytes != null) {
    final data = jsonDecode(utf8.decode(reservationBytes));
    if (data is! List)
      throw const FormatException('Rezervasyon listesi geçersiz');
    final byBook = {
      for (final book in mapped) (book['id'] as String).toUpperCase(): book,
    };
    final ids = <String>{};
    for (final r in data) {
      if (r is! Map ||
          r['id'] is! String ||
          !ids.add((r['id'] as String).toUpperCase()) ||
          r['bookID'] is! String ||
          (r['memberID'] != null &&
              (r['memberID'] is! String ||
                  r['studentID'] != null ||
                  (r['isClosed'] != true &&
                      !memberIds.containsKey(
                        (r['memberID'] as String).toUpperCase(),
                      )))) ||
          (r['studentID'] != null &&
              (r['studentID'] is! String ||
                  !studentIds.containsKey(
                    (r['studentID'] as String).toUpperCase(),
                  )))) {
        throw const FormatException(
          'Rezervasyon kimliği veya öğrenci bağlantısı geçersiz',
        );
      }
      final book = byBook[(r['bookID'] as String).toUpperCase()];
      if (book == null)
        throw const FormatException('Rezervasyonun kitabı bulunamadı');
      final entry = <String, dynamic>{
        'id': r['id'],
        'name': r['studentName'],
        'studentClass': r['studentClass'],
        'createdAt': r['createdAt'],
        'isClosed': r['isClosed'],
        if (r['studentID'] != null)
          'studentId': studentIds[(r['studentID'] as String).toUpperCase()],
        if (r['memberID'] != null)
          'memberId':
              memberIds[(r['memberID'] as String).toUpperCase()] ??
              r['memberID'],
        if (r['copyID'] != null) 'copyId': r['copyID'],
        if (r['notifiedAt'] != null) 'notifiedAt': r['notifiedAt'],
        if (r['expiresAt'] != null) 'expiresAt': r['expiresAt'],
        if (r['closedAt'] != null) 'closedAt': r['closedAt'],
        if (r['closureKind'] != null) 'closureKind': r['closureKind'],
        'iphoneOriginal': Map<String, dynamic>.from(r),
      };
      validateReservations([entry]);
      (book['reservations'] ??= <Map<String, dynamic>>[]).add(entry);
    }
    for (final book in mapped) {
      validateReservations(book['reservations'] ?? []);
      validateReservationHolds(book);
    }
  }
  final eventBytes = archive.readEntry('odunc-gecmisi.json');
  if (eventBytes != null) {
    final events = jsonDecode(utf8.decode(eventBytes));
    if (events is! List) throw const FormatException('Ödünç geçmişi geçersiz');
    final byBook = {for (final book in mapped) book['id'] as String: book};
    final eventIds = <String>{};
    const kinds = {
      'Ödünç verildi': 'lent',
      'İade alındı': 'returned',
      'Kayıp bildirildi': 'lost',
      'Süre uzatıldı': 'extended',
      'Kimlik düzeltildi': 'identityCorrected',
    };
    for (final event in events) {
      if (event is! Map ||
          event['id'] is! String ||
          (event['id'] as String).isEmpty ||
          !eventIds.add(event['id'] as String) ||
          event['bookID'] is! String ||
          event['person'] is! String ||
          event['date'] is! String ||
          DateTime.tryParse(event['date'] as String) == null ||
          !kinds.containsKey(event['kind']) ||
          (event['readingCompleted'] != null &&
              event['readingCompleted'] is! bool) ||
          (event['returnedCondition'] != null &&
              event['returnedCondition'] is! String) ||
          (event['copyID'] != null && event['copyID'] is! String) ||
          (event['studentID'] != null && event['studentID'] is! String) ||
          (event['identitySource'] != null &&
              event['identitySource'] is! String) ||
          (event['memberID'] != null &&
              (event['memberID'] is! String || event['studentID'] != null)) ||
          (event['wasLate'] != null && event['wasLate'] is! bool) ||
          (event['loanKind'] != null &&
              !['library', 'textbook'].contains(event['loanKind'])) ||
          (event['periodSnapshot'] != null &&
              event['periodSnapshot'] is! String)) {
        throw const FormatException('iPhone ödünç geçmişi geçersiz');
      }
      final book = byBook[event['bookID']];
      if (book == null)
        throw const FormatException('Geçmişteki kitabın kaydı bulunamadı');
      final history =
          (book['history'] as List<Map<String, dynamic>>?) ??
          <Map<String, dynamic>>[];
      history.add({
        'kind': kinds[event['kind']],
        if (event['loanKind'] == 'textbook') 'loanKind': 'textbook',
        if (event['periodSnapshot'] != null)
          'periodSnapshot': event['periodSnapshot'],
        if (event['studentNumberSnapshot'] is String)
          'studentNumberSnapshot': event['studentNumberSnapshot'],
        'person': event['person'],
        'date': event['date'],
        'due': event['dueDate'],
        'late': event['wasLate'] ?? false,
        if (event['returnedCondition'] != null)
          'returnedCondition': event['returnedCondition'],
        if (event['readingCompleted'] != null)
          'readingCompleted': event['readingCompleted'],
        if (event['identitySource'] is String)
          'identitySource': event['identitySource'],
        if (event['copyID'] != null) 'copyId': event['copyID'],
        if (event['studentID'] is String) 'studentId': event['studentID'],
        if (event['memberID'] is String) 'memberId': event['memberID'],
        'studentClass': event['classSnapshot'],
        'loanId': event['loanID'],
        'iphoneOriginal': Map<String, dynamic>.from(event),
      });
      book['history'] = history;
    }
  }
  final byId = {
    for (final book in mapped) (book['id'] as String).toUpperCase(): book,
  };
  if (byId.length != mapped.length)
    throw const FormatException('Kitap kimlikleri çakışıyor');
  var totalCoverBytes = 0;
  for (final name in archive.entryNames.where(isIPhoneImageEntry)) {
    final prefix = name.startsWith('kapaklar/')
        ? 'kapaklar/'
        : name.startsWith('arka/')
        ? 'arka/'
        : 'kunye/';
    final imageKey = prefix == 'kapaklar/'
        ? 'coverBase64'
        : prefix == 'arka/'
        ? 'backCoverBase64'
        : 'imprintBase64';
    final id = name.substring(prefix.length, name.length - 4).toUpperCase();
    final book = byId[id];
    if (book == null || book.containsKey(imageKey))
      throw const FormatException('Görsel kitap kaydıyla eşleşmiyor');
    final data = archive.readEntry(name)!;
    totalCoverBytes += data.length;
    if (BookImageStore.extensionOf(data) == null ||
        data.length > maxBookImageBytes ||
        (imageSink == null && totalCoverBytes > maxIPhoneImagesBytes)) {
      throw const FormatException(
        'Kapak biçimi desteklenmiyor veya boyut sınırını aşıyor',
      );
    }
    book[imageKey] = imageSink == null ? base64Encode(data) : imageSink(data);
  }
  return mapped;
}

List<Member>? prepareIPhoneMembers(VerifiedIPhoneArchive archive) {
  final bytes = archive.readEntry('uyeler.json');
  return bytes == null ? null : decodeMembers(utf8.decode(bytes));
}

void _validatePreservedObject(dynamic value) {
  if (value is! Map)
    throw const FormatException('iPhone destek verisi geçersiz');
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw const FormatException('iPhone destek verisi geçersiz');
    }
    try {
      base64Decode(entry.value as String);
    } catch (_) {
      throw const FormatException('iPhone destek verisi geçersiz');
    }
  }
}

/// Original settings and supporting files are retained but not applied.
Map<String, dynamic> prepareIPhoneSupplement(VerifiedIPhoneArchive archive) {
  final result = <String, dynamic>{};
  for (final name in ['ayarlar.json', 'destek-dosyalari.json']) {
    final bytes = archive.readEntry(name);
    if (bytes == null) continue;
    final value = jsonDecode(utf8.decode(bytes));
    _validatePreservedObject(value);
    if ((value as Map).isNotEmpty) result[name] = value;
  }
  return result;
}

/// Missing roster sections leave existing Android students unchanged.
List<Student>? prepareIPhoneStudents(VerifiedIPhoneArchive archive) {
  final bytes = archive.readEntry('ogrenciler.json');
  final graduateBytes = archive.readEntry('mezunlar.json');
  if (bytes == null && graduateBytes != null)
    throw const FormatException('Mezunlar için öğrenci listesi eksik');
  if (bytes == null) return null;
  final students = decodeStudents(utf8.decode(bytes));
  if (graduateBytes != null) {
    final graduates = jsonDecode(utf8.decode(graduateBytes));
    if (graduates is! List)
      throw const FormatException('Mezun listesi geçersiz');
    for (final record in graduates) {
      if (record is! Map ||
          record['student'] is! Map ||
          record['graduatedAt'] is! String ||
          DateTime.tryParse(record['graduatedAt'] as String) == null) {
        throw const FormatException('Mezun kaydı geçersiz');
      }
      final original = Student.fromJson(record['student']);
      if (original.graduatedAt != null)
        throw const FormatException('Mezun kaydı tutarsız');
      students.add(
        Student(
          id: original.id,
          name: original.name,
          number: original.number,
          className: original.className,
          graduatedAt: record['graduatedAt'] as String,
        ),
      );
    }
  }
  final ids = <String>{};
  for (final student in students) {
    if (!ids.add(student.id.toUpperCase())) {
      throw const FormatException('Öğrenci kimlikleri çakışıyor');
    }
  }
  return students;
}


/// Bir aktarım turunun isolate'tan gönderilebilir sonucu.
class IPhoneImportPass {
  const IPhoneImportPass({
    required this.summaryBooks,
    required this.summaryLoans,
    required this.summaryEntries,
    this.books,
    this.students,
    this.members,
    this.supplement,
    this.blockedReason,
    this.images = 0,
    this.scanFiles = 0,
  });
  final int summaryBooks;
  final int summaryLoans;
  final int summaryEntries;
  final List<Map<String, dynamic>>? books;
  final List<Student>? students;
  final List<Member>? members;
  final Map<String, dynamic>? supplement;
  final String? blockedReason;
  final int images;
  final int scanFiles;

  /// Aktarılacak içeriğin özeti. Doğrulama ve yazma turları aynı arşivden
  /// geldiyse eşittir; eşit değilse arşiv iki okuma arasında değişmiştir.
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'books': books,
            'students': students?.map((s) => s.toJson()).toList(),
            'members': members?.map((m) => m.toJson()).toList(),
            'supplement': supplement,
            'blocked': blockedReason,
          }),
        ),
      )
      .toString();
}

/// [imagesPath] null ise doğrulama turudur: görseller için yalnız referans
/// hesaplanır, diske hiçbir şey yazılmaz. Yazma turunda görseller içerik
/// adresli depoya, tarama kayıtları [preserveDir] altına kaydedilir. Yazma
/// turunda bir hata, kataloğa dokunulmadan istisna olarak yükselir.
IPhoneImportPass runIPhoneImportPass(
  String path, {
  String? imagesPath,
  String? preserveDir,
}) {
  final archive = readIPhoneZipFile(path);
  try {
    final summary = archive.summary;
    final images = archive.entryNames.where(isIPhoneImageEntry).length;
    final scanFiles = archive.entryNames
        .where(iphonePreservedScanFiles.contains)
        .length;
    final store = imagesPath == null
        ? null
        : BookImageStore(Directory(imagesPath));
    try {
      final books = prepareIPhoneCatalogImport(
        archive,
        imageSink: store == null ? BookImageStore.refFor : store.put,
      );
      final students = prepareIPhoneStudents(archive);
      final members = prepareIPhoneMembers(archive);
      final supplement = prepareIPhoneSupplement(archive);
      // Ödünç ayarları da önizlemede doğrulanır: geçersiz ayar kataloğa
      // yazılmadan önce aktarımı durdurur.
      LoanSettings.fromSupplement(supplement);
      if (preserveDir != null) {
        preserveIPhoneScanFiles(archive, Directory(preserveDir));
      }
      return IPhoneImportPass(
        summaryBooks: summary.books,
        summaryLoans: summary.loans,
        summaryEntries: summary.entries,
        books: books,
        students: students,
        members: members,
        supplement: supplement,
        images: images,
        scanFiles: scanFiles,
      );
    } on FormatException catch (failure) {
      if (store != null) rethrow;
      return IPhoneImportPass(
        summaryBooks: summary.books,
        summaryLoans: summary.loans,
        summaryEntries: summary.entries,
        blockedReason: failure.message,
      );
    }
  } finally {
    archive.close();
  }
}
