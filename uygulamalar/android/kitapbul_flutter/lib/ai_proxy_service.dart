import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AiProviderMode {
  phoneCliProxy(
    'phoneCliProxy',
    'Cep Telefonu CLIProxyAPI',
    'Telefondaki yerel 127.0.0.1:8317 proxy servisi',
  ),
  customCliProxy(
    'customCliProxy',
    'Özel / Bulut CLIProxyAPI',
    'Yerel ağ veya uzak sunucudaki CLIProxy adresi',
  ),
  directGemini(
    'directGemini',
    'Doğrudan Google Gemini API',
    'Google AI Studio anahtarıyla Interactions v1beta',
  );

  const AiProviderMode(this.id, this.title, this.subtitle);
  final String id;
  final String title;
  final String subtitle;

  static AiProviderMode fromId(String? raw) {
    for (final m in AiProviderMode.values) {
      if (m.id == raw) return m;
    }
    return AiProviderMode.phoneCliProxy;
  }
}

class AiProxySettings {
  const AiProxySettings({
    this.mode = AiProviderMode.phoneCliProxy,
    this.baseUrl = 'http://127.0.0.1:8317',
    this.apiKey = '',
    this.visionModel = 'gemini-3.8-flash',
    this.assistantModel = 'gemini-3.8-flash',
    this.autoEnrichOnline = true,
    this.voiceAutoSpeak = true,
    this.handsFreeLoop = false,
    this.ttsRate = 1.05,
    this.ttsVoice = 'tr-TR-AhmetNeural',
    this.cachedModels = const <String>[],
  });

  final AiProviderMode mode;
  final String baseUrl;
  final String apiKey;
  final String visionModel;
  final String assistantModel;
  final bool autoEnrichOnline;
  final bool voiceAutoSpeak;
  final bool handsFreeLoop;
  final double ttsRate;
  final String ttsVoice;
  final List<String> cachedModels;

  String get effectiveBaseUrl {
    if (mode == AiProviderMode.phoneCliProxy) {
      final trimmed = baseUrl.trim();
      if (trimmed.isEmpty) return 'http://127.0.0.1:8317';
      return trimmed.replaceAll(RegExp(r'/+$'), '');
    }
    if (mode == AiProviderMode.directGemini) {
      return 'https://generativelanguage.googleapis.com';
    }
    final trimmed = baseUrl.trim();
    return (trimmed.isEmpty ? 'http://127.0.0.1:8317' : trimmed)
        .replaceAll(RegExp(r'/+$'), '');
  }

  bool get hasCredentials =>
      apiKey.trim().isNotEmpty || mode != AiProviderMode.directGemini;

  AiProxySettings copyWith({
    AiProviderMode? mode,
    String? baseUrl,
    String? apiKey,
    String? visionModel,
    String? assistantModel,
    bool? autoEnrichOnline,
    bool? voiceAutoSpeak,
    bool? handsFreeLoop,
    double? ttsRate,
    String? ttsVoice,
    List<String>? cachedModels,
  }) {
    return AiProxySettings(
      mode: mode ?? this.mode,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      visionModel: visionModel ?? this.visionModel,
      assistantModel: assistantModel ?? this.assistantModel,
      autoEnrichOnline: autoEnrichOnline ?? this.autoEnrichOnline,
      voiceAutoSpeak: voiceAutoSpeak ?? this.voiceAutoSpeak,
      handsFreeLoop: handsFreeLoop ?? this.handsFreeLoop,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      cachedModels: cachedModels ?? this.cachedModels,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'mode': mode.id,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'visionModel': visionModel,
    'assistantModel': assistantModel,
    'autoEnrichOnline': autoEnrichOnline,
    'voiceAutoSpeak': voiceAutoSpeak,
    'handsFreeLoop': handsFreeLoop,
    'ttsRate': ttsRate,
    'ttsVoice': ttsVoice,
    'cachedModels': cachedModels,
  };

  factory AiProxySettings.fromJson(Map<String, dynamic> json) {
    final models = (json['cachedModels'] as List?)
            ?.whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final rawVoice = (json['ttsVoice'] ?? 'tr-TR-AhmetNeural').toString().trim();
    return AiProxySettings(
      mode: AiProviderMode.fromId(json['mode']?.toString()),
      baseUrl: (json['baseUrl'] ?? 'http://127.0.0.1:8317').toString(),
      apiKey: (json['apiKey'] ?? '').toString(),
      visionModel: _sanitizeModelName(
        (json['visionModel'] ?? 'gemini-3.8-flash').toString(),
      ),
      assistantModel: _sanitizeModelName(
        (json['assistantModel'] ?? 'gemini-3.8-flash').toString(),
      ),
      autoEnrichOnline: json['autoEnrichOnline'] != false,
      voiceAutoSpeak: json['voiceAutoSpeak'] != false,
      handsFreeLoop: json['handsFreeLoop'] == true,
      ttsRate: ((json['ttsRate'] as num?)?.toDouble() ?? 1.05).clamp(0.6, 1.8),
      ttsVoice: rawVoice.isEmpty ? 'tr-TR-AhmetNeural' : rawVoice,
      cachedModels: models,
    );
  }
}

String _sanitizeModelName(String raw) {
  final clean = raw.trim();
  if (clean.isEmpty) return 'gemini-3.8-flash';
  return clean;
}

/// CLIProxyAPI sağlayıcı ailesini model ID ve `owned_by` etiketinden çıkarır.
String inferAiModelProvider(String modelId, {String? ownedBy}) {
  final m = '${modelId.toLowerCase()} ${(ownedBy ?? '').toLowerCase()}';
  if (m.contains('gemini') || m.contains('google') || m.contains('antigravity')) {
    return 'Gemini';
  }
  if (m.contains('claude') || m.contains('anthropic')) {
    return 'Claude';
  }
  if (m.contains('gpt') ||
      m.contains('codex') ||
      m.contains('openai') ||
      RegExp(r'\bo[134](?:-|$|\b)').hasMatch(modelId.toLowerCase())) {
    return 'GPT / Codex';
  }
  if (m.contains('deepseek')) {
    return 'DeepSeek';
  }
  if (m.contains('qwen') || m.contains('alibaba')) {
    return 'Qwen';
  }
  if (m.contains('grok') || m.contains('xai')) {
    return 'Grok';
  }
  if (m.contains('kimi') || m.contains('moonshot') || m.contains('glm') || m.contains('llama') || m.contains('mistral')) {
    return 'Açık / Diğer';
  }
  return 'Özel';
}

final ValueNotifier<AiProxySettings> aiSettingsNotifier =
    ValueNotifier<AiProxySettings>(const AiProxySettings());

class AiProxyStore {
  AiProxyStore(this.directory);
  final Directory directory;

