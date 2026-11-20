import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book_visuals.dart';
import 'catalog_search.dart';
import 'catalog_views.dart';
import 'loan_model.dart';

enum DiscoveryMood {
  any('Fark Etmez'),
  availableOnly('Şu An Rafta'),
  shortRead('Kısa & İnce (<200 s.)'),
  topRated('Yüksek Puanlı'),
  hiddenGem('Hiç Ödünç Alınmamış');

  const DiscoveryMood(this.label);
  final String label;
}

int _bookReadScore(Map<String, dynamic> book) {
  final history = loanHistory(book);
  final lents = history.where((e) => e['kind'] == 'lent').length;
  final returns = history.where((e) => e['kind'] == 'returned').length;
  return math.max(lents, returns);
}

/// Filters active catalog books for the "Ne Okusam?" recommender.
List<Map<String, dynamic>> recommendBooks(
  List<Map<String, dynamic>> books, {
  DiscoveryMood mood = DiscoveryMood.any,
  String? category,
  String? readingLevel,
  int? randomSeed,
}) {
  final matches = <Map<String, dynamic>>[];
  final catFilter = category == null ? '' : foldTurkish(category.trim());
  final lvlFilter = readingLevel == null ? '' : foldTurkish(readingLevel.trim());

  for (final b in books) {
    if (b['deletedAt'] != null || b['isWithdrawn'] == true) continue;
    if (catFilter.isNotEmpty &&
        !foldTurkish('${b['category'] ?? ''}').contains(catFilter)) {
      continue;
    }
    if (lvlFilter.isNotEmpty &&
        foldTurkish('${b['readingLevel'] ?? ''}') != lvlFilter) {
      continue;
    }
    switch (mood) {
      case DiscoveryMood.any:
        break;
      case DiscoveryMood.availableOnly:
        if (availableCopies(b) <= 0) continue;
      case DiscoveryMood.shortRead:
        final pages = int.tryParse('${b['pageCount'] ?? ''}');
        if (pages == null || pages <= 0 || pages >= 200) continue;
      case DiscoveryMood.topRated:
        final rating = (b['rating'] as int?) ?? 0;
        if (rating < 4 && b['isFavorite'] != true) continue;
      case DiscoveryMood.hiddenGem:
        if (availableCopies(b) <= 0 || _bookReadScore(b) > 0) continue;
    }
    matches.add(b);
  }

  if (randomSeed != null) {
    matches.shuffle(math.Random(randomSeed));
  } else {
    matches.sort((a, b) {
      final scoreCmp =
          (((b['rating'] as int?) ?? 0) + (b['isFavorite'] == true ? 2 : 0))
              .compareTo(
                ((a['rating'] as int?) ?? 0) + (a['isFavorite'] == true ? 2 : 0),
              );
      if (scoreCmp != 0) return scoreCmp;
      return foldTurkish('${a['title'] ?? ''}')
          .compareTo(foldTurkish('${b['title'] ?? ''}'));
    });
  }
  return matches;
}

/// Groups active catalog books by `series`, ordering volumes ascending.
Map<String, List<Map<String, dynamic>>> groupBookSeries(
  List<Map<String, dynamic>> books,
) {
  final map = <String, List<Map<String, dynamic>>>{};
  for (final b in books) {
    if (b['deletedAt'] != null || b['isWithdrawn'] == true) continue;
    final series = (b['series'] ?? '').toString().trim();
    if (series.isEmpty) continue;
    map.putIfAbsent(series, () => []).add(b);
  }
  for (final list in map.values) {
    list.sort((a, b) {
      final va = (a['volume'] as int?) ?? 999999;
      final vb = (b['volume'] as int?) ?? 999999;
      if (va != vb) return va.compareTo(vb);
      return foldTurkish('${a['title'] ?? ''}')
          .compareTo(foldTurkish('${b['title'] ?? ''}'));
    });
  }
  final sortedKeys = map.keys.toList()
    ..sort((a, b) {
      final lenCmp = map[b]!.length.compareTo(map[a]!.length);
      return lenCmp != 0 ? lenCmp : foldTurkish(a).compareTo(foldTurkish(b));
    });
  return {for (final k in sortedKeys) k: map[k]!};
}

