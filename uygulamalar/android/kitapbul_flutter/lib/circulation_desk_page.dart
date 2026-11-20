import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_settings.dart';
import 'book_visuals.dart';
import 'catalog_search.dart';
import 'catalog_views.dart';
import 'isbn.dart';
import 'isbn_scanner.dart';
import 'library_labels_page.dart';
import 'loan_model.dart';
import 'loan_settings.dart';
import 'member_store.dart';
import 'school_duty_roster.dart';
import 'student_card.dart';
import 'student_store.dart';

/// Barkod, QR (`KITAP:<id>|...`), demirbaş (`CAL-001781`) veya ISBN ile kitabı bulur.
Map<String, dynamic>? findBookByDeskCode(
  List<Map<String, dynamic>> books,
  String rawInput,
) {
  final input = rawInput.trim();
  if (input.isEmpty) return null;
  final active = books.where((b) => b['deletedAt'] == null).toList();

  // 1. QR KITAP:<uuid>|DEM:...
  if (input.toUpperCase().startsWith('KITAP:')) {
    final firstPart = input.split('|').first.substring(6).trim().toUpperCase();
    for (final b in active) {
      if ((b['id'] ?? '').toString().toUpperCase() == firstPart) return b;
    }
  }

  // 2. Demirbaş kodu tam eşleşmesi (çoklu CAL-004057; CAL-004058 dahil)
  final upper = input.toUpperCase();
  for (final b in active) {
    final tokens = extractAccessionTokens(b);
    if (tokens.any((t) => t.toUpperCase() == upper)) return b;
    final copies = (b['copies'] as List?)?.whereType<Map>() ?? const [];
    if (copies.any(
      (c) => (c['accessionCode'] ?? '').toString().trim().toUpperCase() == upper,
    )) {
      return b;
    }
  }

  // 3. Kanonik ISBN eşleşmesi
  final canon = canonicalIsbn(input);
  if (canon != null) {
    for (final b in active) {
      if (canonicalIsbn((b['isbn'] ?? '').toString()) == canon) return b;
    }
  }

  // 4. Tekil başlık/demirbaş araması
  final matches = active.where((b) => matchesCatalog(b, input)).toList();
  if (matches.length == 1) return matches.first;
  return null;
}

class CirculationDeskView extends StatefulWidget {
  const CirculationDeskView({
    super.key,
    required this.books,
    required this.students,
    required this.loanSettings,
    required this.dutyRoster,
    required this.busy,
    required this.actions,
    required this.onSaveBooks,
    required this.onOpenDutyRoster,
    this.members = const [],
  });

  final List<Map<String, dynamic>> books;
  final List<Student> students;
  final List<Member> members;
  final LoanSettings loanSettings;
  final SchoolDutyRoster dutyRoster;
  final bool busy;
  final BookActionCallbacks actions;
  final Future<void> Function(List<Map<String, dynamic>> updated) onSaveBooks;
  final VoidCallback onOpenDutyRoster;

  @override
  State<CirculationDeskView> createState() => _CirculationDeskViewState();
}

class _CirculationDeskViewState extends State<CirculationDeskView> {
  Student? _selectedStudent;
  Member? _selectedMember;
  String? _selectedBookId;
  final TextEditingController _studentSearchCtrl = TextEditingController();
  final TextEditingController _bookSearchCtrl = TextEditingController();
  String _studentQuery = '';
  String _bookQuery = '';
  String _returnCondition = 'İyi';
  bool _readingCompleted = true;
  int _queueTab = 0; // 0: Gecikenler, 1: Yaklaşanlar, 2: Aktifler, 3: Son İşlemler

