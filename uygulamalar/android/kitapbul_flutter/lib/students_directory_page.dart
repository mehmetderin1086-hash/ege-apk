import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'book_visuals.dart';
import 'catalog_search.dart';
import 'loan_model.dart';
import 'member_management.dart';
import 'member_store.dart';
import 'reservation_model.dart';
import 'student_csv.dart';
import 'student_profile_page.dart';
import 'student_store.dart';

enum _StudentFilterMode { all, withLoans, overdue }

/// Pure helper summarizing active loan and overdue counts per student ID.
Map<String, ({int loans, int overdue})> studentLoanCounts(
  List<Map<String, dynamic>> books, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final counts = <String, ({int loans, int overdue})>{};
  for (final book in books) {
    if (book['deletedAt'] != null) continue;
    for (final loan in activeLoans(book)) {
      if (loan['memberId'] != null) continue;
      final sid = (loan['studentId'] ?? '').toString().trim().toUpperCase();
      if (sid.isEmpty) continue;
      final prev = counts[sid] ?? (loans: 0, overdue: 0);
      counts[sid] = (
        loans: prev.loans + 1,
        overdue: prev.overdue + (isOverdue(loan, now: current) ? 1 : 0),
      );
    }
  }
  return counts;
}

/// Searchable, filterable full-screen directory for managing students and members.
class StudentsDirectoryPage extends StatefulWidget {
  const StudentsDirectoryPage({
    super.key,
    required this.initialStudents,
    required this.initialMembers,
    required this.initialBooks,
    required this.onPersist,
    required this.onImportCsv,
    required this.onUndoImport,
    required this.onPromote,
    required this.onShowGraduates,
    required this.readLatestState,
  });

  final List<Student> initialStudents;
  final List<Member> initialMembers;
  final List<Map<String, dynamic>> initialBooks;
  final Future<bool> Function(
    List<Map<String, dynamic>> books,
    List<Student> students,
    List<Member> members,
  )
  onPersist;
  final Future<void> Function() onImportCsv;
  final Future<void> Function() onUndoImport;
  final Future<void> Function() onPromote;
  final Future<void> Function() onShowGraduates;
  final ({
    List<Map<String, dynamic>> books,
    List<Student> students,
    List<Member> members,
  })
  Function()
  readLatestState;

  @override
  State<StudentsDirectoryPage> createState() => _StudentsDirectoryPageState();
}

class _StudentsDirectoryPageState extends State<StudentsDirectoryPage> {
  late List<Student> _students;
  late List<Member> _members;
  late List<Map<String, dynamic>> _books;
  String _query = '';
  String? _classFilter;
  _StudentFilterMode _mode = _StudentFilterMode.all;

  @override
  void initState() {
    super.initState();
    _students = [...widget.initialStudents];
    _members = [...widget.initialMembers];
    _books = [...widget.initialBooks];
  }