/// Aggregates active authors with their book count and historical borrow count.
List<({String author, int bookCount, int borrowCount})> topAuthorsWithStats(
  List<Map<String, dynamic>> books,
) {
  final displayNames = <String, String>{};
  final bookCounts = <String, int>{};
  final borrowCounts = <String, int>{};

  for (final b in books) {
    if (b['deletedAt'] != null || b['isWithdrawn'] == true) continue;
    final raw = (b['author'] ?? '').toString().trim();
    if (raw.isEmpty) continue;
    final key = foldTurkish(raw);
    displayNames.putIfAbsent(key, () => raw);
    bookCounts[key] = (bookCounts[key] ?? 0) + 1;
    borrowCounts[key] = (borrowCounts[key] ?? 0) + _bookReadScore(b);
  }

  final items = [
    for (final k in displayNames.keys)
      (
        author: displayNames[k]!,
        bookCount: bookCounts[k] ?? 0,
        borrowCount: borrowCounts[k] ?? 0,
      ),
  ];
  items.sort((a, b) {
    final c = b.bookCount.compareTo(a.bookCount);
    if (c != 0) return c;
    final bc = b.borrowCount.compareTo(a.borrowCount);
    return bc != 0 ? bc : foldTurkish(a.author).compareTo(foldTurkish(b.author));
  });
  return items;
}

