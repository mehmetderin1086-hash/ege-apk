import 'textbook_report_page.dart';
import 'package:flutter/material.dart';
import 'student_store.dart';
import 'loan_model.dart';
import 'textbook_distribution.dart';

class TextbookPage extends StatefulWidget {
  const TextbookPage({
    super.key,
    required this.books,
    required this.students,
    required this.save,
  });
  final List<Map<String, dynamic>> books;
  final List<Student> students;
  final Future<bool> Function(List<Map<String, dynamic>>) save;
  @override
  State<TextbookPage> createState() => _TextbookPageState();
}

class _TextbookPageState extends State<TextbookPage> {
  late List<Map<String, dynamic>> books = widget.books;
  String? bookId, className;
  final period = TextEditingController();
  DateTime due = DateTime(
    DateTime.now().year + (DateTime.now().month >= 9 ? 1 : 0),
    6,
    30,
  );
  bool saving = false;
  final selectedReturns = <String>{};
  final returnConditions = <String, String?>{};
  @override
  void dispose() {
    period.dispose();
    super.dispose();
  }

  Future<void> change(
    Map<String, dynamic> Function(Map<String, dynamic>) action,
  ) async {
    if (saving) return;
    try {
      final current = books.firstWhere((b) => b['id'] == bookId);
      final updated = action(current);
      final next = books.map((b) => b['id'] == bookId ? updated : b).toList();
      setState(() => saving = true);
      final saved = await widget.save(next);
      if (!mounted) return;
      if (!saved) throw StateError('Kayıt kaydedilemedi');
      setState(() {
        books = next;
        selectedReturns.clear();
        returnConditions.clear();
        saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem kaydedildi.')));
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
    final textbooks = books
        .where(
          (b) =>
              b['deletedAt'] == null &&
              (b['isTextbook'] == true ||
                  activeLoans(b).any((loan) => loan['kind'] == 'textbook')),
        )
        .toList();
    final classes = <String>{
      ...widget.students
          .where((s) => s.graduatedAt == null && s.className.isNotEmpty)
          .map((s) => s.className),
      for (final book in textbooks)
        for (final loan in activeLoans(book))
          if (loan['kind'] == 'textbook' &&
              loan['studentClass'] is String &&
              (loan['studentClass'] as String).isNotEmpty)
            loan['studentClass'] as String,
    }.toList()..sort();
    final selected = textbooks.where((b) => b['id'] == bookId).firstOrNull;
    final pupils = widget.students
        .where((s) => s.graduatedAt == null && s.className == className)
        .toList();
    final loans = selected == null
        ? <Map<String, dynamic>>[]
        : activeLoans(selected)
              .where(
                (l) =>
                    l['kind'] == 'textbook' && l['studentClass'] == className,
              )
              .toList();
    bool assigned(Student s) =>
        selected != null &&
        activeLoans(selected).any(
          (l) =>
              l['kind'] == 'textbook' &&
              l['memberId'] == null &&
              ((l['studentId'] is String &&
                      (l['studentId'] as String).toUpperCase() ==
                          s.id.toUpperCase()) ||
                  (l['studentId'] == null &&
                      l['identitySource'] != 'manual' &&
                      l['name'] == s.name &&
                      l['studentClass'] == s.className)),
        );
    final missing = pupils.where((s) => !assigned(s)).toList();
    final schoolYear = DateTime.now().month >= 9
        ? DateTime.now().year
        : DateTime.now().year - 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Ders kitabı dağıtımı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TextbookReportPage(books: books),
              ),
            ),
            icon: const Icon(Icons.assessment_outlined),
            label: const Text('Ders kitabı çizelgesi'),
          ),
          if (textbooks.isEmpty)
            const Text(
              'Kitap düzenleme ekranında bir kitabı ders kitabı olarak işaretleyin.',
            ),
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
                    selectedReturns.clear();
                    returnConditions.clear();
                  }),
          ),
          DropdownButtonFormField<String>(
            initialValue: bookId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ders kitabı'),
            items: textbooks
                .map(
                  (b) => DropdownMenuItem(
                    value: b['id'] as String,
                    child: Text(
                      b['title'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: saving
                ? null
                : (v) => setState(() {
                    bookId = v;
                    selectedReturns.clear();
                    returnConditions.clear();
                  }),
          ),
          TextField(
            controller: period,
            decoration: InputDecoration(
              labelText: 'Dönem',
              hintText: '$schoolYear–${schoolYear + 1}',
            ),
          ),
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: due,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null && mounted) setState(() => due = d);
                  },
            child: Text('Teslim tarihi: ${due.day}.${due.month}.${due.year}'),
          ),
          if (selected != null && className != null) ...[
            Text(
              'Dağıtılmış: ${loans.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final loan in loans)
              ListTile(
                title: Text(loan['name'].toString()),
                subtitle: Text(
                  '${loan['periodSnapshot'] ?? 'Dönem belirtilmemiş'} · ${loan['due']?.toString().split('T').first ?? ''}',
                ),
                trailing: TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final condition = await showDialog<String>(
                            context: context,
                            builder: (ctx) => SimpleDialog(
                              title: const Text('Teslim durumu'),
                              children: [
                                for (final c in [
                                  'Belirtilmedi',
                                  'Yeni',
                                  'İyi',
                                  'Yıpranmış',
                                  'Onarım gerekli',
                                ])
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(ctx, c),
                                    child: Text(c),
                                  ),
                              ],
                            ),
                          );
                          if (condition != null)
                            await change(
                              (book) => collectTextbooks(book, {
                                loan['id']
                                    as String: condition == 'Belirtilmedi'
                                    ? null
                                    : condition,
                              }),
                            );
                        },
                  child: const Text('Teslim al'),
                ),
              ),
            if (loans.isNotEmpty) ...[
              const Text(
                'Toplu teslim için öğrencileri seçin; seçilmeyen kitaplar ödünçte kalır.',
              ),
              for (final loan in loans)
                Column(
                  children: [
                    CheckboxListTile(
                      title: Text(loan['name'].toString()),
                      value: selectedReturns.contains(loan['id']),
                      onChanged: saving
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                selectedReturns.add(loan['id'] as String);
                              } else {
                                selectedReturns.remove(loan['id']);
                              }
                            }),
                    ),
                    if (selectedReturns.contains(loan['id']))
                      DropdownButtonFormField<String>(
                        initialValue:
                            returnConditions[loan['id']] ?? 'Belirtilmedi',
                        decoration: InputDecoration(
                          labelText: '${loan['name']} · Teslim durumu',
                        ),
                        items: [
                          for (final condition in [
                            'Belirtilmedi',
                            'Yeni',
                            'İyi',
                            'Yıpranmış',
                            'Onarım gerekli',
                          ])
                            DropdownMenuItem(
                              value: condition,
                              child: Text(condition),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setState(
                                () =>
                                    returnConditions[loan['id'] as String] = v,
                              ),
                      ),
                  ],
                ),
              TextButton(
                onPressed: saving
                    ? null
                    : () => setState(
                        () => selectedReturns.addAll(
                          loans.map((loan) => loan['id'] as String),
                        ),
                      ),
                child: const Text('Tüm teslimleri seç'),
              ),
              FilledButton(
                onPressed: saving || selectedReturns.isEmpty
                    ? null
                    : () async {
                        final count = selectedReturns.length;
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Teslimleri kaydet'),
                            content: Text(
                              '$count ders kitabı seçilen durumlarla teslim alınsın mı?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Vazgeç'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Teslimleri kaydet'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted)
                          await change(
                            (book) => collectTextbooks(book, {
                              for (final id in selectedReturns)
                                id: returnConditions[id] == 'Belirtilmedi'
                                    ? null
                                    : returnConditions[id],
                            }),
                          );
                      },
                child: Text(
                  'Seçili ${selectedReturns.length} kitabı teslim al',
                ),
              ),
            ],
            Text(
              'Dağıtılmamış: ${missing.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final s in missing)
              ListTile(
                title: Text(s.name),
                subtitle: Text(s.number),
                trailing: TextButton(
                  onPressed: saving
                      ? null
                      : () => change(
                          (book) => distributeTextbooks(
                            book,
                            [s],
                            due: due,
                            period: period.text.trim().isEmpty
                                ? '$schoolYear–${schoolYear + 1}'
                                : period.text,
                          ),
                        ),
                  child: const Text('Ver'),
                ),
              ),
            if (missing.isNotEmpty)
              FilledButton(
                onPressed: saving
                    ? null
                    : () => change(
                        (book) => distributeTextbooks(
                          book,
                          missing,
                          due: due,
                          period: period.text.trim().isEmpty
                              ? '$schoolYear–${schoolYear + 1}'
                              : period.text,
                        ),
                      ),
                child: const Text('Tümüne dağıt'),
              ),
          ],
        ],
      ),
    );
  }
}
