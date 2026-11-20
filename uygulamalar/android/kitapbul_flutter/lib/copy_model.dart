/// Validates iPhone physical copy records without losing their metadata.
List<Map<String, dynamic>> validateCopies(
  dynamic value, {
  required String bookId,
  required int quantity,
}) {
  if (value is! List) throw const FormatException('Nüsha listesi geçersiz');
  if (value.length > quantity)
    throw const FormatException('Nüsha sayısı kitap adedini aşıyor');
  final ids = <String>{};
  final records = <Map<String, dynamic>>[];
  for (final raw in value) {
    if (raw is! Map ||
        raw['id'] is! String ||
        (raw['id'] as String).trim().isEmpty ||
        !ids.add((raw['id'] as String).toUpperCase()) ||
        raw['bookID'] is! String ||
        (raw['bookID'] as String).toUpperCase() != bookId.toUpperCase() ||
        raw['accessionCode'] is! String ||
        raw['condition'] is! String ||
        raw['status'] is! String ||
        !['Rafta', 'Onarımda', 'Kayıp', 'Düşüldü'].contains(raw['status']) ||
        raw['note'] is! String ||
        raw['addedAt'] is! String ||
        DateTime.tryParse(raw['addedAt'] as String) == null ||
        (raw['cabinet'] != null && raw['cabinet'] is! String) ||
        (raw['shelf'] != null && raw['shelf'] is! String)) {
      throw const FormatException(
        'Nüsha kaydı geçersiz veya kitapla eşleşmiyor',
      );
    }
    records.add(Map<String, dynamic>.from(raw));
  }
  return records;
}

/// Bound loans must refer to distinct copies of this book that are in circulation.
void validateCopyLoans(
  List<Map<String, dynamic>> copies,
  List<Map<String, dynamic>> loans,
  int quantity, {
  int otherLost = 0,
}) {
  final byId = {
    for (final copy in copies) (copy['id'] as String).toUpperCase(): copy,
  };
  final used = <String>{};
  var anonymous = 0;
  for (final loan in loans) {
    final id = loan['copyId'];
    if (id == null) {
      anonymous++;
      continue;
    }
    if (id is! String ||
        !used.add(id.toUpperCase()) ||
        byId[id.toUpperCase()]?['status'] != 'Rafta') {
      throw const FormatException('Ödüncün nüsha bağlantısı geçersiz');
    }
  }
  if (otherLost < 0 || anonymous + otherLost > quantity - copies.length) {
    throw const FormatException(
      'Kimliği belirlenmemiş ödünç veya kayıp nüsha sayısı adedi aşıyor',
    );
  }
}

int availablePhysicalAndUntracked(
  List<Map<String, dynamic>> copies,
  List<Map<String, dynamic>> loans,
  int quantity, {
  int otherLost = 0,
}) {
  validateCopyLoans(copies, loans, quantity, otherLost: otherLost);
  final used = {
    for (final loan in loans)
      if (loan['copyId'] is String) (loan['copyId'] as String).toUpperCase(),
  };
  final anonymous = loans.where((loan) => loan['copyId'] == null).length;
  return copies
          .where(
            (copy) =>
                copy['status'] == 'Rafta' &&
                !used.contains((copy['id'] as String).toUpperCase()),
          )
          .length +
      quantity -
      copies.length -
      anonymous -
      otherLost;
}

/// Prepares isolated candidate data; callers must not persist until circulation
/// actions and backup validation understand the copies as well.
List<Map<String, dynamic>> prepareIPhoneCopies(
  List<Map<String, dynamic>> books,
  dynamic rawCopies,
) {
  if (rawCopies is! List) throw const FormatException('Nüsha listesi geçersiz');
  final byId = <String, Map<String, dynamic>>{};
  for (final book in books) {
    final id = (book['id'] as String).toUpperCase();
    if (byId.containsKey(id))
      throw const FormatException('Kitap kimlikleri çakışıyor');
    byId[id] = {
      ...book,
      'loans': (book['loans'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList(),
      'copies': <Map<String, dynamic>>[],
    };
  }
  final copyIds = <String>{};
  for (final value in rawCopies) {
    if (value is! Map || value['bookID'] is! String || value['id'] is! String)
      throw const FormatException('Nüsha kaydı geçersiz');
    final id = (value['id'] as String).toUpperCase();
    if (!copyIds.add(id))
      throw const FormatException('Nüsha kimliği tekrarlanıyor');
    final book = byId[(value['bookID'] as String).toUpperCase()];
    if (book == null) throw const FormatException('Nüshanın kitabı bulunamadı');
    (book['copies'] as List).add(Map<String, dynamic>.from(value));
  }
  for (final book in byId.values) {
    final copies = validateCopies(
      book['copies'],
      bookId: book['id'] as String,
      quantity: book['quantity'] as int,
    );
    final loans = (book['loans'] as List).cast<Map<String, dynamic>>();
    for (final loan in loans) {
      final original = loan['iphoneOriginal'];
      if (original is Map && original['copyID'] != null) {
        if (original['copyID'] is! String)
          throw const FormatException('Ödünç nüsha kimliği geçersiz');
        loan['copyId'] = original['copyID'];
      }
    }
    validateCopyLoans(copies, loans, book['quantity'] as int);
    book['lostCount'] = copies
        .where((copy) => copy['status'] == 'Kayıp')
        .length;
  }
  return byId.values.toList();
}