  @override
  void dispose() {
    _studentSearchCtrl.dispose();
    _bookSearchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _selectedBook {
    if (_selectedBookId == null) return null;
    for (final b in widget.books) {
      if (b['id'] == _selectedBookId && b['deletedAt'] == null) return b;
    }
    return null;
  }

  Future<void> _scanSmartCode({bool studentOnly = false}) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            IsbnScannerPage(isbnOnly: false, studentCard: studentOnly),
      ),
    );
    if (!mounted || code == null) return;
    final trimmed = code.trim();
    if (trimmed.toUpperCase().startsWith('OGR')) {
      try {
        final st = resolveStudentCard(trimmed, widget.students);
        HapticFeedback.mediumImpact();
        setState(() {
          _selectedStudent = st;
          _selectedMember = null;
          _studentQuery = '';
          _studentSearchCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Öğrenci seçildi: ${st.name} (${st.className})')),
        );
      } on FormatException catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }

    final found = findBookByDeskCode(widget.books, trimmed);
    if (found != null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _selectedBookId = found['id'] as String;
        _bookQuery = '';
        _bookSearchCtrl.clear();
      });
    } else {
      setState(() {
        _bookQuery = trimmed;
        _bookSearchCtrl.text = trimmed;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$trimmed" ile tam eşleşen kitap bulunamadı.'),
        ),
      );
    }
  }

  Future<void> _executeQuickLendForReader(Map<String, dynamic> book) async {
    final student = _selectedStudent;
    final member = _selectedMember;
    if (student == null && member == null) return;

    final borrower = student != null
        ? <String, dynamic>{
            'studentId': student.id,
            'name': student.name,
            'studentClass': student.className,
          }
        : <String, dynamic>{
            'memberId': member!.id,
            'name': member.name,
            'studentClass': member.kindTitle,
          };

    final violation = loanPolicyViolation(
      widget.books,
      borrower,
      widget.loanSettings,
      memberKind: member?.kind,
    );
    if (violation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(violation)));
      return;
    }

    final days = student != null
        ? widget.loanSettings.durationFor(student.className)
        : (widget.loanSettings.memberRuleFor(member!.kind)?.days ??
              widget.loanSettings.days);
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day).add(Duration(days: days));
    final loanId = 'desk-${now.microsecondsSinceEpoch}';
    final readerName = student?.name ?? member!.name;

    try {
      final updatedBook = addLoan(book, {
        'id': loanId,
        if (student != null) ...{
          'studentId': student.id,
          'name': student.name,
          'studentClass': student.className,
          'studentNumberSnapshot': student.number,
          'identitySource': 'student',
        } else ...{
          'memberId': member!.id,
          'name': member.name,
          'studentClass': member.kindTitle,
          if (member.kind != null) 'memberKind': member.kind,
          'identitySource': 'member',
        },
        'loanedAt': now.toIso8601String(),
        'due': due.toIso8601String(),
      });
      final updatedList = widget.books
          .map((b) => b['id'] == book['id'] ? updatedBook : b)
          .toList();
      await widget.onSaveBooks(updatedList);
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${book['title']}" → $readerName ($days gün ödünç verildi)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ödünç verilemedi: $e')));
      }
    }
  }

  Future<void> _executeQuickReturn(
    Map<String, dynamic> book,
    Map<String, dynamic> loan,
  ) async {
    try {
      final updatedBook = returnLoan(
        book,
        loan['id'] as String,
        returnedCondition: _returnCondition,
        readingCompleted: _readingCompleted,
      );
      final updatedList = widget.books
          .map((b) => b['id'] == book['id'] ? updatedBook : b)
          .toList();
      await widget.onSaveBooks(updatedList);
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${book['title']}" (${loan['name']}) iade alındı.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('İade alınamadı: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfg = appThemeNotifier.value;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final activeBooks = widget.books
        .where((b) => b['deletedAt'] == null)
        .toList();

    // Collect loan entries
    final allLoans = <({Map<String, dynamic> book, Map<String, dynamic> loan})>[];
    final overdueLoans =
        <({Map<String, dynamic> book, Map<String, dynamic> loan})>[];
    final dueSoonLoans =
        <({Map<String, dynamic> book, Map<String, dynamic> loan})>[];
    final recentEvents =
        <({Map<String, dynamic> book, Map<String, dynamic> event})>[];

    for (final b in activeBooks) {
      for (final l in activeLoans(b)) {
        final pair = (book: b, loan: l);
        allLoans.add(pair);
        if (isOverdue(l, now: now)) {
          overdueLoans.add(pair);
        } else {
          final due = DateTime.tryParse((l['due'] ?? '').toString());
          if (due != null) {
            final diff = DateTime(
              due.year,
              due.month,
              due.day,
            ).difference(todayStart).inDays;
            if (diff >= 0 && diff <= 3) dueSoonLoans.add(pair);
          }
        }
      }
      for (final ev in loanHistory(b)) {
        recentEvents.add((book: b, event: ev));
      }
    }

    recentEvents.sort(
      (a, b) => ((b.event['date'] ?? '') as String).compareTo(
        (a.event['date'] ?? '') as String,
      ),
    );

    final todayDuty = widget.dutyRoster.forWeekday(now.weekday.clamp(1, 5));
    final activeStudents = widget.students
        .where((s) => s.graduatedAt == null)
        .toList();

    final matchingStudents = _studentQuery.trim().isEmpty
        ? const <Student>[]
        : activeStudents
              .where(
                (s) => foldTurkish(
                  '${s.name} ${s.number} ${s.className}',
                ).contains(foldTurkish(_studentQuery)),
              )
              .take(6)
              .toList();

    final matchingMembers = _studentQuery.trim().isEmpty
        ? const <Member>[]
        : widget.members
              .where(
                (m) => foldTurkish(
                  '${m.name} ${m.number} ${m.kindTitle}',
                ).contains(foldTurkish(_studentQuery)),
              )
              .take(4)
              .toList();

    final matchingBooks = _bookQuery.trim().isEmpty
        ? const <Map<String, dynamic>>[]
        : activeBooks
              .where((b) => matchesCatalog(b, _bookQuery))
              .take(6)
              .toList();

    final chosenBook = _selectedBook;

    final selectedReaderLoans =
        <({Map<String, dynamic> book, Map<String, dynamic> loan})>[];
    var selectedStudentOverdue = 0;
    if (_selectedStudent != null) {
      for (final item in allLoans) {
        if ((item.loan['studentId'] ?? '').toString().toUpperCase() ==
            _selectedStudent!.id.toUpperCase()) {
          selectedReaderLoans.add(item);
          if (isOverdue(item.loan, now: now)) selectedStudentOverdue++;
        }
      }
    } else if (_selectedMember != null) {
      for (final item in allLoans) {
        if ((item.loan['memberId'] ?? '').toString().toUpperCase() ==
            _selectedMember!.id.toUpperCase()) {
          selectedReaderLoans.add(item);
          if (isOverdue(item.loan, now: now)) selectedStudentOverdue++;
        }
      }
    }
    final selectedStudentLoans = selectedReaderLoans.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        IllustratedBannerCard(
          imageAsset: 'assets/images/school_desk_banner.jpg',
          title: 'Akıllı Ödünç / İade Bankosu',
          subtitle:
              '${cfg.libraryName} · Barkod/QR okutarak tek dokunuşla dolaşım',
          icon: Icons.point_of_sale_rounded,
          gradientColors: const [Color(0xFF065F46), Color(0xFF0D9488)],
          pills: [
            AnimatedStatPill(
              label: 'Aktif Ödünç',
              value: allLoans.length,
              icon: Icons.swap_horiz_rounded,
              accentColor: const Color(0xFFFDE68A),
            ),
            AnimatedStatPill(
              label: 'Geciken',
              value: overdueLoans.length,
              icon: Icons.warning_amber_rounded,
              accentColor: const Color(0xFFFCA5A5),
            ),
            AnimatedStatPill(
              label: 'Yaklaşan Teslim',
              value: dueSoonLoans.length,
              icon: Icons.schedule_rounded,
              accentColor: const Color(0xFFA5F3FC),
            ),
            AnimatedStatPill(
              label: 'Aktif Öğrenci',
              value: activeStudents.length,
              icon: Icons.school_rounded,
              accentColor: const Color(0xFFDDD6FE),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Today's Duty Librarians Strip
        BouncyTap(
          onTap: widget.onOpenDutyRoster,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.badge_rounded, color: scheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Günün Nöbetçi Kütüphanecileri (${weekdayNamesTr[now.weekday.clamp(1, 5)]})',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.2,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                      Text(
                        todayDuty.isEmpty
                            ? 'Nöbet çizelgesini düzenlemek için dokunun'
                            : todayDuty
                                  .map((d) => '${d.name} (${d.className})')
                                  .join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSecondaryContainer.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Dual Scanner Buttons
        Row(
          children: [
            Expanded(
              child: ShimmerActionButton(
                label: 'Akıllı Kamera Okut',
                subtitle: 'Kart + Kitap Barkod/QR',
                icon: Icons.qr_code_scanner_rounded,
                colors: const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                onTap: widget.busy ? null : () => _scanSmartCode(),
              ),
            ),
            const SizedBox(width: 10),
            BouncyTap(
              onTap: widget.busy
                  ? null
                  : () => _scanSmartCode(studentOnly: true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.credit_card_rounded, color: Colors.white),
                    SizedBox(height: 3),
                    Text(
                      'Kart Okut',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Kiosk Workspace Card
        Card(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step 1: Student
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: scheme.primary,
                      child: Text(
                        '1',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Okuyucu / Öğrenci Seçimi',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedStudent != null || _selectedMember != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(() {
                          _selectedStudent = null;
                          _selectedMember = null;
                        }),
                        child: const Text('Değiştir'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_selectedStudent != null || _selectedMember != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: scheme.primary,
                              child: Text(
                                _selectedStudent != null
                                    ? (_selectedStudent!.className.isEmpty
                                          ? 'Ö'
                                          : _selectedStudent!.className)
                                    : 'Ü',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedStudent?.name ??
                                        _selectedMember!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  Text(
                                    _selectedStudent != null
                                        ? 'Sınıf: ${_selectedStudent!.className} · Okul No: ${_selectedStudent!.number}'
                                        : '${_selectedMember!.kindTitle}${_selectedMember!.number.isEmpty ? '' : ' · No: ${_selectedMember!.number}'}',
                                    style: TextStyle(
                                      fontSize: 12.2,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: selectedStudentOverdue > 0
                                    ? scheme.error
                                    : const Color(0xFF059669),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                selectedStudentOverdue > 0
                                    ? '$selectedStudentOverdue Gecikmiş'
                                    : '$selectedStudentLoans Kitap Ödünçte',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (selectedReaderLoans.isNotEmpty) ...[
                          const Divider(height: 16),
                          Text(
                            'Okuyucunun Elindeki Kitaplar (${selectedReaderLoans.length})',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final item in selectedReaderLoans)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    isOverdue(item.loan, now: now)
                                        ? Icons.warning_amber_rounded
                                        : Icons.menu_book_rounded,
                                    size: 16,
                                    color: isOverdue(item.loan, now: now)
                                        ? scheme.error
                                        : scheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${item.book['title'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Hatırlatma Mesajı Kopyala',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.sms_outlined,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: buildOverdueReminderMessage(
                                            item.book,
                                            item.loan,
                                            now: now,
                                          ),
                                        ),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Hatırlatma mesajı kopyalandı.',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    onPressed: widget.busy
                                        ? null
                                        : () => _executeQuickReturn(
                                            item.book,
                                            item.loan,
                                          ),
                                    child: const Text(
                                      'İade Al',
                                      style: TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  )
                else ...[
                  TextField(
                    controller: _studentSearchCtrl,
                    onChanged: (v) => setState(() => _studentQuery = v),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.person_search_rounded),
                      hintText:
                          'Öğrenci adı, okul no, sınıf veya öğretmen/üye adı yazın...',
                    ),
                  ),
                  if (matchingStudents.isNotEmpty || matchingMembers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in matchingStudents)
                            ActionChip(
                              avatar: const Icon(Icons.person_rounded, size: 16),
                              label: Text(
                                '${s.name} (${s.className} · ${s.number})',
                              ),
                              onPressed: () => setState(() {
                                _selectedStudent = s;
                                _selectedMember = null;
                                _studentQuery = '';
                                _studentSearchCtrl.clear();
                              }),
                            ),
                          for (final m in matchingMembers)
                            ActionChip(
                              avatar: const Icon(Icons.badge_rounded, size: 16),
                              label: Text('${m.name} (${m.kindTitle})'),
                              onPressed: () => setState(() {
                                _selectedMember = m;
                                _selectedStudent = null;
                                _studentQuery = '';
                                _studentSearchCtrl.clear();
                              }),
                            ),
                        ],
                      ),
                    ),
                ],
                const Divider(height: 24),

                // Step 2: Book
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: scheme.primary,
                      child: Text(
                        '2',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Kitap Seçimi & Hızlı İşlem',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (chosenBook != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            setState(() => _selectedBookId = null),
                        child: const Text('Temizle'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (chosenBook == null) ...[
                  TextField(
                    controller: _bookSearchCtrl,
                    onChanged: (v) => setState(() => _bookQuery = v),
                    onSubmitted: (v) {
                      final direct = findBookByDeskCode(widget.books, v);
                      if (direct != null) {
                        setState(() {
                          _selectedBookId = direct['id'] as String;
                          _bookQuery = '';
                          _bookSearchCtrl.clear();
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.menu_book_rounded),
                      hintText:
                          'Demirbaş (CAL-001781), ISBN veya kitap adı yazın...',
                    ),
                  ),
                  if (matchingBooks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          for (final b in matchingBooks)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: BookCoverWidget(
                                book: b,
                                width: 34,
                                height: 50,
                              ),
                              title: Text(
                                '${b['title'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if ((b['author'] ?? '').toString().isNotEmpty)
                                    b['author'],
                                  if ((b['accessionCode'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    b['accessionCode'],
                                  if ((b['shelf'] ?? '').toString().isNotEmpty)
                                    'Dolap ${b['shelf']}',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                '${availableCopies(b)}/${b['quantity'] ?? 1} Rafta',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: availableCopies(b) > 0
                                      ? const Color(0xFF059669)
                                      : scheme.error,
                                ),
                              ),
                              onTap: () => setState(() {
                                _selectedBookId = b['id'] as String;
                                _bookQuery = '';
                                _bookSearchCtrl.clear();
                              }),
                            ),
                        ],
                      ),
                    ),
                ] else
                  Builder(
                    builder: (_) {
                      final bLoans = activeLoans(chosenBook);
                      final avail = availableCopies(chosenBook);
                      Map<String, dynamic>? matchingLoan;
                      if (_selectedStudent != null) {
                        for (final l in bLoans) {
                          if ((l['studentId'] ?? '').toString().toUpperCase() ==
                              _selectedStudent!.id.toUpperCase()) {
                            matchingLoan = l;
                            break;
                          }
                        }
                      } else if (_selectedMember != null) {
                        for (final l in bLoans) {
                          if ((l['memberId'] ?? '').toString().toUpperCase() ==
                              _selectedMember!.id.toUpperCase()) {
                            matchingLoan = l;
                            break;
                          }
                        }
                      } else if (bLoans.length == 1) {
                        matchingLoan = bLoans.first;
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BookCoverWidget(
                                book: chosenBook,
                                width: 64,
                                height: 94,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${chosenBook['title'] ?? ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '${chosenBook['author'] ?? ''}',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        if ((chosenBook['shelf'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          'Dolap ${chosenBook['shelf']}',
                                        if ((chosenBook['accessionCode'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          'Demirbaş: ${chosenBook['accessionCode']}',
                                        '$avail/${chosenBook['quantity'] ?? 1} Rafta',
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (matchingLoan != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF059669,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'İade Alınacak Kayıt: ${matchingLoan['name']} (${matchingLoan['studentClass'] ?? ''})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      for (final c in const [
                                        'Yeni',
                                        'İyi',
                                        'Yıpranmış',
                                        'Onarım gerekli',
                                      ])
                                        ChoiceChip(
                                          label: Text(
                                            c,
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          selected: _returnCondition == c,
                                          onSelected: (_) => setState(
                                            () => _returnCondition = c,
                                          ),
                                        ),
                                    ],
                                  ),
                                  SwitchListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Öğrenci kitabı okudu'),
                                    value: _readingCompleted,
                                    onChanged: (v) =>
                                        setState(() => _readingCompleted = v),
                                  ),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF059669,
                                        ),
                                      ),
                                      onPressed: widget.busy
                                          ? null
                                          : () => _executeQuickReturn(
                                              chosenBook,
                                              matchingLoan!,
                                            ),
                                      icon: const Icon(
                                        Icons.assignment_turned_in_rounded,
                                      ),
                                      label: const Text(
                                        'Tek Dokunuşla İade Al',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              if (avail > 0 &&
                                  (_selectedStudent != null ||
                                      _selectedMember != null))
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: widget.busy
                                        ? null
                                        : () => _executeQuickLendForReader(
                                            chosenBook,
                                          ),
                                    icon: const Icon(Icons.outbound_rounded),
                                    label: Text(
                                      '${(_selectedStudent?.name ?? _selectedMember!.name).split(' ').first} Adına Ödünç Ver',
                                    ),
                                  ),
                                )
                              else if (avail > 0)
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: widget.busy
                                        ? null
                                        : () => widget.actions.onLoan(
                                            chosenBook,
                                          ),
                                    icon: const Icon(Icons.outbound_rounded),
                                    label: const Text(
                                      'Detaylı Ödünç Penceresi',
                                    ),
                                  ),
                                ),
                              if (bLoans.length > 1 && matchingLoan == null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: widget.busy
                                        ? null
                                        : () => widget.actions.onReturn(
                                            chosenBook,
                                          ),
                                    icon: const Icon(
                                      Icons.assignment_returned_rounded,
                                    ),
                                    label: Text('İade Seç (${bLoans.length})'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Desk Queues
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: 0,
                icon: const Icon(Icons.warning_amber_rounded, size: 17),
                label: Text('Geciken (${overdueLoans.length})'),
              ),
              ButtonSegment(
                value: 1,
                icon: const Icon(Icons.today_rounded, size: 17),
                label: Text('Yaklaşan (${dueSoonLoans.length})'),
              ),
              ButtonSegment(
                value: 2,
                icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                label: Text('Aktif (${allLoans.length})'),
              ),
              const ButtonSegment(
                value: 3,
                icon: Icon(Icons.history_rounded, size: 17),
                label: Text('Son İşlemler'),
              ),
            ],
            selected: {_queueTab},
            onSelectionChanged: (s) => setState(() => _queueTab = s.first),
          ),
        ),
        const SizedBox(height: 10),
        if (_queueTab == 3)
          if (recentEvents.isEmpty)
            _emptyQueueCard(
              scheme,
              'Henüz kayıtlı ödünç/iade hareketi bulunmuyor.',
            )
          else
            for (final item in recentEvents.take(25))
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: scheme.surfaceContainerLow,
                child: ListTile(
                  leading: BookCoverWidget(
                    book: item.book,
                    width: 36,
                    height: 52,
                  ),
                  title: Text(
                    '${item.book['title'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${loanEventLabel(item.event['kind'] as String?)} · ${item.event['person'] ?? ''} (${item.event['studentClass'] ?? ''})',
                  ),
                  trailing: Text(
                    _shortDate((item.event['date'] ?? '').toString()),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
        else
          Builder(
            builder: (_) {
              final list = _queueTab == 0
                  ? overdueLoans
                  : _queueTab == 1
                  ? dueSoonLoans
                  : allLoans;
              if (list.isEmpty) {
                return _emptyQueueCard(
                  scheme,
                  _queueTab == 0
                      ? 'Harika! Gecikmiş kitap bulunmuyor.'
                      : _queueTab == 1
                      ? 'Önümüzdeki 3 gün içinde teslim tarihi gelen kitap yok.'
                      : 'Şu anda ödünçte kitap bulunmuyor.',
                );
              }
              return Column(
                children: [
                  for (final pair in list.take(40))
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: scheme.surfaceContainerLow,
                      child: ListTile(
                        leading: BookCoverWidget(
                          book: pair.book,
                          width: 38,
                          height: 54,
                        ),
                        title: Text(
                          '${pair.book['title'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${pair.loan['name'] ?? ''} (${pair.loan['studentClass'] ?? ''}) · Teslim: ${_shortDate((pair.loan['due'] ?? '').toString())}',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: widget.busy
                              ? null
                              : () => _executeQuickReturn(pair.book, pair.loan),
                          child: const Text('İade Al'),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _emptyQueueCard(ColorScheme scheme, String message) {
    return Container(
      padding: const EdgeInsets.all(22),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    );
  }

  String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}
