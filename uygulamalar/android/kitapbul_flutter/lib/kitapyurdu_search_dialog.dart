import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'book_lookup.dart';
import 'cover_fetch.dart';

class FetchedBookData {
  const FetchedBookData({required this.metadata, this.coverBytes});

  final Map<String, String> metadata;
  final Uint8List? coverBytes;
}

class KitapyurduSearchDialog extends StatefulWidget {
  const KitapyurduSearchDialog({
    super.key,
    this.initialTitle = '',
    this.initialAuthor = '',
    this.initialPublisher = '',
  });

  final String initialTitle;
  final String initialAuthor;
  final String initialPublisher;

  @override
  State<KitapyurduSearchDialog> createState() => _KitapyurduSearchDialogState();
}

class _KitapyurduSearchDialogState extends State<KitapyurduSearchDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  late final TextEditingController _author = TextEditingController(
    text: widget.initialAuthor,
  );
  late final TextEditingController _publisher = TextEditingController(
    text: widget.initialPublisher,
  );

  List<KitapyurduCandidate> _results = const [];
  bool _searching = false;
  String? _selectingId;
  String? _error;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    if (_title.text.trim().isNotEmpty ||
        _author.text.trim().isNotEmpty ||
        _publisher.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _publisher.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    if (_searching || _selectingId != null) return;
    final t = _title.text.trim();
    final a = _author.text.trim();
    final p = _publisher.text.trim();
    if (t.isEmpty && a.isEmpty && p.isEmpty) {
      setState(() {
        _error = 'En az bir alan (kitap adı, yazar veya yayınevi) girin.';
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _hasSearched = true;
    });
    try {
      final found = await searchKitapyurdu(
        title: t,
        author: a,
        publisher: p,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error =
            'Kitapyurdu araması tamamlanamadı. İnternet bağlantısını kontrol edin.';
      });
    }
  }

  Future<void> _selectCandidate(KitapyurduCandidate candidate) async {
    if (_selectingId != null) return;
    setState(() {
      _selectingId = candidate.productId;
      _error = null;
    });
    try {
      Map<String, String>? detail;
      try {
        detail = await fetchKitapyurduDetail(candidate.detailUrl);
      } catch (_) {
        // Fallback to search card data if detail page cannot be fetched.
      }
      final merged = <String, String>{
        'source': 'Kitapyurdu',
        'title': (detail?['title'] ?? '').trim().isNotEmpty
            ? detail!['title']!
            : candidate.title,
        'author': (detail?['author'] ?? '').trim().isNotEmpty
            ? detail!['author']!
            : candidate.author,
        'publisher': (detail?['publisher'] ?? '').trim().isNotEmpty
            ? detail!['publisher']!
            : candidate.publisher,
        'category': detail?['category'] ?? '',
        'publicationYear': detail?['publicationYear'] ?? '',
        'pageCount': detail?['pageCount'] ?? '',
        'edition': detail?['edition'] ?? '',
        'language': detail?['language'] ?? '',
        if ((detail?['isbn'] ?? '').trim().isNotEmpty) 'isbn': detail!['isbn']!,
        if ((detail?['coverUrl'] ?? candidate.coverUrl).trim().isNotEmpty)
          'coverUrl': (detail?['coverUrl'] ?? '').trim().isNotEmpty
              ? detail!['coverUrl']!
              : candidate.coverUrl,
      };
      Uint8List? coverBytes;
      final coverUrl = (merged['coverUrl'] ?? '').trim();
      if (coverUrl.isNotEmpty) {
        try {
          coverBytes = await fetchCoverBytesFromUrl(coverUrl);
        } catch (_) {
          // Metadata still succeeds even if cover image fails to download.
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        FetchedBookData(metadata: merged, coverBytes: coverBytes),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectingId = null;
        _error = 'Seçilen kitabın künyesi alınamadı. Tekrar deneyin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _searching || _selectingId != null;
    return AlertDialog(
      title: const Text("Kitapyurdu'ndan kitap bul"),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              enabled: !busy,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: const InputDecoration(
                labelText: 'Kitap adı (başlık)',
                prefixIcon: Icon(Icons.menu_book_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _author,
                    enabled: !busy,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: const InputDecoration(
                      labelText: 'Yazar',
                      prefixIcon: Icon(Icons.person_outline),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _publisher,
                    enabled: !busy,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: const InputDecoration(
                      labelText: 'Yayınevi',
                      prefixIcon: Icon(Icons.business_outlined),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : _runSearch,
              icon: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(
                _searching
                    ? 'Kitapyurdu taranıyor…'
                    : _selectingId != null
                    ? 'Künye ve kapak indiriliyor…'
                    : "Kitapyurdu'nda ara",
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Divider(height: 18),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : !_hasSearched
                  ? const Center(
                      child: Text(
                        'Kitap adı, yazar veya yayınevi girerek arama yapın.\nSeçtiğiniz baskının ISBN, sayfa sayısı, yayın yılı, kategori ve kapak görseli otomatik getirilir.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _results.isEmpty
                  ? const Center(
                      child: Text(
                        'Eşleşen baskı bulunamadı. Daha kısa bir başlık veya yazar adıyla tekrar deneyin.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final item = _results[index];
                        final selectingThis = _selectingId == item.productId;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          leading: SizedBox(
                            width: 42,
                            height: 60,
                            child: item.coverUrl.isEmpty
                                ? const Icon(Icons.menu_book_outlined)
                                : Image.network(
                                    item.coverUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.menu_book_outlined),
                                  ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (item.author.isNotEmpty) item.author,
                              if (item.publisher.isNotEmpty) item.publisher,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selectingThis
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_outlined),
                          enabled: !busy,
                          onTap: busy ? null : () => _selectCandidate(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _selectingId != null
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}
