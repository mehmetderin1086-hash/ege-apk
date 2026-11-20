import 'package:flutter/material.dart';

import '../kagit_models.dart';
import '../kagit_store.dart';
import '../theme_kagit.dart';
import 'shared_kagit_widgets.dart';
import 'tool_runner_sheet.dart';

class KagitFilesPage extends StatefulWidget {
  const KagitFilesPage({
    super.key,
    required this.controller,
    required this.onSwitchToTools,
  });

  final KagitController controller;
  final VoidCallback onSwitchToTools;

  @override
  State<KagitFilesPage> createState() => _KagitFilesPageState();
}

class _KagitFilesPageState extends State<KagitFilesPage> {
  String _query = '';
  String _selectedScope = 'all'; // all | starred | trash | folder:<id>

  List<KitaplikOgesi> get _filteredItems {
    Iterable<KitaplikOgesi> source;
    if (_selectedScope == 'trash') {
      source = widget.controller.trashItems;
    } else if (_selectedScope == 'starred') {
      source = widget.controller.starredItems;
    } else if (_selectedScope.startsWith('folder:')) {
      final fid = _selectedScope.substring('folder:'.length);
      source = widget.controller.activeItems.where((i) => i.folderId == fid);
    } else {
      source = widget.controller.activeItems;
    }

    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return source.toList();
    return source
        .where(
          (d) =>
              d.title.toLowerCase().contains(q) ||
              d.tags.any((t) => t.toLowerCase().contains(q)),
        )
        .toList();
  }

  Future<void> _showCreateFolderDialog() async {
    final ctrl = TextEditingController();
    int selectedColor = 0xFFDB3D33;
    const colors = [0xFFDB3D33, 0xFFD98E26, 0xFF288557, 0xFF2F64B8, 0xFF7B4EC2];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Yeni Klasör'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Klasör Adı', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in colors)
                    GestureDetector(
                      onTap: () => setS(() => selectedColor = c),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(c),
                        child: selectedColor == c
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            FilledButton(
              onPressed: () {
                widget.controller.createFolder(ctrl.text, colorValue: selectedColor);
                Navigator.pop(ctx);
              },
              child: const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docs = _filteredItems;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(child: Text('Dosyalar ve Klasörler', style: kagitSerif(context, size: 22))),
              IconButton(
                tooltip: 'Klasör Oluştur',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _showCreateFolderDialog,
              ),
              PopupMenuButton<KitapSortOrder>(
                tooltip: 'Sırala',
                icon: const Icon(Icons.sort_rounded),
                initialValue: widget.controller.sortOrder,
                onSelected: widget.controller.setSortOrder,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: KitapSortOrder.recent, child: Text('Son Açılan')),
                  PopupMenuItem(value: KitapSortOrder.name, child: Text('Ada Göre (A-Z)')),
                  PopupMenuItem(value: KitapSortOrder.size, child: Text('Dosya Boyutu')),
                  PopupMenuItem(value: KitapSortOrder.pages, child: Text('Sayfa Sayısı')),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Dosya adı veya etikete göre ara...',
              filled: true,
              fillColor: KagitTema.cardBg(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: KagitTema.border(context)),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _scopeChip('all', 'Tümü (${widget.controller.activeItems.length})'),
              _scopeChip('starred', 'Yıldızlı (${widget.controller.starredItems.length})'),
              for (final f in widget.controller.folders)
                _scopeChip('folder:${f.id}', f.name, color: Color(f.colorValue)),
              _scopeChip('trash', 'Çöp (${widget.controller.trashItems.length})'),
            ],
          ),
        ),
        if (_selectedScope == 'trash' && widget.controller.trashItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: OutlinedButton.icon(
              onPressed: () {
                widget.controller.emptyTrash();
                showKagitSnack(context, 'Çöp kutusu boşaltıldı.');
              },
              icon: const Icon(Icons.delete_forever_rounded, color: KagitTema.vurgu),
              label: const Text('Çöp Kutusunu Kalıcı Temizle'),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: docs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _selectedScope == 'trash'
                          ? 'Çöp kutusu boş.'
                          : 'Bu görünümde eşleşen PDF belgesi bulunamadı.',
                      style: TextStyle(color: KagitTema.inkSecondary(context)),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  itemCount: docs.length,
                  itemBuilder: (_, i) => KagitDocCard(
                    item: docs[i],
                    controller: widget.controller,
                    onOpen: () => openKagitViewer(context, widget.controller, docs[i]),
                    onOpenTools: widget.onSwitchToTools,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _scopeChip(String key, String label, {Color? color}) {
    final active = _selectedScope == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: color != null ? Icon(Icons.folder_rounded, size: 16, color: color) : null,
        label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        selected: active,
        onSelected: (_) => setState(() => _selectedScope = key),
      ),
    );
  }
}
