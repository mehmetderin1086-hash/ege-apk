/// Maps inspected iPhone catalog data for a future migration preview.
/// Original records remain attached; no existing catalog is changed here.
List<Map<String, dynamic>> mapIphoneCatalog(
  List<dynamic> sourceBooks,
  List<dynamic> sourceLoans,
) {
  final byId = <String, Map<String, dynamic>>{};
  for (final source in sourceBooks) {
    if (source is! Map ||
        source['id'] is! String ||
        (source['id'] as String).isEmpty ||
        source['title'] is! String ||
        (source['title'] as String).trim().isEmpty ||
        source['author'] is! String) {
      throw const FormatException('iPhone kitap kaydı geçersiz');
    }
    final id = source['id'] as String;
    if (byId.containsKey(id)) {
      throw const FormatException('Tekrarlanan kitap kimliği');
    }
    final quantity = source['quantity'];
    if (source['isTextbook'] != null && source['isTextbook'] is! bool) {
      throw const FormatException('Ders kitabı durumu geçersiz');
    }
    if (source['isWithdrawn'] != null && source['isWithdrawn'] is! bool) {
      throw const FormatException('Düşülme durumu geçersiz');
    }
    if (source['withdrawnDate'] != null &&
        (source['withdrawnDate'] is! String ||
            DateTime.tryParse(source['withdrawnDate'] as String) == null)) {
      throw const FormatException('Düşülme tarihi geçersiz');
    }
    if (quantity != null && (quantity is! int || quantity < 1)) {
      throw const FormatException('Nüsha sayısı geçersiz');
    }
    for (final key in ['volume', 'rating']) {
      if (source[key] != null && source[key] is! int)
        throw FormatException('$key geçersiz');
    }
    String optional(String key) {
      final value = source[key];
      if (value != null && value is! String) {
        throw FormatException('$key geçersiz');
      }
      return value as String? ?? '';
    }

    final location = optional('location');
    final shelf = [
      optional('cabinet'),
      optional('shelf'),
    ].where((part) => part.isNotEmpty).join(' · ');
    byId[id] = {
      'id': id,
      'title': source['title'],
      'author': source['author'],
      'isbn': optional('isbn'),
      'publisher': optional('publisher'),
      'category': optional('category'),
      'series': optional('series'),
      'language': optional('language'),
      'tags': optional('tags'),
      'readingLevel': optional('readingLevel'),
      'readingStatus': optional('readingStatus'),
      'contentWarning': optional('contentWarning'),
      'accessionCode': optional('accessionCode'),
      'volume': source['volume'],
      'rating': source['rating'],
      'publicationYear': optional('publicationYear'),
      'edition': optional('edition'),
      'pageCount': optional('pageCount'),
      'notes': optional('notes'),
      'shelf': shelf.isEmpty ? location : shelf,
      'quantity': quantity ?? 1,
      'isWithdrawn': source['isWithdrawn'] == true,
      'isTextbook': source['isTextbook'] == true,
      'withdrawnReason': optional('withdrawnReason'),
      'withdrawnDate': source['withdrawnDate'],
      'loans': <Map<String, dynamic>>[],
      'iphoneOriginal': Map<String, dynamic>.from(source),
    };
  }
  final loanIds = <String>{};
  for (final source in sourceLoans) {
    if (source is! Map ||
        source['id'] is! String ||
        (source['id'] as String).isEmpty ||
        !loanIds.add(source['id'] as String) ||
        source['bookID'] is! String ||
        (source['studentClass'] != null && source['studentClass'] is! String) ||
        (source['identitySource'] != null &&
            source['identitySource'] is! String) ||
        (source['needsIdentityReview'] != null &&
            source['needsIdentityReview'] is! bool) ||
        (source['extensionCount'] != null &&
            (source['extensionCount'] is! int ||
                (source['extensionCount'] as int) < 0)) ||
        source['studentName'] is! String ||
        (source['studentName'] as String).trim().isEmpty ||
        source['dueDate'] is! String ||
        DateTime.tryParse(source['dueDate'] as String) == null) {
      throw const FormatException('iPhone ödünç kaydı geçersiz');
    }
    final book = byId[source['bookID']];
    if (book == null) {
      throw const FormatException('Ödünç kaydının kitabı bulunamadı');
    }
    final loans = book['loans'] as List<Map<String, dynamic>>;
    loans.add({
      'id': source['id'],
      'name': source['studentName'],
      'studentClass': source['studentClass'] ?? '',
      'due': source['dueDate'],
      'extensionCount': source['extensionCount'] ?? 0,
      if (source['kind'] == 'textbook') 'kind': 'textbook',
      if (source['periodSnapshot'] != null)
        'periodSnapshot': source['periodSnapshot'],
      if (source['studentNumberSnapshot'] is String)
        'studentNumberSnapshot': source['studentNumberSnapshot'],
      if (source['loanedAt'] is String) 'loanedAt': source['loanedAt'],
      if (source['identitySource'] != null)
        'identitySource': source['identitySource'],
      if (source['needsIdentityReview'] != null)
        'needsIdentityReview': source['needsIdentityReview'],
      'iphoneOriginal': Map<String, dynamic>.from(source),
    });
    if (loans.length > (book['quantity'] as int)) {
      throw const FormatException('Ödünç sayısı nüsha sayısını aşıyor');
    }
  }
  for (final book in byId.values) {
    final source = book['iphoneOriginal'] as Map<String, dynamic>;
    final value = source['loanedTo'];
    if (value != null && value is! String) {
      throw const FormatException('Eski ödünç alanı geçersiz');
    }
    final name = (value as String? ?? '').trim();
    if (name.isEmpty) continue;
    final due = source['loanDueDate'];
    if (due != null && (due is! String || DateTime.tryParse(due) == null)) {
      throw const FormatException('Eski ödünç tarihi geçersiz');
    }
    final loans = book['loans'] as List<Map<String, dynamic>>;
    final legacyId = 'iphone-legacy:${book['id']}';
    if (loans.any((loan) => loan['id'] == legacyId)) {
      throw const FormatException('Eski ödünç kimliği çakışıyor');
    }
    loans.add({
      'id': legacyId,
      'name': name,
      'studentClass': '',
      'due': due,
      'identitySource': 'legacy',
      'needsIdentityReview': true,
    });
    if (loans.length > (book['quantity'] as int)) {
      throw const FormatException(
        'Eski ödünç dahil toplam nüsha sayısı aşıldı',
      );
    }
  }
  return byId.values.toList();
}
