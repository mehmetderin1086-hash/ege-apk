import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_bridge.dart';
import '../services/speaker_identity.dart';
import '../state/jarvis_controller.dart';

class SpeakerProfileScreen extends StatefulWidget {
  const SpeakerProfileScreen({super.key, required this.controller});
  final JarvisController controller;
  @override
  State<SpeakerProfileScreen> createState() => _SpeakerProfileScreenState();
}

class _SpeakerProfileScreenState extends State<SpeakerProfileScreen> {
  final identity = SpeakerIdentity.instance;
  final samples = <List<double>>[];
  final wakeSamples = <List<double>>[];
  bool busy = false;
  bool recording = false;
  int generation = 0;
  bool wasWakeStopped = false;
  bool renewingProfile = false;
  String status = 'Sessiz bir yerde, normal sesinle üç kısa örnek kaydet.';
  static const phrases = [
    'Asistan, benim sesimi tanı. Bugün birlikte işlerimizi tamamlayacağız.',
    'Asistan, beni dinle. Ekrandaki saatleri ve mesajları bana okuyabilirsin.',
    'Asistan, yalnızca benim söylediklerime yanıt ver. Şimdi konuşmaya hazırım.',
  ];
  @override
  void initState() {
    super.initState();
    wasWakeStopped = widget.controller.wakeWordStoppedByUser;
    // stopLiveSession schedules resumeWakeWord after 800 ms. Hold the pause
    // for this entire screen so that callback cannot steal enrollment audio.
    widget.controller.wakeWordStoppedByUser = true;
    unawaited(widget.controller.stopWakeWord());
    unawaited(
      identity.load().then((_) {
        if (mounted) {
          setState(() {
            if (identity.enrolled) {
              status = identity.wakeEnrolled
                  ? 'Genel ses profilin ve Asistan kalibrasyonun kayıtlı.'
                  : 'Genel ses profilin hazır. Şimdi üç kısa Asistan örneği kaydet.';
            }
          });
        }
      }),
    );
  }

