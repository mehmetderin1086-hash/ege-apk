import 'loan_model.dart';
import 'loan_settings.dart';
import 'student_store.dart';

/// A distribution is prepared entirely before the catalog is written.
Map<String, dynamic> distributeTextbooks(
  Map<String, dynamic> book,
  List<Student> students, {
  required DateTime due,
  required String period,
}) {
  if (book['isTextbook'] != true) throw StateError('Ders kitabı seçin');
  if (students.isEmpty) throw StateError('Öğrenci seçin');
  if (students.any((s) => s.graduatedAt != null)) {
    throw StateError('Mezun öğrenciye yeni dağıtım yapılamaz');
  }
  final ids = <String>{};
  if (students.any((s) => !ids.add(s.id.toUpperCase()))) {
    throw StateError('Öğrenci birden fazla kez seçildi');
  }
  if (availableCopies(book) < students.length) {
    throw StateError('Tüm öğrenciler için yeterli uygun nüsha yok');
  }
  var result = book;
  for (final student in students) {
    final already = activeLoans(result).any(
      (loan) =>
          loan['kind'] == 'textbook' &&
          loan['memberId'] == null &&
          ((loan['studentId'] is String &&
                  (loan['studentId'] as String).toUpperCase() ==
                      student.id.toUpperCase()) ||
              (loan['studentId'] == null &&
                  loan['identitySource'] != 'manual' &&
                  loan['name'] == student.name &&
                  loan['studentClass'] == student.className)),
    );
    if (already)
      throw StateError('${student.name} için ders kitabı zaten dağıtılmış');
    result = addLoan(result, {
      'id': newGradeRuleId(),
      'name': student.name,
      'studentClass': student.className,
      'studentId': student.id,
      'studentNumberSnapshot': student.number,
      'loanedAt': DateTime.now().toIso8601String(),
      'identitySource': 'student',
      'kind': 'textbook',
      'periodSnapshot': period.trim(),
      'due': due.toIso8601String(),
    }, allowDuplicate: true);
  }
  return result;
}

Map<String, dynamic> collectTextbooks(
  Map<String, dynamic> book,
  Map<String, String?> conditions,
) {
  if (conditions.isEmpty) throw StateError('Teslim alınacak kitapları seçin');
  var result = book;
  for (final entry in conditions.entries) {
    final loan = activeLoans(
      result,
    ).where((l) => l['id'] == entry.key).toList();
    if (loan.length != 1 || loan.single['kind'] != 'textbook') {
      throw StateError('Ders kitabı ödüncü bulunamadı');
    }
    result = returnLoan(result, entry.key, returnedCondition: entry.value);
  }
  return result;
}
