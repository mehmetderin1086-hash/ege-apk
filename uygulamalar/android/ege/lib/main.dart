import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'state/jarvis_controller.dart';
import 'widgets/jarvis_fx.dart';
import 'widgets/jarvis_ui.dart';
import 'widgets/chat_palette.dart';
import 'services/wake_word.dart';

import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

class JarvisApp extends StatefulWidget {
  final JarvisController? controller;
  final bool loadPlatformTelemetry;

  const JarvisApp({
    super.key,
    this.controller,
    this.loadPlatformTelemetry = true,
  });

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> with WidgetsBindingObserver {
  late final JarvisController _controller;
  late final bool _ownsController;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.appInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshWakeState());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? JarvisController();
    _controller.addListener(_syncEffects);
    unawaited(
      _controller.init(loadPlatformTelemetry: widget.loadPlatformTelemetry),
    );
  }

  @override
  void didChangePlatformBrightness() => _syncEffects();

  /// Mirrors "Arayüz efektleri" into the global motion switch.
  void _syncEffects() {
    final changed = ChatPalette.configure(_controller.settings.themeMode, _controller.settings.themeAccent,
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    if (changed && mounted) setState(() {});
    final on = _controller.settings.uiEffects;
    if (JFx.userEnabled.value != on) JFx.userEnabled.value = on;
    final scale = _controller.settings.textScaleMax;
    if (_textScaleMax.value != scale) _textScaleMax.value = scale;
  }

  /// Ayarlar → Görünüm → Yazı boyutu. Telefonun yazı ölçeği (ör. %135) bu
  /// değerden büyükse uygulama içinde sınırlanır; aksi hâlde düzen sıkışıyor.
  final ValueNotifier<double> _textScaleMax = ValueNotifier<double>(1.15);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_syncEffects);
    _textScaleMax.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ChatPalette.configure(_controller.settings.themeMode, _controller.settings.themeAccent,
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    return MaterialApp(
      title: 'Ege Mobile',
      debugShowCheckedModeBanner: false,
      // One animated HUD backdrop behind every screen; scaffolds are clear.
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: _textScaleMax,
        builder: (context, maxScale, _) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: maxScale < 0.85 ? 0.85 : maxScale,
              ),
            ),
            child: ColoredBox(color: ChatPalette.background, child: child ?? const SizedBox.shrink()),
          );
        },
      ),
      theme: ChatPalette.theme,
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 520),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: _controller.initialized
              ? HomeShell(key: const ValueKey('shell'), controller: _controller)
              : const JarvisBootView(key: ValueKey('boot')),
        ),
      ),
    );
  }
}

/// Startup screen shown while the core loads.
class JarvisBootView extends StatelessWidget {
  const JarvisBootView({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const JarvisEmblem(size: 170),
            const SizedBox(height: 22),
            const ShimmerText(
              'Ege',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
             Text(
              'Çekirdek başlatılıyor…',
              style: TextStyle(
                color: JColors.muted,
                fontSize: 12.5,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: JFx.testing ? 0.6 : null,
                  backgroundColor: JColors.border.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Material "fade through": the old page fades out, then the new one fades
/// and scales in. Works with the shared transparent backdrop (no overlap).
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fadeIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
    final scaleIn = Tween(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    final fadeOut = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );
    return FadeTransition(
      opacity: fadeOut,
      child: FadeTransition(
        opacity: fadeIn,
        child: ScaleTransition(scale: scaleIn, child: child),
      ),
    );
  }
}

/// A separate engine owned by the microphone foreground service, not an Activity.
@pragma('vm:entry-point')
Future<void> jarvisWakeMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jarvis.assistant/device');
  try {
    final sensitivity = await channel.invokeMethod<double>('wakeConfig') ?? 0.5;
    final error = await WakeWordEngine.instance.start(
      sensitivity: sensitivity,
      onDetected: () => unawaited(channel.invokeMethod<void>('wakeDetected')),
    );
    await channel.invokeMethod<void>('wakeReady', error);
  } catch (e) {
    await channel.invokeMethod<void>('wakeReady', e.toString());
  }
}
