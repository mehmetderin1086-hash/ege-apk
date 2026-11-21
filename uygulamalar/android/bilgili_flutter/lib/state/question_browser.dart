import 'dart:async';
import 'dart:isolate';

import '../data/advanced/catalog.dart';
import '../models/quiz_models.dart';

typedef BrowserCursor = ({int personal, int academic});
const firstBrowserPage = (personal: 0, academic: 0);

class BrowserPage {
  final List<Question> items;
  final BrowserCursor next;
  final bool hasMore;
  const BrowserPage(this.items, this.next, this.hasMore);
}

bool _hasText(Question q, String query) =>
    q.text.toLowerCase().contains(query) ||
    q.explanation.toLowerCase().contains(query) ||
    (q.creation?.brief.toLowerCase().contains(query) ?? false) ||
    q.options.any((o) => o.toLowerCase().contains(query));

typedef _SearchRequest = ({
  SendPort reply,
  Topic topic,
  QuestionFormat format,
  PoolCollection collection,
  BloomLevel? bloom,
  String query,
  Set<String> hidden,
  int start,
  int limit,
});

// Only the small result index list crosses isolates. The million-question
// catalog is compiled into the app, so workers open their own local view.
void _searchAcademicText(_SearchRequest request) {
  try {
    final view = AdvancedCatalog.select(
      topic: request.topic,
      format: request.format,
      level: request.collection.level,
      bloom: request.bloom,
    );
    final found = <int>[];
    for (
      var i = request.start;
      i < view.length && found.length < request.limit;
      i++
    ) {
      final q = view[i];
      if (!request.hidden.contains(q.id) &&
          (request.query.isEmpty || _hasText(q, request.query))) {
        found.add(i);
      }
    }
    request.reply.send(found);
  } catch (e) {
    request.reply.send(e.toString());
  }
}

class BrowserPageTask {
  final List<Question> personal;
  final Topic topic;
  final QuestionFormat format;
  final PoolCollection collection;
  final BloomLevel? bloom;
  final String query;
  final Set<String> hidden;
  final BrowserCursor cursor;
  final int limit;
  bool _cancelled = false;
  Isolate? _isolate;
  ReceivePort? _port;

  BrowserPageTask({
    required this.personal,
    required this.topic,
    required this.format,
    required this.collection,
    this.bloom,
    required this.query,
    required this.hidden,
    required this.cursor,
    this.limit = 30,
  });

  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _port?.close();
  }

  Future<List<int>> _personalMatches() async {
    if (collection.level != null || bloom != null) return [];
    final matches = <int>[];
    final slice = Stopwatch()..start();
    final size = personal.length;
    for (var i = cursor.personal; i < size && matches.length <= limit; i++) {
      if ((i & 127) == 0 && slice.elapsedMilliseconds >= 3) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (_cancelled) return [];
        slice.reset();
      }
      final q = personal[i];
      if (topic == Topic.exam) {
        if (q.category != Topic.exam && q.exam == null) continue;
      } else if (topic != Topic.mixed && q.category != topic) {
        continue;
      }
      if (!q.matchesFormat(format) || hidden.contains(q.id)) continue;
      if (query.isEmpty || _hasText(q, query)) matches.add(i);
    }
    return matches;
  }

  Future<List<int>> _academicMatches(FamilyQuestions view) async {
    if (collection == PoolCollection.personal || cursor.academic >= view.length) {
      return [];
    }
    if (query.isEmpty && hidden.length <= limit * 8) {
      final found = <int>[];
      for (
        var i = cursor.academic;
        i < view.length && found.length <= limit;
        i++
      ) {
        if (hidden.isEmpty || !hidden.contains(view[i].id)) found.add(i);
      }
      return found;
    }

    final port = ReceivePort();
    _port = port;
    final result = Completer<List<int>>();
    port.listen(
      (message) {
        if (result.isCompleted) return;
        if (message is List<int>) {
          result.complete(message);
        } else {
          result.completeError(StateError(message.toString()));
        }
      },
      onDone: () {
        if (!result.isCompleted) result.complete(<int>[]);
      },
    );
    try {
      final worker = await Isolate.spawn(_searchAcademicText, (
        reply: port.sendPort,
        topic: topic,
        format: format,
        collection: collection,
        bloom: bloom,
        query: query,
        hidden: hidden,
        start: cursor.academic,
        limit: limit + 1,
      ));
      _isolate = worker;
      if (_cancelled) {
        worker.kill(priority: Isolate.immediate);
        return [];
      }
      return await result.future;
    } finally {
      port.close();
      _isolate?.kill(priority: Isolate.immediate);
    }
  }

  Future<BrowserPage> run() async {
    if (query.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (_cancelled) return const BrowserPage([], firstBrowserPage, false);
    }
    final academic = AdvancedCatalog.select(
      topic: topic,
      format: format,
      level: collection.level,
      bloom: bloom,
    );
    final matches = await Future.wait([
      _personalMatches(),
      _academicMatches(academic),
    ]);
    if (_cancelled) return const BrowserPage([], firstBrowserPage, false);
    final baseMatches = matches[0];
    final newMatches = matches[1];
    final items = <Question>[];
    var b = 0;
    var n = 0;
    while (items.length < limit &&
        (b < baseMatches.length || n < newMatches.length)) {
      if (n < newMatches.length) items.add(academic[newMatches[n++]]);
      if (items.length < limit && b < baseMatches.length) {
        items.add(personal[baseMatches[b++]]);
      }
    }
    final morePersonal = b < baseMatches.length;
    final moreAcademic = n < newMatches.length;
    final next = (
      personal: morePersonal ? baseMatches[b] : personal.length,
      academic: moreAcademic ? newMatches[n] : academic.length,
    );
    return BrowserPage(items, next, morePersonal || moreAcademic);
  }
}
