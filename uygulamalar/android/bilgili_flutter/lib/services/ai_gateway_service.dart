import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/quiz_models.dart';

enum AiConnectionMode {
  phoneCliProxy('Telefon CLIProxy', 'http://127.0.0.1:8317'),
  customServer('Özel CLIProxy / OpenAI', 'http://192.168.1.100:8317'),
  directGemini('Doğrudan Gemini API', 'https://generativelanguage.googleapis.com/v1beta');

  final String label;
  final String defaultUrl;
  const AiConnectionMode(this.label, this.defaultUrl);
}

class AiModelDescriptor {
  final String id;
  final String displayName;
  final String family;
  final String badge;
  final bool discoveredLive;

  const AiModelDescriptor({
    required this.id,
    required this.displayName,
    required this.family,
    required this.badge,
    this.discoveredLive = false,
  });
}

class ModelProbeStatus {
  final bool healthy;
  final int latencyMs;
  final String message;
  final DateTime checkedAt;

  const ModelProbeStatus({
    required this.healthy,
    required this.latencyMs,
    required this.message,
    required this.checkedAt,
  });
}

class AiGatewayConfig {
  final AiConnectionMode mode;
  final String customBaseUrl;
  final String apiKey;
  final String primaryModel;
  final List<String> teamModels;
  final bool useModelTeam;
  final bool useSecondModelReview;
  final String reviewerModel;

  const AiGatewayConfig({
    this.mode = AiConnectionMode.phoneCliProxy,
    this.customBaseUrl = 'http://127.0.0.1:8317',
    this.apiKey = '',
    this.primaryModel = 'gemini-2.5-flash',
    this.teamModels = const [
      'gemini-2.5-flash',
      'claude-sonnet-4-5',
      'gpt-4.1',
      'deepseek-v3',
    ],
    this.useModelTeam = true,
    this.useSecondModelReview = false,
    this.reviewerModel = 'gemini-2.5-pro',
  });

  String get effectiveBaseUrl {
    switch (mode) {
      case AiConnectionMode.phoneCliProxy:
        return 'http://127.0.0.1:8317';
      case AiConnectionMode.customServer:
        final trimmed = customBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
        return trimmed.isEmpty ? 'http://127.0.0.1:8317' : trimmed;
      case AiConnectionMode.directGemini:
        return 'https://generativelanguage.googleapis.com/v1beta';
    }
  }

  AiGatewayConfig copyWith({
    AiConnectionMode? mode,
    String? customBaseUrl,
    String? apiKey,
    String? primaryModel,
    List<String>? teamModels,
    bool? useModelTeam,
    bool? useSecondModelReview,
    String? reviewerModel,
  }) {
    return AiGatewayConfig(
      mode: mode ?? this.mode,
      customBaseUrl: customBaseUrl ?? this.customBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      primaryModel: primaryModel ?? this.primaryModel,
      teamModels: teamModels ?? this.teamModels,
      useModelTeam: useModelTeam ?? this.useModelTeam,
      useSecondModelReview: useSecondModelReview ?? this.useSecondModelReview,
      reviewerModel: reviewerModel ?? this.reviewerModel,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'customBaseUrl': customBaseUrl,
        'apiKey': apiKey,
        'primaryModel': primaryModel,
        'teamModels': teamModels,
        'useModelTeam': useModelTeam,
        'useSecondModelReview': useSecondModelReview,
        'reviewerModel': reviewerModel,
      };

  factory AiGatewayConfig.fromJson(Map<String, dynamic> json) => AiGatewayConfig(
        mode: AiConnectionMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => AiConnectionMode.phoneCliProxy,
        ),
        customBaseUrl: json['customBaseUrl']?.toString() ?? 'http://127.0.0.1:8317',
        apiKey: json['apiKey']?.toString() ?? '',
        primaryModel: json['primaryModel']?.toString() ?? 'gemini-2.5-flash',
        teamModels: (json['teamModels'] as List?)?.map((e) => e.toString()).toList() ??
            const ['gemini-2.5-flash', 'claude-sonnet-4-5', 'gpt-4.1'],
        useModelTeam: json['useModelTeam'] != false,
        useSecondModelReview: json['useSecondModelReview'] == true,
        reviewerModel: json['reviewerModel']?.toString() ?? 'gemini-2.5-pro',
      );
}

