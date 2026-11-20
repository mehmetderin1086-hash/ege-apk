import 'package:flutter/material.dart';

import '../models/jarvis_models.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';
import '../widgets/chat_palette.dart';

/// Cloud voice gallery: every Azure / Google Chirp 3 HD / OpenAI / Edge voice
/// with live preview, speaking styles, speed & pitch and engine diagnostics.
class VoiceStudioScreen extends StatefulWidget {
  final JarvisController controller;

  const VoiceStudioScreen({super.key, required this.controller});

  @override
  State<VoiceStudioScreen> createState() => _VoiceStudioScreenState();
}

class _VoiceStudioScreenState extends State<VoiceStudioScreen> {
  String _filter = 'all'; // all | f | m
  String _query = '';
  bool _diagnosing = false;
  List<TtsAttempt>? _diag;

  JarvisController get c => widget.controller;

  static const _engines = [
    ('auto', 'Otomatik (önerilen)', Icons.auto_mode_rounded),
    ('proxy', 'PC CLI Proxy', Icons.dns_rounded),
    ('azure', 'Azure Speech', Icons.cloud_rounded),
    ('gemini', 'Gemini TTS', Icons.auto_awesome_rounded),
    ('google_cloud', 'Google Cloud', Icons.cloud_circle_rounded),
    ('openai', 'OpenAI TTS', Icons.hub_rounded),
    ('edge_neural', 'Edge (ücretsiz)', Icons.public_rounded),
    ('device', 'Cihaz sesi', Icons.phone_android_rounded),
  ];

  bool _matches(JarvisVoiceOption v) {
    if (_filter != 'all' && v.gender != _filter) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return v.label.toLowerCase().contains(q) || v.description.toLowerCase().contains(q) || v.id.toLowerCase().contains(q);
  }

  String? _missingKey(String engine) {
    final s = c.settings;
    return switch (engine) {
      'azure' => s.azureSpeechKey.isEmpty && s.ttsProxyUrl.contains('127.0.0.1') ? 'Azure anahtarı yok (PC\'den API alın)' : null,
      'chirp' => s.geminiTtsKey.isEmpty && s.ttsProxyUrl.contains('127.0.0.1') ? 'Gemini anahtarı yok (PC\'den API alın)' : null,
      'openai' => s.openAiTtsKey.isEmpty && s.openAiLiveKey.isEmpty && s.ttsProxyUrl.contains('127.0.0.1')
          ? 'OpenAI anahtarı yok'
          : null,
      _ => null,
    };
  }

