import 'package:flutter/material.dart';
import 'ritim_store.dart';
import 'theme_design.dart';
import 'views/assistant_page.dart';
import 'views/dashboard_page.dart';
import 'views/downloads_page.dart';
import 'views/library_page.dart';
import 'views/player_sheet.dart';
import 'views/search_page.dart';
import 'views/shared_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RitimApp());
}

class RitimApp extends StatefulWidget {
  const RitimApp({super.key, this.controller});

  final RitimController? controller;

  @override
  State<RitimApp> createState() => _RitimAppState();
}

class _RitimAppState extends State<RitimApp> {
  late final RitimController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? RitimController();
    _controller.init();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (_, _) {
        final palette = _controller.palette;
        return MaterialApp(
          title: 'Ritim',
          debugShowCheckedModeBanner: false,
          theme: palette.toThemeData(),
          home: _RitimShell(controller: _controller),
        );
      },
    );
  }
}

class _RitimShell extends StatefulWidget {
  const _RitimShell({required this.controller});

  final RitimController controller;

  @override
  State<_RitimShell> createState() => _RitimShellState();
}

class _RitimShellState extends State<_RitimShell> {
  int _tabIndex = 0;
  String? _queuedSearchQuery;

  RitimController get c => widget.controller;

  void _openPlayer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.94,
        child: PlayerSheet(controller: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    if (!c.initialized) {
      return Scaffold(
        backgroundColor: p.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RitimSpinningVinyl(
                palette: p,
                isPlaying: true,
                size: 86,
              ),
              const SizedBox(height: 16),
              const Text(
                'ritim',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      );
    }

    final activeDownloads = c.downloadEntries.where((e) => e.isActive).length;

    return Scaffold(
      backgroundColor: p.background,
      body: RitimAmbientBackground(
        palette: p,
        isPlaying: c.isPlaying,
        wallpaper: c.wallpaper,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              IndexedStack(
                index: _tabIndex,
                children: [
                  DashboardPage(
                    controller: c,
                    onOpenSearch: () => setState(() => _tabIndex = 1),
                    onOpenLibrary: () => setState(() => _tabIndex = 2),
                    onOpenDownloads: () => setState(() => _tabIndex = 3),
                    onOpenAssistant: () => setState(() => _tabIndex = 4),
                    onOpenPlayer: _openPlayer,
                  ),
                  SearchPage(
                    controller: c,
                    initialQuery: _queuedSearchQuery,
                    onOpenDownloads: () => setState(() => _tabIndex = 3),
                    onOpenPlayer: _openPlayer,
                  ),
                  LibraryPage(
                    controller: c,
                    onOpenPlayer: _openPlayer,
                  ),
                  DownloadsPage(
                    controller: c,
                    onOpenPlayer: _openPlayer,
                  ),
                  AssistantPage(
                    controller: c,
                    onSearchYouTubeQuery: (q) {
                      setState(() {
                        _queuedSearchQuery = q;
                        _tabIndex = 1;
                      });
                    },
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MiniPlayerBar(
                  controller: c,
                  onTap: _openPlayer,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: p.primary.withValues(alpha: 0.16)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          backgroundColor: p.surface.withValues(alpha: 0.94),
          indicatorColor: p.primary.withValues(alpha: 0.20),
          selectedIndex: _tabIndex,
          onDestinationSelected: (i) => setState(() => _tabIndex = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.music_note_outlined),
              selectedIcon: Icon(Icons.music_note_rounded),
              label: 'Keşfet',
            ),
            const NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'Ara',
            ),
            const NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music_rounded),
              label: 'Kitaplığım',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: activeDownloads > 0,
                label: Text('$activeDownloads'),
                child: const Icon(Icons.download_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: activeDownloads > 0,
                label: Text('$activeDownloads'),
                child: const Icon(Icons.download_rounded),
              ),
              label: 'İndir',
            ),
            const NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded),
              label: 'Asistan',
            ),
          ],
        ),
      ),
    );
  }
}
