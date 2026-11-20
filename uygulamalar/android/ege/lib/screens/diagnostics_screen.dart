import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/jarvis_models.dart';
import '../services/ai_client.dart';
import '../services/device_bridge.dart';
import '../services/embedded_keys.dart';
import '../services/pc_bridge_client.dart';
import '../services/tts_cache.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';

class _Check {
  final String title;
  final IconData icon;
  bool? ok; // null = running / skipped(warn)
  bool warn = false;
  String detail = '';
  int ms = 0;

  _Check(this.title, this.icon);
}

/// "Sistem Tanı" (Windows Ege /pc-health port): checks every service the
/// phone uses on its own.
class DiagnosticsScreen extends StatefulWidget {
  final JarvisController controller;

  const DiagnosticsScreen({super.key, required this.controller});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final List<_Check> _checks = [];
  bool _running = false;

  JarvisController get c => widget.controller;
  JarvisSettings get s => c.settings;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _measure(_Check ch, Future<String> Function() body) async {
    final sw = Stopwatch()..start();
    try {
      ch.detail = await body();
      ch.ok = true;
    } on _Warn catch (w) {
      ch.ok = null;
      ch.warn = true;
      ch.detail = w.message;
    } catch (e) {
      ch.ok = false;
      ch.detail = '$e';
    } finally {
      ch.ms = sw.elapsedMilliseconds;
      if (mounted) setState(() {});
    }
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _checks.clear();
    });
    AiClient.resetTtsHealth();
    final client = http.Client();
    try {
      final internet = _Check('İnternet bağlantısı', Icons.public_rounded);
      final keys = _Check('Gömülü / kayıtlı anahtarlar', Icons.vpn_key_rounded);
      final chat = _Check(
        'Sohbet modeli (${s.provider.label} • ${s.model})',
        Icons.chat_rounded,
      );
      final azure = _Check(
        'Azure Speech (HD Türkçe sesler)',
        Icons.record_voice_over_rounded,
      );
      final voice = _Check('Seçili bulut ses', Icons.graphic_eq_rounded);
      final edge = _Check('Edge ücretsiz ses', Icons.campaign_rounded);
      final proxy = _Check('PC CLI Proxy (isteğe bağlı)', Icons.dns_rounded);
      final bridge = _Check(
        'PC Köprüsü (isteğe bağlı)',
        Icons.laptop_windows_rounded,
      );
      final mic = _Check(
        'Konuşma tanıma (Android yerel STT)',
        Icons.mic_rounded,
      );
      final alarms = _Check(
        'Kapalıyken hatırlatıcı (kesin alarm izni)',
        Icons.alarm_rounded,
      );
      final cache = _Check('Ses önbelleği', Icons.storage_rounded);
      _checks.addAll([
        internet,
        keys,
        chat,
        azure,
        voice,
        edge,
        proxy,
        bridge,
        mic,
        alarms,
        cache,
      ]);
      setState(() {});

      await _measure(internet, () async {
        final r = await client
            .get(Uri.parse('https://www.google.com/generate_204'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode != 204 && r.statusCode != 200)
          throw 'HTTP ${r.statusCode}';
        return 'Çevrimiçi';
      });
      await _measure(keys, () async {
        final emb = EmbeddedKeys.instance;
        final parts = [
          'Gemini: ${AiClient.geminiKeyFor(s).isEmpty ? 'yok' : 'var'}',
          'Azure: ${s.azureSpeechKey.isEmpty ? 'yok' : 'var (${s.azureSpeechRegion})'}',
          'Gömülü paket: ${emb.available ? 'var' : 'yok'}',
        ];
        if (AiClient.geminiKeyFor(s).isEmpty && s.azureSpeechKey.isEmpty)
          throw _Warn(parts.join(' • '));
        return parts.join(' • ');
      });
      await _measure(chat, () async {
        final r = await AiClient.completeOnce(
          settings: s,
          system: 'Kısa yanıt ver.',
          user: 'Sadece "tamam" yaz.',
          client: client,
          timeout: const Duration(seconds: 40),
        );
        if (!r.ok) throw r.error ?? 'yanıt yok';
        return 'Yanıt: ${r.text.trim().split('\n').first}';
      });
      await _measure(azure, () async {
        if (s.azureSpeechKey.trim().isEmpty)
          throw const _Warn(
            'Anahtar yok — HD Türkçe sesler kapalı, Edge kullanılır.',
          );
        final region = s.azureSpeechRegion.trim().isEmpty
            ? 'westeurope'
            : s.azureSpeechRegion.trim();
        final r = await client
            .post(
              Uri.parse(
                'https://$region.api.cognitive.microsoft.com/sts/v1.0/issueToken',
              ),
              headers: {'Ocp-Apim-Subscription-Key': s.azureSpeechKey.trim()},
            )
            .timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
        return 'Anahtar geçerli ($region)';
      });
      await _measure(voice, () async {
        final r = await AiClient.synthesizeSpeechDetailed(
          settings: s,
          text: 'Ses testi.',
          client: client,
          useCache: false,
        );
        if (!r.ok) throw r.failureSummary;
        final v =
            JarvisVoiceCatalog.find(s.proxyTtsVoice)?.shortName ??
            s.proxyTtsVoice;
        if (r.provider.contains('Yedek'))
          throw _Warn('$v → yalnız yedek ses çalıştı (${r.provider})');
        return '$v → ${r.provider}';
      });
      await _measure(edge, () async {
        final r = await AiClient.synthesizeSpeechDetailed(
          settings: s,
          text: 'Test.',
          client: client,
          onlyProviders: const ['edge_neural'],
          useCache: false,
        );
        if (!r.ok) throw r.failureSummary;
        return 'Çalışıyor (anahtarsız)';
      });
      await _measure(proxy, () async {
        final base = s.provider == ApiProvider.cliProxyApi
            ? s.baseUrl
            : s.ttsProxyUrl;
        if (base.trim().isEmpty || AiClient.isLoopbackUrl(base)) {
          throw const _Warn('Ayarlanmamış — telefon tek başına çalışıyor.');
        }
        if (!await AiClient.proxyReachable(base))
          throw _Warn('Erişilemiyor ($base) — PC kapalı ya da farklı ağ.');
        final key = s.provider == ApiProvider.cliProxyApi
            ? s.apiKey
            : s.ttsProxyKey;
        final r = await client
            .get(
              Uri.parse('${AiClient.normalizedOpenAiBase(base)}/v1/models'),
              headers: {if (key.isNotEmpty) 'Authorization': 'Bearer $key'},
            )
            .timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
        final n =
            (jsonDecode(utf8.decode(r.bodyBytes))['data'] as List?)?.length ??
            0;
        return '$n model hazır';
      });
      await _measure(bridge, () async {
        if (!s.pcPaired) throw const _Warn('Eşleşmemiş (PC Kod sekmesi).');
        final info = await PcBridgeClient.ping(s.pcBridgeUrl);
        if (info == null) throw const _Warn('PC Köprüsü yanıt vermiyor.');
        return '${info.host} • v${info.version}';
      });
      await _measure(mic, () async {
        await DeviceBridge.preparePhoneSpeech(force: true);
        throw const _Warn(
          'Android dil desteği kontrolü istendi. Gerçek konuşma testi için mikrofonu kullan; Whisper kapalı.',
        );
      });
      await _measure(alarms, () async {
        final ok = await DeviceBridge.canScheduleExactAlarms();
        if (!ok)
          throw const _Warn(
            'İzin yok — hatırlatıcılar birkaç dakika gecikebilir.',
          );
        return 'Kesin zamanlı';
      });
      await _measure(cache, () async {
        final st = await TtsDiskCache.stats();
        return '${st.files} cümle • ${formatBytes(st.bytes)}';
      });
    } finally {
      client.close();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final okCount = _checks.where((c) => c.ok == true).length;
    final bad = _checks.where((c) => c.ok == false).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sistem Tanı'),
        actions: [
          IconButton(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
        children: [
          GlassCard(
            glow: bad > 0 ? JColors.bad : JColors.ok,
            child: Row(
              children: [
                Icon(
                  bad > 0
                      ? Icons.report_problem_rounded
                      : Icons.verified_rounded,
                  color: bad > 0 ? JColors.bad : JColors.ok,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _running
                        ? 'Kontroller çalışıyor…'
                        : (bad == 0
                              ? 'Telefon tek başına çalışmaya hazır ($okCount kontrol başarılı).'
                              : '$bad kontrol başarısız.'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final ch in _checks)
            Card(
              color: JColors.surface,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(ch.icon, color: JColors.primary),
                title: Text(
                  ch.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${ch.detail}${ch.ms > 0 ? ' • ${ch.ms} ms' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: ch.ok == false
                        ? JColors.bad
                        : (ch.warn ? JColors.warn : JColors.muted),
                  ),
                ),
                trailing: ch.ok == null && !ch.warn
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        ch.ok == true
                            ? Icons.check_circle_rounded
                            : (ch.warn
                                  ? Icons.info_rounded
                                  : Icons.cancel_rounded),
                        color: ch.ok == true
                            ? JColors.ok
                            : (ch.warn ? JColors.warn : JColors.bad),
                      ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => DeviceBridge.openExactAlarmSettings(),
                icon: const Icon(Icons.alarm_on_rounded, size: 18),
                label: const Text('Kesin alarm izni'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final n = await TtsDiskCache.clear();
                  if (context.mounted)
                    showJarvisSnack(context, '$n önbellek dosyası silindi');
                  unawaited(_run());
                },
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('Ses önbelleğini temizle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Warn implements Exception {
  final String message;

  const _Warn(this.message);

  @override
  String toString() => message;
}
