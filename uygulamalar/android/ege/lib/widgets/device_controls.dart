import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/jarvis_models.dart';
import '../services/device_bridge.dart';
import '../state/jarvis_controller.dart';
import 'chat_palette.dart';

/// Türkçe duyarlı küçük harf: 'İ' -> 'i', 'I' -> 'ı' (Dart toLowerCase 'İ'yi 'i̇' yapar).
String turkishLower(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// Uygulama arama eşleşmesi: Türkçe küçük harf ya da düz küçük harf (Instagram/ınstagram) eşleşirse true.
bool appMatchesQuery(String name, String packageName, String query) {
  final q = query.trim();
  if (q.isEmpty) return true;
  return turkishLower(name).contains(turkishLower(q)) ||
      name.toLowerCase().contains(q.toLowerCase()) ||
      packageName.toLowerCase().contains(q.toLowerCase());
}

Color get _accent => ChatPalette.accent;
Color get _muted => ChatPalette.muted;

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Brightness, ringer mode, quick panels, screen-on and vibration controls.
class QuickSystemControlsCard extends StatefulWidget {
  const QuickSystemControlsCard({super.key});

  @override
  State<QuickSystemControlsCard> createState() => _QuickSystemControlsCardState();
}

class _QuickSystemControlsCardState extends State<QuickSystemControlsCard> {
  int _brightness = 50;
  String _ringer = 'normal';
  bool _keepOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await DeviceBridge.getBrightness();
    final r = await DeviceBridge.getRingerMode();
    if (!mounted) return;
    setState(() {
      _brightness = b.clamp(0, 100);
      _ringer = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hızlı Sistem Kontrolleri',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.brightness_6_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _brightness.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '%$_brightness',
                    onChanged: (v) => setState(() => _brightness = v.round()),
                    onChangeEnd: (v) async {
                      final res = await DeviceBridge.setBrightness(v.round());
                      if (!context.mounted) return;
                      if (res == 'PERMISSION_NEEDED') {
                        _toast(context, 'Sistem parlaklığı için "Sistem ayarlarını değiştir" iznini verin.');
                      }
                    },
                  ),
                ),
                SizedBox(width: 44, child: Text('%$_brightness', textAlign: TextAlign.end)),
              ],
            ),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'normal', icon: Icon(Icons.notifications_active_outlined), label: Text('Normal')),
                ButtonSegment(value: 'vibrate', icon: Icon(Icons.vibration_rounded), label: Text('Titreşim')),
                ButtonSegment(value: 'silent', icon: Icon(Icons.notifications_off_outlined), label: Text('Sessiz')),
              ],
              selected: {_ringer},
              onSelectionChanged: (sel) async {
                final mode = sel.first;
                final res = await DeviceBridge.setRingerMode(mode);
                if (!context.mounted) return;
                if (res == 'OK') {
                  setState(() => _ringer = mode);
                } else if (res == 'PERMISSION_NEEDED') {
                  _toast(context, 'Rahatsız Etmeyin erişimi izni gerekiyor; ayar ekranı açıldı.');
                }
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              secondary: const Icon(Icons.light_mode_outlined),
              title: const Text('Ekranı açık tut'),
              value: _keepOn,
              onChanged: (v) async {
                await DeviceBridge.keepScreenOn(v);
                if (!mounted) return;
                setState(() => _keepOn = v);
              },
            ),
            const SizedBox(height: 4),
            Text('Hızlı Paneller', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in const [
                  ('İnternet', 'internet', Icons.signal_cellular_alt_rounded),
                  ('Wi-Fi', 'wifi', Icons.wifi_rounded),
                  ('Bluetooth', 'bluetooth', Icons.bluetooth_rounded),
                  ('NFC', 'nfc', Icons.nfc_rounded),
                  ('Hotspot', 'hotspot', Icons.wifi_tethering_rounded),
                  ('Uçak Modu', 'airplane', Icons.airplanemode_active_rounded),
                  ('Rahatsız Etmeyin', 'dnd', Icons.do_not_disturb_on_outlined),
                  ('Pil Tasarrufu', 'battery_saver', Icons.battery_saver_rounded),
                  ('Ses', 'volume', Icons.volume_up_outlined),
                  ('Depolama', 'storage', Icons.sd_storage_outlined),
                  ('Bildirimler', 'notifications', Icons.notifications_outlined),
                ])
                  ActionChip(
                    avatar: Icon(p.$3, size: 16),
                    label: Text(p.$1),
                    onPressed: () => DeviceBridge.openSettingsPanel(p.$2),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.vibration_rounded, size: 16),
                  label: const Text('Titret'),
                  onPressed: () => DeviceBridge.vibrate(ms: 400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen-time card based on Android UsageStatsManager.
class AppUsageCard extends StatefulWidget {
  const AppUsageCard({super.key});

  @override
  State<AppUsageCard> createState() => _AppUsageCardState();
}

class _AppUsageCardState extends State<AppUsageCard> {
  bool? _hasAccess;
  List<AppUsageInfo> _usage = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final access = await DeviceBridge.hasUsageAccess();
    final usage = access ? await DeviceBridge.getAppUsageStats(days: 1) : const <AppUsageInfo>[];
    if (!mounted) return;
    setState(() {
      _hasAccess = access;
      _usage = usage;
      _loading = false;
    });
  }

  String _fmt(int ms) {
    final m = ms ~/ 60000;
    if (m < 60) return '$m dk';
    return '${m ~/ 60} sa ${m % 60} dk';
  }

  @override
  Widget build(BuildContext context) {
    final total = _usage.fold<int>(0, (s, u) => s + u.foregroundMs);
    final maxMs = _usage.isEmpty ? 1 : _usage.first.foregroundMs.clamp(1, 1 << 62);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _usage.isEmpty ? 'Bugünkü Ekran Süresi' : 'Bugünkü Ekran Süresi • ${_fmt(total)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 20)),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_hasAccess == false)
              Row(
                children: [
                  Expanded(
                    child: Text('Uygulama kullanım süreleri için "Kullanım erişimi" izni gerekli.',
                        style: TextStyle(fontSize: 12, color: _muted)),
                  ),
                  TextButton(
                    onPressed: () async {
                      await DeviceBridge.openUsageAccessSettings();
                    },
                    child: const Text('İzin Ver'),
                  ),
                ],
              ),
            if (_hasAccess == true && _usage.isEmpty && !_loading)
              Text('Bugün için veri yok.', style: TextStyle(fontSize: 12, color: _muted)),
            for (final u in _usage.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(_fmt(u.foregroundMs), style: TextStyle(fontSize: 12, color: _muted)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(value: u.foregroundMs / maxMs, minHeight: 4),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Installed apps with icons, search, filters and management actions.
class InstalledAppsManager extends StatefulWidget {
  final JarvisController controller;
  const InstalledAppsManager({super.key, required this.controller});

  @override
  State<InstalledAppsManager> createState() => _InstalledAppsManagerState();
}

class _InstalledAppsManagerState extends State<InstalledAppsManager> {
  String _query = '';
  bool _showSystem = false;
  bool _expanded = false;

  Future<void> _showActions(DeviceAppInfo app) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _AppIcon(packageName: app.packageName, size: 40),
              title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${app.packageName}\nSürüm ${app.versionName.isEmpty ? '-' : app.versionName}'
                '${app.lastUpdateMs > 0 ? ' • Güncelleme ${_date(app.lastUpdateMs)}' : ''}',
                style: const TextStyle(fontSize: 11.5),
              ),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Aç'),
              onTap: () {
                Navigator.pop(ctx);
                widget.controller.launchInstalledApp(app.packageName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Uygulama Bilgisi / İzinler'),
              onTap: () {
                Navigator.pop(ctx);
                DeviceBridge.openAppInfo(app.packageName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shop_outlined),
              title: const Text('Play Store\'da Aç'),
              onTap: () {
                Navigator.pop(ctx);
                DeviceBridge.openPlayStore(app.packageName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Bağlantısını Paylaş'),
              onTap: () {
                Navigator.pop(ctx);
                DeviceBridge.shareText(
                  '${app.name}: https://play.google.com/store/apps/details?id=${app.packageName}',
                );
              },
            ),
            if (!app.isSystem)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171)),
                title: const Text('Kaldır', style: TextStyle(color: Color(0xFFF87171))),
                onTap: () {
                  Navigator.pop(ctx);
                  DeviceBridge.uninstallApp(app.packageName);
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.controller.installedApps;
    final rawQ = _query.trim();
    final filtered = all
        .where((a) => _showSystem || !a.isSystem)
        .where((a) => appMatchesQuery(a.name, a.packageName, rawQ))
        .toList();
    final visible = _expanded ? filtered : filtered.take(24).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Yüklü Uygulamalar (${all.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Listeyi Yenile',
                  onPressed: () => widget.controller.refreshInstalledApps(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
            TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                hintText: 'Uygulama ara veya başlat...',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            Row(
              children: [
                Checkbox(
                  value: _showSystem,
                  onChanged: (v) => setState(() => _showSystem = v ?? false),
                ),
                const Text('Sistem uygulamalarını göster', style: TextStyle(fontSize: 12.5)),
              ],
            ),
            if (all.isEmpty)
              Text('Yüklü uygulama listesi yalnızca Android cihazda görünür.',
                  style: TextStyle(fontSize: 12, color: _muted))
            else if (filtered.isEmpty)
              Text('Eşleşen uygulama bulunamadı.', style: TextStyle(fontSize: 12, color: _muted))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visible.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 84,
                  mainAxisExtent: 92,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemBuilder: (context, i) {
                  final app = visible[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => widget.controller.launchInstalledApp(app.packageName),
                    onLongPress: () => _showActions(app),
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        _AppIcon(packageName: app.packageName, size: 44),
                        const SizedBox(height: 5),
                        Text(
                          app.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (filtered.length > 24)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Daha az göster' : 'Tümünü göster (${filtered.length})'),
                ),
              ),
            Text('İpucu: Yönetim menüsü için simgeye uzun basın.',
                style: TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final String packageName;
  final double size;
  const _AppIcon({required this.packageName, required this.size});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: DeviceBridge.getAppIcon(packageName),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Icon(Icons.android_rounded, size: size * 0.8, color: _accent);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.memory(bytes, width: size, height: size, gaplessPlayback: true),
        );
      },
    );
  }
}
