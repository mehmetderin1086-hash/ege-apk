import 'copy_model.dart';
import 'reservation_model.dart';

/// Normalizes the earlier single-borrower prototype without discarding loans.
Map<String, dynamic> normalizeBook(Map<String, dynamic> source) {
  final book = Map<String, dynamic>.from(source);
  final original = book['iphoneOriginal'];
  if (original is Map) {
    for (final key in [
      'language',
      'tags',
      'readingLevel',
      'readingStatus',
      'contentWarning',
      'accessionCode',
    ]) {
      if (!book.containsKey(key) && original[key] is String)
        book[key] = original[key];
    }
    for (final key in ['volume', 'rating']) {
      if (!book.containsKey(key) && original[key] is int)
        book[key] = original[key];
    }
  }
  final legacy = (book['borrower'] as String?)?.trim() ?? '';
  final stored = book['loans'];
  final loans = stored is List
      ? stored.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : <Map<String, dynamic>>[
          if (legacy.isNotEmpty)
            {
              'id': 'legacy',
              'name': legacy,
              'due': null,
              'identitySource': 'legacy',
              'needsIdentityReview': true,
            },
        ];
  final quantity = book['quantity'] is int ? book['quantity'] as int : 1;
  final rawLost = book['lostCount'];
  final lost = rawLost is int && rawLost > 0 ? rawLost : 0;
  final minimum = loans.length + lost;
  book['quantity'] = quantity < minimum
      ? minimum
      : (quantity < 1 ? 1 : quantity);
  book['lostCount'] = lost;
  book['loans'] = loans;
  book.remove('borrower');
  if (book['reservations'] != null) validateReservations(book['reservations']);
  if (book['copies'] != null) {
    final copies = validateCopies(
      book['copies'],
      bookId: book['id'] as String,
      quantity: book['quantity'] as int,
    );
    final trackedLost = copies
        .where((copy) => copy['status'] == 'Kayıp')
        .length;
    validateCopyLoans(
      copies,
      loans,
      book['quantity'] as int,
      otherLost: lost - trackedLost,
    );
  } else if (loans.any((loan) => loan['copyId'] != null)) {
    throw const FormatException('Ödüncün nüsha kaydı eksik');
  }
  validateReservationHolds(book);
  return book;
}

