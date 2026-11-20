import 'package:flutter/material.dart';
import '../state/jarvis_controller.dart';

class AppearanceSettings extends StatelessWidget {
  final JarvisController controller;
  const AppearanceSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Tema'),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'light', label: Text('Açık')),
          ButtonSegment(value: 'dark', label: Text('Koyu')),
          ButtonSegment(value: 'system', label: Text('Sistem')),
        ],
        selected: {c.settings.themeMode},
        onSelectionChanged: (v) => c.updateSettings(c.settings.copyWith(themeMode: v.first)),
      ),
      const SizedBox(height: 16),
      const Text('Arayüz ve konuşma küresi rengi'),
      Wrap(spacing: 8, children: [
        for (final color in const [0xFFB85C3D, 0xFF1976D2, 0xFF00796B, 0xFF7B4DCC, 0xFFC33C73, 0xFF59616D])
          Semantics(label: 'Renk ${color.toRadixString(16).substring(2)}', selected: c.settings.themeAccent == color,
            child: IconButton(onPressed: () => c.updateSettings(c.settings.copyWith(themeAccent: color)),
              icon: Icon(c.settings.themeAccent == color ? Icons.check_circle : Icons.circle, color: Color(color), size: 32))),
        TextButton(onPressed: () => _custom(context), child: const Text('Özel renk')),
      ]),
      Text('Konuşma küresi: ${c.settings.liveOrbSize.round()}'),
      Slider(value: c.settings.liveOrbSize, min: 96, max: 180, divisions: 14,
        onChanged: (v) => c.updateSettings(c.settings.copyWith(liveOrbSize: v))),
      const Text('Mavi dalgalı kenar ışıkları yalnız Ege konuşurken yanar.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
    ]);
  }
  Future<void> _custom(BuildContext context) async {
    final input = TextEditingController(text: controller.settings.themeAccent.toRadixString(16).substring(2).toUpperCase());
    final color = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Özel renk'),
      content: TextField(controller: input, maxLength: 7, decoration: const InputDecoration(labelText: 'HEX renk', hintText: '#1976D2')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        FilledButton(onPressed: () {
          final raw = input.text.trim().replaceFirst('#', '');
          if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) Navigator.pop(ctx, int.parse(raw, radix: 16) | 0xFF000000);
        }, child: const Text('Uygula')),
      ],
    ));
    input.dispose();
    if (color != null) await controller.updateSettings(controller.settings.copyWith(themeAccent: color));
  }
}
