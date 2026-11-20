import 'catalog_search.dart';
import 'loan_model.dart';

class ClassSummary {
  const ClassSummary({
    required this.name,
    required this.total,
    required this.overdue,
  });
  final String name;
  final int total;
  final int overdue;
}

List<ClassSummary> summarizeClasses(
  List<Map<String, dynamic>> books, {
  DateTime? now,
}) {
  final counts = <String, List<dynamic>>{};
  for (final book in books) {
    if (book['deletedAt'] != null) continue;
    for (final loan in activeLoans(book)) {
      if (loan['kind'] == 'textbook') continue;
      final className = (loan['studentClass'] as String? ?? '').trim();
      final key = foldTurkish(className);
      final entry = counts.putIfAbsent(
        key,
        () => [className.isEmpty ? 'Sınıf belirtilmemiş' : className, 0, 0],
      );
      entry[1] = (entry[1] as int) + 1;
      if (isOverdue(loan, now: now)) entry[2] = (entry[2] as int) + 1;
    }
  }
  final result = counts.values
      .map(
        (v) => ClassSummary(
          name: v[0] as String,
          total: v[1] as int,
          overdue: v[2] as int,
        ),
      )
      .toList();
  result.sort((a, b) => foldTurkish(a.name).compareTo(foldTurkish(b.name)));
  return result;
}
