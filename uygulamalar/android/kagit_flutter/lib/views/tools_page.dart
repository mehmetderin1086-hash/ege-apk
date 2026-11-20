import 'package:flutter/material.dart';

import '../kagit_models.dart';
import '../kagit_store.dart';
import '../theme_kagit.dart';
import 'shared_kagit_widgets.dart';
import 'tool_runner_sheet.dart';

class KagitToolsPage extends StatefulWidget {
  const KagitToolsPage({super.key, required this.controller});

  final KagitController controller;

  @override
  State<KagitToolsPage> createState() => _KagitToolsPageState();
}

class _KagitToolsPageState extends State<KagitToolsPage> {
  String _query = '';
  KagitToolCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final categories = _selectedCategory != null ? [_selectedCategory!] : KagitToolCategory.values;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('Tüm PDF ve Stüdyo Araçları', style: kagitSerif(context, size: 22)),
        const SizedBox(height: 4),
        Text(
          '${kagitToolsCatalog.length} profesyonel araç • Tamamı Türkçe, çoğu tamamen çevrimdışı çalışır.',
          style: TextStyle(fontSize: 13, color: KagitTema.inkSecondary(context)),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Araç ara (birleştir, OCR, karart, kitapçık, Excel...)',
            filled: true,
            fillColor: KagitTema.cardBg(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: KagitTema.border(context)),
            ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Tümü'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
              ),
              for (final cat in KagitToolCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat.title),
                    selected: _selectedCategory == cat,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final cat in categories) ...[
          Builder(
            builder: (context) {
              final tools = kagitToolsCatalog.where((t) {
                if (t.category != cat) return false;
                if (q.isEmpty) return true;
                return t.title.toLowerCase().contains(q) || t.subtitle.toLowerCase().contains(q);
              }).toList();
              if (tools.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(cat.title, style: kagitSerif(context, size: 17)),
                        const SizedBox(width: 6),
                        Text(
                          '(${tools.length})',
                          style: TextStyle(fontSize: 12, color: KagitTema.inkSecondary(context)),
                        ),
                      ],
                    ),
                  ),
                  for (final t in tools)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      color: KagitTema.cardBg(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: KagitTema.border(context)),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: cat.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(kagitToolIcon(t.iconName), color: cat.color),
                        ),
                        title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        subtitle: Text(t.subtitle, style: const TextStyle(fontSize: 12.5)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                        onTap: () => runKagitTool(context, widget.controller, t),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