  Future<void> _diagnose() async {
    setState(() {
      _diagnosing = true;
      _diag = null;
    });
    final res = await c.diagnoseTts();
    if (!mounted) return;
    setState(() {
      _diagnosing = false;
      _diag = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        final current = JarvisVoiceCatalog.find(s.proxyTtsVoice);
        final style = JarvisVoiceCatalog.styleFor(s.ttsStyle);
        final groups = <(String, String, IconData, Color, List<JarvisVoiceOption>)>[
          ('azure', 'Azure Speech • Türkçe & Çok Dilli', Icons.cloud_rounded, ChatPalette.accent,
              JarvisVoiceCatalog.azureVoices.where(_matches).toList()),
          ('chirp', 'Google Chirp 3 HD / Gemini TTS', Icons.auto_awesome_rounded, JColors.violet,
              JarvisVoiceCatalog.chirpCatalog.where(_matches).toList()),
          ('openai', 'OpenAI TTS (gpt-4o-mini-tts)', Icons.hub_rounded, JColors.ok,
              JarvisVoiceCatalog.openAiTtsVoices.where(_matches).toList()),
          ('edge', 'Edge Neural • Anahtarsız', Icons.public_rounded, JColors.warn,
              JarvisVoiceCatalog.edgeVoices.where(_matches).toList()),
          if (c.azureCloudVoices.isNotEmpty)
            ('azure_live', 'Azure Canlı Liste (${c.azureCloudVoices.length})', Icons.cloud_download_rounded,
                ChatPalette.accent, c.azureCloudVoices.where(_matches).toList()),
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bulut Ses Stüdyosu'),
            actions: [
              IconButton(
                tooltip: 'Tüm motorları test et',
                onPressed: _diagnosing ? null : _diagnose,
                icon: _diagnosing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.health_and_safety_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
            children: [
              GlassCard(
                glow: JColors.violet,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Color(0xFF7C3AED), ChatPalette.accent]),
                          ),
                          child: const Icon(Icons.record_voice_over_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(current?.shortName ?? s.proxyTtsVoice,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              Text(
                                '${current?.engineLabel ?? 'Özel ses'} • ton: ${style.label}',
                                style:  TextStyle(fontSize: 12, color: JColors.muted),
                              ),
                              if (c.lastTtsEngine.isNotEmpty)
                                Text('Son çalan: ${c.lastTtsEngine}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:  TextStyle(fontSize: 11, color: JColors.accent)),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: c.previewingVoiceId != null
                              ? null
                              : () async {
                                  final v = current ??
                                      JarvisVoiceOption(id: s.proxyTtsVoice, label: s.proxyTtsVoice, engine: 'azure');
                                  final engine = await c.previewVoice(v);
                                  if (context.mounted) showJarvisSnack(context, 'Çalan motor: $engine');
                                },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Dinle'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                     Text('Konuşma tonu', style: TextStyle(fontSize: 12, color: JColors.muted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final st in JarvisVoiceCatalog.styles.values)
                          ChoiceChip(
                            label: Text(st.label),
                            selected: s.ttsStyle == st.id,
                            onSelected: (_) => c.updateSettings(s.copyWith(ttsStyle: st.id)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const SizedBox(width: 60, child: Text('Hız', style: TextStyle(fontSize: 12.5))),
                        Expanded(
                          child: Slider(
                            value: s.ttsRate.clamp(0.3, 1.0),
                            min: 0.3,
                            max: 1.0,
                            divisions: 14,
                            label: '×${(s.ttsRate / 0.52).toStringAsFixed(2)}',
                            onChanged: (v) => c.updateSettings(s.copyWith(ttsRate: v)),
                          ),
                        ),
                        Text('×${(s.ttsRate / 0.52).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 60, child: Text('Perde', style: TextStyle(fontSize: 12.5))),
                        Expanded(
                          child: Slider(
                            value: s.ttsPitch.clamp(0.6, 1.5),
                            min: 0.6,
                            max: 1.5,
                            divisions: 18,
                            label: s.ttsPitch.toStringAsFixed(2),
                            onChanged: (v) => c.updateSettings(s.copyWith(ttsPitch: v)),
                          ),
                        ),
                        Text(s.ttsPitch.toStringAsFixed(2), style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Yanıtları otomatik seslendir'),
                      value: s.autoTts,
                      onChanged: (v) => c.updateSettings(s.copyWith(autoTts: v)),
                    ),
                  ],
                ),
              ),
              const SectionTitle('Ses motoru', icon: Icons.settings_voice_rounded),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in _engines)
                    ChoiceChip(
                      avatar: Icon(e.$3, size: 16),
                      label: Text(e.$2),
                      selected: s.ttsEngine == e.$1,
                      onSelected: (_) => c.updateSettings(s.copyWith(ttsEngine: e.$1, useProxyTts: e.$1 != 'device')),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.ttsEngine == 'auto'
                    ? 'Otomatik: seçili sese göre en iyi bulut motoru denenir, başarısız olursa sıradakine geçilir.'
                    : 'Yalnız seçili motor kullanılır.',
                style:  TextStyle(fontSize: 11.5, color: JColors.dim),
              ),
              if (_diag != null) ...[
                const SectionTitle('Motor testi', icon: Icons.health_and_safety_rounded),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in _diag!)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(a.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  size: 16, color: a.ok ? JColors.ok : JColors.bad),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${a.provider}${a.ms > 0 ? ' • ${a.ms} ms' : ''}${a.detail.isEmpty ? '' : '\n${a.detail}'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SectionTitle('Ses galerisi', icon: Icons.library_music_rounded),
              TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText: 'Ses ara (ör. sıcak, Kore, HD)',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final f in const [('all', 'Tümü'), ('f', 'Kadın'), ('m', 'Erkek')])
                    ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      onSelected: (_) => setState(() => _filter = f.$1),
                    ),
                  TextButton.icon(
                    onPressed: c.loadingAzureVoices
                        ? null
                        : () async {
                            final err = await c.loadAzureCloudVoices();
                            if (err != null && context.mounted) showJarvisSnack(context, err, error: true);
                          },
                    icon: c.loadingAzureVoices
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_download_rounded, size: 18),
                    label: const Text('Azure listesi'),
                  ),
                ],
              ),
              for (final g in groups)
                if (g.$5.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: GlassCard(
                      padding: EdgeInsets.zero,
                      glow: g.$4,
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: g.$5.any((v) => v.id == s.proxyTtsVoice) || _query.isNotEmpty,
                          leading: Icon(g.$3, color: g.$4),
                          title: Text(g.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(
                            _missingKey(g.$1) ??
                                (g.$1 == 'chirp'
                                    ? '${g.$5.length} ses • ücretsiz anahtarda günlük ~10 istek; dolunca Azure HD devralır'
                                    : g.$1 == 'azure'
                                        ? '${g.$5.length} ses • önerilen: Aydın 2.1 / Elif 2.1 (~1 sn)'
                                        : '${g.$5.length} ses'),
                            style: TextStyle(fontSize: 11.5, color: _missingKey(g.$1) != null ? JColors.warn : JColors.muted),
                          ),
                          children: [
                            for (final v in g.$5) _voiceTile(v, g.$4),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _voiceTile(JarvisVoiceOption v, Color color) {
    final s = c.settings;
    final selected = s.proxyTtsVoice.toLowerCase() == v.id.toLowerCase() &&
        ((v.engine == 'edge') == (s.ttsEngine == 'edge_neural'));
    final previewing = c.previewingVoiceId == v.id;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          v.gender == 'f' ? Icons.face_3_rounded : v.gender == 'm' ? Icons.face_6_rounded : Icons.face_rounded,
          size: 18,
          color: color,
        ),
      ),
      title: Text(v.shortName, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
      subtitle: Text(
        v.description.isEmpty ? v.label : v.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:  TextStyle(fontSize: 11.5, color: JColors.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Dinle',
            onPressed: c.previewingVoiceId != null && !previewing
                ? null
                : previewing
                    ? c.stopSpeaking
                    : () async {
                        final engine = await c.previewVoice(v);
                        if (mounted && engine.contains('hata')) {
                          showJarvisSnack(context, engine, error: true);
                        }
                      },
            icon: previewing
                ?  Icon(Icons.stop_circle_rounded, color: JColors.bad)
                : const Icon(Icons.play_circle_fill_rounded),
          ),
          selected
              ?  Icon(Icons.check_circle_rounded, color: JColors.ok)
              : IconButton(
                  tooltip: 'Bu sesi kullan',
                  onPressed: () async {
                    await c.selectVoice(v);
                    if (mounted) showJarvisSnack(context, '${v.shortName} seçildi');
                  },
                  icon: const Icon(Icons.radio_button_unchecked_rounded),
                ),
        ],
      ),
      onTap: () => c.selectVoice(v),
    );
  }
}
