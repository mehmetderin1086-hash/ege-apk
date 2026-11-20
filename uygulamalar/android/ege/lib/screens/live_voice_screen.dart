import 'package:flutter/material.dart';

import '../state/jarvis_controller.dart';
import '../models/jarvis_models.dart';
import '../widgets/chat_palette.dart';
import '../widgets/speaking_edge_lights.dart';
import '../widgets/ege_3d.dart';

class LiveVoiceScreen extends StatelessWidget {
  final JarvisController controller;
  const LiveVoiceScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final c = controller;
    final active = c.liveLoopActive;
    final speaking = c.livePhase == LiveVoicePhase.speaking;
    final phaseColor = _phaseColor(c, active);
    final energy = c.activeOrbEnergy.clamp(0.0, 1.0).toDouble();
    return ColoredBox(
      color: ChatPalette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final orbSize = c.settings.liveOrbSize.clamp(
                  96.0,
                  constraints.maxHeight < 500 ? 130.0 : 180.0,
                );
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: (constraints.maxHeight - 156).clamp(
                              0,
                              double.infinity,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                active
                                    ? 'Birlikte konuşalım'
                                    : 'Seni dinlemeye hazırım',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.8,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _phaseChip(c, active, phaseColor),
                              const SizedBox(height: 4),
                              Semantics(
                                label: c.liveStatusHint,
                                image: true,
                                child: SizedBox.square(
                                  dimension: orbSize * 1.5,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Ege3DOrb(
                                        size: orbSize * 1.5,
                                        color: phaseColor,
                                        energy: active ? energy : 0,
                                        active: active,
                                      ),
                                      // Boyut ölçümü ve dokunma alanı için
                                      // görünmez çekirdek kutusu.
                                      IgnorePointer(
                                        child: AnimatedContainer(
                                          key: const Key('live_voice_orb'),
                                          duration: const Duration(
                                            milliseconds: 280,
                                          ),
                                          width: orbSize,
                                          height: orbSize,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c.liveStatusHint,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: ChatPalette.ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ses: ${c.settings.ttsEngine == 'device' ? 'Telefon' : (JarvisVoiceCatalog.find(c.settings.proxyTtsVoice)?.label ?? c.settings.proxyTtsVoice)}'
                                '${c.lastSttInfo == null ? '' : '\nTanıma: ${c.lastSttInfo}'}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ChatPalette.muted,
                                ),
                              ),
                              if (c.phoneSttUnavailable) ...[
                                const SizedBox(height: 14),
                                _sttNotice(c),
                              ],
                              if (c.liveTranscript.isNotEmpty ||
                                  c.liveAssistantReply.isNotEmpty) ...[
                                const SizedBox(height: 22),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: ChatPalette.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: ChatPalette.border,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (c.liveTranscript.isNotEmpty) ...[
                                        _speakerLabel('SEN', ChatPalette.muted),
                                        const SizedBox(height: 2),
                                        Text(
                                          c.liveTranscript,
                                          style: TextStyle(
                                            color: ChatPalette.muted,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                      if (c.liveAssistantReply.isNotEmpty) ...[
                                        if (c.liveTranscript.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            child: Divider(
                                              height: 1,
                                              color: ChatPalette.border,
                                            ),
                                          ),
                                        _speakerLabel(
                                          'EGE',
                                          ChatPalette.accent,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          c.liveAssistantReply,
                                          style: TextStyle(
                                            color: ChatPalette.ink,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _control(
                                'Kameraya Sor',
                                Icons.camera_alt_outlined,
                                c.captureCameraAndAskLive,
                                caption: 'Kamera',
                              ),
                              _control(
                                'Yaz',
                                Icons.keyboard_outlined,
                                () => _promptLiveText(context, c),
                                caption: 'Yaz',
                              ),
                              _control(
                                active
                                    ? (speaking
                                          ? 'Sözü al'
                                          : 'Dinlemeyi durdur')
                                    : 'Konuşmayı Başlat',
                                active && !speaking
                                    ? Icons.pause_rounded
                                    : Icons.mic_rounded,
                                active
                                    ? (speaking
                                          ? c.interruptAndListenLive
                                          : c.stopLiveSession)
                                    : c.startLiveSession,
                                primary: true,
                                caption: active
                                    ? (speaking ? 'Sözü al' : 'Durdur')
                                    : 'Başlat',
                                tint: active ? phaseColor : null,
                              ),
                              _control(
                                'Oturumu Bitir',
                                Icons.close_rounded,
                                () async {
                                  await c.stopLiveSession();
                                  c.openTab(0);
                                },
                                caption: 'Bitir',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            active
                                ? 'Bitirmek için “dur” veya “kapat” diyebilirsin.'
                                : 'Başlamak için mikrofona dokun.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: ChatPalette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (active && speaking)
            const Positioned.fill(child: SpeakingEdgeLights()),
        ],
      ),
    );
  }

  static Color _phaseColor(JarvisController c, bool active) {
    if (!active) return ChatPalette.accent;
    switch (c.livePhase) {
      case LiveVoicePhase.speaking:
        return const Color(0xFF187BFF);
      case LiveVoicePhase.thinking:
        return const Color(0xFFD9962B);
      default:
        return ChatPalette.accent;
    }
  }

  Widget _phaseChip(JarvisController c, bool active, Color color) {
    final label = !active
        ? 'Hazır'
        : switch (c.livePhase) {
            LiveVoicePhase.speaking => 'Konuşuyor',
            LiveVoicePhase.thinking => 'Düşünüyor',
            LiveVoicePhase.listening => 'Dinliyor',
            _ => 'Hazır',
          };
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ChatPalette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sttNotice(JarvisController c) => Container(
    key: const Key('live_stt_notice'),
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
    decoration: BoxDecoration(
      color: const Color(0xFFD9962B).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFFD9962B).withValues(alpha: 0.35),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.cloud_outlined,
              size: 18,
              color: Color(0xFFD9962B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Telefonun Türkçe konuşma modeli kurulu değil. Sesin '
                'internet üzerinden çözülüyor. Model inince Ege daha hızlı '
                've çevrimdışı anlar; indirmek için Wi-Fi gerekebilir.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: ChatPalette.ink,
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: c.requestPhoneSttModel,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Modeli indir'),
          ),
        ),
      ],
    ),
  );

  Widget _speakerLabel(String text, Color color) => Text(
    text,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
      color: color,
    ),
  );

  Widget _control(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool primary = false,
    String? caption,
    Color? tint,
  }) {
    final size = primary ? 68.0 : 58.0;
    return SizedBox(
      width: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 68,
            child: Center(
              child: Tooltip(
                message: label,
                child: Semantics(
                  label: label,
                  button: true,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: IconButton.filled(
                      onPressed: onTap,
                      icon: Icon(icon, size: primary ? 30 : 24),
                      style: IconButton.styleFrom(
                        backgroundColor: primary
                            ? (tint ?? ChatPalette.ink)
                            : ChatPalette.soft,
                        foregroundColor: primary
                            ? (tint != null
                                  ? Colors.white
                                  : ChatPalette.background)
                            : ChatPalette.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
                  color: primary ? ChatPalette.ink : ChatPalette.muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _promptLiveText(BuildContext context, JarvisController c) async {
    final textCtrl = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Canlı Oturuma Mesaj Gönder'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Örn: El fenerini aç veya hava durumunu özetle',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textCtrl.text),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    textCtrl.dispose();
    if (submitted != null && submitted.trim().isNotEmpty) {
      await c.sendRealtimeTextPrompt(submitted.trim());
    }
  }
}
