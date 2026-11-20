import 'package:flutter/material.dart';

import 'kagit_store.dart';
import 'theme_kagit.dart';
import 'views/files_page.dart';
import 'views/home_page.dart';
import 'views/settings_sheet.dart';
import 'views/teacher_page.dart';
import 'views/tools_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = KagitController();
  await controller.init();
  runApp(KagitApp(controller: controller));
}

class KagitApp extends StatefulWidget {
  const KagitApp({super.key, required this.controller});

  final KagitController controller;

  @override
  State<KagitApp> createState() => _KagitAppState();
}

class _KagitAppState extends State<KagitApp> with WidgetsBindingObserver {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.checkExternalOpenedPdf();
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _switchTab(int idx) {
    setState(() => _tabIndex = idx.clamp(0, 4));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.controller.ayarlar.isDark;

    return MaterialApp(
      title: 'Kâğıt',
      debugShowCheckedModeBanner: false,
      theme: KagitTema.acikTema(),
      darkTheme: KagitTema.koyuTema(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _tabIndex,
            children: [
              KagitHomePage(controller: widget.controller, onSwitchTab: _switchTab),
              KagitFilesPage(
                controller: widget.controller,
                onSwitchToTools: () => _switchTab(2),
              ),
              KagitToolsPage(controller: widget.controller),
              KagitTeacherPage(controller: widget.controller),
              KagitSettingsPage(controller: widget.controller),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: _switchTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Ana Sayfa',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: 'Dosyalar',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Araçlar',
            ),
            NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school_rounded),
              label: 'Öğretmen',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Ayarlar',
            ),
          ],
        ),
      ),
    );
  }
}
