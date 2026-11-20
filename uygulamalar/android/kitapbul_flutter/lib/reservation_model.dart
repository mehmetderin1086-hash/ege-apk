/// Reservations are stored alongside their book and retain historical closures.
List<Map<String, dynamic>> reservationsOf(Map<String, dynamic> book) =>
    ((book['reservations'] as List?) ?? [])
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();

List<Map<String, dynamic>> validateReservations(dynamic value) {
  if (value is! List)
    throw const FormatException('Rezervasyon listesi geçersiz');
  final ids = <String>{};
  final result = <Map<String, dynamic>>[];
  for (final raw in value) {
    if (raw is! Map ||
        raw['id'] is! String ||
        (raw['id'] as String).trim().isEmpty ||
        !ids.add((raw['id'] as String).toUpperCase()) ||
        raw['name'] is! String ||
        (raw['name'] as String).trim().isEmpty ||
        raw['studentClass'] is! String ||
        raw['createdAt'] is! String ||
        DateTime.tryParse(raw['createdAt'] as String) == null ||
        raw['isClosed'] is! bool ||
        (raw['studentId'] != null &&
            (raw['studentId'] is! String ||
                (raw['studentId'] as String).isEmpty)) ||
        (raw['memberId'] != null &&
            (raw['memberId'] is! String ||
                (raw['memberId'] as String).isEmpty ||
                raw['studentId'] != null)) ||
        (raw['copyId'] != null &&
            (raw['copyId'] is! String || (raw['copyId'] as String).isEmpty)) ||
        (raw['notifiedAt'] != null &&
            (raw['notifiedAt'] is! String ||
                DateTime.tryParse(raw['notifiedAt'] as String) == null)) ||
        (raw['expiresAt'] != null &&
            (raw['expiresAt'] is! String ||
                DateTime.tryParse(raw['expiresAt'] as String) == null)) ||
        (raw['closedAt'] != null &&
            (raw['closedAt'] is! String ||
                DateTime.tryParse(raw['closedAt'] as String) == null)) ||
        (raw['closureKind'] != null &&
            ![
              'delivered',
              'cancelled',
              'expired',
            ].contains(raw['closureKind']))) {
      throw const FormatException('Rezervasyon kaydı geçersiz');
    }
    result.add(Map<String, dynamic>.from(raw));
  }
  return result;
}

bool isActiveReservation(Map<String, dynamic> reservation) =>
    reservation['isClosed'] != true;
bool isReadyReservation(Map<String, dynamic> reservation, {DateTime? now}) {
  if (!isActiveReservation(reservation) || reservation['notifiedAt'] == null)
    return false;
  final expires = reservation['expiresAt'] == null
      ? null
      : DateTime.parse(reservation['expiresAt'] as String);
  return expires == null || expires.isAfter(now ?? DateTime.now());
}

Map<String, dynamic> addReservation(
  Map<String, dynamic> book,
  Map<String, dynamic> reservation,
) {
  final all = reservationsOf(book);
  final parsed = validateReservations([reservation]).single;
  if (!isActiveReservation(parsed) || parsed['notifiedAt'] != null)
    throw StateError('Yeni rezervasyon sırada olmalı');
  if (all.any(
    (r) =>
        r['id'] == parsed['id'] ||
        (isActiveReservation(r) &&
            parsed['studentId'] != null &&
            r['studentId'] == parsed['studentId']) ||
        (isActiveReservation(r) &&
            parsed['memberId'] != null &&
            r['memberId'] is String &&
            (r['memberId'] as String).toUpperCase() ==
                (parsed['memberId'] as String).toUpperCase()),
  )) {
    throw StateError('Bu öğrenci zaten sırada');
  }
  return {
    ...book,
    'reservations': [...all, parsed],
  };
}

Map<String, dynamic> closeReservation(
  Map<String, dynamic> book,
  String id,
  String reason, {
  DateTime? now,
}) {
  if (!['delivered', 'cancelled', 'expired'].contains(reason))
    throw ArgumentError('Kapanış nedeni geçersiz');
  final all = reservationsOf(book);
  final found = all
      .where((r) => r['id'] == id && isActiveReservation(r))
      .toList();
  if (found.length != 1) throw StateError('Açık rezervasyon bulunamadı');
  final timestamp = (now ?? DateTime.now()).toIso8601String();
  return {
    ...book,
    'reservations': all
        .map(
          (r) => r['id'] == id
              ? {
                  ...r,
                  'isClosed': true,
                  'closureKind': reason,
                  'closedAt': timestamp,
                }
              : r,
        )
        .toList(),
  };
}

/// Marks only the oldest waiting reservation ready; callers check free stock.
Map<String, dynamic> readyNextReservation(
  Map<String, dynamic> book, {
  DateTime? now,
  Duration hold = const Duration(days: 2),
}) {
  final timestamp = now ?? DateTime.now();
  final all = reservationsOf(book);
  final waiting =
      all
          .where((r) => isActiveReservation(r) && r['notifiedAt'] == null)
          .toList()
        ..sort(
          (a, b) => DateTime.parse(
            a['createdAt'] as String,
          ).compareTo(DateTime.parse(b['createdAt'] as String)),
        );
  if (waiting.isEmpty) return book;
  final id = waiting.first['id'];
  return {
    ...book,
    'reservations': all
        .map(
          (r) => r['id'] == id
              ? {
                  ...r,
                  'notifiedAt': timestamp.toIso8601String(),
                  'expiresAt': timestamp.add(hold).toIso8601String(),
                }
              : r,
        )
        .toList(),
  };
}