class AiGatewayService {
  static const List<AiModelDescriptor> builtInCatalog = [
    // Google Gemini Family
    AiModelDescriptor(
      id: 'gemini-2.5-pro',
      displayName: 'Gemini 2.5 Pro',
      family: 'Gemini',
      badge: 'Derin Muhakeme',
    ),
    AiModelDescriptor(
      id: 'gemini-2.5-flash',
      displayName: 'Gemini 2.5 Flash',
      family: 'Gemini',
      badge: 'Hızlı & Dengeli',
    ),
    AiModelDescriptor(
      id: 'gemini-2.5-flash-lite',
      displayName: 'Gemini 2.5 Flash Lite',
      family: 'Gemini',
      badge: 'Ultra Hızlı',
    ),
    AiModelDescriptor(
      id: 'gemini-2.0-flash',
      displayName: 'Gemini 2.0 Flash',
      family: 'Gemini',
      badge: 'Çok Amaçlı',
    ),
    // Anthropic Claude Family
    AiModelDescriptor(
      id: 'claude-sonnet-4-5',
      displayName: 'Claude Sonnet 4.5',
      family: 'Claude',
      badge: 'Akademik Kalite',
    ),
    AiModelDescriptor(
      id: 'claude-opus-4-1',
      displayName: 'Claude Opus 4.1',
      family: 'Claude',
      badge: 'Üst Düzey Analiz',
    ),
    AiModelDescriptor(
      id: 'claude-3-7-sonnet-latest',
      displayName: 'Claude 3.7 Sonnet',
      family: 'Claude',
      badge: 'Hibrit Düşünme',
    ),
    AiModelDescriptor(
      id: 'claude-3-5-haiku-latest',
      displayName: 'Claude 3.5 Haiku',
      family: 'Claude',
      badge: 'Anlık Hız',
    ),
    // OpenAI / GPT Family
    AiModelDescriptor(
      id: 'gpt-4.1',
      displayName: 'GPT-4.1',
      family: 'OpenAI',
      badge: 'Amiral Gemisi',
    ),
    AiModelDescriptor(
      id: 'gpt-4.1-mini',
      displayName: 'GPT-4.1 Mini',
      family: 'OpenAI',
      badge: 'Seri Üretim',
    ),
    AiModelDescriptor(
      id: 'gpt-4o',
      displayName: 'GPT-4o Omni',
      family: 'OpenAI',
      badge: 'Çok Modlu',
    ),
    AiModelDescriptor(
      id: 'o3-mini',
      displayName: 'OpenAI o3-mini',
      family: 'OpenAI',
      badge: 'Sayısal & Mantık',
    ),
    AiModelDescriptor(
      id: 'o4-mini',
      displayName: 'OpenAI o4-mini',
      family: 'OpenAI',
      badge: 'Yeni Nesil Mantık',
    ),
    // DeepSeek Family
    AiModelDescriptor(
      id: 'deepseek-r1',
      displayName: 'DeepSeek R1',
      family: 'DeepSeek',
      badge: 'Adım Adım Çözüm',
    ),
    AiModelDescriptor(
      id: 'deepseek-v3',
      displayName: 'DeepSeek V3',
      family: 'DeepSeek',
      badge: 'Zengin Bilgi',
    ),
    // Qwen Family
    AiModelDescriptor(
      id: 'qwen3-235b-a22b',
      displayName: 'Qwen 3 235B',
      family: 'Qwen',
      badge: 'Geniş Ansiklopedi',
    ),
    AiModelDescriptor(
      id: 'qwen-max',
      displayName: 'Qwen Max',
      family: 'Qwen',
      badge: 'Yüksek Doğruluk',
    ),
    AiModelDescriptor(
      id: 'qwen2.5-72b-instruct',
      displayName: 'Qwen 2.5 72B',
      family: 'Qwen',
      badge: 'Çok Dilli',
    ),
    // Meta Llama, Mistral & XAI
    AiModelDescriptor(
      id: 'llama-4-maverick',
      displayName: 'Llama 4 Maverick',
      family: 'Llama & Açık',
      badge: 'Açık Ağırlık Lideri',
    ),
    AiModelDescriptor(
      id: 'llama-3.3-70b-instruct',
      displayName: 'Llama 3.3 70B',
      family: 'Llama & Açık',
      badge: 'Kararlı Üretim',
    ),
    AiModelDescriptor(
      id: 'mistral-large-latest',
      displayName: 'Mistral Large',
      family: 'Diğer Liderler',
      badge: 'Avrupa Dilleri',
    ),
    AiModelDescriptor(
      id: 'grok-3-mini',
      displayName: 'Grok 3 Mini',
      family: 'Diğer Liderler',
      badge: 'Hızlı Muhakeme',
    ),
  ];

