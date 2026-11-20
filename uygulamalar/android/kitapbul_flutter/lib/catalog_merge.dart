import 'catalog_search.dart';
import 'isbn.dart';

const mergeFields = [
  'title',
  'author',
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
  'rating',
  'shelf',
  'publicationYear',
  'edition',
  'pageCount',
  'notes',
];

bool canMergeCopies(
  Map<String, dynamic> incoming,
  Map<String, dynamic> existing,
) {
  if (incoming['isWithdrawn'] == true || existing['isWithdrawn'] == true) {
    return false;
  }
  final isbn = canonicalIsbn((incoming['isbn'] ?? '').toString());
  if (isbn == null ||
      isbn != canonicalIsbn((existing['isbn'] ?? '').toString())) {
    return false;
  }
  for (final key in ['coverBase64', 'backCoverBase64', 'imprintBase64']) {
    if (incoming[key] != null &&
        existing[key] != null &&
        incoming[key] != existing[key])
      return false;
  }
  for (final key in mergeFields) {
    final a = (incoming[key] ?? '').toString().trim();
    final b = (existing[key] ?? '').toString().trim();
    if (a.isNotEmpty && b.isNotEmpty && foldTurkish(a) != foldTurkish(b)) {
      return false;
    }
  }
  final count = incoming['quantity'];
  final current = existing['quantity'];
  return count is int &&
      current is int &&
      count > 0 &&
      current > 0 &&
      current + count <= 1000000;
}

Map<String, dynamic> mergeCopies(
  Map<String, dynamic> incoming,
  Map<String, dynamic> existing,
) {
  if (!canMergeCopies(incoming, existing)) {
    throw StateError('Kayıtlar birleştirilemez');
  }
  final result = Map<String, dynamic>.from(existing);
  for (final key in mergeFields) {
    if ((result[key] ?? '').toString().trim().isEmpty &&
        (incoming[key] ?? '').toString().trim().isNotEmpty) {
      result[key] = incoming[key];
    }
  }
  for (final key in ['coverBase64', 'backCoverBase64', 'imprintBase64']) {
    if (result[key] == null && incoming[key] != null)
      result[key] = incoming[key];
  }
  result['quantity'] =
      (existing['quantity'] as int) + (incoming['quantity'] as int);
  return result;
}
