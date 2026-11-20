import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum KagitAiMode {
  localCliProxy,
  customCliProxy,
  directGemini,
}

extension KagitAiModeMeta on KagitAiMode {
  String get title {
    switch (this) {
      case KagitAiMode.localCliProxy:
        return 'Yerel CLIProxyAPI (127.0.0.1:8317)';
      case KagitAiMode.customCliProxy:
        return 'Özel CLIProxyAPI Sunucusu';
      case KagitAiMode.directGemini:
        return 'Doğrudan Gemini API';
    }
  }
}

class KagitAiModel {
  const KagitAiModel({
    required this.id,
    required this.displayName,
    required this.provider,
  });

  final String id;
  final String displayName;
  final String provider;

  static String inferProvider(String id) {
    final l = id.toLowerCase();
    if (l.contains('gemini') || l.contains('gemma') || l.contains('imagen')) return 'Google Gemini';
    if (l.contains('claude')) return 'Anthropic Claude';
    if (l.contains('gpt') || l.startsWith('o1') || l.startsWith('o3') || l.startsWith('o4') || l.contains('codex')) {
      return 'OpenAI / Codex';
    }
    if (l.contains('qwen')) return 'Qwen';
    if (l.contains('deepseek')) return 'DeepSeek';
    if (l.contains('glm') || l.contains('zhipu')) return 'GLM / Zhipu';
    if (l.contains('grok')) return 'xAI Grok';
    if (l.contains('kimi') || l.contains('moonshot')) return 'Moonshot Kimi';
    if (l.contains('llama') || l.contains('mistral')) return 'Meta / Mistral';
    return 'Diğer Sağlayıcılar';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'provider': provider,
      };

  factory KagitAiModel.fromJson(Map<String, dynamic> j) => KagitAiModel(
        id: j['id'] as String? ?? '',
        displayName: j['displayName'] as String? ?? (j['id'] as String? ?? ''),
        provider: j['provider'] as String? ?? inferProvider(j['id'] as String? ?? ''),
      );
}

