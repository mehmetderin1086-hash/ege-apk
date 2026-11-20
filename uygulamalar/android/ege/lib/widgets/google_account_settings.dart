import 'package:flutter/material.dart';

import '../services/google_workspace.dart';

class GoogleAccountSettings extends StatefulWidget {
  const GoogleAccountSettings({super.key, required this.google});
  final GoogleWorkspace google;
  @override
  State<GoogleAccountSettings> createState() => _GoogleAccountSettingsState();
}

class _GoogleAccountSettingsState extends State<GoogleAccountSettings> {
  final _connected = <String, bool>{};
  String? _busy;
  String? _message;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final service in GoogleWorkspace.services) {
      final value = await widget.google.connected(service);
      if (mounted) setState(() => _connected[service] = value);
    }
  }

  Future<void> _connect(String service) async {
    setState(() {
      _busy = service;
      _message = null;
    });
    try {
      await widget.google.connect(service);
      if (mounted) setState(() => _message = 'Bağlantı doğrulandı.');
    } catch (e) {
      if (mounted)
        setState(
          () => _message = e is StateError
              ? e.message.toString()
              : 'Google bağlantısı kurulamadı.',
        );
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Google hesapları',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      const Text(
        'Her hizmeti ayrı bağla. Hesap ve izin seçimi Google ekranında yapılır. Erişim anahtarları sohbet veya hafızaya kaydedilmez.',
      ),
      for (final item in const [
        ('gmail', 'Gmail', 'Mailleri oku ve komutunla mail gönder'),
        (
          'drive',
          'Google Drive',
          'Dosyaları bul; Ege dosyalarını Drive’a yükle',
        ),
        ('calendar', 'Google Takvim', 'Etkinlikleri oku, oluştur ve güncelle'),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item.$2),
          subtitle: Text(
            '${item.$3}\n${_connected[item.$1] == true ? "Bağlı" : "Bağlı değil"}',
          ),
          trailing: _busy == item.$1
              ? const CircularProgressIndicator()
              : TextButton(
                  onPressed: _busy != null ? null : () => _connect(item.$1),
                  child: Text(
                    _connected[item.$1] == true ? 'Yenile' : 'Bağlan',
                  ),
                ),
          onLongPress: _connected[item.$1] != true
              ? null
              : () async {
                  await widget.google.disconnect(item.$1);
                  await _refresh();
                  if (mounted)
                    setState(
                      () => _message = 'Ege’de bağlantı kapatıldı. Google’daki izni de kaldırmak için Google hesabındaki Üçüncü taraf bağlantıları bölümünü kullan.',
                    );
                },
        ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(_message!),
        ),
    ],
  );
}
