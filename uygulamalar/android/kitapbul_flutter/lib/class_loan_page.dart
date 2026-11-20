import 'package:flutter/material.dart';
import 'catalog_search.dart';
import 'class_loan.dart';
import 'loan_model.dart';
import 'loan_settings.dart';
import 'student_store.dart';

class ClassLoanPage extends StatefulWidget {
  const ClassLoanPage({
    super.key,
    required this.books,
    required this.students,
    required this.settings,
    required this.save,
  });
  final List<Map<String, dynamic>> books;
  final List<Student> students;
  final LoanSettings settings;
  final Future<bool> Function(List<Map<String, dynamic>>) save;
  @override
  State<ClassLoanPage> createState() => _ClassLoanPageState();
}

class _ClassLoanPageState extends State<ClassLoanPage> {
  late List<Map<String, dynamic>> books = widget.books;
  String? className, bookId;
  String query = '';
  final selected = <String>{};
  bool saving = false;
  Future<void> lend() async {
    if (saving || bookId == null || selected.isEmpty) return;
    final pupils = widget.students
        .where(
          (s) =>
              s.graduatedAt == null &&
              s.className == className &&
              selected.contains(s.id),
        )
        .toList();
    setState(() => saving = true);
    try {
      final result = prepareClassLoans(books, bookId!, pupils, widget.settings);
      if (result.lent.isNotEmpty) {
        final ok = await widget.save(result.books);
        if (!ok)
          throw StateError('Kayıt kaydedilemedi; hiçbir ödünç uygulanmadı.');
        books = result.books;
      }
      if (!mounted) return;
      setState(() {
        saving = false;
        selected.clear();
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Toplu ödünç sonucu'),
          content: SingleChildScrollView(
            child: Text(
              '${result.lent.length} öğrenciye ödünç verildi.${result.skipped.isEmpty ? '' : '\n\nZaten elinde olanlar:\n${result.skipped.join('\n')}'}${result.failures.isEmpty ? '' : '\n\nVerilemeyenler:\n${result.failures.join('\n')}'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes =
        widget.students
            .where((s) => s.graduatedAt == null && s.className.isNotEmpty)
            .map((s) => s.className)
            .toSet()
            .toList()
          ..sort();
    final pupils = widget.students
        .where((s) => s.graduatedAt == null && s.className == className)
        .toList();
    final choices = query.trim().isEmpty
        ? <Map<String, dynamic>>[]
        : books
              .where((b) => b['deletedAt'] == null && matchesCatalog(b, query))
              .take(8)
              .toList();
    final chosen = books.where((b) => b['id'] == bookId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Sınıfa toplu ödünç')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (classes.isEmpty)
            const Text('Önce öğrenci ve sınıf kaydı ekleyin.'),
          DropdownButtonFormField<String>(
            initialValue: className,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sınıf'),
            items: classes
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: saving
                ? null
                : (v) => setState(() {
                    className = v;
                    selected.clear();
                  }),
          ),
          if (pupils.isNotEmpty) ...[
            Text(
              'Öğrenciler (${selected.length}/${pupils.length} seçili)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () => setState(() {
                      if (selected.length == pupils.length) {
                        selected.clear();
                      } else {
                        selected.addAll(pupils.map((s) => s.id));
                      }
                    }),
              child: Text(
                selected.length == pupils.length
                    ? 'Seçimi kaldır'
                    : 'Tümünü seç',
              ),
            ),
            for (final student in pupils)
              CheckboxListTile(
                title: Text(student.name),
                subtitle: Text(
                  [
                    student.number,
                    if (chosen != null &&
                        hasDuplicateBorrower(chosen, {
                          'name': student.name,
                          'studentClass': student.className,
                          'studentId': student.id,
                        }))
                      'Kitap elinde',
                  ].where((x) => x.isNotEmpty).join(' · '),
                ),
                value: selected.contains(student.id),
                onChanged: saving
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          selected.add(student.id);
                        } else {
                          selected.remove(student.id);
                        }
                      }),
              ),
          ],
          TextField(
            decoration: const InputDecoration(
              labelText: 'Kitap adı veya ISBN ara',
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          for (final book in choices)
            ListTile(
              title: Text(book['title'].toString()),
              subtitle: Text('${availableCopies(book)} uygun nüsha'),
              trailing: book['id'] == bookId ? const Icon(Icons.check) : null,
              onTap: saving
                  ? null
                  : () => setState(() => bookId = book['id'] as String),
            ),
          if (chosen != null)
            Text(
              'Seçili: ${chosen['title']} · ${availableCopies(chosen)} uygun nüsha · ${selected.length} öğrenci',
            ),
          FilledButton.icon(
            onPressed: saving || selected.isEmpty || chosen == null
                ? null
                : lend,
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Seçili öğrencilere ödünç ver'),
          ),
        ],
      ),
    );
  }
}
