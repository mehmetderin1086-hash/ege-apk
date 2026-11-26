import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/academy_pool_tab.dart';
import 'screens/home_play_tab.dart';
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
      systemNavigationBarColor: StudioPalette.night,
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
            return MediaQuery(
              data: media.copyWith(
                disableAnimations: media.disableAnimations ||
                    ctrl.reduceMotion ||
                    ctrl.effectIntensity == EffectIntensity.off,
              ),
              child: child!,
            );
          },
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: StudioPalette.night,
            colorScheme: ColorScheme.dark(
              primary: wp.primary,
              secondary: wp.secondary,
              surface: StudioPalette.navyMid,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: StudioPalette.navyMid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: StudioPalette.gold, width: 1.8),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: StudioPalette.navyMid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                side: BorderSide(color: StudioPalette.gold, width: 1.5),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: StudioPalette.navyTop,
              contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: StudioPalette.gold, width: 1.2),
              ),
              behavior: SnackBarBehavior.floating,
            ),
            navigationBarTheme: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final sel = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 11.5,
                  fontWeight: sel ? FontWeight.w900 : FontWeight.w600,
                  color: sel ? StudioPalette.goldBright : Colors.white70,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final sel = states.contains(WidgetState.selected);
                return IconThemeData(
                  size: sel ? 24 : 21,
                  color: sel ? StudioPalette.goldBright : Colors.white70,
                );
              }),
            ),
          ),
          home: Scaffold(
            backgroundColor: StudioPalette.night,
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
                          TickerMode(
                            enabled: _tabIndex == 0,
                            child: HomePlayTab(
                              controller: ctrl,
                              onOpenAcademyReview: () => setState(() => _tabIndex = 1),
                              onOpenProgressTab: () => setState(() => _tabIndex = 2),
                            ),
                          ),
                          AcademyPoolTab(controller: ctrl),
                          ProgressTab(controller: ctrl),
                          SettingsTab(controller: ctrl),
                        ],
                      ),
                    ),
            ),
            bottomNavigationBar: ctrl.activeRound != null
                ? null
                : _StudioBottomNav(
                    selectedIndex: _tabIndex,
                    dueReviewCount: ctrl.dueReviewCards.length,
                    onSelect: (idx) => setState(() => _tabIndex = idx),
                  ),
          ),
        );
      },
    );
  }
}

/// Zirve Merdiveni tarzı 3D altın kenarlıklı 4 sekmeli stüdyo alt gezinme barı.
class _StudioBottomNav extends StatelessWidget {
  final int selectedIndex;
  final int dueReviewCount;
  final ValueChanged<int> onSelect;

  const _StudioBottomNav({
    required this.selectedIndex,
    required this.dueReviewCount,
    required this.onSelect,
  });

  Widget _academyIcon(bool selected) {
    final base = Icon(
      selected ? Icons.school_rounded : Icons.school_outlined,
      color: selected ? StudioPalette.goldBright : null,
    );
    if (dueReviewCount <= 0) return base;
    return Badge(
      backgroundColor: StudioPalette.amber,
      textColor: StudioPalette.night,
      label: Text(
        dueReviewCount > 99 ? '99+' : '$dueReviewCount',
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
      ),
      child: base,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF5152172), Color(0xFA060B2C), StudioPalette.night],
        ),
        border: const Border(
          top: BorderSide(color: StudioPalette.gold, width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: StudioPalette.gold.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, -3),
          ),
          const BoxShadow(
            color: Colors.black87,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: NavigationBar(
        height: 66,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: StudioPalette.gold.withValues(alpha: 0.22),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.7), width: 1.2),
        ),
        selectedIndex: selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: onSelect,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.play_circle_outline_rounded),
            selectedIcon: Icon(Icons.play_circle_fill_rounded, color: StudioPalette.goldBright),
            label: 'Oyna',
          ),
          NavigationDestination(
            icon: _academyIcon(false),
            selectedIcon: _academyIcon(true),
            label: 'Akademi',
          ),
          const NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium_rounded, color: StudioPalette.goldBright),
            label: 'İlerleme',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded, color: StudioPalette.goldBright),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }
}