  Future<void> record({bool wake = false}) async {
    if (busy) return;
    final token = ++generation;
    setState(() {
      busy = true;
      status = 'Mikrofon hazırlanıyor...';
    });
    try {
      await widget.controller.stopLiveSession();
      await widget.controller.stopWakeWord();
      await widget.controller.stopSpeaking();
      DeviceBridge.setMicCallbacks();
      if (!mounted || token != generation) return;
      final result = await DeviceBridge.startMicCapture(
        endSilenceMs: 4000,
        noSpeechMs: 10000,
      );
      if (result != 'OK') throw StateError('Mikrofon açılamadı: $result');
      recording = true;
      for (var left = wake ? 3 : 7; left > 0; left--) {
        if (!mounted || token != generation) return;
        setState(
          () => status = wake
              ? 'Bir kez normal sesinle “Asistan” de · $left saniye'
              : 'Şimdi oku · $left saniye',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final wav = await DeviceBridge.stopMicCapture();
      recording = false;
      if (!mounted || token != generation) return;
      if (wav == null) throw StateError('Konuşma duyulmadı. Yeniden dene.');
      final raw = SpeakerIdentity.pcmFromWav(wav);
      final pcm = wake ? SpeakerIdentity.prepareWakeSamples(raw) : raw;
      if (pcm.length < (wake ? 12000 : 16000 * 3))
        throw StateError(
          wake
              ? 'Asistan net duyulmadı; tekrar söyle.'
              : 'En az üç saniye konuş.',
        );
      setState(() => status = 'Ses örneği telefonda işleniyor...');
      final vector = await identity.embedding(pcm);
      if (!mounted || token != generation) return;
      final target = wake ? wakeSamples : samples;
      target.add(vector);
      if (target.length == 3) {
        try {
          if (wake) {
            await identity.enrollWake(target);
          } else {
            await identity.enroll(target);
            wakeSamples.clear();
            renewingProfile = false;
          }
        } catch (_) {
          target.clear();
          rethrow;
        }
        setState(
          () => status = wake
              ? 'Asistan kalibrasyonu hazır. Genel ses profilin korundu.'
              : 'Ses profilin hazır. Aşağıdan Asistan için kısa ses kalibrasyonunu da yapabilirsin.',
        );
      } else {
        setState(
          () => status =
              '${target.length}/3 örnek hazır. ${wake ? 'Bir sonraki Asistan örneğini kaydet.' : 'Sonraki cümleyi kaydet.'}',
        );
      }
    } catch (e) {
      if (mounted && token == generation) {
        setState(() => status = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (recording) {
        recording = false;
        await DeviceBridge.cancelMicCapture();
      }
      if (mounted && token == generation) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    generation++;
    if (recording) unawaited(DeviceBridge.cancelMicCapture());
    // stopWakeWord is an explicit temporary pause during enrollment.
    widget.controller.wakeWordStoppedByUser = wasWakeStopped;
    unawaited(widget.controller.resumeWakeWord());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Yalnızca benim sesim')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.record_voice_over, size: 48),
        const SizedBox(height: 20),
        Text(status, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        if ((!identity.enrolled || renewingProfile) && samples.length < 3) ...[
          Text(
            phrases[samples.length],
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : () => record(),
            icon: const Icon(Icons.mic),
            label: Text('${samples.length + 1}. örneği kaydet'),
          ),
        ],
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (identity.enrolled && !renewingProfile) ...[
          const SizedBox(height: 20),
          const Text(
            'Asistan için ses kalibrasyonu',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            identity.wakeEnrolled ? 'Kısa uyandırma sesi kayıtlı.' : 'Kısa “Asistan” sesi genel konuşmandan farklı eşleşebilir. Normal kullanım mesafesinden üç ayrı örnek kaydet.',
          ),
          if (wakeSamples.length < 3)
            FilledButton.tonalIcon(
              onPressed: busy ? null : () => record(wake: true),
              icon: const Icon(Icons.hearing),
              label: Text('Asistan · ${wakeSamples.length + 1}. örneği kaydet'),
            ),
          if (wakeSamples.length == 3)
            TextButton(
              onPressed: busy ? null : () => setState(wakeSamples.clear),
              child: const Text('Asistan örneklerini yenile'),
            ),
        ],
        if (identity.enrolled)
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    samples.clear();
                    renewingProfile = true;
                    status = 'Genel ses profilini yenilemek için üç cümleyi kaydet. Mevcut profil tamamlanana kadar korunur.';
                  }),
            child: const Text('Genel ses profilimi yeniden kaydet'),
          ),
        if (identity.enrolled)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Yalnızca benim sesim'),
            value: identity.enabled,
            onChanged: busy
                ? null
                : (v) async {
                    await widget.controller.stopWakeWord();
                    await identity.setEnabled(v);
                    if (mounted) {
                      setState(() {});
                    }
                  },
          ),
        if (identity.enrolled)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Ses profilin silinsin mi?'),
                        content: const Text(
                          'Genel ses profilin ve Asistan örneklerin kaldırılır. Yeniden kayıt yapman gerekir.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Vazgeç'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Profili sil'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) return;
                    try {
                      await widget.controller.stopWakeWord();
                      await identity.forget();
                      samples.clear();
                      wakeSamples.clear();
                      if (mounted) {
                        setState(
                          () => status =
                              'Ses profili silindi. Yeniden kaydedebilirsin.',
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => status = 'Profil silinemedi. Tekrar dene.',
                        );
                      }
                    }
                  },
            child: const Text('Ses profilimi sil'),
          ),
        const SizedBox(height: 24),
        const Text(
          'Ses örnekleri gönderilmez ve saklanmaz. Ses profili yalnızca bu telefonda tutulur; sohbetlere ve Obsidian’a eklenmez.\n\nBu özellik ses filtresidir. Ses kaydı veya taklitlere karşı kimlik doğrulama güvencesi vermez. Gürültüde yeniden konuşman gerekebilir.',
        ),
      ],
    ),
  );
}