  void _syncFromParent() {
    final latest = widget.readLatestState();
    if (!mounted) return;
    setState(() {
      _books = [...latest.books];
      _students = [...latest.students];
      _members = [...latest.members];
    });
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Future<void> _addStudent() async {
    var name = '';
    var number = '';
    var className = '';
    final created = await showDialog<Student>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Öğrenci ekle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                onChanged: (v) => name = v,
                decoration: const InputDecoration(
                  labelText: 'Ad soyad *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => number = v,
                decoration: const InputDecoration(
                  labelText: 'Okul numarası',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => className = v,
                decoration: const InputDecoration(
                  labelText: 'Sınıf',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) {
                Navigator.pop(
                  ctx,
                  Student(
                    id: newStudentId(),
                    name: name.trim(),
                    number: number.trim(),
                    className: className.trim(),
                  ),
                );
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (created == null || !mounted) return;
    if (_students.any(
      (s) =>
          s.name.toLowerCase() == created.name.toLowerCase() &&
          s.number == created.number &&
          s.className == created.className,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu öğrenci zaten kayıtlı.')),
      );
      return;
    }
    final nextStudents = [..._students, created];
    final ok = await widget.onPersist(_books, nextStudents, _members);
    if (ok && mounted) {
      setState(() => _students = nextStudents);
    }
  }

  Future<void> _editStudent(Student student) async {
    var name = student.name;
    var number = student.number;
    var className = student.className;
    final edited = await showDialog<Student>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Öğrenciyi düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: name,
                onChanged: (v) => name = v,
                decoration: const InputDecoration(
                  labelText: 'Ad soyad *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: number,
                onChanged: (v) => number = v,
                decoration: const InputDecoration(
                  labelText: 'Okul numarası',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: className,
                onChanged: (v) => className = v,
                decoration: const InputDecoration(
                  labelText: 'Sınıf',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) {
                Navigator.pop(
                  ctx,
                  Student(
                    id: student.id,
                    name: name.trim(),
                    number: number.trim(),
                    className: className.trim(),
                  ),
                );
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (edited == null || !mounted) return;
    if (_students.any(
      (s) =>
          s.id != edited.id &&
          s.name.toLowerCase() == edited.name.toLowerCase() &&
          s.number == edited.number &&
          s.className == edited.className,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu öğrenci zaten kayıtlı.')),
      );
      return;
    }
    final nextStudents = _students
        .map((s) => s.id == edited.id ? edited : s)
        .toList();
    final nextBooks = syncStudentLoans(_books, [edited]);
    final ok = await widget.onPersist(nextBooks, nextStudents, _members);
    if (ok && mounted) {
      setState(() {
        _students = nextStudents;
        _books = nextBooks;
      });
    }
  }

  Future<void> _deleteStudent(Student student) async {
    final inUse = _books.any(
      (book) => activeLoans(book).any((loan) => loan['studentId'] == student.id),
    );
    if (inUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Öğrencinin etkin ödüncü var.')),
      );
      return;
    }
    if (_books.any(
      (book) => reservationsOf(book).any(
        (r) => isActiveReservation(r) && r['studentId'] == student.id,
      ),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Öğrencinin açık rezervasyonu var.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Öğrenci silinsin mi?'),
        content: Text(student.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final nextStudents = _students.where((s) => s.id != student.id).toList();
    final ok = await widget.onPersist(_books, nextStudents, _members);
    if (ok && mounted) {
      setState(() => _students = nextStudents);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeStudents = _students
        .where((s) => s.graduatedAt == null)
        .toList()
      ..sort((a, b) => foldTurkish(a.name).compareTo(foldTurkish(b.name)));
    final loanStats = studentLoanCounts(_books);
    final classes = activeStudents
        .map((s) => s.className.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => foldTurkish(a).compareTo(foldTurkish(b)));

    final withLoansCount = activeStudents
        .where((s) => (loanStats[s.id.toUpperCase()]?.loans ?? 0) > 0)
        .length;
    final overdueCount = activeStudents
        .where((s) => (loanStats[s.id.toUpperCase()]?.overdue ?? 0) > 0)
        .length;

    final filtered = activeStudents.where((s) {
      final stat = loanStats[s.id.toUpperCase()] ?? (loans: 0, overdue: 0);
      if (_mode == _StudentFilterMode.withLoans && stat.loans == 0) {
        return false;
      }
      if (_mode == _StudentFilterMode.overdue && stat.overdue == 0) {
        return false;
      }
      if (_classFilter != null && s.className.trim() != _classFilter) {
        return false;
      }
      if (_query.trim().isNotEmpty) {
        final q = foldTurkish(_query.trim());
        if (!foldTurkish(s.name).contains(q) &&
            !foldTurkish(s.number).contains(q) &&
            !foldTurkish(s.className).contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Öğrenciler (${activeStudents.length})'),
        actions: [
          IconButton(
            tooltip: 'Üyeler (Öğretmen / Personel)',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemberManagementPage(
                    initialMembers: _members,
                    books: _books,
                    save: (updated) async {
                      final ok = await widget.onPersist(
                        _books,
                        _students,
                        updated,
                      );
                      if (ok && mounted) {
                        setState(() => _members = [...updated]);
                      }
                      return ok;
                    },
                  ),
                ),
              );
              _syncFromParent();
            },
            icon: const Icon(Icons.badge_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'csv_import':
                  await widget.onImportCsv();
                  _syncFromParent();
                case 'undo_import':
                  await widget.onUndoImport();
                  _syncFromParent();
                case 'promote':
                  await widget.onPromote();
                  _syncFromParent();
                case 'graduates':
                  await widget.onShowGraduates();
                  _syncFromParent();
                case 'copy_list':
                  final lines = [
                    'Ad Soyad;Sınıf;Numara',
                    for (final s in filtered)
                      '${s.name};${s.className};${s.number}',
                  ].join('\n');
                  await Clipboard.setData(ClipboardData(text: lines));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${filtered.length} öğrenci listesi panoya kopyalandı.',
                        ),
                      ),
                    );
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'csv_import',
                child: Text('CSV İle Öğrenci Yükle'),
              ),
              PopupMenuItem(
                value: 'undo_import',
                child: Text('Son Aktarımı Geri Al'),
              ),
              PopupMenuItem(value: 'promote', child: Text('Sınıf Atlat')),
              PopupMenuItem(value: 'graduates', child: Text('Mezunlar')),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'copy_list',
                child: Text('Filtreli Listeyi Kopyala'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStudent,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Öğrenci Ekle'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Ad, okul no veya sınıf ara...',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('Tümü (${activeStudents.length})'),
                  selected: _mode == _StudentFilterMode.all,
                  onSelected: (_) =>
                      setState(() => _mode = _StudentFilterMode.all),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('Kitabı Olan ($withLoansCount)'),
                  selected: _mode == _StudentFilterMode.withLoans,
                  onSelected: (_) =>
                      setState(() => _mode = _StudentFilterMode.withLoans),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('Geciken ($overdueCount)'),
                  avatar: overdueCount > 0
                      ? Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: scheme.error,
                        )
                      : null,
                  selected: _mode == _StudentFilterMode.overdue,
                  onSelected: (_) =>
                      setState(() => _mode = _StudentFilterMode.overdue),
                ),
                if (classes.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<String?>(
                    onSelected: (v) => setState(() => _classFilter = v),
                    itemBuilder: (_) => [
                      const PopupMenuItem<String?>(
                        value: null,
                        child: Text('Tüm Sınıflar'),
                      ),
                      for (final c in classes)
                        PopupMenuItem<String?>(value: c, child: Text(c)),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.class_outlined, size: 16),
                      label: Text(_classFilter ?? 'Tüm Sınıflar'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('Filtrelere uygun öğrenci kaydı bulunamadı.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
                    itemCount: filtered.length,
                    itemBuilder: (_, idx) {
                      final s = filtered[idx];
                      final stat =
                          loanStats[s.id.toUpperCase()] ??
                          (loans: 0, overdue: 0);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: stat.overdue > 0
                                ? scheme.errorContainer
                                : scheme.primaryContainer,
                            child: Text(
                              _initials(s.name),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: stat.overdue > 0
                                    ? scheme.onErrorContainer
                                    : scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          title: Text(
                            s.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  if (s.className.isNotEmpty) s.className,
                                  if (s.number.isNotEmpty) 'No: ${s.number}',
                                ].join(' · '),
                              ),
                              if (stat.loans > 0) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    CompactStatChip(
                                      icon: Icons.menu_book_rounded,
                                      label: '${stat.loans} ödünç',
                                      color: scheme.primary,
                                    ),
                                    if (stat.overdue > 0)
                                      CompactStatChip(
                                        icon: Icons.warning_amber_rounded,
                                        label: '${stat.overdue} gecikmiş',
                                        color: scheme.error,
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StudentProfilePage(
                                student: s,
                                books: _books,
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Düzenle',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _editStudent(s),
                              ),
                              IconButton(
                                tooltip: 'Sil',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                onPressed: () => _deleteStudent(s),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
