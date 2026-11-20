import 'inventory_session.dart';
import 'book_images.dart';
import 'dart:convert';
import 'dart:io';
import 'loan_model.dart';
import 'student_store.dart';
import 'member_store.dart';
import 'student_csv.dart';
import 'copy_model.dart';
import 'reservation_model.dart';

const maxAndroidBackupBytes = 50 * 1024 * 1024;
const maxBookImageBytes = 4 * 1024 * 1024;
const maxBookImageBase64Length = ((maxBookImageBytes + 2) ~/ 3) * 4;

Map<String, dynamic> validateIPhoneSupplement(dynamic value) {
  if (value is! Map)
    throw const FormatException('iPhone destek verisi geçersiz');
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (!['ayarlar.json', 'destek-dosyalari.json'].contains(entry.key) ||
        entry.value is! Map) {
      throw const FormatException('iPhone destek verisi geçersiz');
    }
    final values = <String, String>{};
    for (final part in (entry.value as Map).entries) {
      if (part.key is! String || part.value is! String)
        throw const FormatException('iPhone destek verisi geçersiz');
      try {
        base64Decode(part.value as String);
      } catch (_) {
        throw const FormatException('iPhone destek verisi geçersiz');
      }
      values[part.key as String] = part.value as String;
    }
    result[entry.key as String] = values;
  }
  return result;
}

String encodeAndroidBackup(
  List<Map<String, dynamic>> books, {
  List<Student>? students,
  List<Member>? members,
  Map<String, dynamic>? iphoneSupplement,
  bool includeInventory = false,
  InventorySession? inventorySession,
  List<InventoryArchive>? inventoryHistory,
  int maxBytes = maxAndroidBackupBytes,
}) {
  if (includeInventory && (students == null || members == null))
    throw const FormatException(
      'Sayım yedeği için öğrenci ve üye listesi gerekli',
    );
  if (inventoryHistory != null && !includeInventory)
    throw const FormatException('Sayım yedeği etkin değil');
  if (inventoryHistory != null)
    parseInventoryHistory(inventoryHistory.map((e) => e.toJson()).toList());
  if (inventorySession != null && !includeInventory)
    throw const FormatException('Sayım yedeği etkin değil');
  if (inventorySession != null)
    InventorySession.fromJson(inventorySession.toJson());
  if (members != null && students == null)
    throw const FormatException('Öğrenci listesi eksik');
  if (iphoneSupplement != null && students == null)
    throw const FormatException('Öğrenci listesi eksik');
  if (iphoneSupplement != null) validateIPhoneSupplement(iphoneSupplement);
  final data = jsonEncode({
    'format': 'kitapbul-android',
    'version': inventoryHistory != null
        ? 6
        : includeInventory
        ? 5
        : members != null
        ? 4
        : (iphoneSupplement != null ? 3 : (students == null ? 1 : 2)),
    'books': books,
    if (students != null) 'students': students.map((s) => s.toJson()).toList(),
    if (members != null) 'members': members.map((m) => m.toJson()).toList(),
    if (iphoneSupplement != null) 'iphoneSupplement': iphoneSupplement,
    if (includeInventory) 'inventorySession': inventorySession?.toJson(),
    if (inventoryHistory != null)
      'inventoryHistory': inventoryHistory.map((e) => e.toJson()).toList(),
  });
  if (utf8.encode(data).length > maxBytes) {
    throw FormatException(
      'Yedek ${maxBytes ~/ (1024 * 1024)} MB sınırını aşıyor',
    );
  }
  return data;
}

class CatalogStore {
  CatalogStore(this.directory);
  final Directory directory;
  File get current => File('${directory.path}/books.json');
  File get backup => File('${directory.path}/books.backup.json');

  List<Map<String, dynamic>> decode(String raw) => _bookList(
    raw,
  ).map((e) => normalizeBook(Map<String, dynamic>.from(e as Map))).toList();

  List<dynamic> _bookList(String raw) {
    final value = jsonDecode(raw);
    if (value is List) {
      validateMemberLinks(value, []);
      return value;
    }
    if (value is Map && value['books'] is List && value['students'] is List) {
      decodeStudents(jsonEncode(value['students']));
      final members = value['members'] == null
          ? <Member>[]
          : decodeMembers(jsonEncode(value['members']));
      validateMemberLinks(value['books'] as List, members);
      if (value['inventoryHistory'] != null)
        parseInventoryHistory(value['inventoryHistory']);
      if (value['inventorySession'] != null)
        InventorySession.fromJson(value['inventorySession']);
      if (value['studentImportReceipt'] != null)
        StudentImportReceipt.parse(value['studentImportReceipt']);
      if (value['iphoneSupplement'] != null)
        validateIPhoneSupplement(value['iphoneSupplement']);
      return value['books'] as List;
    }
    throw const FormatException('Katalog biçimi geçersiz');
  }

