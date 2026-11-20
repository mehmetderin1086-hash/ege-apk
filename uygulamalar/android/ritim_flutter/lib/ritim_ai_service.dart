import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'ritim_models.dart';

enum RitimAiBackendMode {
  localProxy('Yerel CLIProxy (127.0.0.1:8317)', 'http://127.0.0.1:8317'),
  customProxy('Özel CLIProxy / OpenAI', ''),
  directGemini('Doğrudan Gemini API', 'https://generativelanguage.googleapis.com');

  const RitimAiBackendMode(this.title, this.defaultUrl);
  final String title;
  final String defaultUrl;

  static RitimAiBackendMode fromRaw(String? v) =>
      RitimAiBackendMode.values.firstWhere(
        (e) => e.name == v,
        orElse: () => RitimAiBackendMode.localProxy,
      );
}

enum AIAction {
  none,
  play,
  queueNext;

  static AIAction fromRaw(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase();
    if (s == 'play') return AIAction.play;
    if (s == 'queue_next') return AIAction.queueNext;
    return AIAction.none;
  }
}

enum AITask {
  chat(
    'chat',
    'Görev: sohbet. Kullanıcı açıkça çalmak/dinlemek istiyorsa action="play", sıraya eklemek istiyorsa action="queue_next" ver; yoksa "none". Kullanıcı YouTube\'da bir şey bulmak, aramak veya indirmek istiyorsa search_queries\'in ilki onun aradığı, diğer ikisi benzer sanatçı/tür/havada somut aramalar olsun.',
  ),
  dj(
    'dj',
    'Görev: DJ seti. request alanındaki ruh hâline uygun, akışı düşünülmüş 10-15 parçalık sıralı bir liste kur. reply, DJ gibi 1-2 cümlelik sıcak bir açılış anonsu olsun. action="play".',
  ),
  djContinue(
    'dj_continue',
    'Görev: DJ setini sürdür. listening_context.exclude_ids içindeki parçaları KULLANMA. Aynı ruh hâlinde 6-10 yeni parça seç ve geçişi anlatan tek cümlelik reply yaz. action="queue_next".',
  ),
  insight(
    'insight',
    'Görev: şimdi çalan parça hakkında not. reply en fazla 3 kısa cümle: parçanın/sanatçının havası ve ne zaman dinlenir. playlist, kitaplıktan bu parçaya benzeyen en fazla 5 parça olsun (şimdi çalanı katma). search_queries\'e 2 benzer keşif araması koy. action="none".',
  ),
  daily(
    'daily',
    'Görev: günün karışımı. listening_context\'teki gün bölümüne ve dinleme geçmişine göre 8-15 parçalık bir liste seç. playlist.name kısa ve yaratıcı olsun; reply 1-2 cümlelik kişisel bir not olsun. action="none".',
  ),
  discover(
    'discover',
    'Görev: YouTube keşfi. request bir YouTube arama ifadesidir. search_queries alanına bu ifadeyle aynı sanatçı, tür, dönem veya havada 3 farklı benzer arama koy. reply bu aramaları anlatan tek kısa cümle olsun. playlist null, action="none".',
  );

  const AITask(this.rawValue, this.instruction);
  final String rawValue;
  final String instruction;
}

class AIMoodPreset {
  const AIMoodPreset(this.id, this.title, this.icon, this.prompt);
  final String id;
  final String title;
  final IconData icon;
  final String prompt;
}

enum AIDayPart {
  morning('sabah', 'Günaydın'),
  noon('öğle', 'İyi öğlenler'),
  afternoon('ikindi', 'İyi günler'),
  evening('akşam', 'İyi akşamlar'),
  night('gece', 'İyi geceler');

  const AIDayPart(this.rawValue, this.greeting);
  final String rawValue;
  final String greeting;

