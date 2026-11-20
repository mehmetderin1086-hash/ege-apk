import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/jarvis_models.dart';
import '../services/device_bridge.dart';
import '../services/local_command_engine.dart';
import '../state/jarvis_controller.dart';
import '../widgets/chat_palette.dart';

class WhatsAppScreen extends StatefulWidget {
  final JarvisController controller;
  const WhatsAppScreen({super.key, required this.controller});

  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen>
    with WidgetsBindingObserver {
  final _recipient = TextEditingController();
  final _draft = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _access = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _opening = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _recipient.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final access = await DeviceBridge.notificationAccessGranted();
      final messages = access
          ? await DeviceBridge.recentNotifications(limit: 40)
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _access = access;
        _messages = messages
            .where(
              (n) =>
                  n['package'] == 'com.whatsapp' ||
                  n['package'] == 'com.whatsapp.w4b',
            )
            .toList();
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _read(Map<String, dynamic> message) async {
    if (widget.controller.liveLoopActive || widget.controller.isDictating) {
      _notice('Seslendirmek için önce canlı konuşmayı veya dikteyi bitir.');
      return;
    }
    await widget.controller.speakMessage(
      'whatsapp:${message['key']}',
      '${message['title'] ?? 'WhatsApp'}: ${message['text'] ?? ''}',
    );
  }

  Future<String?> _resolveNumber() async {
    final who = _recipient.text.trim();
    if (who.isEmpty) {
      _notice('Bir kişi adı veya telefon numarası gir.');
      return null;
    }
    if (RegExp(r'^\+?[\d\s()\-]+$').hasMatch(who)) {
      final number = LocalCommandEngine.waNumber(who);
      if (!RegExp(r'^\d{8,15}$').hasMatch(number)) {
        _notice('Ülke koduyla geçerli bir telefon numarası gir.');
        return null;
      }
      return number;
    }
    final contacts = await DeviceBridge.searchContacts(who);
    if (!mounted) return null;
    if (contacts.isEmpty) {
      _notice('Kişi bulunamadı. Rehber iznini kontrol et veya numara gir.');
      return null;
    }
    final contact = await showModalBottomSheet<ContactInfo>(
      context: context,
      backgroundColor: ChatPalette.surface,
      isScrollControlled: true,
      builder: (_) => Theme(
        data: ChatPalette.theme,
        child: SafeArea(
          child: SizedBox(
            height: 320,
            child: ListView(
              children: [
                const ListTile(
                  title: Text('Alıcıyı seç'),
                  subtitle: Text('Adını ve numarasını kontrol et.'),
                ),
                for (final contact in contacts)
                  ListTile(
                    title: Text(contact.name),
                    subtitle: Text(contact.phone),
                    onTap: () => Navigator.pop(context, contact),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return contact == null ? null : LocalCommandEngine.waNumber(contact.phone);
  }

  Future<void> _openDraft() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final text = _draft.text.trim();
      final number = await _resolveNumber();
      if (number == null || !mounted) return;
      final uri = Uri.https(
        'wa.me',
        '/$number',
        text.isEmpty ? null : {'text': text},
      );
      final opened = await DeviceBridge.openUrl(uri.toString());
      if (!opened) {
        _notice('WhatsApp açılamadı. Uygulamanın kurulu olduğunu kontrol et.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: ChatPalette.surface,
      border: Border.all(color: ChatPalette.border),
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: ChatPalette.theme,
    child: Scaffold(
      backgroundColor: ChatPalette.background,
      appBar: AppBar(
        title: const Text('WhatsApp'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
             Text(
              'Mesajların, bir arada.',
              style: TextStyle(
                fontSize: 26,
                color: ChatPalette.ink,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
             Text(
              'Burada yalnızca telefonda bulunan WhatsApp bildirimleri görünür. '
              'Geçmiş sohbetlerin tamamı okunmaz.',
              style: TextStyle(color: ChatPalette.muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Yeni mesaj taslağı',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipient,
                    decoration: const InputDecoration(
                      labelText: 'Kişi adı veya telefon',
                      hintText: '+90 5xx xxx xx xx',
                      border: UnderlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _draft,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Mesaj taslağı',
                      hintText: 'Ne söylemek istersin?',
                      border: UnderlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final template in const [
                        ('Selamlaş', 'Merhaba, nasılsın?'),
                        (
                          'Gecikeceğim',
                          'Merhaba, biraz gecikeceğim. Anlayışın için teşekkür ederim.',
                        ),
                        ('Teşekkür et', 'Yardımın için çok teşekkür ederim.'),
                      ])
                        ActionChip(
                          label: Text(template.$1),
                          onPressed: () {
                            _draft.text = _draft.text.isEmpty
                                ? template.$2
                                : '${_draft.text}\n${template.$2}';
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _opening ? null : _openDraft,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('WhatsApp’ta aç'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          if (_draft.text.trim().isEmpty) {
                            _notice('Önce bir mesaj yaz.');
                            return;
                          }
                          await Clipboard.setData(
                            ClipboardData(text: _draft.text),
                          );
                          _notice('Taslak kopyalandı.');
                        },
                        icon: const Icon(Icons.copy_outlined, size: 17),
                        label: const Text('Kopyala'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                   Text(
                    'Taslağı düzenle; son gönderme işlemini WhatsApp’ta yap.',
                    style: TextStyle(fontSize: 12, color: ChatPalette.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Gelen mesajlar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (!_access)
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mesajları görmek için bildirim erişimini aç.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (!await DeviceBridge.openNotificationAccessSettings()) {
                          _notice('Bildirim erişimi ayarları açılamadı.');
                        }
                      },
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('Bildirim erişimini aç'),
                    ),
                  ],
                ),
              )
            else if (_messages.isEmpty)
              _card(
                 Text(
                  'Henüz WhatsApp bildirimi yok.',
                  style: TextStyle(color: ChatPalette.muted),
                ),
              )
            else
              for (final message in _messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['title']?.toString() ?? 'WhatsApp',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          message['text']?.toString() ?? '',
                          style: const TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: () => _read(message),
                              icon: const Icon(
                                Icons.volume_up_outlined,
                                size: 18,
                              ),
                              label: const Text('Seslendir'),
                            ),
                            TextButton.icon(
                              onPressed: widget.controller.stopSpeaking,
                              icon: const Icon(Icons.stop_rounded, size: 18),
                              label: const Text('Durdur'),
                            ),
                            TextButton.icon(
                              key: ValueKey('open-whatsapp-${message['key']}'),
                              onPressed: () async {
                                if (!await DeviceBridge.openWhatsAppNotification(
                                  message['key']?.toString() ?? '',
                                )) {
                                  _notice(
                                    'Bu bildirim artık açılamıyor. Mesaj listesini yenile.',
                                  );
                                }
                              },
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                              ),
                              label: const Text('Konuşmayı aç'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}
