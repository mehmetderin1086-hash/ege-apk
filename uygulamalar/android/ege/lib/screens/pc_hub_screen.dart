import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pc_models.dart';
import '../services/pc_bridge_client.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';
import 'pc_files_screen.dart';
import 'pc_jobs_screen.dart';
import '../widgets/chat_palette.dart';

/// "PC Kod" tab: pairs the phone with the Ege PC Bridge on Windows and
/// gives access to source code, CLI Proxy API keys, tasks and coding agents.
class PcHubScreen extends StatefulWidget {
  final JarvisController controller;

  const PcHubScreen({super.key, required this.controller});

  @override
  State<PcHubScreen> createState() => _PcHubScreenState();
}

class _PcHubScreenState extends State<PcHubScreen> {
  final _manualCtrl = TextEditingController();
  bool _pairing = false;
  bool _importing = false;

  JarvisController get c => widget.controller;

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _pairFlow(String url, {String? hostLabel}) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => _PinDialog(host: hostLabel ?? url),
    );
    if (pin == null || pin.trim().length != 6 || !mounted) return;
    setState(() => _pairing = true);
    final err = await c.pairPc(url, pin);
    if (!mounted) return;
    setState(() => _pairing = false);
    if (err != null) {
      showJarvisSnack(context, err, error: true);
      return;
    }
    showJarvisSnack(context, 'PC ile eşleşildi: ${c.settings.pcBridgeName}');
    await _importKeys(auto: true);
  }

  Future<void> _importKeys({bool auto = false}) async {
    setState(() => _importing = true);
    final res = await c.importKeysFromPc();
    if (!mounted) return;
    setState(() => _importing = false);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    res.ok ? Icons.verified_rounded : Icons.error_outline_rounded,
                    color: res.ok ? JColors.ok : JColors.bad,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      res.ok
                          ? (auto ? 'Kurulum tamam!' : 'API\'ler güncellendi')
                          : 'API\'ler alınamadı',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(res.message, style:  TextStyle(color: JColors.muted)),
              const SizedBox(height: 10),
              for (final item in res.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Icon(Icons.check_circle_rounded, size: 16, color: JColors.ok),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
              if (res.ok) ...[
                const SizedBox(height: 10),
                 Text(
                  'Sohbet artık PC\'deki CLI Proxy modelleriyle, sesler bulut motorlarıyla çalışır. '
                  'Ses seçmek için Ayarlar → Bulut Ses Stüdyosu.',
                  style: TextStyle(fontSize: 12.5, color: JColors.accent),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tamam'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFiles(PcRoot root) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PcFilesScreen(controller: c, startPath: root.path, title: root.name),
    ));
  }

  Future<PcRoot?> _pickRoot({String title = 'Proje seç'}) async {
    final roots = c.pcInfo?.roots ?? const <PcRoot>[];
    if (roots.isEmpty) {
      showJarvisSnack(context, 'PC proje listesi yüklenemedi.', error: true);
      return null;
    }
    if (roots.length == 1) return roots.first;
    return showModalBottomSheet<PcRoot>(
      context: context,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final r in roots)
              ListTile(
                leading:  Icon(Icons.folder_special_rounded, color: JColors.warn),
                title: Text(r.name),
                subtitle: Text(r.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _search() async {
    final root = await _pickRoot(title: 'Hangi projede aranacak?');
    if (root == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PcSearchScreen(controller: c, root: root.path, rootName: root.name),
    ));
  }

  void _openJobs(int tab) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PcJobsScreen(controller: c, initialTab: tab),
    ));
  }

  Future<void> _upload() async {
    final root = await _pickRoot(title: 'Dosya hangi klasöre gönderilsin?');
    if (root == null || !mounted) return;
    final f = await FilePicker.pickFile();
    if (f == null || !mounted) return;
    try {
      final bytes = await f.readAsBytes();
      final path = await c.pcClient!.upload(dir: root.path, name: f.name, bytes: bytes);
      if (mounted) showJarvisSnack(context, 'PC\'ye gönderildi: $path');
    } catch (e) {
      if (mounted) showJarvisSnack(context, '$e', error: true);
    }
  }

  Future<void> _clipboard() async {
    final client = c.pcClient;
    if (client == null) return;
    final sendCtrl = TextEditingController();
    String? pcText;
    String? err;
    try {
      pcText = await client.clipboard();
    } catch (e) {
      err = '$e';
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ortak Pano', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
             Text('PC panosundaki metin', style: TextStyle(color: JColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: JColors.code,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JColors.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  err ?? ((pcText ?? '').isEmpty ? '(boş)' : pcText!),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: (pcText ?? '').isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: pcText!));
                        Navigator.pop(ctx);
                        showJarvisSnack(context, 'Telefon panosuna kopyalandı');
                      },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Telefona kopyala'),
              ),
            ),
            TextField(
              controller: sendCtrl,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'PC panosuna gönderilecek metin',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    sendCtrl.text = data?.text ?? '';
                  },
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                  label: const Text('Telefon panosu'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await client.setClipboard(sendCtrl.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) showJarvisSnack(context, 'PC panosuna gönderildi');
                    } catch (e) {
                      if (mounted) showJarvisSnack(context, '$e', error: true);
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('PC\'ye gönder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    sendCtrl.dispose();
  }

  Future<void> _apkUpdate() async {
    final client = c.pcClient;
    if (client == null) return;
    PcApkInfo? info;
    String? err;
    try {
      info = await client.apkInfo();
    } catch (e) {
      err = '$e';
    }
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JColors.surface,
        title: const Text('PC\'den Uygulama Güncelle'),
        content: Text(
          info == null
              ? (err ?? 'APK bulunamadı.')
              : 'PC\'deki en yeni Ege APK\'sı:\n\n${info.name}\n'
                  '${formatBytes(info.size)} • ${formatAgo(info.modified)}\n\n'
                  'İndirilip Android kurulum ekranı açılacak.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          if (info != null)
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.system_update_rounded, size: 18),
              label: const Text('İndir ve Kur'),
            ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final msg = await c.updateAppFromPc();
    if (mounted) showJarvisSnack(context, msg);
  }

  void _screenshot() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PcScreenshotScreen(controller: c),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    if (!s.pcPaired) return _buildPairing();
    return RefreshIndicator(
      onRefresh: c.refreshPcInfo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _buildHostCard(),
          if (c.apkDownloadProgress != null) ...[
            const SizedBox(height: 10),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('APK indiriliyor… %${((c.apkDownloadProgress ?? 0) * 100).round()}'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: c.apkDownloadProgress),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildKeysCard(),
          const SectionTitle('Hızlı İşlemler', icon: Icons.bolt_rounded),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 1.05,
            children: [
              QuickTile(
                icon: Icons.search_rounded,
                label: 'Kod Ara',
                subtitle: 'İçerik / dosya adı',
                onTap: _search,
              ),
              QuickTile(
                icon: Icons.smart_toy_rounded,
                label: 'Kodlama Ajanı',
                subtitle: 'Claude / Codex',
                color: JColors.violet,
                onTap: () => _openJobs(0),
              ),
              QuickTile(
                icon: Icons.play_circle_outline_rounded,
                label: 'Görevler',
                subtitle: 'analyze • test • build',
                color: JColors.ok,
                onTap: () => _openJobs(1),
              ),
              QuickTile(
                icon: Icons.monitor_rounded,
                label: 'PC Ekranı',
                subtitle: 'Canlı görüntü',
                color: ChatPalette.accent,
                onTap: _screenshot,
              ),
              QuickTile(
                icon: Icons.content_paste_go_rounded,
                label: 'Ortak Pano',
                subtitle: 'PC ⇄ Telefon',
                color: JColors.warn,
                onTap: _clipboard,
              ),
              QuickTile(
                icon: Icons.system_update_rounded,
                label: 'APK Güncelle',
                subtitle: c.pcInfo?.apk == null ? 'PC\'den kur' : formatAgo(c.pcInfo!.apk!.modified),
                color: JColors.ok,
                onTap: _apkUpdate,
              ),
              QuickTile(
                icon: Icons.upload_file_rounded,
                label: 'Dosya Gönder',
                subtitle: 'Telefon → PC',
                color: const Color(0xFFF472B6),
                onTap: _upload,
              ),
              QuickTile(
                icon: Icons.history_rounded,
                label: 'İşler',
                subtitle: 'Çalışan/biten',
                color: JColors.muted,
                onTap: () => _openJobs(2),
              ),
              QuickTile(
                icon: Icons.key_rounded,
                label: 'API Yenile',
                subtitle: 'CLI Proxy',
                color: JColors.accent,
                onTap: _importing ? null : () => _importKeys(),
              ),
            ],
          ),
          SectionTitle(
            'Projeler (Kaynak Kodlar)',
            icon: Icons.folder_copy_rounded,
            trailing: IconButton(
              tooltip: 'Yenile',
              onPressed: c.refreshPcInfo,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ),
          if ((c.pcInfo?.roots ?? const []).isEmpty)
            GlassCard(
              child: Text(
                c.pcOnline == false
                    ? 'PC\'ye şu an ulaşılamıyor. Köprünün açık olduğundan emin olun.'
                    : 'Projeler yükleniyor…',
                style:  TextStyle(color: JColors.muted),
              ),
            ),
          for (final r in c.pcInfo?.roots ?? const <PcRoot>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onTap: () => _openFiles(r),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: JColors.warn.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:  Icon(Icons.folder_special_rounded, color: JColors.warn),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            r.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:  TextStyle(fontSize: 11.5, color: JColors.dim),
                          ),
                        ],
                      ),
                    ),
                     Icon(Icons.chevron_right_rounded, color: JColors.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHostCard() {
    final info = c.pcInfo;
    final s = c.settings;
    final online = c.pcOnline;
    return GlassCard(
      glow: online == false ? JColors.bad : JColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [ChatPalette.accent, ChatPalette.accent]),
                  boxShadow: [BoxShadow(color: JColors.primary.withValues(alpha: 0.35), blurRadius: 14)],
                ),
                child: const Icon(Icons.laptop_windows_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            info?.host ?? (s.pcBridgeName.isEmpty ? 'Windows PC' : s.pcBridgeName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusDot(ok: online),
                      ],
                    ),
                    Text(
                      s.pcBridgeUrl,
                      style:  TextStyle(fontSize: 11.5, color: JColors.muted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'refresh') {
                    await c.refreshPcInfo();
                  } else if (v == 'unpair') {
                    await c.unpairPc();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'refresh', child: Text('Durumu yenile')),
                  PopupMenuItem(value: 'unpair', child: Text('Eşleşmeyi kaldır')),
                ],
              ),
            ],
          ),
          if (c.pcStatus != null) ...[
            const SizedBox(height: 8),
            Text(c.pcStatus!, style:  TextStyle(color: JColors.bad, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: c.refreshPcInfo,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Tekrar dene'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await c.unpairPc();
                  },
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text('Yeniden eşleş'),
                ),
              ],
            ),
          ],
          if (info != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill('RAM %${info.ramUsedPct} / ${info.ramTotalGb.toStringAsFixed(0)} GB', icon: Icons.memory_rounded),
                Pill('Disk ${info.diskFreeGb.toStringAsFixed(0)} GB boş', icon: Icons.storage_rounded, color: JColors.violet),
                if (info.batteryPct != null)
                  Pill('Pil %${info.batteryPct}${info.charging ? ' ⚡' : ''}', icon: Icons.battery_std_rounded, color: JColors.ok),
                Pill('Açık ${(info.uptimeMin / 60).toStringAsFixed(1)} sa', icon: Icons.schedule_rounded, color: JColors.muted),
                for (final t in info.tools.entries)
                  Pill(
                    t.key,
                    icon: t.value ? Icons.check_rounded : Icons.close_rounded,
                    color: t.value ? JColors.ok : JColors.dim,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeysCard() {
    final s = c.settings;
    final b = c.lastImportedBundle;
    final hasCloud = s.azureSpeechKey.isNotEmpty || s.geminiTtsKey.isNotEmpty || s.openAiTtsKey.isNotEmpty;
    return GlassCard(
      glow: JColors.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               Icon(Icons.vpn_key_rounded, color: JColors.violet),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'CLI Proxy API Anahtarları',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              if (hasCloud)  Pill('Bulut ses hazır', icon: Icons.graphic_eq_rounded, color: JColors.ok),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            b == null
                ? 'PC\'deki CLI Proxy API ortamında bulunan proxy, Azure Speech, Gemini ve OpenAI anahtarlarını tek dokunuşla telefona aktarır.'
                : b.summary.join('\n'),
            style:  TextStyle(fontSize: 12.5, color: JColors.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _importing ? null : () => _importKeys(),
              icon: _importing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_for_offline_rounded),
              label: Text(_importing ? 'Alınıyor…' : 'API\'leri PC\'den Al'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairing() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [ChatPalette.accent, ChatPalette.accent]),
                  boxShadow: [BoxShadow(color: JColors.primary.withValues(alpha: 0.4), blurRadius: 30)],
                ),
                child: const Icon(Icons.laptop_windows_rounded, size: 38, color: Colors.white),
              ),
              const SizedBox(height: 14),
              const Text(
                'Windows PC\'ye Bağlan',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
               Text(
                'PC\'deki kaynak kodlarını gez, düzenle, AI ile değiştir; Claude Code / Codex ajanlarını çalıştır; '
                'CLI Proxy API anahtarlarını alıp bulut seslerini etkinleştir.',
                textAlign: TextAlign.center,
                style: TextStyle(color: JColors.muted, height: 1.45, fontSize: 13),
              ),
            ],
          ),
        ),
        const SectionTitle('Nasıl bağlanılır?', icon: Icons.route_rounded),
        const _Step(n: 1, text: 'PC\'de Masaüstü\\JARVIS\\start-pc-bridge.bat dosyasını çalıştırın (PIN orada görünür).'),
        const _Step(n: 2, text: 'Telefon ve PC aynı Wi‑Fi\'da ya da telefon hotspot\'unda olsun.'),
        const _Step(n: 3, text: '"PC\'yi Bul"a dokunun, çıkan bilgisayarı seçip 6 haneli PIN\'i girin.'),
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: c.pcScanning || _pairing ? null : c.discoverPcs,
            icon: c.pcScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar_rounded),
            label: Text(
              c.pcScanning ? 'Ağ taranıyor… %${(c.pcScanProgress * 100).round()}' : 'PC\'yi Bul',
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (c.pcScanning) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: c.pcScanProgress),
        ],
        if (!c.pcScanning && c.pcFound.isEmpty && c.pcScanProgress >= 1)
           Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Ağda PC Köprüsü bulunamadı. Köprünün çalıştığından emin olun ya da adresi aşağıya elle yazın.',
              style: TextStyle(color: JColors.warn, fontSize: 12.5),
            ),
          ),
        for (final d in c.pcFound)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GlassCard(
              glow: JColors.ok,
              onTap: _pairing ? null : () => _pairFlow(d.url, hostLabel: d.host),
              child: Row(
                children: [
                   Icon(Icons.computer_rounded, color: JColors.ok),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.host, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${d.url} • köprü v${d.version}', style:  TextStyle(fontSize: 11.5, color: JColors.muted)),
                      ],
                    ),
                  ),
                   Pill('Eşleş', icon: Icons.link_rounded, color: JColors.ok),
                ],
              ),
            ),
          ),
        const SectionTitle('Adresi elle gir', icon: Icons.edit_rounded),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: '192.168.1.20 veya http://192.168.1.20:8765',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _pairing
                  ? null
                  : () async {
                      final url = PcBridgeClient.normalizeUrl(_manualCtrl.text);
                      if (url.isEmpty) return;
                      final info = await PcBridgeClient.ping(url);
                      if (!mounted) return;
                      if (info == null) {
                        showJarvisSnack(context, '$url adresinde PC Köprüsü yanıt vermedi.', error: true);
                        return;
                      }
                      await _pairFlow(url, hostLabel: info.host);
                    },
              child: const Text('Bağlan'),
            ),
          ],
        ),
        if (_pairing) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;

  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: JColors.primary.withValues(alpha: 0.15),
              border: Border.all(color: JColors.primary.withValues(alpha: 0.5)),
            ),
            child: Text('$n', style:  TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: JColors.accent)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  final String host;

  const _PinDialog({required this.host});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: JColors.surface,
      title: Text('${widget.host} ile eşleş'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           Text(
            'PC\'deki köprü penceresinde (veya %USERPROFILE%\\.jarvis-bridge\\PIN.txt) görünen 6 haneli PIN\'i girin.',
            style: TextStyle(fontSize: 12.5, color: JColors.muted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w800),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Eşleş')),
      ],
    );
  }
}

