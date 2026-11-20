import 'loan_model.dart';
import 'reading_champions.dart';
import 'reservation_model.dart';
import 'student_store.dart';

class StudentProfile {
  const StudentProfile({
    required this.active,
    required this.reservations,
    required this.history,
    required this.points,
    required this.completedBooks,
    required this.returns,
    required this.lateReturns,
  });
  final List<({String title, Map<String, dynamic> entry})> active,
      reservations,
      history;
  final int points, completedBooks, returns, lateReturns;
}

StudentProfile buildStudentProfile(
  Student student,
  List<Map<String, dynamic>> books,
) {
  final active = <({String title, Map<String, dynamic> entry})>[];
  final reservations = <({String title, Map<String, dynamic> entry})>[];
  final history = <({String title, Map<String, dynamic> entry})>[];
  bool belongs(Map<String, dynamic> entry) =>
      entry['memberId'] == null &&
      entry['studentId'] is String &&
      (entry['studentId'] as String).toUpperCase() == student.id.toUpperCase();
  for (final book in books) {
    final title = (book['title'] ?? '').toString();
    for (final loan in activeLoans(book).where(belongs)) {
      active.add((title: title, entry: loan));
    }
    for (final reservation in reservationsOf(
      book,
    ).where((r) => isActiveReservation(r) && belongs(r))) {
      reservations.add((title: title, entry: reservation));
    }
    for (final event in loanHistory(book).where(belongs)) {
      history.add((title: title, entry: event));
    }
  }
  history.sort(
    (a, b) =>
        ((DateTime.tryParse((b.entry['date'] ?? '').toString()) ??
                DateTime(1900))
            .compareTo(
              DateTime.tryParse((a.entry['date'] ?? '').toString()) ??
                  DateTime(1900),
            )),
  );
  final scores = readingChampions(books, [student])
      .where((c) => c.studentId.toUpperCase() == student.id.toUpperCase())
      .firstOrNull;
  final returns = history.where((e) => e.entry['kind'] == 'returned').toList();
  return StudentProfile(
    active: active,
    reservations: reservations,
    history: history,
    points: scores?.points ?? 0,
    completedBooks: scores?.books ?? 0,
    returns: returns.length,
    lateReturns: returns.where((e) => e.entry['late'] == true).length,
  );
}
