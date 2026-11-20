import 'catalog_search.dart' show foldTurkish;
import 'isbn.dart';

List<String> isbnsInOcrLine(String text) {
  final result = <String>[];
  for (final match in RegExp(
    r'(?<!\d)(?:97[89](?:[ -]*\d){10}|(?:\d[ -]*){9}[\dXx])(?!\d)',
  ).allMatches(text)) {
    final canonical = canonicalIsbn(match.group(0)!.trim());
    if (canonical != null && !result.contains(canonical)) result.add(canonical);
  }
  return result;
}

String? isbnInOcrLine(String text) => isbnsInOcrLine(text).firstOrNull;

class OcrLine {
  const OcrLine(this.text, {this.height = 0});
  final String text;
  final double height;
}

class OcrDocument {
  const OcrDocument(this.text, this.lines);
  final String text;
  final List<OcrLine> lines;
  factory OcrDocument.fromPlatform(Object? value) {
    if (value is String)
      return OcrDocument(
        value,
        value.split(RegExp(r'\r?\n')).map((s) => OcrLine(s)).toList(),
      );
    if (value is! Map || value['text'] is! String || value['lines'] is! List)
      throw const FormatException('OCR sonucu geçersiz');
    final lines = <OcrLine>[];
    for (final item in (value['lines'] as List).take(200)) {
      if (item is! Map ||
          item['text'] is! String ||
          (item['height'] != null && item['height'] is! num))
        throw const FormatException('OCR satırı geçersiz');
      lines.add(
        OcrLine(
          item['text'] as String,
          height: (item['height'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    final text = value['text'] as String;
    if (lines.isEmpty && text.trim().isNotEmpty) {
      lines.addAll(
        text.split(RegExp(r'\r?\n')).take(200).map((s) => OcrLine(s)),
      );
    }
    return OcrDocument(text, lines);
  }
}

class OcrSuggestion {
  const OcrSuggestion(this.field, this.value, {this.heuristic = false});
  final String field, value;
  final bool heuristic;
}

class OcrPage {
  const OcrPage(this.source, this.document);
  final String source;
  final OcrDocument document;
}

class SourcedOcrSuggestion {
  const SourcedOcrSuggestion(this.suggestion, this.sources);
  final OcrSuggestion suggestion;
  final List<String> sources;
}

/// Distinct values stay separate; identical values from several images are combined.
List<SourcedOcrSuggestion> combineOcrSuggestions(List<OcrPage> pages) {
  final results = <SourcedOcrSuggestion>[];
  for (final page in pages) {
    for (final suggestion in suggestBookFields(
      page.document,
      source: page.source,
    )) {
      final index = results.indexWhere(
        (entry) =>
            entry.suggestion.field == suggestion.field &&
            foldTurkish(entry.suggestion.value.trim()) ==
                foldTurkish(suggestion.value.trim()),
      );
      if (index < 0) {
        results.add(SourcedOcrSuggestion(suggestion, [page.source]));
      } else {
        final previous = results[index];
        results[index] = SourcedOcrSuggestion(
          OcrSuggestion(
            previous.suggestion.field,
            previous.suggestion.value,
            heuristic: previous.suggestion.heuristic && suggestion.heuristic,
          ),
          [
            ...previous.sources,
            if (!previous.sources.contains(page.source)) page.source,
          ],
        );
      }
    }
  }
  final confirmedAuthors = results
      .where(
        (entry) =>
            entry.suggestion.field == 'author' && !entry.suggestion.heuristic,
      )
      .toList();
  if (confirmedAuthors.length == 1) {
    final author = foldTurkish(confirmedAuthors.single.suggestion.value.trim());
    final authorWords = author.split(RegExp(r'\s+')).length;
    for (var i = 0; i < results.length; i++) {
      final current = results[i];
      if (current.suggestion.field != 'title' || !current.suggestion.heuristic)
        continue;
      final words = current.suggestion.value.split(RegExp(r'\s+'));
      if (words.length <= authorWords) continue;
      final prefix = foldTurkish(words.take(authorWords).join(' '));
      final suffix = foldTurkish(
        words.skip(words.length - authorWords).join(' '),
      );
      final remaining = prefix == author
          ? words.skip(authorWords).join(' ')
          : suffix == author
          ? words.take(words.length - authorWords).join(' ')
          : '';
      if (remaining.trim().length >= 3)
        results[i] = SourcedOcrSuggestion(
          OcrSuggestion('title', remaining, heuristic: true),
          current.sources,
        );
    }
  }
  final merged = <SourcedOcrSuggestion>[];
  for (final current in results) {
    final index = merged.indexWhere(
      (entry) =>
          entry.suggestion.field == current.suggestion.field &&
          foldTurkish(entry.suggestion.value.trim()) ==
              foldTurkish(current.suggestion.value.trim()),
    );
    if (index < 0) {
      merged.add(current);
    } else {
      final previous = merged[index];
      merged[index] = SourcedOcrSuggestion(
        OcrSuggestion(
          previous.suggestion.field,
          previous.suggestion.value,
          heuristic:
              previous.suggestion.heuristic && current.suggestion.heuristic,
        ),
        [
          ...previous.sources,
          ...current.sources.where(
            (source) => !previous.sources.contains(source),
          ),
        ],
      );
    }
  }
  return merged;
}

/// Suggestions are reviewable, not authoritative metadata.
List<OcrSuggestion> suggestBookFields(
  OcrDocument document, {
  required String source,
}) {
  final lines = document.lines
      .map((line) => OcrLine(line.text.trim(), height: line.height))
      .where((line) => line.text.isNotEmpty)
      .toList();
  final found = <String, OcrSuggestion>{};
  final isbnCandidates = <String>{};
  void offer(String field, String value, {bool heuristic = false}) {
    final clean = value.trim();
    if (clean.isNotEmpty && clean.length <= 160)
      found.putIfAbsent(
        field,
        () => OcrSuggestion(field, clean, heuristic: heuristic),
      );
  }

  const labels = {
    'kitap adı': 'title',
    'kitap adi': 'title',
    'eser adı': 'title',
    'eser adi': 'title',
    'başlık': 'title',
    'baslik': 'title',
    'title': 'title',
    'yazar': 'author',
    'yazan': 'author',
    'author': 'author',
    'yayınevi': 'publisher',
    'yayinevi': 'publisher',
    'publisher': 'publisher',
  };
  for (var index = 0; index < lines.length; index++) {
    final text = lines[index].text;
    final matched = RegExp(r'^([^:：]{2,30})[:：]\s*(.*)$').firstMatch(text);
    if (matched != null) {
      final label = foldTurkish(matched.group(1)!.trim());
      final field = labels[label];
      if (field != null) {
        var value = matched.group(2)!.trim();
        if (value.isEmpty &&
            index + 1 < lines.length &&
            !lines[index + 1].text.contains(':'))
          value = lines[index + 1].text;
        offer(field, value);
      }
    }
    for (final isbn in isbnsInOcrLine(text)) {
      isbnCandidates.add(isbn);
      offer('isbn', isbn);
    }
    final folded = foldTurkish(text);
    if (!folded.contains('isbn') &&
        text.length <= 80 &&
        RegExp(
          r'(yayınevi|yayinevi|yayınları|yayinlari|yayıncılık|yayincilik)',
          caseSensitive: false,
        ).hasMatch(folded))
      offer('publisher', text, heuristic: true);
    if (!folded.contains('adet') &&
        (folded.contains('baskı') ||
            folded.contains('baski') ||
            folded.contains('yayın') ||
            folded.contains('yayin') ||
            folded.contains('copyright') ||
            folded.contains('©'))) {
      final year = RegExp(
        r'\b(?:19|20)\d{2}\b',
      ).allMatches(text).lastOrNull?.group(0);
      if (year != null) offer('publicationYear', year);
    }
    final page =
        RegExp(
          r'\b(\d{2,5})\s*(?:sayfa|pages?)\b',
          caseSensitive: false,
        ).firstMatch(folded)?.group(1) ??
        RegExp(
          r'(?:sayfa\s+say[ıi]s[ıi]|toplam\s+sayfa)\s*[:：]?\s*(\d{2,5})',
          caseSensitive: false,
        ).firstMatch(folded)?.group(1);
    if (page != null && int.parse(page) >= 20 && int.parse(page) <= 10000)
      offer('pageCount', page);
    final edition = RegExp(
      r'\b(\d{1,3})\.?\s*bask[ıi](?=$|[\s.,;:])',
      caseSensitive: false,
    ).firstMatch(folded)?.group(1);
    if (edition != null) offer('edition', '$edition. Baskı');
  }
  if (source == 'Kapak' && !found.containsKey('title')) {
    final candidates = lines.where((line) {
      final lower = foldTurkish(line.text);
      return line.height > 0 &&
          line.text.length >= 3 &&
          line.text.length <= 100 &&
          RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(line.text) &&
          !RegExp(r'\d').hasMatch(line.text) &&
          ![
            'isbn',
            'yayın',
            'yayin',
            'baskı',
            'baski',
            'çevir',
            'cevir',
            'yazar:',
            'author:',
            'www.',
            'http',
          ].any(lower.contains) &&
          line.text != found['author']?.value &&
          line.text != found['publisher']?.value;
    }).toList();
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.height.compareTo(a.height));
      final tallest = candidates.first;
      var start = lines.indexOf(tallest);
      var end = start;
      bool similar(OcrLine line) =>
          candidates.contains(line) &&
          (line.height - tallest.height).abs() / tallest.height < .30;
      while (start > 0 && end - start < 3 && similar(lines[start - 1])) start--;
      while (end + 1 < lines.length &&
          end - start < 3 &&
          similar(lines[end + 1]))
        end++;
      final titleLines = lines.sublist(start, end + 1);
      offer(
        'title',
        titleLines.map((line) => line.text).join(' '),
        heuristic: true,
      );
      final other = candidates
          .where(
            (line) =>
                !titleLines.contains(line) &&
                line.text.split(RegExp(r'\s+')).length <= 5,
          )
          .toList();
      if (!found.containsKey('author') && other.isNotEmpty)
        offer('author', other.first.text, heuristic: true);
    }
  }
  return [
    ...found.values,
    for (final isbn in isbnCandidates)
      if (isbn != found['isbn']?.value) OcrSuggestion('isbn', isbn),
  ];
}
