import 'dart:convert';
import 'dart:typed_data';
import 'student_store.dart';
import 'loan_model.dart';
import 'reservation_model.dart';

class StudentImportReceipt {
  const StudentImportReceipt({required this.before, required this.after});
  final List<Student> before;
  final List<Student> after;
  Map<String, dynamic> toJson() => {
    'before': before.map((s) => s.toJson()).toList(),
    'after': after.map((s) => s.toJson()).toList(),
  };
  static StudentImportReceipt parse(dynamic value) {
    if (value is List)
      return StudentImportReceipt(
        before: const [],
        after: decodeStudents(jsonEncode(value)),
      );
    if (value is! Map || value['before'] is! List || value['after'] is! List)
      throw const FormatException('Aktarım kaydı geçersiz');
    final before = decodeStudents(jsonEncode(value['before']));
    final after = decodeStudents(jsonEncode(value['after']));
    final ids = after.map((s) => s.id).toSet();
    if (after.isEmpty || before.any((s) => !ids.contains(s.id)))
      throw const FormatException('Aktarım kaydı tutarsız');
    return StudentImportReceipt(before: before, after: after);
  }
}

List<Map<String, dynamic>> syncStudentLoans(
  List<Map<String, dynamic>> books,
  List<Student> changed,
) {
  final byId = {for (final s in changed) s.id: s};
  return books
      .map(
        (book) => {
          ...book,
          'loans': activeLoans(book).map((loan) {
            final student = byId[loan['studentId']];
            return student == null
                ? loan
                : {
                    ...loan,
                    'name': student.name,
                    'studentClass': student.className,
                  };
          }).toList(),
          if (book['reservations'] != null)
            'reservations': reservationsOf(book).map((r) {
              final student = byId[r['studentId']];
              return student == null || !isActiveReservation(r)
                  ? r
                  : {
                      ...r,
                      'name': student.name,
                      'studentClass': student.className,
                    };
            }).toList(),
        },
      )
      .toList();
}

bool canUndoStudentImport(
  StudentImportReceipt receipt,
  List<Student> current,
  List<Map<String, dynamic>> books,
) {
  final byId = {for (final student in current) student.id: student};
  final ids = receipt.after.map((s) => s.id).toSet();
  final updatedIds = receipt.before.map((s) => s.id).toSet();
  final addedIds = ids.difference(updatedIds);
  if (receipt.after.isEmpty || ids.length != receipt.after.length) return false;
  if (receipt.after.any(
    (s) =>
        byId[s.id] == null ||
        jsonEncode(byId[s.id]!.toJson()) != jsonEncode(s.toJson()),
  ))
    return false;
  return !books.any(
    (book) =>
        activeLoans(book).any((loan) {
          final id = loan['studentId'];
          if (addedIds.contains(id)) return true;
          final student = byId[id];
          return updatedIds.contains(id) &&
              student != null &&
              (loan['name'] != student.name ||
                  loan['studentClass'] != student.className);
        }) ||
        loanHistory(
          book,
        ).any((event) => addedIds.contains(event['studentId'])) ||
        reservationsOf(book).any((r) {
          final id = r['studentId'];
          if (addedIds.contains(id)) return true;
          final student = byId[id];
          return isActiveReservation(r) &&
              updatedIds.contains(id) &&
              student != null &&
              (r['name'] != student.name ||
                  r['studentClass'] != student.className);
        }),
  );
}

List<List<String>> parseStudentCsv(Uint8List bytes) {
  var input = utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
  input = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final counts = {',': 0, ';': 0, '\t': 0};
  var headerQuoted = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '"') {
      if (headerQuoted && i + 1 < input.length && input[i + 1] == '"') {
        i++;
      } else {
        headerQuoted = !headerQuoted;
      }
    } else if (!headerQuoted && ch == '\n') {
      break;
    } else if (!headerQuoted && counts.containsKey(ch)) {
      counts[ch] = counts[ch]! + 1;
    }
  }
  final delimiter = counts.entries
      .reduce((a, b) => b.value > a.value ? b : a)
      .key;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var closedQuote = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (quoted) {
        quoted = false;
        closedQuote = true;
      } else if (cell.toString().trim().isEmpty && !closedQuote) {
        cell.clear();
        quoted = true;
      } else {
        throw const FormatException('CSV tırnak işareti geçersiz');
      }
    } else if (!quoted && (ch == delimiter || ch == '\n')) {
      row.add(cell.toString().trim());
      cell.clear();
      closedQuote = false;
      if (ch == '\n') {
        if (row.any((v) => v.isNotEmpty)) rows.add(row);
        row = [];
      }
    } else if (closedQuote && ch.trim().isNotEmpty) {
      throw const FormatException('CSV tırnak işareti geçersiz');
    } else {
      cell.write(ch);
    }
  }
  if (quoted) throw const FormatException('CSV içinde kapanmamış tırnak var');
  if (row.isNotEmpty || cell.isNotEmpty) {
    row.add(cell.toString().trim());
    if (row.any((v) => v.isNotEmpty)) rows.add(row);
  }
  if (rows.isEmpty ||
      rows.length > 10000 ||
      rows.any((row) => row.length > 100))
    throw const FormatException(
      'CSV boş veya izin verilen satır/sütun sınırını aşıyor',
    );
  return rows;
}