  Future<InventorySession?> loadInventory() async {
    if (!await current.exists()) return null;
    final raw = await current.readAsString();
    _bookList(raw);
    final value = jsonDecode(raw);
    return value is Map && value['inventorySession'] != null
        ? InventorySession.fromJson(value['inventorySession'])
        : null;
  }

  Future<List<InventoryArchive>> loadInventoryHistory() async {
    if (!await current.exists()) return [];
    final raw = await current.readAsString();
    _bookList(raw);
    final value = jsonDecode(raw);
    return value is Map && value['inventoryHistory'] != null
        ? parseInventoryHistory(value['inventoryHistory'])
        : [];
  }

  Future<List<Student>> loadStudents() async {
    if (!await current.exists()) return [];
    final raw = await current.readAsString();
    final value = jsonDecode(raw);
    _bookList(raw);
    return value is List ? [] : decodeStudents(jsonEncode(value['students']));
  }

  Future<StudentImportReceipt?> loadStudentImportReceipt() async {
    if (!await current.exists()) return null;
    final raw = await current.readAsString();
    _bookList(raw);
    final value = jsonDecode(raw);
    if (value is! Map || value['studentImportReceipt'] == null) return null;
    return StudentImportReceipt.parse(value['studentImportReceipt']);
  }

  Future<Map<String, dynamic>?> loadIPhoneSupplement() async {
    if (!await current.exists()) return null;
    final raw = await current.readAsString();
    _bookList(raw);
    final value = jsonDecode(raw);
    if (value is! Map || value['iphoneSupplement'] == null) return null;
    return validateIPhoneSupplement(value['iphoneSupplement']);
  }

  Future<List<Map<String, dynamic>>> load() async =>
      await current.exists() ? decode(await current.readAsString()) : [];

  Future<
    ({
      List<Map<String, dynamic>> books,
      List<Student> students,
      List<Member> members,
      Map<String, dynamic>? supplement,
    })
  >
  loadBundle() async {
    if (!await current.exists())
      return (
        books: <Map<String, dynamic>>[],
        students: <Student>[],
        members: <Member>[],
        supplement: null,
      );
    final raw = await current.readAsString();
    final books = decode(raw);
    final value = jsonDecode(raw);
    if (value is! Map)
      return (
        books: books,
        students: <Student>[],
        members: <Member>[],
        supplement: null,
      );
    return (
      books: books,
      students: decodeStudents(jsonEncode(value['students'])),
      members: value['members'] == null
          ? <Member>[]
          : decodeMembers(jsonEncode(value['members'])),
      supplement: value['iphoneSupplement'] == null
          ? null
          : validateIPhoneSupplement(value['iphoneSupplement']),
    );
  }

