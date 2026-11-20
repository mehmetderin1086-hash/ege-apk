import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'student_store.dart';

/// iPhone UUID cards are shared verbatim; older Android IDs use a separate,
/// deterministic namespace so existing roster and loan identities remain intact.
String studentCardCode(Student student) {
  final compact = student.id.replaceAll('-', '');
  if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact))
    return 'OGRID${compact.toUpperCase()}';
  if (student.id.isEmpty)
    throw const FormatException('Öğrenci kimliği kart için uygun değil');
  return 'OGRA${sha256.convert(utf8.encode(student.id)).toString().substring(0, 32).toUpperCase()}';
}

Student resolveStudentCard(String value, List<Student> students) {
  final code = value.trim().toUpperCase();
  final active = students.where((s) => s.graduatedAt == null).toList();
  List<Student> matches;
  if (code.startsWith('OGRID')) {
    final id = code.substring(5);
    if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(id))
      throw const FormatException('Kartın öğrenci kimliği geçersiz');
    matches = active
        .where((s) => s.id.replaceAll('-', '').toUpperCase() == id)
        .toList();
  } else if (code.startsWith('OGRA')) {
    final digest = code.substring(4);
    if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(digest))
      throw const FormatException('Kartın öğrenci kimliği geçersiz');
    matches = active
        .where(
          (s) =>
              sha256
                  .convert(utf8.encode(s.id))
                  .toString()
                  .substring(0, 32)
                  .toUpperCase() ==
              digest,
        )
        .toList();
  } else if (code.startsWith('OGRKB')) {
    final hex = code.substring(5);
    if (hex.isEmpty ||
        hex.length > 200 ||
        hex.length.isOdd ||
        !RegExp(r'^[0-9A-F]+$').hasMatch(hex))
      throw const FormatException('Kartın öğrenci kimliği geçersiz');
    String id;
    try {
      id = utf8.decode([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
    } catch (_) {
      throw const FormatException('Kartın öğrenci kimliği geçersiz');
    }
    matches = active.where((s) => s.id == id).toList();
  } else if (code.startsWith('OGR')) {
    final number = code.substring(3);
    if (!RegExp(r'^\d+$').hasMatch(number))
      throw const FormatException('Eski kartın okul numarası geçersiz');
    matches = active
        .where((s) => s.number.replaceAll(RegExp(r'\D'), '') == number)
        .toList();
  } else {
    throw const FormatException('Öğrenci kartı tanınmadı');
  }
  if (matches.isEmpty)
    throw const FormatException('Bu kartın aktif öğrenci kaydı bulunamadı');
  if (matches.length != 1)
    throw const FormatException(
      'Kart birden çok öğrenciyle eşleşiyor; kimlikli kart kullanın',
    );
  return matches.single;
}