List<Map<String, dynamic>> activeLoans(Map<String, dynamic> book) =>
    (book['loans'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

int physicalAvailableCopies(Map<String, dynamic> book) {
  final physical = book['copies'];
  if (physical is List && physical.isNotEmpty) {
    final copies = validateCopies(
      physical,
      bookId: book['id'] as String,
      quantity: book['quantity'] as int,
    );
    final trackedLost = copies
        .where((copy) => copy['status'] == 'Kayıp')
        .length;
    return availablePhysicalAndUntracked(
      copies,
      activeLoans(book),
      book['quantity'] as int,
      otherLost: ((book['lostCount'] as int?) ?? 0) - trackedLost,
    );
  }
  return (book['quantity'] as int) -
      activeLoans(book).length -
      ((book['lostCount'] as int?) ?? 0);
}

int availableCopies(Map<String, dynamic> book) {
  if (book['isWithdrawn'] == true) return 0;
  final free = physicalAvailableCopies(book);
  final held = reservationsOf(book).where((r) => isReadyReservation(r)).length;
  return free > held ? free - held : 0;
}

void validateReservationHolds(Map<String, dynamic> book) {
  final ready = reservationsOf(
    book,
  ).where((r) => isReadyReservation(r)).toList();
  if (ready.length > physicalAvailableCopies(book))
    throw const FormatException('Ayrılmış nüsha sayısı uygun stoğu aşıyor');
  final copies = ((book['copies'] as List?) ?? []).whereType<Map>().toList();
  for (final r in reservationsOf(book).where(isActiveReservation)) {
    if (r['copyId'] != null &&
        !copies.any(
          (c) =>
              (c['id'] as String).toUpperCase() ==
              (r['copyId'] as String).toUpperCase(),
        )) {
      throw const FormatException('Açık rezervasyonun nüşası bulunamadı');
    }
  }
  final borrowed = {
    for (final loan in activeLoans(book))
      if (loan['copyId'] is String) (loan['copyId'] as String).toUpperCase(),
  };
  final ids = <String>{};
  for (final r in ready) {
    if (r['copyId'] == null) continue;
    final id = (r['copyId'] as String).toUpperCase();
    if (!ids.add(id) ||
        borrowed.contains(id) ||
        !copies.any(
          (copy) =>
              (copy['id'] as String).toUpperCase() == id &&
              copy['status'] == 'Rafta',
        )) {
      throw const FormatException('Rezervasyon nüsha bağlantısı geçersiz');
    }
  }
}

Map<String, dynamic> advanceReservationQueue(
  Map<String, dynamic> book, {
  DateTime? now,
}) {
  if (book['isWithdrawn'] == true) return book;
  final time = now ?? DateTime.now();
  var result = book;
  for (final r in reservationsOf(result)) {
    final expires = r['expiresAt'] == null
        ? null
        : DateTime.parse(r['expiresAt'] as String);
    if (isActiveReservation(r) &&
        r['notifiedAt'] != null &&
        expires != null &&
        !expires.isAfter(time)) {
      result = closeReservation(
        result,
        r['id'] as String,
        'expired',
        now: time,
      );
    }
  }
  var free =
      physicalAvailableCopies(result) -
      reservationsOf(
        result,
      ).where((r) => isReadyReservation(r, now: time)).length;
  while (free > 0 &&
      reservationsOf(
        result,
      ).any((r) => isActiveReservation(r) && r['notifiedAt'] == null)) {
    final waiting =
        reservationsOf(result)
            .where((r) => isActiveReservation(r) && r['notifiedAt'] == null)
            .toList()
          ..sort(
            (a, b) => DateTime.parse(
              a['createdAt'] as String,
            ).compareTo(DateTime.parse(b['createdAt'] as String)),
          );
    final desired = waiting.first['copyId'];
    if (desired is String) {
      final id = desired.toUpperCase();
      final copy = ((result['copies'] as List?) ?? []).whereType<Map>().where(
        (c) =>
            (c['id'] as String).toUpperCase() == id && c['status'] == 'Rafta',
      );
      final unavailable =
          activeLoans(result).any(
            (l) =>
                l['copyId'] is String &&
                (l['copyId'] as String).toUpperCase() == id,
          ) ||
          reservationsOf(result).any(
            (r) =>
                isReadyReservation(r, now: time) &&
                r['copyId'] is String &&
                (r['copyId'] as String).toUpperCase() == id,
          );
      if (copy.isEmpty || unavailable) break;
    }
    result = readyNextReservation(result, now: time);
    free--;
  }
  return result;
}

Map<String, dynamic> lendReservation(
  Map<String, dynamic> book,
  String reservationId, {
  required String loanId,
  required DateTime due,
  bool allowDuplicate = false,
}) {
  final matches = reservationsOf(
    book,
  ).where((r) => r['id'] == reservationId && isReadyReservation(r)).toList();
  if (matches.length != 1)
    throw StateError('Teslime hazır rezervasyon bulunamadı');
  final reservation = matches.single;
  final closed = closeReservation(book, reservationId, 'delivered');
  return addLoan(
    closed,
    {
      'id': loanId,
      'name': reservation['name'],
      'studentClass': reservation['studentClass'],
      if (reservation['studentId'] != null)
        'studentId': reservation['studentId'],
      if (reservation['memberId'] != null) 'memberId': reservation['memberId'],
      'identitySource': reservation['memberId'] != null
          ? 'member'
          : (reservation['studentId'] == null ? 'manual' : 'student'),
      'due': due.toIso8601String(),
    },
    copyId: reservation['copyId'] as String?,
    honorQueue: false,
    allowDuplicate: allowDuplicate,
  );
}

int minimumCopyQuantity(Map<String, dynamic> book) {
  final copies = (book['copies'] as List?) ?? [];
  if (copies.isEmpty)
    return activeLoans(book).length + ((book['lostCount'] as int?) ?? 0);
  final trackedLost = copies
      .where((copy) => (copy as Map)['status'] == 'Kayıp')
      .length;
  return copies.length +
      activeLoans(book).where((loan) => loan['copyId'] == null).length +
      ((book['lostCount'] as int?) ?? 0) -
      trackedLost;
}

/// Adds an identified copy using a free unidentified slot, or increases stock.
Map<String, dynamic> addPhysicalCopy(
  Map<String, dynamic> book,
  Map<String, dynamic> copy,
) {
  final existing = ((book['copies'] as List?) ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  final quantity = book['quantity'] as int;
  final nextQuantity = minimumCopyQuantity(book) >= quantity
      ? quantity + 1
      : quantity;
  final next = [...existing, Map<String, dynamic>.from(copy)];
  validateCopies(next, bookId: book['id'] as String, quantity: nextQuantity);
  final lost =
      ((book['lostCount'] as int?) ?? 0) + (copy['status'] == 'Kayıp' ? 1 : 0);
  final result = {
    ...book,
    'quantity': nextQuantity,
    'copies': next,
    'lostCount': lost,
  };
  availableCopies(result);
  return advanceReservationQueue(result);
}

Map<String, dynamic> editPhysicalCopy(
  Map<String, dynamic> book,
  Map<String, dynamic> updated,
) {
  final copies = ((book['copies'] as List?) ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  final id = updated['id'];
  if (id is! String) throw StateError('Nüsha kimliği geçersiz');
  final matches = copies
      .where((copy) => (copy['id'] as String).toUpperCase() == id.toUpperCase())
      .toList();
  if (matches.length != 1) throw StateError('Nüsha bulunamadı');
  final old = matches.single;
  final loaned = activeLoans(book).any(
    (loan) =>
        loan['copyId'] is String &&
        (loan['copyId'] as String).toUpperCase() == id.toUpperCase(),
  );
  if (loaned && updated['status'] != 'Rafta')
    throw StateError('Ödünçteki nüshanın durumu değiştirilemez');
  final next = copies
      .map(
        (copy) => (copy['id'] as String).toUpperCase() == id.toUpperCase()
            ? {
                ...copy,
                ...updated,
                'id': old['id'],
                'bookID': old['bookID'],
                'addedAt': old['addedAt'],
              }
            : copy,
      )
      .toList();
  validateCopies(
    next,
    bookId: book['id'] as String,
    quantity: book['quantity'] as int,
  );
  final lost =
      ((book['lostCount'] as int?) ?? 0) +
      (updated['status'] == 'Kayıp' ? 1 : 0) -
      (old['status'] == 'Kayıp' ? 1 : 0);
  final result = {...book, 'copies': next, 'lostCount': lost};
  availableCopies(result);
  return advanceReservationQueue(result);
}

Map<String, dynamic> reportLost(Map<String, dynamic> book, String loanId) {
  final loans = activeLoans(book);
  final matches = loans.where((loan) => loan['id'] == loanId).toList();
  if (matches.length != 1) throw StateError('Ödünç kaydı bulunamadı');
  final loan = matches.single;
  final copyId = loan['copyId'];
  final copies = (book['copies'] as List?)?.map((value) {
    final copy = Map<String, dynamic>.from(value as Map);
    if (copyId is String &&
        (copy['id'] as String).toUpperCase() == copyId.toUpperCase())
      copy['status'] = 'Kayıp';
    return copy;
  }).toList();
  return {
    ...book,
    if (copies != null) 'copies': copies,
    'lostCount': ((book['lostCount'] as int?) ?? 0) + 1,
    'loans': loans.where((loan) => loan['id'] != loanId).toList(),
    'history': [
      ...loanHistory(book),
      {
        'kind': 'lost',
        if (loan['kind'] == 'textbook') 'loanKind': 'textbook',
        if (loan['periodSnapshot'] != null)
          'periodSnapshot': loan['periodSnapshot'],
        if (loan['studentNumberSnapshot'] != null)
          'studentNumberSnapshot': loan['studentNumberSnapshot'],
        if (loan['copyId'] != null) 'copyId': loan['copyId'],
        'person': loan['name'],
        if (loan['studentId'] != null) 'studentId': loan['studentId'],
        if (loan['memberId'] != null) 'memberId': loan['memberId'],
        'studentClass': loan['studentClass'],
        'date': DateTime.now().toIso8601String(),
        'due': loan['due'],
        'loanId': loanId,
      },
    ],
  };
}

/// Duplicate matching never merges two different registered student IDs.
bool hasDuplicateBorrower(
  Map<String, dynamic> book,
  Map<String, dynamic> person,
) {
  final studentId = person['studentId'] as String?;
  final memberId = person['memberId'] as String?;
  String nameKey(String value) => value
      .trim()
      .replaceAll('İ', 'i')
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u')
      .replaceAll(RegExp(r'\s+'), ' ');
  final name = nameKey((person['name'] ?? '').toString());
  final className = (person['studentClass'] ?? '').toString().trim();
  if (studentId == null && memberId == null && name.isEmpty) return false;
  return activeLoans(book).any((loan) {
    if ((loan['kind'] == 'textbook') != (person['kind'] == 'textbook'))
      return false;
    final otherId = loan['studentId'] as String?;
    final otherMember = loan['memberId'] as String?;
    if (memberId != null)
      return otherMember != null &&
          memberId.toUpperCase() == otherMember.toUpperCase();
    if (otherMember != null) return false;
    if (studentId != null)
      return otherId != null &&
          studentId.toUpperCase() == otherId.toUpperCase();
    return otherId == null &&
        nameKey((loan['name'] ?? '').toString()) == name &&
        (loan['studentClass'] ?? '').toString().trim() == className;
  });
}

Map<String, dynamic> addLoan(
  Map<String, dynamic> book,
  Map<String, dynamic> loan, {
  String? copyId,
  bool untracked = false,
  bool honorQueue = true,
  bool allowDuplicate = false,
}) {
  if (honorQueue) book = advanceReservationQueue(book);
  final loans = activeLoans(book);
  if (!allowDuplicate && hasDuplicateBorrower(book, loan)) {
    throw StateError('Bu kişi kitabı zaten ödünç aldı');
  }
  if (availableCopies(book) <= 0) {
    throw StateError('Nüsha kalmadı');
  }
  if ((loan['name'] as String).trim().isEmpty) {
    throw ArgumentError('İsim gerekli');
  }
  final copies = (book['copies'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final used = {
    for (final active in loans)
      if (active['copyId'] is String)
        (active['copyId'] as String).toUpperCase(),
  };
  final heldCopyIds = {
    for (final reservation in reservationsOf(book))
      if (isReadyReservation(reservation) && reservation['copyId'] is String)
        (reservation['copyId'] as String).toUpperCase(),
  };
  final available = copies.where(
    (copy) =>
        copy['status'] == 'Rafta' &&
        !used.contains((copy['id'] as String).toUpperCase()) &&
        !heldCopyIds.contains((copy['id'] as String).toUpperCase()),
  );
  if (copyId != null && untracked) throw ArgumentError('Tek bir nüsha seçin');
  final matching = copyId == null
      ? <Map<String, dynamic>>[]
      : available
            .where(
              (copy) =>
                  (copy['id'] as String).toUpperCase() == copyId.toUpperCase(),
            )
            .toList();
  if (copyId != null && matching.length != 1)
    throw StateError('Seçilen nüsha kullanılamıyor');
  final trackedLost = copies.where((copy) => copy['status'] == 'Kayıp').length;
  final anonymous = loans.where((loan) => loan['copyId'] == null).length;
  final untrackedAvailable =
      (book['quantity'] as int) -
      copies.length -
      anonymous -
      (((book['lostCount'] as int?) ?? 0) - trackedLost) -
      reservationsOf(
        book,
      ).where((r) => isReadyReservation(r) && r['copyId'] == null).length;
  if (untracked && untrackedAvailable <= 0)
    throw StateError('Nüshasız stok kalmadı');
  if (!untracked &&
      copyId == null &&
      available.isEmpty &&
      untrackedAvailable <= 0)
    throw StateError('Kullanılabilir nüsha kalmadı');
  final chosen = untracked
      ? null
      : copyId != null
      ? matching.single['id']
      : available.isNotEmpty
      ? available.first['id']
      : null;
  final assigned = {...loan, if (chosen != null) 'copyId': chosen};
  assigned.remove('copyId');
  if (chosen != null) assigned['copyId'] = chosen;
  return {
    ...book,
    'loans': [...loans, assigned],
    'history': [
      ...loanHistory(book),
      {
        'kind': 'lent',
        if (loan['kind'] == 'textbook') 'loanKind': 'textbook',
        if (loan['periodSnapshot'] != null)
          'periodSnapshot': loan['periodSnapshot'],
        if (loan['studentNumberSnapshot'] != null)
          'studentNumberSnapshot': loan['studentNumberSnapshot'],
        if (chosen != null) 'copyId': chosen,
        'person': loan['name'],
        if (loan['studentId'] != null) 'studentId': loan['studentId'],
        if (loan['memberId'] != null) 'memberId': loan['memberId'],
        'studentClass': loan['studentClass'],
        'due': loan['due'],
        'date': DateTime.now().toIso8601String(),
        'loanId': loan['id'],
      },
    ],
  };
}

List<Map<String, dynamic>> loanHistory(Map<String, dynamic> book) =>
    ((book['history'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

bool isOverdue(Map<String, dynamic> loan, {DateTime? now}) {
  final due = DateTime.tryParse(loan['due']?.toString() ?? '');
  if (due == null) return false;
  final today = now ?? DateTime.now();
  return DateTime(
    due.year,
    due.month,
    due.day,
  ).isBefore(DateTime(today.year, today.month, today.day));
}

Map<String, dynamic> returnLoan(
  Map<String, dynamic> book,
  String loanId, {
  String? returnedCondition,
  bool? readingCompleted,
}) {
  final loans = activeLoans(book);
  final found = loans.where((loan) => loan['id'] == loanId).toList();
  if (found.isEmpty) throw StateError('Ödünç kaydı bulunamadı');
  final loan = found.single;
  final now = DateTime.now();
  final late = isOverdue(loan, now: now);
  if (returnedCondition != null &&
      ![
        'Yeni',
        'İyi',
        'Yıpranmış',
        'Onarım gerekli',
      ].contains(returnedCondition))
    throw ArgumentError('Nüsha durumu geçersiz');
  var result = <String, dynamic>{
    ...book,
    'loans': loans.where((item) => item['id'] != loanId).toList(),
  };
  String? copyId = loan['copyId'] as String?;
  if (returnedCondition != null && copyId != null) {
    final copies = ((book['copies'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    final matches = copies
        .where(
          (c) => (c['id'] as String).toUpperCase() == copyId!.toUpperCase(),
        )
        .toList();
    if (matches.length != 1) throw StateError('Ödüncün nüsha kaydı bulunamadı');
    result = editPhysicalCopy(result, {
      ...matches.single,
      'condition': returnedCondition,
      'status': returnedCondition == 'Onarım gerekli' ? 'Onarımda' : 'Rafta',
    });
  } else if (returnedCondition == 'Yıpranmış' ||
      returnedCondition == 'Onarım gerekli') {
    copyId = 'return-${now.microsecondsSinceEpoch}-$loanId';
    final originalQuantity = result['quantity'];
    result = addPhysicalCopy(result, {
      'id': copyId,
      'bookID': book['id'],
      'accessionCode': '',
      'condition': returnedCondition,
      'status': returnedCondition == 'Onarım gerekli' ? 'Onarımda' : 'Rafta',
      'note': 'İadede durum kaydı',
      'addedAt': now.toIso8601String(),
    });
    if (result['quantity'] != originalQuantity)
      throw StateError('Hasarın bağlanacağı nüsha kapasitesi bulunamadı');
  }
  return advanceReservationQueue({
    ...result,
    'history': [
      ...loanHistory(book),
      {
        'kind': 'returned',
        if (loan['kind'] == 'textbook') 'loanKind': 'textbook',
        if (loan['periodSnapshot'] != null)
          'periodSnapshot': loan['periodSnapshot'],
        if (loan['studentNumberSnapshot'] != null)
          'studentNumberSnapshot': loan['studentNumberSnapshot'],
        if (copyId != null) 'copyId': copyId,
        if (returnedCondition != null) 'returnedCondition': returnedCondition,
        if (readingCompleted != null && loan['kind'] != 'textbook')
          'readingCompleted': readingCompleted,
        if (loan['identitySource'] != null)
          'identitySource': loan['identitySource'],
        'person': loan['name'],
        if (loan['studentId'] != null) 'studentId': loan['studentId'],
        if (loan['memberId'] != null) 'memberId': loan['memberId'],
        'studentClass': loan['studentClass'],
        'due': loan['due'],
        'date': now.toIso8601String(),
        'loanId': loanId,
        'late': late,
      },
    ],
  });
}

Map<String, dynamic> assignStudentIdentity(
  Map<String, dynamic> book,
  String loanId, {
  required String studentId,
  required String name,
  required String studentClass,
}) {
  final loans = activeLoans(book);
  final matches = loans.where((loan) => loan['id'] == loanId).toList();
  if (matches.length != 1 || studentId.isEmpty || name.trim().isEmpty)
    throw StateError('Kimlik veya ödünç kaydı geçersiz');
  final old = matches.single;
  if (old['memberId'] != null)
    throw StateError('Üye ödüncü öğrenciye dönüştürülemez');
  final corrected = {
    ...old,
    'studentId': studentId,
    'name': name,
    'studentClass': studentClass,
    'identitySource': 'student',
    'needsIdentityReview': false,
  };
  return {
    ...book,
    'loans': loans
        .map((loan) => loan['id'] == loanId ? corrected : loan)
        .toList(),
    'history': [
      ...loanHistory(book),
      {
        'kind': 'identityCorrected',
        if (old['kind'] == 'textbook') 'loanKind': 'textbook',
        if (old['periodSnapshot'] != null)
          'periodSnapshot': old['periodSnapshot'],
        if (old['studentNumberSnapshot'] != null)
          'studentNumberSnapshot': old['studentNumberSnapshot'],
        'person': name,
        'studentId': studentId,
        'studentClass': studentClass,
        'date': DateTime.now().toIso8601String(),
        'loanId': loanId,
        'previousName': old['name'],
        'previousClass': old['studentClass'],
        'previousStudentId': old['studentId'],
      },
    ],
  };
}

/// A loaned book remains visible until every copy is returned.
Map<String, dynamic> moveToTrash(Map<String, dynamic> book) {
  if (activeLoans(book).isNotEmpty) {
    throw StateError('Ödünçte nüsha bulunan kitap çöp kutusuna taşınamaz');
  }
  if (reservationsOf(book).any(isActiveReservation))
    throw StateError('Açık rezervasyon bulunan kitap çöp kutusuna taşınamaz');
  return {...book, 'deletedAt': DateTime.now().toIso8601String()};
}

Map<String, dynamic> restoreBook(Map<String, dynamic> book) => {
  ...book,
  'deletedAt': null,
};

Map<String, dynamic> extendLoan(
  Map<String, dynamic> book,
  String loanId,
  DateTime newDue,
) {
  final loans = activeLoans(book);
  final found = loans.where((loan) => loan['id'] == loanId).toList();
  if (found.length != 1) throw StateError('Ödünç kaydı bulunamadı');
  final old = found.single;
  final oldDue = DateTime.tryParse(old['due']?.toString() ?? '');
  final chosen = DateTime(newDue.year, newDue.month, newDue.day);
  if (oldDue != null &&
      !chosen.isAfter(DateTime(oldDue.year, oldDue.month, oldDue.day))) {
    throw ArgumentError('Yeni tarih önceki tarihten sonra olmalı');
  }
  final updated = {
    ...old,
    'due': chosen.toIso8601String(),
    'extensionCount': ((old['extensionCount'] as int?) ?? 0) + 1,
  };
  return {
    ...book,
    'loans': loans
        .map((loan) => loan['id'] == loanId ? updated : loan)
        .toList(),
    'history': [
      ...loanHistory(book),
      {
        'kind': 'extended',
        if (old['kind'] == 'textbook') 'loanKind': 'textbook',
        if (old['periodSnapshot'] != null)
          'periodSnapshot': old['periodSnapshot'],
        if (old['copyId'] != null) 'copyId': old['copyId'],
        'person': old['name'],
        if (old['studentId'] != null) 'studentId': old['studentId'],
        if (old['memberId'] != null) 'memberId': old['memberId'],
        'studentClass': old['studentClass'],
        'previousDue': old['due'],
        'due': updated['due'],
        'date': DateTime.now().toIso8601String(),
        'loanId': loanId,
      },
    ],
  };
}

String loanEventLabel(String? kind) => switch (kind) {
  'lent' => 'Ödünç verildi',
  'returned' => 'İade alındı',
  'extended' => 'Süre uzatıldı',
  'lost' => 'Kayıp bildirildi',
  'identityCorrected' => 'Kimlik düzeltildi',
  _ => 'Bilinmeyen hareket',
};