  static AIDayPart forNow([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour >= 5 && hour < 11) return AIDayPart.morning;
    if (hour >= 11 && hour < 14) return AIDayPart.noon;
    if (hour >= 14 && hour < 18) return AIDayPart.afternoon;
    if (hour >= 18 && hour < 23) return AIDayPart.evening;
    return AIDayPart.night;
  }

  List<AIMoodPreset> get presets {
    const common = AIMoodPreset(
      'favorites',
      'Favorilerimden',
      Icons.favorite_rounded,
      'En sevdiğim ve çok dinlediğim parçalardan akıcı bir set',
    );
    switch (this) {
      case AIDayPart.morning:
        return const [
          AIMoodPreset('wake', 'Güne başla', Icons.wb_sunny_rounded,
              'Sabah uyanışı: yumuşak başlayıp enerjisi yükselen bir set'),
          AIMoodPreset('focus', 'Odak', Icons.psychology_rounded,
              'Çalışırken dikkat dağıtmayan odak seti'),
          common,
        ];
      case AIDayPart.noon:
      case AIDayPart.afternoon:
        return const [
          AIMoodPreset('energy', 'Enerji', Icons.bolt_rounded,
              'Enerjimi yükseltecek tempolu bir set'),
          AIMoodPreset('focus', 'Odak', Icons.psychology_rounded,
              'Çalışırken dikkat dağıtmayan odak seti'),
          common,
        ];
      case AIDayPart.evening:
        return const [
          AIMoodPreset('unwind', 'Akşam sakinliği', Icons.wb_twilight_rounded,
              'Günün yorgunluğunu alan sakin bir akşam seti'),
          AIMoodPreset('energy', 'Enerji', Icons.bolt_rounded,
              'Akşam için hareketli bir set'),
          common,
        ];
      case AIDayPart.night:
        return const [
          AIMoodPreset('sleep', 'Uykuya doğru', Icons.nightlight_round,
              'Gece için yavaşça sakinleşen, uykuya hazırlayan bir set'),
          AIMoodPreset('deep', 'Derin düşünce', Icons.auto_awesome_rounded,
              'Gece yarısı düşünceli ve atmosferik bir set'),
          common,
        ];
    }
  }
}

class RitimAIModel {
  const RitimAIModel({
    required this.id,
    required this.name,
    required this.provider,
    this.ownedBy,
  });

  final String id;
  final String name;
  final String provider;
  final String? ownedBy;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        if (ownedBy != null) 'owned_by': ownedBy,
      };

  factory RitimAIModel.fromJson(Map<String, dynamic> json) => RitimAIModel(
        id: (json['id'] ?? '') as String,
        name: (json['name'] ?? json['id'] ?? '') as String,
        provider: (json['provider'] ?? 'CLIProxy') as String,
        ownedBy: json['owned_by'] as String?,
      );
}

class AIPlaylistProposal {
  const AIPlaylistProposal({required this.name, required this.trackIDs});

  final String name;
  final List<String> trackIDs;

  Map<String, dynamic> toJson() => {'name': name, 'track_ids': trackIDs};