  static AiProxyStore? instance;

  File get file => File('${directory.path}/ai_proxy_settings.json');

  Future<AiProxySettings> load() async {
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          final loaded = AiProxySettings.fromJson(decoded);
          aiSettingsNotifier.value = loaded;
          return loaded;
        }
      }
    } catch (_) {}
    return aiSettingsNotifier.value;
  }

  Future<void> save(AiProxySettings next) async {
    aiSettingsNotifier.value = next;
    try {
      await directory.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(next.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }
}

class AiImagePart {
  const AiImagePart({
    required this.bytes,
    this.mimeType = 'image/jpeg',
    this.label = '',
  });

  final Uint8List bytes;
  final String mimeType;
  final String label;
}

class CliProxyProbeResult {
  const CliProxyProbeResult({
    required this.reachable,
    required this.authorized,
    required this.statusCode,
    required this.latencyMs,
    required this.serverBanner,
    this.models = const [],
    this.modelOwners = const <String, String>{},
    this.message = '',
  });

  final bool reachable;
  final bool authorized;
  final int statusCode;
  final int latencyMs;
  final String serverBanner;
  final List<String> models;
  final Map<String, String> modelOwners;
  final String message;
}

/// Model yanıtından `<think>...</think>` ve ```json ... ``` bloklarını ayıklayıp
/// geçerli JSON nesnesini veya dizisini çıkarır.
dynamic extractJsonFromModelText(String rawText) {
  var cleaned = rawText
      .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
      .trim();
  if (cleaned.isEmpty) {
    throw const FormatException('Model boş yanıt döndürdü');
  }

  // Markdown ```json ... ``` bloğu varsa içini al
  final fenced = RegExp(
    r'```(?:json)?\s*([\s\S]*?)```',
    caseSensitive: false,
  ).firstMatch(cleaned);
  if (fenced != null && (fenced.group(1) ?? '').trim().isNotEmpty) {
    cleaned = fenced.group(1)!.trim();
  }

  try {
    return jsonDecode(cleaned);
  } catch (_) {
    // İlk '{' veya '[' ile son '}' veya ']' arasını dene
    final objStart = cleaned.indexOf('{');
    final objEnd = cleaned.lastIndexOf('}');
    final arrStart = cleaned.indexOf('[');
    final arrEnd = cleaned.lastIndexOf(']');

    if (objStart >= 0 &&
        objEnd > objStart &&
        (arrStart < 0 || objStart < arrStart)) {
      return jsonDecode(cleaned.substring(objStart, objEnd + 1));
    }
    if (arrStart >= 0 && arrEnd > arrStart) {
      return jsonDecode(cleaned.substring(arrStart, arrEnd + 1));
    }
    rethrow;
  }
}

/// Tüm CLIProxy ve sağlanan modelleri hiçbir modeli elemeden akıllı sırayla döndürür
/// (`gemini-3.8-flash` en üstte; 2.5, 2.0, Claude, GPT/Codex, DeepSeek, Qwen vb. dahil).
List<String> prioritizeVisionModels(Iterable<String> rawModels) {
  final unique = <String>[];
  for (final m in rawModels) {
    final clean = m.trim();
    if (clean.isEmpty) continue;
    if (!unique.contains(clean)) unique.add(clean);
  }

  int score(String m) {
    final low = m.toLowerCase();
    if (low == 'gemini-3.8-flash') return 1000;
    if (low.contains('gemini-3.8')) return 970;
    if (low.contains('gemini-4-argon')) return 950;
    if (low.contains('gemini-4-carbon')) return 940;
    if (low.contains('gemini-3.5-flash')) return 920;
    if (low.contains('gemini-3.1')) return 905;
    if (low.contains('gemini-3-pro')) return 895;
    if (low.contains('gemini-3-flash')) return 890;
    if (low.contains('gemini-2.5-pro')) return 880;
    if (low.contains('gemini-2.5-flash')) return 875;
    if (low.contains('gemini') && low.contains('flash')) return 860;
    if (low.contains('gemini')) return 840;
    if (low.contains('claude-opus-4') || low.contains('claude-sonnet-4')) {
      return 820;
    }
    if (low.contains('claude')) return 795;
    if (low.contains('gpt-5.4') || low.contains('gpt-5.3') || low.contains('gpt-5.2')) {
      return 785;
    }
    if (low.contains('gpt-5') || low.contains('gpt-6') || low.contains('gpt-4o')) {
      return 770;
    }
    if (low.contains('codex') || low.contains('gpt-4.1') || low.startsWith('o4') || low.startsWith('o3')) {
      return 755;
    }
    if (low.contains('qwen')) return 720;
    if (low.contains('deepseek')) return 705;
    if (low.contains('grok')) return 690;
    if (low.contains('kimi') || low.contains('glm') || low.contains('llama') || low.contains('mistral')) {
      return 675;
    }
    return 600;
  }

  unique.sort((a, b) => score(b).compareTo(score(a)));
  return unique;
}

class AiProxyClient {
  const AiProxyClient._();

  /// Tüm CLIProxyAPI sağlayıcı ailesi (Gemini, Antigravity, Claude, GPT/Codex,
  /// Qwen, DeepSeek, Grok, Kimi, GLM, Llama) için yerleşik tam model kataloğu.
  static const defaultSuggestedModels = <String>[
    // Google Gemini & Antigravity
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-4-argon',
    'gemini-4-carbon',
    'gemini-3.1-pro-preview',
    'gemini-3.1-flash-lite',
    'gemini-3-pro-preview',
    'gemini-3-pro-image-preview',
    'gemini-3-flash-preview',
    'gemini-2.5-pro',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash-image',
    'gemini-2.0-flash',
    'gemini-pro-latest',
    'gemini-flash-latest',
    // Anthropic Claude (Claude Code / OAuth)
    'claude-opus-4-6',
    'claude-sonnet-4-6',
    'claude-haiku-4-5-20251001',
    'claude-opus-4-5-20251101',
    'claude-sonnet-4-5-20250929',
    'claude-opus-4-1',
    'claude-sonnet-4',
    'claude-3-7-sonnet-20250219',
    'claude-3-5-sonnet-20241022',
    'claude-3-5-haiku-20241022',
    // OpenAI / ChatGPT Codex
    'gpt-5.4',
    'gpt-5.3-codex',
    'gpt-5.2-codex',
    'gpt-5.1-codex',
    'gpt-5.1',
    'gpt-5',
    'gpt-5-mini',
    'gpt-5-nano',
    'gpt-5-codex',
    'gpt-4.1',
    'gpt-4.1-mini',
    'gpt-4o',
    'gpt-4o-mini',
    'o4-mini',
    'o3',
    'o3-mini',
    'codex-mini-latest',
    // Qwen & Alibaba
    'qwen3-coder-plus',
    'qwen3-coder-flash',
    'qwen3-max',
    'qwen3-235b-a22b',
    'qwen-plus',
    'qwen-vl-max',
    'qwen-vl-plus',
    // DeepSeek
    'deepseek-r1',
    'deepseek-v3.2',
    'deepseek-v3.1',
    'deepseek-v3',
    'deepseek-chat',
    'deepseek-reasoner',
    // Grok / Kimi / GLM / Llama
    'grok-4',
    'grok-3',
    'kimi-k2',
    'kimi-k2-thinking',
    'glm-4.7',
    'glm-4.6',
    'glm-4.5',
    'llama-4-maverick',
    'llama-3.3-70b-instruct',
  ];

  /// Canlı sunucu modellerini, önbellekteki modelleri ve tüm yerleşik CLIProxy
  /// sağlayıcı kataloğunu tekilleştirip akıllı öncelik sırasıyla birleştirir.
  static List<String> buildCombinedModelPool({
    Iterable<String> serverModels = const [],
    Iterable<String> cachedModels = const [],
  }) {
    final serverFirst = <String>[];
    final seen = <String>{};
    for (final m in [...serverModels, ...cachedModels]) {
      final clean = m.trim();
      if (clean.isEmpty || !seen.add(clean)) continue;
      serverFirst.add(clean);
    }
    final orderedServer = prioritizeVisionModels(serverFirst);
    for (final m in defaultSuggestedModels) {
      if (seen.add(m)) orderedServer.add(m);
    }
    return orderedServer;
  }

  static void _parseModelsJsonInto(
    dynamic parsed,
    List<String> rawList,
    Map<String, String> owners,
  ) {
    if (parsed is Map && parsed['data'] is List) {
      for (final item in parsed['data'] as List) {
        if (item is Map && item['id'] != null) {
          final id = item['id'].toString().trim();
          if (id.isEmpty) continue;
          if (!rawList.contains(id)) rawList.add(id);
          final owner = (item['owned_by'] ?? '').toString().trim();
          if (owner.isNotEmpty) owners[id] = owner;
        }
      }
    }
    if (parsed is Map && parsed['models'] is List) {
      for (final item in parsed['models'] as List) {
        if (item is Map && item['name'] != null) {
          final id = item['name']
              .toString()
              .replaceFirst('models/', '')
              .trim();
          if (id.isEmpty) continue;
          if (!rawList.contains(id)) rawList.add(id);
          final display = (item['displayName'] ?? '').toString().trim();
          if (display.isNotEmpty && !owners.containsKey(id)) {
            owners[id] = 'gemini';
          }
        }
      }
    }
  }

  /// Telefondaki `127.0.0.1:8317` veya seçili CLIProxy sunucusunu yoklar ve
  /// `/v1/models` (+ yedeği `/v1beta/models`) üzerinden TÜM modelleri çeker.
  static Future<CliProxyProbeResult> probeAndFetchModels({
    AiProxySettings? overrideSettings,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final cfg = overrideSettings ?? aiSettingsNotifier.value;
    final sw = Stopwatch()..start();

    if (cfg.mode == AiProviderMode.directGemini) {
      if (cfg.apiKey.trim().isEmpty) {
        return const CliProxyProbeResult(
          reachable: true,
          authorized: false,
          statusCode: 401,
          latencyMs: 0,
          serverBanner: 'Google Gemini Interactions API',
          models: defaultSuggestedModels,
          message: 'Google AI Studio API anahtarı girilmedi.',
        );
      }
      final client = HttpClient()..connectionTimeout = timeout;
      try {
        // Doğrudan Google Gemini hesabındaki tüm modelleri çek
        final listUri = Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models',
        );
        final listReq = await client.getUrl(listUri).timeout(timeout);
        listReq.headers.set('x-goog-api-key', cfg.apiKey.trim());
        final listResp = await listReq.close().timeout(timeout);
        final listBody = await utf8.decodeStream(listResp).timeout(timeout);
        if (listResp.statusCode == 200) {
          final rawList = <String>[];
          final owners = <String, String>{};
          _parseModelsJsonInto(jsonDecode(listBody), rawList, owners);
          sw.stop();
          final ordered = prioritizeVisionModels(
            rawList.isEmpty ? defaultSuggestedModels : rawList,
          );
          return CliProxyProbeResult(
            reachable: true,
            authorized: true,
            statusCode: 200,
            latencyMs: sw.elapsedMilliseconds,
            serverBanner: 'Google Gemini API',
            models: ordered,
            modelOwners: owners,
            message:
                'Google Gemini API doğrulandı (${ordered.length} model · ${sw.elapsedMilliseconds} ms).',
          );
        }

        // `/v1beta/models` kısıtlıysa doğrudan Interactions doğrulamasına düş
        final activeModel = _sanitizeModelName(cfg.assistantModel);
        final reply = await _callDirectGeminiInteractions(
          apiKey: cfg.apiKey.trim(),
          model: activeModel,
          promptText: 'Yalnızca OK yaz.',
          images: const [],
          timeout: timeout,
        );
        sw.stop();
        return CliProxyProbeResult(
          reachable: true,
          authorized: reply.isNotEmpty,
          statusCode: 200,
          latencyMs: sw.elapsedMilliseconds,
          serverBanner: 'Google Gemini API (Interactions v1beta)',
          models: defaultSuggestedModels,
          message: 'Google Gemini bağlantısı doğrulandı ($activeModel).',
        );
      } catch (e) {
        sw.stop();
        return CliProxyProbeResult(
          reachable: false,
          authorized: false,
          statusCode: 0,
          latencyMs: sw.elapsedMilliseconds,
          serverBanner: 'Google Gemini API',
          models: defaultSuggestedModels,
          message: '$e',
        );
      } finally {
        client.close(force: true);
      }
    }

    final base = cfg.effectiveBaseUrl;
    final uri = Uri.parse(
      base.endsWith('/v1') ? '$base/models' : '$base/v1/models',
    );
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(uri).timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final key = cfg.apiKey.trim();
      if (key.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
        req.headers.set('x-goog-api-key', key);
      }
      final resp = await req.close().timeout(timeout);
      final body = await utf8.decodeStream(resp).timeout(timeout);
      final serverHeader = resp.headers.value('server') ?? 'CLIProxyAPI';

      if (resp.statusCode == 200) {
        final rawList = <String>[];
        final owners = <String, String>{};
        _parseModelsJsonInto(jsonDecode(body), rawList, owners);

        // Bazı CLIProxy yapılandırmalarında ek modeller `/v1beta/models` altında olabilir
        if (rawList.isEmpty && !base.endsWith('/v1beta')) {
          try {
            final rootBase = base.replaceAll(RegExp(r'/v1$'), '');
            final betaUri = Uri.parse('$rootBase/v1beta/models');
            final betaReq = await client.getUrl(betaUri).timeout(
              const Duration(seconds: 3),
            );
            betaReq.headers.set(HttpHeaders.acceptHeader, 'application/json');
            if (key.isNotEmpty) {
              betaReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
              betaReq.headers.set('x-goog-api-key', key);
            }
            final betaResp = await betaReq.close().timeout(
              const Duration(seconds: 3),
            );
            if (betaResp.statusCode == 200) {
              final betaBody = await utf8.decodeStream(betaResp).timeout(
                const Duration(seconds: 3),
              );
              _parseModelsJsonInto(jsonDecode(betaBody), rawList, owners);
            }
          } catch (_) {}
        }

        sw.stop();
        final ordered = prioritizeVisionModels([
          ...rawList,
          if (rawList.isEmpty) ...defaultSuggestedModels,
        ]);
        return CliProxyProbeResult(
          reachable: true,
          authorized: true,
          statusCode: 200,
          latencyMs: sw.elapsedMilliseconds,
          serverBanner: serverHeader,
          models: ordered,
          modelOwners: owners,
          message: rawList.isNotEmpty
              ? '$serverHeader bağlandı (${ordered.length} canlı model · ${sw.elapsedMilliseconds} ms).'
              : '$serverHeader bağlandı (varsayılan ${ordered.length} model katalogu · ${sw.elapsedMilliseconds} ms).',
        );
      }
      sw.stop();

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        String errDetail = 'API anahtarı gerekli veya geçersiz.';
        try {
          final errMap = jsonDecode(body);
          if (errMap is Map &&
              errMap['error'] is Map &&
              errMap['error']['message'] != null) {
            errDetail = errMap['error']['message'].toString();
          }
        } catch (_) {}
        return CliProxyProbeResult(
          reachable: true,
          authorized: false,
          statusCode: resp.statusCode,
          latencyMs: sw.elapsedMilliseconds,
          serverBanner: serverHeader,
          models: defaultSuggestedModels,
          message:
              '$serverHeader algılandı ($base) — $errDetail Lütfen CLIProxy anahtarınızı girin.',
        );
      }

      return CliProxyProbeResult(
        reachable: true,
        authorized: false,
        statusCode: resp.statusCode,
        latencyMs: sw.elapsedMilliseconds,
        serverBanner: serverHeader,
        models: defaultSuggestedModels,
        message: 'Sunucu HTTP ${resp.statusCode} döndürdü.',
      );
    } catch (e) {
      sw.stop();
      return CliProxyProbeResult(
        reachable: false,
        authorized: false,
        statusCode: 0,
        latencyMs: sw.elapsedMilliseconds,
        serverBanner: 'Ulaşılamadı',
        models: defaultSuggestedModels,
        message:
            '$base adresindeki CLIProxy servisine ulaşılamadı. Telefondaki CLIProxy uygulamasının açık olduğundan emin olun.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Görsel + metin istemini CLIProxyAPI veya doğrudan Gemini 3.8 Flash üzerinden çalıştırıp
  /// ayrıştırılmış JSON nesnesi döner.
  static Future<dynamic> generateStructuredJson({
    required String systemPrompt,
    required String userPrompt,
    List<AiImagePart> images = const [],
    Map<String, dynamic>? geminiJsonSchema,
    AiProxySettings? overrideSettings,
    Duration timeout = const Duration(seconds: 65),
  }) async {
    final text = await generateText(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      images: images,
      expectJson: true,
      geminiJsonSchema: geminiJsonSchema,
      useVisionModel: images.isNotEmpty,
      overrideSettings: overrideSettings,
      timeout: timeout,
    );
    return extractJsonFromModelText(text);
  }

  /// Hem çoklu görsel (OCR / Raf okuma) hem de metin/sesli asistan sohbeti için ortak çağrı.
  static Future<String> generateText({
    required String systemPrompt,
    required String userPrompt,
    List<AiImagePart> images = const [],
    bool expectJson = false,
    Map<String, dynamic>? geminiJsonSchema,
    bool useVisionModel = false,
    AiProxySettings? overrideSettings,
    Duration timeout = const Duration(seconds: 65),
  }) async {
    final cfg = overrideSettings ?? aiSettingsNotifier.value;
    final chosenModel = _sanitizeModelName(
      useVisionModel ? cfg.visionModel : cfg.assistantModel,
    );

    if (cfg.mode == AiProviderMode.directGemini) {
      final key = cfg.apiKey.trim();
      if (key.isEmpty) {
        throw const FormatException(
          'Google Gemini API anahtarı girilmemiş. Yapay Zekâ Ayarlarından anahtar girin veya CLIProxy modunu seçin.',
        );
      }
      return _callDirectGeminiInteractions(
        apiKey: key,
        model: chosenModel,
        systemInstruction: systemPrompt,
        promptText: userPrompt,
        images: images,
        jsonSchema: expectJson ? geminiJsonSchema : null,
        expectJson: expectJson,
        timeout: timeout,
      );
    }

    // CLIProxyAPI (/v1/chat/completions — OpenAI uyumlu çoklu görsel + metin katmanı)
    try {
      return await _callCliProxyChatCompletions(
        baseUrl: cfg.effectiveBaseUrl,
        apiKey: cfg.apiKey.trim(),
        model: chosenModel,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        images: images,
        expectJson: expectJson,
        timeout: timeout,
      );
    } on _CliProxyModelNotFoundException {
      // Seçili model takma adı CLIProxy'de farklıysa /v1/models üzerinden en uygun modeli otomatik bul!
      final probe = await probeAndFetchModels(overrideSettings: cfg);
      if (probe.authorized && probe.models.isNotEmpty) {
        final fallbackModel = probe.models.first;
        if (fallbackModel != chosenModel) {
          final updated = useVisionModel
              ? cfg.copyWith(
                  visionModel: fallbackModel,
                  cachedModels: probe.models,
                )
              : cfg.copyWith(
                  assistantModel: fallbackModel,
                  cachedModels: probe.models,
                );
          await AiProxyStore.instance?.save(updated);
          return _callCliProxyChatCompletions(
            baseUrl: cfg.effectiveBaseUrl,
            apiKey: cfg.apiKey.trim(),
            model: fallbackModel,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images,
            expectJson: expectJson,
            timeout: timeout,
          );
        }
      }
      rethrow;
    }
  }

  static Future<String> _callCliProxyChatCompletions({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required List<AiImagePart> images,
    required bool expectJson,
    required Duration timeout,
  }) async {
    final endpoint = Uri.parse(
      baseUrl.endsWith('/v1')
          ? '$baseUrl/chat/completions'
          : '$baseUrl/v1/chat/completions',
    );

    final dynamic userContent;
    if (images.isEmpty) {
      userContent = userPrompt;
    } else {
      final parts = <Map<String, dynamic>>[
        {'type': 'text', 'text': userPrompt},
      ];
      for (final img in images) {
        if (img.label.isNotEmpty) {
          parts.add({'type': 'text', 'text': '[Görsel: ${img.label}]'});
        }
        final b64 = base64Encode(img.bytes);
        parts.add({
          'type': 'image_url',
          'image_url': {'url': 'data:${img.mimeType};base64,$b64'},
        });
      }
      userContent = parts;
    }

    final lowModel = model.toLowerCase();
    final isOpenAiReasoning =
        lowModel.startsWith('o1') ||
        lowModel.startsWith('o3') ||
        lowModel.startsWith('o4');

    final payload = <String, dynamic>{
      'model': model,
      'messages': [
        if (systemPrompt.trim().isNotEmpty)
          {'role': 'system', 'content': systemPrompt.trim()},
        {'role': 'user', 'content': userContent},
      ],
      if (!isOpenAiReasoning) 'temperature': expectJson ? 0.1 : 0.35,
    };

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.postUrl(endpoint).timeout(timeout);
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (apiKey.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        req.headers.set('x-goog-api-key', apiKey);
      }
      req.add(utf8.encode(jsonEncode(payload)));

      final resp = await req.close().timeout(timeout);
      final body = await utf8.decodeStream(resp).timeout(timeout);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const FormatException(
          'CLIProxyAPI kimlik doğrulaması başarısız (401). Lütfen Yapay Zekâ Ayarlarından CLIProxy API anahtarınızı kontrol edin.',
        );
      }
      if (resp.statusCode == 404 ||
          (resp.statusCode >= 400 &&
              (body.toLowerCase().contains('model') &&
                  body.toLowerCase().contains('not found')))) {
        throw _CliProxyModelNotFoundException(
          'Model bulunamadı: $model (HTTP ${resp.statusCode})',
        );
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String detail = body;
        try {
          final m = jsonDecode(body);
          if (m is Map && m['error'] is Map && m['error']['message'] != null) {
            detail = m['error']['message'].toString();
          }
        } catch (_) {}
        throw HttpException(
          'CLIProxyAPI hatası (HTTP ${resp.statusCode}): $detail',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['choices'] is List) {
        final choices = decoded['choices'] as List;
        if (choices.isNotEmpty && choices.first is Map) {
          final firstChoice = choices.first as Map;
          final msg = firstChoice['message'];
          if (msg is Map) {
            final content = msg['content'];
            if (content is String && content.trim().isNotEmpty) {
              return content.trim();
            }
            if (content is List) {
              final joined = content
                  .whereType<Map>()
                  .map((p) => (p['text'] ?? '').toString())
                  .where((s) => s.isNotEmpty)
                  .join('\n')
                  .trim();
              if (joined.isNotEmpty) return joined;
            }
            final reasoning = msg['reasoning_content'];
            if (reasoning is String && reasoning.trim().isNotEmpty) {
              return reasoning.trim();
            }
          }
          final altText = firstChoice['text'];
          if (altText is String && altText.trim().isNotEmpty) {
            return altText.trim();
          }
        }
      }
      if (decoded is Map && decoded['candidates'] is List) {
        final cands = decoded['candidates'] as List;
        if (cands.isNotEmpty && cands.first is Map) {
          final content = (cands.first as Map)['content'];
          if (content is Map && content['parts'] is List) {
            final joined = (content['parts'] as List)
                .whereType<Map>()
                .map((p) => (p['text'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .join('\n')
                .trim();
            if (joined.isNotEmpty) return joined;
          }
        }
      }
      throw const FormatException('CLIProxyAPI yanıtında metin bulunamadı.');
    } finally {
      client.close(force: true);
    }
  }

  /// Güncel Google Gemini Interactions REST API (`POST /v1beta/interactions`, `Api-Revision: 2026-05-20`).
  static Future<String> _callDirectGeminiInteractions({
    required String apiKey,
    required String model,
    String systemInstruction = '',
    required String promptText,
    required List<AiImagePart> images,
    Map<String, dynamic>? jsonSchema,
    bool expectJson = false,
    required Duration timeout,
  }) async {
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/interactions',
    );
    final inputItems = <Map<String, dynamic>>[
      {'type': 'text', 'text': promptText},
    ];
    for (final img in images) {
      if (img.label.isNotEmpty) {
        inputItems.add({'type': 'text', 'text': '[Görsel: ${img.label}]'});
      }
      inputItems.add({
        'type': 'image',
        'data': base64Encode(img.bytes),
        'mime_type': img.mimeType,
      });
    }

    final payload = <String, dynamic>{
      'model': model,
      'store': false,
      if (systemInstruction.trim().isNotEmpty)
        'system_instruction': systemInstruction.trim(),
      'input': inputItems,
      if (expectJson)
        'response_format': {
          'type': 'text',
          'mime_type': 'application/json',
          'schema': ?jsonSchema,
        },
    };

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.postUrl(uri).timeout(timeout);
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      req.headers.set('x-goog-api-key', apiKey);
      req.headers.set('Api-Revision', '2026-05-20');
      req.add(utf8.encode(jsonEncode(payload)));

      final resp = await req.close().timeout(timeout);
      final body = await utf8.decodeStream(resp).timeout(timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException(
          'Gemini Interactions API hatası (HTTP ${resp.statusCode}): $body',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['steps'] is List) {
        final buf = StringBuffer();
        for (final step in decoded['steps'] as List) {
          if (step is Map &&
              step['type'] == 'model_output' &&
              step['content'] is List) {
            for (final part in step['content'] as List) {
              if (part is Map &&
                  part['type'] == 'text' &&
                  part['text'] is String) {
                buf.write(part['text'] as String);
              }
            }
          }
        }
        final out = buf.toString().trim();
        if (out.isNotEmpty) return out;
      }
      throw const FormatException('Gemini API yanıtında model_output bulunamadı.');
    } finally {
      client.close(force: true);
    }
  }
}

class _CliProxyModelNotFoundException implements Exception {
  const _CliProxyModelNotFoundException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Yerel Android SpeechRecognizer + TextToSpeech denetleyicisi (`kitapbul/voice`).
class VoiceEvent {
  const VoiceEvent({
    required this.type,
    this.text = '',
    this.value = 0,
  });

  final String type;
  final String text;
  final double value;
}

class NativeVoiceController {
  NativeVoiceController._() {
    _channel.setMethodCallHandler(_handleCall);
  }

  static final NativeVoiceController instance = NativeVoiceController._();
  static const MethodChannel _channel = MethodChannel('kitapbul/voice');

  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();

  Stream<VoiceEvent> get events => _events.stream;

  Future<void> _handleCall(MethodCall call) async {
    if (call.method == 'onVoiceEvent' && call.arguments is Map) {
      final map = Map<String, dynamic>.from(call.arguments as Map);
      _events.add(
        VoiceEvent(
          type: (map['type'] ?? '').toString(),
          text: (map['text'] ?? '').toString(),
          value: (map['value'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
  }

  Future<Map<String, dynamic>> status() async {
    try {
      final res = await _channel.invokeMethod<Map>('status');
      if (res != null) return Map<String, dynamic>.from(res);
    } catch (_) {}
    return const {
      'micPermission': false,
      'speechAvailable': false,
      'ttsReady': false,
      'listening': false,
    };
  }

  Future<bool> startListening({String locale = 'tr-TR'}) async {
    final ok = await _channel.invokeMethod<bool>('startListening', {
      'locale': locale,
    });
    return ok == true;
  }

  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopListening');
    } catch (_) {}
  }

  Future<void> cancelListening() async {
    try {
      await _channel.invokeMethod('cancelListening');
    } catch (_) {}
  }

  Future<bool> speak(
    String text, {
    double? rate,
    double pitch = 1.0,
    String? voice,
  }) async {
    if (text.trim().isEmpty) return false;
    try {
      final effectiveRate = rate ?? aiSettingsNotifier.value.ttsRate;
      final effectiveVoice = voice ?? aiSettingsNotifier.value.ttsVoice;
      final ok = await _channel.invokeMethod<bool>('speak', {
        'text': text,
        'rate': effectiveRate,
        'pitch': pitch,
        'voice': effectiveVoice,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _channel.invokeMethod('stopSpeaking');
    } catch (_) {}
  }
}

/// Yapay Zekâ, Cep Telefonu CLIProxyAPI ve Sesli Asistan Ayarları Alt Penceresi.
Future<void> showAiProxySettingsSheet(BuildContext context) async {
  var draft = aiSettingsNotifier.value;
  final urlCtrl = TextEditingController(text: draft.baseUrl);
  final keyCtrl = TextEditingController(text: draft.apiKey);
  final visionCtrl = TextEditingController(text: draft.visionModel);
  final assistantCtrl = TextEditingController(text: draft.assistantModel);

  CliProxyProbeResult? probeResult;
  bool probing = false;
  bool obscureKey = true;
  bool initialProbed = false;
  String selectedProvider = 'Tümü';
  String applyTarget = 'both'; // 'both' | 'vision' | 'assistant'

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, refresh) {
          Future<void> runProbe() async {
            refresh(() => probing = true);
            final candidate = draft.copyWith(
              baseUrl: urlCtrl.text.trim().isEmpty
                  ? 'http://127.0.0.1:8317'
                  : urlCtrl.text.trim(),
              apiKey: keyCtrl.text.trim(),
              visionModel: visionCtrl.text.trim(),
              assistantModel: assistantCtrl.text.trim(),
            );
            final res = await AiProxyClient.probeAndFetchModels(
              overrideSettings: candidate,
            );
            if (!ctx.mounted) return;
            refresh(() {
              probing = false;
              probeResult = res;
              if (res.authorized && res.models.isNotEmpty) {
                draft = candidate.copyWith(cachedModels: res.models);
                if (visionCtrl.text.trim().isEmpty) {
                  visionCtrl.text = res.models.first;
                }
                if (assistantCtrl.text.trim().isEmpty) {
                  assistantCtrl.text = res.models.first;
                }
              }
            });
          }

          if (!initialProbed) {
            initialProbed = true;
            Future.microtask(runProbe);
          }

          final scheme = Theme.of(ctx).colorScheme;
          final liveServerModels = (probeResult?.authorized == true)
              ? probeResult!.models.toSet()
              : draft.cachedModels.toSet();
          final owners = probeResult?.modelOwners ?? const <String, String>{};
          final fullPool = AiProxyClient.buildCombinedModelPool(
            serverModels: probeResult?.models ?? const <String>[],
            cachedModels: draft.cachedModels,
          );

          final providerCategories = <String>[
            'Tümü',
            if (liveServerModels.isNotEmpty) 'Canlı Sunucu',
            'Gemini',
            'Claude',
            'GPT / Codex',
            'DeepSeek',
            'Qwen',
            'Grok',
            'Açık / Diğer',
          ];

          final filteredPool = fullPool.where((m) {
            if (selectedProvider == 'Tümü') return true;
            if (selectedProvider == 'Canlı Sunucu') {
              return liveServerModels.contains(m);
            }
            return inferAiModelProvider(m, ownedBy: owners[m]) ==
                selectedProvider;
          }).toList();

          void assignModel(String modelId, {String? explicitTarget}) {
            final target = explicitTarget ?? applyTarget;
            refresh(() {
              if (target == 'both' || target == 'vision') {
                visionCtrl.text = modelId;
              }
              if (target == 'both' || target == 'assistant') {
                assistantCtrl.text = modelId;
              }
            });
          }

          Future<void> openAllModelsCatalog(String initialTarget) async {
            final chosen = await _openAllModelsCatalogDialog(
              ctx,
              allModels: fullPool,
              liveModels: liveServerModels,
              owners: owners,
              initialTarget: initialTarget,
              currentVision: visionCtrl.text.trim(),
              currentAssistant: assistantCtrl.text.trim(),
            );
            if (chosen != null) {
              assignModel(chosen.modelId, explicitTarget: chosen.target);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hub_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'CLIProxyAPI, Gemini OCR & Ses Ayarları',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (probeResult != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: probeResult!.authorized
                            ? Colors.green.withValues(alpha: 0.14)
                            : (probeResult!.reachable
                                  ? Colors.orange.withValues(alpha: 0.16)
                                  : scheme.errorContainer.withValues(
                                      alpha: 0.55,
                                    )),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: probeResult!.authorized
                              ? Colors.green
                              : (probeResult!.reachable
                                    ? Colors.orange
                                    : scheme.error),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            probeResult!.authorized
                                ? Icons.verified_rounded
                                : (probeResult!.reachable
                                      ? Icons.vpn_key_rounded
                                      : Icons.wifi_off_rounded),
                            color: probeResult!.authorized
                                ? Colors.green.shade700
                                : (probeResult!.reachable
                                      ? Colors.orange.shade800
                                      : scheme.error),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              probeResult!.message,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bağlantı Yöntemi',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in AiProviderMode.values)
                        ChoiceChip(
                          selected: draft.mode == m,
                          label: Text(m.title),
                          onSelected: (_) {
                            refresh(() {
                              draft = draft.copyWith(mode: m);
                              if (m == AiProviderMode.phoneCliProxy) {
                                urlCtrl.text = 'http://127.0.0.1:8317';
                              }
                            });
                            runProbe();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (draft.mode != AiProviderMode.directGemini) ...[
                    TextField(
                      controller: urlCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'CLIProxyAPI Sunucu Adresi',
                        hintText: 'http://127.0.0.1:8317',
                        prefixIcon: const Icon(Icons.dns_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Telefon varsayılanına sıfırla',
                          onPressed: () {
                            urlCtrl.text = 'http://127.0.0.1:8317';
                            runProbe();
                          },
                          icon: const Icon(Icons.phone_android_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: keyCtrl,
                    obscureText: obscureKey,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: draft.mode == AiProviderMode.directGemini
                          ? 'Google AI Studio API Anahtarı'
                          : 'CLIProxyAPI Erişim Anahtarı (Bearer Key)',
                      hintText: 'CLIProxy veya Gemini API anahtarınızı yapıştırın',
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Panodan yapıştır',
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              final txt = data?.text?.trim() ?? '';
                              if (txt.isNotEmpty) {
                                keyCtrl.text = txt;
                                runProbe();
                              }
                            },
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
                          IconButton(
                            tooltip: obscureKey ? 'Göster' : 'Gizle',
                            onPressed: () =>
                                refresh(() => obscureKey = !obscureKey),
                            icon: Icon(
                              obscureKey
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: probing ? null : runProbe,
                      icon: probing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(
                        probing
                            ? 'CLIProxy sorgulanıyor...'
                            : 'Bağlantıyı Test Et & Tüm Modelleri Çek (/v1/models)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: visionCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Görsel / OCR Modeli',
                            hintText: 'gemini-3.8-flash',
                            suffixIcon: IconButton(
                              tooltip: 'Tüm modellerden OCR seç',
                              onPressed: () => openAllModelsCatalog('vision'),
                              icon: const Icon(Icons.list_alt_rounded, size: 19),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: assistantCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Sesli Asistan Modeli',
                            hintText: 'gemini-3.8-flash',
                            suffixIcon: IconButton(
                              tooltip: 'Tüm modellerden Asistan seç',
                              onPressed: () => openAllModelsCatalog('assistant'),
                              icon: const Icon(Icons.list_alt_rounded, size: 19),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Model Havuzu (${fullPool.length} model · dokun & ata):',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => openAllModelsCatalog(applyTarget),
                        icon: const Icon(Icons.search_rounded, size: 16),
                        label: Text('Tümünü Ara (${fullPool.length})'),
                      ),
                    ],
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final opt in const [
                          (id: 'both', label: 'İkisine Uygula'),
                          (id: 'vision', label: 'Sadece Görsel/OCR'),
                          (id: 'assistant', label: 'Sadece Asistan'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                opt.label,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: applyTarget == opt.id,
                              onSelected: (_) =>
                                  refresh(() => applyTarget = opt.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final cat in providerCategories)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                cat,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: selectedProvider == cat,
                              onSelected: (_) =>
                                  refresh(() => selectedProvider = cat),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (filteredPool.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 145),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final m in filteredPool)
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: liveServerModels.contains(m)
                                    ? const Icon(
                                        Icons.cloud_done_rounded,
                                        size: 14,
                                        color: Colors.green,
                                      )
                                    : null,
                                backgroundColor:
                                    (visionCtrl.text.trim() == m ||
                                        assistantCtrl.text.trim() == m)
                                    ? scheme.primaryContainer
                                    : null,
                                label: Text(
                                  m,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight:
                                        (visionCtrl.text.trim() == m ||
                                            assistantCtrl.text.trim() == m)
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                onPressed: () => assignModel(m),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Divider(height: 22),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Asistan yanıtlarını sesli oku (Edge Neural TTS · Ahmet)',
                    ),
                    value: draft.voiceAutoSpeak,
                    onChanged: (v) =>
                        refresh(() => draft = draft.copyWith(voiceAutoSpeak: v)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Seslendirme Motoru & Sesi (Edge Neural TTS)',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final opt in const [
                        (
                          id: 'tr-TR-AhmetNeural',
                          label: 'Edge TTS · Ahmet (Varsayılan)',
                        ),
                        (
                          id: 'tr-TR-EmelNeural',
                          label: 'Edge TTS · Emel',
                        ),
                        (
                          id: 'system',
                          label: 'Sistem TTS (Çevrimdışı)',
                        ),
                      ])
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          selected: draft.ttsVoice == opt.id,
                          label: Text(
                            opt.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onSelected: (_) => refresh(
                            () => draft = draft.copyWith(ttsVoice: opt.id),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Eller serbest kesintisiz sesli sohbet döngüsü'),
                    subtitle: const Text(
                      'Asistan konuşmayı bitirince mikrofonu otomatik açar',
                    ),
                    value: draft.handsFreeLoop,
                    onChanged: (v) =>
                        refresh(() => draft = draft.copyWith(handsFreeLoop: v)),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('OCR sonrası Amazon & Kitapyurdu ile tamamla'),
                    value: draft.autoEnrichOnline,
                    onChanged: (v) => refresh(
                      () => draft = draft.copyWith(autoEnrichOnline: v),
                    ),
                  ),
                  Row(
                    children: [
                      const Text('Ses Hızı:'),
                      Expanded(
                        child: Slider(
                          min: 0.7,
                          max: 1.5,
                          divisions: 8,
                          label: '${draft.ttsRate.toStringAsFixed(2)}x',
                          value: draft.ttsRate,
                          onChanged: (v) =>
                              refresh(() => draft = draft.copyWith(ttsRate: v)),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          NativeVoiceController.instance.speak(
                            'Merhaba, Cumhuriyet Kütüphanesi sesli yapay zekâ asistanı Ahmet sesiyle hazır.',
                            rate: draft.ttsRate,
                            voice: draft.ttsVoice,
                          );
                        },
                        icon: const Icon(Icons.volume_up_rounded, size: 18),
                        label: const Text('Ahmet Sesini Dene'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final saved = draft.copyWith(
                          baseUrl: urlCtrl.text.trim().isEmpty
                              ? 'http://127.0.0.1:8317'
                              : urlCtrl.text.trim(),
                          apiKey: keyCtrl.text.trim(),
                          visionModel: visionCtrl.text.trim(),
                          assistantModel: assistantCtrl.text.trim(),
                          cachedModels: probeResult?.authorized == true
                              ? probeResult!.models
                              : draft.cachedModels,
                        );
                        await AiProxyStore.instance?.save(saved);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Yapay Zekâ & CLIProxy Ayarlarını Kaydet'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<({String modelId, String target})?> _openAllModelsCatalogDialog(
  BuildContext context, {
  required List<String> allModels,
  required Set<String> liveModels,
  required Map<String, String> owners,
  required String initialTarget,
  required String currentVision,
  required String currentAssistant,
}) async {
  var searchQuery = '';
  var providerFilter = 'Tümü';
  var target = initialTarget;

  final categories = <String>[
    'Tümü',
    if (liveModels.isNotEmpty) 'Canlı Sunucu',
    'Gemini',
    'Claude',
    'GPT / Codex',
    'DeepSeek',
    'Qwen',
    'Grok',
    'Açık / Diğer',
  ];

  return showModalBottomSheet<({String modelId, String target})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, refresh) {
          final scheme = Theme.of(ctx).colorScheme;
          final filtered = allModels.where((m) {
            final prov = inferAiModelProvider(m, ownedBy: owners[m]);
            if (providerFilter == 'Canlı Sunucu' && !liveModels.contains(m)) {
              return false;
            } else if (providerFilter != 'Tümü' &&
                providerFilter != 'Canlı Sunucu' &&
                prov != providerFilter) {
              return false;
            }
            if (searchQuery.trim().isNotEmpty) {
              final q = searchQuery.trim().toLowerCase();
              if (!m.toLowerCase().contains(q) &&
                  !prov.toLowerCase().contains(q)) {
                return false;
              }
            }
            return true;
          }).toList();

          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.84,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.smart_toy_rounded, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tüm CLIProxy Modelleri (${filtered.length} / ${allModels.length})',
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => refresh(() => searchQuery = v),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText:
                          'Model ara (gemini, claude, gpt, codex, qwen, deepseek...)',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final opt in const [
                        (id: 'both', label: 'İkisine Ata'),
                        (id: 'vision', label: 'Görsel / OCR'),
                        (id: 'assistant', label: 'Sesli Asistan'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(opt.label),
                            selected: target == opt.id,
                            onSelected: (_) => refresh(() => target = opt.id),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final cat in categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(cat),
                            selected: providerFilter == cat,
                            onSelected: (_) =>
                                refresh(() => providerFilter = cat),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 12),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (_, index) {
                      final m = filtered[index];
                      final isLive = liveModels.contains(m);
                      final prov = inferAiModelProvider(m, ownedBy: owners[m]);
                      final isVision = currentVision == m;
                      final isAssistant = currentAssistant == m;
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: (isVision || isAssistant)
                                ? scheme.primary
                                : scheme.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        tileColor: (isVision || isAssistant)
                            ? scheme.primaryContainer.withValues(alpha: 0.32)
                            : scheme.surfaceContainerLow,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isLive
                              ? Colors.green.withValues(alpha: 0.16)
                              : scheme.secondaryContainer,
                          child: Icon(
                            isLive
                                ? Icons.cloud_done_rounded
                                : Icons.auto_awesome_rounded,
                            size: 16,
                            color: isLive
                                ? Colors.green.shade700
                                : scheme.onSecondaryContainer,
                          ),
                        ),
                        title: Text(
                          m,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        subtitle: Text(
                          [
                            prov,
                            if (isLive) 'Canlı Sunucu',
                            if (isVision) 'Seçili OCR',
                            if (isAssistant) 'Seçili Asistan',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(
                          ctx,
                        ).pop((modelId: m, target: target)),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
