import 'package:flutter/material.dart';

import '../services/asistan_controller.dart';
import 'theme_asistan.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key, required this.controller});

  final AsistanController controller;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  late final TextEditingController _proxyUrlCtrl;
  late final TextEditingController _proxyKeyCtrl;
  late final TextEditingController _geminiKeyCtrl;
  final TextEditingController _memoryCtrl = TextEditingController();
  final TextEditingController _reminderCtrl = TextEditingController();
  final TextEditingController _mcpNameCtrl = TextEditingController();
  final TextEditingController _mcpUrlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _proxyUrlCtrl = TextEditingController(
      text: widget.controller.engine.baseUrl,
    );
    _proxyKeyCtrl = TextEditingController(
      text: widget.controller.engine.apiKey,
    );
    _geminiKeyCtrl = TextEditingController(
      text: widget.controller.engine.geminiDirectApiKey,
    );
    widget.controller.refreshDeviceStatus();
  }

  @override
  void dispose() {
    _proxyUrlCtrl.dispose();
    _proxyKeyCtrl.dispose();
    _geminiKeyCtrl.dispose();
    _memoryCtrl.dispose();
    _reminderCtrl.dispose();
    _mcpNameCtrl.dispose();
    _mcpUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final preset = c.themePreset;
    final dev = c.deviceStatus;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // 1. Background Service & Digital Assistant Card
          GlassCard3D(
            borderColor: preset.primary.withValues(alpha: 0.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_rounded, color: preset.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Kesintisiz Arka Plan & Sistem Asistanı',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.backgroundServiceEnabled
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        c.backgroundServiceEnabled ? 'AKTİF' : 'KAPALI',
                        style: TextStyle(
                          color: c.backgroundServiceEnabled
                              ? const Color(0xFF34D399)
                              : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: preset.primary,
                  title: const Text(
                    'Arka Planda Kesintisiz Çalışma (WakeLock + Bildirim)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: const Text(
                    'Ekran kapalıyken veya başka uygulamadayken Asistan çalışmaya devam eder',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                  value: c.backgroundServiceEnabled,
                  onChanged: (v) => c.toggleBackgroundService(v),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        c.invokeNative('requestIgnoreBatteryOptimizations');
                      },
                      icon: const Icon(Icons.battery_saver_rounded, size: 17),
                      label: Text(
                        dev.ignoringBatteryOptimizations
                            ? 'Pil Kısıtlaması Yok (Onaylı)'
                            : 'Pil Kısıtlamasını Kaldır',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        c.invokeNative('deviceAction', {
                          'action': 'ayar_ac',
                          'target': 'asistan',
                        });
                      },
                      icon: const Icon(Icons.assistant_rounded, size: 17),
                      label: const Text('Varsayılan Asistan Yap'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        c.invokeNative('requestPermissions');
                      },
                      icon: const Icon(Icons.verified_user_rounded, size: 17),
                      label: const Text('Tüm İzinleri Doğrula'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. Hardware Telemetry & Quick Siri/Google Assistant Controls
          GlassCard3D(
            enable3DTilt: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.phone_android_rounded, color: preset.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cihaz Donanım Kontrolü (${dev.deviceModel})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: c.refreshDeviceStatus,
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _metricTile(
                      label: 'Batarya',
                      value: '%${dev.batteryPercent}',
                      sub: dev.isCharging
                          ? '⚡ Şarj Oluyor (${dev.batteryTempC}°C)'
                          : '${dev.batteryTempC}°C',
                      color: const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    _metricTile(
                      label: 'Boş Alan',
                      value: '${dev.storageFreeGb} GB',
                      sub: 'Toplam ${dev.storageTotalGb} GB',
                      color: preset.primary,
                    ),
                    const SizedBox(width: 8),
                    _metricTile(
                      label: 'Ses & Zil',
                      value: '%${dev.volumePercent}',
                      sub: dev.ringerMode.toUpperCase(),
                      color: preset.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: Icon(
                        dev.torchEnabled
                            ? Icons.flashlight_off_rounded
                            : Icons.flashlight_on_rounded,
                        size: 16,
                        color: dev.torchEnabled
                            ? const Color(0xFFF59E0B)
                            : Colors.white,
                      ),
                      label: Text(
                        dev.torchEnabled ? 'Feneri Kapat' : 'Feneri Aç',
                      ),
                      onPressed: () =>
                          c.executeQuickDeviceCommand('fener_degistir'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.volume_off_rounded, size: 16),
                      label: const Text('Sessize Al'),
                      onPressed: () => c.executeQuickDeviceCommand(
                        'zil_modu',
                        target: 'sessiz',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.vibration_rounded, size: 16),
                      label: const Text('Titreşim'),
                      onPressed: () => c.executeQuickDeviceCommand(
                        'zil_modu',
                        target: 'titresim',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.volume_up_rounded, size: 16),
                      label: const Text('Normal Ses'),
                      onPressed: () => c.executeQuickDeviceCommand(
                        'zil_modu',
                        target: 'normal',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.wifi_rounded, size: 16),
                      label: const Text('Wi-Fi'),
                      onPressed: () => c.executeQuickDeviceCommand(
                        'ayar_ac',
                        target: 'wifi',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.bluetooth_rounded, size: 16),
                      label: const Text('Bluetooth'),
                      onPressed: () => c.executeQuickDeviceCommand(
                        'ayar_ac',
                        target: 'bluetooth',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.music_note_rounded, size: 16),
                      label: const Text('Ritim Aç'),
                      onPressed: () =>
                          c.invokeNative('openAppOrUrl', {'target': 'ritim'}),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.school_rounded, size: 16),
                      label: const Text('Bilgili Aç'),
                      onPressed: () =>
                          c.invokeNative('openAppOrUrl', {'target': 'bilgili'}),
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 16,
                      ),
                      label: const Text('Kağıt Aç'),
                      onPressed: () =>
                          c.invokeNative('openAppOrUrl', {'target': 'kagit'}),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. Long-Term Memory (Hafıza)
          GlassCard3D(
            enable3DTilt: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🧠 Uzun Süreli Asistan Hafızası (${c.memories.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _memoryCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Asistanın her zaman hatırlamasını istediğiniz bilgi...',
                          hintStyle: TextStyle(color: Colors.white38),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        c.addMemoryFact('kisisel', _memoryCtrl.text);
                        _memoryCtrl.clear();
                      },
                      child: const Text('Ekle'),
                    ),
                  ],
                ),
                if (c.memories.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...c.memories.take(6).map((m) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        m.fact,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                        onPressed: () => c.deleteMemoryFact(m.id),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. Reminders (Hatırlatıcılar)
          GlassCard3D(
            enable3DTilt: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔔 Zamanlanmış Hatırlatıcılar (${c.reminders.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reminderCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          hintText:
                              'Hatırlatıcı başlığı (10 dk sonrasına kurar)...',
                          hintStyle: TextStyle(color: Colors.white38),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final txt = _reminderCtrl.text.trim();
                        if (txt.isEmpty) return;
                        _reminderCtrl.clear();
                        c.addReminder(
                          title: txt,
                          body: txt,
                          triggerAt: DateTime.now().add(
                            const Duration(minutes: 10),
                          ),
                        );
                      },
                      child: const Text('+10 Dk'),
                    ),
                  ],
                ),
                if (c.reminders.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...c.reminders.take(5).map((r) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.alarm_on_rounded,
                        color: preset.primary,
                      ),
                      title: Text(
                        r.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                      subtitle: Text(
                        '${r.triggerAt.hour.toString().padLeft(2, '0')}:${r.triggerAt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                        onPressed: () => c.removeReminder(r.id),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 5. CLIProxy & Cloud Server Configuration
          GlassCard3D(
            enable3DTilt: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_sync_rounded, color: preset.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'CLIProxy (ChatGPT • Gemini • Claude) & API',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.proxyOnline
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        c.proxyOnline ? 'BAĞLI (8317)' : 'YEREL MOD',
                        style: TextStyle(
                          color: c.proxyOnline
                              ? const Color(0xFF34D399)
                              : Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _proxyUrlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'CLIProxy / OpenAI Uyumlu Sunucu Adresi',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _proxyKeyCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Proxy / Sunucu Anahtarı',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _geminiKeyCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Doğrudan Gemini API Anahtarı (İsteğe Bağlı)',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: preset.primary,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () async {
                          await c.updateServerConfig(
                            proxyUrl: _proxyUrlCtrl.text,
                            proxyKey: _proxyKeyCtrl.text,
                            geminiKey: _geminiKeyCtrl.text,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                c.proxyOnline
                                    ? 'CLIProxy bağlantısı doğrulandı (${c.availableModels.length} model hazır)'
                                    : 'Ayarlar kaydedildi',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Kaydet & Modelleri Yenile',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        c.invokeNative('openAppOrUrl', {'target': 'cliproxy'});
                      },
                      child: const Text('CLIProxy Aç'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 6. MCP Servers (Model Context Protocol)
          GlassCard3D(
            enable3DTilt: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔌 MCP (Model Context Protocol) Sunucuları (${c.mcpServers.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _mcpNameCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Sunucu Adı',
                          hintStyle: TextStyle(color: Colors.white38),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _mcpUrlCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'http://127.0.0.1:3000/mcp',
                          hintStyle: TextStyle(color: Colors.white38),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () {
                        if (_mcpUrlCtrl.text.trim().isEmpty) return;
                        c.addMcpServer(
                          name: _mcpNameCtrl.text.trim().isEmpty
                              ? 'MCP Sunucu'
                              : _mcpNameCtrl.text.trim(),
                          url: _mcpUrlCtrl.text.trim(),
                        );
                        _mcpNameCtrl.clear();
                        _mcpUrlCtrl.clear();
                      },
                      child: const Text('Bağla'),
                    ),
                  ],
                ),
                if (c.mcpServers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...c.mcpServers.map((s) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        s.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${s.url} • ${s.tools.length} araç',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                        onPressed: () => c.removeMcpServer(s.id),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile({
    required String label,
    required String value,
    required String sub,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}
