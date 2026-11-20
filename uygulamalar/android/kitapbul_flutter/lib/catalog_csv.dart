import 'loan_model.dart';

enum CatalogColumn {
  title('Kitap Adı'),
  author('Yazar'),
  publisher('Yayınevi'),
  isbn('ISBN'),
  year('Yıl'),
  category('Kategori'),
  language('Dil'),
  tags('Etiketler'),
  readingLevel('Okuma Düzeyi'),
  readingStatus('Okuma Durumu'),
  accessionCode('Demirbaş'),
  volume('Cilt'),
  rating('Puan'),
  contentWarning('İçerik Uyarısı'),
  quantity('Adet'),
  available('Ödünç Verilebilir'),
  shelf('Raf / Konum'),
  series('Seri'),
  edition('Baskı'),
  pageCount('Sayfa'),
  notes('Notlar');

  const CatalogColumn(this.label);
  final String label;
  String value(Map<String, dynamic> book) => switch (this) {
    CatalogColumn.title => '${book['title'] ?? ''}',
    CatalogColumn.author => '${book['author'] ?? ''}',
    CatalogColumn.publisher => '${book['publisher'] ?? ''}',
    CatalogColumn.isbn => '${book['isbn'] ?? ''}',
    CatalogColumn.year => '${book['publicationYear'] ?? ''}',
    CatalogColumn.category => '${book['category'] ?? ''}',
    CatalogColumn.language => '${book['language'] ?? ''}',
    CatalogColumn.tags => '${book['tags'] ?? ''}',
    CatalogColumn.readingLevel => '${book['readingLevel'] ?? ''}',
    CatalogColumn.readingStatus => '${book['readingStatus'] ?? ''}',
    CatalogColumn.accessionCode => '${book['accessionCode'] ?? ''}',
    CatalogColumn.volume => '${book['volume'] ?? ''}',
    CatalogColumn.rating => '${book['rating'] ?? ''}',
    CatalogColumn.contentWarning => '${book['contentWarning'] ?? ''}',
    CatalogColumn.quantity => '${book['quantity'] ?? 1}',
    CatalogColumn.available => '${availableCopies(book)}',
    CatalogColumn.shelf => '${book['shelf'] ?? ''}',
    CatalogColumn.series => '${book['series'] ?? ''}',
    CatalogColumn.edition => '${book['edition'] ?? ''}',
    CatalogColumn.pageCount => '${book['pageCount'] ?? ''}',
    CatalogColumn.notes => '${book['notes'] ?? ''}',
  };
}

String csvCell(String source) {
  var value = source.replaceAll(RegExp(r'[\r\n]+'), ' ');
  final leading = value.trimLeft();
  if (leading.startsWith('=') ||
      leading.startsWith('+') ||
      leading.startsWith('-') ||
      leading.startsWith('@') ||
      value.startsWith('\t'))
    value = "'$value";
  return value.contains(';') || value.contains('"') || value.startsWith("'")
      ? '"${value.replaceAll('"', '""')}"'
      : value;
}

String catalogCsv(
  List<Map<String, dynamic>> books,
  List<CatalogColumn> columns,
) {
  if (columns.isEmpty || columns.toSet().length != columns.length)
    throw ArgumentError('En az bir farklı sütun seçin');
  final rows = <String>[
    columns.map((column) => csvCell(column.label)).join(';'),
  ];
  for (final book in books.where((book) => book['deletedAt'] == null)) {
    rows.add(columns.map((column) => csvCell(column.value(book))).join(';'));
  }
  return '\uFEFF${rows.join('\r\n')}\r\n';
}