/// Extracts comma/semicolon-separated tags with frequency counts.
List<({String tag, int count})> extractTagCounts(
  List<Map<String, dynamic>> books,
) {
  final display = <String, String>{};
  final counts = <String, int>{};
  for (final b in books) {
    if (b['deletedAt'] != null || b['isWithdrawn'] == true) continue;
    final rawTags = (b['tags'] ?? '').toString();
    for (final part in rawTags.split(RegExp(r'[,;]+'))) {
      final tag = part.trim();
      if (tag.isEmpty) continue;
      final key = foldTurkish(tag);
      display.putIfAbsent(key, () => tag);
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final list = [
    for (final k in display.keys) (tag: display[k]!, count: counts[k] ?? 0),
  ];
  list.sort((a, b) {
    final cmp = b.count.compareTo(a.count);
    return cmp != 0 ? cmp : foldTurkish(a.tag).compareTo(foldTurkish(b.tag));
  });
  return list;
}

/// Ranks active books by historical checkouts descending.
List<({Map<String, dynamic> book, int borrowCount})> mostBorrowedBooks(
  List<Map<String, dynamic>> books, {
  int limit = 40,
}) {
  final scored = <({Map<String, dynamic> book, int borrowCount})>[];
  for (final b in books) {
    if (b['deletedAt'] != null || b['isWithdrawn'] == true) continue;
    final count = _bookReadScore(b);
    if (count > 0) scored.add((book: b, borrowCount: count));
  }
  scored.sort((a, b) {
    final c = b.borrowCount.compareTo(a.borrowCount);
    if (c != 0) return c;
    return foldTurkish('${a.book['title'] ?? ''}')
        .compareTo(foldTurkish('${b.book['title'] ?? ''}'));
  });
  return scored.take(limit).toList();
}

/// Discovery hub featuring "Ne Okusam?" recommender, Series tracker, Author directory,
/// Tag cloud, and Most Borrowed Books leaderboard.
class LibraryDiscoveryPage extends StatefulWidget {
  const LibraryDiscoveryPage({
    super.key,
    required this.books,
    required this.actions,
  });

  final List<Map<String, dynamic>> books;
  final BookActionCallbacks actions;

  @override
  State<LibraryDiscoveryPage> createState() => _LibraryDiscoveryPageState();
}

class _LibraryDiscoveryPageState extends State<LibraryDiscoveryPage> {
  DiscoveryMood _mood = DiscoveryMood.availableOnly;
  String? _selectedCategory;
  int _spinSeed = DateTime.now().millisecondsSinceEpoch;
  String _authorQuery = '';
  String? _selectedTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeBooks = widget.books
        .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
        .toList();
    final categories = activeBooks
        .map((b) => (b['category'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => foldTurkish(a).compareTo(foldTurkish(b)));

    final picks = recommendBooks(
      activeBooks,
      mood: _mood,
      category: _selectedCategory,
      randomSeed: _spinSeed,
    );
    final spotlight = picks.isEmpty ? null : picks.first;
    final seriesMap = groupBookSeries(activeBooks);
    final authors = topAuthorsWithStats(activeBooks).where((item) {
      if (_authorQuery.trim().isEmpty) return true;
      return foldTurkish(item.author).contains(foldTurkish(_authorQuery.trim()));
    }).toList();
    final tags = extractTagCounts(activeBooks);
    final popular = mostBorrowedBooks(activeBooks);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kitap Keşfet & Ne Okusam?'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.casino_rounded), text: 'Ne Okusam?'),
              Tab(icon: Icon(Icons.collections_bookmark_rounded), text: 'Seriler'),
              Tab(icon: Icon(Icons.person_search_rounded), text: 'Yazarlar'),
              Tab(icon: Icon(Icons.local_fire_department_rounded), text: 'Etiket & Popüler'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Ne Okusam?
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final m in DiscoveryMood.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: _mood == m,
                        onSelected: (_) => setState(() {
                          _mood = m;
                          _spinSeed = DateTime.now().microsecondsSinceEpoch;
                        }),
                      ),
                  ],
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedCategory,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Kategori Filtresi',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tüm Kategoriler'),
                      ),
                      for (final cat in categories)
                        DropdownMenuItem<String?>(
                          value: cat,
                          child: Text(cat, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedCategory = v;
                      _spinSeed = DateTime.now().microsecondsSinceEpoch;
                    }),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => setState(
                    () => _spinSeed = DateTime.now().microsecondsSinceEpoch,
                  ),
                  icon: const Icon(Icons.casino_rounded),
                  label: Text(
                    picks.isEmpty
                        ? 'Kriterlere Uygun Kitap Bulunamadı'
                        : 'Rastgele Öner (${picks.length} seçenek)',
                  ),
                ),
                const SizedBox(height: 16),
                if (spotlight != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primaryContainer.withValues(alpha: 0.72),
                          scheme.secondaryContainer.withValues(alpha: 0.55),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => showRichBookDetailSheet(
                        context,
                        spotlight,
                        widget.actions,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BookCoverWidget(
                            book: spotlight,
                            width: 106,
                            height: 156,
                            heroTag: 'discover-spot-${spotlight['id']}',
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CompactStatChip(
                                  icon: Icons.auto_awesome_rounded,
                                  label: 'Günün Önerisi',
                                  color: scheme.primary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${spotlight['title'] ?? ''}',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                if ((spotlight['author'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${spotlight['author']}',
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if ((spotlight['shelf'] ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty)
                                      CompactStatChip(
                                        icon: Icons.shelves,
                                        label: 'Raf: ${spotlight['shelf']}',
                                      ),
                                    CompactStatChip(
                                      icon: availableCopies(spotlight) > 0
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.swap_horiz_rounded,
                                      label: availableCopies(spotlight) > 0
                                          ? '${availableCopies(spotlight)} rafta'
                                          : 'Ödünçte',
                                      color: availableCopies(spotlight) > 0
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: () => showRichBookDetailSheet(
                                        context,
                                        spotlight,
                                        widget.actions,
                                      ),
                                      child: const Text('Detay & Ödünç'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (picks.length > 1) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Diğer Uygun Öneriler',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final b in picks.skip(1).take(12))
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: BookCoverWidget(
                            book: b,
                            width: 44,
                            height: 62,
                            heroTag: 'discover-list-${b['id']}',
                          ),
                          title: Text(
                            '${b['title'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              if ((b['author'] ?? '').toString().isNotEmpty)
                                b['author'],
                              if ((b['shelf'] ?? '').toString().isNotEmpty)
                                'Raf ${b['shelf']}',
                              if ((b['pageCount'] ?? '').toString().isNotEmpty)
                                '${b['pageCount']} s.',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => showRichBookDetailSheet(
                            context,
                            b,
                            widget.actions,
                          ),
                        ),
                      ),
                  ],
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyCatalogArtwork(
                      title: 'Eşleşen kitap yok',
                      subtitle:
                          'Farklı bir mod veya kategori seçerek yeniden deneyin.',
                    ),
                  ),
              ],
            ),

            // Tab 2: Seriler
            seriesMap.isEmpty
                ? const EmptyCatalogArtwork(
                    title: 'Seri kaydı bulunmuyor',
                    subtitle:
                        'Kitap düzenleme ekranından "Seri" alanı girilen kitaplar burada sıralanır.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: seriesMap.length,
                    itemBuilder: (_, idx) {
                      final name = seriesMap.keys.elementAt(idx);
                      final list = seriesMap[name]!;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              '${list.length}',
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text('${list.length} kitap seri içinde'),
                          children: [
                            for (final b in list)
                              ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 15,
                                  child: Text(
                                    b['volume'] != null ? '${b['volume']}' : '•',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                title: Text('${b['title'] ?? ''}'),
                                subtitle: Text(
                                  [
                                    if ((b['shelf'] ?? '').toString().isNotEmpty)
                                      'Raf ${b['shelf']}',
                                    availableCopies(b) > 0
                                        ? '${availableCopies(b)} rafta'
                                        : 'Ödünçte',
                                  ].join(' · '),
                                ),
                                trailing: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                ),
                                onTap: () => showRichBookDetailSheet(
                                  context,
                                  b,
                                  widget.actions,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),

            // Tab 3: Yazarlar
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Yazar ara...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _authorQuery = v),
                  ),
                ),
                Expanded(
                  child: authors.isEmpty
                      ? const EmptyCatalogArtwork(
                          title: 'Yazar bulunamadı',
                          subtitle: 'Arama filtresini temizleyip tekrar deneyin.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                          itemCount: authors.length,
                          itemBuilder: (_, idx) {
                            final item = authors[idx];
                            final authorBooks = activeBooks
                                .where(
                                  (b) =>
                                      foldTurkish('${b['author'] ?? ''}') ==
                                      foldTurkish(item.author),
                                )
                                .toList();
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: scheme.secondaryContainer,
                                  child: Text(
                                    item.author.trim().isEmpty
                                        ? '?'
                                        : item.author
                                              .trim()
                                              .substring(0, 1)
                                              .toUpperCase(),
                                    style: TextStyle(
                                      color: scheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  item.author,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${item.bookCount} kitap${item.borrowCount > 0 ? ' · ${item.borrowCount} ödünç' : ''}',
                                ),
                                children: [
                                  for (final b in authorBooks)
                                    ListTile(
                                      dense: true,
                                      title: Text('${b['title'] ?? ''}'),
                                      subtitle: Text(
                                        availableCopies(b) > 0
                                            ? '${availableCopies(b)} rafta'
                                            : 'Ödünçte',
                                      ),
                                      onTap: () => showRichBookDetailSheet(
                                        context,
                                        b,
                                        widget.actions,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),

            // Tab 4: Etiket & Popüler
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                if (tags.isNotEmpty) ...[
                  Text(
                    'Etiket Bulutu',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final t in tags.take(30))
                        ChoiceChip(
                          label: Text('#${t.tag} (${t.count})'),
                          selected: _selectedTag == t.tag,
                          onSelected: (sel) => setState(
                            () => _selectedTag = sel ? t.tag : null,
                          ),
                        ),
                    ],
                  ),
                  if (_selectedTag != null) ...[
                    const SizedBox(height: 10),
                    for (final b in activeBooks.where(
                      (book) => foldTurkish(
                        '${book['tags'] ?? ''}',
                      ).contains(foldTurkish(_selectedTag!)),
                    ))
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          title: Text('${b['title'] ?? ''}'),
                          subtitle: Text('${b['author'] ?? ''}'),
                          onTap: () => showRichBookDetailSheet(
                            context,
                            b,
                            widget.actions,
                          ),
                        ),
                      ),
                  ],
                  const Divider(height: 28),
                ],
                Text(
                  'En Çok Ödünç Alınan Kitaplar',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (popular.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Ödünç geçmişi oluştukça en popüler kitaplar burada sıralanacaktır.',
                    ),
                  )
                else
                  for (var i = 0; i < popular.length; i++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: i < 3
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                              : scheme.surfaceContainerHighest,
                          child: Text(
                            '#${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: i < 3
                                  ? const Color(0xFFB45309)
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                        title: Text(
                          '${popular[i].book['title'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${popular[i].book['author'] ?? ''} · ${popular[i].borrowCount} kez ödünç alındı',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showRichBookDetailSheet(
                          context,
                          popular[i].book,
                          widget.actions,
                        ),
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