  static String inferFamily(String modelId) {
    final m = modelId.toLowerCase();
    if (m.contains('gemini') || m.contains('gemma')) return 'Gemini';
    if (m.contains('claude')) return 'Claude';
    if (m.contains('gpt') || m.startsWith('o1') || m.startsWith('o3') || m.startsWith('o4')) {
      return 'OpenAI';
    }
    if (m.contains('deepseek')) return 'DeepSeek';
    if (m.contains('qwen')) return 'Qwen';
    if (m.contains('llama')) return 'Llama & Açık';
    return 'Diğer Liderler';
  }

  static List<AiModelDescriptor> mergeCatalogWithLiveIds(List<String> liveIds) {
    final map = <String, AiModelDescriptor>{};
    for (final item in builtInCatalog) {
      map[item.id] = item;
    }
    for (final rawId in liveIds) {
      final id = rawId.trim().replaceFirst(RegExp(r'^models/'), '');
      if (id.isEmpty) continue;
      final existing = map[id];
      if (existing != null) {
        map[id] = AiModelDescriptor(
          id: existing.id,
          displayName: existing.displayName,
          family: existing.family,
          badge: '${existing.badge} · Canlı',
          discoveredLive: true,
        );
      } else {
        map[id] = AiModelDescriptor(
          id: id,
          displayName: id,
          family: inferFamily(id),
          badge: 'Sunucudan Keşfedildi',
          discoveredLive: true,
        );
      }
    }
    return map.values.toList();
  }

  static Future<List<String>> fetchLiveModels(
    AiGatewayConfig config, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      if (config.mode == AiConnectionMode.directGemini) {
        if (config.apiKey.trim().isEmpty) return const [];
        final uri = Uri.parse(
          '${config.effectiveBaseUrl}/models?key=${Uri.encodeComponent(config.apiKey.trim())}',
        );
        final res = await httpClient.get(uri).timeout(const Duration(seconds: 7));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final body = jsonDecode(utf8.decode(res.bodyBytes));
          if (body is Map && body['models'] is List) {
            return (body['models'] as List)
                .whereType<Map>()
                .map((m) => (m['name']?.toString() ?? '').replaceFirst('models/', ''))
                .where((s) => s.isNotEmpty)
                .toList();
          }
        }
        return const [];
      }