  Future<bool> hasValidBackup() async {
    try {
      if (!await backup.exists()) return false;
      decode(await backup.readAsString());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> save(
    List<Map<String, dynamic>> books, {
    List<Student>? students,
    List<Member>? members,
    StudentImportReceipt? importReceipt,
    bool clearImportReceipt = false,
    Map<String, dynamic>? iphoneSupplement,
    bool clearIPhoneSupplement = false,
    InventorySession? inventorySession,
    bool clearInventorySession = false,
    List<InventoryArchive>? inventoryHistory,
  }) async {
    final oldData = await current.exists()
        ? await current.readAsString()
        : null;
    final oldValue = oldData == null ? null : jsonDecode(oldData);
    final hasRoster = oldValue is Map;
    if (oldData != null) _bookList(oldData);
    final roster =
        students ??
        (hasRoster
            ? decodeStudents(jsonEncode(oldValue['students']))
            : <Student>[]);
    final memberRoster =
        members ??
        (hasRoster && oldValue['members'] != null
            ? decodeMembers(jsonEncode(oldValue['members']))
            : <Member>[]);
    final receipt = clearImportReceipt
        ? null
        : (importReceipt ??
              (hasRoster && oldValue['studentImportReceipt'] != null
                  ? StudentImportReceipt.parse(oldValue['studentImportReceipt'])
                  : null));
    final supplement = clearIPhoneSupplement
        ? null
        : (iphoneSupplement ??
              (hasRoster && oldValue['iphoneSupplement'] != null
                  ? validateIPhoneSupplement(oldValue['iphoneSupplement'])
                  : null));
    final inventory = clearInventorySession
        ? null
        : inventorySession ??
              (hasRoster && oldValue['inventorySession'] != null
                  ? InventorySession.fromJson(oldValue['inventorySession'])
                  : null);
    if (inventory != null) InventorySession.fromJson(inventory.toJson());
    final history =
        inventoryHistory ??
        (hasRoster && oldValue['inventoryHistory'] != null
            ? parseInventoryHistory(oldValue['inventoryHistory'])
            : <InventoryArchive>[]);
    parseInventoryHistory(history.map((e) => e.toJson()).toList());
    final data =
        students != null ||
            members != null ||
            hasRoster ||
            supplement != null ||
            inventory != null ||
            history.isNotEmpty
        ? jsonEncode({
            'books': books,
            'students': roster.map((s) => s.toJson()).toList(),
            if (members != null || (hasRoster && oldValue['members'] != null))
              'members': memberRoster.map((m) => m.toJson()).toList(),
            if (receipt != null) 'studentImportReceipt': receipt.toJson(),
            if (supplement != null) 'iphoneSupplement': supplement,
            if (inventory != null) 'inventorySession': inventory.toJson(),
            if (history.isNotEmpty)
              'inventoryHistory': history.map((e) => e.toJson()).toList(),
          })
        : jsonEncode(books);
    decode(data);
    if (await current.exists()) {
      final previous = await current.readAsString();
      decode(previous); // Never replace a backup with an unreadable catalog.
      final backupTemp = File('${directory.path}/books.backup.tmp');
      await backupTemp.writeAsString(previous, flush: true);
      await backupTemp.rename(backup.path);
    }
    final temp = File('${directory.path}/books.tmp');
    await temp.writeAsString(data, flush: true);
    await temp.rename(current.path);
  }

  /// iPhone aktarımından önce mevcut kataloğun üzerine yazılmayan kopyası.
  /// Kopya bayt bayt karşılaştırılır ve çözümlenir; doğrulanamazsa hata
  /// fırlatır ve aktarım yapılmamalıdır. Katalog yoksa null döner.
  Future<File?> snapshotBeforeIPhoneImport({
    DateTime? now,
    String label = 'pre-iphone-import',
  }) async {
    if (!await current.exists()) return null;
    final original = await current.readAsBytes();
    decode(utf8.decode(original));
    final stamp = (now ?? DateTime.now()).toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9TZ]'),
      '',
    );
    var target = File('${directory.path}/books.$label.$stamp.json');
    for (var i = 1; await target.exists(); i++) {
      target = File(
        '${directory.path}/books.$label.$stamp-$i.json',
      );
    }
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(original, flush: true);
    await temp.rename(target.path);
    final copy = await target.readAsBytes();
    if (copy.length != original.length) {
      throw const FileSystemException('Yedek doğrulanamadı');
    }
    for (var i = 0; i < copy.length; i++) {
      if (copy[i] != original[i]) {
        throw const FileSystemException('Yedek doğrulanamadı');
      }
    }
    decode(utf8.decode(copy));
    return target;
  }

  /// Preserve the unreadable original before restoring the verified backup.
  Future<List<Map<String, dynamic>>> restoreBackup() async {
    final data = await backup.readAsString();
    final restored = decode(data);
    if (await current.exists()) {
      final evidence = File(
        '${directory.path}/books.damaged.${DateTime.now().microsecondsSinceEpoch}.json',
      );
      await current.copy(evidence.path);
    }
    final temp = File('${directory.path}/books.restore.tmp');
    await temp.writeAsString(data, flush: true);
    await temp.rename(current.path);
    return restored;
  }
}

