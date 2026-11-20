import 'catalog_search.dart';
import 'isbn.dart';

enum DataQualityField {
  isbn('ISBN eksik'),
  invalidIsbn('ISBN geçersiz'),
  author('Yazar eksik / genel'),
  publisher('Yayınevi eksik'),
  category('Kategori eksik'),
  cover('Kapak görseli eksik'),
  pages('Sayfa sayısı eksik'),
  shelf('Raf / konum eksik'),
  accession('Demirbaş kodu eksik');

  const DataQualityField(this.label);
  final String label;
}

bool isQualityCandidate(Map<String, dynamic> book) =>
    book['deletedAt'] == null && book['isWithdrawn'] != true;
bool missingQualityField(Map<String, dynamic> book, DataQualityField field) {
  if (!isQualityCandidate(book)) return false;
  String get(String key) => (book[key] ?? '').toString().trim();
  return switch (field) {
    DataQualityField.isbn => get('isbn').isEmpty,
    DataQualityField.invalidIsbn =>
      get('isbn').isNotEmpty && !isValidIsbn(get('isbn')),
    DataQualityField.author =>
      get('author').isEmpty ||
          {
            'kolektif',
            'anonim',
            'bilinmiyor',
            'derleme',
            'yazar bilinmiyor',
            'various',
          }.contains(foldTurkish(get('author'))),
    DataQualityField.publisher => get('publisher').isEmpty,
    DataQualityField.category => get('category').isEmpty,
    DataQualityField.cover => get('coverBase64').isEmpty,
    DataQualityField.pages => get('pageCount').isEmpty,
    DataQualityField.shelf => get('shelf').isEmpty,
    DataQualityField.accession => get('accessionCode').isEmpty,
  };
}

Map<DataQualityField, int> qualityCounts(List<Map<String, dynamic>> books) => {
  for (final field in DataQualityField.values)
    field: books.where((book) => missingQualityField(book, field)).length,
};