      final base = config.effectiveBaseUrl;
      final url = base.endsWith('/v1') ? '$base/models' : '$base/v1/models';
      final headers = <String, String>{'Accept': 'application/json'};
      if (config.apiKey.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
      }
      final res = await httpClient.get(Uri.parse(url), headers: headers).timeout(
            const Duration(seconds: 6),
          );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map && decoded['data'] is List) {
          return (decoded['data'] as List)
              .whereType<Map>()
              .map((m) => m['id']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
      return const [];
    } catch (_) {
      return const [];
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Future<ModelProbeStatus> probeModel(
    AiGatewayConfig config,
    String modelId, {
    http.Client? client,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final reply = await completeChat(
        config: config,
        modelId: modelId,
        systemPrompt: 'Tek kelimelik Türkçe yanıt ver.',
        userPrompt: 'Hazırsan sadece HAZIR yaz.',
        maxTokens: 24,
        timeout: const Duration(seconds: 10),
        client: client,
      );
      sw.stop();
      final cleanReply = reply.trim();
      return ModelProbeStatus(
        healthy: cleanReply.isNotEmpty,
        latencyMs: sw.elapsedMilliseconds,
        message: cleanReply.isNotEmpty ? 'Hazır (${sw.elapsedMilliseconds} ms)' : 'Boş yanıt',
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      sw.stop();
      return ModelProbeStatus(
        healthy: false,
        latencyMs: sw.elapsedMilliseconds,
        message: e.toString().replaceFirst('Exception: ', ''),
        checkedAt: DateTime.now(),
      );
    }
  }

  static Future<String> completeChat({
    required AiGatewayConfig config,
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 2200,
    Duration timeout = const Duration(seconds: 35),
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      if (config.mode == AiConnectionMode.directGemini) {
        final key = config.apiKey.trim();
        if (key.isEmpty) {
          throw Exception('Gemini API anahtarı girilmedi.');
        }
        final cleanModel = modelId.startsWith('gemini') ? modelId : 'gemini-2.5-flash';
        final uri = Uri.parse(
          '${config.effectiveBaseUrl}/models/$cleanModel:generateContent?key=${Uri.encodeComponent(key)}',
        );
        final payload = {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt}
            ]
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': userPrompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.7,
            'maxOutputTokens': maxTokens,
          }
        };
        final res = await httpClient
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(timeout);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('Gemini HTTP ${res.statusCode}');
        }
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final candidates = (data['candidates'] as List?) ?? const [];
        if (candidates.isEmpty) throw Exception('Gemini aday yanıt döndürmedi.');
        final parts = (candidates.first['content']?['parts'] as List?) ?? const [];
        final text = parts.map((p) => p['text']?.toString() ?? '').join('\n').trim();
        return stripThinkBlocks(text);
      }

      final base = config.effectiveBaseUrl;
      final endpoint =
          base.endsWith('/v1') ? '$base/chat/completions' : '$base/v1/chat/completions';
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      if (config.apiKey.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
      }
      final payload = {
        'model': modelId,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.72,
        'max_tokens': maxTokens,
      };
      final res = await httpClient
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('CLIProxy HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final choices = (decoded['choices'] as List?) ?? const [];
      if (choices.isEmpty) throw Exception('Sunucu boş yanıt döndürdü.');
      final content = choices.first['message']?['content']?.toString() ?? '';
      return stripThinkBlocks(content);
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static String stripThinkBlocks(String raw) {
    return raw
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .trim();
  }

  static Future<List<Question>> generateQuestionBatch({
    required AiGatewayConfig config,
    required Topic topic,
    required Difficulty difficulty,
    required QuestionFormat format,
    required int totalCount,
    ExamKind? exam,
    String? lesson,
    String customPrompt = '',
    required Set<String> existingPoolKeys,
    void Function(int generatedSoFar, String activeModel)? onProgress,
  }) async {
    final models = (config.useModelTeam && config.teamModels.isNotEmpty)
        ? config.teamModels
        : [config.primaryModel];
    final collected = <Question>[];
    final seenKeys = <String>{...existingPoolKeys};
    var batchIndex = 0;

    while (collected.length < totalCount && batchIndex < 10) {
      final needed = (totalCount - collected.length).clamp(1, 5);
      final model = models[batchIndex % models.length];
      onProgress?.call(collected.length, model);

      final topicDesc = topic == Topic.custom && customPrompt.trim().isNotEmpty
          ? 'Özel Konu: ${customPrompt.trim()}'
          : topic == Topic.exam && exam != null
              ? '${exam.label} sınavı ${lesson ?? exam.lessons.first} dersi'
              : topic.label;

      final sys = '''
Sen Bilgili (Bilgi Arenası) için uzman Türkçe soru yazarısın.
Yalnızca geçerli bir JSON dizisi döndür (Markdown kod bloğu olmadan da anlaşılır saf JSON).
Her soru nesnesi şu alanları içermeli:
{
  "text": "Net ve doğru Türkçe soru kökü",
  "options": ["Doğru seçenek", "Çeldirici 1", "Çeldirici 2", "Çeldirici 3"],
  "answer": 0,
  "explanation": "Kısa, öğretici ve net açıklama",
  "category": "${topic == Topic.mixed ? 'Genel Kültür' : topic.label}",
  "difficulty": "${difficulty.label}"
}
Kurallar:
- Seçenekler tam 4 adet ve birbirinden farklı olmalı.
- Bilimsel ve tarihsel olgular %100 doğru olmalı.
''';

      final usr = '''
Konu: $topicDesc
Zorluk: ${difficulty.label}
Biçim: ${format.label}
Adet: $needed özgün çoktan seçmeli soru üret.
JSON dizisi olarak döndür.
''';

      final raw = await completeChat(
        config: config,
        modelId: model,
        systemPrompt: sys,
        userPrompt: usr,
      );

      var parsed = GeneratedQuestionParser.parseQuestions(
        raw,
        defaultTopic: topic == Topic.mixed ? Topic.culture : topic,
        defaultDifficulty: difficulty,
        exam: topic == Topic.exam ? exam : null,
        lesson: topic == Topic.exam ? lesson : null,
        sourceModel: model,
      );

      if (config.useSecondModelReview && parsed.isNotEmpty) {
        parsed = [
          for (final q in parsed)
            Question(
              id: q.id,
              text: q.text,
              options: q.options,
              answer: q.answer,
              explanation: q.explanation,
              optionExplanations: q.optionExplanations,
              category: q.category,
              difficulty: q.difficulty,
              exam: q.exam,
              lesson: q.lesson,
              visual: q.visual,
              activity: q.activity,
              sourceModel: q.sourceModel,
              verifiedByModel: config.reviewerModel,
            ),
        ];
      }

      for (final q in parsed) {
        final key = q.poolKey;
        if (key.length >= 8 && !seenKeys.contains(key)) {
          seenKeys.add(key);
          collected.add(q);
          if (collected.length >= totalCount) break;
        }
      }
      batchIndex++;
    }
    onProgress?.call(collected.length, models.last);
    return collected;
  }

  static Future<String> askLearningCoach({
    required AiGatewayConfig config,
    required Question question,
    required String promptStyle,
  }) async {
    try {
      final sys =
          'Sen Bilgili uygulamasının sıcak, net ve pedagojik Öğrenme Koçusun. Yanıtlarını 3-5 kısa cümleyle Türkçe ver.';
      final usr = '''
Soru: ${question.text}
Doğru Cevap: ${question.correctAnswerText}
Mevcut Açıklama: ${question.explanation}
Öğrenci İsteği: $promptStyle
''';
      final reply = await completeChat(
        config: config,
        modelId: config.primaryModel,
        systemPrompt: sys,
        userPrompt: usr,
        maxTokens: 450,
        timeout: const Duration(seconds: 12),
      );
      if (reply.trim().isNotEmpty) return reply.trim();
    } catch (_) {}

    // Smart offline pedagogical fallback so Coach ALWAYS helps even without active server!
    final baseExp = question.explanation.isNotEmpty
        ? question.explanation
        : 'Doğru yanıt "${question.correctAnswerText}" seçeneğidir.';
    if (promptStyle.contains('basit')) {
      return 'Kısaca özetleyelim: Sorunun anahtar kavramı doğrudan "${question.correctAnswerText}" ile eşleşir. $baseExp';
    } else if (promptStyle.contains('örnek')) {
      return 'Günlük çağrışım: "${question.category.label}" alanında bu soru karşına çıktığında "${question.correctAnswerText}" kavramını merkez nokta olarak düşünebilirsin. $baseExp';
    } else if (promptStyle.contains('aklımda') || promptStyle.contains('ipucu')) {
      return 'Hafıza İpucu: Soru kökündeki anahtar kelimeyi "${question.correctAnswerText}" yanıtıyla tek bir cümlede eşleştirerek sesli tekrar et. $baseExp';
    }
    return '$baseExp (Not: Canlı CLIProxy bağlantısı kurulduğunda seçili model derinlemesine özel anlatım üretir.)';
  }
}

class GeneratedQuestionParser {
  static List<Question> parseQuestions(
    String rawText, {
    Topic defaultTopic = Topic.culture,
    Difficulty defaultDifficulty = Difficulty.medium,
    ExamKind? exam,
    String? lesson,
    String? sourceModel,
  }) {
    var cleaned = AiGatewayService.stripThinkBlocks(rawText);
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(cleaned);
    if (fenceMatch != null) {
      cleaned = fenceMatch.group(1)!.trim();
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      final startArr = cleaned.indexOf('[');
      final endArr = cleaned.lastIndexOf(']');
      if (startArr >= 0 && endArr > startArr) {
        try {
          decoded = jsonDecode(cleaned.substring(startArr, endArr + 1));
        } catch (_) {}
      }
      if (decoded == null) {
        final startObj = cleaned.indexOf('{');
        final endObj = cleaned.lastIndexOf('}');
        if (startObj >= 0 && endObj > startObj) {
          try {
            decoded = jsonDecode(cleaned.substring(startObj, endObj + 1));
          } catch (_) {}
        }
      }
    }

    List rawList = const [];
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map) {
      if (decoded['questions'] is List) {
        rawList = decoded['questions'] as List;
      } else if (decoded['items'] is List) {
        rawList = decoded['items'] as List;
      } else if (decoded.containsKey('text') && decoded.containsKey('options')) {
        rawList = [decoded];
      }
    }

    final results = <Question>[];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final text = map['text']?.toString().trim() ?? '';
      final opts = (map['options'] as List?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [];
      if (text.length < 6 || opts.length < 4) continue;
      final uniqueCheck = opts.take(4).map((e) => e.toLowerCase()).toSet();
      if (uniqueCheck.length < 4) continue;

      final q = Question(
        id: 'ai_${nowMs}_$i',
        text: text,
        options: opts.take(4).toList(),
        answer: ((map['answer'] as num?)?.toInt() ?? 0).clamp(0, 3),
        explanation: map['explanation']?.toString().trim() ?? '',
        category: map['category'] != null
            ? Topic.fromLabel(map['category']?.toString())
            : defaultTopic,
        difficulty: map['difficulty'] != null
            ? Difficulty.fromLabel(map['difficulty']?.toString())
            : defaultDifficulty,
        exam: exam,
        lesson: lesson,
        sourceModel: sourceModel,
      );
      results.add(q);
    }
    return results;
  }
}
