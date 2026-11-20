import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog_search.dart';
import 'reading_champions.dart';
import 'student_store.dart';

class ReadingChampionsPage extends StatefulWidget {
  const ReadingChampionsPage({
    super.key,
    required this.books,
    required this.students,
  });
  final List<Map<String, dynamic>> books;
  final List<Student> students;

  @override
  State<ReadingChampionsPage> createState() => _ReadingChampionsPageState();
}

class _ReadingChampionsPageState extends State<ReadingChampionsPage> {
  int _segment = 0; // 0: Öğrenciler, 1: Sınıflar
  String _query = '';
  String? _classFilter;

  Widget _podiumCard(
    BuildContext context, {
    required ReadingChampion person,
    required int place,
    required double height,
  }) {
    final palette = switch (place) {
      1 => [const Color(0xFFF59E0B), const Color(0xFFD97706)],
      2 => [const Color(0xFF64748B), const Color(0xFF475569)],
      _ => [const Color(0xFFB45309), const Color(0xFF92400E)],
    };
    final medal = switch (place) {
      1 => '1.',
      2 => '2.',
      _ => '3.',
    };
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => CertificateDialog(person: person),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CircleAvatar(
              radius: place == 1 ? 26 : 21,
              backgroundColor: palette.first.withValues(alpha: 0.2),
              child: Icon(
                place == 1
                    ? Icons.emoji_events_rounded
                    : Icons.workspace_premium_rounded,
                color: palette.first,
                size: place == 1 ? 28 : 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              person.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: place == 1 ? 13 : 11.5,
                height: 1.15,
              ),
            ),
            Text(
              person.className,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: height,
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: palette,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    medal,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    '${person.books} kitap',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  Text(
                    '${person.points} p',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final people = readingChampions(widget.books, widget.students);
    final classes = championClassTotals(people);
    final classOptions = classes.map((c) => c.className).toList();
    final filteredPeople = people.where((p) {
      if (_classFilter != null && p.className != _classFilter) return false;
      if (_query.trim().isNotEmpty) {
        final q = foldTurkish(_query.trim());
        if (!foldTurkish(p.name).contains(q) &&
            !foldTurkish(p.className).contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Okuma Şampiyonları')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: const Text(
              'Yalnız kimliği belli öğrencilerin tamamlandığı bildirilen kütüphane okumaları sayılır. Aynı eser tekrar okunursa kitap sayısı artmaz; ders kitapları sayılmaz. Sertifika için öğrenciye dokunun.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (people.isNotEmpty && _segment == 0 && _query.isEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 196,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (people.length >= 2)
                    _podiumCard(context, person: people[1], place: 2, height: 74)
                  else
                    const Expanded(child: SizedBox.shrink()),
                  _podiumCard(context, person: people[0], place: 1, height: 96),
                  if (people.length >= 3)
                    _podiumCard(context, person: people[2], place: 3, height: 60)
                  else
                    const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SegmentedButton<int>(
            segments: [
              ButtonSegment<int>(
                value: 0,
                icon: const Icon(Icons.person_rounded),
                label: Text('Öğrenciler (${people.length})'),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: const Icon(Icons.groups_rounded),
                label: Text('Sınıflar (${classes.length})'),
              ),
            ],
            selected: {_segment},
            onSelectionChanged: (sel) => setState(() => _segment = sel.first),
          ),
          const SizedBox(height: 12),
          if (_segment == 0) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Öğrenci veya sınıf ara...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                if (classOptions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<String?>(
                    tooltip: 'Sınıfa göre filtrele',
                    icon: Icon(
                      Icons.filter_list_rounded,
                      color: _classFilter != null ? scheme.primary : null,
                    ),
                    onSelected: (v) => setState(() => _classFilter = v),
                    itemBuilder: (_) => [
                      const PopupMenuItem<String?>(
                        value: null,
                        child: Text('Tüm Sınıflar'),
                      ),
                      for (final c in classOptions)
                        PopupMenuItem<String?>(value: c, child: Text(c)),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (filteredPeople.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.emoji_events_outlined),
                  title: Text('Gösterilecek okuma verisi bulunamadı.'),
                ),
              )
            else
              for (var i = 0; i < filteredPeople.length && i < 50; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: i < 3
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                          : scheme.surfaceContainerHighest,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: i < 3
                              ? const Color(0xFFB45309)
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                    title: Text(
                      filteredPeople[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${filteredPeople[i].className} · ${filteredPeople[i].points} puan',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '${filteredPeople[i].books} kitap',
                            style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.workspace_premium_outlined, size: 18),
                      ],
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (ctx) =>
                          CertificateDialog(person: filteredPeople[i]),
                    ),
                  ),
                ),
          ] else ...[
            if (classes.isEmpty)
              const Card(
                child: ListTile(title: Text('Henüz okuma verisi yok.')),
              )
            else
              for (var i = 0; i < classes.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.secondaryContainer,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      classes[i].className,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${classes[i].books} kitap',
                        style: TextStyle(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class CertificateDialog extends StatefulWidget {
  const CertificateDialog({super.key, required this.person});
  final ReadingChampion person;
  @override
  State<CertificateDialog> createState() => _CertificateDialogState();
}

class _CertificateDialogState extends State<CertificateDialog> {
  bool saving = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Okuma Başarı Sertifikası'),
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFEF3C7).withValues(alpha: 0.75),
              scheme.surfaceContainerLow,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD97706).withValues(alpha: 0.65),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              size: 44,
              color: Color(0xFFD97706),
            ),
            const SizedBox(height: 8),
            const Text(
              'TEBRİKLER!',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Color(0xFFB45309),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.person.name,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              widget.person.className,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.person.books} kitap okudu · ${widget.person.points} puan',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
        FilledButton.icon(
          onPressed: saving
              ? null
              : () async {
                  setState(() => saving = true);
                  try {
                    final saved = await const MethodChannel('kitapbul/files')
                        .invokeMethod<bool>('exportCertificatePdf', {
                          'filename': 'OkumaSertifikasi.pdf',
                          'data': jsonEncode({
                            'name': widget.person.name,
                            'className': widget.person.className,
                            'books': widget.person.books,
                          }),
                        });
                    if (context.mounted && saved == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sertifika kaydedildi.')),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sertifika kaydedilemedi.'),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => saving = false);
                  }
                },
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: const Text('PDF Kaydet'),
        ),
      ],
    );
  }
}
