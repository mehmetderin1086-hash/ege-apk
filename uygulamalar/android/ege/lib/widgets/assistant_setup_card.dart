import 'package:flutter/material.dart';

import '../services/device_bridge.dart';
import '../screens/wake_tune_screen.dart';
import '../services/wake_word.dart';
import '../state/jarvis_controller.dart';
import 'jarvis_ui.dart';
import 'wake_diagnostic_dialog.dart';
import 'chat_palette.dart';
import '../services/wake_verifier.dart';

/// Ayarlar → "Asistan ve Arka Plan" (Ege 3.0): varsayılan asistan, pil
/// kısıtlaması, bildirim erişimi, araya girme, sabah özeti, uyandırma.
class AssistantSetupCard extends StatefulWidget {
  const AssistantSetupCard({super.key, required this.controller});

  final JarvisController controller;

  @override
  State<AssistantSetupCard> createState() => _AssistantSetupCardState();
}

class _AssistantSetupCardState extends State<AssistantSetupCard>
    with WidgetsBindingObserver {
  bool? _isAssistant;
  bool? _batteryFree;
  bool? _notifAccess;
  bool? _callControl;
  late final TextEditingController _cityCtrl;

  JarvisController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cityCtrl = TextEditingController(text: c.settings.briefingCity);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cityCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kullanıcı ayarlardan dönünce durumu tazele.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final r = await Future.wait([
      DeviceBridge.isDefaultAssistant(),
      DeviceBridge.batteryOptimizationIgnored(),
      DeviceBridge.notificationAccessGranted(),
      DeviceBridge.callControlPermission(),
    ]);
    if (!mounted) return;
    setState(() {
      _isAssistant = r[0];
      _batteryFree = r[1];
      _notifAccess = r[2];
      _callControl = r[3];
    });
  }

  Widget _status(
    String label,
    bool? ok,
    String okText,
    String badText,
    VoidCallback onFix,
    String fixText,
  ) {
    final color = ok == null ? JColors.muted : (ok ? JColors.ok : JColors.warn);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            ok == true
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ok == null ? '…' : (ok ? okText : badText),
                    style: TextStyle(color: color),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (ok != true) TextButton(onPressed: onFix, child: Text(fixText)),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final p = c.settings.briefingTime.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(p.first) ?? 7,
        minute: p.length > 1 ? int.tryParse(p[1]) ?? 30 : 30,
      ),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (t == null) return;
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    await c.updateSettings(c.settings.copyWith(briefingTime: hm));
  }

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    return GlassCard(
      key: const Key('settings_assistant_card'),
      glow: JColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assistant_rounded, color: JColors.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Asistan ve Arka Plan',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _status(
            'Varsayılan asistan',
            _isAssistant,
            'Ege (ana tuşa uzun bas)',
            'değil',
            () async {
              await DeviceBridge.requestDefaultAssistant();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '"Dijital asistan uygulaması" → Ege seç. "Ekran görüntüsünü kullan" açık kalsın '
                    '(ekranda ne var? soruları için).',
                  ),
                  duration: Duration(seconds: 6),
                ),
              );
            },
            'Yap',
          ),
          _status(
            'Pil kısıtlaması',
            _batteryFree,
            'yok (arka planda çalışır)',
            'var (realme dondurabilir)',
            () => DeviceBridge.requestIgnoreBatteryOptimization(),
            'Kaldır',
          ),
          _status('Bildirim erişimi', _notifAccess, 'var', 'yok', () async {
            await DeviceBridge.openNotificationAccessSettings();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Ege gri görünüyorsa: Ayarlar → Uygulamalar → Ege → ⋮ → "Kısıtlanmış ayarlara izin ver", sonra tekrar dene.',
                ),
                duration: Duration(seconds: 7),
              ),
            );
          }, 'Ver'),
          SwitchListTile(
            key: const Key('settings_announce_notifications'),
            contentPadding: EdgeInsets.zero,
            value: s.announceNotifications,
            onChanged: (v) =>
                c.updateSettings(c.settings.copyWith(announceNotifications: v)),
            title: const Text('Gelen mesajları sesli oku'),
            subtitle: const Text(
              'WhatsApp, Telegram, SMS… ("Bildirimleri oku" komutu her zaman çalışır)',
              style: TextStyle(fontSize: 12),
            ),
          ),
          _status(
            'Aramayı sonlandırma',
            _callControl,
            'izin hazır',
            'telefon izni gerekli',
            () async {
              final result = await DeviceBridge.requestCallControlPermission();
              await _refresh();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result == 'READY'
                        ? '“Aramayı kapat” komutu hazır.'
                        : result == 'PERMISSION_NEEDED'
                        ? 'Telefon izinlerini tamamlayıp “Aramayı kapat” diyebilirsin.'
                        : 'Bu cihazda doğrudan kapatma desteklenmiyor; çağrı ekranını kullan.',
                  ),
                ),
              );
            },
            'İzin ver',
          ),
          SwitchListTile(
            key: const Key('settings_live_barge_in'),
            contentPadding: EdgeInsets.zero,
            value: s.liveBargeIn,
            onChanged: (v) =>
                c.updateSettings(c.settings.copyWith(liveBargeIn: v)),
            title: const Text('Canlı Ses\'te sesle sözünü kes'),
            subtitle: const Text(
              'Kapalıyken Ege konuşurken mikrofon susar, hoparlör yankısı yüzünden kendi sözünü kesmez. '
              'Açıkken yüksek sesle konuşarak araya girebilirsin (kulaklıkla önerilir).',
              style: TextStyle(fontSize: 12),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.keepAliveService,
            onChanged: (v) =>
                c.updateSettings(c.settings.copyWith(keepAliveService: v)),
            title: const Text('Canlı Ses sürerken arka plan servisi'),
            subtitle: const Text(
              'Ekran kapansa da konuşma kesilmez (bildirimde "Durdur").',
              style: TextStyle(fontSize: 12),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.assistantAutoListen,
            onChanged: (v) =>
                c.updateSettings(c.settings.copyWith(assistantAutoListen: v)),
            title: const Text('Asistan hareketiyle hemen dinle'),
            subtitle: const Text(
              'Ana tuşa uzun basma, hızlı ayar kutucuğu ve "Konuş" kısayolu.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (WakeWordEngine.supported)
            SwitchListTile(
              key: const Key('settings_wake_word'),
              contentPadding: EdgeInsets.zero,
              value: s.wakeWordEnabled,
              onChanged: (v) =>
                  c.updateSettings(c.settings.copyWith(wakeWordEnabled: v)),
              title: const Text('"Asistan" ile uyandır'),
              subtitle: Text(
                c.wakeWordActive
                    ? 'Dinliyor (bildirimde görünür). Pil tüketimi artar.'
                    : (c.wakeWordError ??
                          (s.wakeWordEnabled
                              ? 'Şu anda dinlemiyor. Canlı görüşme bittikten sonra yeniden başlar.'
                              : 'Kapalı. Açıldığında cihazda dinler; ses dışarı gitmez.')),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (s.wakeWordEnabled)
            TextButton.icon(
              onPressed: () async {
                final info = await DeviceBridge.wakeWordInfo();
                if (!context.mounted) return;
                final message = info['silenced'] == true
                    ? 'Android mikrofonu başka bir kayıt/görüşme nedeniyle sessize aldı. Görüşme bitince dinleme devam eder.'
                    : 'Motor: ${info['active'] == true ? "açık" : "kapalı"} • Ses paketleri: ${info['pcmFrames'] ?? 0} • İşlenen örnek: ${info['decodedSamples'] ?? 0} • Algılama: ${info['hits'] ?? 0}';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    duration: const Duration(seconds: 8),
                  ),
                );
              },
              icon: const Icon(Icons.graphic_eq),
              label: const Text('Uyandırma durumunu kontrol et'),
            ),
          if (s.wakeWordEnabled && !c.wakeWordActive)
            TextButton.icon(
              onPressed: () async {
                final error = await c.startWakeWord();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error ??
                          (c.wakeWordActive
                              ? 'Asistan dinlemesi başladı.'
                              : 'Mikrofon canlı görüşmede kullanılıyor.'),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Uyandırmayı yeniden başlat'),
            ),
          if (s.wakeWordEnabled)
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const WakeDiagnosticDialog(),
              ),
              icon: const Icon(Icons.hearing),
              label: const Text('Asistan tanılaması'),
            ),
          if (s.wakeWordEnabled)
            TextButton.icon(
              key: const Key('settings_wake_tune'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WakeTuneScreen(controller: c),
                ),
              ),
              icon: const Icon(Icons.record_voice_over_rounded),
              label: const Text('Asistan sözcüğünü sesime göre ayarla'),
            ),
          if (s.wakeWordEnabled) const WakeCloudVerifyTile(),
          Divider(height: 22, color: ChatPalette.border),
          SwitchListTile(
            key: const Key('settings_briefing'),
            contentPadding: EdgeInsets.zero,
            value: s.briefingEnabled,
            onChanged: (v) =>
                c.updateSettings(c.settings.copyWith(briefingEnabled: v)),
            title: const Text('Sabah özeti'),
            subtitle: const Text(
              'Hava, bugünkü hatırlatıcılar ve gündem; bildirime dokununca sesli okunur. "Günaydın" demen de yeter.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(s.briefingTime),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Şehir (boşsa konum)',
                    isDense: true,
                  ),
                  onSubmitted: (v) => c.updateSettings(
                    c.settings.copyWith(briefingCity: v.trim()),
                  ),
                  onTapOutside: (_) {
                    if (_cityCtrl.text.trim() != c.settings.briefingCity) {
                      c.updateSettings(
                        c.settings.copyWith(
                          briefingCity: _cityCtrl.text.trim(),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => c.briefingToChat(speak: true),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Şimdi dinle'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'İpuçları: Bildirim panelindeki kalem simgesinden "Ege" kutucuğunu ekleyebilirsin. '
            'Herhangi bir uygulamada metni seçip "Ege\'ye sor" diyebilir, paylaş menüsünden Ege\'ye gönderebilirsin. '
            'Uygulama simgesine uzun basınca "Konuş" ve "Sabah özeti" kısayolları çıkar.',
            style: TextStyle(fontSize: 12, color: JColors.muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// "Asistan"yi isabet anında bulutta doğrulama anahtarı.
class WakeCloudVerifyTile extends StatefulWidget {
  const WakeCloudVerifyTile({super.key});

  @override
  State<WakeCloudVerifyTile> createState() => _WakeCloudVerifyTileState();
}

class _WakeCloudVerifyTileState extends State<WakeCloudVerifyTile> {
  bool? on;

  @override
  void initState() {
    super.initState();
    WakeVerifier.enabled().then((v) {
      if (mounted) setState(() => on = v);
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const Key('settings_wake_cloud_verify'),
    contentPadding: EdgeInsets.zero,
    value: on ?? false,
    onChanged: on == null
        ? null
        : (v) async {
            await WakeVerifier.setEnabled(v);
            if (mounted) setState(() => on = v);
          },
    title: const Text('Asistan sözcüğünü bulutta doğrula'),
    subtitle: const Text(
      'Yalnız telefon “Asistan” duyduğunda o ~2 saniyelik ses Gemini ile '
      'kontrol edilir; “Hey Engin”, “hediye” gibi yanlış uyanmaları önler. '
      'İnternet yoksa telefonun kararı geçerli olur.',
    ),
  );
}
