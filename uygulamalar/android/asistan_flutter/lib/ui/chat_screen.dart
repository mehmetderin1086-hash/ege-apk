import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/asistan_models.dart';
import '../services/asistan_controller.dart';
import 'animations_3d.dart';
import 'theme_asistan.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    required this.onOpenDrawer,
    required this.onSwitchTab,
  });

  final AsistanController controller;
  final VoidCallback onOpenDrawer;
  final void Function(int index) onSwitchTab;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showSlashPalette = false;
  String _slashFilter = '';

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final txt = _inputController.text;
    if (txt.startsWith('/') && !txt.contains(' ')) {
      setState(() {
        _showSlashPalette = true;
        _slashFilter = txt.toLowerCase();
      });
    } else if (_showSlashPalette) {
      setState(() {
        _showSlashPalette = false;
        _slashFilter = '';
      });
    }
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitMessage() {
    if (widget.controller.isGenerating) return;
    final txt = _inputController.text.trim();
    if (txt.isEmpty && widget.controller.pendingAttachments.isEmpty) return;
    _inputController.clear();
    setState(() {
      _showSlashPalette = false;
    });
    widget.controller.sendMessage(txt);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 220), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final preset = c.themePreset;
    final thread = c.activeThread;

    return Column(
      children: [
        _buildClaudeCodeTopBar(context, c, preset),

        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
              itemCount: thread.messages.length,
              itemBuilder: (context, index) {
                final msg = thread.messages[index];
                return _buildClaudeCodeMessageBlock(context, c, msg, preset);
              },
            ),
          ),
        ),
        if (_showSlashPalette) _buildSlashCommandOverlay(c, preset),
        if (c.isGenerating) _buildGeneratingIndicator(c, preset),
        if (c.pendingAttachments.isNotEmpty) _buildAttachmentStrip(c, preset),
        SafeArea(top: false, child: _buildComposerBar(context, c, preset)),
      ],
    );
  }

  // ─── CLAUDE CODE TOP HEADER BAR ──────────────────────────────────────────

  Widget _buildClaudeCodeTopBar(
    BuildContext context,
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: widget.onOpenDrawer,
              tooltip: 'Menü ve sohbetler',
              icon: const Icon(Icons.menu),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _showModelSelectorSheet(context, c),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Asistan',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${c.proxyOnline ? "Bağlı" : "Bağlantı yok"} · ${c.selectedModelId == 'auto' ? 'Otomatik model' : c.selectedModelInfo.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: c.createNewThread,
              tooltip: 'Yeni sohbet',
              icon: const Icon(Icons.edit_square),
            ),
            PopupMenuButton<String>(
              tooltip: 'Sohbet seçenekleri',
              onSelected: (value) {
                if (value == 'reading') _showReadingAndPersonaSheet(context, c);
                if (value == 'theme') _showThemeAndWallpaperSheet(context, c);
                if (value == 'proxy') _showManualProxyDialog(context, c);
                if (value != 'examples') return;
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SizedBox(
                    height: MediaQuery.sizeOf(context).height * .75,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildCliProxyQuickConnectBanner(context, c, preset),
                          _buildEasyStarterDashboard(context, c, preset),
                        ],
                      ),
                    ),
                  ),
                );
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reading', child: Text('Yazı boyutu')),
                PopupMenuItem(value: 'theme', child: Text('Görünüm')),
                PopupMenuItem(value: 'proxy', child: Text('Bağlantı ayarları')),
                PopupMenuItem(
                  value: 'examples',
                  child: Text('Araçlar ve örnekler'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── SIRI CLIPROXY 1-TAP CONNECTION & KEY RECOVERY BANNER ────────────────

  Widget _buildCliProxyQuickConnectBanner(
    BuildContext context,
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    final isNeedsKey = c.proxyAuthStatus == ProxyAuthStatus.needsKey;
    final bannerColor = isNeedsKey
        ? const Color(0xFFF59E0B)
        : const Color(0xFF38BDF8);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.14),
        border: Border(
          bottom: BorderSide(color: bannerColor.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isNeedsKey ? Icons.vpn_key_rounded : Icons.router_rounded,
            color: bannerColor,
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isNeedsKey
                  ? 'Siri CLIProxy (8317) açık • Anahtarı bağlayın:'
                  : 'Siri CLIProxy (8317) bağlantısı:',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _bannerMiniBtn(
            label: '📋 Panodan Yapıştır',
            color: const Color(0xFF10B981),
            onTap: () async {
              final ok = await c.pasteKeyFromClipboardAndConnect();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? '✅ CLIProxy bağlandı! (${c.availableModels.length} model aktif)'
                          : 'Panodaki anahtar denendi. CLIProxy üzerinden anahtarı kopyalayıp tekrar dokunun.',
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 5),
          _bannerMiniBtn(
            label: '🚀 CLIProxy Aç',
            color: bannerColor,
            onTap: () async {
              final opened = await c.openCliProxyApp();
              if (!opened && context.mounted) {
                _showManualProxyDialog(context, c);
              }
            },
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showManualProxyDialog(context, c),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.settings_ethernet_rounded,
                size: 16,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerMiniBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ─── EASY 1-TAP STARTER DASHBOARD (CLEAN, LARGE VISUAL CARDS) ────────────

  Widget _buildEasyStarterDashboard(
    BuildContext context,
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    final isFreshThread = c.activeThread.messages.length <= 1;

    if (!isFreshThread) {
      // When chatting, show a clean, unobtrusive 1-line quick bar
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _quickCommandPill(
                icon: Icons.cloud_download_rounded,
                label: '📥 Web Kazıma & Toplu İndir',
                color: const Color(0xFF38BDF8),
                onTap: () => widget.onSwitchTab(2),
              ),
              _quickCommandPill(
                icon: Icons.science_rounded,
                label: '🔬 Derin Araştırma',
                color: const Color(0xFF10B981),
                onTap: () => _showQuickPromptDialog(
                  context,
                  c,
                  title: '🔬 Çok Kaynaklı Derin Araştırma',
                  hint: 'Araştırılacak konuyu yazın (örn: Kuantum bilgisayarlar, Yapay zeka tarihi)...',
                  prefix:
                      'Derin araştırma yap ve kaynaklarıyla rapor hazırla: ',
                  mode: WorkMode.research,
                ),
              ),
              _quickCommandPill(
                icon: Icons.folder_zip_rounded,
                label: '📄 Ofis & Resim Üret',
                color: const Color(0xFFF59E0B),
                onTap: () => widget.onSwitchTab(3),
              ),
              _quickCommandPill(
                icon: Icons.graphic_eq_rounded,
                label: '🎙️ Canlı Ses',
                color: const Color(0xFFFF2E93),
                onTap: () => widget.onSwitchTab(1),
              ),
            ],
          ),
        ),
      );
    }

    final actions =
        <
          ({
            IconData icon,
            String title,
            String subtitle,
            Color color,
            VoidCallback onTap,
          })
        >[
          (
            icon: Icons.science_rounded,
            title: '🔬 Derin Araştırma',
            subtitle: 'Vikipedi + Akademik + Kitap',
            color: const Color(0xFF10B981),
            onTap: () => _showQuickPromptDialog(
              context,
              c,
              title: '🔬 Çok Kaynaklı Derin Araştırma',
              hint: 'Hangi konuyu derinlemesine araştırayım? (örn: Türkiye ekonomisi, Yapay zeka mimarileri)...',
              prefix: 'Derin araştırma yap ve detaylı rapor oluştur: ',
              mode: WorkMode.research,
            ),
          ),
          (
            icon: Icons.cloud_download_rounded,
            title: '📥 İndir & Web Kazı',
            subtitle: 'Resim, Video, Ses, Bulk İndir',
            color: const Color(0xFF38BDF8),
            onTap: () => widget.onSwitchTab(2),
          ),
          (
            icon: Icons.description_rounded,
            title: '📄 Tüm Ofis Dosyaları',
            subtitle: 'PDF, Word, Excel, Sunum',
            color: const Color(0xFFF59E0B),
            onTap: () => _showQuickPromptDialog(
              context,
              c,
              title: '📄 Tüm Ofis Dosyalarını Oluştur (PDF + Word + Excel + Sunum)',
              hint: 'Belge konusunu yazın (örn: Şirket Bütçe Planı, Kira Sözleşmesi, Ders Özeti)...',
              prefix:
                  'Tüm ofis dosyalarını oluştur (PDF, Word, Excel, Sunum): ',
              mode: WorkMode.office,
            ),
          ),
          (
            icon: Icons.library_music_rounded,
            title: '🎵 Ses Dosyası Üret',
            subtitle: 'MP3 / WAV Ses Kaydı İndir',
            color: const Color(0xFFA855F7),
            onTap: () => _showQuickPromptDialog(
              context,
              c,
              title: '🎵 Ses Dosyası (MP3 / WAV) Oluştur & İndir',
              hint: 'Hangi konuda sesli anlatım veya ses dosyası hazırlayayım?...',
              prefix: 'Detaylı anlat ve ses dosyası olarak indir: ',
              mode: WorkMode.auto,
            ),
          ),
          (
            icon: Icons.palette_rounded,
            title: '🎨 Yapay Zeka Resim',
            subtitle: 'Görsel Çiz & Galeriye İndir',
            color: const Color(0xFFEC4899),
            onTap: () => _showQuickPromptDialog(
              context,
              c,
              title: '🎨 Yapay Zeka Resim Çiz & İndir',
              hint: 'Çizilecek resmi tarif edin (örn: Geleceğin İstanbul silüeti)...',
              prefix: 'Görsel üret: ',
              mode: WorkMode.image,
            ),
          ),
          (
            icon: Icons.graphic_eq_rounded,
            title: '🎙️ Canlı Sesli Sohbet',
            subtitle: 'Gemini / ChatGPT / Claude Live',
            color: const Color(0xFFFF2E93),
            onTap: () => widget.onSwitchTab(1),
          ),
        ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: actions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.35,
        ),
        itemBuilder: (context, idx) {
          final a = actions[idx];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: a.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xE60B1224),
                border: Border.all(
                  color: a.color.withValues(alpha: 0.5),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: a.color.withValues(alpha: 0.18),
                    ),
                    child: Icon(a.icon, color: a.color, size: 20),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
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

  void _showQuickPromptDialog(
    BuildContext context,
    AsistanController c, {
    required String title,
    required String hint,
    required String prefix,
    required WorkMode mode,
  }) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.themePreset.surfaceBg,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.themePreset.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final val = ctrl.text.trim();
              Navigator.pop(ctx);
              if (val.isNotEmpty) {
                c.setWorkMode(mode);
                c.sendMessage('$prefix$val', overrideMode: mode);
                _scrollToBottom();
              }
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text(
              'Başlat',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickCommandPill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xCC0B1120),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CLAUDE CODE WIDE READING MESSAGE BLOCK ──────────────────────────────

  Widget _buildClaudeCodeMessageBlock(
    BuildContext context,
    AsistanController c,
    ChatMessage msg,
    AsistanThemePreset preset,
  ) {
    final isUser = msg.role == 'user';
    final accentColor = isUser
        ? preset.primary
        : (msg.modelUsed.toLowerCase().contains('claude')
              ? const Color(0xFFF59E0B)
              : (msg.modelUsed.toLowerCase().contains('gpt')
                    ? const Color(0xFF10B981)
                    : preset.primary));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(
        horizontal: c.wideReadingMode ? 12 : 14,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xF0626972) : const Color(0xF050565E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Claude Code Terminal-Style Header Bar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUser ? Icons.person_rounded : Icons.terminal_rounded,
                      size: 13,
                      color: accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isUser ? 'KULLANICI' : msg.modelUsed.toUpperCase(),
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (!isUser)
                Text(
                  msg.workMode.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10.5,
                  ),
                ),
              const Spacer(),
              Text(
                '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),

          // Collapsible Thinking / Reasoning Trace
          if (msg.reasoningText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: ExpansionTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                leading: const Icon(
                  Icons.psychology_rounded,
                  color: Color(0xFFF59E0B),
                  size: 16,
                ),
                title: const Text(
                  '▸ Claude Code Düşünce & Muhakeme Zinciri',
                  style: TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                children: [
                  Text(
                    msg.reasoningText,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: c.chatFontSize - 2,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Tool Call Traces (Claude Code Terminal Steps)
          if (msg.toolTraces.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: msg.toolTraces.map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 13,
                        color: Color(0xFF34D399),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '⚡ ${t.title}: ${t.outputSummary}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD1FAE5),
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // Rich Claude Code Content (Formatted Markdown + Dedicated Code Terminals)
          const SizedBox(height: 9),
          _buildRichClaudeCodeContent(context, c, msg.text, preset),

          // Arena Candidates (Multi-Model Council Comparison)
          if (msg.arenaCandidates.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '🏛️ Model Konseyi Bireysel Yanıtları:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...msg.arenaCandidates.map((cand) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: ExpansionTile(
                  dense: true,
                  title: Text(
                    '${cand.modelName} (${cand.provider}) • ${cand.latencyMs}ms',
                    style: TextStyle(
                      color: preset.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.all(10),
                  children: [
                    Text(
                      cand.response,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: c.chatFontSize - 1,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          // Generated Artifacts (PDF, DOCX, XLSX, PPTX, AI Images)
          if (msg.artifacts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...msg.artifacts.map((art) => _buildArtifactCard(c, art, preset)),
          ],

          // Web Citations [1], [2]
          if (msg.citations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: msg.citations.map((cit) {
                return ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(
                    radius: 10,
                    backgroundColor: preset.primary,
                    child: Text(
                      '${cit.index}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  label: Text(
                    cit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  onPressed: () {
                    c.invokeNative('openAppOrUrl', {
                      'target': cit.title,
                      'url': cit.url,
                    });
                  },
                );
              }).toList(),
            ),
          ],

          // Per-Message 1-Tap Office, Audio & Action Bar
          if (!isUser) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Yanıt seçenekleri',
                    style: TextStyle(fontSize: 12),
                  ),
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _miniActionButton(
                          icon: Icons.picture_as_pdf_rounded,
                          label: '📕 PDF İndir',
                          color: const Color(0xFFEF4444),
                          onTap: () => _quickExportMessage(
                            context,
                            c,
                            msg,
                            'pdf',
                            'PDF',
                          ),
                        ),
                        _miniActionButton(
                          icon: Icons.description_rounded,
                          label: '📘 Word İndir',
                          color: const Color(0xFF3B82F6),
                          onTap: () => _quickExportMessage(
                            context,
                            c,
                            msg,
                            'docx',
                            'Word (DOCX)',
                          ),
                        ),
                        _miniActionButton(
                          icon: Icons.table_chart_rounded,
                          label: '📊 Excel İndir',
                          color: const Color(0xFF10B981),
                          onTap: () => _quickExportMessage(
                            context,
                            c,
                            msg,
                            'xlsx',
                            'Excel (XLSX)',
                          ),
                        ),
                        _miniActionButton(
                          icon: Icons.slideshow_rounded,
                          label: '📽️ Sunum İndir',
                          color: const Color(0xFFF59E0B),
                          onTap: () => _quickExportMessage(
                            context,
                            c,
                            msg,
                            'pptx',
                            'PowerPoint (PPTX)',
                          ),
                        ),
                        _miniActionButton(
                          icon: Icons.folder_zip_rounded,
                          label: '📦 Tüm Ofis Paketi',
                          color: const Color(0xFF00E5FF),
                          onTap: () async {
                            final list = await c.createAllOfficeFormatsPack(
                              title: c.activeThread.title,
                              content: msg.text,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '✅ Tüm Ofis Paketi (${list.length} dosya: PDF, Word, Excel, Sunum, CSV, HTML, Ses) İndirilenler/Asistan klasörüne kaydedildi!',
                                ),
                              ),
                            );
                          },
                        ),
                        _miniActionButton(
                          icon: Icons.library_music_rounded,
                          label: '🎵 Ses İndir',
                          color: const Color(0xFFA855F7),
                          onTap: () async {
                            final art = await c.createAndDownloadAudioFile(
                              msg.text,
                              title: c.activeThread.title,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  art != null
                                      ? '✅ Ses dosyası (${art.format.toUpperCase()}) İndirilenler/Asistan/Sesler klasörüne kaydedildi!'
                                      : '⚠️ Ses dosyası oluşturulamadı.',
                                ),
                                action: art != null
                                    ? SnackBarAction(
                                        label: 'Aç',
                                        onPressed: () => c.openArtifact(art),
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                        _miniActionButton(
                          icon: Icons.volume_up_rounded,
                          label: '🔊 Dinle',
                          color: const Color(0xFF38BDF8),
                          onTap: () => c.speakText(msg.text),
                        ),
                        _miniActionButton(
                          icon: Icons.autorenew_rounded,
                          label: '🔄 Başka Model',
                          color: const Color(0xFFFBBF24),
                          onTap: () =>
                              _showRegenerateWithModelSheet(context, c, msg),
                        ),
                        _miniActionButton(
                          icon: Icons.copy_rounded,
                          label: '📋 Kopyala',
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: msg.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Yanıt panoya kopyalandı'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── CLAUDE CODE RICH MARKDOWN & CODE BLOCK PARSER ───────────────────────

  Widget _buildRichClaudeCodeContent(
    BuildContext context,
    AsistanController c,
    String rawText,
    AsistanThemePreset preset,
  ) {
    final codeRegex = RegExp(r'```([a-zA-Z0-9_+-]*)\n?([\s\S]*?)```');
    final matches = codeRegex.allMatches(rawText).toList();

    if (matches.isEmpty) {
      return _buildFormattedProse(rawText, c.chatFontSize);
    }

    final widgets = <Widget>[];
    int lastEnd = 0;

    for (final m in matches) {
      if (m.start > lastEnd) {
        final prose = rawText.substring(lastEnd, m.start).trim();
        if (prose.isNotEmpty) {
          widgets.add(_buildFormattedProse(prose, c.chatFontSize));
          widgets.add(const SizedBox(height: 8));
        }
      }
      final lang = (m.group(1) ?? '').trim().isEmpty
          ? 'code'
          : m.group(1)!.trim();
      final code = (m.group(2) ?? '').trimRight();
      widgets.add(_buildClaudeCodeTerminalBox(context, c, lang, code, preset));
      widgets.add(const SizedBox(height: 8));
      lastEnd = m.end;
    }

    if (lastEnd < rawText.length) {
      final tail = rawText.substring(lastEnd).trim();
      if (tail.isNotEmpty) {
        widgets.add(_buildFormattedProse(tail, c.chatFontSize));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildFormattedProse(String text, double fontSize) {
    final lines = text.split('\n');
    final spans = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      if (trimmed.startsWith('### ') ||
          trimmed.startsWith('## ') ||
          trimmed.startsWith('# ')) {
        final cleanHeading = trimmed.replaceFirst(RegExp(r'^#{1,4}\s*'), '');
        spans.add(
          TextSpan(
            text: '${i > 0 ? "\n" : ""}$cleanHeading\n',
            style: TextStyle(
              color: const Color(0xFFFBBF24),
              fontSize: fontSize + 1.5,
              fontWeight: FontWeight.w800,
              height: 1.55,
            ),
          ),
        );
      } else {
        spans.addAll(_parseInlineBoldAndCode(line, fontSize));
        if (i < lines.length - 1) {
          spans.add(const TextSpan(text: '\n'));
        }
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        color: const Color(0xFFF1F5F9),
        fontSize: fontSize,
        height: 1.56,
      ),
    );
  }

  List<InlineSpan> _parseInlineBoldAndCode(String line, double fontSize) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');
    int lastIdx = 0;

    for (final m in pattern.allMatches(line)) {
      if (m.start > lastIdx) {
        spans.add(TextSpan(text: line.substring(lastIdx, m.start)));
      }
      final token = m.group(0)!;
      if (token.startsWith('**') && token.endsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      } else if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(
          TextSpan(
            text: ' ${token.substring(1, token.length - 1)} ',
            style: TextStyle(
              color: const Color(0xFF38BDF8),
              backgroundColor: const Color(0xFF1E293B),
              fontFamily: 'monospace',
              fontSize: fontSize - 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }
      lastIdx = m.end;
    }

    if (lastIdx < line.length) {
      spans.add(TextSpan(text: line.substring(lastIdx)));
    }
    return spans;
  }

  Widget _buildClaudeCodeTerminalBox(
    BuildContext context,
    AsistanController c,
    String language,
    String code,
    AsistanThemePreset preset,
  ) {
    final lineCount = code.split('\n').length;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF050811),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 14,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 6),
                Text(
                  '${language.toUpperCase()} • $lineCount satır',
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kod panoya kopyalandı')),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: Colors.white70,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Kopyala',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    c.canvasTitle = 'Claude Code ($language)';
                    c.canvasContent = code;
                    widget.onSwitchTab(3);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.open_in_full_rounded,
                          size: 13,
                          color: Color(0xFF00E5FF),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Tuvalde Aç',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(
              code,
              style: TextStyle(
                color: const Color(0xFFE2E8F0),
                fontSize: c.chatFontSize - 1.5,
                fontFamily: 'monospace',
                height: 1.48,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _quickExportMessage(
    BuildContext context,
    AsistanController c,
    ChatMessage msg,
    String format,
    String label,
  ) async {
    final art = await c.exportCanvasAsDocument(
      title: c.activeThread.title,
      content: msg.text,
      format: format,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ $label indirildi: İndirilenler/Asistan/Belgeler (${art.title}.${art.format})',
        ),
        action: SnackBarAction(
          label: 'Aç',
          onPressed: () => c.openArtifact(art),
        ),
      ),
    );
  }

  void _showSuperToolsSheet(BuildContext context, AsistanController c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.themePreset.surfaceBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final tools =
            <
              ({
                IconData icon,
                String title,
                String subtitle,
                Color color,
                VoidCallback onTap,
              })
            >[
              (
                icon: Icons.attach_file_rounded,
                title: '📎 Telefondan Dosya / Resim Ekle',
                subtitle: 'Sohbete belge, fotoğraf veya dosya yükle',
                color: const Color(0xFF38BDF8),
                onTap: () {
                  Navigator.pop(ctx);
                  c.pickAttachments();
                },
              ),
              (
                icon: Icons.cloud_download_rounded,
                title: '📥 Evrensel İndirici & Web Kazıma (Bulk İndir)',
                subtitle:
                    'Siteden veya konudan toplu resim, video, ses ve PDF indir',
                color: const Color(0xFF10B981),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onSwitchTab(2);
                },
              ),
              (
                icon: Icons.science_rounded,
                title: '🔬 Çok Kaynaklı Derin Araştırma Yap',
                subtitle: 'Vikipedi + Akademik Makaleler + Kitaplar ile kaynaklı rapor',
                color: const Color(0xFF00E5FF),
                onTap: () {
                  Navigator.pop(ctx);
                  _showQuickPromptDialog(
                    context,
                    c,
                    title: '🔬 Çok Kaynaklı Derin Araştırma',
                    hint: 'Araştırılacak konuyu yazın...',
                    prefix:
                        'Derin araştırma yap ve kaynaklarıyla rapor hazırla: ',
                    mode: WorkMode.research,
                  );
                },
              ),
              (
                icon: Icons.folder_zip_rounded,
                title:
                    '📄 Tüm Ofis Dosyalarını Oluştur (PDF, Word, Excel, Sunum)',
                subtitle: 'Tek tuşla tüm ofis paketini İndirilenler/Asistan klasörüne kaydet',
                color: const Color(0xFFF59E0B),
                onTap: () {
                  Navigator.pop(ctx);
                  _showQuickPromptDialog(
                    context,
                    c,
                    title: '📄 Tüm Ofis Dosyalarını Oluştur',
                    hint: 'Rapor, tablo veya sunum konusunu yazın...',
                    prefix: 'Tüm ofis dosyalarını oluştur (PDF, Word, Excel, Sunum): ',
                    mode: WorkMode.office,
                  );
                },
              ),
              (
                icon: Icons.hub_rounded,
                title: '🏛️ 3x Model Konseyi (Claude + GPT + Gemini)',
                subtitle:
                    'Sorunuzu aynı anda 3 büyük modele sorup karşılaştırın',
                color: const Color(0xFFEC4899),
                onTap: () {
                  Navigator.pop(ctx);
                  _showQuickPromptDialog(
                    context,
                    c,
                    title: '🏛️ 3x Model Konseyi (Claude + GPT + Gemini)',
                    hint: '3 modelin karşılaştırmalı yanıtlamasını istediğiniz soruyu yazın...',
                    prefix: '',
                    mode: WorkMode.council,
                  );
                },
              ),
              (
                icon: Icons.waves_rounded,
                title: '🌍 Son Depremler • 🌤️ Hava Durumu • 💱 Canlı Döviz',
                subtitle: 'Canlı Türkiye depremleri, meteoroloji ve merkez bankası kurları',
                color: const Color(0xFFEF4444),
                onTap: () {
                  Navigator.pop(ctx);
                  c.sendMessage(
                    'Türkiye son depremler, İstanbul hava durumu ve canlı döviz kurlarını göster.',
                  );
                },
              ),
            ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '➕ Süper Araçlar & Hızlı İşlemler',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: tools.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final t = tools[i];
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: t.color.withValues(alpha: 0.35),
                          ),
                        ),
                        tileColor: Colors.white.withValues(alpha: 0.04),
                        leading: CircleAvatar(
                          backgroundColor: t.color.withValues(alpha: 0.2),
                          child: Icon(t.icon, color: t.color, size: 20),
                        ),
                        title: Text(
                          t.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          t.subtitle,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11.5,
                          ),
                        ),
                        onTap: t.onTap,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── INTERACTIVE `/` SLASH COMMAND PALETTE OVERLAY ───────────────────────

  Widget _buildSlashCommandOverlay(
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    final filtered = SlashCommandInfo.catalog.where((cmd) {
      if (_slashFilter.isEmpty || _slashFilter == '/') return true;
      return cmd.command.toLowerCase().contains(_slashFilter) ||
          cmd.title.toLowerCase().contains(_slashFilter);
    }).toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 210),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xF50B1120),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 16),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 15,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Claude Code Hızlı Komut Paleti (/)',
                    style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _showSlashPalette = false),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final sc = filtered[i];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(sc.icon, color: sc.color, size: 18),
                  title: Row(
                    children: [
                      Text(
                        sc.command,
                        style: TextStyle(
                          color: sc.color,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sc.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    sc.description,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  onTap: () {
                    if (sc.targetMode != null) {
                      c.setWorkMode(sc.targetMode!);
                    }
                    setState(() => _showSlashPalette = false);
                    if (sc.template.endsWith(' ')) {
                      _inputController.text = sc.template;
                      _inputController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _inputController.text.length),
                      );
                    } else {
                      _inputController.clear();
                      c.sendMessage(sc.template);
                      _scrollToBottom();
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtifactCard(
    AsistanController c,
    GeneratedArtifact art,
    AsistanThemePreset preset,
  ) {
    final isImg = art.isImage && File(art.filePath).existsSync();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: preset.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isImg) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(art.filePath),
                height: 210,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: preset.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isImg ? Icons.image_rounded : Icons.description_rounded,
                  color: preset.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      art.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      '${art.format.toUpperCase()} • ${(art.sizeBytes / 1024).toStringAsFixed(1)} KB',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => c.openArtifact(art),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                tooltip: 'Aç',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => c.shareArtifact(art),
                icon: Icon(
                  Icons.share_rounded,
                  color: preset.primary,
                  size: 18,
                ),
                tooltip: 'Paylaş',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => c.saveArtifactToDevice(art),
                icon: const Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                tooltip: 'Kaydet',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? Colors.white70;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratingIndicator(
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      color: const Color(0xFF080D1A),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              color: preset.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '⚡ ${c.selectedModelInfo.name} (${c.activeWorkMode.title}) yanıt üretiyor...',
              style: TextStyle(
                color: preset.primary,
                fontSize: 11.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentStrip(AsistanController c, AsistanThemePreset preset) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        scrollDirection: Axis.horizontal,
        itemCount: c.pendingAttachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, idx) {
          final att = c.pendingAttachments[idx];
          return Chip(
            visualDensity: VisualDensity.compact,
            label: Text(
              att.name,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            backgroundColor: preset.cardBg,
            deleteIcon: const Icon(
              Icons.close,
              size: 14,
              color: Colors.white70,
            ),
            onDeleted: () {
              setState(() {
                c.pendingAttachments.removeAt(idx);
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildComposerBar(
    BuildContext context,
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    final isListening = c.orbState == OrbActivityState.listening;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: preset.surfaceBg.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _showSuperToolsSheet(context, c),
            icon: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: preset.primary.withValues(alpha: 0.18),
                border: Border.all(
                  color: preset.primary.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(Icons.add_rounded, color: preset.primary, size: 18),
            ),
            tooltip: 'Süper Araçlar & Dosya Ekle',
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: preset.cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isListening
                      ? const Color(0xFFFF2E93)
                      : preset.primary.withValues(alpha: 0.4),
                ),
              ),
              child: TextField(
                controller: _inputController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitMessage(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  border: InputBorder.none,
                  hintText: isListening
                      ? (c.livePartialTranscript.isEmpty
                            ? '🎙️ Sizi dinliyorum...'
                            : c.livePartialTranscript)
                      : 'Mesajınızı yazın…',
                  hintStyle: TextStyle(
                    color: isListening
                        ? const Color(0xFFFF2E93)
                        : Colors.white.withValues(alpha: 0.45),
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              if (isListening) {
                c.stopSpeechAndListening();
              } else {
                c.startVoiceListening();
              }
            },
            onLongPress: () => widget.onSwitchTab(1),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    offset: Offset(0, 3),
                    blurRadius: 5,
                  ),
                ],
                gradient: LinearGradient(
                  colors: isListening
                      ? const [Color(0xFFFF2E93), Color(0xFFFF7A00)]
                      : [preset.secondary, preset.primary],
                ),
              ),
              child: Icon(
                isListening ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
          ),
          const SizedBox(width: 5),
          IconButton.filled(
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: preset.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: c.isGenerating ? null : _submitMessage,
            icon: const Icon(Icons.send_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  // ─── MODEL SELECTOR, REGENERATE, READING & PROXY DIALOGS ─────────────────

  void _showModelSelectorSheet(BuildContext context, AsistanController c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.themePreset.surfaceBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.92,
          minChildSize: 0.5,
          builder: (context, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Yapay Zeka Modeli & Çalışma Modu',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Siri CLIProxy (127.0.0.1:8317) + Claude + ChatGPT + Gemini',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await c.pasteKeyFromClipboardAndConnect();
                        },
                        icon: const Icon(Icons.content_paste_rounded, size: 15),
                        label: const Text('Anahtar Yapıştır'),
                      ),
                      IconButton(
                        onPressed: () async {
                          await c.refreshProxyAndModels();
                        },
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white70,
                        ),
                        tooltip: 'Modelleri Yenile',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // WorkMode strip inside sheet
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: WorkMode.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        final wm = WorkMode.values[i];
                        final sel = c.activeWorkMode == wm;
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          selected: sel,
                          showCheckmark: false,
                          avatar: Icon(
                            wm.icon,
                            size: 14,
                            color: sel ? Colors.black : wm.accent,
                          ),
                          label: Text(
                            wm.title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: sel ? Colors.black : Colors.white,
                            ),
                          ),
                          selectedColor: wm.accent,
                          backgroundColor: const Color(0xFF0F172A),
                          onSelected: (_) {
                            c.setWorkMode(wm);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: c.availableModels.length,
                      itemBuilder: (context, idx) {
                        final m = c.availableModels[idx];
                        final selected = m.id == c.selectedModelId;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? m.color.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? m.color
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: m.color.withValues(alpha: 0.22),
                              child: Icon(
                                m.id.startsWith('auto')
                                    ? Icons.hub_rounded
                                    : Icons.auto_awesome_rounded,
                                color: m.color,
                                size: 16,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (m.isLiveFromProxy)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF10B981),
                                      ),
                                    ),
                                    child: const Text(
                                      'CANLI PROXY',
                                      style: TextStyle(
                                        color: Color(0xFF34D399),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              '${m.provider} • ${m.badge} (${m.id})',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: m.color,
                                  )
                                : null,
                            onTap: () {
                              c.setSelectedModel(m.id);
                              Navigator.pop(ctx);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRegenerateWithModelSheet(
    BuildContext context,
    AsistanController c,
    ChatMessage msg,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.themePreset.surfaceBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🔄 Bu Soruyu Başka Modelle Yanıtla',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: c.availableModels.length,
                  itemBuilder: (context, i) {
                    final m = c.availableModels[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.bolt_rounded, color: m.color),
                      title: Text(
                        m.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${m.provider} • ${m.id}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        c.regenerateMessageWithModel(msg, m.id);
                        _scrollToBottom();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReadingAndPersonaSheet(BuildContext context, AsistanController c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.themePreset.surfaceBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📖 Geniş Okuma Ayarları & Uzman Kimlik',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Yazı Boyutu:',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          c.adjustFontSize(-1.0);
                          setModal(() {});
                        },
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${c.chatFontSize.toStringAsFixed(1)} pt',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          c.adjustFontSize(1.0);
                          setModal(() {});
                        },
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Claude Code Tam Ekran Geniş Okuma Alanı',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Mesaj kartlarını ekranın tamamına yayar',
                      style: TextStyle(color: Colors.white60, fontSize: 11.5),
                    ),
                    value: c.wideReadingMode,
                    onChanged: (_) {
                      c.toggleWideReadingMode();
                      setModal(() {});
                    },
                  ),
                  const Divider(color: Colors.white12),
                  const Text(
                    '🎭 Aktif Asistan Uzmanlık Kimliği (Persona):',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: AssistantPersona.presets.map((p) {
                      final active = c.activePersonaId == p.id;
                      return ChoiceChip(
                        selected: active,
                        avatar: Icon(
                          p.icon,
                          size: 15,
                          color: active ? Colors.black : p.color,
                        ),
                        label: Text(
                          p.name,
                          style: TextStyle(
                            color: active ? Colors.black : Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        selectedColor: p.color,
                        backgroundColor: const Color(0xFF0F172A),
                        onSelected: (_) {
                          c.setPersona(p.id);
                          setModal(() {});
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showManualProxyDialog(BuildContext context, AsistanController c) {
    final urlCtrl = TextEditingController(text: c.engine.baseUrl);
    final keyCtrl = TextEditingController(text: c.engine.apiKey);
    final gemCtrl = TextEditingController(text: c.engine.geminiDirectApiKey);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          title: const Text(
            '🔑 Siri CLIProxy (8317) Bağlantısı',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CLIProxy uygulamasındaki API anahtarını (sk-iphone-...) buraya yapıştırabilir veya tek dokunuşla panodan alabilirsiniz.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'CLIProxy Adresi',
                    labelStyle: TextStyle(color: Colors.white60),
                    hintText: 'http://127.0.0.1:8317',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'CLIProxy API Anahtarı (sk-iphone-...)',
                    labelStyle: const TextStyle(color: Colors.white60),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.content_paste_rounded,
                        color: Color(0xFF00E5FF),
                      ),
                      onPressed: () async {
                        final clip = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (clip?.text != null) {
                          keyCtrl.text = clip!.text!.trim();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: gemCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Doğrudan Gemini API Key (İsteğe Bağlı)',
                    labelStyle: TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => c.openCliProxyApp(),
              child: const Text('CLIProxy Uygulamasını Aç'),
            ),
            FilledButton(
              onPressed: () async {
                await c.updateServerConfig(
                  proxyUrl: urlCtrl.text,
                  proxyKey: keyCtrl.text,
                  geminiKey: gemCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Kaydet & Bağlan'),
            ),
          ],
        );
      },
    );
  }

  void _showThemeAndWallpaperSheet(BuildContext context, AsistanController c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.themePreset.surfaceBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🎨 3D Holografik Temalar & Arka Planlar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AsistanThemePreset.presets.map((p) {
                      final active = c.themePreset.id == p.id;
                      return ChoiceChip(
                        selected: active,
                        label: Text(p.name),
                        selectedColor: p.primary,
                        labelStyle: TextStyle(
                          color: active ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) {
                          c.setThemePreset(p);
                          setModalState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '🖼️ Özel İllüstrasyon Arka Planları',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: WallpaperOption.all.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final w = WallpaperOption.all[i];
                        final selected = c.wallpaperAsset == w.assetPath;
                        return GestureDetector(
                          onTap: () {
                            c.setWallpaper(w.assetPath);
                            setModalState(() {});
                          },
                          child: Container(
                            width: 145,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? c.themePreset.primary
                                    : Colors.white24,
                                width: selected ? 2.4 : 1.0,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.asset(w.assetPath, fit: BoxFit.cover),
                                  Container(
                                    alignment: Alignment.bottomLeft,
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black87,
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      w.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
