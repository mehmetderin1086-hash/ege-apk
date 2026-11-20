import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/jarvis_models.dart';
import 'local_command_engine.dart';

/// Source-backed memories. Inferences are never silently promoted to facts.
class EvidenceMemory {
  static const _key = 'ege.evidenceMemory.v1';
  final List<Map<String, dynamic>> entries = [];
  final List<String> forgotten = [];
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final data = jsonDecode(p.getString(_key) ?? '{}') as Map;
      entries
        ..clear()
        ..addAll(
          (data['entries'] as List? ?? []).whereType<Map>().map(
            (m) => Map<String, dynamic>.from(m),
          ),
        );
      forgotten
        ..clear()
        ..addAll((data['forgotten'] as List? ?? []).whereType<String>());
    } catch (_) {}
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({'entries': entries, 'forgotten': forgotten}),
    );
  }

  bool excluded(String text) {
    final f = LocalCommandEngine.foldTr(text);
    return forgotten.any((q) => f.contains(q));
  }

  String add(Map<String, dynamic> input, List<ChatSession> sessions) {
    final text = input['text']?.toString().trim() ?? '';
    final kind = input['kind']?.toString() ?? '';
    if (text.isEmpty ||
        text.length > 1000 ||
        !{'fact', 'inference'}.contains(kind) ||
        excluded(text)) {
      return 'Hata: Geçerli bilgi/tahmin ve kaynak gerekli; unutulmuş bilgi geri eklenmez.';
    }
    final sources = <Map<String, String>>[];
    for (final raw in (input['sources'] as List? ?? []).whereType<Map>()) {
      final id = raw['messageId']?.toString() ?? '';
      final quote = raw['quote']?.toString().trim() ?? '';
      final session = sessions
          .where((s) => s.messages.any((m) => m.id == id && m.role == 'user'))
          .firstOrNull;
      final message = session?.messages
          .where((m) => m.id == id && m.role == 'user')
          .firstOrNull;
      if (message == null ||
          quote.length < 4 ||
          quote.length > 500 ||
          !message.content.contains(quote) ||
          excluded(message.content)) {
        continue;
      }
      if (sources.any((s) => s['messageId'] == id)) continue;
      sources.add({
        'sessionId': session!.id,
        'messageId': id,
        'quote': quote,
        'at': message.timestamp.toIso8601String(),
      });
    }
    if (sources.length < (kind == 'inference' ? 2 : 1)) {
      return 'Hata: Bilgi için bir, çıkarım için en az iki ayrı kullanıcı mesajından doğrulanabilir alıntı gerekli.';
    }
    if (entries.any(
      (e) =>
          LocalCommandEngine.foldTr(e['text'].toString()) ==
          LocalCommandEngine.foldTr(text),
    )) {
      return 'Bu bilgi zaten kayıtlı.';
    }
    entries.add({
      'id': LocalCommandEngine.newId(),
      'text': text,
      'kind': kind,
      'sources': sources,
      'at': DateTime.now().toIso8601String(),
    });
    return kind == 'fact'
        ? 'Kaynaklı bilgi kaydedildi.'
        : 'Çıkarım, doğrulanmamış tahmin olarak kaydedildi.';
  }

  Future<int> forget(String query) async {
    final q = LocalCommandEngine.foldTr(query);
    if (q.length < 3) return 0;
    final before = entries.length;
    entries.removeWhere(
      (e) => LocalCommandEngine.foldTr(e['text'].toString()).contains(q),
    );
    if (!forgotten.contains(q)) forgotten.add(q);
    await save();
    return before - entries.length;
  }

  String relevant(String query) {
    final terms = LocalCommandEngine.foldTr(query)
        .split(' ')
        .where((t) => t.length > 3)
        .toSet();
    final matched = entries
        .where(
          (e) =>
              !excluded(e['text'].toString()) &&
              terms.any(
                (t) =>
                    LocalCommandEngine.foldTr(e['text'].toString()).contains(t),
              ),
        )
        .take(8);
    return matched
        .map(
          (e) =>
              '${e['kind'] == 'fact' ? 'Kullanıcı beyanı' : 'Doğrulanmamış çıkarım'}: ${e['text']}\nKaynak: ${jsonEncode(e['sources'])}',
        )
        .join('\n');
  }
}