/// Accept only this application's explicit versioned export format.
/// [availableImageRefs] verilirse (ZIP yedeği) `file:` referansı cihazdaki
/// depoya değil, arşivde doğrulanmış görsel kümesine göre sınanır.
List<Map<String, dynamic>> parseAndroidBackup(
  String source, {
  Set<String>? availableImageRefs,
}) {
  final value = jsonDecode(source);
  if (value is! Map ||
      value['format'] != 'kitapbul-android' ||
      ![1, 2, 3, 4, 5, 6].contains(value['version']) ||
      value['books'] is! List) {
    throw const FormatException('Desteklenmeyen yedek biçimi');
  }
  if ([2, 3, 4, 5, 6].contains(value['version'])) {
    if (value['students'] is! List)
      throw const FormatException('Öğrenci listesi eksik');
    decodeStudents(jsonEncode(value['students']));
  }
  if (value['version'] == 3 ||
      ([4, 5, 6].contains(value['version']) &&
          value['iphoneSupplement'] != null)) {
    validateIPhoneSupplement(value['iphoneSupplement']);
  }
  if ([4, 5, 6].contains(value['version'])) {
    if (value['members'] is! List)
      throw const FormatException('Üye listesi eksik');
    decodeMembers(jsonEncode(value['members']));
  }
  if ([5, 6].contains(value['version'])) {
    if (!value.containsKey('inventorySession'))
      throw const FormatException('Sayım verisi eksik');
    if (value['inventorySession'] != null)
      InventorySession.fromJson(value['inventorySession']);
  }
  if (value['version'] == 6) {
    if (!value.containsKey('inventoryHistory'))
      throw const FormatException('Sayım geçmişi eksik');
    parseInventoryHistory(value['inventoryHistory']);
  }
  final memberRoster = [4, 5, 6].contains(value['version'])
      ? decodeMembers(jsonEncode(value['members']))
      : <Member>[];
  validateMemberLinks(value['books'] as List, memberRoster);
  final books = <Map<String, dynamic>>[];
  final ids = <String>{};
  for (final item in value['books'] as List) {
    if (item is! Map ||
        item['id'] is! String ||
        (item['id'] as String).isEmpty ||
        !ids.add(item['id'] as String) ||
        item['title'] is! String ||
        (item['title'] as String).trim().isEmpty ||
        item['author'] is! String ||
        item['isbn'] is! String ||
        item['shelf'] is! String ||
        item['quantity'] is! int ||
        (item['quantity'] as int) < 1 ||
        item['loans'] is! List) {
      throw const FormatException('Yedekte geçersiz kitap kaydı var');
    }
    final loanIds = <String>{};
    for (final loan in item['loans'] as List) {
      if (loan is! Map ||
          loan['id'] is! String ||
          (loan['id'] as String).trim().isEmpty ||
          !loanIds.add(loan['id'] as String) ||
          (loan['kind'] != null &&
              !['library', 'textbook'].contains(loan['kind'])) ||
          (loan['periodSnapshot'] != null &&
              loan['periodSnapshot'] is! String) ||
          (loan['studentClass'] != null && loan['studentClass'] is! String) ||
          (loan['studentId'] != null &&
              (loan['studentId'] is! String ||
                  (loan['studentId'] as String).isEmpty)) ||
          (loan['identitySource'] != null &&
              loan['identitySource'] is! String) ||
          (loan['needsIdentityReview'] != null &&
              loan['needsIdentityReview'] is! bool) ||
          loan['name'] is! String ||
          (loan['name'] as String).trim().isEmpty ||
          (loan['due'] != null &&
              DateTime.tryParse(loan['due'].toString()) == null)) {
        throw const FormatException('Yedekte geçersiz ödünç kaydı var');
      }
    }
    if ((item['lostCount'] != null &&
            (item['lostCount'] is! int || (item['lostCount'] as int) < 0)) ||
        (item['loans'] as List).length + ((item['lostCount'] as int?) ?? 0) >
            (item['quantity'] as int) ||
        (item['history'] != null && item['history'] is! List)) {
      throw const FormatException('Yedekte tutarsız kayıt var');
    }
    if (item['copies'] != null) {
      final copies = validateCopies(
        item['copies'],
        bookId: item['id'] as String,
        quantity: item['quantity'] as int,
      );
      final trackedLost = copies
          .where((copy) => copy['status'] == 'Kayıp')
          .length;
      final loans = (item['loans'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      validateCopyLoans(
        copies,
        loans,
        item['quantity'] as int,
        otherLost: ((item['lostCount'] as int?) ?? 0) - trackedLost,
      );
    } else if ((item['loans'] as List).any(
      (loan) => (loan as Map)['copyId'] != null,
    )) {
      throw const FormatException('Ödünç için nüsha kaydı eksik');
    }
    for (final imageKey in [
      'coverBase64',
      'backCoverBase64',
      'imprintBase64',
    ]) {
      if (item[imageKey] == null) continue;
      // Dışa aktarım görselleri satır içine çevirir; dış yedekte referans
      // yalnız bu cihazda dosyası var ve içeriği doğrulanıyorsa kabul edilir.
      // Aksi hâlde geri yükleme sessizce kapaksız kitaplar üretirdi.
      if (BookImageStore.isRef(item[imageKey])) {
        if (availableImageRefs != null
            ? availableImageRefs.contains(item[imageKey])
            : BookImageStore.instance?.hasValid(item[imageKey] as String) ==
                  true) {
          continue;
        }
        throw const FormatException('Yedekteki görsel dosyası eksik');
      }
      if (item[imageKey] is! String ||
          (item[imageKey] as String).length > maxBookImageBase64Length)
        throw const FormatException('Görsel verisi geçersiz');
      try {
        if (base64Decode(item[imageKey] as String).length > maxBookImageBytes) {
          throw const FormatException('Görsel verisi geçersiz');
        }
      } catch (_) {
        throw const FormatException('Görsel verisi geçersiz');
      }
    }
    for (final key in [
      'publisher',
      'category',
      'series',
      'language',
      'tags',
      'readingLevel',
      'readingStatus',
      'contentWarning',
      'accessionCode',
      'publicationYear',
      'edition',
      'pageCount',
      'notes',
      'deletedAt',
      'withdrawnReason',
      'withdrawnDate',
    ]) {
      if (item[key] != null && item[key] is! String) {
        throw const FormatException('Yedekte geçersiz kitap alanı var');
      }
    }
    if (item['isWithdrawn'] != null && item['isWithdrawn'] is! bool) {
      throw const FormatException('Yedekte geçersiz düşülme durumu var');
    }
    if (item['withdrawnDate'] != null &&
        DateTime.tryParse(item['withdrawnDate'] as String) == null) {
      throw const FormatException('Yedekte geçersiz düşülme tarihi var');
    }
    for (final key in ['volume', 'rating']) {
      if (item[key] != null && item[key] is! int)
        throw const FormatException('Yedekte geçersiz sayısal kitap alanı var');
    }
    if (item['deletedAt'] != null && (item['loans'] as List).isNotEmpty) {
      throw const FormatException('Silinmiş kitapta etkin ödünç var');
    }
    if (item['deletedAt'] != null &&
        item['reservations'] != null &&
        validateReservations(item['reservations']).any(isActiveReservation)) {
      throw const FormatException('Silinmiş kitapta açık rezervasyon var');
    }
    for (final event in (item['history'] as List?) ?? []) {
      if (event is! Map ||
          event['person'] is! String ||
          event['kind'] is! String ||
          ![
            'lent',
            'returned',
            'extended',
            'lost',
            'identityCorrected',
          ].contains(event['kind']) ||
          event['date'] is! String ||
          DateTime.tryParse(event['date'] as String) == null ||
          (event['identitySource'] != null &&
              event['identitySource'] is! String) ||
          (event['loanKind'] != null &&
              !['library', 'textbook'].contains(event['loanKind'])) ||
          (event['periodSnapshot'] != null &&
              event['periodSnapshot'] is! String) ||
          (event['readingCompleted'] != null &&
              event['readingCompleted'] is! bool) ||
          (event['returnedCondition'] != null &&
              event['returnedCondition'] is! String) ||
          (event['late'] != null && event['late'] is! bool)) {
        throw const FormatException('Yedekte geçersiz hareket geçmişi var');
      }
    }
    books.add(normalizeBook(Map<String, dynamic>.from(item)));
  }
  return books;
}

/// Old version-one backups do not contain a roster and must not erase it.
List<Student>? parseBackupStudents(String source) {
  parseAndroidBackup(source);
  final value = jsonDecode(source) as Map;
  return value['version'] == 1
      ? null
      : decodeStudents(jsonEncode(value['students']));
}

Map<String, dynamic>? parseBackupIPhoneSupplement(String source) {
  parseAndroidBackup(source);
  final value = jsonDecode(source) as Map;
  return [3, 4, 5, 6].contains(value['version']) &&
          value['iphoneSupplement'] != null
      ? validateIPhoneSupplement(value['iphoneSupplement'])
      : null;
}

List<Member>? parseBackupMembers(String source) {
  parseAndroidBackup(source);
  final value = jsonDecode(source) as Map;
  return [4, 5, 6].contains(value['version'])
      ? decodeMembers(jsonEncode(value['members']))
      : null;
}

/// Older backups have no sayım data and do not replace the current session.
({bool present, InventorySession? session}) parseBackupInventory(
  String source,
) {
  parseAndroidBackup(source);
  final value = jsonDecode(source) as Map;
  if (![5, 6].contains(value['version']))
    return (present: false, session: null);
  return (
    present: true,
    session: value['inventorySession'] == null
        ? null
        : InventorySession.fromJson(value['inventorySession']),
  );
}

/// Only version 6 explicitly contains archived counts. Older backups preserve them.
List<InventoryArchive>? parseBackupInventoryHistory(String source) {
  parseAndroidBackup(source);
  final value = jsonDecode(source) as Map;
  return value['version'] == 6
      ? parseInventoryHistory(value['inventoryHistory'])
      : null;
}
