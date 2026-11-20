import 'package:flutter/material.dart';

import '../services/google_workspace.dart';
import '../services/microsoft_workspace.dart';

class AccountConnections extends StatefulWidget {
  const AccountConnections({
    super.key,
    required this.google,
    required this.microsoft,
  });
  final GoogleWorkspace google;
  final MicrosoftWorkspace microsoft;
  @override
  State<AccountConnections> createState() => _AccountConnectionsState();
}

class _AccountConnectionsState extends State<AccountConnections> {
  static const _items = [
    ('google', 'gmail', 'Gmail', 'Mailleri oku ve isteğinle gönder'),
    (
      'google',
      'drive',
      'Google Drive',
      'Dosyaları bul ve Ege dosyalarını yükle',
    ),
    (
      'google',
      'calendar',
      'Google Takvim',
      'Etkinlikleri oku, oluştur ve güncelle',
    ),
    (
      'microsoft',
      'outlook',
      'Outlook / Hotmail',
      'Mailleri oku ve isteğinle gönder',
    ),
    (
      'microsoft',
      'onedrive',
      'OneDrive · Word · Excel',
      'Office dosyalarını bul, aç ve Ege dosyalarını yükle',
    ),
    (
      'microsoft',
      'calendar',
      'Microsoft Takvim',
      'Etkinlikleri oku, oluştur ve güncelle',
    ),
  ];
  final _connected = <String, bool>{};
  String? _busy;
  String? _message;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final item in _items) {
      final value = item.$1 == 'google'
          ? await widget.google.connected(item.$2)
          : await widget.microsoft.connected(item.$2);
      if (!mounted) return;
      setState(() => _connected['${item.$1}/${item.$2}'] = value);
    }
  }

  Future<void> _action(
    String provider,
    String service, {
    bool disconnect = false,
  }) async {
    setState(() {
      _busy = '$provider/$service';
      _message = null;
    });
    try {
      if (provider == 'google') {
        if (disconnect) {
          await widget.google.disconnect(service);
        } else {
          await widget.google.connect(service);
        }
      } else {
        if (disconnect) {
          await widget.microsoft.disconnect(service);
        } else {
          await widget.microsoft.connect(service);
        }
      }
      if (mounted)
        setState(
          () => _message = disconnect
              ? 'Ege’de hizmet bağlantısı kapatıldı. Sağlayıcıdaki izinleri hesabının uygulama izinlerinden ayrıca kaldırabilirsin.'
              : 'Hesap bağlantısı doğrulandı.',
        );
    } catch (e) {
      if (mounted)
        setState(
          () => _message = e is StateError
              ? e.message.toString()
              : 'Bağlantı tamamlanamadı. Tekrar deneyebilirsin.',
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
        'Hesabını buradan bağla. Giriş ve izin seçimi Google veya Microsoft’un kendi ekranında yapılır. Şifren Ege’ye kaydedilmez.',
      ),
      for (final provider in ['google', 'microsoft']) ...[
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 4),
          child: Text(
            provider == 'google' ? 'Google' : 'Microsoft',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final item in _items.where((i) => i.$1 == provider)) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.$3),
            subtitle: Text(
              '${item.$4}\n${_connected['$provider/${item.$2}'] == true ? 'Bağlı' : 'Bağlı değil'}',
            ),
            trailing: _busy == '$provider/${item.$2}'
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(),
                  )
                : TextButton(
                    onPressed: _busy == null
                        ? () => _action(provider, item.$2)
                        : null,
                    child: Text(
                      _connected['$provider/${item.$2}'] == true
                          ? 'Yenile'
                          : 'Bağlan',
                    ),
                  ),
          ),
          if (_connected['$provider/${item.$2}'] == true)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy == null
                    ? () => _action(provider, item.$2, disconnect: true)
                    : null,
                icon: const Icon(Icons.link_off, size: 18),
                label: Text('${item.$3} bağlantısını kapat'),
              ),
            ),
        ],
      ],
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_message!),
        ),
    ],
  );
}