/// Live view of the PC screen (periodic screenshots).
class PcScreenshotScreen extends StatefulWidget {
  final JarvisController controller;

  const PcScreenshotScreen({super.key, required this.controller});

  @override
  State<PcScreenshotScreen> createState() => _PcScreenshotScreenState();
}

class _PcScreenshotScreenState extends State<PcScreenshotScreen> {
  Uint8List? _img;
  String? _err;
  bool _loading = false;
  bool _auto = false;
  Timer? _timer;
  DateTime? _at;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final client = widget.controller.pcClient;
    if (client == null || _loading) return;
    setState(() => _loading = true);
    try {
      final bytes = await client.screenshot();
      if (!mounted) return;
      setState(() {
        _img = bytes;
        _err = null;
        _at = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleAuto() {
    setState(() => _auto = !_auto);
    _timer?.cancel();
    if (_auto) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_at == null ? 'PC Ekranı' : 'PC Ekranı • ${TimeOfDay.fromDateTime(_at!).format(context)}'),
        actions: [
          IconButton(
            tooltip: _auto ? 'Otomatik yenilemeyi durdur' : 'Her 3 sn yenile',
            onPressed: _toggleAuto,
            icon: Icon(_auto ? Icons.pause_circle_rounded : Icons.play_circle_rounded),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _img == null
          ? Center(
              child: _err != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_err!, textAlign: TextAlign.center, style:  TextStyle(color: JColors.bad)),
                    )
                  : const CircularProgressIndicator(),
            )
          : InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.memory(_img!, gaplessPlayback: true)),
            ),
    );
  }
}
