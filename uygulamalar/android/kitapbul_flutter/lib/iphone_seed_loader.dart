import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'book_images.dart';
import 'catalog_store.dart';
import 'loan_model.dart';
import 'student_store.dart';

class IPhoneSeedResult {
  const IPhoneSeedResult({
    required this.seeded,
    required this.addedBooks,
    required this.updatedCovers,
    required this.addedStudents,
    required this.totalBooks,
  });

  final bool seeded;
  final int addedBooks;
  final int updatedCovers;
  final int addedStudents;
  final int totalBooks;
}

const _seedMarkerName = 'iphone_2892_seed_v1.done';

Future<void> _copyAssetFileIfNeeded(String assetPath, File target) async {
  final byteData = await rootBundle.load(assetPath);
  final bytes = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  if (await target.exists()) {
    try {
      if (await target.length() == bytes.length) return;
    } catch (_) {}
  }
  await target.parent.create(recursive: true);
  final tmp = File('${target.path}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(target.path);
}

Future<void> _ensureImagePacksInstalled(
  Directory docs, {
  void Function(String status)? onProgress,
}) async {
  final indexRaw = await rootBundle.loadString(
    'assets/seed/iphone_images_index.json',
  );
  final indexJson = jsonDecode(indexRaw) as Map<String, dynamic>;
  final shards = (indexJson['shards'] as List).cast<String>();

  for (var i = 0; i < shards.length; i++) {
    final shardName = shards[i];
    final target = File('${docs.path}/$shardName');
    if (!await target.exists()) {
      onProgress?.call(
        'iPhone kapak arşivi hazırlanıyor (${i + 1}/${shards.length})...',
      );
      await _copyAssetFileIfNeeded('assets/seed/$shardName', target);
    }
  }

  final indexTarget = File('${docs.path}/iphone_images_index.json');
  if (!await indexTarget.exists() ||
      await indexTarget.length() != utf8.encode(indexRaw).length) {
    final tmp = File('${indexTarget.path}.tmp');
    await tmp.writeAsString(indexRaw, flush: true);
    await tmp.rename(indexTarget.path);
  }
  BookImageStore.instance?.invalidatePackCache();
}

Future<void> _ensurePreservedScansInstalled(Directory docs) async {
  try {
    final metaRaw = await rootBundle.loadString(
      'assets/seed/iphone_preserved_bundle.json',
    );
    final meta = jsonDecode(metaRaw);
    if (meta is! Map || meta['files'] is! List) return;
    final preservedDir = Directory('${docs.path}/iphone-preserved');
    await preservedDir.create(recursive: true);
    final indexFile = File('${preservedDir.path}/index.json');
    final existing = await indexFile.exists()
        ? (jsonDecode(await indexFile.readAsString()) as List<dynamic>)
        : <dynamic>[];
    final knownFiles = {
      for (final item in existing)
        if (item is Map && item['file'] is String) item['file'] as String,
    };
    final updatedIndex = [...existing];
    final importedAt = DateTime.now().toUtc().toIso8601String();
    var changed = false;

    for (final entry in meta['files'] as List) {
      if (entry is! Map) continue;
      final name = entry['name'] as String;
      final expectedSha = entry['sha256'] as String;
      final manifestSha = entry['manifestSha256'] as String;
      final stem = name.substring(0, name.length - '.json'.length);
      final targetName = '$stem.$expectedSha.json';
      final target = File('${preservedDir.path}/$targetName');
      if (!await target.exists()) {
        final bd = await rootBundle.load('assets/seed/$name');
        final data = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
        if (sha256.convert(data).toString() != expectedSha) continue;
        final tmp = File('${target.path}.tmp');
        await tmp.writeAsBytes(data, flush: true);
        await tmp.rename(target.path);
      }
      if (!knownFiles.contains(targetName)) {
        updatedIndex.add({
          'name': name,
          'file': targetName,
          'sha256': expectedSha,
          'size': entry['size'],
          'manifestSha256': manifestSha,
          'importedAt': importedAt,
        });
        changed = true;
      }
    }

    if (changed) {
      final tmp = File('${indexFile.path}.tmp');
      await tmp.writeAsString(jsonEncode(updatedIndex), flush: true);
      await tmp.rename(indexFile.path);
    }
  } catch (_) {
    // Tarama geçmişi ikincildir; ana katalog aktarımını engellemez.
  }
}

/// Uygulama ilk açıldığında (veya kullanıcı eşitleme istediğinde) 2.892 kitaplık
/// iPhone arşivini, 2.896 kapak görselini ve Cumhuriyet Kütüphanesi nöbetçi
/// öğrenci listesini mevcut verileri silmeden birleştirir.
Future<IPhoneSeedResult> ensureBundledIPhoneCatalogSeeded(
  Directory docs,
  CatalogStore store, {
  bool forceResync = false,
  void Function(String status)? onProgress,
}) async {
  // Kapak paketleri her zaman yerinde olsun (kullanıcı yedeği geri yüklese bile).
  await _ensureImagePacksInstalled(docs, onProgress: onProgress);

  final marker = File('${docs.path}/$_seedMarkerName');
  if (!forceResync && await marker.exists()) {
    final current = await store.load();
    if (current.length >= 2800) {
      return IPhoneSeedResult(
        seeded: false,
        addedBooks: 0,
        updatedCovers: 0,
        addedStudents: 0,
        totalBooks: current.length,
      );
    }
  }

  onProgress?.call('2.892 iPhone kitap kaydı kütüphaneye aktarılıyor...');
  await _ensurePreservedScansInstalled(docs);

  final rawBundle = await rootBundle.loadString(
    'assets/seed/iphone_catalog_bundle.json',
  );
  final decoded = jsonDecode(rawBundle) as Map<String, dynamic>;
  final seedBooksRaw = decoded['books'] as List<dynamic>;
  final seedStudentsRaw = decoded['students'] as List<dynamic>;
  final seedSupplement = decoded['supplement'] as Map<String, dynamic>?;
  final seedDuty = decoded['dutySchedule'];

  // Nöbet çizelgesini henüz yoksa kaydet.
  final dutyFile = File('${docs.path}/school_duty_roster.json');
  if (seedDuty is Map && !await dutyFile.exists()) {
    final tmp = File('${dutyFile.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'version': 1, 'days': seedDuty, 'attendance': {}}),
      flush: true,
    );
    await tmp.rename(dutyFile.path);
  }

  final currentBundle = await store.loadBundle();
  await store.snapshotBeforeIPhoneImport(label: 'pre-iphone-2892-seed');

  final byUpperId = <String, Map<String, dynamic>>{
    for (final b in currentBundle.books)
      (b['id'] as String).toUpperCase(): Map<String, dynamic>.from(b),
  };

  var addedBooks = 0;
  var updatedCovers = 0;
  final mergedBooks = <Map<String, dynamic>>[...currentBundle.books];
  final indexByUpperId = <String, int>{
    for (var i = 0; i < mergedBooks.length; i++)
      (mergedBooks[i]['id'] as String).toUpperCase(): i,
  };

  for (final item in seedBooksRaw) {
    final incoming = normalizeBook(Map<String, dynamic>.from(item as Map));
    final key = (incoming['id'] as String).toUpperCase();
    final existingIdx = indexByUpperId[key];
    if (existingIdx == null) {
      mergedBooks.add(incoming);
      indexByUpperId[key] = mergedBooks.length - 1;
      byUpperId[key] = incoming;
      addedBooks++;
    } else {
      final current = Map<String, dynamic>.from(mergedBooks[existingIdx]);
      var patched = false;
      for (final imgKey in bookImageKeys) {
        if ((current[imgKey] == null ||
                (current[imgKey] is String &&
                    (current[imgKey] as String).isEmpty)) &&
            incoming[imgKey] != null) {
          current[imgKey] = incoming[imgKey];
          patched = true;
        }
      }
      for (final textKey in [
        'accessionCode',
        'shelf',
        'category',
        'publisher',
        'publicationYear',
        'pageCount',
      ]) {
        if ((current[textKey] ?? '').toString().trim().isEmpty &&
            (incoming[textKey] ?? '').toString().trim().isNotEmpty) {
          current[textKey] = incoming[textKey];
          patched = true;
        }
      }
      if (patched) {
        mergedBooks[existingIdx] = normalizeBook(current);
        updatedCovers++;
      }
    }
  }

  // Öğrencileri tekrarsız birleştir (ID veya numara+sınıf eşleşmesi).
  final mergedStudents = <Student>[...currentBundle.students];
  final existingStudentIds = {
    for (final s in mergedStudents) s.id.toUpperCase(),
  };
  final existingNumClass = {
    for (final s in mergedStudents)
      if (s.number.trim().isNotEmpty)
        '${s.number.trim()}|${s.className.trim().toUpperCase()}',
  };
  var addedStudents = 0;
  for (final rawStudent in seedStudentsRaw) {
    final student = Student.fromJson(rawStudent);
    final ncKey =
        '${student.number.trim()}|${student.className.trim().toUpperCase()}';
    if (existingStudentIds.contains(student.id.toUpperCase()) ||
        (student.number.trim().isNotEmpty &&
            existingNumClass.contains(ncKey))) {
      continue;
    }
    mergedStudents.add(student);
    existingStudentIds.add(student.id.toUpperCase());
    if (student.number.trim().isNotEmpty) existingNumClass.add(ncKey);
    addedStudents++;
  }

  final mergedSupplement = currentBundle.supplement ?? seedSupplement;

  await store.save(
    mergedBooks,
    students: mergedStudents,
    members: currentBundle.members,
    iphoneSupplement: mergedSupplement,
  );

  final markerTmp = File('${marker.path}.tmp');
  await markerTmp.writeAsString(
    jsonEncode({
      'seededAt': DateTime.now().toUtc().toIso8601String(),
      'addedBooks': addedBooks,
      'updatedCovers': updatedCovers,
      'addedStudents': addedStudents,
      'totalBooks': mergedBooks.length,
    }),
    flush: true,
  );
  await markerTmp.rename(marker.path);

  return IPhoneSeedResult(
    seeded: true,
    addedBooks: addedBooks,
    updatedCovers: updatedCovers,
    addedStudents: addedStudents,
    totalBooks: mergedBooks.length,
  );
}
