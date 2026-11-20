import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'book_visuals.dart';
import 'library_labels_page.dart';
import 'loan_model.dart';
import 'reservation_model.dart';
import 'student_card.dart';
import 'student_profile.dart';
import 'student_store.dart';

/// Returns a motivating Turkish reader rank badge based on completed book count.
String studentRankTitle(int completedBooks) {
  if (completedBooks >= 20) return 'Kütüphane Şampiyonu';
  if (completedBooks >= 10) return 'Altın Okur';
  if (completedBooks >= 6) return 'Kitap Kurdu';
  if (completedBooks >= 3) return 'Kitap Dostu';
  if (completedBooks >= 1) return 'Okuma Yolcusu';
  return 'Yeni Okur';
}

class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({
    super.key,
    required this.student,
    required this.books,
  });
  final Student student;
  final List<Map<String, dynamic>> books;
  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  int limit = 50;
  bool _showBarcode = false;

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final student = widget.student;
    final profile = buildStudentProfile(student, widget.books);
    final rank = studentRankTitle(profile.completedBooks);
    final subtitleParts = [
      student.graduatedAt != null ? 'Mezun' : student.className,
      if (student.number.isNotEmpty) 'No: ${student.number}',
    ].where((s) => s.isNotEmpty).join(' · ');

    String? cardCode;
    List<List<double>> bars = const [];
    try {
      cardCode = studentCardCode(student);
      bars = buildCode128Bars(cardCode);
    } catch (_) {
      cardCode = null;
    }

    String day(dynamic value) {
      final d = DateTime.tryParse((value ?? '').toString())?.toLocal();
      return d == null
          ? 'Belirtilmemiş'
          : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    }

    return Scaffold(
      appBar: AppBar(title: Text(student.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Gradient Hero Profile Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      child: Text(
                        _initials(student.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                          ),
                          if (subtitleParts.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitleParts,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.amberAccent.withValues(alpha: 0.7),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.workspace_premium_rounded,
                                  size: 14,
                                  color: Colors.amberAccent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  rank,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      CompactStatChip(
                        icon: Icons.stars_rounded,
                        label: '${profile.points} puan',
                        color: Colors.amberAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      CompactStatChip(
                        icon: Icons.menu_book_rounded,
                        label: '${profile.completedBooks} okunan',
                        color: Colors.lightGreenAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      CompactStatChip(
                        icon: Icons.inventory_2_rounded,
                        label: '${profile.active.length} elinde',
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      CompactStatChip(
                        icon: Icons.history_rounded,
                        label: '${profile.returns} iade',
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      if (profile.lateReturns > 0) ...[
                        const SizedBox(width: 6),
                        CompactStatChip(
                          icon: Icons.schedule_rounded,
                          label: '${profile.lateReturns} gecikmeli',
                          color: Colors.redAccent,
                          backgroundColor: Colors.red.withValues(alpha: 0.28),
                          foregroundColor: Colors.white,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (cardCode != null && bars.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.qr_code_2_rounded, color: scheme.primary),
                    title: const Text(
                      'Dijital Öğrenci Barkod Kartı',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _showBarcode
                          ? 'Akıllı Banko\'da doğrudan ekrandan okutabilirsiniz'
                          : 'Bankoda okutmak için dokunup barkodu gösterin',
                    ),
                    trailing: Icon(
                      _showBarcode
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    onTap: () => setState(() => _showBarcode = !_showBarcode),
                  ),
                  if (_showBarcode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 68,
                                  width: double.infinity,
                                  child: CustomPaint(
                                    painter: _Code128Painter(bars),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  cardCode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: cardCode!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Kart kodu kopyalandı.'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Kart Kodunu Kopyala'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Fiziksel iade: ${profile.returns} · Tamamlanan okuma: ${profile.completedBooks}. İade alınması okunduğu anlamına gelmez; yalnız tamamlandığı bildirilen kütüphane kitapları puan ve okumaya sayılır.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Şu an elindeki kitaplar (${profile.active.length})',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (profile.active.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline_rounded),
                title: Text('Öğrencinin elinde ödünç kitap bulunmuyor.'),
              ),
            )
          else
            for (final item in profile.active)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: isOverdue(item.entry)
                    ? scheme.errorContainer.withValues(alpha: 0.45)
                    : null,
                child: ListTile(
                  leading: Icon(
                    isOverdue(item.entry)
                        ? Icons.warning_amber_rounded
                        : Icons.book_outlined,
                    color: isOverdue(item.entry)
                        ? scheme.error
                        : scheme.primary,
                  ),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${item.entry['kind'] == 'textbook' ? 'Ders kitabı · ' : ''}Son tarih: ${day(item.entry['due'])}${isOverdue(item.entry) ? ' · GECİKMİŞ' : ''}',
                  ),
                ),
              ),
          if (profile.reservations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Rezervasyonları (${profile.reservations.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final item in profile.reservations)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    isReadyReservation(item.entry)
                        ? Icons.bookmark_added_rounded
                        : Icons.hourglass_top_rounded,
                    color: isReadyReservation(item.entry)
                        ? Colors.green
                        : scheme.tertiary,
                  ),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    isReadyReservation(item.entry)
                        ? 'Teslim için hazır'
                        : 'Sırada bekliyor',
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            'Ödünç geçmişi (${profile.history.length})',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (profile.history.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.history_rounded),
                title: Text('Bu öğrenci kimliğine bağlı hareket bulunmuyor.'),
              ),
            )
          else ...[
            for (final item in profile.history.take(limit))
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    item.entry['kind'] == 'returned'
                        ? Icons.assignment_turned_in_rounded
                        : item.entry['kind'] == 'extended'
                        ? Icons.update_rounded
                        : Icons.outbound_rounded,
                    color: item.entry['late'] == true
                        ? scheme.error
                        : scheme.primary,
                    size: 20,
                  ),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${loanEventLabel(item.entry['kind'] as String?)} · ${day(item.entry['date'])}${item.entry['late'] == true ? ' · Gecikmeli' : ''}${item.entry['readingCompleted'] == true
                        ? ' · Okundu'
                        : item.entry['readingCompleted'] == false
                        ? ' · Okunmadı'
                        : ''}',
                  ),
                ),
              ),
            if (limit < profile.history.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton(
                  onPressed: () => setState(() => limit += 50),
                  child: Text(
                    'Daha fazla göster ($limit/${profile.history.length})',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Code128Painter extends CustomPainter {
  const _Code128Painter(this.bars);
  final List<List<double>> bars;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    for (final bar in bars) {
      if (bar.length < 2) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          bar[0] * size.width,
          0,
          bar[1] * size.width,
          size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Code128Painter oldDelegate) =>
      oldDelegate.bars != bars;
}
