import 'package:flutter/material.dart';

import 'services/asistan_controller.dart';
import 'ui/animations_3d.dart';
import 'ui/chat_screen.dart';
import 'ui/downloader_screen.dart';
import 'ui/hub_screen.dart';
import 'ui/live_voice_screen.dart';
import 'ui/studio_screen.dart';
import 'ui/theme_asistan.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AsistanController();
  controller.initialize();
  runApp(AsistanApp(controller: controller));
}

class AsistanApp extends StatelessWidget {
  const AsistanApp({super.key, required this.controller});

  final AsistanController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final preset = controller.themePreset;
        return MaterialApp(
          title: 'Asistan',
          debugShowCheckedModeBanner: false,
          theme: preset.toThemeData(),
          home: AsistanHomeShell(controller: controller),
        );
      },
    );
  }
}

class AsistanHomeShell extends StatefulWidget {
  const AsistanHomeShell({super.key, required this.controller});

  final AsistanController controller;

  @override
  State<AsistanHomeShell> createState() => _AsistanHomeShellState();
}

class _AsistanHomeShellState extends State<AsistanHomeShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _switchTab(int index) {
    setState(() {
      widget.controller.currentTabIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final preset = c.themePreset;
    final edgeGlowActive =
        c.orbState != OrbActivityState.idle || c.wakeWordEnabled;

    return SiriEdgeGlowOverlay(
      active: edgeGlowActive,
      audioLevel: c.voiceAudioLevel,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildThreadsDrawer(context, c, preset),
        appBar: c.currentTabIndex == 0
            ? null
            : AppBar(
                title: const Text('Asistan'),
                actions: [
                  IconButton(
                    tooltip: 'Sohbete dön',
                    onPressed: () => _switchTab(0),
                    icon: const Icon(Icons.chat_bubble_outline),
                  ),
                ],
              ),
        body: AsistanWallpaperBackground(
          preset: preset,
          wallpaperAsset: c.wallpaperAsset,
          dimOpacity: c.wallpaperDim,
          child: IndexedStack(
            index: c.currentTabIndex,
            children: [
              ChatScreen(
                controller: c,
                onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                onSwitchTab: _switchTab,
              ),
              LiveVoiceScreen(controller: c),
              DownloaderScreen(controller: c),
              StudioScreen(controller: c),
              HubScreen(controller: c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreadsDrawer(
    BuildContext context,
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    final filtered = c.threads.where((t) {
      if (c.threadSearchQuery.trim().isEmpty) return true;
      return t.title.toLowerCase().contains(
        c.threadSearchQuery.trim().toLowerCase(),
      );
    }).toList();

    return Drawer(
      backgroundColor: preset.surfaceBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in const [
              (0, 'Sohbet', Icons.chat_bubble_outline),
              (1, 'Canlı Ses', Icons.mic_none),
              (2, 'İndirmeler', Icons.download_outlined),
              (3, 'Belgeler ve görseller', Icons.description_outlined),
              (4, 'Telefon ve ayarlar', Icons.settings_outlined),
            ])
              ListTile(
                leading: Icon(entry.$3),
                title: Text(entry.$2),
                selected: c.currentTabIndex == entry.$1,
                onTap: () {
                  _switchTab(entry.$1);
                  Navigator.pop(context);
                },
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  HolographicOrb3D(
                    size: 42,
                    state: c.orbState,
                    primaryColor: preset.primary,
                    secondaryColor: preset.secondary,
                    tertiaryColor: preset.tertiary,
                    interactive: false,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Asistan AI v3.0',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'ChatGPT • Gemini • Claude • Siri',
                          style: TextStyle(
                            color: preset.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: preset.primary,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  c.createNewThread();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Yeni Sohbet Başlat',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: filtered.length,
                itemBuilder: (context, idx) {
                  final t = filtered[idx];
                  final active = t.id == c.activeThreadId;
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    selected: active,
                    selectedTileColor: preset.primary.withValues(alpha: 0.16),
                    leading: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: active ? preset.primary : Colors.white54,
                      size: 18,
                    ),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      '${t.messages.length} ileti',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.white38,
                      ),
                      onPressed: () => c.deleteThread(t.id),
                    ),
                    onTap: () {
                      c.selectThread(t.id);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
