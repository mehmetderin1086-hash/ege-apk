import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'isbn_scanner.dart';

enum ScanSeverity { success, warning, error }

class ScanFeedback {
  const ScanFeedback({
    required this.title,
    this.subtitle = '',
    this.severity = ScanSeverity.success,
  });

  final String title;
  final String subtitle;
  final ScanSeverity severity;
}

class ContinuousScannerPage extends StatefulWidget {
  const ContinuousScannerPage({
    super.key,
    required this.title,
    required this.onBarcode,
    this.onUndo,
    this.isbnOnly = false,
    this.hintText = 'Barkodları sırayla kameraya gösterin. Ekran kapanmadan sayım devam eder.',
  });

  final String title;
  final bool isbnOnly;
  final String hintText;
  final Future<ScanFeedback> Function(String barcode) onBarcode;
  final Future<String?> Function()? onUndo;

  @override
  State<ContinuousScannerPage> createState() => _ContinuousScannerPageState();
}

class _ContinuousScannerPageState extends State<ContinuousScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;
  String? _lastCode;
  DateTime? _lastScanAt;
  ScanFeedback? _lastFeedback;
  int _scanCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String code, {bool forceRepeat = false}) async {
    if (_processing) return;
    final now = DateTime.now();
    if (!forceRepeat &&
        _lastCode == code &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(milliseconds: 2200)) {
      return;
    }
    setState(() => _processing = true);
    try {
      final feedback = await widget.onBarcode(code);
      if (feedback.severity == ScanSeverity.success) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.heavyImpact();
      }
      if (!mounted) return;
      setState(() {
        _lastCode = code;
        _lastScanAt = DateTime.now();
        _lastFeedback = feedback;
        if (feedback.severity != ScanSeverity.error) {
          _scanCount++;
        }
        _processing = false;
      });
    } catch (_) {
      await HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _lastCode = code;
        _lastScanAt = DateTime.now();
        _lastFeedback = const ScanFeedback(
          title: 'Barkod işlenemedi',
          subtitle: 'Tekrar deneyin.',
          severity: ScanSeverity.error,
        );
        _processing = false;
      });
    }
  }

  Future<void> _handleUndo() async {
    if (_processing || widget.onUndo == null) return;
    setState(() => _processing = true);
    try {
      final msg = await widget.onUndo!();
      if (!mounted) return;
      setState(() {
        _processing = false;
        if (msg != null) {
          if (_scanCount > 0) _scanCount--;
          _lastCode = null;
          _lastFeedback = ScanFeedback(
            title: msg,
            severity: ScanSeverity.warning,
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color cardColor = switch (_lastFeedback?.severity) {
      ScanSeverity.success => scheme.primaryContainer,
      ScanSeverity.warning => scheme.tertiaryContainer,
      ScanSeverity.error => scheme.errorContainer,
      null => scheme.surfaceContainerHighest,
    };
    final IconData statusIcon = switch (_lastFeedback?.severity) {
      ScanSeverity.success => Icons.check_circle_outline,
      ScanSeverity.warning => Icons.warning_amber_rounded,
      ScanSeverity.error => Icons.error_outline,
      null => Icons.qr_code_scanner,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} ($_scanCount)'),
        actions: [
          IconButton(
            tooltip: 'El feneri',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
          IconButton(
            tooltip: 'Kamerayı çevir',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    if (_processing) return;
                    for (final barcode in capture.barcodes) {
                      final value = barcode.rawValue?.trim() ?? '';
                      if (acceptBarcode(value, isbnOnly: widget.isbnOnly)) {
                        _handleCode(value);
                        break;
                      }
                    }
                  },
                  errorBuilder: (context, error) => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Kamera açılamadı. Kamera iznini kontrol edin.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                if (_processing)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: cardColor,
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lastFeedback?.title ?? widget.hintText,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  if ((_lastFeedback?.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_lastFeedback!.subtitle),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (_lastCode != null)
                        OutlinedButton.icon(
                          onPressed: _processing
                              ? null
                              : () => _handleCode(_lastCode!, forceRepeat: true),
                          icon: const Icon(Icons.repeat, size: 18),
                          label: const Text('Aynı barkodu tekrar ekle'),
                        ),
                      if (widget.onUndo != null && _scanCount > 0)
                        OutlinedButton.icon(
                          onPressed: _processing ? null : _handleUndo,
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Son okutmayı geri al'),
                        ),
                      FilledButton.icon(
                        onPressed: _processing
                            ? null
                            : () => Navigator.of(context).pop(_scanCount),
                        icon: const Icon(Icons.check),
                        label: const Text('Tamam'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
