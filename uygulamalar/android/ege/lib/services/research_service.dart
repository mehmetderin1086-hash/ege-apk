// Deep research pipeline for JARVIS: plan queries with an LLM, search the web,
// read the best sources concurrently and let the LLM write a cited Turkish
// Markdown report. Network/LLM failures never throw; they end up in
// [ResearchReport.error].

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'web_tools.dart';

typedef ResearchLlm = Future<String> Function(String prompt);

class ResearchProgress {
  /// 'plan' | 'search' | 'read' | 'write' | 'done' | 'error'
  final String stage;
  final String message;
  final int sourcesFound;
  final int sourcesRead;

  /// 0..1
  final double fraction;

  const ResearchProgress({
    required this.stage,
    required this.message,
    this.sourcesFound = 0,
    this.sourcesRead = 0,
    this.fraction = 0,
  });

  @override
  String toString() => 'ResearchProgress($stage, ${(fraction * 100).round()}%, $message)';
}

class ResearchSource {
  final int index;
  final String title;
  final String url;
  final String excerpt;

  const ResearchSource({
    required this.index,
    required this.title,
    required this.url,
    this.excerpt = '',
  });
}

class ResearchReport {
  final String question;
  final String markdown;
  final List<ResearchSource> sources;
  final List<String> queries;
  final Duration elapsed;
  final String? error;

  bool get ok => error == null;

  const ResearchReport({
    required this.question,
    this.markdown = '',
    this.sources = const [],
    this.queries = const [],
    this.elapsed = Duration.zero,
    this.error,
  });
}

class _Candidate {
  final String title;
  final String url;
  final String snippet;
  final String? fallbackText;
  const _Candidate(this.title, this.url, {this.snippet = '', this.fallbackText});
}

class _Doc {
  final String title;
  final String url;
  final String text;
  const _Doc(this.title, this.url, this.text);
}

class DeepResearchService {
  DeepResearchService._();

  static const _cancelMessage = 'İptal edildi';

