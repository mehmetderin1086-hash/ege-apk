import 'package:flutter/material.dart';

import '../services/device_bridge.dart';

class DownloadSettings extends StatefulWidget {
  const DownloadSettings({super.key});
  @override
  State<DownloadSettings> createState() => _DownloadSettingsState();
}

class _DownloadSettingsState extends State<DownloadSettings> {
  bool _wifi = false;
  int _limit = 0;
  int _parallel = 2;
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await DeviceBridge.downloadPreferences();
    if (mounted) {
      setState(() {
        _wifi = p['wifiOnly'] == true;
        _limit = (p['limitKbps'] as num?)?.toInt() ?? 0;
        _parallel = (p['concurrency'] as num?)?.toInt() ?? 2;
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    await DeviceBridge.downloadPreferences(
      save: true,
      wifiOnly: _wifi,
      limitKbps: _limit,
      concurrency: _parallel,
    );
  }

  @override
  Widget build(BuildContext context) => !_loaded
      ? const LinearProgressIndicator()
      : Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Yalnızca Wi-Fi'),
              value: _wifi,
              onChanged: (v) {
                setState(() => _wifi = v);
                _save();
              },
            ),
            DropdownButtonFormField<int>(
              initialValue: _parallel,
              decoration: const InputDecoration(labelText: 'Aynı anda indirme'),
              items: [
                for (final n in [1, 2, 3])
                  DropdownMenuItem(value: n, child: Text('$n dosya')),
              ],
              onChanged: (v) {
                setState(() => _parallel = v!);
                _save();
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _limit,
              decoration: const InputDecoration(
                labelText: 'Dosya başına hız sınırı',
              ),
              items: [
                for (final n in {0, 128, 512, 1024, 2048, _limit})
                  DropdownMenuItem(
                    value: n,
                    child: Text(n == 0 ? 'Sınırsız' : '$n KB/sn'),
                  ),
              ],
              onChanged: (v) {
                setState(() => _limit = v!);
                _save();
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Tercihler otomatik kaydedilir. Devam ettirme sunucunun desteğine bağlıdır. Dosya değişmişse indirme baştan başlar.',
            ),
          ],
        );
}
