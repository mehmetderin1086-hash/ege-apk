import 'package:flutter/material.dart';

import '../kagit_models.dart';
import '../kagit_store.dart';
import '../theme_kagit.dart';

IconData kagitToolIcon(String name) {
  switch (name) {
    case 'edit_note':
      return Icons.edit_note_rounded;
    case 'draw':
      return Icons.draw_rounded;
    case 'layers_clear':
      return Icons.layers_rounded;
    case 'note_add':
      return Icons.note_add_rounded;
    case 'merge':
      return Icons.call_merge_rounded;
    case 'call_split':
      return Icons.call_split_rounded;
    case 'view_agenda':
      return Icons.view_carousel_rounded;
    case 'grid_view':
      return Icons.grid_view_rounded;
    case 'menu_book':
      return Icons.menu_book_rounded;
    case 'aspect_ratio':
      return Icons.aspect_ratio_rounded;
    case 'crop':
      return Icons.crop_rounded;
    case 'water_drop':
      return Icons.branding_watermark_rounded;
    case 'format_list_numbered':
      return Icons.format_list_numbered_rounded;
    case 'compress':
      return Icons.compress_rounded;
    case 'document_scanner':
      return Icons.document_scanner_rounded;
    case 'photo_library':
      return Icons.photo_library_rounded;
    case 'text_fields':
      return Icons.text_fields_rounded;
    case 'description':
      return Icons.description_rounded;
    case 'table_chart':
      return Icons.table_chart_rounded;
    case 'auto_stories':
      return Icons.auto_stories_rounded;
    case 'code':
      return Icons.code_rounded;
    case 'image':
      return Icons.image_rounded;
    case 'visibility_off':
      return Icons.visibility_off_rounded;
    case 'compare':
      return Icons.compare_rounded;
    case 'cleaning_services':
      return Icons.cleaning_services_rounded;
    case 'folder_copy':
      return Icons.folder_copy_rounded;
    case 'shuffle':
      return Icons.shuffle_rounded;
    case 'school':
      return Icons.school_rounded;
    case 'calculate':
      return Icons.calculate_rounded;
    case 'summarize':
      return Icons.summarize_rounded;
    case 'translate':
      return Icons.translate_rounded;
    case 'chat':
      return Icons.forum_rounded;
    case 'quiz':
      return Icons.quiz_rounded;
    default:
      return Icons.picture_as_pdf_rounded;
  }
}

