import 'package:flutter/material.dart';

import '../kagit_ai_service.dart';
import '../kagit_store.dart';
import '../theme_kagit.dart';
import 'shared_kagit_widgets.dart';

class KagitSettingsPage extends StatefulWidget {
  const KagitSettingsPage({super.key, required this.controller});

  final KagitController controller;

  @override
  State<KagitSettingsPage> createState() => _KagitSettingsPageState();
}

class _KagitSettingsPageState extends State<KagitSettingsPage> {
  late final TextEditingController _yazarCtrl;
  late final TextEditingController _okulCtrl;
  late final TextEditingController _dersCtrl;
  late final TextEditingController _turCtrl;
  late final TextEditingController _tarihCtrl;
  late final TextEditingController _sureCtrl;
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _personalTokenCtrl;

  @override
  void initState() {
    super.initState();
    final a = widget.controller.ayarlar;
    final ai = widget.controller.aiService.config;
    _yazarCtrl = TextEditingController(text: a.yazarAdi);
    _okulCtrl = TextEditingController(text: a.okulBasligi.okulAdi);
    _dersCtrl = TextEditingController(text: a.okulBasligi.dersAdi);
    _turCtrl = TextEditingController(text: a.okulBasligi.sinavTuru);
    _tarihCtrl = TextEditingController(text: a.okulBasligi.tarih);
    _sureCtrl = TextEditingController(text: a.okulBasligi.sure);
    _endpointCtrl = TextEditingController(text: ai.endpoint);
    _apiKeyCtrl = TextEditingController(text: ai.apiKey);
    _personalTokenCtrl = TextEditingController(text: ai.personalToken);
  }

  @override
  void dispose() {
    _yazarCtrl.dispose();
    _okulCtrl.dispose();
    _dersCtrl.dispose();
    _turCtrl.dispose();
    _tarihCtrl.dispose();
    _sureCtrl.dispose();
    _endpointCtrl.dispose();
    _apiKeyCtrl.dispose();
    _personalTokenCtrl.dispose();
    super.dispose();
  }

  void _saveAllSettings() {
    final a = widget.controller.ayarlar;
    a.yazarAdi = _yazarCtrl.text.trim().isEmpty ? 'Öğretmen' : _yazarCtrl.text.trim();
    a.okulBasligi
      ..okulAdi = _okulCtrl.text.trim()
      ..dersAdi = _dersCtrl.text.trim()
      ..sinavTuru = _turCtrl.text.trim()
      ..tarih = _tarihCtrl.text.trim()
      ..sure = _sureCtrl.text.trim();

    widget.controller.aiService.updateConfig((cfg) {
      cfg.endpoint = _endpointCtrl.text.trim();
      cfg.apiKey = _apiKeyCtrl.text.trim();
      cfg.personalToken = _personalTokenCtrl.text.trim();
    });
    widget.controller.persist();
    showKagitSnack(context, 'Ayarlar ve CLIProxyAPI profili kaydedildi.');
  }

