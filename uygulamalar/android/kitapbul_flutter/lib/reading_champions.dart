import 'catalog_search.dart';
import 'loan_model.dart';
import 'student_store.dart';

class ReadingChampion {
  const ReadingChampion({
    required this.studentId,
    required this.name,
    required this.className,
    required this.books,
    required this.points,
  });
  final String studentId, name, className;
  final int books, points;
}

/// An identified completed library reading counts once per book and student.
List<ReadingChampion> readingChampions(
  List<Map<String, dynamic>> books,
  List<Student> students,
) {
  final best = <String, Map<String, int>>{};
  final latest = <String, DateTime>{};
  final names = <String, String>{},
      classes = <String, String>{},
      ids = <String, String>{};
  for (final book in books) {
    final bookId = book['id'];
    if (bookId is! String || bookId.isEmpty) continue;
    for (final event in loanHistory(book)) {
      final id = event['studentId'];
      final name = event['person'];
      final original = event['iphoneOriginal'];
      final source =
          event['identitySource'] ??
          (original is Map ? original['identitySource'] : null);
      final date = DateTime.tryParse((event['date'] ?? '').toString());
      if (event['kind'] != 'returned' ||
          event['readingCompleted'] != true ||
          event['loanKind'] == 'textbook' ||
          id is! String ||
          id.isEmpty ||
          event['memberId'] != null ||
          source == 'manual' ||
          name is! String ||
          name.trim().isEmpty ||
          date == null)
        continue;
      final key = id.toUpperCase();
      final works = best.putIfAbsent(key, () => {});
      final bookKey = bookId.toUpperCase();
      final score = event['late'] == true ? 3 : 10;
      if (score > (works[bookKey] ?? 0)) works[bookKey] = score;
      if (latest[key] == null || !date.isBefore(latest[key]!)) {
        latest[key] = date;
        names[key] = name;
        classes[key] = (event['studentClass'] ?? '').toString();
        ids[key] = id;
      }
    }
  }
  final studentById = {
    for (final student in students) student.id.toUpperCase(): student,
  };
  final result = <ReadingChampion>[];
  for (final entry in best.entries) {
    final student = studentById[entry.key];
    final klass = student?.graduatedAt != null
        ? 'Mezun'
        : (student?.className.isNotEmpty == true
              ? student!.className
              : classes[entry.key] ?? '');
    result.add(
      ReadingChampion(
        studentId: ids[entry.key]!,
        name: names[entry.key]!,
        className: klass.isEmpty ? 'Sınıf belirtilmemiş' : klass,
        books: entry.value.length,
        points: entry.value.values.fold(0, (a, b) => a + b),
      ),
    );
  }
  result.sort((a, b) {
    final score = b.points.compareTo(a.points);
    return score != 0
        ? score
        : foldTurkish(a.name).compareTo(foldTurkish(b.name));
  });
  return result;
}

List<({String className, int books})> championClassTotals(
  List<ReadingChampion> champions,
) {
  final totals = <String, int>{};
  for (final c in champions) {
    totals[c.className] = (totals[c.className] ?? 0) + c.books;
  }
  final result = totals.entries
      .map((e) => (className: e.key, books: e.value))
      .toList();
  result.sort((a, b) {
    final count = b.books.compareTo(a.books);
    return count != 0
        ? count
        : foldTurkish(a.className).compareTo(foldTurkish(b.className));
  });
  return result;
}
