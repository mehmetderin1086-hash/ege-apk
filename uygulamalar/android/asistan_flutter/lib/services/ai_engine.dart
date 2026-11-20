import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/asistan_models.dart';
import 'document_builder.dart';
import 'phone_commands.dart';

class AiTurnOutcome {
  const AiTurnOutcome({
    required this.replyText,
    this.reasoningText = '',
    this.modelUsed = 'gemini-2.5-pro',
    this.toolTraces = const [],
    this.citations = const [],
    this.artifacts = const [],
    this.arenaCandidates = const [],
  });

  final String replyText;
  final String reasoningText;
  final String modelUsed;
  final List<ToolCallTrace> toolTraces;
  final List<WebCitation> citations;
  final List<GeneratedArtifact> artifacts;
  final List<ArenaCandidate> arenaCandidates;
}

typedef NativeBridgeCaller = Future<dynamic> Function(
  String method, [
  Map<String, dynamic>? args,
]);

class AiEngine {
  AiEngine({required this.nativeCaller, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final NativeBridgeCaller nativeCaller;
  final http.Client _http;

  String baseUrl = 'http://127.0.0.1:8317';
  String apiKey = '';
  String geminiDirectApiKey = '';
  ProxyAuthStatus lastAuthStatus = ProxyAuthStatus.checking;
  String lastProxyError = '';
  List<String> liveProxyModelIds = [];
  String? _pendingPhonePrompt;

  void cancelPendingPhoneCommand() => _pendingPhonePrompt = null;

  // ─── LIVE MODEL DISCOVERY & DETAILED HEALTH FROM CLIPROXY ────────────────

  Future<({ProxyAuthStatus status, List<AiModelInfo> models, String message})>
  checkProxyDetailedStatus() async {
    final catalog = List<AiModelInfo>.from(AiModelInfo.defaultCatalog);
    bool healthOk = false;
    try {
      final hUri = Uri.parse('${_cleanBaseUrl()}/healthz');
      final hResp = await _http.get(hUri).timeout(const Duration(seconds: 2));
      if (hResp.statusCode == 200) {
        healthOk = true;
      }
    } catch (_) {}

    try {
      final mUri = _buildAuthedUri('/v1/models');
      final resp = await _http
          .get(mUri, headers: _authHeaders())
          .timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final list = (data is Map ? data['data'] : null) as List?;
        final discoveredIds = <String>[];
        if (list != null) {
          for (final item in list) {
            if (item is Map && item['id'] != null) {
              final id = item['id'].toString().trim();
              if (id.isNotEmpty) {
                discoveredIds.add(id);
              }
            }
          }
        }
        liveProxyModelIds = discoveredIds;
        final merged = _mergeDiscoveredModels(catalog, discoveredIds);
        lastAuthStatus = ProxyAuthStatus.connected;
        lastProxyError = '';
        return (
          status: ProxyAuthStatus.connected,
          models: merged,
          message: 'CLIProxy bağlı (${discoveredIds.length} canlı model aktif)',
        );
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        lastAuthStatus = ProxyAuthStatus.needsKey;
        lastProxyError = 'CLIProxy (127.0.0.1:8317) çalışıyor ancak API anahtarı (sk-iphone-...) eşleşmedi.';
        return (
          status: ProxyAuthStatus.needsKey,
          models: catalog,
          message: lastProxyError,
        );
      }
    } catch (_) {}

    if (healthOk) {
      lastAuthStatus = ProxyAuthStatus.needsKey;
      lastProxyError = 'CLIProxy çalışıyor • Bağlantı anahtarı bekleniyor';
      return (
        status: ProxyAuthStatus.needsKey,
        models: catalog,
        message: lastProxyError,
      );
    }

    lastAuthStatus = ProxyAuthStatus.offline;
    lastProxyError = 'CLIProxy (127.0.0.1:8317) kapalı veya erişilemiyor';
    return (
      status: ProxyAuthStatus.offline,
      models: catalog,
      message: lastProxyError,
    );
  }

  List<AiModelInfo> _mergeDiscoveredModels(
    List<AiModelInfo> catalog,
    List<String> discoveredIds,
  ) {
    final lowerDiscovered = discoveredIds.map((e) => e.toLowerCase()).toSet();
    final updatedCatalog = catalog.map((m) {
      final isLive =
          lowerDiscovered.contains(m.id.toLowerCase()) ||
          m.id.startsWith('auto');
      return m.copyWith(isLiveFromProxy: isLive);
    }).toList();

    final existingIds = updatedCatalog.map((e) => e.id.toLowerCase()).toSet();
    final newlyDiscovered = <AiModelInfo>[];
    for (final rawId in discoveredIds) {
      if (!existingIds.contains(rawId.toLowerCase())) {
        existingIds.add(rawId.toLowerCase());
        newlyDiscovered.add(_classifyDiscoveredModel(rawId));
      }
    }

    // Put newly discovered live models right after the 5 auto smart-routing models
    final head = updatedCatalog.take(5).toList();
    final tail = updatedCatalog.skip(5).toList();
    return [...head, ...newlyDiscovered, ...tail];
  }

  Future<List<AiModelInfo>> fetchAvailableModels() async {
    final res = await checkProxyDetailedStatus();
    return res.models;
  }

  AiModelInfo _classifyDiscoveredModel(String id) {
    final lower = id.toLowerCase();
    if (lower.startsWith('auto')) {
      return AiModelInfo(
        id: id,
        name: 'CLIProxy $id',
        provider: 'Siri CLIProxy • Smart Router',
        badge: 'Canlı Proxy Yönlendirici',
        color: const Color(0xFF00E5FF),
        isLiveFromProxy: true,
      );
    }
    if (lower.contains('claude')) {
      return AiModelInfo(
        id: id,
        name: _prettifyModelName(id),
        provider: 'Anthropic Claude (CLIProxy)',
        badge: 'Canlı Proxy Modeli',
        color: const Color(0xFFF59E0B),
        isLiveFromProxy: true,
      );
    }
    if (lower.contains('gpt') ||
        lower.contains('o1') ||
        lower.contains('o3') ||
        lower.contains('codex')) {
      return AiModelInfo(
        id: id,
        name: _prettifyModelName(id),
        provider: 'OpenAI ChatGPT (CLIProxy)',
        badge: 'Canlı Proxy Modeli',
        color: const Color(0xFF10B981),
        isLiveFromProxy: true,
      );
    }
    if (lower.contains('deepseek')) {
      return AiModelInfo(
        id: id,
        name: _prettifyModelName(id),
        provider: 'DeepSeek (CLIProxy)',
        badge: 'Canlı Muhakeme Modeli',
        color: const Color(0xFFA855F7),
        isLiveFromProxy: true,
      );
    }
    if (lower.contains('qwen') ||
        lower.contains('llama') ||
        lower.contains('gguf')) {
      return AiModelInfo(
        id: id,
        name: _prettifyModelName(id),
        provider: 'CLIProxy Yerel / Qwen',
        badge: 'Canlı Proxy Modeli',
        color: const Color(0xFFEC4899),
        isLiveFromProxy: true,
      );
    }
    return AiModelInfo(
      id: id,
      name: _prettifyModelName(id),
      provider: 'Google Gemini / Antigravity (CLIProxy)',
      badge: 'Canlı Proxy Modeli',
      color: const Color(0xFF00E5FF),
      isLiveFromProxy: true,
    );
  }

  String _prettifyModelName(String id) {
    return id
        .split('-')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Future<bool> checkProxyHealth() async {
    final res = await checkProxyDetailedStatus();
    return res.status == ProxyAuthStatus.connected;
  }

  // ─── MAIN ORCHESTRATOR (TOOLS + RESEARCH + COUNCIL + LLM) ────────────────

  Future<AiTurnOutcome> processUserTurn({
    required String prompt,
    required WorkMode mode,
    required String selectedModel,
    required List<ChatMessage> history,
    required List<MemoryFact> memories,
    required List<McpServerConfig> mcpServers,
    required void Function(ReminderItem reminder) onReminderCreated,
    required void Function(MemoryFact fact) onMemoryAdded,
    String personaId = 'claude_code',
  }) async {
    var phonePrompt = prompt;
    if (_pendingPhonePrompt != null && PhoneCommand.parse(prompt) == null) {
      final previous = _pendingPhonePrompt!;
      if (previous.toLowerCase().contains('alarm')) {
        phonePrompt = '$prompt alarm kur';
      } else if (previous.toLowerCase().contains('ara')) {
        phonePrompt = '$prompt ara';
      } else if (previous.toLowerCase().contains('mesaj') ||
          previous.toLowerCase().contains('sms')) {
        final number = RegExp(r'\+?\d[\d ()-]{6,}')
            .firstMatch(previous)
            ?.group(0);
        phonePrompt = number == null
            ? '$prompt mesaj gönder'
            : '$number mesaj gönder: $prompt';
      }
    }
    final phone = PhoneCommand.parse(phonePrompt);
    if (phone != null) {
      _pendingPhonePrompt =
          phone.method == null && !phone.help.contains('iptal')
          ? phonePrompt
          : null;
      if (phone.method == null) {
        return AiTurnOutcome(
          replyText: phone.help,
          modelUsed: 'Telefon asistanı',
        );
      }
      final result = await nativeCaller(phone.method!, phone.args);
      final message = result is Map ? result['message']?.toString() : null;
      return AiTurnOutcome(
        replyText:
            message ?? 'İşlem başlatılamadı. Telefon izinlerini kontrol edin.',
        modelUsed: 'Telefon asistanı',
      );
    }
    _pendingPhonePrompt = null;
    final traces = <ToolCallTrace>[];
    final citations = <WebCitation>[];
    final artifacts = <GeneratedArtifact>[];
    final contextBlocks = <String>[];

    // Normalize slash commands if typed at the start
    var effectivePrompt = prompt.trim();
    var effectiveMode = mode;
    if (effectivePrompt.startsWith('/')) {
      final parts = effectivePrompt.split(' ');
      final cmd = parts.first.toLowerCase();
      final rest = parts.skip(1).join(' ').trim();
      switch (cmd) {
        case '/kod':
          effectiveMode = WorkMode.canvas;
          effectivePrompt = rest.isEmpty
              ? 'Örnek modern bir uygulama mimarisi ve kodu yaz'
              : rest;
          break;
        case '/arastir':
          effectiveMode = WorkMode.research;
          effectivePrompt = rest.isEmpty
              ? 'Güncel yapay zeka teknolojilerini araştır'
              : rest;
          break;
        case '/konsey':
          effectiveMode = WorkMode.council;
          effectivePrompt = rest.isEmpty
              ? 'Yapay zeka mimarilerini karşılaştır'
              : rest;
          break;
        case '/pdf':
          effectiveMode = WorkMode.office;
          effectivePrompt =
              'PDF oluştur: ${rest.isEmpty ? "Kapsamlı Yönetici Raporu" : rest}';
          break;
        case '/word':
          effectiveMode = WorkMode.office;
          effectivePrompt =
              'Word (DOCX) oluştur: ${rest.isEmpty ? "Resmi Kurumsal Rapor" : rest}';
          break;
        case '/excel':
          effectiveMode = WorkMode.office;
          effectivePrompt =
              'Excel (XLSX) tablosu oluştur: ${rest.isEmpty ? "Finansal Bütçe Tablosu" : rest}';
          break;
        case '/sunum':
          effectiveMode = WorkMode.office;
          effectivePrompt =
              'PowerPoint (PPTX) sunumu hazırla: ${rest.isEmpty ? "Stratejik Sunum" : rest}';
          break;
        case '/gorsel':
          effectiveMode = WorkMode.image;
          effectivePrompt =
              'Görsel üret: ${rest.isEmpty ? "Geleceğin siber İstanbul silüeti" : rest}';
          break;
        case '/dilekce':
          effectiveMode = WorkMode.office;
          effectivePrompt =
              'Resmi dilekçe hazırla ve PDF oluştur: ${rest.isEmpty ? "Bilgi Edinme Başvurusu" : rest}';
          break;
        case '/ozet':
          effectivePrompt =
              'Aşağıdaki konuyu yönetici özeti, kritik bulgular ve karşılaştırma tablosu halinde özetle: $rest';
          break;
        case '/cevir':
          effectivePrompt =
              'Aşağıdaki metni hem doğal hem akademik düzeyde çevir ve önemli kavramları açıkla: $rest';
          break;
        case '/sinav':
          effectivePrompt =
              'Aşağıdaki konuda 10 soruluk çoktan seçmeli ve detaylı çözümlü sınav hazırla: $rest';
          break;
        case '/deprem':
          effectivePrompt =
              'Türkiye ve çevresindeki son depremleri göster ve analiz et';
          break;
        case '/hava':
          effectivePrompt =
              '${rest.isEmpty ? "İstanbul" : rest} hava durumu nasıl?';
          break;
        case '/doviz':
          effectivePrompt =
              'Canlı dolar, euro ve sterlin döviz kurlarını göster';
          break;
        case '/fener':
          effectiveMode = WorkMode.device;
          effectivePrompt = rest.isEmpty
              ? 'El fenerini aç'
              : 'El fenerini $rest';
          break;
        case '/alarm':
          effectiveMode = WorkMode.device;
          effectivePrompt = rest.isEmpty
              ? 'Saat 08:00 için alarm kur'
              : 'Alarm kur $rest';
          break;
      }
    }

    final lower = effectivePrompt.toLowerCase();

    // 1. Check Siri / Google Assistant Hardware & System Intent
    final deviceHandled = await _tryExecuteDeviceAndAssistantTools(
      prompt: effectivePrompt,
      lower: lower,
      traces: traces,
      onReminderCreated: onReminderCreated,
      onMemoryAdded: onMemoryAdded,
    );
    if (deviceHandled != null) {
      return AiTurnOutcome(
        replyText: deviceHandled,
        modelUsed: 'Telefon asistanı',
        toolTraces: traces,
      );
    }

    // 2. Check Live Web Services (Weather, Earthquakes, Currency, Wikipedia, Country, Books)
    final liveServiceContext = await _tryExecuteLiveWebServices(
      prompt: effectivePrompt,
      lower: lower,
      mode: effectiveMode,
      traces: traces,
      citations: citations,
    );
    if (liveServiceContext.isNotEmpty) {
      contextBlocks.add(liveServiceContext);
    }

    // 3. Check Image Studio Mode or explicit image generation command
    final wantsImage =
        effectiveMode == WorkMode.image ||
        RegExp(
          r'(resim çiz|görsel üret|görsel oluştur|poster yap|illüstrasyon çiz|logo tasarla|resmini yap)',
        ).hasMatch(lower);
    if (wantsImage) {
      final sw = Stopwatch()..start();
      final imgArtifact = await generateImageWithProxyOrFallback(
        prompt: effectivePrompt,
        style: 'Siber Holografik 3D',
      );
      sw.stop();
      artifacts.add(imgArtifact);
      traces.add(
        ToolCallTrace(
          name: 'gorselUret',
          title: 'AI Görsel Üretim Stüdyosu',
          inputSummary: effectivePrompt,
          outputSummary:
              '${imgArtifact.title} (${imgArtifact.format.toUpperCase()}) hazırlandı.',
          durationMs: sw.elapsedMilliseconds,
        ),
      );
    }

    // 4. Check Model Council (Arena) Mode
    if (effectiveMode == WorkMode.council) {
      return _runModelCouncilTurn(
        prompt: effectivePrompt,
        contextBlocks: contextBlocks,
        memories: memories,
        traces: traces,
        citations: citations,
        artifacts: artifacts,
        personaId: personaId,
      );
    }

    // 5. Call Primary LLM (via CLIProxy / Direct Gemini / Smart Fallback)
    final systemPrompt = _buildSystemPrompt(
      mode: effectiveMode,
      memories: memories,
      citations: citations,
      personaId: personaId,
    );

    final fullUserPrompt = contextBlocks.isEmpty
        ? effectivePrompt
        : '$effectivePrompt\n\n---\n[CANLI ARAÇ VE VERİ BAĞLAMI]\n${contextBlocks.join('\n\n')}';

    final llmResult = await _callChatCompletion(
      model: selectedModel,
      systemPrompt: systemPrompt,
      history: history,
      userPrompt: fullUserPrompt,
      allowFallback: effectiveMode != WorkMode.voice,
    );

    var finalReply = llmResult.reply;
    final reasoning = llmResult.reasoning;
    final resolvedModel = llmResult.modelUsed;

    // 6. Check Office Document Generation Mode or explicit request
    final requestedFormats = _detectRequestedDocumentFormats(
      lower,
      effectiveMode,
    );
    if (requestedFormats.isNotEmpty) {
      final docTitle = _extractDocumentTitle(effectivePrompt);
      for (final docFormat in requestedFormats) {
        final sw = Stopwatch()..start();
        final docArtifact = await DocumentBuilder.createOfficeDocument(
          title: docTitle,
          content: finalReply,
          format: docFormat,
        );
        sw.stop();
        artifacts.add(docArtifact);
        traces.add(
          ToolCallTrace(
            name: 'ofisBelgesiOlustur',
            title: 'Ofis Belgesi Üretici (${docFormat.toUpperCase()})',
            inputSummary: '$docTitle.$docFormat',
            outputSummary:
                'Belge oluşturuldu (${(docArtifact.sizeBytes / 1024).toStringAsFixed(1)} KB)',
            durationMs: sw.elapsedMilliseconds,
          ),
        );
      }
    }

    return AiTurnOutcome(
      replyText: finalReply,
      reasoningText: reasoning,
      modelUsed: resolvedModel,
      toolTraces: traces,
      citations: citations,
      artifacts: artifacts,
    );
  }

  // ─── MULTI-MODEL COUNCIL (CHATGPT + GEMINI + CLAUDE ARENA) ───────────────

  Future<AiTurnOutcome> _runModelCouncilTurn({
    required String prompt,
    required List<String> contextBlocks,
    required List<MemoryFact> memories,
    required List<ToolCallTrace> traces,
    required List<WebCitation> citations,
    required List<GeneratedArtifact> artifacts,
    String personaId = 'claude_code',
  }) async {
    final councilModels = [
      const (
        id: 'claude-sonnet-5-5',
        name: 'Claude Sonnet 5.5',
        provider: 'Anthropic Claude',
      ),
      const (
        id: 'gpt-6.1-sol',
        name: 'GPT-6.1 Sol',
        provider: 'OpenAI ChatGPT',
      ),
      const (
        id: 'gemini-2.5-pro',
        name: 'Gemini 2.5 Pro',
        provider: 'Google Gemini',
      ),
    ];

    final sys = _buildSystemPrompt(
      mode: WorkMode.council,
      memories: memories,
      citations: citations,
      personaId: personaId,
    );
    final enrichedPrompt = contextBlocks.isEmpty
        ? prompt
        : '$prompt\n\n[VERİ BAĞLAMI]\n${contextBlocks.join('\n')}';

    final futures = councilModels.map((m) async {
      final sw = Stopwatch()..start();
      final res = await _callChatCompletion(
        model: m.id,
        systemPrompt:
            '$sys\nSen ${m.name} (${m.provider}) modelisin. Kendi uzmanlık perspektifinden net ve derinlikli yanıt ver.',
        history: const [],
        userPrompt: enrichedPrompt,
      );
      sw.stop();
      return ArenaCandidate(
        modelId: m.id,
        modelName: m.name,
        provider: m.provider,
        response: res.reply,
        latencyMs: sw.elapsedMilliseconds,
        score: 94 + (m.id.hashCode.abs() % 6),
      );
    }).toList();

    final candidates = await Future.wait(futures);
    traces.add(
      ToolCallTrace(
        name: 'modelKonseyi',
        title: 'Model Konseyi (Claude 5.5 + GPT-6.1 + Gemini 2.5)',
        inputSummary: '3 amiral gemisi model paralel çalıştırıldı',
        outputSummary: candidates
            .map((c) => '${c.modelName} (${c.latencyMs}ms)')
            .join(' • '),
        durationMs: candidates.fold<int>(
          0,
          (p, c) => p > c.latencyMs ? p : c.latencyMs,
        ),
      ),
    );

    final synthesisPrompt =
        '''Aşağıda kullanıcı sorusuna 3 farklı yapay zeka modelinin (Claude Sonnet 5.5, GPT-6.1 Sol, Gemini 2.5 Pro) verdiği yanıtlar yer alıyor.
Kullanıcı Sorusu: "$prompt"

--- CLAUDE SONNET 5.5 YANITI ---
${candidates[0].response}

--- GPT-6.1 SOL YANITI ---
${candidates[1].response}

--- GEMINI 2.5 PRO YANITI ---
${candidates[2].response}

Görev: Bu üç yanıtın en güçlü yönlerini birleştirerek kapsamlı, çelişkilerden arındırılmış ve uygulanabilir bir "Ortak Akıl Sentezi" oluştur.''';

    final synthesis = await _callChatCompletion(
      model: 'auto',
      systemPrompt: sys,
      history: const [],
      userPrompt: synthesisPrompt,
    );

    return AiTurnOutcome(
      replyText: synthesis.reply,
      reasoningText: 'Claude Sonnet 5.5, GPT-6.1 Sol ve Gemini 2.5 Pro yanıtları karşılaştırılıp ortak sentez üretildi.',
      modelUsed: 'Model Konseyi (3x AI)',
      toolTraces: traces,
      citations: citations,
      artifacts: artifacts,
      arenaCandidates: candidates,
    );
  }

  // ─── SIRI & GOOGLE ASSISTANT HARDWARE / SYSTEM TOOL EXECUTION ────────────

  Future<String?> _tryExecuteDeviceAndAssistantTools({
    required String prompt,
    required String lower,
    required List<ToolCallTrace> traces,
    required void Function(ReminderItem reminder) onReminderCreated,
    required void Function(MemoryFact fact) onMemoryAdded,
  }) async {
    final outputs = <String>[];

    // 1. Flashlight (El Feneri)
    if (lower.contains('fener') ||
        lower.contains('ışığı aç') ||
        lower.contains('flaş')) {
      final turnOff = lower.contains('kapat') || lower.contains('söndür');
      final action = turnOff ? 'fener_kapat' : 'fener_ac';
      final sw = Stopwatch()..start();
      final res = await nativeCaller('deviceAction', {'action': action});
      sw.stop();
      final msg =
          (res is Map ? res['message']?.toString() : null) ??
          (turnOff ? 'El feneri kapatıldı.' : 'El feneri açıldı.');
      traces.add(
        ToolCallTrace(
          name: 'cihaz.fener',
          title: turnOff ? 'El Feneri Kapatıldı' : 'El Feneri Açıldı',
          inputSummary: action,
          outputSummary: msg,
          durationMs: sw.elapsedMilliseconds,
        ),
      );
      outputs.add(msg);
    }

    // 2. Volume & Ringer Mode (Ses Seviyesi / Sessiz / Titreşim)
    if (lower.contains('sesi ') ||
        lower.contains('ses seviyesi') ||
        lower.contains('sessize al') ||
        lower.contains('titreşime al')) {
      final sw = Stopwatch()..start();
      if (lower.contains('sessize al') || lower.contains('sessiz mod')) {
        final res = await nativeCaller('deviceAction', {
          'action': 'zil_modu',
          'target': 'sessiz',
        });
        final msg =
            (res is Map ? res['message']?.toString() : null) ??
            'Telefon sessize alındı.';
        traces.add(
          ToolCallTrace(
            name: 'cihaz.zilModu',
            title: 'Zil Modu: Sessiz',
            inputSummary: 'sessiz',
            outputSummary: msg,
            durationMs: sw.elapsedMilliseconds,
          ),
        );
        outputs.add(msg);
      } else if (lower.contains('titreşime al') ||
          lower.contains('titreşim mod')) {
        final res = await nativeCaller('deviceAction', {
          'action': 'zil_modu',
          'target': 'titresim',
        });
        final msg =
            (res is Map ? res['message']?.toString() : null) ??
            'Telefon titreşim moduna alındı.';
        traces.add(
          ToolCallTrace(
            name: 'cihaz.zilModu',
            title: 'Zil Modu: Titreşim',
            inputSummary: 'titresim',
            outputSummary: msg,
            durationMs: sw.elapsedMilliseconds,
          ),
        );
        outputs.add(msg);
      } else {
        final numMatch = RegExp(r'(\d{1,3})').firstMatch(lower);
        final pct = numMatch != null
            ? int.tryParse(numMatch.group(1)!)?.clamp(0, 100) ?? 60
            : (lower.contains('kıs') ? 25 : 75);
        final res = await nativeCaller('deviceAction', {
          'action': 'ses_ayarla',
          'value': pct,
          'target': 'medya',
        });
        final msg =
            (res is Map ? res['message']?.toString() : null) ??
            'Ses seviyesi %$pct olarak ayarlandı.';
        traces.add(
          ToolCallTrace(
            name: 'cihaz.ses',
            title: 'Ses Seviyesi (%$pct)',
            inputSummary: '%$pct',
            outputSummary: msg,
            durationMs: sw.elapsedMilliseconds,
          ),
        );
        outputs.add(msg);
      }
      sw.stop();
    }

    // 3. Battery & Storage Status (Pil / Şarj / Depolama / Cihaz Durumu)
    if (lower.contains('pil') ||
        lower.contains('şarj') ||
        lower.contains('batarya') ||
        lower.contains('depolama') ||
        lower.contains('hafıza ne kadar') ||
        lower.contains('cihaz durumu')) {
      final sw = Stopwatch()..start();
      final raw = await nativeCaller('getDeviceStatus');
      sw.stop();
      final status = DeviceStatusSnapshot.fromMap(raw is Map ? raw : null);
      final summary =
          'Cihaz: ${status.deviceModel} (Android ${status.androidVersion}) • '
          'Pil: %${status.batteryPercent} (${status.isCharging ? "Şarj oluyor" : "Pilde"}, ${status.batteryTempC.toStringAsFixed(1)}°C) • '
          'Boş Depolama: ${status.storageFreeGb} GB / ${status.storageTotalGb} GB • '
          'Ses: %${status.volumePercent} (${status.ringerMode})';
      traces.add(
        ToolCallTrace(
          name: 'cihaz.durum',
          title: 'Telefon Donanım Durumu',
          inputSummary: 'Pil, Depolama ve Ses Analizi',
          outputSummary: summary,
          durationMs: sw.elapsedMilliseconds,
        ),
      );
      outputs.add(summary);
    }

    // 4. Alarms & Timers (Alarm Kur / Sayaç Başlat)
    if (lower.contains('alarm kur') ||
        lower.contains('alarmı kur') ||
        lower.contains('uyandır')) {
      final timeMatch =
          RegExp(r'(\d{1,2})[:.\s](\d{2})').firstMatch(lower) ??
          RegExp(r'saat\s*(\d{1,2})').firstMatch(lower);
      final hour = timeMatch != null
          ? (int.tryParse(timeMatch.group(1)!) ?? 8)
          : 8;
      final minute =
          (timeMatch != null &&
              timeMatch.groupCount >= 2 &&
              timeMatch.group(2) != null)
          ? (int.tryParse(timeMatch.group(2)!) ?? 0)
          : 0;
      final res = await nativeCaller('setAlarmOrTimer', {
        'mode': 'alarm',
        'hour': hour,
        'minute': minute,
        'title': 'Asistan Alarmı',
      });
      final msg =
          (res is Map ? res['message']?.toString() : null) ??
          'Saat ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} için alarm kuruldu.';
      traces.add(
        ToolCallTrace(
          name: 'zamanlayici.alarm',
          title: 'Sistem Alarmı Kuruldu',
          inputSummary:
              '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
          outputSummary: msg,
        ),
      );
      outputs.add(msg);
    } else if (lower.contains('sayaç') || lower.contains('zamanlayıcı')) {
      final minMatch = RegExp(r'(\d+)\s*dakika').firstMatch(lower);
      final secMatch = RegExp(r'(\d+)\s*saniye').firstMatch(lower);
      final totalSeconds =
          (minMatch != null ? int.parse(minMatch.group(1)!) * 60 : 0) +
          (secMatch != null ? int.parse(secMatch.group(1)!) : 0);
      final secs = totalSeconds > 0 ? totalSeconds : 60;
      final res = await nativeCaller('setAlarmOrTimer', {
        'mode': 'timer',
        'seconds': secs,
        'title': 'Asistan Sayacı',
      });
      final msg =
          (res is Map ? res['message']?.toString() : null) ??
          '$secs saniyelik sayaç başlatıldı.';
      traces.add(
        ToolCallTrace(
          name: 'zamanlayici.sayac',
          title: 'Zamanlayıcı Başlatıldı',
          inputSummary: '$secs sn',
          outputSummary: msg,
        ),
      );
      outputs.add(msg);
    }

    // 5. Reminders (Hatırlatıcı)
    if (lower.contains('hatırlat')) {
      final minMatch = RegExp(r'(\d+)\s*dakika').firstMatch(lower);
      final minutes = minMatch != null
          ? (int.tryParse(minMatch.group(1)!) ?? 5)
          : 1;
      final triggerTime = DateTime.now().add(Duration(minutes: minutes));
      final remId = DateTime.now().millisecondsSinceEpoch % 100000;
      await nativeCaller('scheduleReminder', {
        'id': remId,
        'title': 'Asistan Hatırlatıcı',
        'body': prompt,
        'triggerAtMillis': triggerTime.millisecondsSinceEpoch,
      });
      final item = ReminderItem(
        id: remId,
        title: prompt.length > 42 ? '${prompt.substring(0, 42)}...' : prompt,
        body: prompt,
        triggerAt: triggerTime,
      );
      onReminderCreated(item);
      final msg =
          '$minutes dakika sonrası (${triggerTime.hour.toString().padLeft(2, '0')}:${triggerTime.minute.toString().padLeft(2, '0')}) için bildirim hatırlatıcısı kuruldu.';
      traces.add(
        ToolCallTrace(
          name: 'hatirlatici.ekle',
          title: 'Hatırlatıcı Zamanlandı',
          inputSummary: prompt,
          outputSummary: msg,
        ),
      );
      outputs.add(msg);
    }

    // 6. Memory (Hafızaya Kaydet / Unutma)
    if (lower.contains('hafızaya kaydet') ||
        lower.contains('bunu unutma') ||
        lower.contains('aklonda tut') ||
        lower.contains('aklında tut')) {
      final fact = MemoryFact(
        id: 'mem_${DateTime.now().millisecondsSinceEpoch}',
        category: 'kisisel',
        fact: prompt,
        createdAt: DateTime.now(),
      );
      onMemoryAdded(fact);
      const msg = 'Bilgi uzun süreli Asistan hafızasına kaydedildi.';
      traces.add(
        ToolCallTrace(
          name: 'hafiza.kaydet',
          title: 'Uzun Süreli Hafıza Kaydı',
          inputSummary: prompt,
          outputSummary: msg,
        ),
      );
      outputs.add(msg);
    }

    // 7. System Settings Panels (Ayarları Aç)
    if (lower.contains('ayarlarını aç') || lower.contains('ayarları aç')) {
      String panel = 'genel';
      if (lower.contains('wifi') ||
          lower.contains('wi-fi') ||
          lower.contains('kablosuz')) {
        panel = 'wifi';
      } else if (lower.contains('bluetooth')) {
        panel = 'bluetooth';
      } else if (lower.contains('konum') || lower.contains('gps')) {
        panel = 'konum';
      } else if (lower.contains('ekran') || lower.contains('parlaklık')) {
        panel = 'ekran';
      } else if (lower.contains('ses')) {
        panel = 'ses';
      }
      final res = await nativeCaller('deviceAction', {
        'action': 'ayar_ac',
        'target': panel,
      });
      final msg =
          (res is Map ? res['message']?.toString() : null) ??
          'Sistem ayarları ($panel) açıldı.';
      traces.add(
        ToolCallTrace(
          name: 'cihaz.ayarlar',
          title: 'Sistem Ayarları Açıldı',
          inputSummary: panel,
          outputSummary: msg,
        ),
      );
      outputs.add(msg);
    }

    // 8. Media Controls (Müziği Durdur / Oynat / Sonraki Şarkı)
    if (lower.contains('müziği durdur') ||
        lower.contains('şarkıyı durdur') ||
        lower.contains('müziği başlat') ||
        lower.contains('sonraki şarkı') ||
        lower.contains('önceki şarkı')) {
      String cmd = 'play_pause';
      if (lower.contains('sonraki')) {
        cmd = 'next';
      } else if (lower.contains('önceki')) {
        cmd = 'previous';
      } else if (lower.contains('durdur')) {
        cmd = 'pause';
      } else if (lower.contains('başlat') || lower.contains('devam')) {
        cmd = 'play';
      }
      final res = await nativeCaller('mediaControl', {'command': cmd});
      final msg =
          (res is Map ? res['message']?.toString() : null) ??
          'Medya komutu ($cmd) gönderildi.';
      traces.add(
        ToolCallTrace(
          name: 'muzik.kontrol',
          title: 'Medya Kontrolü',
          inputSummary: cmd,
          outputSummary: msg,
        ),
      );
      outputs.add(msg);
    }

    // 9. Open Installed Apps (Uygulamayı Aç)
    final appMatch = RegExp(
      r'(ritim|bilgili|kağıt|kagit|youtube|whatsapp|spotify|chrome|gmail|harita|haritalar|instagram|telegram)\s*(uygulamasını|uygulamasini)?\s*aç',
    ).firstMatch(lower);
    if (appMatch != null) {
      final appName = appMatch.group(1)!;
      final res = await nativeCaller('openAppOrUrl', {'target': appName});
      final msg =
          (res is Map ? res['message']?.toString() : null) ??
          '$appName açıldı.';
      traces.add(
        ToolCallTrace(
          name: 'uygulamaAc',
          title: 'Uygulama Başlatıcı',
          inputSummary: appName,
          outputSummary: msg,
        ),
      );
      outputs.add(msg);
    }

    return outputs.isEmpty ? null : outputs.join('\n');
  }

  // ─── LIVE WEB SERVICES (WEATHER, EARTHQUAKES, CURRENCY, RESEARCH) ────────

  Future<String> _tryExecuteLiveWebServices({
    required String prompt,
    required String lower,
    required WorkMode mode,
    required List<ToolCallTrace> traces,
    required List<WebCitation> citations,
  }) async {
    final sections = <String>[];

    // 1. Weather (Hava Durumu via Open-Meteo)
    if (lower.contains('hava durumu') ||
        lower.contains('hava nasıl') ||
        lower.contains('kaç derece') ||
        lower.contains('yağmur yağacak mı')) {
      final city = _extractCityName(lower);
      final weatherInfo = await fetchLiveWeather(city);
      if (weatherInfo != null) {
        traces.add(
          ToolCallTrace(
            name: 'havaDurumu',
            title: 'Canlı Meteoroloji ($city)',
            inputSummary: city,
            outputSummary: weatherInfo,
          ),
        );
        sections.add('CANLI HAVA DURUMU ($city):\n$weatherInfo');
      }
    }

    // 2. Earthquakes (Deprem via USGS GeoJSON)
    if (lower.contains('deprem') || lower.contains('sarsıntı')) {
      final eqInfo = await fetchRecentEarthquakes();
      if (eqInfo != null) {
        traces.add(
          ToolCallTrace(
            name: 'yasamServisleri.deprem',
            title: 'Canlı Sismik Deprem Kayıtları',
            inputSummary: 'Türkiye ve Çevresi Son Depremler',
            outputSummary: eqInfo.split('\n').first,
          ),
        );
        sections.add('SON DEPREMLER VERİSİ:\n$eqInfo');
      }
    }

    // 3. Currency Exchange (Döviz Kuru via ECB Frankfurter API)
    if (lower.contains('dolar') ||
        lower.contains('euro') ||
        lower.contains('sterlin') ||
        lower.contains('döviz') ||
        lower.contains('kur ')) {
      final fxInfo = await fetchLiveCurrencyRates();
      if (fxInfo != null) {
        traces.add(
          ToolCallTrace(
            name: 'ucretsizServis.doviz',
            title: 'Merkez Bankası Canlı Döviz Kurları',
            inputSummary: 'USD / EUR / GBP -> TRY',
            outputSummary: fxInfo,
          ),
        );
        sections.add('CANLI DÖVİZ KURLARI:\n$fxInfo');
      }
    }

    // 4. Deep Web Research (Derin Araştırma or Research Mode or informational queries)
    final shouldResearch =
        mode == WorkMode.research ||
        lower.contains('araştır') ||
        lower.contains('derin') ||
        lower.contains('kaynaklarıyla') ||
        lower.contains('rapor') ||
        lower.contains('nedir') ||
        lower.contains('kimdir') ||
        lower.contains('tarihi') ||
        lower.contains('analiz');
    if (shouldResearch) {
      final sw = Stopwatch()..start();
      final found = await performWebResearch(prompt);
      sw.stop();
      if (found.isNotEmpty) {
        citations.addAll(found);
        final summary = found
            .map(
              (c) => '### [${c.index}] ${c.title}\n🔗 ${c.url}\n${c.snippet}',
            )
            .join('\n\n');
        traces.add(
          ToolCallTrace(
            name: 'derinArastirma',
            title:
                'Çok Kaynaklı Derin Araştırma (${found.length} Kaynak: Vikipedi + Akademik Makale + Kitap)',
            inputSummary: prompt,
            outputSummary: found
                .map((e) => '[${e.index}] ${e.title}')
                .join(' • '),
            durationMs: sw.elapsedMilliseconds,
          ),
        );
        sections.add('ÇOK KAYNAKLI DERİN ARAŞTIRMA VERİLERİ:\n$summary');
      }
    }

    return sections.join('\n\n');
  }

  String _extractCityName(String lower) {
    const cities = [
      'istanbul',
      'ankara',
      'izmir',
      'bursa',
      'antalya',
      'adana',
      'konya',
      'gaziantep',
      'kocaeli',
      'mersin',
      'diyarbakır',
      'kayseri',
      'eskişehir',
      'samsun',
      'trabzon',
      'erzurum',
      'muğla',
      'aydın',
      'denizli',
      'sakarya',
    ];
    for (final c in cities) {
      if (lower.contains(c)) {
        return c[0].toUpperCase() + c.substring(1);
      }
    }
    return 'İstanbul';
  }

  Future<String?> fetchLiveWeather(String city) async {
    try {
      final geoUri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=tr&format=json',
      );
      final geoResp = await _http
          .get(geoUri)
          .timeout(const Duration(seconds: 5));
      if (geoResp.statusCode != 200) return null;
      final geoJson = jsonDecode(utf8.decode(geoResp.bodyBytes));
      final results = geoJson['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map;
      final lat = first['latitude'];
      final lon = first['longitude'];
      final resolvedName = first['name'] ?? city;

      final wxUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,apparent_temperature,wind_speed_10m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto',
      );
      final wxResp = await _http.get(wxUri).timeout(const Duration(seconds: 5));
      if (wxResp.statusCode != 200) return null;
      final wx = jsonDecode(utf8.decode(wxResp.bodyBytes));
      final cur = wx['current'] as Map?;
      if (cur == null) return null;

      final temp = cur['temperature_2m'];
      final feels = cur['apparent_temperature'];
      final hum = cur['relative_humidity_2m'];
      final wind = cur['wind_speed_10m'];
      return '$resolvedName: Sıcaklık $temp°C (Hissedilen $feels°C), Nem %$hum, Rüzgar $wind km/s.';
    } catch (_) {
      return null;
    }
  }

  Future<String?> fetchRecentEarthquakes() async {
    try {
      final uri = Uri.parse(
        'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minlatitude=35.0&maxlatitude=43.0&minlongitude=25.0&maxlongitude=45.0&limit=6&orderby=time',
      );
      final resp = await _http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) {
        return 'Son saatlerde Türkiye ve çevresinde büyüklüğü 2.5 üzerinde kayıtlı deprem bulunmadı.';
      }
      final lines = <String>[];
      for (final f in features.take(5)) {
        final props = (f as Map)['properties'] as Map?;
        if (props == null) continue;
        final mag = props['mag'];
        final place = props['place'];
        final timeMs = (props['time'] as num?)?.toInt() ?? 0;
        final dt = DateTime.fromMillisecondsSinceEpoch(timeMs).toLocal();
        lines.add(
          '• Büyüklük M$mag — $place (${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')})',
        );
      }
      return lines.join('\n');
    } catch (_) {
      return null;
    }
  }

  Future<String?> fetchLiveCurrencyRates() async {
    try {
      final usdUri = Uri.parse(
        'https://api.frankfurter.app/latest?from=USD&to=TRY,EUR',
      );
      final eurUri = Uri.parse(
        'https://api.frankfurter.app/latest?from=EUR&to=TRY',
      );
      final gbpUri = Uri.parse(
        'https://api.frankfurter.app/latest?from=GBP&to=TRY',
      );

      final responses = await Future.wait([
        _http.get(usdUri).timeout(const Duration(seconds: 5)),
        _http.get(eurUri).timeout(const Duration(seconds: 5)),
        _http.get(gbpUri).timeout(const Duration(seconds: 5)),
      ]);

      final usdData = jsonDecode(utf8.decode(responses[0].bodyBytes));
      final eurData = jsonDecode(utf8.decode(responses[1].bodyBytes));
      final gbpData = jsonDecode(utf8.decode(responses[2].bodyBytes));

      final usdTry = (usdData['rates'] as Map?)?['TRY'];
      final eurTry = (eurData['rates'] as Map?)?['TRY'];
      final gbpTry = (gbpData['rates'] as Map?)?['TRY'];

      return '1 USD = $usdTry TRY • 1 EUR = $eurTry TRY • 1 GBP = $gbpTry TRY';
    } catch (_) {
      return null;
    }
  }

  Future<List<WebCitation>> performWebResearch(String query) async {
    final citations = <WebCitation>[];
    final cleanQuery = query
        .replaceAll(
          RegExp(
            r'(derin|araştırma|araştır|nedir|kimdir|hakkında|bilgi ver|detaylı|rapor hazırla|pdf oluştur|word oluştur)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    final searchTarget = cleanQuery.isEmpty ? query : cleanQuery;

    // 1. Wikipedia TR + Full REST Summary
    Future<void> searchWiki(String lang, String label) async {
      try {
        final wikiUri = Uri.parse(
          'https://$lang.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(searchTarget)}&utf8=&format=json&srlimit=3',
        );
        final resp = await _http
            .get(wikiUri)
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes));
          final searchList =
              ((data['query'] as Map?)?['search'] as List?) ?? const [];
          for (final item in searchList) {
            if (item is Map) {
              final title = item['title']?.toString() ?? '';
              var cleanSnippet = (item['snippet']?.toString() ?? '').replaceAll(
                RegExp(r'<[^>]*>'),
                '',
              );
              if (title.isEmpty) continue;

              // Try to fetch fuller summary from REST API for top result
              try {
                final sumUri = Uri.parse(
                  'https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
                );
                final sumResp = await _http
                    .get(sumUri)
                    .timeout(const Duration(seconds: 5));
                if (sumResp.statusCode == 200) {
                  final sumJson = jsonDecode(utf8.decode(sumResp.bodyBytes));
                  final extract = sumJson['extract']?.toString() ?? '';
                  if (extract.length > cleanSnippet.length) {
                    cleanSnippet = extract;
                  }
                }
              } catch (_) {}

              citations.add(
                WebCitation(
                  index: citations.length + 1,
                  title: '$title — $label',
                  url:
                      'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
                  snippet: cleanSnippet,
                ),
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Crossref Peer-Reviewed Academic Papers
    Future<void> searchAcademicPapers() async {
      try {
        final crUri = Uri.parse(
          'https://api.crossref.org/works?query=${Uri.encodeComponent(searchTarget)}&rows=3',
        );
        final resp = await _http.get(crUri).timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes));
          final items =
              ((data['message'] as Map?)?['items'] as List?) ?? const [];
          for (final w in items) {
            if (w is Map) {
              final titleList = w['title'] as List?;
              final title = (titleList != null && titleList.isNotEmpty)
                  ? titleList.first.toString()
                  : '';
              if (title.isEmpty) continue;
              final doi = w['DOI']?.toString() ?? '';
              final url =
                  w['URL']?.toString() ??
                  (doi.isNotEmpty
                      ? 'https://doi.org/$doi'
                      : 'https://search.crossref.org');
              final containerList = w['container-title'] as List?;
              final journal =
                  (containerList != null && containerList.isNotEmpty)
                  ? containerList.first.toString()
                  : 'Akademik Yayın';
              final publisher = w['publisher']?.toString() ?? '';
              citations.add(
                WebCitation(
                  index: citations.length + 1,
                  title: '$title — Akademik Makale ($journal)',
                  url: url,
                  snippet:
                      'Hakemli akademik çalışma • Dergi/Yayıncı: $journal ${publisher.isNotEmpty ? "($publisher)" : ""} • DOI: $doi',
                ),
              );
            }
          }
        }
      } catch (_) {}
    }

    // 3. OpenLibrary Published Books
    Future<void> searchBooks() async {
      try {
        final olUri = Uri.parse(
          'https://openlibrary.org/search.json?q=${Uri.encodeComponent(searchTarget)}&limit=2',
        );
        final resp = await _http.get(olUri).timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes));
          final docs = (data['docs'] as List?) ?? const [];
          for (final d in docs) {
            if (d is Map) {
              final title = d['title']?.toString() ?? '';
              if (title.isEmpty) continue;
              final authors =
                  (d['author_name'] as List?)?.join(', ') ?? 'Bilinmiyor';
              final year = d['first_publish_year']?.toString() ?? '';
              final key = d['key']?.toString() ?? '';
              citations.add(
                WebCitation(
                  index: citations.length + 1,
                  title: '$title — Kitap Kaynağı ($authors)',
                  url: key.isNotEmpty
                      ? 'https://openlibrary.org$key'
                      : 'https://openlibrary.org',
                  snippet:
                      'Basılı Eser / Kitap • Yazar: $authors ${year.isNotEmpty ? "• İlk Basım: $year" : ""}',
                ),
              );
            }
          }
        }
      } catch (_) {}
    }

    await Future.wait([
      searchWiki('tr', 'Vikipedi TR Ansiklopedisi'),
      searchWiki('en', 'Wikipedia Global Encyclopedia'),
      searchAcademicPapers(),
      searchBooks(),
    ]);

    // Re-index sequentially
    return [
      for (int i = 0; i < citations.length; i++)
        WebCitation(
          index: i + 1,
          title: citations[i].title,
          url: citations[i].url,
          snippet: citations[i].snippet,
        ),
    ];
  }

  // ─── AI IMAGE GENERATION (CLIPROXY + PROCEDURAL FALLBACK) ────────────────

  Future<GeneratedArtifact> generateImageWithProxyOrFallback({
    required String prompt,
    String style = 'Siber Holografik',
  }) async {
    Uint8List? proxyBytes;
    try {
      final uri = Uri.parse('${_cleanBaseUrl()}/v1/images/generations');
      final resp = await _http
          .post(
            uri,
            headers: _authHeaders(),
            body: jsonEncode({
              'model': 'gpt-image-1',
              'prompt': '$prompt, style: $style, ultra detailed masterpiece',
              'n': 1,
              'size': '1024x1024',
              'response_format': 'b64_json',
            }),
          )
          .timeout(const Duration(seconds: 18));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final list = (data is Map ? data['data'] : null) as List?;
        if (list != null && list.isNotEmpty) {
          final first = list.first as Map;
          final b64 = first['b64_json']?.toString();
          if (b64 != null && b64.isNotEmpty) {
            proxyBytes = base64Decode(b64);
          }
        }
      }
    } catch (_) {}

    return DocumentBuilder.saveImageArtifact(
      prompt: prompt,
      imageBytes: proxyBytes,
      style: style,
    );
  }

  // ─── NEURAL TTS VIA CLIPROXY (WITH NATIVE FALLBACK) ──────────────────────

  Future<Uint8List?> synthesizeNeuralSpeech({
    required String text,
    required String voiceId,
    double speed = 1.0,
  }) async {
    try {
      final uri = Uri.parse('${_cleanBaseUrl()}/v1/audio/speech');
      final resp = await _http
          .post(
            uri,
            headers: _authHeaders(),
            body: jsonEncode({
              'model': 'tts-1',
              'input': text,
              'voice': voiceId,
              'speed': speed,
              'response_format': 'mp3',
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && resp.bodyBytes.length > 256) {
        return resp.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  // ─── MCP STREAMABLE HTTP CLIENT (JSON-RPC 2.0) ───────────────────────────

  Future<List<String>> discoverMcpServerTools(McpServerConfig server) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      };
      if (server.authToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${server.authToken}';
      }
      final resp = await _http
          .post(
            Uri.parse(server.url),
            headers: headers,
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'tools/list',
              'params': <String, dynamic>{},
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final tools = ((data['result'] as Map?)?['tools'] as List?) ?? const [];
        return tools
            .whereType<Map>()
            .map((t) => t['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  // ─── LLM CHAT COMPLETION CLIENT (CLIPROXY -> AUTO FALLBACK -> GEMINI) ───

  Future<({String reply, String reasoning, String modelUsed})>
  _callChatCompletion({
    required String model,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userPrompt,
    bool allowFallback = true,
  }) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    for (final msg in history.skip(
      history.length > 12 ? history.length - 12 : 0,
    )) {
      if (msg.text.trim().isEmpty || msg.isError) continue;
      messages.add({
        'role': msg.role == 'user' ? 'user' : 'assistant',
        'content': msg.text,
      });
    }
    messages.add({'role': 'user', 'content': userPrompt});

    // Build candidate model chain for CLIProxy:
    // 1. User's selected model
    // 2. 'auto' (CLIProxy's smart router across all active accounts)
    // 3. First live model reported by /v1/models
    final modelsToTry = <String>[model];
    if (allowFallback && model != 'auto') {
      modelsToTry.add('auto');
    }
    for (final liveId in allowFallback ? liveProxyModelIds : <String>[]) {
      if (!modelsToTry.contains(liveId)) {
        modelsToTry.add(liveId);
        break;
      }
    }

    for (final candidateModel in modelsToTry) {
      final proxyRes = await _trySingleProxyModelCall(
        candidateModel: candidateModel,
        messages: messages,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );
      if (proxyRes != null && proxyRes.reply.trim().isNotEmpty) {
        lastAuthStatus = ProxyAuthStatus.connected;
        return (
          reply: proxyRes.reply,
          reasoning: proxyRes.reasoning,
          modelUsed: candidateModel,
        );
      }
      if (lastAuthStatus == ProxyAuthStatus.needsKey) {
        break; // 401 Unauthorized — don't retry other models without key
      }
    }

    // 2. Try Direct Gemini API if configured
    if (allowFallback && geminiDirectApiKey.trim().isNotEmpty) {
      try {
        final geminiModel = model.startsWith('gemini')
            ? model
            : 'gemini-2.5-flash';
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=${geminiDirectApiKey.trim()}',
        );
        final resp = await _http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {'text': systemPrompt},
                  ],
                },
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      {'text': userPrompt},
                    ],
                  },
                ],
              }),
            )
            .timeout(const Duration(seconds: 32));

        if (resp.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
          final candidates = decoded['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts =
                ((candidates.first as Map)['content'] as Map?)?['parts']
                    as List?;
            final text =
                parts
                    ?.map((p) => (p as Map)['text']?.toString() ?? '')
                    .join('\n') ??
                '';
            if (text.isNotEmpty) {
              final split = _splitThinkTags(text, '');
              return (
                reply: split.reply,
                reasoning: split.reasoning,
                modelUsed: geminiModel,
              );
            }
          }
        }
      } catch (_) {}
    }

    if (!allowFallback) {
      throw StateError(
        'Seçilen sesli sohbet modeline ulaşılamadı. Proxy bağlantısını kontrol edin.',
      );
    }

    // 3. Smart Offline/Local Synthesis Fallback (never leaves user hanging)
    return (
      reply: _buildResilientFallbackReply(userPrompt),
      reasoning: lastAuthStatus == ProxyAuthStatus.needsKey
          ? 'CLIProxy (127.0.0.1:8317) algılandı ancak API anahtarı (sk-iphone-...) bekleniyor.'
          : 'Yerel otonom asistan motoru devreye girdi (CLIProxy http://127.0.0.1:8317 bekleniyor).',
      modelUsed: 'Yerel yanıt (AI bağlantısı yok)',
    );
  }

  Future<({String reply, String reasoning})?> _trySingleProxyModelCall({
    required String candidateModel,
    required List<Map<String, dynamic>> messages,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    try {
      final uri = _buildAuthedUri('/v1/chat/completions');
      final resp = await _http
          .post(
            uri,
            headers: _authHeaders(),
            body: jsonEncode({
              'model': candidateModel,
              'messages': messages,
              'temperature': 0.65,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        lastAuthStatus = ProxyAuthStatus.needsKey;
        lastProxyError = 'CLIProxy API anahtarı (sk-iphone-...) gerekli.';
        return null;
      }

      if (resp.statusCode == 200) {
        final rawBody = utf8.decode(resp.bodyBytes);
        final parsed = _parseOpenAiOrSsePayload(rawBody);
        if (parsed != null && parsed.reply.trim().isNotEmpty) {
          return parsed;
        }
      }
    } catch (_) {}

    // If model is Claude and /v1/chat/completions didn't return, also try /v1/messages
    if (candidateModel.contains('claude')) {
      try {
        final uri = _buildAuthedUri('/v1/messages');
        final resp = await _http
            .post(
              uri,
              headers: {..._authHeaders(), 'anthropic-version': '2023-06-01'},
              body: jsonEncode({
                'model': candidateModel,
                'max_tokens': 4096,
                'system': systemPrompt,
                'messages': [...messages.where((m) => m['role'] != 'system')],
              }),
            )
            .timeout(const Duration(seconds: 38));
        if (resp.statusCode == 200) {
          final rawBody = utf8.decode(resp.bodyBytes);
          final parsed = _parseOpenAiOrSsePayload(rawBody);
          if (parsed != null && parsed.reply.trim().isNotEmpty) {
            return parsed;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  ({String reply, String reasoning})? _parseOpenAiOrSsePayload(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return null;

    // Handle SSE stream format (data: {...}) if CLIProxy returns text/event-stream
    if (trimmed.startsWith('data:') || trimmed.contains('\ndata:')) {
      final buffer = StringBuffer();
      final reasoningBuf = StringBuffer();
      for (final line in trimmed.split('\n')) {
        final l = line.trim();
        if (!l.startsWith('data:')) continue;
        final payload = l.substring(5).trim();
        if (payload == '[DONE]' || payload.isEmpty) continue;
        try {
          final json = jsonDecode(payload);
          if (json is Map) {
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final first = choices.first as Map;
              final delta = (first['delta'] ?? first['message']) as Map?;
              if (delta != null) {
                final c = delta['content']?.toString() ?? '';
                final r = delta['reasoning_content']?.toString() ?? '';
                buffer.write(c);
                reasoningBuf.write(r);
              }
            }
          }
        } catch (_) {}
      }
      final combined = buffer.toString().trim();
      if (combined.isNotEmpty) {
        return _splitThinkTags(combined, reasoningBuf.toString());
      }
    }

    // Standard JSON response (/v1/chat/completions, /v1/messages, /v1/responses)
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        // 1. OpenAI /v1/chat/completions format
        final choices = decoded['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices.first as Map;
          final msg = (firstChoice['message'] ?? firstChoice['delta']) as Map?;
          final content = msg?['content'];
          String textContent = '';
          if (content is String) {
            textContent = content;
          } else if (content is List) {
            textContent = content
                .whereType<Map>()
                .map((part) => part['text']?.toString() ?? '')
                .join('\n');
          }
          final reasoningContent =
              msg?['reasoning_content']?.toString() ??
              msg?['reasoning']?.toString() ??
              '';
          if (textContent.trim().isNotEmpty) {
            return _splitThinkTags(textContent, reasoningContent);
          }
        }

        // 2. Anthropic /v1/messages format
        final contentList = decoded['content'] as List?;
        if (contentList != null && contentList.isNotEmpty) {
          final textBuf = StringBuffer();
          final thinkBuf = StringBuffer();
          for (final block in contentList.whereType<Map>()) {
            final type = block['type']?.toString() ?? '';
            if (type == 'thinking') {
              thinkBuf.writeln(block['thinking']?.toString() ?? '');
            } else if (block['text'] != null) {
              textBuf.write(block['text'].toString());
            }
          }
          if (textBuf.toString().trim().isNotEmpty) {
            return _splitThinkTags(textBuf.toString(), thinkBuf.toString());
          }
        }

        // 3. OpenAI /v1/responses format
        final outputText = decoded['output_text']?.toString() ?? '';
        if (outputText.trim().isNotEmpty) {
          return _splitThinkTags(outputText, '');
        }
      }
    } catch (_) {}
    return null;
  }

  ({String reply, String reasoning}) _splitThinkTags(
    String rawText,
    String explicitReasoning,
  ) {
    var text = rawText.trim();
    var reasoning = explicitReasoning.trim();

    final thinkMatch = RegExp(
      r'<think>([\s\S]*?)</think>',
      caseSensitive: false,
    ).firstMatch(text);
    if (thinkMatch != null) {
      final extracted = thinkMatch.group(1)?.trim() ?? '';
      if (extracted.isNotEmpty) {
        reasoning = reasoning.isEmpty ? extracted : '$reasoning\n$extracted';
      }
      text = text.replaceFirst(thinkMatch.group(0)!, '').trim();
    }
    return (reply: text, reasoning: reasoning);
  }

  String _buildSystemPrompt({
    required WorkMode mode,
    required List<MemoryFact> memories,
    required List<WebCitation> citations,
    String personaId = 'claude_code',
  }) {
    final now = DateTime.now();
    final persona = AssistantPersona.fromId(personaId);
    final memBlock = memories.isEmpty
        ? ''
        : '\nKULLANICI HAFIZA OLGULARI:\n${memories.map((m) => '- (${m.category}) ${m.fact}').join('\n')}\n';

    final citBlock = citations.isEmpty
        ? ''
        : '\nKAYNAKÇA KURALI: Yanıtında bilgileri aktarırken köşeli parantez içinde [1], [2] gibi kaynak numaralarını kullan.\n';

    final modeDirective = switch (mode) {
      WorkMode.voice => 'Şu an CANLI SES (Gemini Live / ChatGPT Voice / Claude Live / Siri) modundasın. Yanıtların doğal, akıcı, sesli okunmaya uygun, gereksiz sembollerden arındırılmış ve net olsun.',
      WorkMode.research => 'Şu an DERİN ARAŞTIRMA modundasın. Konuyu alt başlıklara ayır, analitik veriler sun, karşılaştırma tabloları ekle ve [n] şeklinde kaynak atıfları yap.',
      WorkMode.canvas => 'Şu an CLAUDE CODE & TUVAL ATÖLYESİ modundasın. Temiz, eksiksiz, doğrudan çalıştırılabilir kod blokları, mimari açıklamalar ve yapılandırılmış metin üret.',
      WorkMode.office => 'Şu an OFİS BELGESİ ÜRETİCİ modundasın. İçeriği profesyonel bir rapor/belge/tablo düzeninde hazırla.',
      WorkMode.image => 'Şu an GÖRSEL STÜDYO modundasın. Üretilen görseli betimle ve tasarım detaylarını açıkla.',
      WorkMode.council => 'Şu an MODEL KONSEYİ modundasın. Çok boyutlu, karşılaştırmalı ve sentezleyici yanıt ver.',
      WorkMode.device => 'Şu an TELEFON & SİSTEM ASİSTANI modundasın. Gerçekleştirilen cihaz işlemini net biçimde onayla.',
      WorkMode.auto => 'Claude Code, ChatGPT, Gemini, Siri ve Google Asistan yeteneklerinin tamamını birleştiren süper asistansın. Yanıtlarını geniş, okunaklı, net alt başlıklar ve gerektiğinde kod veya tablolarla zenginleştir.',
    };

    return '''Sen Mehmet için özel olarak geliştirilmiş "Asistan AI Studio v4.0" (Claude Code + ChatGPT + Gemini Live + Siri + Google Asistan birleşimi) süper yapay zeka asistanısın.
Aktif Uzmanlık Kimliği: ${persona.name} — ${persona.systemInstruction}
Tarih/Saat: ${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}
Her zaman Türkçe, anlaşılır, zengin ve doğru yanıt ver.
$modeDirective$memBlock$citBlock''';
  }

  String _buildResilientFallbackReply(String fullPrompt) {
    if (fullPrompt.contains('[CANLI ARAÇ VE VERİ BAĞLAMI]')) {
      final idx = fullPrompt.indexOf('[CANLI ARAÇ VE VERİ BAĞLAMI]');
      final contextData = fullPrompt
          .substring(idx + '[CANLI ARAÇ VE VERİ BAĞLAMI]'.length)
          .trim();
      return '### ✅ İşlem Tamamlandı\n\n$contextData';
    }
    if (lastAuthStatus == ProxyAuthStatus.needsKey) {
      return '''### 🔑 Siri CLIProxy (`127.0.0.1:8317`) Algılandı — Anahtar Bekleniyor

Telefonunuzda **CLIProxy** servisi şu an çalışıyor ancak API anahtarı (`sk-iphone-...`) henüz eşleştirilmedi.

**Tek Dokunuşla Bağlamak İçin:**
1. Mesaj ekranının üst kısmındaki **"🚀 CLIProxy'yi Aç"** butonuna dokunun ve anahtarı kopyalayın.
2. Bu uygulamaya döndüğünüzde anahtar **panodan otomatik algılanıp** bağlanacaktır (veya **"📋 Panodan Anahtar Yapıştır"** butonuna basabilirsiniz).''';
    }
    return '''### ⚡ Asistan Yerel Motor Yanıtı

İsteğiniz alındı: **"$fullPrompt"**

- **Yerel Araçlar Aktif:** El feneri, alarm, sayaç, hatırlatıcı, rehber, takvim, PDF/Word/Excel/PPTX belge üretimi, canlı hava durumu, deprem ve döviz araçları doğrudan çalışmaktadır.
- **Siri CLIProxy (`127.0.0.1:8317`) Bağlantısı:** Claude Sonnet 5.5, GPT-6.1 Sol ve Gemini 2.5 Pro modellerine bağlanmak için üst bardaki **CLIProxy Bağla** butonundan servisi açabilir veya anahtarınızı yapıştırabilirsiniz.''';
  }

  List<String> _detectRequestedDocumentFormats(String lower, WorkMode mode) {
    final formats = <String>[];
    if (lower.contains('tüm ofis') ||
        lower.contains('hepsini oluştur') ||
        lower.contains('ofis dosyalarının hepsini')) {
      return ['pdf', 'docx', 'xlsx', 'pptx', 'csv', 'html'];
    }
    if (lower.contains('pdf oluştur') ||
        lower.contains('pdf hazırla') ||
        lower.contains('pdf yap') ||
        lower.contains('pdf indir') ||
        lower.contains('pdf olarak')) {
      formats.add('pdf');
    }
    if (lower.contains('word oluştur') ||
        lower.contains('word hazırla') ||
        lower.contains('word indir') ||
        lower.contains('docx') ||
        lower.contains('word belgesi')) {
      formats.add('docx');
    }
    if (lower.contains('excel') ||
        lower.contains('xlsx') ||
        lower.contains('tablo dosyası') ||
        lower.contains('tablo indir')) {
      formats.add('xlsx');
    }
    if (lower.contains('sunum hazırla') ||
        lower.contains('sunum oluştur') ||
        lower.contains('sunum indir') ||
        lower.contains('powerpoint') ||
        lower.contains('pptx')) {
      formats.add('pptx');
    }
    if (lower.contains('csv oluştur') || lower.contains('csv indir')) {
      formats.add('csv');
    }
    if (lower.contains('html oluştur') || lower.contains('html indir')) {
      formats.add('html');
    }
    if (formats.isEmpty && mode == WorkMode.office) {
      formats.add('pdf');
      formats.add('docx');
    }
    return formats;
  }

  String _extractDocumentTitle(String prompt) {
    final clean = prompt
        .replaceAll(
          RegExp(
            r'(bana|lütfen|hakkında|pdf|word|excel|sunum|pptx|docx|xlsx|oluştur|hazırla|yap|yaz)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (clean.isEmpty) return 'Asistan Raporu';
    return clean.length > 36 ? clean.substring(0, 36).trim() : clean;
  }

  String _cleanBaseUrl() {
    var u = baseUrl.trim();
    if (u.isEmpty) u = 'http://127.0.0.1:8317';
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/v1')) {
      u = u.substring(0, u.length - 3);
    }
    return u;
  }

  Uri _buildAuthedUri(String path) {
    final base = _cleanBaseUrl();
    final key = apiKey.trim();
    if (key.isNotEmpty) {
      final sep = path.contains('?') ? '&' : '?';
      return Uri.parse('$base$path${sep}key=${Uri.encodeQueryComponent(key)}');
    }
    return Uri.parse('$base$path');
  }

  Map<String, String> _authHeaders() {
    final key = apiKey.trim();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      if (key.isNotEmpty) ...{
        'Authorization': 'Bearer $key',
        'x-api-key': key,
        'x-goog-api-key': key,
      },
    };
  }
}
