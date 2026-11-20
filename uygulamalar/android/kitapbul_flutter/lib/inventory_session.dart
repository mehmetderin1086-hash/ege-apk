import 'isbn.dart';
import 'loan_model.dart';

/// Frozen baseline and append-only scan events. Counting never changes stock.
class InventorySession {
  const InventorySession({
    required this.name,
    required this.operatorName,
    required this.startedAt,
    required this.entries,
    required this.events,
    this.location,
    this.outsideCodes = const [],
  });
  final String name, operatorName, startedAt;
  final String? location;
  final List<String> outsideCodes;
  final List<Map<String, dynamic>> entries, events;
  Map<String, dynamic> toJson() => {
    'name': name,
    'operatorName': operatorName,
    'startedAt': startedAt,
    'entries': entries,
    'events': events,
    if (location != null) 'location': location,
    if (outsideCodes.isNotEmpty) 'outsideCodes': outsideCodes,
  };
  factory InventorySession.fromJson(dynamic raw) {
    if (raw is! Map ||
        raw['name'] is! String ||
        (raw['name'] as String).trim().isEmpty ||
        raw['operatorName'] is! String ||
        (raw['operatorName'] as String).trim().isEmpty ||
        raw['startedAt'] is! String ||
        DateTime.tryParse(raw['startedAt'] as String) == null ||
        raw['entries'] is! List ||
        raw['events'] is! List ||
        (raw['entries'] as List).length > 10000 ||
        (raw['events'] as List).length > 100000)
      throw const FormatException('Sayım oturumu geçersiz');
    if (raw['location'] != null &&
        (raw['location'] is! String ||
            (raw['location'] as String).trim().isEmpty))
      throw const FormatException('Sayım konumu geçersiz');
    final outside = raw['outsideCodes'] ?? [];
    if (outside is! List ||
        outside.length > 100000 ||
        outside.any((e) => e is! String || e.isEmpty || e.length > 512))
      throw const FormatException('Sayım konumu geçersiz');
    final entries = <Map<String, dynamic>>[];
    final bookIds = <String>{}, copyIds = <String>{}, isbns = <String>{};
    for (final value in raw['entries'] as List) {
      if (value is! Map ||
          value['id'] is! String ||
          (value['id'] as String).isEmpty ||
          !bookIds.add((value['id'] as String).toUpperCase()) ||
          value['title'] is! String ||
          value['author'] is! String ||
          value['isbn'] is! String ||
          value['expected'] is! int ||
          (value['expected'] as int) < 0 ||
          (value['expected'] as int) > 1000000 ||
          value['copies'] is! List)
        throw const FormatException('Sayım beklentisi geçersiz');
      final copies = <Map<String, dynamic>>[];
      for (final copy in value['copies'] as List) {
        if (copy is! Map ||
            copy['id'] is! String ||
            (copy['id'] as String).isEmpty ||
            !copyIds.add((copy['id'] as String).toUpperCase()) ||
            copy['code'] is! String)
          throw const FormatException('Sayım nüshası geçersiz');
        copies.add({'id': copy['id'], 'code': copy['code']});
      }
      final isbn = canonicalIsbn(value['isbn'] as String);
      if (isbn != null) isbns.add(isbn);
      entries.add({
        'id': value['id'],
        'title': value['title'],
        'author': value['author'],
        'isbn': value['isbn'],
        'expected': value['expected'],
        'copies': copies,
      });
    }
    final events = <Map<String, dynamic>>[], seenCopies = <String>{};
    for (final value in raw['events'] as List) {
      if (value is! Map ||
          value['kind'] is! String ||
          value['key'] is! String ||
          (value['key'] as String).isEmpty ||
          (value['key'] as String).length > 512)
        throw const FormatException('Sayım okutması geçersiz');
      final kind = value['kind'] as String, key = value['key'] as String;
      if (kind == 'copy') {
        if (!copyIds.contains(key.toUpperCase()) ||
            !seenCopies.add(key.toUpperCase()))
          throw const FormatException('Sayım nüshası yinelendi');
      } else if (kind == 'manual') {
        if (!bookIds.contains(key.toUpperCase()))
          throw const FormatException('Sayım kitabı bulunamadı');
      } else if (kind == 'isbn') {
        if (!isbns.contains(key))
          throw const FormatException('Sayım ISBN kaydı bulunamadı');
      } else if (kind != 'unknown') {
        throw const FormatException('Sayım okutma türü geçersiz');
      }
      events.add({'kind': kind, 'key': key});
    }
    return InventorySession(
      name: raw['name'] as String,
      operatorName: raw['operatorName'] as String,
      startedAt: raw['startedAt'] as String,
      entries: entries,
      events: events,
      location: raw['location'] as String?,
      outsideCodes: outside.cast<String>(),
    );
  }
}