  factory AIPlaylistProposal.fromJson(Map<String, dynamic> json) =>
      AIPlaylistProposal(
        name: (json['name'] ?? 'Ritim önerisi') as String,
        trackIDs: (json['track_ids'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class AIMessage {
  AIMessage({
    required this.id,
    required this.role,
    required this.content,
    this.model,
    this.playlist,
    this.searchQueries = const [],
    this.action = AIAction.none,
    this.appliedNote,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String role;
  final String content;
  final String? model;
  final AIPlaylistProposal? playlist;
  final List<String> searchQueries;
  final AIAction action;
  final String? appliedNote;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        if (model != null) 'model': model,
        if (playlist != null) 'playlist': playlist!.toJson(),
        if (searchQueries.isNotEmpty) 'searchQueries': searchQueries,
        'action': action.name,
        if (appliedNote != null) 'appliedNote': appliedNote,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AIMessage.fromJson(Map<String, dynamic> json) => AIMessage(
        id: (json['id'] ?? '') as String,
        role: (json['role'] ?? 'assistant') as String,
        content: (json['content'] ?? '') as String,
        model: json['model'] as String?,
        playlist: json['playlist'] is Map<String, dynamic>
            ? AIPlaylistProposal.fromJson(
                json['playlist'] as Map<String, dynamic>)
            : null,
        searchQueries: (json['searchQueries'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        action: AIAction.fromRaw(json['action']),
        appliedNote: json['appliedNote'] as String?,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ??
            DateTime.now(),
      );
}

class AITrackInsight {
  const AITrackInsight({
    required this.trackID,
    required this.text,
    required this.similarIDs,
    required this.searchQueries,
    required this.model,
    required this.createdAt,
  });

  final String trackID;
  final String text;
  final List<String> similarIDs;
  final List<String> searchQueries;
  final String model;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'trackID': trackID,
        'text': text,
        'similarIDs': similarIDs,
        'searchQueries': searchQueries,
        'model': model,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AITrackInsight.fromJson(Map<String, dynamic> json) => AITrackInsight(
        trackID: (json['trackID'] ?? '') as String,
        text: (json['text'] ?? '') as String,
        similarIDs: (json['similarIDs'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        searchQueries: (json['searchQueries'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        model: (json['model'] ?? '') as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ??
            DateTime.now(),
      );
}

class AIDailyMix {
  const AIDailyMix({
    required this.title,
    required this.note,
    required this.trackIDs,
    required this.model,
    required this.createdAt,
    required this.dayPart,
  });

  final String title;
  final String note;
  final List<String> trackIDs;
  final String model;
  final DateTime createdAt;
  final String dayPart;

  bool isFresh([DateTime? now]) {
    final t = now ?? DateTime.now();
    return t.year == createdAt.year &&
        t.month == createdAt.month &&
        t.day == createdAt.day;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'note': note,
        'trackIDs': trackIDs,
        'model': model,
        'createdAt': createdAt.toIso8601String(),
        'dayPart': dayPart,
      };

  factory AIDailyMix.fromJson(Map<String, dynamic> json) => AIDailyMix(
        title: (json['title'] ?? 'Günün Karışımı') as String,
        note: (json['note'] ?? '') as String,
        trackIDs: (json['trackIDs'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        model: (json['model'] ?? '') as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ??
            DateTime.now(),
        dayPart: (json['dayPart'] ?? '') as String,
      );
}

class AIDJSession {
  AIDJSession({
    required this.mood,
    required this.note,
    required this.trackIDs,
    Set<String>? played,
    this.isExtending = false,
    this.extensions = 0,
  }) : played = played ?? <String>{};

  final String mood;
  String note;
  List<String> trackIDs;
  final Set<String> played;
  bool isExtending;
  int extensions;
}

class AIConnectionConfig {
  AIConnectionConfig({
    this.mode = RitimAiBackendMode.localProxy,
    this.baseUrl = 'http://127.0.0.1:8317',
    this.apiKey = '',
    this.authHeader = 'Authorization',
    this.selectedModelId = '',
    this.proactiveEnabled = true,
  });

  RitimAiBackendMode mode;
  String baseUrl;
  String apiKey;
  String authHeader; // 'Authorization' or 'X-Personal-Token'
  String selectedModelId;
  bool proactiveEnabled;

  String get effectiveBaseUrl {
    if (mode == RitimAiBackendMode.directGemini) {
      return RitimAiBackendMode.directGemini.defaultUrl;
    }
    final cleaned = baseUrl.trim();
    if (cleaned.isNotEmpty) return cleaned;
    return RitimAiBackendMode.localProxy.defaultUrl;
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'authHeader': authHeader,
        'selectedModelId': selectedModelId,
        'proactiveEnabled': proactiveEnabled,
      };

  factory AIConnectionConfig.fromJson(Map<String, dynamic> json) =>
      AIConnectionConfig(
        mode: RitimAiBackendMode.fromRaw(json['mode'] as String?),
        baseUrl: (json['baseUrl'] ?? 'http://127.0.0.1:8317') as String,
        apiKey: (json['apiKey'] ?? '') as String,
        authHeader: (json['authHeader'] ?? 'Authorization') as String,
        selectedModelId: (json['selectedModelId'] ?? '') as String,
        proactiveEnabled: json['proactiveEnabled'] != false,
      );
}

class RitimAIChatReply {
  const RitimAIChatReply({
    required this.model,
    required this.reply,
    this.playlist,
    this.searchQueries = const [],
    this.action = AIAction.none,
  });

  final String model;
  final String reply;
  final AIPlaylistProposal? playlist;
  final List<String> searchQueries;
  final AIAction action;
}

/// CLIProxyAPI / Direct Gemini tam kapsamlı AI istemcisi (tüm sağlayıcı & modeller dâhil).
class RitimAIClient {
  RitimAIClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String systemPrompt = '''
Sen Ritim'in Türkçe müzik asistanısın. Kullanıcıya kısa, faydalı ve dürüst cevap ver.
Yalnızca aşağıdaki JSON nesnesini üret; Markdown veya başka bir metin ekleme:
{"reply":"Türkçe cevap","playlist":{"name":"Liste adı","track_ids":["UUID"]},"search_queries":["sanatçı şarkı"],"action":"none"}
Liste önerilmiyorsa playlist null olsun. search_queries en fazla 3 kısa YouTube araması içersin; gerekmiyorsa boş dizi olsun.
action yalnızca "none", "play" veya "queue_next" olabilir; playlist yoksa "none" olsun. Uygulama yalnızca yerel çalmayı uygular.
listening_context saat, gün bölümü, şimdi çalan parça, son dinlenenler ve listeler hakkında bilgidir; önerini buna göre kişiselleştir.
Çalma listelerinde yalnızca verilen kütüphanedeki UUID'leri kullan, en fazla 100 parça seç. Bilinmeyen parçalar için arama öner.
''';

  Uri _buildUri(String baseUrl, String suffix) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/v1') && suffix.startsWith('/v1')) {
      base = base.substring(0, base.length - 3);
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    return Uri.parse('$base$suffix');
  }

  /// CLIProxyAPI `/v1/models` (ve Direct Gemini `/v1beta/models`) içindeki TÜM modelleri eksiksiz getirir.
  Future<List<RitimAIModel>> fetchAllModels(AIConnectionConfig config) async {
    if (config.mode == RitimAiBackendMode.directGemini) {
      if (config.apiKey.trim().isEmpty) {
        throw const RitimException('Direct Gemini için API anahtarı gir.');
      }
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=${Uri.encodeQueryComponent(config.apiKey.trim())}',
      );
      final resp = await _client.get(uri).timeout(const Duration(seconds: 20));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RitimException('Gemini modelleri okunamadı (HTTP ${resp.statusCode}).');
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = (decoded as Map<String, dynamic>)['models'] as List<dynamic>? ?? const [];
      final seen = <String>{};
      final models = <RitimAIModel>[];
      for (final raw in list.whereType<Map<String, dynamic>>()) {
        final full = (raw['name'] as String? ?? '').replaceFirst('models/', '');
        if (full.isEmpty || !seen.add(full)) continue;
        models.add(RitimAIModel(
          id: full,
          name: (raw['displayName'] as String?)?.trim().isNotEmpty == true
              ? raw['displayName'] as String
              : friendlyName(full),
          provider: 'Gemini',
        ));
      }
      return models;
    }

    final uri = _buildUri(config.effectiveBaseUrl, '/v1/models');
    final headers = <String, String>{'Accept': 'application/json'};
    final key = config.apiKey.trim();
    if (key.isNotEmpty) {
      headers[config.authHeader] =
          config.authHeader == 'Authorization' ? 'Bearer $key' : key;
    }

    final resp = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const RitimException(
          'CLIProxyAPI erişim anahtarı geçersiz veya yetkisiz.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw RitimException(
          'CLIProxy model listesi okunamadı (HTTP ${resp.statusCode}).');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    final rows = ((decoded as Map<String, dynamic>)['data'] ??
            decoded['models'] ??
            const []) as List<dynamic>;
    final seen = <String>{};
    final out = <RitimAIModel>[];
    for (final item in rows.whereType<Map<String, dynamic>>()) {
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty || !seen.add(id)) continue;
      final owner = item['owned_by']?.toString();
      out.add(RitimAIModel(
        id: id,
        name: friendlyName(id),
        provider: providerName(id, owner),
        ownedBy: owner,
      ));
    }
    return out;
  }

  Future<RitimAIChatReply> chat({
    required AIConnectionConfig config,
    required String modelId,
    required String prompt,
    required List<Map<String, String>> history,
    required List<Map<String, dynamic>> libraryTracks,
    required Map<String, dynamic> listeningContext,
    AITask task = AITask.chat,
  }) async {
    final userPayload = {
      'library_metadata': libraryTracks,
      'request': prompt,
      'task': task.rawValue,
      if (listeningContext.isNotEmpty) 'listening_context': listeningContext,
    };
    final userText = jsonEncode(userPayload);
    final allowedIds = libraryTracks
        .map((t) => t['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (config.mode == RitimAiBackendMode.directGemini) {
      final key = config.apiKey.trim();
      if (key.isEmpty) {
        throw const RitimException('Gemini API anahtarı eksik.');
      }
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=${Uri.encodeQueryComponent(key)}',
      );
      final contents = <Map<String, dynamic>>[
        for (final h in history)
          {
            'role': h['role'] == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': h['content'] ?? ''}
            ],
          },
        {
          'role': 'user',
          'parts': [
            {'text': userText}
          ],
        },
      ];
      final resp = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': '$systemPrompt\n${task.instruction}'}
                ],
              },
              'contents': contents,
            }),
          )
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RitimException('Gemini isteği tamamlanamadı (${resp.statusCode}).');
      }
      final obj = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final candidates = obj['candidates'] as List<dynamic>? ?? const [];
      var text = '';
      if (candidates.isNotEmpty) {
        final first = candidates.first;
        if (first is Map) {
          final content = first['content'];
          if (content is Map) {
            final parts = content['parts'];
            if (parts is List && parts.isNotEmpty && parts.first is Map) {
              text = (parts.first as Map)['text']?.toString() ?? '';
            }
          }
        }
      }
      return normalizeReply(text, model: modelId, allowedIds: allowedIds);
    }

    final uri = _buildUri(config.effectiveBaseUrl, '/v1/chat/completions');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final key = config.apiKey.trim();
    if (key.isNotEmpty) {
      headers[config.authHeader] =
          config.authHeader == 'Authorization' ? 'Bearer $key' : key;
    }

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': '$systemPrompt\n${task.instruction}'},
      ...history,
      {'role': 'user', 'content': userText},
    ];

    final resp = await _client
        .post(
          uri,
          headers: headers,
          body: jsonEncode({
            'model': modelId,
            'messages': messages,
            'max_tokens': 4096,
          }),
        )
        .timeout(const Duration(seconds: 150));

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const RitimException(
          'Asistan erişim anahtarı veya model oturumu geçersiz.');
    }
    if (resp.statusCode == 402) {
      throw const RitimException(
          'Seçili modelin hesabında bakiye veya kota yetersiz.');
    }
    if (resp.statusCode == 429) {
      throw const RitimException(
          'Seçili modelin kullanım sınırına ulaşıldı. Başka bir model seç.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw RitimException(
          'CLIProxy isteği tamamlanamadı (HTTP ${resp.statusCode}).');
    }

    final obj = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = obj['choices'] as List<dynamic>? ?? const [];
    final first = choices.isNotEmpty ? choices.first as Map<String, dynamic> : {};
    final content = ((first['message'] as Map?)?['content'] ?? '').toString();
    final returnedModel = (obj['model'] as String?) ?? modelId;
    if (content.trim().isEmpty) {
      throw const RitimException('Seçili model boş bir yanıt verdi.');
    }
    return normalizeReply(
      content,
      model: returnedModel,
      allowedIds: allowedIds,
    );
  }

  static RitimAIChatReply normalizeReply(
    String rawContent, {
    required String model,
    required Set<String> allowedIds,
  }) {
    var clean = rawContent.trim();
    if (clean.startsWith('```json')) {
      clean = clean.substring(7);
      if (clean.endsWith('```')) {
        clean = clean.substring(0, clean.length - 3);
      }
      clean = clean.trim();
    } else if (clean.startsWith('```') && clean.endsWith('```')) {
      clean = clean.substring(3, clean.length - 3).trim();
    }

    final braceStart = clean.indexOf('{');
    final braceEnd = clean.lastIndexOf('}');
    if (braceStart >= 0 && braceEnd > braceStart) {
      final candidateJson = clean.substring(braceStart, braceEnd + 1);
      try {
        final obj = jsonDecode(candidateJson);
        if (obj is Map<String, dynamic>) {
          final reply = (obj['reply'] ?? '').toString().trim();
          AIPlaylistProposal? proposal;
          if (obj['playlist'] is Map<String, dynamic>) {
            final row = obj['playlist'] as Map<String, dynamic>;
            final name = (row['name'] ?? 'Ritim önerisi').toString().trim();
            final seen = <String>{};
            final ids = (row['track_ids'] as List<dynamic>? ?? const [])
                .map((e) => e.toString())
                .where((id) => allowedIds.contains(id) && seen.add(id))
                .take(100)
                .toList();
            if (ids.isNotEmpty) {
              proposal = AIPlaylistProposal(
                name: name.isEmpty ? 'Ritim önerisi' : name,
                trackIDs: ids,
              );
            }
          }
          final rawQueries = obj['search_queries'] as List<dynamic>? ?? const [];
          final seenQ = <String>{};
          final queries = <String>[];
          for (final q in rawQueries) {
            final text = q.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
            if (text.isNotEmpty &&
                !text.contains('http') &&
                seenQ.add(text)) {
              queries.add(text);
              if (queries.length >= 3) break;
            }
          }
          if (reply.isNotEmpty) {
            return RitimAIChatReply(
              model: model,
              reply: reply,
              playlist: proposal,
              searchQueries: queries,
              action: proposal == null
                  ? AIAction.none
                  : AIAction.fromRaw(obj['action']),
            );
          }
        }
      } catch (_) {}
    }

    // Düz metin fallback
    return RitimAIChatReply(model: model, reply: clean);
  }

  static String providerName(String id, String? owner) {
    final low = id.toLowerCase();
    if (low.startsWith('antigravity-')) return 'Antigravity';
    if (low.contains('claude')) return 'Claude';
    if (low.startsWith('gpt') || low.contains('codex') || low.startsWith('o1') || low.startsWith('o3') || low.startsWith('o4')) {
      return 'ChatGPT / Codex';
    }
    if (low.contains('gemini')) return 'Gemini';
    if (low.contains('deepseek')) return 'DeepSeek';
    if (low.contains('qwen')) return 'Qwen';
    if (low.contains('grok')) return 'Grok';
    if (low.contains('glm') || low.contains('kimi')) return 'Kimi / GLM';
    if (owner != null && owner.trim().isNotEmpty) return owner.trim();
    return 'CLIProxy';
  }

  static String friendlyName(String id) {
    final isAntigravity = id.startsWith('antigravity-');
    final base = isAntigravity ? id.substring('antigravity-'.length) : id;
    final clean = base
        .split('-')
        .where((s) => s.isNotEmpty)
        .map((s) => s.length == 1
            ? s.toUpperCase()
            : '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
    return isAntigravity ? '$clean · Antigravity' : clean;
  }
}
