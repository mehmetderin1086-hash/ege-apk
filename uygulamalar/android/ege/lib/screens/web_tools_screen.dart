import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/jarvis_models.dart';
import '../services/device_bridge.dart';
import '../services/web_tools.dart';
import '../state/jarvis_controller.dart';
import '../widgets/markdown_message.dart';
import '../widgets/chat_palette.dart';

Color get _cardColor => ChatPalette.surface;
Color get _borderColor => ChatPalette.border;
Color get _accent => ChatPalette.accent;
Color get _muted => ChatPalette.muted;

BoxDecoration _panelDecoration() => BoxDecoration(
  color: _cardColor,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: _borderColor),
);

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
}

/// Web scraping + web search tab (Araçlar › Web).
class WebScraperTab extends StatefulWidget {
  final JarvisController controller;
  const WebScraperTab({super.key, required this.controller});

  @override
  State<WebScraperTab> createState() => _WebScraperTabState();
}

class _WebScraperTabState extends State<WebScraperTab> {
  final _inputCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  WebPage? _page;
  List<SearchResult> _results = const [];

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _go({bool forceSearch = false}) async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) return;
    FocusScope.of(context).unfocus();
    final url = forceSearch ? null : WebTools.normalizeUrl(input);
    if (url != null && (input.contains('.') || input.startsWith('http'))) {
      await _scrape(url);
    } else {
      await _search(input);
    }
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
    });
    final res = await WebTools.search(
      q,
      client: widget.controller.httpClient,
      limit: 10,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _results = res;
      _error = res.isEmpty ? 'Sonuç bulunamadı.' : null;
    });
  }

  Future<void> _scrape(String url) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final page = await widget.controller.fetchPageCached(url);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (page.ok) {
        _page = page;
      } else {
        _error = page.error;
      }
    });
  }

  String _safeName(String title, String ext) {
    final base = title
        .replaceAll(RegExp(r'[^\w\sçğıöşüÇĞİÖŞÜ-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final cut = base.length > 50 ? base.substring(0, 50) : base;
    return '${cut.isEmpty ? 'jarvis_sayfa' : cut}_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.$ext';
  }

  Future<void> _askAi(WebPage page, String instruction) async {
    final c = widget.controller;
    c.openTab(0);
    await c.sendMessage(
      '$instruction\n${page.finalUrl.isEmpty ? page.url : page.finalUrl}',
    );
  }

  Future<void> _askQuestion(WebPage page) async {
    final ctrl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayfa hakkında soru sor'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Örn: Fiyatlar ne kadar? Ana fikir ne?',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Sor'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (q != null && q.trim().isNotEmpty) {
      await _askAi(page, q.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Web Kazıma & Arama',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: ChatPalette.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bir bağlantı yapıştırın (sayfayı okur, metin/bağlantı/görsel/video çıkarır) veya arama yapın.',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _inputCtrl,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: 'https://... veya arama sorgusu',
                  prefixIcon: const Icon(
                    Icons.travel_explore_rounded,
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Panodan yapıştır',
                    icon: const Icon(Icons.content_paste_rounded, size: 19),
                    onPressed: () async {
                      final d = await Clipboard.getData(Clipboard.kTextPlain);
                      if (d?.text != null) _inputCtrl.text = d!.text!.trim();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _loading ? null : () => _go(),
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text('Sayfayı Oku'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : () => _go(forceSearch: true),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Web\'de Ara'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading || _inputCtrl.text.trim().isEmpty
                        ? null
                        : () async {
                            final q = _inputCtrl.text.trim();
                            final msg = await widget.controller
                                .startDeepResearch(q);
                            if (context.mounted) {
                              _toast(context, msg.replaceAll('**', ''));
                            }
                          },
                    icon: const Icon(Icons.biotech_outlined, size: 18),
                    label: const Text('Derin Araştır'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null && !_loading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '⚠️ $_error',
              style: const TextStyle(color: Color(0xFFFBBF24)),
            ),
          ),
        if (page == null && _results.isNotEmpty && !_loading) ...[
          const SizedBox(height: 12),
          for (final r in _results)
            Card(
              child: ListTile(
                title: Text(
                  r.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${Uri.tryParse(r.url)?.host ?? r.url}\n${r.snippet}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Tarayıcıda aç',
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  onPressed: () => DeviceBridge.openUrl(r.url),
                ),
                onTap: () {
                  _inputCtrl.text = r.url;
                  _scrape(r.url);
                },
              ),
            ),
        ],
        if (page != null && !_loading) ...[
          const SizedBox(height: 12),
          _PageHeader(page: page),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('AI ile Özetle'),
                onPressed: () => _askAi(
                  page,
                  'Bu web sayfasını ayrıntılı, maddeler halinde Türkçe özetle ve önemli noktaları vurgula:',
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.question_answer_outlined, size: 16),
                label: const Text('Soru Sor'),
                onPressed: () => _askQuestion(page),
              ),
              ActionChip(
                avatar: const Icon(Icons.note_add_outlined, size: 16),
                label: const Text('Notlara Ekle'),
                onPressed: () async {
                  final md = page.markdown.length > 12000
                      ? '${page.markdown.substring(0, 12000)}…'
                      : page.markdown;
                  await widget.controller.appendToActiveNote(
                    '${page.title}\n${page.finalUrl}\n\n$md',
                  );
                  if (context.mounted) _toast(context, 'Not defterine eklendi');
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Markdown İndir'),
                onPressed: () async {
                  final saved = await widget.controller.saveTextToDownloads(
                    _safeName(page.title, 'md'),
                    page.markdown,
                  );
                  if (context.mounted) {
                    _toast(
                      context,
                      saved == null
                          ? 'Kaydedilemedi'
                          : 'İndirilenler/Ege klasörüne kaydedildi',
                    );
                  }
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Metni Kopyala'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: page.text));
                  if (context.mounted) _toast(context, 'Metin kopyalandı');
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.share_outlined, size: 16),
                label: const Text('Paylaş'),
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text:
                        '${page.title}\n${page.finalUrl}\n\n${page.description}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ExpandableSection(
            title: 'Okunabilir Metin (${page.text.length} karakter)',
            icon: Icons.subject_rounded,
            initiallyExpanded: true,
            child: MarkdownMessage(
              text: page.markdown.length > 15000
                  ? '${page.markdown.substring(0, 15000)}\n\n…(kısaltıldı)'
                  : (page.markdown.isEmpty
                        ? '(Metin bulunamadı)'
                        : page.markdown),
            ),
          ),
          if (page.media.isNotEmpty)
            _ExpandableSection(
              title: 'Medya & Dosyalar (${page.media.length})',
              icon: Icons.video_library_outlined,
              initiallyExpanded: true,
              child: Column(
                children: [
                  for (final m in page.media)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_kindIcon(m.kind), color: _accent),
                      title: Text(
                        m.label.isEmpty
                            ? WebTools.guessFileName(m.url)
                            : m.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${m.kind} • ${m.source}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        tooltip: 'İndir',
                        icon: const Icon(Icons.download_rounded),
                        onPressed: () async {
                          final msg = await widget.controller.downloadFile(
                            m.url,
                          );
                          if (context.mounted) {
                            _toast(
                              context,
                              msg.replaceAll('**', '').split('\n').first,
                            );
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (page.images.isNotEmpty)
            _ExpandableSection(
              title: 'Görseller (${page.images.length})',
              icon: Icons.image_outlined,
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final img in page.images.take(30))
                    GestureDetector(
                      onTap: () async {
                        final msg = await widget.controller.downloadFile(img);
                        if (context.mounted) {
                          _toast(
                            context,
                            msg.replaceAll('**', '').split('\n').first,
                          );
                        }
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          img,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: ChatPalette.soft,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: _muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (page.links.isNotEmpty)
            _ExpandableSection(
              title: 'Bağlantılar (${page.links.length})',
              icon: Icons.link_rounded,
              child: Column(
                children: [
                  for (final l in page.links.take(80))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l.text.isEmpty ? l.url : l.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        l.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () {
                        _inputCtrl.text = l.url;
                        _scrape(l.url);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, size: 17),
                        onPressed: () => DeviceBridge.openUrl(l.url),
                      ),
                    ),
                ],
              ),
            ),
          if (page.emails.isNotEmpty || page.phones.isNotEmpty)
            _ExpandableSection(
              title: 'İletişim Bilgileri',
              icon: Icons.contact_mail_outlined,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in page.emails)
                    ActionChip(
                      avatar: const Icon(Icons.email_outlined, size: 15),
                      label: Text(e),
                      onPressed: () => DeviceBridge.openUrl('mailto:$e'),
                    ),
                  for (final p in page.phones)
                    ActionChip(
                      avatar: const Icon(Icons.phone_outlined, size: 15),
                      label: Text(p),
                      onPressed: () => DeviceBridge.dialNumber(p),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

IconData _kindIcon(String kind) => switch (kind) {
  'video' => Icons.movie_outlined,
  'audio' => Icons.audiotrack_outlined,
  'image' => Icons.image_outlined,
  _ => Icons.insert_drive_file_outlined,
};

class _PageHeader extends StatelessWidget {
  final WebPage page;
  const _PageHeader({required this.page});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (page.ogImage != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  page.ogImage!,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(width: 0),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.title.isEmpty ? page.url : page.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  page.siteName.isEmpty
                      ? (Uri.tryParse(page.finalUrl)?.host ?? '')
                      : page.siteName,
                  style: TextStyle(fontSize: 11.5, color: _accent),
                ),
                if (page.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    page.description,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: ChatPalette.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${JarvisController.formatBytes(page.byteLength)} • ${page.links.length} bağlantı • ${page.images.length} görsel • ${page.media.length} medya • HTTP ${page.statusCode}',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  const _ExpandableSection({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _panelDecoration(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: _accent, size: 20),
          title: Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [child],
        ),
      ),
    );
  }
}

/// Download manager tab (Araçlar › İndir): files, videos, Termux yt-dlp.
class DownloadsTab extends StatefulWidget {
  final JarvisController controller;
  const DownloadsTab({super.key, required this.controller});

  @override
  State<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<DownloadsTab> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  String _filter = 'all';
  String _search = '';
  String? _lastMessage;
  List<MediaCandidate> _candidates = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.setDownloadPolling(true);
  }

  @override
  void dispose() {
    widget.controller.setDownloadPolling(false);
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function(String url) task) async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _lastMessage = null;
    });
    final msg = await task(url);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastMessage = msg;
    });
  }

  Future<void> _analyze() async {
    final norm = WebTools.normalizeUrl(_urlCtrl.text.trim());
    if (norm == null) return;
    setState(() {
      _busy = true;
      _candidates = const [];
      _lastMessage = null;
    });
    final media = await WebTools.findMedia(
      norm,
      client: widget.controller.httpClient,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _candidates = media;
      _lastMessage = media.isEmpty
          ? 'Bu sayfada doğrudan indirilebilir medya/dosya bulunamadı. Video siteleri için "yt-dlp (Termux)" kullanın.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: _panelDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'İndirme Merkezi',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: ChatPalette.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Dosya, belge, görsel, müzik ve video indirin. Dosyalar İndirilenler/Ege klasörüne kaydedilir.',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText:
                        'https://... (dosya, sayfa veya video bağlantısı)',
                    prefixIcon: const Icon(Icons.link_rounded, size: 20),
                    suffixIcon: IconButton(
                      tooltip: 'Panodan yapıştır',
                      icon: const Icon(Icons.content_paste_rounded, size: 19),
                      onPressed: () async {
                        final d = await Clipboard.getData(Clipboard.kTextPlain);
                        final urls = WebTools.extractUrls(d?.text ?? '');
                        if (urls.isNotEmpty) _urlCtrl.text = urls.first;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run((u) async {
                              final links = WebTools.extractUrls(u);
                              if (links.length <= 1) return c.downloadFile(u);
                              final results = <String>[];
                              for (final link in links.toSet().take(30)) {
                                results.add(await c.downloadFile(link));
                              }
                              return results.join('\n');
                            }),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Dosya İndir'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _run(c.downloadVideo),
                      icon: const Icon(Icons.movie_creation_outlined, size: 18),
                      label: const Text('Video İndir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _analyze,
                      icon: const Icon(Icons.manage_search_rounded, size: 18),
                      label: const Text('Medyayı Bul'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              (u) => c.downloadWithYtDlp(
                                WebTools.normalizeUrl(u) ?? u,
                              ),
                            ),
                      icon: const Icon(Icons.terminal_rounded, size: 18),
                      label: const Text('yt-dlp (Termux)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final u = _urlCtrl.text.trim();
                        if (u.isNotEmpty) DeviceBridge.shareText(u);
                      },
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Paylaş'),
                    ),
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_lastMessage != null) ...[
                  const SizedBox(height: 10),
                  MarkdownMessage(text: _lastMessage!),
                ],
              ],
            ),
          ),
          if (_candidates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _panelDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bulunan medya (${_candidates.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final m in _candidates)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_kindIcon(m.kind), color: _accent),
                      title: Text(
                        m.label.isEmpty
                            ? WebTools.guessFileName(m.url)
                            : m.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        m.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.download_rounded),
                        onPressed: () async {
                          final msg = await c.downloadFile(m.url);
                          if (!mounted) return;
                          setState(() => _lastMessage = msg);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'İndirmeler (${c.downloads.length})',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Yenile',
                onPressed: c.refreshDownloads,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          TextField(
            decoration: const InputDecoration(
              hintText: 'İndirmelerde ara',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final entry in const {
                'all': 'Tümü',
                'running': 'Etkin',
                'successful': 'Tamamlanan',
                'failed': 'Başarısız',
                'paused': 'Duraklatılan',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _filter == entry.key,
                  onSelected: (_) => setState(() => _filter = entry.key),
                ),
              ActionChip(
                label: const Text('İndirme ayarları'),
                avatar: const Icon(Icons.tune, size: 16),
                onPressed: () => c.openTab(4),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (c.downloads.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Henüz indirme yok. Sohbette "https://... indir" veya "video indir <bağlantı>" diyebilirsiniz.',
                style: TextStyle(color: _muted, fontSize: 12.5),
              ),
            ),
          for (final d in c.downloads.where(
            (d) =>
                d.title.toLowerCase().contains(_search) &&
                (_filter == 'all' ||
                    d.status == _filter ||
                    (_filter == 'running' && d.status == 'pending')),
          ))
            _DownloadTile(item: d, controller: c),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: _panelDecoration(),
            child: const MarkdownMessage(
              text:
                  '**Video siteleri (YouTube, Instagram, TikTok, X)** doğrudan dosya bağlantısı vermez. '
                  'Telefona [Termux](https://f-droid.org/packages/com.termux/) kurup şu komutları çalıştırırsanız Ege yt-dlp ile otomatik indirir:\n\n'
                  '```\npkg install python ffmpeg\npip install yt-dlp\ntermux-setup-storage\necho "allow-external-apps=true" >> ~/.termux/termux.properties\n```\n'
                  'Yalnızca indirme hakkınız olan içerikleri indirin.',
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadItem item;
  final JarvisController controller;
  const _DownloadTile({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (item.status) {
      'successful' => ('Tamamlandı', const Color(0xFF34D399)),
      'failed' => ('Başarısız', const Color(0xFFF87171)),
      'paused' => ('Duraklatıldı', const Color(0xFFFBBF24)),
      'running' => ('İndiriliyor', _accent),
      _ => ('Bekliyor', _muted),
    };
    final sizeText = item.totalBytes > 0
        ? '${JarvisController.formatBytes(item.downloadedBytes)} / ${JarvisController.formatBytes(item.totalBytes)}'
        : JarvisController.formatBytes(item.downloadedBytes);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _kindIcon(WebTools.kindForUrl(item.title)),
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (item.isDone)
                  IconButton(
                    tooltip: 'Aç',
                    icon: const Icon(Icons.open_in_new_rounded, size: 19),
                    onPressed: () => controller.openDownload(item.id),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'İndirme işlemleri',
                  onSelected: (action) async {
                    if (action == 'remove') {
                      await controller.removeDownload(item.id);
                    } else if (action == 'share') {
                      await DeviceBridge.shareManagedDownload(item.id);
                    } else if (item.managed) {
                      await DeviceBridge.managedDownloadControl(
                        item.id,
                        action,
                      );
                      await controller.refreshDownloads();
                    } else if (action == 'resume') {
                      await controller.downloadFile(
                        item.url,
                        fileName: item.title,
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    if (item.managed &&
                        (item.status == 'running' || item.status == 'pending'))
                      const PopupMenuItem(
                        value: 'pause',
                        child: Text('Duraklat'),
                      ),
                    if (item.status == 'paused' || item.isFailed)
                      const PopupMenuItem(
                        value: 'resume',
                        child: Text('Devam et / yeniden dene'),
                      ),
                    if (item.managed && item.isDone)
                      const PopupMenuItem(
                        value: 'share',
                        child: Text('Dosyayı paylaş'),
                      ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(item.isDone ? 'Dosyayı sil' : 'İptal et'),
                    ),
                  ],
                ),
              ],
            ),
            if (!item.isDone && !item.isFailed)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2, bottom: 4),
                child: LinearProgressIndicator(value: item.progress),
              ),
            Text(
              '$label • $sizeText${item.speed > 0 ? ' • ${JarvisController.formatBytes(item.speed)}/sn' : ''}${item.reason.isNotEmpty ? ' • ${item.reason}' : ''}',
              style: TextStyle(fontSize: 11.5, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