  static Future<ResearchReport> run({
    required String question,
    required ResearchLlm llm,
    http.Client? client,
    int maxQueries = 4,
    int maxSources = 8,
    int maxCharsPerSource = 6000,
    void Function(ResearchProgress p)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sw = Stopwatch()..start();
    final q = question.trim();
    var queries = <String>[];
    var sources = <ResearchSource>[];
    var found = 0;
    var read = 0;

    void emit(String stage, String message, double fraction) {
      try {
        onProgress?.call(ResearchProgress(
          stage: stage,
          message: message,
          sourcesFound: found,
          sourcesRead: read,
          fraction: fraction.clamp(0.0, 1.0).toDouble(),
        ));
      } catch (_) {
        // A faulty listener must not break the pipeline.
      }
    }

    bool cancelled() {
      try {
        return isCancelled?.call() ?? false;
      } catch (_) {
        return false;
      }
    }

    ResearchReport fail(String error) {
      emit('error', error, 1);
      return ResearchReport(
        question: q,
        sources: sources,
        queries: queries,
        elapsed: sw.elapsed,
        error: error,
      );
    }

    if (q.isEmpty) return fail('Araştırma sorusu boş.');
    final own = client == null;
    final c = client ?? http.Client();
    try {
      // (1) Plan -----------------------------------------------------------
      emit('plan', 'Araştırma planlanıyor…', 0.02);
      final maxQ = maxQueries < 1 ? 1 : maxQueries;
      var planOut = '';
      try {
        planOut = await llm(_planPrompt(q, maxQ));
      } catch (_) {
        planOut = '';
      }
      queries = parseQueries(planOut, fallback: q, max: maxQ);
      if (cancelled()) return fail(_cancelMessage);
      emit('plan', '${queries.length} arama sorgusu hazırlandı.', 0.1);

      // (2) Search ---------------------------------------------------------
      emit('search', 'Web\'de aranıyor…', 0.12);
      var doneQueries = 0;
      final searchFutures = queries.map((query) async {
        final r = await WebTools.search(query, client: c, limit: 6);
        doneQueries++;
        emit('search', 'Arandı: "$query" (${r.length} sonuç)', 0.12 + 0.16 * doneQueries / queries.length);
        return r;
      }).toList();
      final wikiFuture = WebTools.wikipediaSummary(_wikiTopic(q), client: c);
      final perQuery = await Future.wait(searchFutures);
      final wiki = await wikiFuture;
      if (cancelled()) return fail(_cancelMessage);

      final candidates = _selectCandidates(perQuery, wiki, maxSources < 1 ? 1 : maxSources);
      found = candidates.length;
      emit('search', '$found kaynak bulundu.', 0.3);
      if (cancelled()) return fail(_cancelMessage);

      // (3) Read -----------------------------------------------------------
      final docs = <_Doc>[];
      for (var i = 0; i < candidates.length; i += 3) {
        if (cancelled()) return fail(_cancelMessage);
        final batch = candidates.sublist(i, i + 3 > candidates.length ? candidates.length : i + 3);
        final results = await Future.wait(batch.map((cand) => _read(cand, c, maxCharsPerSource)));
        for (final d in results) {
          if (d != null) docs.add(d);
        }
        read = docs.length;
        final processed = i + batch.length;
        emit('read', '$processed/${candidates.length} kaynak tarandı, $read okundu.',
            0.3 + 0.45 * processed / (candidates.isEmpty ? 1 : candidates.length));
      }
      if (candidates.isEmpty) emit('read', 'Okunacak kaynak bulunamadı.', 0.75);
      sources = [
        for (var i = 0; i < docs.length; i++)
          ResearchSource(index: i + 1, title: docs[i].title, url: docs[i].url, excerpt: _excerpt(docs[i].text)),
      ];
      if (cancelled()) return fail(_cancelMessage);

      // (4) Write ----------------------------------------------------------
      emit('write', 'Rapor yazılıyor…', 0.8);
      String body;
      try {
        body = await llm(docs.isEmpty ? _noSourcePrompt(q) : _writePrompt(q, docs));
      } catch (e) {
        return fail('Rapor yazılamadı: $e');
      }
      if (cancelled()) return fail(_cancelMessage);
      body = _cleanBody(body);
      if (body.isEmpty) return fail('Model boş bir rapor döndürdü.');
      if (docs.isEmpty && !body.toLowerCase().contains('kaynak doğrulanamadı')) {
        body = '> ⚠️ Not: kaynak doğrulanamadı — web kaynakları okunamadığı için bu yanıt genel bilgiye dayanır.\n\n$body';
      }
      final md = StringBuffer(body)..write('\n\n## Kaynaklar\n\n');
      if (sources.isEmpty) {
        md.write('_Okunabilir kaynak bulunamadı (kaynak doğrulanamadı)._');
      } else {
        md.write(sources.map((s) => '[${s.index}] ${s.title} — ${s.url}').join('\n\n'));
      }
      emit('done', 'Araştırma tamamlandı.', 1);
      return ResearchReport(
        question: q,
        markdown: md.toString(),
        sources: sources,
        queries: queries,
        elapsed: sw.elapsed,
      );
    } catch (e) {
      return fail('Araştırma başarısız: $e');
    } finally {
      if (own) c.close();
    }
  }

  // -------------------------------------------------------------------------
  // Query parsing
  // -------------------------------------------------------------------------

  /// Accepts a JSON array, a JSON object {"queries":[...]}, ```json fences or
  /// numbered / bulleted lines. Falls back to `[fallback]`.
  static List<String> parseQueries(String llmOutput, {required String fallback, int max = 4}) {
    final limit = max < 1 ? 1 : max;
    var s = llmOutput.trim();
    final fence = RegExp(r'```(?:json|JSON)?\s*([\s\S]*?)```').firstMatch(s);
    if (fence != null) s = fence.group(1)!.trim();

    final out = <String>[];
    final seen = <String>{};
    void add(String raw) {
      var v = raw.trim();
      v = v.replaceAll(RegExp(r'''^["'`“”‘’]+|["'`“”‘’,]+$'''), '').trim();
      v = v.replaceAll(RegExp(r'\s+'), ' ');
      if (v.isEmpty || v.length > 200) return;
      if (seen.add(v.toLowerCase())) out.add(v);
    }

    void addJsonItems(List list) {
      for (final item in list) {
        if (item is String) {
          add(item);
        } else if (item is Map) {
          final v = item['query'] ?? item['q'] ?? item['sorgu'];
          if (v is String) add(v);
        }
      }
    }

    var parsedJson = false;
    final lb = s.indexOf('[');
    final rb = s.lastIndexOf(']');
    if (lb >= 0 && rb > lb) {
      try {
        final j = jsonDecode(s.substring(lb, rb + 1));
        if (j is List) {
          addJsonItems(j);
          parsedJson = true;
        }
      } catch (_) {
        parsedJson = false;
      }
    }
    if (!parsedJson) {
      final lc = s.indexOf('{');
      final rc = s.lastIndexOf('}');
      if (lc >= 0 && rc > lc) {
        try {
          final j = jsonDecode(s.substring(lc, rc + 1));
          if (j is Map) {
            final list = j['queries'] ?? j['sorgular'] ?? j['searches'];
            if (list is List) {
              addJsonItems(list);
              parsedJson = true;
            }
          }
        } catch (_) {
          parsedJson = false;
        }
      }
    }
    if (!parsedJson) {
      final marker = RegExp(r'^\s*(?:[-*•]|\d+[.)]|\(\d+\))\s+');
      final lines = s.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final marked = lines.where(marker.hasMatch).toList();
      final use = marked.isNotEmpty ? marked : lines;
      for (final l in use) {
        final v = l.replaceFirst(marker, '');
        if (v.endsWith(':')) continue;
        add(v);
      }
    }
    if (out.isEmpty) {
      final f = fallback.trim();
      return f.isEmpty ? <String>[] : [f];
    }
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// URL key for deduplication: no scheme/www/fragment/utm_*, no trailing '/'.
  static String normalizeUrlKey(String url) {
    final raw = url.trim();
    try {
      final u = Uri.parse(raw);
      var host = u.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      if (host.startsWith('m.')) host = host.substring(2);
      var path = u.path;
      while (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      final params = u.queryParametersAll.entries
          .where((e) {
            final k = e.key.toLowerCase();
            return !k.startsWith('utm_') && k != 'fbclid' && k != 'gclid' && k != 'ref';
          })
          .map((e) => '${e.key}=${e.value.join(',')}')
          .toList()
        ..sort();
      return params.isEmpty ? '$host$path' : '$host$path?${params.join('&')}';
    } catch (_) {
      return raw.toLowerCase();
    }
  }

  static String _domainOf(String url) {
    var h = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (h.startsWith('www.')) h = h.substring(4);
    return h;
  }

  static List<_Candidate> _selectCandidates(
      List<List<SearchResult>> perQuery, ({String title, String extract, String url})? wiki, int maxSources) {
    final out = <_Candidate>[];
    final seen = <String>{};
    final perDomain = <String, int>{};
    if (wiki != null) {
      out.add(_Candidate(wiki.title, wiki.url, snippet: wiki.extract, fallbackText: wiki.extract));
      seen.add(normalizeUrlKey(wiki.url));
      final d = _domainOf(wiki.url);
      perDomain[d] = (perDomain[d] ?? 0) + 1;
    }
    // Round-robin across queries for diversity.
    final ordered = <SearchResult>[];
    var depth = 0;
    var added = true;
    while (added) {
      added = false;
      for (final list in perQuery) {
        if (depth < list.length) {
          ordered.add(list[depth]);
          added = true;
        }
      }
      depth++;
    }
    final skipped = <SearchResult>[];
    for (final r in ordered) {
      if (out.length >= maxSources) break;
      final key = normalizeUrlKey(r.url);
      if (seen.contains(key)) continue;
      final d = _domainOf(r.url);
      if ((perDomain[d] ?? 0) >= 2) {
        skipped.add(r);
        continue;
      }
      seen.add(key);
      perDomain[d] = (perDomain[d] ?? 0) + 1;
      out.add(_Candidate(r.title, r.url, snippet: r.snippet));
    }
    // Relax the domain cap only when not enough diverse sources exist.
    for (final r in skipped) {
      if (out.length >= maxSources) break;
      final key = normalizeUrlKey(r.url);
      if (!seen.add(key)) continue;
      out.add(_Candidate(r.title, r.url, snippet: r.snippet));
    }
    return out.length > maxSources ? out.sublist(0, maxSources) : out;
  }

  static Future<_Doc?> _read(_Candidate cand, http.Client c, int maxChars) async {
    String text = '';
    String title = cand.title;
    try {
      final page = await WebTools.fetchPage(cand.url, client: c, maxBytes: 2500000);
      if (page.ok) {
        text = page.text.trim();
        if (page.title.trim().isNotEmpty) title = page.title.trim();
      }
    } catch (_) {
      text = '';
    }
    if (text.length < 80 && cand.fallbackText != null) text = cand.fallbackText!.trim();
    if (text.length < 80) return null;
    if (text.length > maxChars) text = '${text.substring(0, maxChars)}…';
    return _Doc(title.isEmpty ? cand.url : title, cand.url, text);
  }

  static String _excerpt(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 300 ? flat : '${flat.substring(0, 300)}…';
  }

  static String _wikiTopic(String q) {
    var t = q.replaceAll(RegExp(r'[?!.]+$'), '').trim();
    t = t.replaceAll(
        RegExp(r'\b(nedir|kimdir|nelerdir|ne demek|ne demektir|nasıl çalışır|hakkında bilgi ver|hakkında|anlat)\b',
            caseSensitive: false),
        ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? q : t;
  }

  static String _cleanBody(String raw) {
    var s = raw.trim();
    final fence = RegExp(r'^```(?:markdown|md)?\s*\n([\s\S]*?)\n?```$').firstMatch(s);
    if (fence != null) s = fence.group(1)!.trim();
    // Drop a sources section written by the model; we append our own.
    final m = RegExp(r'^#{1,3}\s*(Kaynaklar|Kaynakça|Sources|References)\s*$', multiLine: true, caseSensitive: false)
        .firstMatch(s);
    if (m != null && m.start > 0) s = s.substring(0, m.start).trimRight();
    return s;
  }

  static String _today() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static String _planPrompt(String q, int maxQueries) {
    final minQ = maxQueries < 3 ? maxQueries : 3;
    return 'Sen bir araştırma planlayıcısısın. Aşağıdaki soruyu kapsamlı biçimde araştırmak için '
        '$minQ-$maxQueries adet, birbirinden farklı açıları kapsayan web arama sorgusu üret. '
        'Uygun olduğunda Türkçe ve İngilizce sorguları karıştır; kısa ve arama motoruna uygun yaz.\n'
        'YALNIZCA bir JSON dizisi döndür, örneğin: ["sorgu 1", "sorgu 2", "sorgu 3"]. '
        'Başka hiçbir açıklama, başlık veya kod bloğu yazma.\n\n'
        'Bugünün tarihi: ${_today()}\n'
        'Soru: $q';
  }

  static String _writePrompt(String q, List<_Doc> docs) {
    final sb = StringBuffer()
      ..writeln('Sen titiz bir araştırma analistisin. Aşağıdaki soruyu YALNIZCA verilen numaralı kaynaklara '
          'dayanarak yanıtla.')
      ..writeln()
      ..writeln('Soru: $q')
      ..writeln('Bugünün tarihi: ${_today()}')
      ..writeln()
      ..writeln('Kurallar:')
      ..writeln('- Türkçe, ayrıntılı ve iyi yapılandırılmış bir Markdown rapor yaz.')
      ..writeln('- Yapı: "# <Başlık>", "## Kısa Özet (TL;DR)", "## Ana Bulgular", konu uygunsa '
          '"## Karşılaştırma" (Markdown tablosu), "## Belirsizlikler ve Çelişkiler", "## Sonuç".')
      ..writeln('- Her önemli bilgiden sonra ilgili kaynağı köşeli parantezle göster: [1], [2] gibi. '
          'Numaralar aşağıdaki kaynak numaralarıyla aynı olmalı.')
      ..writeln('- Kaynaklarda olmayan bilgiyi uydurma; bilgi yetersizse bunu açıkça belirt.')
      ..writeln('- Kaynaklar birbiriyle çelişiyorsa bunu belirt.')
      ..writeln('- "Kaynaklar" bölümü yazma; o bölüm otomatik eklenecek.')
      ..writeln()
      ..writeln('Kaynaklar:');
    for (var i = 0; i < docs.length; i++) {
      final d = docs[i];
      sb
        ..writeln()
        ..writeln('[${i + 1}] ${d.title}')
        ..writeln('URL: ${d.url}')
        ..writeln('İçerik:')
        ..writeln(d.text);
    }
    return sb.toString();
  }

  static String _noSourcePrompt(String q) =>
      'Web kaynaklarına erişilemedi. Aşağıdaki soruyu genel bilginle, Türkçe ve Markdown formatında yanıtla '
      '(başlık, kısa özet, ana noktalar, sonuç). Raporun en başına şu satırı aynen ekle:\n'
      '"> ⚠️ Not: kaynak doğrulanamadı — bu yanıt web kaynaklarıyla doğrulanmadı, genel bilgiye dayanır."\n'
      'Emin olmadığın noktaları açıkça belirt ve güncel olmayabilecek bilgiler için uyar.\n\n'
      'Bugünün tarihi: ${_today()}\n'
      'Soru: $q';
}