String inventoryBookPlace(Map<String, dynamic> book) {
  final stored = (book['shelf'] as String? ?? '').trim();
  final original = book['iphoneOriginal'];
  if (original is Map) {
    final location = (original['location'] as String? ?? '').trim();
    final initial = [
      (original['cabinet'] as String? ?? '').trim(),
      (original['shelf'] as String? ?? '').trim(),
    ].where((e) => e.isNotEmpty).join(' · ');
    final mapped = initial.isEmpty ? location : initial;
    // Honor an explicit iPhone location only while the mapped field is unchanged.
    if (stored == mapped && location.isNotEmpty) return location;
  }
  return stored;
}

String inventoryCopyPlace(Map<String, dynamic> book, Map copy) {
  final cabinet = (copy['cabinet'] as String? ?? '').trim();
  final shelf = (copy['shelf'] as String? ?? '').trim();
  if (cabinet.isEmpty && shelf.isEmpty) return inventoryBookPlace(book);
  final original = book['iphoneOriginal'];
  final baseCabinet = original is Map
      ? (original['cabinet'] as String? ?? '').trim()
      : '';
  final baseShelf = original is Map
      ? (original['shelf'] as String? ?? '').trim()
      : inventoryBookPlace(book);
  return [
    cabinet.isEmpty ? baseCabinet : cabinet,
    shelf.isEmpty ? baseShelf : shelf,
  ].where((e) => e.isNotEmpty).join(' · ');
}

List<String> inventoryLocations(List<Map<String, dynamic>> books) {
  final places = <String>{};
  for (final book in books.where(
    (b) => b['deletedAt'] == null && b['isWithdrawn'] != true,
  )) {
    final place = inventoryBookPlace(book);
    if (place.isNotEmpty) places.add(place);
    for (final copy in ((book['copies'] as List?) ?? []).whereType<Map>()) {
      final copyPlace = inventoryCopyPlace(book, copy);
      if (copyPlace.isNotEmpty) places.add(copyPlace);
    }
  }
  return places.toList()..sort();
}

