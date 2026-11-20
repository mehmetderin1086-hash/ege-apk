import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'isbn.dart';

class IsbnScannerPage extends StatefulWidget {
  const IsbnScannerPage({
    super.key,
    this.isbnOnly = true,
    this.studentCard = false,
  });
  final bool isbnOnly;
  final bool studentCard;
  @override
  State<IsbnScannerPage> createState() => _IsbnScannerPageState();
}

class _IsbnScannerPageState extends State<IsbnScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _completed = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu cihazda flaş kullanılamıyor')),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamera değiştirilemedi')),
        );
      }
    }
  }

  Future<void> _promptManualCode() async {
    final ctrl = TextEditingController();
    String? error;
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(
            widget.studentCard
                ? 'Öğrenci kart kodu gir'
                : widget.isbnOnly
                ? 'ISBN numarası gir'
                : 'Barkod / Demirbaş kodu gir',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: widget.studentCard
                      ? 'Örn. OGR-1042'
                      : widget.isbnOnly
                      ? 'Örn. 9789750738609'
                      : 'Örn. 978... veya KB-0001',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: (_) {
                  final code = ctrl.text.trim();
                  if (acceptBarcode(
                    code,
                    isbnOnly: widget.isbnOnly,
                    studentCard: widget.studentCard,
                  )) {
                    Navigator.pop(dialogContext, code);
                  } else {
                    setModalState(() {
                      error = widget.studentCard
                          ? 'OGR ile başlayan geçerli bir kart kodu girin'
                          : widget.isbnOnly
                          ? 'Geçerli bir ISBN-10 veya ISBN-13 girin'
                          : 'Geçerli bir barkod değeri girin';
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal'),
            ),
            FilledButton.icon(
              onPressed: () {
                final code = ctrl.text.trim();
                if (acceptBarcode(
                  code,
                  isbnOnly: widget.isbnOnly,
                  studentCard: widget.studentCard,
                )) {
                  Navigator.pop(dialogContext, code);
                } else {
                  setModalState(() {
                    error = widget.studentCard
                        ? 'OGR ile başlayan geçerli bir kart kodu girin'
                        : widget.isbnOnly
                        ? 'Geçerli bir ISBN-10 veya ISBN-13 girin'
                        : 'Geçerli bir barkod değeri girin';
                  });
                }
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Onayla'),
            ),
          ],
        ),
      ),
    );
    if (entered != null && mounted && !_completed) {
      _completed = true;
      Navigator.of(context).pop(entered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.studentCard
        ? 'Öğrenci kartı tara'
        : widget.isbnOnly
        ? 'ISBN barkodu tara'
        : 'Kitap veya nüsha barkodu tara';
    final hint = widget.studentCard
        ? 'Öğrenci kartındaki barkodu çerçevenin içine hizalayın.'
        : widget.isbnOnly
        ? 'Kitabın arka kapağındaki ISBN barkodunu çerçeveye getirin.'
        : 'ISBN veya demirbaş nüsha barkodunu çerçevenin içine tutun.';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Flaş Kapat' : 'Flaş Aç',
            onPressed: _toggleTorch,
            icon: Icon(
              _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torchOn ? Colors.amber : null,
            ),
          ),
          IconButton(
            tooltip: 'Kamera Değiştir',
            onPressed: _switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    if (_completed) return;
                    for (final barcode in capture.barcodes) {
                      final value = barcode.rawValue?.trim() ?? '';
                      if (acceptBarcode(
                        value,
                        isbnOnly: widget.isbnOnly,
                        studentCard: widget.studentCard,
                      )) {
                        _completed = true;
                        Navigator.of(context).pop(value);
                        break;
                      }
                    }
                  },
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.no_photography_rounded,
                            size: 48,
                            color: scheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.studentCard
                                ? 'Kamera açılamadı. Kamera iznini kontrol edin veya kart kodunu elle girin.'
                                : widget.isbnOnly
                                ? 'Kamera açılamadı. Kamera iznini kontrol edin veya ISBN numarasını elle girin.'
                                : 'Kamera açılamadı. Kamera iznini kontrol edin veya barkodu elle girin.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ScannerReticlePainter(
                      accentColor: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hint,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _promptManualCode,
                    icon: const Icon(Icons.keyboard_rounded),
                    label: const Text('Elle Gir'),
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

class _ScannerReticlePainter extends CustomPainter {
  const _ScannerReticlePainter({required this.accentColor});
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rectWidth = (size.width * 0.72).clamp(200.0, 340.0);
    final rectHeight = (rectWidth * 0.62).clamp(130.0, 210.0);
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: rectWidth,
      height: rectHeight,
    );
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(18)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final cornerPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const arm = 26.0;
    final path = Path()
      // Top-left
      ..moveTo(frame.left, frame.top + arm)
      ..lineTo(frame.left, frame.top)
      ..lineTo(frame.left + arm, frame.top)
      // Top-right
      ..moveTo(frame.right - arm, frame.top)
      ..lineTo(frame.right, frame.top)
      ..lineTo(frame.right, frame.top + arm)
      // Bottom-left
      ..moveTo(frame.left, frame.bottom - arm)
      ..lineTo(frame.left, frame.bottom)
      ..lineTo(frame.left + arm, frame.bottom)
      // Bottom-right
      ..moveTo(frame.right - arm, frame.bottom)
      ..lineTo(frame.right, frame.bottom)
      ..lineTo(frame.right, frame.bottom - arm);
    canvas.drawPath(path, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerReticlePainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

bool acceptBarcode(
  String value, {
  required bool isbnOnly,
  bool studentCard = false,
}) {
  final code = value.trim();
  return code.isNotEmpty &&
      code.length <= 512 &&
      !code.contains(RegExp(r'[\x00-\x1F\x7F]')) &&
      (studentCard
          ? code.toUpperCase().startsWith('OGR')
          : (!isbnOnly || isValidIsbn(code)));
}
