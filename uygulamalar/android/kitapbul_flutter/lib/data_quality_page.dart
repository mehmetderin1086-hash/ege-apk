import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'book_lookup.dart';
import 'cover_fetch.dart';
import 'data_quality.dart';
import 'isbn.dart';

typedef ApplyDownloadedCover =
    Future<bool> Function(
      String id,
      String isbn,
      Uint8List bytes,
      String source,
    );
typedef ApplyDownloadedMetadata =
    Future<bool> Function(
      String id,
      Map<String, String> info,
      Uint8List? coverBytes,
    );
typedef CoverFetcher = Future<DownloadedCover?> Function(String isbn);

bool eligibleForMetadataEnrichment(Map<String, dynamic> book) {
  if (!isQualityCandidate(book)) return false;
  final needsAny =
      missingQualityField(book, DataQualityField.isbn) ||
      missingQualityField(book, DataQualityField.author) ||
      missingQualityField(book, DataQualityField.publisher) ||
      missingQualityField(book, DataQualityField.category) ||
      missingQualityField(book, DataQualityField.pages);
  if (!needsAny) return false;
  final isbn = (book['isbn'] ?? '').toString().trim();
  if (isbn.isNotEmpty && isValidIsbn(isbn)) return true;
  final title = (book['title'] ?? '').toString().trim();
  return title.isNotEmpty;
}

class DataQualityPage extends StatefulWidget {
  const DataQualityPage({
    super.key,
    required this.books,
    this.applyCover,
    this.applyMetadata,
    this.fetchCover = fetchBestCover,
    this.allowTitleCoverLookup = false,
  });

  final List<Map<String, dynamic>> books;
  final ApplyDownloadedCover? applyCover;
  final ApplyDownloadedMetadata? applyMetadata;
  final CoverFetcher fetchCover;
  final bool allowTitleCoverLookup;

  @override
  State<DataQualityPage> createState() => _DataQualityPageState();
}

class _DataQualityPageState extends State<DataQualityPage> {
  late List<Map<String, dynamic>> books = [...widget.books];
  bool busy = false, stopRequested = false;
  int found = 0, missing = 0, failed = 0, locked = 0;
  String? summary;

  bool _bookEligibleForCover(Map<String, dynamic> b) =>
      eligibleForCover(b, allowTitleLookup: widget.allowTitleCoverLookup);

  Future<void> fillCovers() async {
    if (busy || widget.applyCover == null) return;
    final pending = books.where(_bookEligibleForCover).toList();
    final lockedCount = books
        .where(
          (b) =>
              missingQualityField(b, DataQualityField.cover) &&
              coverFieldLocked(b),
        )
        .length;
    setState(() {
      busy = true;
      stopRequested = false;
      found = 0;
      missing = 0;
      failed = 0;
      locked = lockedCount;
      summary = null;
    });
    for (final book in pending) {
      if (stopRequested || !mounted) break;
      try {
        final rawIsbn = (book['isbn'] ?? '').toString().trim();
        final DownloadedCover? cover;
        if (widget.allowTitleCoverLookup &&
            identical(widget.fetchCover, fetchBestCover)) {
          cover = await fetchBestCoverForBook(book);
        } else {
          cover = await widget.fetchCover(rawIsbn);
        }
        if (stopRequested || !mounted) break;
        if (cover == null) {
          missing++;
        } else {
          final ok = await widget.applyCover!(
            book['id'] as String,
            (book['isbn'] ?? '').toString(),
            cover.bytes,
            cover.source,
          );
          if (!mounted) return;
          if (ok) {
            found++;
            final encoded = storeCoverBytes(cover.bytes);
            final coverSource = cover.source;
            books = books
                .map(
                  (b) => b['id'] == book['id']
                      ? {...b, 'coverBase64': encoded, 'coverSource': coverSource}
                      : b,
                )
                .toList();
          } else {
            failed++;
          }
        }
      } catch (_) {
        failed++;
      }
      if (mounted) setState(() {});
      if (!stopRequested && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      summary =
          '$found kapak kaydedildi, $missing bulunamadı, $failed işlem başarısız${locked > 0 ? ', $locked kilitli kayıt atlandı' : ''}${stopRequested ? ' (duraklatıldı)' : ''}.';
    });
  }

