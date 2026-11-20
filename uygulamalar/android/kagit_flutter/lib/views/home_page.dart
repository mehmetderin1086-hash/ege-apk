import 'package:flutter/material.dart';

import '../kagit_models.dart';
import '../kagit_store.dart';
import '../theme_kagit.dart';
import 'shared_kagit_widgets.dart';
import 'tool_runner_sheet.dart';

class KagitHomePage extends StatelessWidget {
  const KagitHomePage({
    super.key,
    required this.controller,
    required this.onSwitchTab,
  });

  final KagitController controller;
  final void Function(int index) onSwitchTab;

  @override
  Widget build(BuildContext context) {
    final recent = controller.recentOpenedItems;
    final starred = controller.starredItems;
    final recentToolModels = controller.recentTools
        .map((id) => kagitToolsCatalog.where((t) => t.id == id).firstOrNull)
        .whereType<KagitTool>()
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        KagitHeroBanner(
          imageAsset: 'assets/images/kagit_desk_backdrop.jpg',
          badge: 'KÂĞIT PDF ATÖLYESİ',
          title: 'Editoryal PDF, Tarama ve Sınav Stüdyosu',
          subtitle:
              '${controller.activeItems.length} belge kitaplığınızda • Çevrimdışı ML Kit OCR, imza, kitapçık basım ve CLIProxyAPI.',
          trailing: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Image.asset('assets/images/kagit_icon.png', width: 34, height: 34),
          ),
          bottomWidget: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: KagitTema.vurgu,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onPressed: () {
                    final tool = kagitToolsCatalog.firstWhere((t) => t.id == KagitToolId.kameraTara);
                    runKagitTool(context, controller, tool);
                  },
                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Kamerayla Tara', maxLines: 1),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    foregroundColor: KagitTema.koyuMurekkep,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onPressed: () async {
                    final added = await controller.importPdfsFromDevice(allowMultiple: true);
                    if (context.mounted && added.isNotEmpty) {
                      showKagitSnack(context, '${added.length} PDF kitaplığa aktarıldı.');
                    }
                  },
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('PDF İçe Aktar', maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Hızlı Stüdyo Kısayolları
        Row(
          children: [
            _QuickDockTile(
              icon: Icons.note_add_rounded,
              label: 'Boş PDF',
              color: KagitTema.murekkepMavi,
              onTap: () {
                final t = kagitToolsCatalog.firstWhere((e) => e.id == KagitToolId.bosPdfOlustur);
                runKagitTool(context, controller, t);
              },
            ),
            const SizedBox(width: 10),
            _QuickDockTile(
              icon: Icons.call_merge_rounded,
              label: 'Birleştir',
              color: KagitTema.yaprakYesili,
              onTap: () {
                final t = kagitToolsCatalog.firstWhere((e) => e.id == KagitToolId.birlestir);
                runKagitTool(context, controller, t);
              },
            ),
            const SizedBox(width: 10),
            _QuickDockTile(
              icon: Icons.school_rounded,
              label: 'Öğretmen',
              color: KagitTema.altinMuhur,
              onTap: () => onSwitchTab(3),
            ),
            const SizedBox(width: 10),
            _QuickDockTile(
              icon: Icons.build_circle_rounded,
              label: 'Araç Kutusu',
              color: KagitTema.morOkuma,
              onTap: () => onSwitchTab(2),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // Sık Kullanılan Araçlar
        Row(
          children: [
            Text('Hızlı Araçlar', style: kagitSerif(context, size: 19)),
            const Spacer(),
            TextButton(onPressed: () => onSwitchTab(2), child: const Text('33 Aracı Gör')),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recentToolModels.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final tool = recentToolModels[i];
              final accent = tool.category.color;
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => runKagitTool(context, controller, tool),
                child: Container(
                  width: 152,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: KagitTema.cardBg(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: KagitTema.border(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: accent.withValues(alpha: 0.14),
                        child: Icon(kagitToolIcon(tool.iconName), size: 18, color: accent),
                      ),
                      const Spacer(),
                      Text(
                        tool.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        if (starred.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Yıldızlı Belgeler', style: kagitSerif(context, size: 19)),
          const SizedBox(height: 8),
          for (final item in starred.take(3))
            KagitDocCard(
              item: item,
              controller: controller,
              onOpen: () => openKagitViewer(context, controller, item),
              onOpenTools: () => onSwitchTab(2),
            ),
        ],

        const SizedBox(height: 22),
        Row(
          children: [
            Text('Son Belgeler', style: kagitSerif(context, size: 19)),
            const Spacer(),
            TextButton(onPressed: () => onSwitchTab(1), child: const Text('Tüm Dosyalar')),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty && controller.activeItems.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: KagitTema.cardBg(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: KagitTema.border(context)),
            ),
            child: const Column(
              children: [
                Icon(Icons.auto_stories_outlined, size: 36, color: KagitTema.vurgu),
                SizedBox(height: 8),
                Text('Henüz kitaplığınızda belge yok.', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Yukarıdan kamera taraması yapabilir veya cihazınızdan PDF aktarabilirsiniz.'),
              ],
            ),
          )
        else
          for (final item in (recent.isNotEmpty ? recent : controller.activeItems.take(5)))
            KagitDocCard(
              item: item,
              controller: controller,
              onOpen: () => openKagitViewer(context, controller, item),
              onOpenTools: () => onSwitchTab(2),
            ),
      ],
    );
  }
}

class _QuickDockTile extends StatelessWidget {
  const _QuickDockTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
          decoration: BoxDecoration(
            color: KagitTema.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KagitTema.border(context)),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
