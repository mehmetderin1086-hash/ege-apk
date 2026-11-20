import '../services/device_bridge.dart';

import 'package:flutter/material.dart';

import '../models/jarvis_models.dart';
import '../state/jarvis_controller.dart';
import '../widgets/chat_palette.dart';
import '../widgets/appearance_settings.dart';
import '../widgets/account_connections.dart';
import '../widgets/download_settings.dart';
import '../widgets/jarvis_ui.dart' show showJarvisSnack, StatusDot;
import '../widgets/assistant_setup_card.dart';
import '../widgets/model_picker_sheet.dart';
import 'voice_studio_screen.dart';
import 'speaker_profile_screen.dart';
import 'app_control_screen.dart';
import 'diagnostics_screen.dart';
import 'memory_screen.dart';
import '../services/embedded_keys.dart';

class SettingsScreen extends StatefulWidget {
  final JarvisController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _personaCtrl;
  late final TextEditingController _azureKeyCtrl;
  late final TextEditingController _azureRegionCtrl;
  late final TextEditingController _ttsProxyUrlCtrl;
  late final TextEditingController _geminiTtsKeyCtrl;
  late final TextEditingController _googleCloudTtsKeyCtrl;
  late final TextEditingController _openAiTtsKeyCtrl;
  late final TextEditingController _whisperKeyCtrl;
  late final TextEditingController _whisperBaseCtrl;
  bool _obscureKey = true;
  bool _obscureAzureKey = true;
  bool _obscureGeminiTtsKey = true;
  bool _obscureGoogleCloudTtsKey = true;
  bool _obscureOpenAiTtsKey = true;
  bool _diagnosingTts = false;
  List<TtsAttempt>? _ttsDiagResults;
  String? _testVoiceResult;
  late String _lastSyncedBaseUrl;
  late String _lastSyncedModel;
  late JarvisSettings _synced;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _baseUrlCtrl = TextEditingController(text: s.baseUrl);
    _apiKeyCtrl = TextEditingController(text: s.apiKey);
    _modelCtrl = TextEditingController(text: s.model);
    _personaCtrl = TextEditingController(text: s.personaPrompt);
    _azureKeyCtrl = TextEditingController(text: s.azureSpeechKey);
    _azureRegionCtrl = TextEditingController(text: s.azureSpeechRegion);
    _ttsProxyUrlCtrl = TextEditingController(text: s.ttsProxyUrl);
    _geminiTtsKeyCtrl = TextEditingController(text: s.geminiTtsKey);
    _googleCloudTtsKeyCtrl = TextEditingController(text: s.googleCloudTtsKey);
    _openAiTtsKeyCtrl = TextEditingController(text: s.openAiTtsKey);
    _whisperKeyCtrl = TextEditingController(text: s.whisperKey);
    _whisperBaseCtrl = TextEditingController(text: s.whisperBaseUrl);
    _lastSyncedBaseUrl = s.baseUrl;
    _lastSyncedModel = s.model;
    _synced = s;
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final s = widget.controller.settings;
    if (!identical(s, _synced)) {
      // Keep text fields in sync with changes made elsewhere (e.g. keys
      // imported from the PC), so a later "Kaydet" never overwrites them.
      void sync(TextEditingController ctrl, String Function(JarvisSettings) f) {
        if (f(s) != f(_synced)) ctrl.text = f(s);
      }

      sync(_apiKeyCtrl, (x) => x.apiKey);
      sync(_personaCtrl, (x) => x.personaPrompt);
      sync(_azureKeyCtrl, (x) => x.azureSpeechKey);
      sync(_azureRegionCtrl, (x) => x.azureSpeechRegion);
      sync(_ttsProxyUrlCtrl, (x) => x.ttsProxyUrl);
      sync(_geminiTtsKeyCtrl, (x) => x.geminiTtsKey);
      sync(_googleCloudTtsKeyCtrl, (x) => x.googleCloudTtsKey);
      sync(_openAiTtsKeyCtrl, (x) => x.openAiTtsKey);
      sync(_whisperKeyCtrl, (x) => x.whisperKey);
      sync(_whisperBaseCtrl, (x) => x.whisperBaseUrl);
      _synced = s;
    }
    if (s.model != _lastSyncedModel) {
      _lastSyncedModel = s.model;
      _modelCtrl.text = s.model;
    }
    if (s.baseUrl != _lastSyncedBaseUrl) {
      _lastSyncedBaseUrl = s.baseUrl;
      _baseUrlCtrl.text = s.baseUrl;
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _personaCtrl.dispose();
    _azureKeyCtrl.dispose();
    _azureRegionCtrl.dispose();
    _ttsProxyUrlCtrl.dispose();
    _geminiTtsKeyCtrl.dispose();
    _googleCloudTtsKeyCtrl.dispose();
    _openAiTtsKeyCtrl.dispose();
    _whisperKeyCtrl.dispose();
    _whisperBaseCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveTextSettings({bool showToast = true}) async {
    final c = widget.controller;
    final nextBaseUrl = _baseUrlCtrl.text.trim();
    final nextModel = _modelCtrl.text.trim().isEmpty
        ? 'gemini-2.5-flash'
        : _modelCtrl.text.trim();
    final nextRegion = _azureRegionCtrl.text.trim().isEmpty
        ? 'westeurope'
        : _azureRegionCtrl.text.trim();
    final nextTtsProxyUrl = _ttsProxyUrlCtrl.text.trim().isEmpty
        ? 'http://127.0.0.1:8317'
        : _ttsProxyUrlCtrl.text.trim();
    _lastSyncedBaseUrl = nextBaseUrl;
    _lastSyncedModel = nextModel;
    await c.updateSettings(
      c.settings.copyWith(
        baseUrl: nextBaseUrl,
        apiKey: _apiKeyCtrl.text.trim(),
        model: nextModel,
        azureSpeechKey: _azureKeyCtrl.text.trim(),
        azureSpeechRegion: nextRegion,
        ttsProxyUrl: nextTtsProxyUrl,
        geminiTtsKey: _geminiTtsKeyCtrl.text.trim(),
        googleCloudTtsKey: _googleCloudTtsKeyCtrl.text.trim(),
        openAiTtsKey: _openAiTtsKeyCtrl.text.trim(),
        whisperKey: _whisperKeyCtrl.text.trim(),
        whisperBaseUrl: _whisperBaseCtrl.text.trim().isEmpty
            ? 'https://api.openai.com/v1'
            : _whisperBaseCtrl.text.trim(),
        personaPrompt: _personaCtrl.text.trim().isEmpty
            ? const JarvisSettings().personaPrompt
            : _personaCtrl.text.trim(),
      ),
    );
    if (showToast && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ayarlar cihaza kaydedildi')),
      );
    }
  }

