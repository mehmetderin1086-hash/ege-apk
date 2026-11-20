import 'loan_model.dart';
import 'isbn.dart';

/// Turkish case-insensitive matching without changing saved catalog values.
String foldTurkish(String value) =>
    value.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

bool matchesCatalog(Map<String, dynamic> book, String query) {
  final search = foldTurkish(query.trim());
  if (search.isEmpty) return true;
  final key = canonicalIsbn(query);
  if (key != null && key == canonicalIsbn((book['isbn'] ?? '').toString()))
    return true;
  final content = [
    'title',
    'author',
    'isbn',
    'shelf',
    'publisher',
    'category',
    'series',
    'language',
    'tags',
    'readingLevel',
    'readingStatus',
    'contentWarning',
    'accessionCode',
    'volume',
    'publicationYear',
    'edition',
    'notes',
  ].map((key) => book[key]?.toString() ?? '').join(' ');
  if (foldTurkish(content).contains(search)) return true;
  final copies = book['copies'];
  if (copies is List) {
    return copies.whereType<Map>().any(
      (copy) => foldTurkish(
        (copy['accessionCode'] ?? '').toString(),
      ).contains(search),
    );
  }
  return false;
}

/// In overdue mode, person/class matches must belong to the overdue loan.
bool matchesLoanSearch(
  Map<String, dynamic> book,
  String query, {
  bool overdueOnly = false,
  DateTime? now,
}) {
  final raw = book['loans'];
  if (raw is! List) return false;
  final loans = raw.whereType<Map>().map(
    (entry) => Map<String, dynamic>.from(entry),
  );
  final search = foldTurkish(query.trim());
  final bookMatches = matchesCatalog(book, query);
  return loans.any((loan) {
    if (overdueOnly &&
        (loan['kind'] == 'textbook' || !isOverdue(loan, now: now)))
      return false;
    if (search.isEmpty || bookMatches) return true;
    return foldTurkish(
      '${loan['name'] ?? ''} ${loan['studentClass'] ?? ''}',
    ).contains(search);
  });
}