class KagitAiMessage {
  KagitAiMessage({
    required this.isUser,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final bool isUser;
  final String text;
  final DateTime timestamp;
}

class KagitAiConfig {
  KagitAiConfig({
    this.mode = KagitAiMode.localCliProxy,
    this.endpoint = 'http://127.0.0.1:8317',
    this.apiKey = '',
    this.personalToken = '',
    this.selectedModelId = 'gemini-2.5-flash',
    this.models = const [],
  });

  KagitAiMode mode;
  String endpoint;
  String apiKey;
  String personalToken;
  String selectedModelId;
  List<KagitAiModel> models;

  String get normalizedEndpoint {
    var e = endpoint.trim();
    if (e.isEmpty) return 'http://127.0.0.1:8317';
    while (e.endsWith('/')) {
      e = e.substring(0, e.length - 1);
    }
    if (!e.startsWith('http://') && !e.startsWith('https://')) {
      e = 'http://$e';
    }
    return e;
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'personalToken': personalToken,
        'selectedModelId': selectedModelId,
        'models': models.map((m) => m.toJson()).toList(),
      };

  factory KagitAiConfig.fromJson(Map<String, dynamic> j) {
    final modeStr = j['mode'] as String? ?? 'localCliProxy';
    return KagitAiConfig(
      mode: KagitAiMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => KagitAiMode.localCliProxy,
      ),
      endpoint: j['endpoint'] as String? ?? 'http://127.0.0.1:8317',
      apiKey: j['apiKey'] as String? ?? '',
      personalToken: j['personalToken'] as String? ?? '',
      selectedModelId: j['selectedModelId'] as String? ?? 'gemini-2.5-flash',
      models: (j['models'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(KagitAiModel.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// CLIProxyAPI (tüm modeller) + Doğrudan Gemini istemcisi.
class KagitAiService extends ChangeNotifier {
  KagitAiService({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;
  KagitAiConfig config = KagitAiConfig();
  bool isFetchingModels = false;
  bool isGenerating = false;
  String? lastError;

  static const List<KagitAiModel> fallbackCatalog = [
    KagitAiModel(id: 'gemini-2.5-flash', displayName: 'gemini-2.5-flash', provider: 'Google Gemini'),
    KagitAiModel(id: 'gemini-2.5-pro', displayName: 'gemini-2.5-pro', provider: 'Google Gemini'),
    KagitAiModel(id: 'claude-sonnet-4-5', displayName: 'claude-sonnet-4-5', provider: 'Anthropic Claude'),
    KagitAiModel(id: 'gpt-4o', displayName: 'gpt-4o', provider: 'OpenAI / Codex'),
    KagitAiModel(id: 'gpt-5', displayName: 'gpt-5', provider: 'OpenAI / Codex'),
    KagitAiModel(id: 'qwen-plus', displayName: 'qwen-plus', provider: 'Qwen'),
    KagitAiModel(id: 'deepseek-chat', displayName: 'deepseek-chat', provider: 'DeepSeek'),
  ];

  List<KagitAiModel> get effectiveModels =>
      config.models.isNotEmpty ? config.models : fallbackCatalog;

  Map<String, List<KagitAiModel>> groupedModels([String filter = '']) {
    final q = filter.trim().toLowerCase();
    final map = <String, List<KagitAiModel>>{};
    for (final m in effectiveModels) {
      if (q.isNotEmpty &&
          !m.id.toLowerCase().contains(q) &&
          !m.displayName.toLowerCase().contains(q) &&
          !m.provider.toLowerCase().contains(q)) {
        continue;
      }
      map.putIfAbsent(m.provider, () => []).add(m);
    }
    return map;
  }

  void updateConfig(void Function(KagitAiConfig cfg) mutate) {
    mutate(config);
    notifyListeners();
  }

  Map<String, String> _buildHeaders() {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (config.apiKey.trim().isNotEmpty) {
      h['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }
    if (config.personalToken.trim().isNotEmpty) {
      h['X-Personal-Token'] = config.personalToken.trim();
    }
    return h;
  }

  Future<List<KagitAiModel>> fetchAllModels() async {
    isFetchingModels = true;
    lastError = null;
    notifyListeners();
    try {
      final fetched = config.mode == KagitAiMode.directGemini
          ? await _fetchDirectGeminiModels()
          : await _fetchCliProxyModels();
      if (fetched.isNotEmpty) {
        config.models = fetched;
        if (!fetched.any((m) => m.id == config.selectedModelId)) {
          config.selectedModelId = fetched.first.id;
        }
      }
      return effectiveModels;
    } catch (e) {
      lastError = 'Model listesi alınamadı: $e';
      rethrow;
    } finally {
      isFetchingModels = false;
      notifyListeners();
    }
  }

  Future<List<KagitAiModel>> _fetchCliProxyModels() async {
    final base = config.normalizedEndpoint;
    final candidates = [
      Uri.parse('$base/v1/models'),
      Uri.parse('$base/models'),
      Uri.parse('$base/v1beta/models'),
    ];
    final seen = <String>{};
    final out = <KagitAiModel>[];
    Object? lastErr;

    for (final uri in candidates) {
      try {
        final resp = await _client.get(uri, headers: _buildHeaders()).timeout(const Duration(seconds: 12));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final parsed = parseModelsPayload(jsonDecode(resp.body));
          for (final m in parsed) {
            if (seen.add(m.id)) out.add(m);
          }
          if (out.isNotEmpty) return out;
        } else {
          lastErr = 'HTTP ${resp.statusCode}: ${resp.body}';
        }
      } catch (e) {
        lastErr = e;
      }
    }
    if (out.isEmpty && lastErr != null) throw Exception(lastErr.toString());
    return out;
  }

  Future<List<KagitAiModel>> _fetchDirectGeminiModels() async {
    final key = config.apiKey.trim();
    if (key.isEmpty) throw Exception('Doğrudan Gemini API için API anahtarı girin.');
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?pageSize=100&key=$key',
    );
    final resp = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Gemini HTTP ${resp.statusCode}: ${resp.body}');
    }
    return parseModelsPayload(jsonDecode(resp.body));
  }

  /// CLIProxy `/v1/models`, Gemini `/v1beta/models` ve düz dizi yanıtlarından TÜM modelleri eksiksiz ayıklar.
  static List<KagitAiModel> parseModelsPayload(dynamic raw) {
    final items = <dynamic>[];
    if (raw is List) {
      items.addAll(raw);
    } else if (raw is Map<String, dynamic>) {
      if (raw['data'] is List) items.addAll(raw['data'] as List);
      if (raw['models'] is List) items.addAll(raw['models'] as List);
    }

    final result = <KagitAiModel>[];
    final seen = <String>{};
    for (final item in items) {
      String id = '';
      String display = '';
      String provider = '';
      if (item is String) {
        id = item;
        display = item;
      } else if (item is Map<String, dynamic>) {
        id = (item['id'] as String?) ?? (item['name'] as String?) ?? '';
        if (id.startsWith('models/')) id = id.substring('models/'.length);
        display = (item['displayName'] as String?) ?? (item['owned_by'] as String?) ?? id;
        final ownedBy = item['owned_by'] as String?;
        if (ownedBy != null && ownedBy.isNotEmpty && ownedBy != 'system') {
          provider = ownedBy;
        }
      }
      id = id.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      final inferred = KagitAiModel.inferProvider(id);
      result.add(
        KagitAiModel(
          id: id,
          displayName: display.isEmpty ? id : display,
          provider: inferred != 'Diğer Sağlayıcılar' ? inferred : (provider.isNotEmpty ? provider : inferred),
        ),
      );
    }
    result.sort((a, b) {
      final p = a.provider.compareTo(b.provider);
      return p != 0 ? p : a.id.compareTo(b.id);
    });
    return result;
  }

  Future<String> sendPrompt({
    required String systemPrompt,
    required List<KagitAiMessage> messages,
  }) async {
    isGenerating = true;
    lastError = null;
    notifyListeners();
    try {
      if (config.mode == KagitAiMode.directGemini) {
        return await _callDirectGemini(systemPrompt, messages);
      }
      return await _callOpenAiCompatible(systemPrompt, messages);
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      isGenerating = false;
      notifyListeners();
    }
  }

  Future<String> _callOpenAiCompatible(String systemPrompt, List<KagitAiMessage> messages) async {
    final base = config.normalizedEndpoint;
    final uri = Uri.parse('$base/v1/chat/completions');
    final chatMessages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      for (final m in messages) {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    ];
    final body = jsonEncode({
      'model': config.selectedModelId,
      'messages': chatMessages,
      'temperature': 0.35,
    });
    final resp = await _client.post(uri, headers: _buildHeaders(), body: body).timeout(const Duration(seconds: 75));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('CLIProxy HTTP ${resp.statusCode}: ${resp.body}');
    }
    final parsed = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = parsed['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      final first = choices.first as Map<String, dynamic>;
      final msg = first['message'] as Map<String, dynamic>?;
      final content = msg?['content'];
      if (content is String && content.trim().isNotEmpty) return content.trim();
      if (content is List) {
        return content
            .whereType<Map<String, dynamic>>()
            .map((e) => e['text'] as String? ?? '')
            .join('\n')
            .trim();
      }
    }
    throw Exception('Yanıt çözümlenemedi: ${resp.body}');
  }

  Future<String> _callDirectGemini(String systemPrompt, List<KagitAiMessage> messages) async {
    final key = config.apiKey.trim();
    if (key.isEmpty) throw Exception('Gemini API anahtarı boş.');
    final model = config.selectedModelId.trim().isEmpty ? 'gemini-2.5-flash' : config.selectedModelId.trim();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
    );
    final contents = [
      for (final m in messages)
        {
          'role': m.isUser ? 'user' : 'model',
          'parts': [
            {'text': m.text}
          ],
        },
    ];
    final payload = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ],
      },
      'contents': contents,
      'generationConfig': {'temperature': 0.35},
    });
    final resp = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: payload)
        .timeout(const Duration(seconds: 75));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Gemini HTTP ${resp.statusCode}: ${resp.body}');
    }
    final parsed = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = parsed['candidates'] as List?;
    if (candidates != null && candidates.isNotEmpty) {
      final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      final text = parts?.whereType<Map<String, dynamic>>().map((p) => p['text'] as String? ?? '').join('\n').trim();
      if (text != null && text.isNotEmpty) return text;
    }
    throw Exception('Gemini yanıtı boş döndü.');
  }

