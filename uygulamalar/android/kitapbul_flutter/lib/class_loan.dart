import 'loan_model.dart';
import 'loan_settings.dart';
import 'reservation_model.dart';
import 'student_store.dart';

class ClassLoanResult {
  const ClassLoanResult({
    required this.books,
    required this.lent,
    required this.skipped,
    required this.failures,
  });
  final List<Map<String, dynamic>> books;
  final List<String> lent, skipped, failures;
}

/// Prepares all successful loans before a single catalog save; each student's
/// expected policy or stock failure is reported without changing that student.
ClassLoanResult prepareClassLoans(
  List<Map<String, dynamic>> books,
  String bookId,
  List<Student> students,
  LoanSettings settings, {
  DateTime? now,
}) {
  if (students.isEmpty) throw StateError('Öğrenci seçin');
  final ids = <String>{};
  if (students.any((s) => !ids.add(s.id.toUpperCase())))
    throw StateError('Öğrenci birden fazla seçildi');
  final matches = books
      .where((b) => b['id'] == bookId && b['deletedAt'] == null)
      .toList();
  if (matches.length != 1) throw StateError('Kitap bulunamadı');
  final time = now ?? DateTime.now();
  var book = advanceReservationQueue(matches.single, now: time);
  final lent = <String>[], skipped = <String>[], failures = <String>[];
  for (final student in students) {
    if (student.graduatedAt != null) {
      failures.add('${student.name}: Mezun öğrenciye yeni ödünç verilemez.');
      continue;
    }
    final borrower = <String, dynamic>{
      'name': student.name,
      'studentClass': student.className,
      'studentId': student.id,
    };
    if (hasDuplicateBorrower(book, borrower)) {
      skipped.add(student.name);
      continue;
    }
    final currentBooks = books
        .map((b) => b['id'] == bookId ? book : b)
        .toList();
    final violation = loanPolicyViolation(
      currentBooks,
      borrower,
      settings,
      now: time,
    );
    if (violation != null) {
      failures.add('${student.name}: $violation');
      continue;
    }
    try {
      final ready = reservationsOf(book)
          .where(
            (r) =>
                isReadyReservation(r, now: time) &&
                r['studentId'] is String &&
                (r['studentId'] as String).toUpperCase() ==
                    student.id.toUpperCase(),
          )
          .firstOrNull;
      final loan = {
        'id': newGradeRuleId(),
        'name': student.name,
        'studentClass': student.className,
        'studentId': student.id,
        'studentNumberSnapshot': student.number,
        'identitySource': 'student',
        'loanedAt': time.toIso8601String(),
        'due': time
            .add(Duration(days: settings.durationFor(student.className)))
            .toIso8601String(),
      };
      var candidate = book;
      if (ready != null) {
        candidate = closeReservation(
          candidate,
          ready['id'] as String,
          'delivered',
          now: time,
        );
        candidate = addLoan(
          candidate,
          loan,
          copyId: ready['copyId'] as String?,
          honorQueue: false,
        );
      } else {
        candidate = addLoan(candidate, loan);
      }
      for (final reservation in reservationsOf(candidate)) {
        if (isActiveReservation(reservation) &&
            reservation['studentId'] is String &&
            (reservation['studentId'] as String).toUpperCase() ==
                student.id.toUpperCase()) {
          candidate = closeReservation(
            candidate,
            reservation['id'] as String,
            'delivered',
            now: time,
          );
        }
      }
      book = advanceReservationQueue(candidate, now: time);
      lent.add(student.name);
    } on StateError catch (e) {
      failures.add('${student.name}: ${e.message}');
    } on ArgumentError catch (e) {
      failures.add('${student.name}: ${e.message}');
    }
  }
  return ClassLoanResult(
    books: books.map((b) => b['id'] == bookId ? book : b).toList(),
    lent: lent,
    skipped: skipped,
    failures: failures,
  );
}