  Future<void> _fetchModels() async {
    widget.controller.aiService.updateConfig((cfg) {
      cfg.endpoint = _endpointCtrl.text.trim();
      cfg.apiKey = _apiKeyCtrl.text.trim();
      cfg.personalToken = _personalTokenCtrl.text.trim();
    });
    try {
      final list = await widget.controller.aiService.fetchAllModels();
      widget.controller.persist();
      if (mounted) {
        showKagitSnack(context, 'Tüm sağlayıcılardan ${list.length} model yüklendi.');
      }
    } catch (e) {
      if (mounted) showKagitSnack(context, 'Bağlantı hatası: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.controller.ayarlar;
    final aiSvc = widget.controller.aiService;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        Text('Stüdyo Ayarları', style: kagitSerif(context, size: 24)),
        const SizedBox(height: 4),
        Text(
          'Görünüm, okul sınav başlığı varsayılanları ve CLIProxyAPI bağlantısı.',
          style: TextStyle(fontSize: 13, color: KagitTema.inkSecondary(context)),
        ),
        const SizedBox(height: 16),

        // Görünüm ve Genel
        _SectionCard(
          title: 'Görünüm ve Düzenleme',
          icon: Icons.palette_outlined,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Koyu Mürekkep Teması'),
              subtitle: const Text('Gece okuma ve düşük ışık çalışma modu'),
              value: a.isDark,
              onChanged: (v) {
                a.isDark = v;
                widget.controller.persist();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Değişiklikleri Otomatik Kaydet'),
              value: a.otomatikKaydet,
              onChanged: (v) {
                a.otomatikKaydet = v;
                widget.controller.persist();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _yazarCtrl,
              decoration: const InputDecoration(
                labelText: 'Varsayılan Yazar / Öğretmen Adı',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // CLIProxyAPI ve Tüm Modeller
        _SectionCard(
          title: 'CLIProxyAPI ve Tüm AI Modelleri',
          icon: Icons.hub_outlined,
          children: [
            SegmentedButton<KagitAiMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: KagitAiMode.localCliProxy, label: Text('Yerel Proxy', style: TextStyle(fontSize: 11.5))),
                ButtonSegment(value: KagitAiMode.customCliProxy, label: Text('Özel Proxy', style: TextStyle(fontSize: 11.5))),
                ButtonSegment(value: KagitAiMode.directGemini, label: Text('Gemini API', style: TextStyle(fontSize: 11.5))),
              ],
              selected: {aiSvc.config.mode},
              onSelectionChanged: (s) {
                final m = s.first;
                aiSvc.updateConfig((cfg) {
                  cfg.mode = m;
                  if (m == KagitAiMode.localCliProxy) {
                    cfg.endpoint = 'http://127.0.0.1:8317';
                    _endpointCtrl.text = cfg.endpoint;
                  }
                });
                widget.controller.persist();
              },
            ),
            const SizedBox(height: 12),
            if (aiSvc.config.mode != KagitAiMode.directGemini)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _endpointCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CLIProxyAPI Sunucu Adresi',
                    hintText: 'http://127.0.0.1:8317',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Anahtarı (Bearer)',
                border: OutlineInputBorder(),
              ),
            ),
            if (aiSvc.config.mode != KagitAiMode.directGemini) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _personalTokenCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Kişisel Token (X-Personal-Token, opsiyonel)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: aiSvc.isFetchingModels ? null : _fetchModels,
                    icon: aiSvc.isFetchingModels
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: Text('Tüm Modelleri Getir (${aiSvc.effectiveModels.length})'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: KagitTema.border(context)),
              ),
              leading: const Icon(Icons.smart_toy_rounded, color: KagitTema.morOkuma),
              title: Text(aiSvc.config.selectedModelId, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Sağlayıcı grupları arasında model seç (${aiSvc.effectiveModels.length} model)'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showAiModelPickerSheet(context, widget.controller),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Okul Başlık Şablonu
        _SectionCard(
          title: 'Varsayılan Okul Sınav Başlığı',
          icon: Icons.school_outlined,
          children: [
            TextField(
              controller: _okulCtrl,
              decoration: const InputDecoration(labelText: 'Okul / Kurum Adı', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dersCtrl,
                    decoration: const InputDecoration(labelText: 'Ders Adı', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _turCtrl,
                    decoration: const InputDecoration(labelText: 'Sınav Türü', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tarihCtrl,
                    decoration: const InputDecoration(labelText: 'Tarih', hintText: '13.11.2026', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _sureCtrl,
                    decoration: const InputDecoration(labelText: 'Süre', hintText: '40 dk', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveAllSettings,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Tüm Ayarları Kaydet'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        _SectionCard(
          title: 'Kitaplık ve Depolama',
          icon: Icons.folder_special_outlined,
          children: [
            Text(
              'Etkin Belge: ${widget.controller.activeItems.length}   •   '
              'Yıldızlı: ${widget.controller.starredItems.length}   •   '
              'Çöp Kutusu: ${widget.controller.trashItems.length}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (widget.controller.trashItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  widget.controller.emptyTrash();
                  showKagitSnack(context, 'Çöp kutusu tamamen boşaltıldı.');
                },
                icon: const Icon(Icons.delete_forever_rounded, color: KagitTema.vurgu),
                label: const Text('Çöp Kutusunu Kalıcı Olarak Boşalt'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KagitTema.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: KagitTema.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: KagitTema.vurgu),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(title, maxLines: 1, style: kagitSerif(context, size: 17)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// CLIProxyAPI'den gelen TÜM modelleri sağlayıcı başlıkları altında aramalı olarak listeler.
Future<void> showAiModelPickerSheet(BuildContext context, KagitController controller) async {
  String filter = '';
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final groups = controller.aiService.groupedModels(filter);
        final totalCount = controller.aiService.effectiveModels.length;

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Tüm Modeller ($totalCount)', style: kagitSerif(ctx, size: 18)),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await controller.aiService.fetchAllModels();
                            controller.persist();
                            setModalState(() {});
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Yenile'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Model veya sağlayıcı ara (claude, gpt, gemini, qwen...)',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onChanged: (v) => setModalState(() => filter = v),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: RadioGroup<String>(
                    groupValue: controller.aiService.config.selectedModelId,
                    onChanged: (v) {
                      if (v == null) return;
                      controller.aiService.updateConfig((cfg) => cfg.selectedModelId = v);
                      controller.persist();
                      Navigator.pop(ctx);
                    },
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text(
                              '${entry.key} (${entry.value.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: KagitTema.morOkuma,
                              ),
                            ),
                          ),
                          for (final m in entry.value)
                            RadioListTile<String>(
                              dense: true,
                              value: m.id,
                              title: Text(m.id, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: m.displayName != m.id ? Text(m.displayName) : null,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