  Future<String> ozetle(String documentText, {String title = 'Belge'}) {
    final clipped = documentText.length > 26000 ? documentText.substring(0, 26000) : documentText;
    return sendPrompt(
      systemPrompt:
          'Sen Kâğıt PDF Stüdyosu editoryal belge asistanısın. Yanıtlarını temiz, yapılandırılmış Türkçe markdown olarak yaz.',
      messages: [
        KagitAiMessage(
          isUser: true,
          text:
              '"$title" belgesini incele.\n1. Ana fikir (2-3 cümle)\n2. Madde madde önemli noktalar\n3. Kritik tarih/rakam/kararlar varsa vurgula.\n\nMetin:\n$clipped',
        ),
      ],
    );
  }

  Future<String> cevir(String documentText, {String targetLanguage = 'Türkçe'}) {
    final clipped = documentText.length > 26000 ? documentText.substring(0, 26000) : documentText;
    return sendPrompt(
      systemPrompt: 'Profesyonel belge çevirmenisin. Sayfa ayrımlarını (--- Sayfa X ---) ve başlıkları koru.',
      messages: [
        KagitAiMessage(
          isUser: true,
          text: 'Aşağıdaki metni doğal, akıcı $targetLanguage diline çevir:\n\n$clipped',
        ),
      ],
    );
  }

  Future<String> belgeyeSor(String documentText, List<KagitAiMessage> thread) {
    final clipped = documentText.length > 26000 ? documentText.substring(0, 26000) : documentText;
    return sendPrompt(
      systemPrompt:
          'Sen Kâğıt Belge Asistanısın. Yalnızca aşağıdaki PDF metnine dayanarak Türkçe yanıt ver. Her iddianın sonuna ilgili sayfa numarasını [Sayfa X] şeklinde ekle.\n\nBelge Metni:\n$clipped',
      messages: thread,
    );
  }

  Future<String> soruUret({
    required String topicOrText,
    int count = 5,
    String difficulty = 'Orta',
    String questionType = 'Karışık (Test + Açık Uçlu)',
  }) {
    final clipped = topicOrText.length > 18000 ? topicOrText.substring(0, 18000) : topicOrText;
    return sendPrompt(
      systemPrompt:
          'Deneyimli bir Türk öğretmensin. Sınav kâğıdına basılmaya hazır, net, özgün sorular ve en sonda "Cevap Anahtarı" bölümü oluştur.',
      messages: [
        KagitAiMessage(
          isUser: true,
          text:
              'Aşağıdaki konu veya kaynak metne göre $count adet ($difficulty zorluk, biçim: $questionType) sınav sorusu hazırla. Soruları "1.", "2." biçiminde numaralandır ve en alta ayrı "Cevap Anahtarı" ekle.\n\nİçerik:\n$clipped',
        ),
      ],
    );
  }
}
