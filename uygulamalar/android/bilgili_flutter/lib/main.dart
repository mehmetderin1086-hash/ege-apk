import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/academy_pool_tab.dart';
import 'screens/home_play_tab.dart';
import 'screens/model_center_tab.dart';
import 'screens/progress_tab.dart';
import 'screens/quiz_session_screen.dart';
import 'screens/settings_tab.dart';
import 'state/arena_controller.dart';
import 'theme/arena_design.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF060B16),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  final controller = ArenaController();
  unawaited(controller.initialize());
  runApp(BilgiliApp(controller: controller));
}

class BilgiliApp extends StatefulWidget {
  final ArenaController controller;
  const BilgiliApp({super.key, required this.controller});

  @override
  State<BilgiliApp> createState() => _BilgiliAppState();
}

class _BilgiliAppState extends State<BilgiliApp> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final wp = ctrl.currentWallpaper;

        return MaterialApp(
          title: 'Bilgili',
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(data: media.copyWith(disableAnimations: media.disableAnimations || ctrl.reduceMotion || ctrl.effectIntensity == EffectIntensity.off), child: child!);
          },
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: wp.ink,
            colorScheme: ColorScheme.dark(
              primary: wp.primary,
              secondary: wp.secondary,
              surface: wp.surface,
            ),
          ),
          home: Scaffold(
            backgroundColor: wp.ink,
            extendBody: true,
            body: ArenaAmbientBackground(
              wallpaper: wp,
              clarity: ctrl.wallpaperClarity,
              intensity: ctrl.effectIntensity,
              reduceMotion: ctrl.reduceMotion,
              child: ctrl.activeRound != null
                  ? QuizSessionScreen(controller: ctrl)
                  : SafeArea(
                      bottom: false,
                      child: IndexedStack(
                        index: _tabIndex,
                        children: [
                          TickerMode(enabled: _tabIndex == 0, child: HomePlayTab(
                            controller: ctrl,
                            onOpenAiStudioTab: () => setState(() => _tabIndex = 2),
                            onOpenAcademyReview: () => setState(() => _tabIndex = 1),
                          )),
                          AcademyPoolTab(controller: ctrl),
                          ModelCenterTab(controller: ctrl),
                          ProgressTab(controller: ctrl),
                          SettingsTab(controller: ctrl),
                        ],
                      ),
                    ),
            ),
            bottomNavigationBar: ctrl.activeRound != null
                ? null
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(wp.surface, wp.primary, .14)!, wp.ink]),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 18, offset: Offset(0,-3))],
                      border: Border(
                        top: BorderSide(color: wp.primary.withValues(alpha: 0.18)),
                      ),
                    ),
                    child: NavigationBar(
                      height: 64,
                      backgroundColor: Colors.transparent,
                      indicatorColor: wp.primary.withValues(alpha: 0.20),
                      selectedIndex: _tabIndex,
                      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                      onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
                      destinations: [
                        NavigationDestination(
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
                          selectedIcon:
                              Icon(Icons.play_circle_fill_rounded, size: 22, color: wp.primary),
                          label: 'Oyna',
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.school_outlined, size: 22),
                          selectedIcon: Icon(Icons.school_rounded, size: 22, color: wp.primary),
                          label: 'Akademi',
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.auto_awesome_outlined, size: 22),
                          selectedIcon:
                              Icon(Icons.auto_awesome_rounded, size: 22, color: wp.primary),
                          label: 'AI Stüdyo',
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.workspace_premium_outlined, size: 22),
                          selectedIcon:
                              Icon(Icons.workspace_premium_rounded, size: 22, color: wp.primary),
                          label: 'İlerleme',
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.tune_rounded, size: 22),
                          selectedIcon: Icon(Icons.tune_rounded, size: 22, color: wp.primary),
                          label: 'Ayarlar',
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}
