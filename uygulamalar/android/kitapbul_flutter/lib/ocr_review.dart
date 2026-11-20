import 'package:flutter/material.dart';
import 'ocr_extract.dart';
export 'ocr_extract.dart' show isbnInOcrLine;

/// Every field change is chosen by the user; recognition never overwrites it silently.
class OcrReview extends StatefulWidget {
  const OcrReview({
    super.key,
    required this.pages,
    this.failedSources = const [],
    required this.applyLine,
    required this.applySuggestions,
  });
  final List<OcrPage> pages;
  final List<String> failedSources;
  final Future<String> Function(String field, String value) applyLine;
  final Future<String> Function(Map<String, String> values) applySuggestions;
  @override
  State<OcrReview> createState() => _OcrReviewState();
}

class _OcrReviewState extends State<OcrReview> {
  String? message;
  bool applying = false;
  late final List<SourcedOcrSuggestion> suggestions;
  final selected = <String, int>{};

  @override
  void initState() {
    super.initState();
    suggestions = combineOcrSuggestions(widget.pages);
    for (var i = 0; i < suggestions.length; i++) {
      final item = suggestions[i].suggestion;
      if (!item.heuristic &&
          suggestions.where((s) => s.suggestion.field == item.field).length ==
              1)
        selected[item.field] = i;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLines = widget.pages.any(
      (page) => page.document.lines.any((line) => line.text.trim().isNotEmpty),
    );
    const fields = {
      'title': 'Kitap adına',
      'author': 'Yazara',
      'publisher': 'Yayınevine',
      'isbn': 'ISBN alanına',
      'publicationYear': 'Yayın yılına',
      'pageCount': 'Sayfa sayısına',
      'edition': 'Baskı bilgisine',
      'notes': 'Notlara ekle',
    };
    return AlertDialog(
      title: const Text('Okunan metni kontrol et'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          children: [
            if (message != null)
              Text(
                message!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            if (widget.failedSources.isNotEmpty)
              Text(
                '${widget.failedSources.join(', ')} okunamadı; diğer görsellerin sonucu gösteriliyor.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const Divider(),
            Expanded(
              child: !hasLines
                  ? const Center(
                      child: Text('Görselde okunabilir metin bulunamadı.'),
                    )
                  : ListView(
                      children: [
                        const Text(
                          'Önerileri kontrol edin; tahmini alanlar seçim bekler. Yalnızca boş alanlar doldurulur.',
                        ),
                        if (suggestions.isNotEmpty) ...[
                          for (
                            var index = 0;
                            index < suggestions.length;
                            index++
                          )
                            CheckboxListTile(
                              value:
                                  selected[suggestions[index]
                                      .suggestion
                                      .field] ==
                                  index,
                              onChanged: applying
                                  ? null
                                  : (checked) => setState(() {
                                      if (checked == true) {
                                        selected[suggestions[index]
                                                .suggestion
                                                .field] =
                                            index;
                                      } else {
                                        selected.remove(
                                          suggestions[index].suggestion.field,
                                        );
                                      }
                                    }),
                              title: Text(
                                '${fields[suggestions[index].suggestion.field] ?? suggestions[index].suggestion.field}: ${suggestions[index].suggestion.value}',
                              ),
                              subtitle: Text(
                                '${suggestions[index].sources.join(', ')}${suggestions[index].suggestion.heuristic ? ' · Tahmin; kontrol edin' : ''}${suggestions.where((s) => s.suggestion.field == suggestions[index].suggestion.field).length > 1 ? ' · Farklı adaylar var' : ''}',
                              ),
                            ),
                          TextButton(
                            onPressed: applying || selected.isEmpty
                                ? null
                                : () async {
                                    setState(() => applying = true);
                                    final result = await widget
                                        .applySuggestions({
                                          for (final selection
                                              in selected.entries)
                                            selection.key:
                                                suggestions[selection.value]
                                                    .suggestion
                                                    .value,
                                        });
                                    if (mounted)
                                      setState(() {
                                        applying = false;
                                        message = result;
                                      });
                                  },
                            child: const Text(
                              'Seçilenleri boş alanlara uygula',
                            ),
                          ),
                        ],
                        const Text(
                          'İsterseniz bir satırın menüsünden alanı kendiniz seçin.',
                        ),
                        for (final page in widget.pages) ...[
                          if (widget.pages.length > 1)
                            Text(
                              page.source,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          for (final line
                              in page.document.lines
                                  .map((line) => line.text.trim())
                                  .where((line) => line.isNotEmpty)
                                  .take(200))
                            ListTile(
                              title: SelectableText(line),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Satırı alana aktar',
                                enabled: !applying,
                                onSelected: (field) async {
                                  var value = line;
                                  if (field == 'isbn') {
                                    final matches = isbnsInOcrLine(line);
                                    if (matches.isEmpty) {
                                      setState(
                                        () => message =
                                            'Bu satırda geçerli ISBN bulunamadı.',
                                      );
                                      return;
                                    }
                                    if (matches.length > 1) {
                                      setState(
                                        () => message =
                                            'Bu satırda birden fazla ISBN var; önerilerden birini seçin.',
                                      );
                                      return;
                                    }
                                    value = matches.single;
                                  }
                                  setState(() => applying = true);
                                  final result = await widget.applyLine(
                                    field,
                                    value,
                                  );
                                  if (mounted)
                                    setState(() {
                                      applying = false;
                                      message = result;
                                    });
                                },
                                itemBuilder: (_) => fields.entries
                                    .map(
                                      (entry) => PopupMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: applying ? null : () => Navigator.pop(context),
          child: const Text('Bitti'),
        ),
      ],
    );
  }
}
