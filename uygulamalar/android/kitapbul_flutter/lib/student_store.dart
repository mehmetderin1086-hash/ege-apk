import 'dart:convert';
import 'dart:io';
import 'dart:math';

String newStudentId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// A student's identifier remains stable even when their name or class changes.
class Student {
  const Student({
    required this.id,
    required this.name,
    this.number = '',
    this.className = '',
    this.graduatedAt,
  });
  final String id;
  final String name;
  final String number;
  final String className;
  final String? graduatedAt;

  factory Student.fromJson(dynamic value) {
    if (value is! Map ||
        value['id'] is! String ||
        (value['id'] as String).trim().isEmpty ||
        value['name'] is! String ||
        (value['name'] as String).trim().isEmpty ||
        value['number'] is! String ||
        value['className'] is! String ||
        (value['graduatedAt'] != null &&
            (value['graduatedAt'] is! String ||
                DateTime.tryParse(value['graduatedAt'] as String) == null))) {
      throw const FormatException('Geçersiz öğrenci kaydı');
    }
    return Student(
      id: value['id'] as String,
      name: value['name'] as String,
      number: value['number'] as String,
      className: value['className'] as String,
      graduatedAt: value['graduatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'number': number,
    'className': className,
    if (graduatedAt != null) 'graduatedAt': graduatedAt,
  };
}

List<Student> decodeStudents(String source) {
  final data = jsonDecode(source);
  if (data is! List) throw const FormatException('Öğrenci listesi geçersiz');
  final ids = <String>{};
  final students = <Student>[];
  for (final value in data) {
    final student = Student.fromJson(value);
    if (!ids.add(student.id))
      throw const FormatException('Tekrarlanan öğrenci kimliği');
    students.add(student);
  }
  return students;
}

/// Protects an unreadable roster and retains the previous valid file on writes.
class StudentStore {
  StudentStore(this.directory);
  final Directory directory;
  File get current => File('${directory.path}/students.json');
  File get backup => File('${directory.path}/students.backup.json');

  Future<List<Student>> load() async => await current.exists()
      ? decodeStudents(await current.readAsString())
      : [];

  Future<void> save(List<Student> students) async {
    final data = jsonEncode(
      students.map((student) => student.toJson()).toList(),
    );
    decodeStudents(data);
    if (await current.exists()) {
      final previous = await current.readAsString();
      decodeStudents(previous);
      final tempBackup = File('${directory.path}/students.backup.tmp');
      await tempBackup.writeAsString(previous, flush: true);
      await tempBackup.rename(backup.path);
    }
    final temp = File('${directory.path}/students.tmp');
    await temp.writeAsString(data, flush: true);
    await temp.rename(current.path);
  }
}