  Future<void> fillMetadata() async {
    if (busy || widget.applyMetadata == null) return;
    final pending = books.where(eligibleForMetadataEnrichment).toList();
    setState(() {
      busy = true;
      stopRequested = false;
      found = 0;
      missing = 0;
      failed = 0;
      locked = 0;
      summary = null;
    });
    for (final book in pending) {
      if (stopRequested || !mounted) break;
      try {
        final rawIsbn = (book['isbn'] ?? '').toString().trim();
        final title = (book['title'] ?? '').toString().trim();
        final author = (book['author'] ?? '').toString().trim();
        final publisher = (book['publisher'] ?? '').toString().trim();

        Map<String, String>? info;
        if (rawIsbn.isNotEmpty && isValidIsbn(rawIsbn)) {
          try {
            info = await lookupIsbn(rawIsbn);
          } catch (_) {}
        }
        if ((info == null ||
                (info['publisher'] ?? '').isEmpty ||
                (info['category'] ?? '').isEmpty ||
                (info['pageCount'] ?? '').isEmpty) &&
            title.isNotEmpty) {
          try {
            final ky = await lookupKitapyurduFirstMatch(
              title: title,
              author: missingQualityField(book, DataQualityField.author)
                  ? ''
                  : author,
              publisher: publisher,
              expectedIsbn: rawIsbn.isNotEmpty && isValidIsbn(rawIsbn)
                  ? rawIsbn
                  : null,
            );
            info = mergeLookupMaps([info, ky]);
          } catch (_) {}
        }
        if (stopRequested || !mounted) break;
        if (info == null) {
          missing++;
        } else {
          Uint8List? coverBytes;
          if (missingQualityField(book, DataQualityField.cover) &&
              !coverFieldLocked(book) &&
              (info['coverUrl'] ?? '').trim().isNotEmpty) {
            try {
              coverBytes = await fetchCoverBytesFromUrl(info['coverUrl']!);
            } catch (_) {}
          }
          final ok = await widget.applyMetadata!(
            book['id'] as String,
            info,
            coverBytes,
          );
          if (!mounted) return;
          if (ok) {
            found++;
            books = books.map((b) {
              if (b['id'] != book['id']) return b;
              final copy = Map<String, dynamic>.from(b);
              void fillField(String key, String? val) {
                if ((copy[key] ?? '').toString().trim().isEmpty &&
                    val != null &&
                    val.trim().isNotEmpty) {
                  copy[key] = val.trim();
                }
              }

              if (missingQualityField(copy, DataQualityField.author) &&
                  (info!['author'] ?? '').trim().isNotEmpty) {
                copy['author'] = info['author']!.trim();
              }
              fillField('isbn', info!['isbn']);
              fillField('publisher', info['publisher']);
              fillField('category', info['category']);
              fillField('pageCount', info['pageCount']);
              fillField('publicationYear', info['publicationYear']);
              fillField('language', info['language']);
              fillField('edition', info['edition']);
              if (coverBytes != null &&
                  missingQualityField(copy, DataQualityField.cover) &&
                  !coverFieldLocked(copy)) {
                copy['coverBase64'] = storeCoverBytes(coverBytes);
              }
              return copy;
            }).toList();
          } else {
            missing++;
          }
        }
      } catch (_) {
        failed++;
      }
      if (mounted) setState(() {});
      if (!stopRequested && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      summary =
          '$found kitap kaydı güncellendi, $missing kayıtta yeni bilgi bulunamadı, $failed işlem başarısız${stopRequested ? ' (duraklatıldı)' : ''}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final counts = qualityCounts(books);
    final total = books.where(isQualityCandidate).length;
    final pendingCovers = books.where(_bookEligibleForCover).length;
    final pendingMeta = books.where(eligibleForMetadataEnrichment).length;
    final lockedCount = books
        .where(
          (book) =>
              missingQualityField(book, DataQualityField.cover) &&
              coverFieldLocked(book),
        )
        .length;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Eksik alan panosu')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Aktif kayıt: $total',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Bir alanı seçerek ilgili kitapları listeleyebilir ve kayıtları düzenleyebilirsiniz. Çöp kutusu ve koleksiyondan düşülen kayıtlar sayılmaz.',
            ),
            for (final field in DataQualityField.values)
              ListTile(
                title: Text(field.label),
                trailing: Text('${counts[field]}'),
                subtitle: counts[field] == 0
                    ? null
                    : const Text('Kitapları göster'),
                onTap: busy || counts[field] == 0
                    ? null
                    : () => Navigator.pop(context, field),
              ),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(
                'İşleniyor: $found güncellendi, $missing bulunamadı, $failed başarısız.',
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: stopRequested
                    ? null
                    : () => setState(() => stopRequested = true),
                icon: const Icon(Icons.pause),
                label: Text(stopRequested ? 'Duraklatılıyor…' : 'Duraklat'),
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: 8),
              Text(
                summary!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
            if (widget.applyMetadata != null) ...[
              const Divider(height: 24),
              Text(
                'Eksik künye bilgilerini tamamla',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'ISBN olan kitaplar Amazon, Google Books ve Open Library üzerinden; ISBN olmayan kitaplar ise Kitapyurdu (başlık, yazar, yayınevi) üzerinden aranır. Yalnızca boş alanlar doldurulur.',
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: busy || pendingMeta == 0 ? null : fillMetadata,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: Text('Eksik künyeleri tamamla ($pendingMeta)'),
              ),
            ],
            if (widget.applyCover != null) ...[
              const Divider(height: 24),
              Text(
                'Eksik kapakları tamamla',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Amazon, Kitapyurdu, Open Library ve Google Books üzerinden kapak aranır. Mevcut ve kilitli kapaklar korunur; her bulunan kapak ayrı kaydedilir.',
              ),
              if (lockedCount > 0)
                Text(
                  '$lockedCount kapak alanı kilitli; otomatik değiştirilmez.',
                ),
              if (pendingCovers == 0 && (counts[DataQualityField.cover] ?? 0) > 0)
                const Text('İndirilebilecek uygun kitap kaydı yok.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy || pendingCovers == 0 ? null : fillCovers,
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text('Eksik kapakları indir ($pendingCovers)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