class StudentCsvPreview {
  StudentCsvPreview(
    this.students,
    this.issues, {
    this.beforeUpdates = const [],
    this.afterUpdates = const [],
  });
  final List<Student> students;
  final List<String> issues;
  final List<Student> beforeUpdates;
  final List<Student> afterUpdates;
  int get skipped => issues.length;
}

StudentCsvPreview previewStudentCsv(
  List<List<String>> rows,
  List<Student> existing, {
  required int nameColumn,
  required int numberColumn,
  required int classColumn,
  required bool header,
  bool updateMatches = false,
}) {
  final columns = [
    nameColumn,
    numberColumn,
    classColumn,
  ].where((v) => v >= 0).toList();
  if (nameColumn < 0 || columns.toSet().length != columns.length)
    throw const FormatException('Her alan için ayrı sütun seçin');
  final added = <Student>[];
  final issues = <String>[];
  String key(String name, String number, String className) =>
      jsonEncode([name.toLowerCase(), number, className.toLowerCase()]);
  final keys = {for (final s in existing) key(s.name, s.number, s.className)};
  final numbers = {
    for (final s in existing)
      if (s.number.isNotEmpty) s.number,
  };
  final beforeUpdates = <Student>[];
  final afterUpdates = <Student>[];
  final numberCounts = <String, int>{};
  if (numberColumn >= 0) {
    for (final row in rows.skip(header ? 1 : 0)) {
      if (numberColumn < row.length && row[numberColumn].trim().isNotEmpty) {
        final number = row[numberColumn].trim();
        numberCounts[number] = (numberCounts[number] ?? 0) + 1;
      }
    }
  }
  final byNumber = <String, List<Student>>{};
  final byNameClass = <String, List<Student>>{};
  for (final student in existing) {
    if (student.number.isNotEmpty)
      byNumber.putIfAbsent(student.number, () => []).add(student);
    byNameClass
        .putIfAbsent(
          jsonEncode([
            student.name.toLowerCase(),
            student.className.toLowerCase(),
          ]),
          () => [],
        )
        .add(student);
  }
  var line = header ? 1 : 0;
  for (final row in rows.skip(header ? 1 : 0)) {
    line++;
    String value(int column) =>
        column >= 0 && column < row.length ? row[column].trim() : '';
    final name = value(nameColumn),
        number = value(numberColumn),
        className = value(classColumn);
    final conflict =
        keys.contains(key(name, number, className)) ||
        (number.isNotEmpty && numbers.contains(number));
    final candidates = byNumber[number] ?? [];
    final sameName =
        byNameClass[jsonEncode([
          name.toLowerCase(),
          className.toLowerCase(),
        ])] ??
        [];
    if (name.isNotEmpty &&
        updateMatches &&
        number.isNotEmpty &&
        numberCounts[number] == 1 &&
        candidates.length == 1 &&
        candidates.single.graduatedAt == null &&
        sameName.every((s) => s.id == candidates.single.id) &&
        !keys.contains(key(name, number, className))) {
      final before = candidates.single;
      beforeUpdates.add(before);
      afterUpdates.add(
        Student(
          id: before.id,
          name: name,
          number: number,
          className: classColumn < 0 ? before.className : className,
        ),
      );
      continue;
    }
    if (name.isEmpty || conflict) {
      issues.add(
        'Kayıt $line: ${name.isEmpty ? 'ad eksik' : 'eşleşen kayıt veya okul numarası'}${name.isEmpty ? '' : ' · $name${number.isEmpty ? '' : ' ($number)'}'}',
      );
      continue;
    }
    added.add(
      Student(
        id: newStudentId(),
        name: name,
        number: number,
        className: className,
      ),
    );
    keys.add(key(name, number, className));
    if (number.isNotEmpty) numbers.add(number);
  }
  return StudentCsvPreview(
    added,
    issues,
    beforeUpdates: beforeUpdates,
    afterUpdates: afterUpdates,
  );
}