InventorySession startInventory(
  List<Map<String, dynamic>> books, {
  required String name,
  required String operatorName,
  String? location,
  DateTime? now,
}) {
  if (name.trim().isEmpty || operatorName.trim().isEmpty)
    throw const FormatException('Sayım adı ve görevli gerekli');
  if (location != null && !inventoryLocations(books).contains(location))
    throw const FormatException('Sayım konumu bulunamadı');
  final entries = <Map<String, dynamic>>[];
  final outside = <String>[];
  for (final book in books.where(
    (b) => b['deletedAt'] == null && b['isWithdrawn'] != true,
  )) {
    final all = ((book['copies'] as List?) ?? []).whereType<Map>().toList();
    final bookPlace = inventoryBookPlace(book);
    final selected = location == null
        ? all
        : all.where((c) => inventoryCopyPlace(book, c) == location).toList();
    if (location != null) {
      for (final c in all.where(
        (c) => inventoryCopyPlace(book, c) != location,
      )) {
        final code = c['accessionCode'];
        if (code is String && code.isNotEmpty) outside.add(code);
      }
      if (bookPlace != location && selected.isEmpty) continue;
    }
    var expected = physicalAvailableCopies(book);
    if (location != null) {
      final loans = activeLoans(book);
      final loaned = {
        for (final loan in loans)
          if (loan['copyId'] is String)
            (loan['copyId'] as String).toUpperCase(),
      };
      final trackedLost = all.where((c) => c['status'] == 'Kayıp').length;
      final anonymousLost = ((book['lostCount'] as int?) ?? 0) - trackedLost;
      final anonymousLoans = loans.where((l) => l['copyId'] == null).length;
      final untracked = bookPlace == location
          ? (book['quantity'] as int) -
                all.length -
                anonymousLoans -
                anonymousLost
          : 0;
      expected =
          selected
              .where(
                (c) =>
                    c['status'] == 'Rafta' &&
                    !loaned.contains((c['id'] as String).toUpperCase()),
              )
              .length +
          untracked;
      if (expected < 0)
        throw const FormatException('Konum stok kaydı tutarsız');
    }
    entries.add({
      'id': book['id'],
      'title': book['title'],
      'author': book['author'],
      'isbn': book['isbn'] ?? '',
      'expected': expected,
      'copies': selected
          .map((c) => {'id': c['id'], 'code': c['accessionCode']})
          .toList(),
    });
  }
  return InventorySession.fromJson({
    'name': name.trim(),
    'operatorName': operatorName.trim(),
    'startedAt': (now ?? DateTime.now()).toIso8601String(),
    if (location != null) 'location': location,
    if (outside.isNotEmpty) 'outsideCodes': outside,
    'entries': entries,
    'events': [],
  });
}

InventorySession recordInventoryScan(InventorySession session, String input) {
  final code = input.trim();
  if (code.isEmpty ||
      code.length > 512 ||
      code.contains(RegExp(r'[\x00-\x1f\x7f]')))
    throw const FormatException('Barkod geçersiz');
  final copies = <Map<String, dynamic>>[];
  for (final entry in session.entries) {
    for (final copy in (entry['copies'] as List).cast<Map<String, dynamic>>()) {
      if ((copy['code'] as String).isNotEmpty &&
          (copy['code'] as String).toUpperCase() == code.toUpperCase())
        copies.add(copy);
    }
  }
  Map<String, dynamic> event;
  final outsideMatches = session.outsideCodes
      .where((c) => c.toUpperCase() == code.toUpperCase())
      .length;
  if (outsideMatches > 0 && copies.isNotEmpty || outsideMatches > 1)
    throw StateError(
      'Demirbaş kodu birden fazla nüshada var; sayıma eklenmedi',
    );
  if (outsideMatches == 1)
    throw StateError('Bu nüsha seçilen konumun dışında; sayıma eklenmedi');
  if (copies.length > 1)
    throw StateError(
      'Demirbaş kodu birden fazla nüshada var; sayıma eklenmedi',
    );
  if (copies.length == 1) {
    final id = copies.single['id'] as String;
    if (session.events.any(
      (e) =>
          e['kind'] == 'copy' &&
          (e['key'] as String).toUpperCase() == id.toUpperCase(),
    ))
      throw StateError('Bu nüsha zaten sayıldı');
    event = {'kind': 'copy', 'key': id};
  } else {
    final isbn = canonicalIsbn(code);
    final known =
        isbn != null &&
        session.entries.any((e) => canonicalIsbn(e['isbn'] as String) == isbn);
    event = known
        ? {'kind': 'isbn', 'key': isbn}
        : {'kind': 'unknown', 'key': code};
  }
  return InventorySession.fromJson({
    ...session.toJson(),
    'events': [...session.events, event],
  });
}

