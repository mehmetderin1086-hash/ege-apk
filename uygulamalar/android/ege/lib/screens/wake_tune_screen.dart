import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/device_bridge.dart';
import '../services/speaker_identity.dart';
import '../services/wake_calibration.dart';
import '../services/wake_word.dart';
import '../state/jarvis_controller.dart';
import '../widgets/chat_palette.dart';

/// "Asistan"yi kullanıcının sesine göre ayarlar: beş kısa kayıt alınır,
/// cihazdaki algılayıcıyla denenir ve kişisel anahtar sözcük satırı kaydedilir.
class WakeTuneScreen extends StatefulWidget {
  const WakeTuneScreen({super.key, required this.controller});
  final JarvisController controller;

  static const sampleCount = 5;

  @override
  State<WakeTuneScreen> createState() => _WakeTuneScreenState();
}

class _WakeTuneScreenState extends State<WakeTuneScreen> {
  final clips = <Float32List>[];
  bool busy = false;
  bool recording = false;
  bool hasCustom = false;
  int generation = 0;
  late final bool wasWakeStopped;
  WakeCalibrationResult? result;
  String status =
      'Normal konuşma mesafesinden, her seferinde bir kez “Asistan” de. '
      'Bir kaydı biraz kısık sesle söylemek de faydalı olur.';

  JarvisController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    wasWakeStopped = c.wakeWordStoppedByUser;
    // Kayıt sırasında uyandırma mikrofonu meşgul etmesin.
    c.wakeWordStoppedByUser = true;
    unawaited(c.stopWakeWord());
    unawaited(
      WakeCalibration.savedLine().then((line) {
        if (mounted) setState(() => hasCustom = line != null);
      }),
    );
  }

  @override
  void dispose() {
    generation++;
    if (recording) unawaited(DeviceBridge.cancelMicCapture());
    c.wakeWordStoppedByUser = wasWakeStopped;
    // Yeniden başlayan motor yeni (ya da silinmiş) kişisel satırı okur.
    unawaited(c.resumeWakeWord());
    super.dispose();
  }

  Future<void> _record() async {
    if (busy || clips.length >= WakeTuneScreen.sampleCount) return;
    final token = ++generation;
    setState(() {
      busy = true;
      result = null;
      status = 'Mikrofon hazırlanıyor...';
    });
    try {
      await c.stopLiveSession();
      await c.stopSpeaking();
      DeviceBridge.setMicCallbacks();
      final started = await DeviceBridge.startMicCapture(
        endSilenceMs: 4000,
        noSpeechMs: 10000,
      );
      if (started != 'OK') throw StateError('Mikrofon açılamadı: $started');
      recording = true;
      for (var left = 3; left > 0; left--) {
        if (!mounted || token != generation) return;
        setState(() => status = '“Asistan” de · $left');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final wav = await DeviceBridge.stopMicCapture();
      recording = false;
      if (!mounted || token != generation) return;
      final pcm = wav == null
          ? Float32List(0)
          : SpeakerIdentity.pcmFromWav(wav);
      if (pcm.length < 8000) {
        throw StateError('Ses duyulmadı; biraz daha yakından tekrar dene.');
      }
      clips.add(pcm);
      if (clips.length < WakeTuneScreen.sampleCount) {
        setState(
          () => status =
              '${clips.length}/${WakeTuneScreen.sampleCount} kayıt hazır. Sıradakini kaydet.',
        );
        return;
      }
      setState(() => status = 'Kayıtlar algılayıcıyla deneniyor...');
      final t = WakeWordEngine.tuning(c.settings.wakeWordSensitivity);
      final r = await WakeCalibration.calibrate(
        modelDir: await WakeWordEngine.instance.modelDir(),
        clips: List.of(clips),
        defaultPaths: WakeWordEngine.defaultPaths,
        defaultThreshold: t.threshold,
      );
      if (!mounted || token != generation) return;
      setState(() {
        result = r;
        status = r.caughtCount == clips.length
            ? 'Harika: ${r.caughtCount}/${clips.length} kaydın hepsi yakalandı. '
                  'Kaydedip uyandırmayı bu ayarla kullanabilirsin.'
            : '${r.caughtCount}/${clips.length} kayıt yakalandı. Kaydetmek yine '
                  'de yardımcı olur; yakalanmayanlar için daha net ya da biraz '
                  'daha uzatarak “Heeey Ege” demeyi dene.';
      });
    } catch (e) {
      if (mounted && token == generation) {
        setState(() => status = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (recording) {
        recording = false;
        await DeviceBridge.cancelMicCapture();
      }
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    final r = result;
    if (r == null) return;
    final f = await WakeCalibration.customFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(r.line, flush: true);
    debugPrint('[Ege] Asistan kişisel ayarı kaydedildi: ${r.line}');
    if (!mounted) return;
    setState(() {
      hasCustom = true;
      clips.clear();
      result = null;
      status = 'Kişisel ayar kaydedildi. Bu ekrandan çıkınca Asistan yeniden başlar.';
    });
  }

  Future<void> _reset() async {
    await WakeCalibration.clear();
    if (!mounted) return;
    setState(() {
      hasCustom = false;
      clips.clear();
      result = null;
      status = 'Kişisel ayar silindi; varsayılan ayar kullanılacak.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = clips.length >= WakeTuneScreen.sampleCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Asistan sözcüğünü sesime göre ayarla')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Ege, “Asistan”yi telefonda çalışan küçük bir modelle dinler. Beş '
            'kısa kayıtla senin söyleyişine en uygun ses yolları ve hassasiyet '
            'seçilir. Kayıtlar telefondan çıkmaz ve işlem bitince silinir.',
            style: TextStyle(color: ChatPalette.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < WakeTuneScreen.sampleCount; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _dot(i),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            status,
            key: const Key('wake_tune_status'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (!done)
            FilledButton.icon(
              key: const Key('wake_tune_record'),
              onPressed: busy ? null : _record,
              icon: const Icon(Icons.mic_rounded),
              label: Text('${clips.length + 1}. kaydı başlat'),
            ),
          if (result != null) ...[
            FilledButton.icon(
              key: const Key('wake_tune_save'),
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Bu ayarı kaydet'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      clips.clear();
                      result = null;
                      status =
                          'Baştan kaydet: her seferinde bir kez “Asistan” de.';
                    }),
              child: const Text('Baştan kaydet'),
            ),
          ],
          if (hasCustom) ...[
            const SizedBox(height: 24),
            Text(
              'Kişisel ayar etkin.',
              style: TextStyle(color: ChatPalette.muted),
              textAlign: TextAlign.center,
            ),
            TextButton(
              key: const Key('wake_tune_reset'),
              onPressed: busy ? null : _reset,
              child: const Text('Varsayılan ayara dön'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dot(int i) {
    final recorded = i < clips.length;
    final caught = result != null && i < result!.caught.length
        ? result!.caught[i]
        : null;
    final color = caught == null
        ? (recorded ? ChatPalette.accent : ChatPalette.border)
        : (caught ? const Color(0xFF34D399) : const Color(0xFFF87171));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: recorded ? color : Colors.transparent,
        border: Border.all(color: color, width: 2),
      ),
      child: caught == null
          ? null
          : Icon(
              caught ? Icons.check_rounded : Icons.close_rounded,
              size: 14,
              color: Colors.white,
            ),
    );
  }
}