  Widget _buildLookCard() {
    final c = widget.controller;
    return _SettingsCard(
      key: const Key('settings_look_card'),
      glow: ChatPalette.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: ChatPalette.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Görünüm ve Animasyonlar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppearanceSettings(controller: c),
          SwitchListTile(
            key: const Key('settings_ui_effects'),
            contentPadding: EdgeInsets.zero,
            value: c.settings.uiEffects,
            onChanged: (v) =>
                c.updateSettings(c.settings.copyWith(uiEffects: v)),
            title: const Text('Arayüz efektleri'),
            subtitle: const Text(
              'Hareketli holografik arka plan, parıltılar ve çekirdek animasyonu. '
              'Pil tasarrufu için kapatabilirsin (telefonun "animasyonları kaldır" ayarına da uyar).',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Yazı boyutu',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'Telefonun yazı boyutu çok büyükse ekran sıkışır; Ege içinde bu sınır uygulanır.',
            style: TextStyle(fontSize: 12, color: ChatPalette.muted),
          ),
          const SizedBox(height: 6),
          SegmentedButton<double>(
            key: const Key('settings_text_scale'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 1.0, label: Text('Küçük')),
              ButtonSegment(value: 1.15, label: Text('Normal')),
              ButtonSegment(value: 1.3, label: Text('Büyük')),
              ButtonSegment(value: 2.0, label: Text('Sistem')),
            ],
            selected: {
              const [1.0, 1.15, 1.3, 2.0].reduce(
                (a, b) =>
                    (a - c.settings.textScaleMax).abs() <=
                        (b - c.settings.textScaleMax).abs()
                    ? a
                    : b,
              ),
            },
            onSelectionChanged: (v) =>
                c.updateSettings(c.settings.copyWith(textScaleMax: v.first)),
          ),
        ],
      ),
    );
  }

  Widget _buildStandaloneCard() {
    final c = widget.controller;
    final s = c.settings;
    final emb = EmbeddedKeys.instance;
    final standalone =
        s.provider != ApiProvider.cliProxyApi || !s.usesLoopbackProxy;
    return _SettingsCard(
      glow: ChatPalette.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android_rounded, color: ChatPalette.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Bağımsız Mod (PC gerekmez)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              StatusDot(ok: standalone && s.azureSpeechKey.isNotEmpty),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            emb.available
                ? 'Bu kurulumda CLI Proxy API\'den alınmış anahtarlar gömülü: sohbet Gemini ile, '
                      'HD sesler Azure ile doğrudan telefondan çalışır.'
                : 'Gömülü anahtar yok. PC Kod sekmesinden "API\'leri PC\'den Al" ya da anahtarları aşağıya girin.',
            style: TextStyle(
              fontSize: 12,
              color: ChatPalette.muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (emb.available)
                FilledButton.tonalIcon(
                  key: const Key('settings_apply_embedded_keys'),
                  onPressed: () async {
                    await c.updateSettings(
                      emb.applyTo(c.settings, force: true),
                    );
                    await c.refreshProxyModels(silent: true);
                    if (mounted) {
                      showJarvisSnack(context, 'Gömülü anahtarlar uygulandı');
                    }
                  },
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Anahtarları yeniden uygula'),
                ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MemoryScreen(controller: c),
                  ),
                ),
                icon: const Icon(Icons.psychology_alt_rounded, size: 18),
                label: Text('Hafıza (${c.memoryItems.length})'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DiagnosticsScreen(controller: c),
                  ),
                ),
                icon: const Icon(Icons.health_and_safety_rounded, size: 18),
                label: const Text('Sistem Tanı'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Bulut anahtarları silinsin mi?'),
                      content: const Text(
                        'Gemini, Azure, OpenAI ve PC proxy anahtarları telefondan silinir.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Vazgeç'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sil'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await c.updateSettings(
                    c.settings.copyWith(
                      geminiTtsKey: '',
                      azureSpeechKey: '',
                      openAiTtsKey: '',
                      ttsProxyKey: '',
                      apiKey: c.settings.provider == ApiProvider.geminiDirect
                          ? ''
                          : null,
                    ),
                  );
                  if (mounted) showJarvisSnack(context, 'Anahtarlar silindi');
                },
                icon: const Icon(Icons.key_off_rounded, size: 18),
                label: const Text('Anahtarları sil'),
              ),
            ],
          ),
          Divider(height: 22, color: ChatPalette.border),
          Row(
            children: [
              Icon(Icons.badge_rounded, size: 18, color: ChatPalette.accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Profiller',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final ctrl = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Profil olarak kaydet'),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Ör: Gece, İş, Araba',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('İptal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                          child: const Text('Kaydet'),
                        ),
                      ],
                    ),
                  );
                  ctrl.dispose();
                  if (name == null || name.isEmpty) return;
                  await c.saveProfile(name);
                  if (mounted) {
                    showJarvisSnack(context, '"$name" profili kaydedildi');
                  }
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Kaydet'),
              ),
            ],
          ),
          if (c.profiles.isEmpty)
            Text(
              'Model, ses, ton ve kişilik ayarlarını adlandırıp sesle geçiş yapın: "Gece profiline geç".',
              style: TextStyle(fontSize: 11.5, color: ChatPalette.muted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in c.profiles.keys)
                  InputChip(
                    label: Text(name),
                    onPressed: () async {
                      final msg = await c.applyProfile(name);
                      if (mounted) showJarvisSnack(context, msg);
                    },
                    onDeleted: () => c.deleteProfile(name),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPcVoiceCard() {
    final c = widget.controller;
    final s = c.settings;
    final cloudReady =
        s.azureSpeechKey.isNotEmpty ||
        s.geminiTtsKey.isNotEmpty ||
        s.openAiTtsKey.isNotEmpty ||
        (s.ttsProxyKey.isNotEmpty && !s.ttsProxyUrl.contains('127.0.0.1'));
    final voice = JarvisVoiceCatalog.find(s.proxyTtsVoice);
    return _SettingsCard(
      glow: ChatPalette.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.laptop_windows_rounded, color: ChatPalette.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.pcPaired
                      ? 'PC: ${s.pcBridgeName.isEmpty ? s.pcBridgeUrl : s.pcBridgeName}'
                      : 'PC Köprüsü bağlı değil',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              StatusDot(ok: s.pcPaired ? c.pcOnline : false),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            cloudReady
                ? 'Bulut sesler hazır • Ses: ${voice?.shortName ?? s.proxyTtsVoice} • Ton: ${JarvisVoiceCatalog.styleFor(s.ttsStyle).label}'
                : 'Bulut sesler için PC\'deki CLI Proxy API anahtarlarını alın.',
            style: TextStyle(
              fontSize: 12,
              color: cloudReady ? ChatPalette.accent : ChatPalette.accent,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!s.pcPaired)
                FilledButton.icon(
                  key: const Key('settings_pc_pair_button'),
                  onPressed: () => c.openTab(5),
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('PC\'ye Bağlan'),
                )
              else
                FilledButton.icon(
                  onPressed: _importing
                      ? null
                      : () async {
                          setState(() => _importing = true);
                          final res = await c.importKeysFromPc();
                          if (!mounted) return;
                          setState(() => _importing = false);
                          showJarvisSnack(
                            context,
                            res.ok
                                ? '${res.message}\n${res.items.join('\n')}'
                                : res.message,
                            error: !res.ok,
                          );
                        },
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.download_for_offline_rounded,
                          size: 18,
                        ),
                  label: const Text('API\'leri PC\'den Al'),
                ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VoiceStudioScreen(controller: c),
                  ),
                ),
                icon: const Icon(Icons.record_voice_over_rounded, size: 18),
                label: const Text('Bulut Ses Stüdyosu'),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Proxy\'ye ulaşılamazsa Gemini ile devam et',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: const Text(
              'PC kapalıyken bile sohbet çalışır (Gemini anahtarı gerekir).',
              style: TextStyle(fontSize: 11),
            ),
            value: s.autoFallbackGemini,
            onChanged: (v) =>
                c.updateSettings(s.copyWith(autoFallbackGemini: v)),
          ),
        ],
      ),
    );
  }

  void _applyPreset({
    required ApiProvider provider,
    required String baseUrl,
    required String model,
    String? apiKeyIfEmpty,
  }) {
    _baseUrlCtrl.text = baseUrl;
    _modelCtrl.text = model;
    _lastSyncedBaseUrl = baseUrl;
    _lastSyncedModel = model;
    var nextKey = _apiKeyCtrl.text.trim();
    if (nextKey.isEmpty && apiKeyIfEmpty != null) {
      nextKey = apiKeyIfEmpty;
      _apiKeyCtrl.text = apiKeyIfEmpty;
    }
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(
        provider: provider,
        baseUrl: baseUrl,
        model: model,
        apiKey: nextKey,
      ),
    );
  }

  Widget _section(
    String title,
    IconData icon,
    String subtitle,
    List<Widget> children,
  ) => Card(
    elevation: 0,
    color: ChatPalette.surface,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: ChatPalette.border),
    ),
    child: ExpansionTile(
      leading: Icon(icon, color: ChatPalette.accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: ChatPalette.muted),
      ),
      childrenPadding: const EdgeInsets.all(14),
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.settings;
    final seenModelIds = <String>{};
    final dropdownModels = <ProxyModelInfo>[];
    for (final m in c.proxyModels) {
      if (m.id.isNotEmpty && seenModelIds.add(m.id)) {
        dropdownModels.add(m);
      }
    }
    for (final id in c.availableModels) {
      if (id.isNotEmpty && seenModelIds.add(id)) {
        dropdownModels.add(ProxyModelInfo.classify(id));
      }
    }
    final typedModel = _modelCtrl.text.trim();
    if (typedModel.isNotEmpty && seenModelIds.add(typedModel)) {
      dropdownModels.add(ProxyModelInfo.classify(typedModel));
    }
    final selectedDropdownModel = seenModelIds.contains(typedModel)
        ? typedModel
        : (dropdownModels.isNotEmpty
              ? dropdownModels.first.id
              : 'gemini-2.5-flash');

    const voicePresets = JarvisVoiceCatalog.presets;
    final voiceIds = voicePresets.map((v) => v.id).toSet();
    final selectedVoice = voiceIds.contains(s.proxyTtsVoice)
        ? s.proxyTtsVoice
        : voicePresets.first.id;
    const validTtsEngines = {
      'auto',
      'edge_neural',
      'proxy',
      'azure',
      'gemini',
      'google_cloud',
      'openai',
      'device',
    };
    final selectedTtsEngine = validTtsEngines.contains(s.ttsEngine)
        ? s.ttsEngine
        : 'auto';
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Ege’yi kendine göre ayarla. Tüm tercihler tek yerde.',
                  style: TextStyle(color: ChatPalette.muted, height: 1.5),
                ),
              ),
              Card(
                elevation: 0,
                color: ChatPalette.surface,
                child: ListTile(
                  leading: Icon(Icons.apps_rounded, color: ChatPalette.accent),
                  title: const Text('Uygulama kontrolü'),
                  subtitle: const Text(
                    'Uygulamaları aç, düğmelere dokun ve alanları doldur',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppControlScreen()),
                  ),
                ),
              ),
              _section(
                'Bağlı hesaplar',
                Icons.account_circle_outlined,
                'Google, Microsoft, e-posta, takvim ve Office',
                [
                  AccountConnections(
                    google: c.googleWorkspace,
                    microsoft: c.microsoftWorkspace,
                  ),
                ],
              ),
              _section(
                'İndirmeler',
                Icons.download_outlined,
                'Wi-Fi, kuyruk ve hız sınırı',
                [const DownloadSettings()],
              ),
              _section(
                'Canlı ses',
                Icons.graphic_eq_rounded,
                'Ege’yin kendi konuşma modu',
                [
                  const Text(
                    'Telefon STT → seçili sohbet modeli → Seslendirme bölümünde seçtiğin ses. Azure, Chirp ve diğer sesler canlı modda da kullanılır. Ayrı bir Live API bağlantısı gerekmez.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  const Text('Konuşma hızı'),
                  Slider(
                    value: s.ttsRate.clamp(0.2, 0.8),
                    min: 0.2,
                    max: 0.8,
                    onChanged: (v) =>
                        c.updateSettings(c.settings.copyWith(ttsRate: v)),
                  ),
                  Text(
                    'Konuşma tanıma önce Android yerel STT ile yapılır. Türkçe model kurulu değilse kayıt Gemini ile çözümlenir (internet gerekir). Whisper kapalıdır.',
                    style: TextStyle(color: ChatPalette.muted),
                  ),
                ],
              ),

              _section(
                'Konuşmayı yazıya çevir',
                Icons.mic_none_rounded,
                'Android yerel konuşma tanıma',
                [
                  const ListTile(
                    leading: Icon(Icons.phone_android),
                    title: Text('Android yerel STT'),
                    subtitle: Text(
                      'Önce telefonun yerel konuşma tanıması denenir; Türkçe model yoksa Gemini çözümler. Whisper kapalıdır. Modeli indirmek için aşağıdaki düğmeyi kullan (Wi-Fi gerekebilir).',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.record_voice_over),
                    title: const Text('Yalnızca benim sesim'),
                    subtitle: const Text(
                      'Ses profilini kaydet ve diğer sesleri filtrele',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SpeakerProfileScreen(controller: c),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => DeviceBridge.preparePhoneSpeech(force: true),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Android Türkçe dil desteğini hazırla'),
                  ),
                ],
              ),
              _section(
                'Bağlantı ve modeller',
                Icons.hub_outlined,
                'Sağlayıcı, model ve API anahtarları',
                [
                  Text(
                    'AI Sağlayıcı',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: ChatPalette.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ApiProvider>(
                    segments: const [
                      ButtonSegment(
                        value: ApiProvider.cliProxyApi,
                        icon: Icon(Icons.dns_rounded),
                        label: Text('CLI Proxy'),
                      ),
                      ButtonSegment(
                        value: ApiProvider.geminiDirect,
                        icon: Icon(Icons.auto_awesome_rounded),
                        label: Text('Gemini'),
                      ),
                      ButtonSegment(
                        value: ApiProvider.openAiCompatible,
                        icon: Icon(Icons.hub_outlined),
                        label: Text('OpenAI'),
                      ),
                    ],
                    selected: {s.provider},
                    onSelectionChanged: (sel) {
                      final chosen = sel.first;
                      final nextUrl = switch (chosen) {
                        ApiProvider.cliProxyApi => 'http://127.0.0.1:8317',
                        ApiProvider.geminiDirect =>
                          'https://generativelanguage.googleapis.com',
                        ApiProvider.openAiCompatible =>
                          'https://api.openai.com',
                      };
                      final nextModel = switch (chosen) {
                        ApiProvider.cliProxyApi => 'gemini-2.5-flash',
                        ApiProvider.geminiDirect => 'gemini-2.5-flash',
                        ApiProvider.openAiCompatible => 'gpt-4o-mini',
                      };
                      var nextKey = _apiKeyCtrl.text.trim();
                      if (chosen == ApiProvider.cliProxyApi &&
                          nextKey.isEmpty) {
                        nextKey = 'sk-local';
                        _apiKeyCtrl.text = 'sk-local';
                      }
                      _baseUrlCtrl.text = nextUrl;
                      _modelCtrl.text = nextModel;
                      _lastSyncedBaseUrl = nextUrl;
                      _lastSyncedModel = nextModel;
                      c.updateSettings(
                        s.copyWith(
                          provider: chosen,
                          baseUrl: nextUrl,
                          model: nextModel,
                          apiKey: nextKey,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(
                          Icons.phone_android_rounded,
                          size: 16,
                        ),
                        label: const Text('Telefon CLI Proxy (127.0.0.1:8317)'),
                        onPressed: () => _applyPreset(
                          provider: ApiProvider.cliProxyApi,
                          baseUrl: 'http://127.0.0.1:8317',
                          model: 'gemini-2.5-flash',
                          apiKeyIfEmpty: 'sk-local',
                        ),
                      ),
                      if (s.ttsProxyUrl.trim().isNotEmpty &&
                          !s.ttsProxyUrl.contains('127.0.0.1') &&
                          s.ttsProxyKey.trim().isNotEmpty)
                        ActionChip(
                          avatar: const Icon(
                            Icons.laptop_windows_rounded,
                            size: 16,
                          ),
                          label: Text(
                            'PC CLI Proxy (${Uri.tryParse(s.ttsProxyUrl)?.host ?? 'PC'})',
                          ),
                          onPressed: () {
                            _apiKeyCtrl.text = s.ttsProxyKey;
                            _applyPreset(
                              provider: ApiProvider.cliProxyApi,
                              baseUrl: s.ttsProxyUrl,
                              model:
                                  s.model.startsWith('gemini') ||
                                      s.model.startsWith('claude') ||
                                      s.model.startsWith('gpt')
                                  ? s.model
                                  : 'gemini-2.5-flash',
                            );
                          },
                        ),
                      ActionChip(
                        label: const Text('Google Gemini'),
                        onPressed: () => _applyPreset(
                          provider: ApiProvider.geminiDirect,
                          baseUrl: 'https://generativelanguage.googleapis.com',
                          model: 'gemini-2.5-flash',
                        ),
                      ),
                      ActionChip(
                        label: const Text('OpenAI'),
                        onPressed: () => _applyPreset(
                          provider: ApiProvider.openAiCompatible,
                          baseUrl: 'https://api.openai.com',
                          model: 'gpt-4o-mini',
                        ),
                      ),
                      ActionChip(
                        label: const Text('Groq'),
                        onPressed: () => _applyPreset(
                          provider: ApiProvider.openAiCompatible,
                          baseUrl: 'https://api.groq.com/openai',
                          model: 'llama-3.3-70b-versatile',
                        ),
                      ),
                      ActionChip(
                        label: const Text('OpenRouter'),
                        onPressed: () => _applyPreset(
                          provider: ApiProvider.openAiCompatible,
                          baseUrl: 'https://openrouter.ai/api',
                          model: 'google/gemini-2.5-flash',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _baseUrlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'API Temel Adresi (Base URL)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'API Anahtarı',
                      hintText: 'AIza... veya sk-...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Model Adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (dropdownModels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('model_dd_$selectedDropdownModel'),
                      initialValue: selectedDropdownModel,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText:
                            'Proxy / Bulunan Modeller (${dropdownModels.length} model)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final m in dropdownModels)
                          DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              '${m.id}  •  ${m.categoryLabel}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          _modelCtrl.text = val;
                          _saveTextSettings(showToast: false);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => showModelPickerSheet(context, c),
                        icon: const Icon(Icons.apps_rounded, size: 18),
                        label: Text(
                          'Tüm Modelleri Kategorili Seç (${c.proxyModels.length})',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _saveTextSettings(),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Kaydet'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: c.testingConnection
                              ? null
                              : () async {
                                  await _saveTextSettings(showToast: false);
                                  await c.testConnection();
                                },
                          icon: c.testingConnection
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering_rounded),
                          label: const Text('Modelleri Çek & Test Et'),
                        ),
                      ),
                    ],
                  ),
                  if (c.connectionStatusMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            (c.connectionOk == true
                                    ? ChatPalette.soft
                                    : ChatPalette.soft)
                                .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: c.connectionOk == true
                              ? ChatPalette.accent
                              : ChatPalette.accent,
                        ),
                      ),
                      child: Text(
                        c.connectionStatusMessage!,
                        style: const TextStyle(fontSize: 12.8),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Canlı Akış (Streaming)'),
                    subtitle: const Text(
                      'Yanıtları kelime kelime akıtır. Bazı modeller akışta hata verirse otomatik olarak tek-yanıt moduna geçer.',
                    ),
                    value: s.preferStreaming,
                    onChanged: (v) =>
                        c.updateSettings(s.copyWith(preferStreaming: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ajan Web & Telefon Araçları'),
                    subtitle: const Text(
                      'Yapay zekânın güncel web araması, sayfa okuma, hava durumu, döviz, haber, Wikipedia, konum ve uygulama listesini araç olarak çağırmasına izin verir.',
                    ),
                    value: s.agentTools,
                    onChanged: (v) =>
                        c.updateSettings(s.copyWith(agentTools: v)),
                  ),
                  if (s.provider == ApiProvider.geminiDirect) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Google Arama Desteği (Grounding)'),
                      subtitle: const Text(
                        'Güncel web bilgisi gerektiren sorularda Gemini Google Arama aracını kullanır',
                      ),
                      value: s.googleGrounding,
                      onChanged: (v) =>
                          c.updateSettings(s.copyWith(googleGrounding: v)),
                    ),
                  ],
                  Divider(height: 28, color: ChatPalette.border),
                ],
              ),
              _section(
                'Seslendirme',
                Icons.volume_up_outlined,
                'Okuma sesi, hız ve ses servisleri',
                [
                  Text(
                    'Sesli Okuma & Konuşma Tanıma (Azure / Google Chirp 3 HD)',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: ChatPalette.accent,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Yanıtları Otomatik Seslendir'),
                    subtitle: const Text(
                      'Sohbet sekmesinde gelen cevapları sesli okur',
                    ),
                    value: s.autoTts,
                    onChanged: (v) => c.updateSettings(s.copyWith(autoTts: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Azure / Google Chirp 3 HD TTS Kullan'),
                    subtitle: const Text(
                      'Etkinleştirildiğinde Edge Neural, CLI Proxy, Azure, Google Chirp 3 HD ve OpenAI bulut seslerini kullanır; yerel robotik sese düşmez',
                    ),
                    value: s.useProxyTts,
                    onChanged: (v) => c.updateSettings(
                      s.copyWith(
                        useProxyTts: v,
                        ttsEngine: v
                            ? (s.ttsEngine == 'device' ? 'auto' : s.ttsEngine)
                            : 'device',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: ValueKey('tts_engine_dd_$selectedTtsEngine'),
                    initialValue: selectedTtsEngine,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Bulut Ses Motoru (TTS)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text(
                          'Otomatik (Edge Neural + Proxy + Chirp / Azure)',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'edge_neural',
                        child: Text(
                          'Edge Neural Doğrudan (Ahmet / Emel • Anahtarsız)',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'proxy',
                        child: Text(
                          'CLI Proxy (Chirp 3 HD & Edge/Azure Neural)',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'azure',
                        child: Text('Azure Speech Neural / MAI-Voice'),
                      ),
                      DropdownMenuItem(
                        value: 'gemini',
                        child: Text('Gemini API Doğrudan (Chirp 3 HD)'),
                      ),
                      DropdownMenuItem(
                        value: 'google_cloud',
                        child: Text('Google Cloud TTS API (Chirp 3 HD)'),
                      ),
                      DropdownMenuItem(
                        value: 'openai',
                        child: Text(
                          'OpenAI /v1/audio/speech (gpt-4o-mini-tts)',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'device',
                        child: Text('Yalnızca Cihaz İçi Android TTS'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        c.updateSettings(
                          s.copyWith(
                            ttsEngine: val,
                            useProxyTts: val == 'device' ? false : true,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  if (s.useProxyTts || s.azureSpeechKey.trim().isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('voice_dd_$selectedVoice'),
                      initialValue: selectedVoice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText:
                            'TTS Sesi (Azure Neural & Google Chirp 3 HD)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final v in voicePresets)
                          DropdownMenuItem(value: v.id, child: Text(v.label)),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          c.updateSettings(s.copyWith(proxyTtsVoice: val));
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 10),

                  const SizedBox(height: 10),

                  const SizedBox(height: 10),
                  TextField(
                    controller: _azureKeyCtrl,
                    obscureText: _obscureAzureKey,
                    decoration: InputDecoration(
                      labelText: 'Azure Speech API Anahtarı (bulut sesler)',
                      hintText: 'İsteğe bağlı (doğrudan Azure Neural/MAI sesler için)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscureAzureKey = !_obscureAzureKey,
                        ),
                        icon: Icon(
                          _obscureAzureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _saveTextSettings(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _azureRegionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Azure Speech Bölgesi',
                      hintText: 'Örn: westeurope, eastus, germanywestcentral',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _saveTextSettings(),
                  ),
                  const SizedBox(height: 8),
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Gelişmiş Bulut TTS Anahtarları & Proxy Adresi',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Özel CLI Proxy adresi, Gemini Chirp, Google Cloud TTS ve OpenAI TTS anahtarları',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ChatPalette.muted,
                        ),
                      ),
                      children: [
                        const SizedBox(height: 6),
                        TextField(
                          controller: _ttsProxyUrlCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'Ayrı TTS CLI Proxy Adresi (İsteğe bağlı)',
                            hintText: 'http://127.0.0.1:8317',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _saveTextSettings(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _geminiTtsKeyCtrl,
                          obscureText: _obscureGeminiTtsKey,
                          decoration: InputDecoration(
                            labelText:
                                'Gemini TTS API Anahtarı (AI Studio - AIza...)',
                            hintText: 'Chirp 3 HD / Kore / Aoede doğrudan ses sentezi için',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscureGeminiTtsKey =
                                    !_obscureGeminiTtsKey,
                              ),
                              icon: Icon(
                                _obscureGeminiTtsKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _saveTextSettings(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _googleCloudTtsKeyCtrl,
                          obscureText: _obscureGoogleCloudTtsKey,
                          decoration: InputDecoration(
                            labelText:
                                'Google Cloud Text-to-Speech API Anahtarı',
                            hintText: 'Google Cloud Chirp 3 HD REST API için',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscureGoogleCloudTtsKey =
                                    !_obscureGoogleCloudTtsKey,
                              ),
                              icon: Icon(
                                _obscureGoogleCloudTtsKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _saveTextSettings(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _openAiTtsKeyCtrl,
                          obscureText: _obscureOpenAiTtsKey,
                          decoration: InputDecoration(
                            labelText: 'OpenAI TTS API Anahtarı (sk-...)',
                            hintText:
                                'Doğrudan OpenAI gpt-4o-mini-tts / tts-1 için',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscureOpenAiTtsKey =
                                    !_obscureOpenAiTtsKey,
                              ),
                              icon: Icon(
                                _obscureOpenAiTtsKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _saveTextSettings(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 72, child: Text('Hız')),
                      Expanded(
                        child: Slider(
                          min: 0.3,
                          max: 0.9,
                          divisions: 12,
                          value: s.ttsRate.clamp(0.3, 0.9),
                          onChanged: (v) =>
                              c.updateSettings(s.copyWith(ttsRate: v)),
                        ),
                      ),
                      Text(s.ttsRate.toStringAsFixed(2)),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 72, child: Text('Ton')),
                      Expanded(
                        child: Slider(
                          min: 0.7,
                          max: 1.4,
                          divisions: 14,
                          value: s.ttsPitch.clamp(0.7, 1.4),
                          onChanged: (v) =>
                              c.updateSettings(s.copyWith(ttsPitch: v)),
                        ),
                      ),
                      Text(s.ttsPitch.toStringAsFixed(2)),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await _saveTextSettings(showToast: false);
                          final engine = await c.testVoice();
                          if (!mounted) return;
                          setState(() => _testVoiceResult = engine);
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text('🔊 Kullanılan motor: $engine'),
                              ),
                            );
                        },
                        icon: const Icon(Icons.volume_up_outlined),
                        label: const Text('Sesi Test Et'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _diagnosingTts
                            ? null
                            : () async {
                                await _saveTextSettings(showToast: false);
                                setState(() => _diagnosingTts = true);
                                final results = await c.diagnoseTts();
                                if (!mounted) return;
                                setState(() {
                                  _diagnosingTts = false;
                                  _ttsDiagResults = results;
                                });
                              },
                        icon: _diagnosingTts
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.monitor_heart_outlined),
                        label: const Text('Bulut Seslerini Tanıla'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _saveTextSettings,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Seslendirmeyi Kaydet'),
                      ),
                    ],
                  ),
                  if (_testVoiceResult != null ||
                      c.lastTtsEngine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: ChatPalette.soft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ChatPalette.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aktif / Son TTS Motoru: ${_testVoiceResult ?? c.lastTtsEngine}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: ChatPalette.accent,
                            ),
                          ),
                          if (c.lastTtsAttempts.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            for (final a in c.lastTtsAttempts)
                              Text(
                                a.toString(),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: ChatPalette.muted,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (_ttsDiagResults != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: ChatPalette.soft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: ChatPalette.accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bulut TTS Tanılama Sonuçları',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: ChatPalette.accent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_ttsDiagResults!.isEmpty)
                            Text(
                              'Hiçbir bulut TTS motoru yapılandırılmamış. CLI Proxy adresini veya Azure / Gemini / Google Cloud / OpenAI anahtarını girin.',
                              style: TextStyle(
                                fontSize: 12,
                                color: ChatPalette.muted,
                              ),
                            )
                          else
                            for (final r in _ttsDiagResults!)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  r.toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: r.ok
                                        ? ChatPalette.accent
                                        : ChatPalette.accent,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                  Divider(height: 28, color: ChatPalette.border),
                ],
              ),
              _section(
                'Görünüm ve telefon',
                Icons.phone_android_outlined,
                'Görünüm, izinler ve asistan kurulumu',
                [
                  _buildLookCard(),
                  AssistantSetupCard(controller: c),
                  _buildStandaloneCard(),
                  _buildPcVoiceCard(),
                ],
              ),
              _section(
                'Kişilik',
                Icons.auto_awesome_outlined,
                'Asistanın yanıt verme biçimi',
                [
                  Text(
                    'Ege Kişiliği (Sistem Yönergesi)',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: ChatPalette.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _personaCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          const def = JarvisSettings();
                          _personaCtrl.text = def.personaPrompt;
                          _saveTextSettings(showToast: true);
                        },
                        child: const Text('Varsayılana Sıfırla'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _saveTextSettings,
                        child: const Text('Yönergeyi Kaydet'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveTextSettings,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Ayarları Kaydet'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;
  final Color? glow;
  final EdgeInsetsGeometry padding = const EdgeInsets.all(12);
  const _SettingsCard({super.key, required this.child, this.glow});
  @override
  Widget build(BuildContext context) => Material(
    color: ChatPalette.soft,
    borderRadius: BorderRadius.circular(14),
    child: Padding(padding: padding, child: child),
  );
}
