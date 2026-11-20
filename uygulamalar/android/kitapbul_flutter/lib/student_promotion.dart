import 'student_store.dart';
import 'loan_model.dart';
import 'reservation_model.dart';

String? nextClass(String current, int finalGrade) {
  if (finalGrade < 4 || finalGrade > 12)
    throw ArgumentError('Son kademe 4 ile 12 arasında olmalı');
  final match = RegExp(r'[0-9]+').firstMatch(current);
  if (match == null) return current;
  final grade = int.tryParse(match.group(0)!);
  if (grade == null) return current;
  if (grade >= finalGrade) return null;
  return current.replaceRange(match.start, match.end, '${grade + 1}');
}

class PromotionChange {
  PromotionChange(this.before, this.next);
  final Student before;
  final String? next;
}

List<PromotionChange> planPromotion(List<Student> students, int finalGrade) => [
  for (final s in students.where((s) => s.graduatedAt == null))
    if (nextClass(s.className, finalGrade) != s.className)
      PromotionChange(s, nextClass(s.className, finalGrade)),
];

class PromotionResult {
  PromotionResult(this.students, this.books);
  final List<Student> students;
  final List<Map<String, dynamic>> books;
}

PromotionResult applyPromotion(
  List<Student> students,
  List<Map<String, dynamic>> books,
  List<PromotionChange> plan, {
  DateTime? now,
}) {
  final current = {for (final s in students) s.id: s};
  final seen = <String>{};
  for (final change in plan) {
    final old = current[change.before.id];
    if (old == null ||
        !seen.add(old.id) ||
        old.graduatedAt != null ||
        old.toJson().toString() != change.before.toJson().toString()) {
      throw StateError('Öğrenci listesi değişti; planı yeniden oluşturun');
    }
  }
  final changes = {for (final change in plan) change.before.id: change};
  final updated = students.map((s) {
    final change = changes[s.id];
    if (change == null) return s;
    return Student(
      id: s.id,
      name: s.name,
      number: s.number,
      className: change.next ?? s.className,
      graduatedAt: change.next == null
          ? (now ?? DateTime.now()).toIso8601String()
          : null,
    );
  }).toList();
  String key(String name, String klass) =>
      '${name.trim().toLowerCase()}\u0000${klass.trim().toLowerCase()}';
  final legacy = <String, List<String>>{};
  for (final s in students.where((s) => s.graduatedAt == null)) {
    final change = changes[s.id];
    legacy
        .putIfAbsent(key(s.name, s.className), () => [])
        .add(change == null ? s.className : change.next ?? 'Mezun');
  }
  final resultBooks = books
      .map(
        (book) => {
          ...book,
          'loans': activeLoans(book).map((loan) {
            final change = changes[loan['studentId']];
            if (change != null)
              return {...loan, 'studentClass': change.next ?? 'Mezun'};
            if (loan['studentId'] == null &&
                loan['memberId'] == null &&
                loan['identitySource'] != 'manual') {
              final matches =
                  legacy[key(
                    (loan['name'] ?? '').toString(),
                    (loan['studentClass'] ?? '').toString(),
                  )];
              if (matches != null && matches.length == 1)
                return {...loan, 'studentClass': matches.single};
              if (matches != null && matches.length > 1)
                return {...loan, 'needsIdentityReview': true};
            }
            return loan;
          }).toList(),
          if (book['reservations'] != null)
            'reservations': reservationsOf(book).map((r) {
              final change = changes[r['studentId']];
              return isActiveReservation(r) && change != null
                  ? {...r, 'studentClass': change.next ?? 'Mezun'}
                  : r;
            }).toList(),
        },
      )
      .toList();
  return PromotionResult(updated, resultBooks);
}