void showKagitSnack(BuildContext context, String message, {bool isError = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade800 : KagitTema.koyuMurekkep,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class KagitDocCard extends StatelessWidget {
  const KagitDocCard({
    super.key,
    required this.item,
    required this.controller,
    required this.onOpen,
    required this.onOpenTools,
  });

  final KitaplikOgesi item;
  final KagitController controller;
  final VoidCallback onOpen;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) {
    final annCount = controller.annotationsFor(item.id).length;
    final folder = item.folderId != null
        ? controller.folders.where((f) => f.id == item.folderId).firstOrNull
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: KagitTema.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: KagitTema.border(context)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 58,
                decoration: BoxDecoration(
                  color: KagitTema.vurgu.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: KagitTema.vurgu.withValues(alpha: 0.28)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: KagitTema.vurgu, size: 22),
                    const SizedBox(height: 2),
                    Text(
                      '${item.pageCount} s',
                      style: const TextStyle(
                        color: KagitTema.vurgu,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: kagitSerif(context, size: 15.5),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${formatFileSizeTr(item.fileSize)} • ${formatRelativeDateTr(item.lastOpenedAt ?? item.modifiedAt)}',
                          style: TextStyle(fontSize: 12, color: KagitTema.inkSecondary(context)),
                        ),
                        if (annCount > 0)
                          _MiniChip(
                            label: '$annCount not',
                            color: KagitTema.vurgu,
                          ),
                        if (folder != null)
                          _MiniChip(
                            label: folder.name,
                            color: Color(folder.colorValue),
                          ),
                        for (final tag in item.tags.take(2))
                          _MiniChip(
                            label: tag,
                            color: KagitTema.murekkepMavi,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: item.isStarred ? 'Yıldızı kaldır' : 'Yıldızla',
                onPressed: () => controller.toggleStar(item),
                icon: Icon(
                  item.isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                  color: item.isStarred ? KagitTema.altinMuhur : KagitTema.inkSecondary(context),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: KagitTema.inkSecondary(context)),
                onSelected: (action) => _handleMenuAction(context, action),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'open', child: Text('Aç ve Oku')),
                  const PopupMenuItem(value: 'tools', child: Text('Araçla İşle')),
                  const PopupMenuItem(value: 'rename', child: Text('Yeniden Adlandır')),
                  const PopupMenuItem(value: 'folder', child: Text('Klasöre Taşı')),
                  const PopupMenuItem(value: 'saveas', child: Text('Cihaza Dışa Kaydet')),
                  const PopupMenuItem(value: 'share', child: Text('Paylaş')),
                  if (item.inTrash) ...[
                    const PopupMenuItem(value: 'restore', child: Text('Geri Yükle')),
                    const PopupMenuItem(value: 'purge', child: Text('Kalıcı Olarak Sil')),
                  ] else
                    const PopupMenuItem(value: 'trash', child: Text('Çöp Kutusuna At')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, String action) async {
    switch (action) {
      case 'open':
        onOpen();
      case 'tools':
        onOpenTools();
      case 'rename':
        final ctrl = TextEditingController(text: item.title);
        final res = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Belgeyi Yeniden Adlandır'),
            content: TextField(controller: ctrl, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );
        ctrl.dispose();
        if (res != null) controller.renameItem(item, res);
      case 'folder':
        final chosen = await showDialog<String?>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Klasör Seç'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, '__none__'),
                child: const Text('Klasörsüz (Kök Kitaplık)'),
              ),
              for (final f in controller.folders)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, f.id),
                  child: Row(
                    children: [
                      Icon(Icons.folder_rounded, color: Color(f.colorValue), size: 18),
                      const SizedBox(width: 8),
                      Text(f.name),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (chosen != null) {
          controller.moveToFolder(item, chosen == '__none__' ? null : chosen);
        }
      case 'saveas':
        final ok = await controller.saveFileToUserLocation(
          item.path,
          '${item.title}.pdf',
          'application/pdf',
        );
        if (context.mounted) {
          showKagitSnack(context, ok ? 'PDF cihaza kaydedildi.' : 'Kayıt iptal edildi.');
        }
      case 'share':
        await controller.shareFile(item.path, title: item.title);
      case 'trash':
        controller.moveToTrash(item);
        if (context.mounted) showKagitSnack(context, 'Çöp kutusuna taşındı.');
      case 'restore':
        controller.restoreFromTrash(item);
      case 'purge':
        controller.deletePermanently(item);
    }
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

Future<KitaplikOgesi?> showPickDocumentSheet(
  BuildContext context,
  KagitController controller, {
  String title = 'İşlenecek PDF Belgesini Seçin',
}) {
  return showModalBottomSheet<KitaplikOgesi>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: kagitSerif(ctx, size: 17))),
                  TextButton.icon(
                    onPressed: () async {
                      final imported = await controller.importPdfsFromDevice(allowMultiple: false);
                      if (imported.isNotEmpty && ctx.mounted) {
                        Navigator.pop(ctx, imported.first);
                      }
                    },
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: const Text('Cihazdan Al'),
                  ),
                ],
              ),
            ),
            if (controller.activeItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Text('Kitaplıkta henüz belge yok. Yukarıdan cihazdan PDF seçebilirsiniz.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: controller.activeItems.length,
                  itemBuilder: (_, i) {
                    final doc = controller.activeItems[i];
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf_rounded, color: KagitTema.vurgu),
                      title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${doc.pageCount} sayfa • ${formatFileSizeTr(doc.fileSize)}'),
                      onTap: () => Navigator.pop(ctx, doc),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
