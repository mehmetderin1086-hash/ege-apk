import 'dart:convert';
import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'student_card.dart';
import 'student_store.dart';

List<Map<String, dynamic>> studentCardsData(
  List<Student> students, {
  bool showName = true,
  bool showClass = true,
  bool showNumber = true,
}) {
  final result = <Map<String, dynamic>>[];
  for (final student in students.where((s) => s.graduatedAt == null)) {
    final code = studentCardCode(student);
    final bars = Barcode.code128()
        .make(code, width: 1, height: 1)
        .whereType<BarcodeBar>()
        .where((bar) => bar.black)
        .map((bar) => [bar.left, bar.width])
        .toList();
    final displayedName = showName
        ? student.name
        : student.name
              .trim()
              .split(RegExp(r'\s+'))
              .where((s) => s.isNotEmpty)
              .map((s) => '${String.fromCharCode(s.runes.first)}.')
              .join(' ');
    result.add({
      'name': displayedName,
      'className': showClass ? student.className : '',
      'number': showNumber ? student.number : '',
      'bars': bars,
    });
  }
  return result;
}

class StudentCardsPage extends StatefulWidget {
  const StudentCardsPage({super.key, required this.students});
  final List<Student> students;
  @override
  State<StudentCardsPage> createState() => _StudentCardsPageState();
}

class _StudentCardsPageState extends State<StudentCardsPage> {
  String selectedClass = '';
  bool showName = true, showClass = true, showNumber = true, saving = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.students.where((s) => s.graduatedAt == null).toList();
    final classes =
        active
            .map((s) => s.className)
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final students = active
        .where((s) => selectedClass.isEmpty || s.className == selectedClass)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Öğrenci kartları')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: selectedClass,
            decoration: const InputDecoration(labelText: 'Sınıf'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tüm sınıflar')),
              for (final c in classes)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: saving
                ? null
                : (v) => setState(() => selectedClass = v ?? ''),
          ),
          Text('${students.length} kart · A4 sayfada 2 sütun, 5 satır'),
          SwitchListTile(
            title: const Text('Öğrenci adını göster'),
            value: showName,
            onChanged: saving ? null : (v) => setState(() => showName = v),
          ),
          SwitchListTile(
            title: const Text('Sınıfı göster'),
            value: showClass,
            onChanged: saving ? null : (v) => setState(() => showClass = v),
          ),
          SwitchListTile(
            title: const Text('Okul numarasını göster'),
            value: showNumber,
            onChanged: saving ? null : (v) => setState(() => showNumber = v),
          ),
          const Text(
            'Kart barkodu öğrencinin sabit kimliğini taşır. Ad gizlendiğinde baş harfleri gösterilir.',
          ),
          FilledButton.icon(
            onPressed: saving || students.isEmpty
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      final payload = jsonEncode(
                        studentCardsData(
                          students,
                          showName: showName,
                          showClass: showClass,
                          showNumber: showNumber,
                        ),
                      );
                      final ok = await const MethodChannel('kitapbul/files')
                          .invokeMethod<bool>('exportStudentCardsPdf', {
                            'data': payload,
                            'filename': 'OgrenciKartlari.pdf',
                          });
                      if (mounted && ok == true)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Öğrenci kartları kaydedildi.'),
                          ),
                        );
                    } catch (_) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Öğrenci kartları kaydedilemedi.'),
                          ),
                        );
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Kartları PDF kaydet'),
          ),
          for (final student in students.take(50))
            ListTile(
              title: Text(
                showName
                    ? student.name
                    : student.name
                          .trim()
                          .split(RegExp(r'\s+'))
                          .where((s) => s.isNotEmpty)
                          .map((s) => '${String.fromCharCode(s.runes.first)}.')
                          .join(' '),
              ),
              subtitle: Text(
                [
                  if (showClass) student.className,
                  if (showNumber && student.number.isNotEmpty)
                    'No: ${student.number}',
                ].where((v) => v.isNotEmpty).join(' · '),
              ),
            ),
          if (students.length > 50)
            Text(
              '… ve ${students.length - 50} öğrenci daha (PDF’de tamamı yer alır).',
            ),
          if (students.isEmpty) const Text('Bu sınıfta öğrenci yok.'),
        ],
      ),
    );
  }
}
