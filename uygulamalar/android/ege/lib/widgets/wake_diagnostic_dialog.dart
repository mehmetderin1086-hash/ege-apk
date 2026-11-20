import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_bridge.dart';

/// Explicit, short local diagnostic. Audio is never stored; text stays in RAM
/// and is cleared when the dialog closes. No private speech is written to logs.
class WakeDiagnosticDialog extends StatefulWidget {
  const WakeDiagnosticDialog({super.key});
  @override
  State<WakeDiagnosticDialog> createState() => _WakeDiagnosticDialogState();
}

class _WakeDiagnosticDialogState extends State<WakeDiagnosticDialog> {
  Timer? _timer;
  final _clock = Stopwatch();
  Map<String, dynamic> _info = {};
  String? _error;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final ok = await DeviceBridge.wakeDiagnosticStart();
    if (!mounted) {
      await DeviceBridge.wakeDiagnosticEnd();
      return;
    }
    if (!ok) {
      setState(
        () => _error = 'Uyandırma dinlemesi açık değil. Canlı görüşmeyi kapatıp uyandırmayı yeniden başlat.',
      );
      return;
    }
    _clock.start();
    await _poll();
    if (!mounted) return;
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final info = await DeviceBridge.wakeWordInfo();
      if (!mounted) return;
      setState(() => _info = info);
      if (_clock.elapsed.inSeconds >= 40) _timer?.cancel();
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(DeviceBridge.wakeDiagnosticEnd());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (30 - _clock.elapsed.inSeconds).clamp(0, 30);
    final texts =
        (_info['diagnosticTexts'] as List?)?.cast<String>() ?? const <String>[];
    final peak = ((_info['diagnosticPeak'] as num?)?.toDouble() ?? 0)
        .toStringAsFixed(5);
    return AlertDialog(
      title: const Text('Asistan tanılaması'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _error ??
                  (remaining > 0
                      ? '$remaining saniye içinde normal sesinle “Asistan” de; 3 saniye arayla tekrarla. Bu testte canlı ekran açılmaz, algılama sayısı artar.'
                      : 'Dinleme testi bitti. Son çözümleme birkaç saniye daha sürebilir.'),
            ),
            const SizedBox(height: 12),
            Text(
              'Mikrofon: ${_info['silenced'] == true ? "Android tarafından susturulmuş" : "açık"}',
            ),
            Text('En yüksek ses seviyesi: $peak'),
            Text('Algılama: ${_info['diagnosticHits'] ?? 0}'),
            Text(
              'Ses filtresi: ${_info['speakerFilter'] == true ? _info['speakerStatus'] ?? "kontrol ediliyor" : "kapalı"}',
            ),
            const SizedBox(height: 10),
            const Text('Yerel çözümleyicinin duyduğu:'),
            if (texts.isEmpty) const Text('Henüz metin yok.'),
            for (final text in texts)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(text),
              ),
            const SizedBox(height: 12),
            const Text(
              'Ses kaydedilmez veya internete gönderilmez. Bu kısa testin metni pencere kapatılınca bellekten silinir.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}