InventorySession recordManualInventory(
  InventorySession session,
  String bookId,
) => InventorySession.fromJson({
  ...session.toJson(),
  'events': [
    ...session.events,
    {'kind': 'manual', 'key': bookId},
  ],
});
InventorySession undoInventory(InventorySession session) =>
    session.events.isEmpty
    ? session
    : InventorySession.fromJson({
        ...session.toJson(),
        'events': session.events.sublist(0, session.events.length - 1),
      });

class InventoryRow {
  const InventoryRow({
    required this.entry,
    required this.count,
    required this.identified,
    required this.manual,
    required this.isbn,
  });
  final Map<String, dynamic> entry;
  final int count, identified, manual, isbn;
}

List<InventoryRow> inventoryRows(InventorySession session) {
  final entries = [...session.entries]
    ..sort(
      (a, b) => (a['id'] as String).toUpperCase().compareTo(
        (b['id'] as String).toUpperCase(),
      ),
    );
  final pooled = <String, int>{}, manualCounts = <String, int>{};
  final countedCopies = <String>{}, lastBookForIsbn = <String, String>{};
  for (final entry in entries) {
    final isbn = canonicalIsbn(entry['isbn'] as String);
    if (isbn != null)
      lastBookForIsbn[isbn] = (entry['id'] as String).toUpperCase();
  }
  for (final event in session.events) {
    final key = event['key'] as String;
    if (event['kind'] == 'isbn') pooled[key] = (pooled[key] ?? 0) + 1;
    if (event['kind'] == 'manual')
      manualCounts[key.toUpperCase()] =
          (manualCounts[key.toUpperCase()] ?? 0) + 1;
    if (event['kind'] == 'copy') countedCopies.add(key.toUpperCase());
  }
  final result = <InventoryRow>[];
  for (final entry in entries) {
    final id = (entry['id'] as String).toUpperCase();
    final identified = (entry['copies'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (copy) =>
              countedCopies.contains((copy['id'] as String).toUpperCase()),
        )
        .length;
    final manual = manualCounts[id] ?? 0;
    final isbn = canonicalIsbn(entry['isbn'] as String);
    final remaining = isbn == null ? 0 : pooled[isbn] ?? 0;
    final last = isbn == null || lastBookForIsbn[isbn] == id;
    final capacity = (entry['expected'] as int) - identified - manual;
    final share = last
        ? remaining
        : (capacity > 0 ? (remaining < capacity ? remaining : capacity) : 0);
    if (isbn != null) pooled[isbn] = remaining - share;
    result.add(
      InventoryRow(
        entry: entry,
        count: identified + manual + share,
        identified: identified,
        manual: manual,
        isbn: share,
      ),
    );
  }
  return result;
}

class InventoryArchive {
  const InventoryArchive({required this.finishedAt, required this.session});
  final String finishedAt;
  final InventorySession session;
  Map<String, dynamic> toJson() => {
    'finishedAt': finishedAt,
    'session': session.toJson(),
  };
  factory InventoryArchive.fromJson(dynamic raw) {
    if (raw is! Map ||
        raw['finishedAt'] is! String ||
        DateTime.tryParse(raw['finishedAt'] as String) == null) {
      throw const FormatException('Sayım geçmişi geçersiz');
    }
    return InventoryArchive(
      finishedAt: raw['finishedAt'] as String,
      session: InventorySession.fromJson(raw['session']),
    );
  }
}

List<InventoryArchive> parseInventoryHistory(dynamic raw) {
  if (raw is! List || raw.length > 1000)
    throw const FormatException('Sayım geçmişi geçersiz');
  return raw.map(InventoryArchive.fromJson).toList();
}

class InventorySummary {
  const InventorySummary({
    required this.totalTitles,
    required this.expectedTotal,
    required this.countedTotal,
    required this.exactTitles,
    required this.missingTitles,
    required this.surplusTitles,
    required this.uncountedTitles,
    required this.missingCopies,
    required this.surplusCopies,
    required this.unknownScans,
  });

  final int totalTitles;
  final int expectedTotal;
  final int countedTotal;
  final int exactTitles;
  final int missingTitles;
  final int surplusTitles;
  final int uncountedTitles;
  final int missingCopies;
  final int surplusCopies;
  final int unknownScans;
}

InventorySummary summarizeInventory(InventorySession session) {
  final rows = inventoryRows(session);
  var expectedTotal = 0;
  var countedTotal = 0;
  var exactTitles = 0;
  var missingTitles = 0;
  var surplusTitles = 0;
  var uncountedTitles = 0;
  var missingCopies = 0;
  var surplusCopies = 0;
  for (final row in rows) {
    final exp = row.entry['expected'] as int;
    expectedTotal += exp;
    countedTotal += row.count;
    if (row.count == exp) {
      if (exp > 0) exactTitles++;
    } else if (row.count < exp) {
      missingTitles++;
      missingCopies += exp - row.count;
      if (row.count == 0) uncountedTitles++;
    } else {
      surplusTitles++;
      surplusCopies += row.count - exp;
    }
  }
  final unknownScans = session.events.where((e) => e['kind'] == 'unknown').length;
  return InventorySummary(
    totalTitles: rows.length,
    expectedTotal: expectedTotal,
    countedTotal: countedTotal,
    exactTitles: exactTitles,
    missingTitles: missingTitles,
    surplusTitles: surplusTitles,
    uncountedTitles: uncountedTitles,
    missingCopies: missingCopies,
    surplusCopies: surplusCopies,
    unknownScans: unknownScans,
  );
}

/// Decrements a single count event belonging to [bookId] (preferring manual, then ISBN, then copy).
InventorySession decrementInventoryBook(
  InventorySession session,
  String bookId,
) {
  final upperId = bookId.toUpperCase();
  final entry = session.entries
      .where((e) => (e['id'] as String).toUpperCase() == upperId)
      .firstOrNull;
  if (entry == null) return session;
  final events = [...session.events];

  for (var i = events.length - 1; i >= 0; i--) {
    if (events[i]['kind'] == 'manual' &&
        (events[i]['key'] as String).toUpperCase() == upperId) {
      events.removeAt(i);
      return InventorySession.fromJson({...session.toJson(), 'events': events});
    }
  }
  final isbn = canonicalIsbn(entry['isbn'] as String);
  if (isbn != null) {
    for (var i = events.length - 1; i >= 0; i--) {
      if (events[i]['kind'] == 'isbn' && events[i]['key'] == isbn) {
        events.removeAt(i);
        return InventorySession.fromJson({...session.toJson(), 'events': events});
      }
    }
  }
  final copyIds = {
    for (final c in (entry['copies'] as List).cast<Map<String, dynamic>>())
      (c['id'] as String).toUpperCase(),
  };
  for (var i = events.length - 1; i >= 0; i--) {
    if (events[i]['kind'] == 'copy' &&
        copyIds.contains((events[i]['key'] as String).toUpperCase())) {
      events.removeAt(i);
      return InventorySession.fromJson({...session.toJson(), 'events': events});
    }
  }
  return session;
}

/// Removes unknown scan events matching [code].
InventorySession removeUnknownBarcodeEvents(
  InventorySession session,
  String code,
) {
  final clean = code.trim().toUpperCase();
  final nextEvents = session.events
      .where(
        (e) =>
            !(e['kind'] == 'unknown' &&
                (e['key'] as String).trim().toUpperCase() == clean),
      )
      .toList();
  return InventorySession.fromJson({...session.toJson(), 'events': nextEvents});
}

/// Integrates a newly registered (or updated) catalog book into an active
/// inventory session, converting any matching unknown barcode scans into counted events.
InventorySession integrateRegisteredBookIntoInventory(
  InventorySession session,
  Map<String, dynamic> rawBook,
) {
  final book = normalizeBook(rawBook);
  if (book['deletedAt'] != null || book['isWithdrawn'] == true) return session;
  final bookId = book['id'] as String;

  final allCopies = ((book['copies'] as List?) ?? []).whereType<Map>().toList();
  final location = session.location;
  final bookPlace = inventoryBookPlace(book);
  final selectedCopies = location == null
      ? allCopies
      : allCopies.where((c) => inventoryCopyPlace(book, c) == location).toList();
  if (location != null && bookPlace != location && selectedCopies.isEmpty) {
    return session;
  }

  var expected = physicalAvailableCopies(book);
  if (location != null) {
    final loans = activeLoans(book);
    final loaned = {
      for (final loan in loans)
        if (loan['copyId'] is String) (loan['copyId'] as String).toUpperCase(),
    };
    final trackedLost = allCopies.where((c) => c['status'] == 'Kayıp').length;
    final anonymousLost = ((book['lostCount'] as int?) ?? 0) - trackedLost;
    final anonymousLoans = loans.where((l) => l['copyId'] == null).length;
    final untracked = bookPlace == location
        ? (book['quantity'] as int) -
              allCopies.length -
              anonymousLoans -
              anonymousLost
        : 0;
    expected =
        selectedCopies
            .where(
              (c) =>
                  c['status'] == 'Rafta' &&
                  !loaned.contains((c['id'] as String).toUpperCase()),
            )
            .length +
        untracked;
  }

  final newEntry = <String, dynamic>{
    'id': bookId,
    'title': book['title'],
    'author': book['author'] ?? '',
    'isbn': book['isbn'] ?? '',
    'expected': expected < 0 ? 0 : expected,
    'copies': selectedCopies
        .map((c) => {'id': c['id'], 'code': c['accessionCode']})
        .toList(),
  };

  final existingIndex = session.entries.indexWhere(
    (e) => (e['id'] as String).toUpperCase() == bookId.toUpperCase(),
  );
  final nextEntries = [...session.entries];
  if (existingIndex >= 0) {
    nextEntries[existingIndex] = newEntry;
  } else {
    nextEntries.add(newEntry);
  }

  final isbn = canonicalIsbn((book['isbn'] ?? '').toString());
  final topAccession = (book['accessionCode'] ?? '').toString().trim().toUpperCase();
  final copyByCode = <String, String>{
    for (final c in selectedCopies)
      if ((c['accessionCode'] as String? ?? '').trim().isNotEmpty)
        (c['accessionCode'] as String).trim().toUpperCase(): c['id'] as String,
  };
  final seenCopyIds = <String>{
    for (final e in session.events)
      if (e['kind'] == 'copy') (e['key'] as String).toUpperCase(),
  };

  final convertedEvents = <Map<String, dynamic>>[];
  for (final event in session.events) {
    if (event['kind'] != 'unknown') {
      convertedEvents.add(event);
      continue;
    }
    final rawKey = (event['key'] as String).trim();
    final copyId = copyByCode[rawKey.toUpperCase()];
    if (copyId != null) {
      if (seenCopyIds.add(copyId.toUpperCase())) {
        convertedEvents.add({'kind': 'copy', 'key': copyId});
      }
      continue;
    }
    final eventIsbn = canonicalIsbn(rawKey);
    if (isbn != null && eventIsbn == isbn) {
      convertedEvents.add({'kind': 'isbn', 'key': isbn});
      continue;
    }
    if (topAccession.isNotEmpty && rawKey.toUpperCase() == topAccession) {
      convertedEvents.add({'kind': 'manual', 'key': bookId});
      continue;
    }
    convertedEvents.add(event);
  }

  return InventorySession.fromJson({
    ...session.toJson(),
    'entries': nextEntries,
    'events': convertedEvents,
  });
}
