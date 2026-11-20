import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/jarvis_models.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_fx.dart';
import '../widgets/chat_palette.dart';
import '../widgets/jarvis_nav_bar.dart';
import '../widgets/model_picker_sheet.dart';
import 'chat_screen.dart';
import 'live_voice_screen.dart';
import 'pc_hub_screen.dart';
import 'settings_screen.dart';
import 'studio_screen.dart';
import 'tools_screen.dart';
import 'voice_studio_screen.dart';
import 'diagnostics_screen.dart';
import 'memory_screen.dart';
import 'agent_center_screen.dart';
import 'works_screen.dart';
import 'youtube_screen.dart';
import 'whatsapp_screen.dart';

class HomeShell extends StatelessWidget {
  final JarvisController controller;

  const HomeShell({super.key, required this.controller});

  /// Visual order of the bottom navigation → internal tab index. The PC tab
  /// was added as internal index 5 so existing `openTab` indices stay valid.
  static const List<int> displayOrder = [0, 1, 5, 2, 3, 4];

  Future<void> _promptRenameSession(
    BuildContext context,
    ChatSession session,
  ) async {
    final ctrl = TextEditingController(text: session.title);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Text('Sohbeti Yeniden Adlandır'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (res != null && res.isNotEmpty) {
      await controller.renameSession(session.id, res);
    }
  }

  void _openPendingRoute(BuildContext context) {
    final route = controller.pendingRoute;
    if (route == null) return;
    controller.pendingRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final Widget? screen = switch (route) {
        'works' => WorksScreen(controller: controller),
        'youtube' => YoutubeScreen(controller: controller),
        'memory' => MemoryScreen(controller: controller),
        'agent' => AgentCenterScreen(controller: controller),
        'voices' => VoiceStudioScreen(controller: controller),
        'diagnostics' => DiagnosticsScreen(controller: controller),
        _ => null,
      };
      if (screen != null && context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Uygulama teması zaten ChatPalette.theme; sade sekmeler ayrı Scaffold
    // ağacıyla kurulur (çekmece sekme değişiminde hemen kapanır).
    if ({0, 1, 4}.contains(controller.mainTabIndex)) {
      return Theme(
        data: ChatPalette.theme,
        child: Builder(builder: _buildShell),
      );
    }
    return _buildShell(context);
  }

  static String _tabTitle(int i) => switch (i) {
    2 => 'Araçlar',
    3 => 'Stüdyo',
    5 => 'PC Kod',
    _ => 'Ege',
  };

  static IconData _tabIcon(int i) => switch (i) {
    2 => Icons.handyman_rounded,
    3 => Icons.auto_stories_rounded,
    5 => Icons.terminal_rounded,
    _ => Icons.auto_awesome_rounded,
  };

  Widget _buildShell(BuildContext context) {
    final c = controller;
    final isChat = c.mainTabIndex == 0;
    final isSimple = {0, 1, 4}.contains(c.mainTabIndex);
    _openPendingRoute(context);
    final activeTimers = c.activeTimers;
    final firedTimers = c.firedUnacknowledgedTimers;

    return Scaffold(
      backgroundColor: ChatPalette.background,
      appBar: !isChat && isSimple
          ? AppBar(
              leading: IconButton(
                tooltip: 'Sohbete dön',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => c.openTab(0),
              ),
              title: Text(c.mainTabIndex == 1 ? 'Canlı Ses' : 'Ayarlar'),
              centerTitle: true,
              actions: [
                if (c.mainTabIndex == 1)
                  IconButton(
                    tooltip: 'Ayarlar',
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: () => c.openTab(4),
                  ),
              ],
            )
          : isChat
          ? AppBar(
              leading: Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menü',
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              titleSpacing: 0,
              title: InkWell(
                key: const Key('appbar_model_picker_button'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => showModelPickerSheet(context, c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ege',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                              ),
                            ),
                            Text(
                              c.settings.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:  TextStyle(
                                fontSize: 10.5,
                                color: ChatPalette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                    ],
                  ),
                ),
              ),
              actions: [
                if (activeTimers.isNotEmpty)
                  IconButton(
                    tooltip: 'Sayaçlar',
                    onPressed: () => c.openTab(2, toolsSubTab: 0),
                    icon: Badge(
                      label: Text('${activeTimers.length}'),
                      child: const Icon(Icons.timer_outlined),
                    ),
                  ),
                IconButton(
                  tooltip: 'Yeni Sohbet',
                  onPressed: () {
                    c.createNewSession();
                    c.openTab(0);
                  },
                  icon: const Icon(Icons.edit_square),
                ),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              backgroundColor: ChatPalette.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(height: 1, color: ChatPalette.border),
              ),
              titleSpacing: 0,
              title: Row(
                children: [
                  const SizedBox(width: 4),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: ChatPalette.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      _tabIcon(c.mainTabIndex),
                      size: 19,
                      color: ChatPalette.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tabTitle(c.mainTabIndex),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                            fontSize: 18,
                            color: ChatPalette.ink,
                          ),
                        ),
                        Text(
                          c.activeSession.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: ChatPalette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    key: const Key('appbar_model_picker_button'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => showModelPickerSheet(context, c),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              ChatPalette.surface.withValues(alpha: 0.92),
                              ChatPalette.surface.withValues(alpha: 0.92),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: c.connectionOk == true
                                ? const Color(0xFF10B981)
                                      .withValues(alpha: 0.45)
                                : ChatPalette.accent
                                      .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BreathingDot(
                              size: 7,
                              color: c.connectionOk == true
                                  ? const Color(0xFF34D399)
                                  : c.connectionOk == false
                                  ? const Color(0xFFF87171)
                                  : const Color(0xFFFBBF24),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                c.settings.model,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: ChatPalette.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 15,
                              color: ChatPalette.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (activeTimers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ActionChip(
                      backgroundColor: ChatPalette.soft,
                      side: BorderSide(color: ChatPalette.accent),
                      avatar: Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: ChatPalette.accent,
                      ),
                      label: Text(
                        '${activeTimers.length}',
                        style: TextStyle(
                          color: ChatPalette.accent,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: () => c.openTab(2, toolsSubTab: 0),
                    ),
                  ),
                if (c.settings.pcPaired)
                  IconButton(
                    tooltip: c.pcOnline == true
                        ? 'PC bağlı: ${c.settings.pcBridgeName}'
                        : 'PC bağlantısı yok',
                    onPressed: () => c.openTab(5),
                    icon: Badge(
                      backgroundColor: c.pcOnline == true
                          ? const Color(0xFF34D399)
                          : c.pcOnline == false
                          ? const Color(0xFFF87171)
                          : const Color(0xFFFBBF24),
                      smallSize: 8,
                      child: const Icon(Icons.laptop_windows_rounded),
                    ),
                  ),
                IconButton(
                  tooltip: 'Bulut Ses Stüdyosu',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VoiceStudioScreen(controller: c),
                    ),
                  ),
                  icon: const Icon(Icons.record_voice_over_outlined),
                ),
                const SizedBox(width: 4),
              ],
            ),
      drawer: Drawer(
        backgroundColor: isChat
            ? ChatPalette.background
            : ChatPalette.surface,
        child: SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 26,
                      color: isChat
                          ? ChatPalette.accent
                          : ChatPalette.accent,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Sohbet Oturumları',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Yeni Sohbet',
                      onPressed: () {
                        c.createNewSession();
                        Navigator.pop(context);
                        c.openTab(0);
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in const [
                      ('Sohbet', Icons.chat_bubble_outline_rounded, 0),
                      ('Canlı Ses', Icons.graphic_eq_rounded, 1),
                      ('PC Kod', Icons.terminal_rounded, 5),
                      ('Araçlar', Icons.handyman_outlined, 2),
                      ('Stüdyo', Icons.auto_stories_outlined, 3),
                      ('Ayarlar', Icons.settings_outlined, 4),
                    ])
                      ActionChip(
                        label: Text(item.$1),
                        avatar: Icon(item.$2, size: 16),
                        onPressed: () {
                          Navigator.pop(context);
                          c.openTab(item.$3);
                        },
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: ChatPalette.border),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: c.sessions.length,
                itemBuilder: (context, idx) {
                  final s = c.sessions[idx];
                  final selected = s.id == c.activeSessionId;
                  return ListTile(
                    selected: selected,
                    selectedTileColor: isChat
                        ? ChatPalette.soft
                        : ChatPalette.soft,
                    leading: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 19,
                      color: selected
                          ? (isChat
                                ? ChatPalette.accent
                                : ChatPalette.accent)
                          : ChatPalette.muted,
                    ),
                    title: Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${s.messages.length} mesaj',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ChatPalette.muted,
                      ),
                    ),
                    onTap: () {
                      c.selectSession(s.id);
                      Navigator.pop(context);
                      c.openTab(0);
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (val) async {
                        if (val == 'rename') {
                          await _promptRenameSession(context, s);
                        } else if (val == 'copy') {
                          await Clipboard.setData(
                            ClipboardData(text: c.exportSessionMarkdown(s)),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Markdown olarak kopyalandı'),
                              ),
                            );
                          }
                        } else if (val == 'share') {
                          await c.shareSession(s);
                        } else if (val == 'delete') {
                          await c.deleteSession(s.id);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Yeniden Adlandır'),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: Text('Markdown Kopyala'),
                        ),
                        PopupMenuItem(value: 'share', child: Text('Paylaş')),
                        PopupMenuItem(value: 'delete', child: Text('Sil')),
                      ],
                    ),
                  );
                },
              ),
              Divider(height: 1, color: ChatPalette.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final link in <(String, IconData, Widget Function())>[
                      (
                        'Çalışmalar',
                        Icons.work_history_rounded,
                        () => WorksScreen(controller: c),
                      ),
                      (
                        'WhatsApp',
                        Icons.chat_outlined,
                        () => WhatsAppScreen(controller: c),
                      ),
                      (
                        'YouTube',
                        Icons.smart_display_rounded,
                        () => YoutubeScreen(controller: c),
                      ),
                      (
                        'Hafıza',
                        Icons.psychology_alt_rounded,
                        () => MemoryScreen(controller: c),
                      ),
                      (
                        'Sesler',
                        Icons.record_voice_over_rounded,
                        () => VoiceStudioScreen(controller: c),
                      ),
                      (
                        'Sistem Tanı',
                        Icons.health_and_safety_rounded,
                        () => DiagnosticsScreen(controller: c),
                      ),
                    ])
                      ActionChip(
                        avatar: Icon(link.$2, size: 16),
                        label: Text(
                          link.$1,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(
                            context,
                          ).push(MaterialPageRoute(builder: (_) => link.$3()));
                        },
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, size: 19),
                title: const Text('Aktif Sohbeti Temizle'),
                onTap: () {
                  c.clearActiveSession();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (firedTimers.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF9F1239),
                    Color(0xFFBE123C),
                    Color(0xFF7C3AED),
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0x66F43F5E), blurRadius: 18),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Süre doldu: ${firedTimers.map((t) => t.label).join(', ')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: c.acknowledgeAllFired,
                      child: const Text('TAMAM'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _TabSwitcher(
              index: c.mainTabIndex,
              children: [
                ChatScreen(controller: c),
                LiveVoiceScreen(controller: c),
                ToolsScreen(controller: c),
                StudioScreen(controller: c),
                SettingsScreen(controller: c),
                PcHubScreen(controller: c),
              ],
            ),
          ),
          MiniPlayerBar(controller: c),
        ],
      ),
      bottomNavigationBar: isSimple
          ? null
          : JarvisNavBar(
              selectedIndex: displayOrder.indexOf(c.mainTabIndex).clamp(0, 5),
              onSelected: (idx) => c.openTab(displayOrder[idx]),
              items: [
                const JarvisNavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  selectedIcon: Icons.chat_bubble_rounded,
                  label: 'Sohbet',
                ),
                const JarvisNavItem(
                  icon: Icons.graphic_eq_rounded,
                  selectedIcon: Icons.graphic_eq_rounded,
                  label: 'Canlı Ses',
                ),
                JarvisNavItem(
                  icon: Icons.terminal_rounded,
                  selectedIcon: Icons.terminal_rounded,
                  label: 'PC Kod',
                  badgeColor: !c.settings.pcPaired
                      ? null
                      : c.pcOnline == true
                      ? const Color(0xFF34D399)
                      : const Color(0xFFFBBF24),
                ),
                const JarvisNavItem(
                  icon: Icons.handyman_outlined,
                  selectedIcon: Icons.handyman_rounded,
                  label: 'Araçlar',
                ),
                const JarvisNavItem(
                  icon: Icons.auto_stories_outlined,
                  selectedIcon: Icons.auto_stories_rounded,
                  label: 'Stüdyo',
                ),
                const JarvisNavItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  label: 'Ayarlar',
                ),
              ],
            ),
    );
  }
}

/// IndexedStack that plays a short fade + lift when the tab changes.
class _TabSwitcher extends StatefulWidget {
  const _TabSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<_TabSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(covariant _TabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && JFx.on(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: 0.25 + 0.75 * _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * 14),
          child: child,
        ),
      ),
      child: IndexedStack(index: widget.index, children: widget.children),
    );
  }
}
