import 'dart:io';

import 'package:flutter/material.dart';

import '../models/asistan_models.dart';
import '../services/asistan_controller.dart';
import 'theme_asistan.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.controller});

  final AsistanController controller;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  final TextEditingController _imagePromptCtrl = TextEditingController();
  String _selectedFormat = 'pdf';
  String _selectedImageStyle = 'Siber Holografik';
  int _subTab = 0; // 0: Belge & Kod Tuvali, 1: Görsel Stüdyo, 2: Arşiv

  static const List<String> _formats = [
    'pdf',
    'docx',
    'xlsx',
    'pptx',
    'csv',
    'html',
    'json',
    'md',
    'txt',
  ];

  static const List<String> _imageStyles = [
    'Siber Holografik',
    'Siri Aurora',
    'Sinematik Altın',
    'Zümrüt Kuantum',
  ];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.controller.canvasTitle);
    _contentCtrl = TextEditingController(text: widget.controller.canvasContent);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _imagePromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportDocument() async {
    final c = widget.controller;
    final title = _titleCtrl.text.trim().isEmpty
        ? 'Asistan_Belgesi'
        : _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) return;

    final art = await c.exportCanvasAsDocument(
      title: title,
      content: content,
      format: _selectedFormat,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${art.format.toUpperCase()} belgesi hazır: ${art.title}',
        ),
        action: SnackBarAction(
          label: 'Dışarı Paylaş',
          onPressed: () => c.shareArtifact(art),
        ),
      ),
    );
  }

  Future<void> _generateImage() async {
    final prompt = _imagePromptCtrl.text.trim();
    if (prompt.isEmpty) return;
    final art = await widget.controller.createStudioImage(
      prompt: prompt,
      style: _selectedImageStyle,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Görsel üretildi: ${art.title}'),
        action: SnackBarAction(
          label: 'Paylaş',
          onPressed: () => widget.controller.shareArtifact(art),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final preset = c.themePreset;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Studio Header Banner
          GlassCard3D(
            padding: EdgeInsets.zero,
            borderColor: preset.primary.withValues(alpha: 0.4),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/card_studio_canvas.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xEB070B19),
                        const Color(0xB8070B19),
                        preset.primary.withValues(alpha: 0.25),
                      ],
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CANVAS • OFFICE • IMAGE STUDIO',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Çalışma Tuvali, Belge & Görsel Atölyesi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Gerçek PDF, Word (DOCX), Excel (XLSX), Sunum (PPTX) ve 3D AI görseller oluşturup dışarıya paylaşın.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Sub-tab selector
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  selected: _subTab == 0,
                  label: const Text('📄 Belge & Tuval'),
                  selectedColor: preset.primary,
                  labelStyle: TextStyle(
                    color: _subTab == 0 ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _subTab = 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  selected: _subTab == 1,
                  label: const Text('🎨 Görsel Üret'),
                  selectedColor: preset.secondary,
                  labelStyle: TextStyle(
                    color: _subTab == 1 ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _subTab = 1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  selected: _subTab == 2,
                  label: Text('🗂️ Arşiv (${c.artifacts.length})'),
                  selectedColor: preset.tertiary,
                  labelStyle: TextStyle(
                    color: _subTab == 2 ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _subTab = 2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (_subTab == 0) _buildDocumentCanvasSection(c, preset),
          if (_subTab == 1) _buildImageStudioSection(c, preset),
          if (_subTab == 2) _buildArtifactArchiveSection(c, preset),
        ],
      ),
    );
  }

  Widget _buildDocumentCanvasSection(
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    return GlassCard3D(
      enable3DTilt: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
            decoration: const InputDecoration(
              labelText: 'Belge / Proje Başlığı',
              labelStyle: TextStyle(color: Colors.white70),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Çıktı Formatı Seçin:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _formats.map((fmt) {
              final active = _selectedFormat == fmt;
              return ChoiceChip(
                selected: active,
                label: Text(fmt.toUpperCase()),
                selectedColor: preset.primary,
                labelStyle: TextStyle(
                  color: active ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _selectedFormat = fmt),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _contentCtrl,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
              ),
              minLines: 10,
              maxLines: 18,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Rapor, tablo veya kod içeriğini buraya yazın...',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 1-Tap All Office Formats Pack Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final title = _titleCtrl.text.trim().isEmpty
                  ? 'Asistan_Raporu'
                  : _titleCtrl.text.trim();
              final content = _contentCtrl.text.trim();
              if (content.isEmpty) return;
              final list = await c.createAllOfficeFormatsPack(
                title: title,
                content: content,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '🎉 Tüm Ofis Paketi (${list.length} dosya: PDF, Word, Excel, Sunum, CSV, HTML ve Ses) İndirilenler/Asistan klasörüne kaydedildi!',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.folder_zip_rounded),
            label: const Text(
              '📦 Tüm Ofis Paketini Tek Tuşla İndir (PDF+Word+Excel+Sunum+Ses)',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: preset.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _exportDocument,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(
                    '${_selectedFormat.toUpperCase()} Olarak İndir',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFA855F7)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                ),
                onPressed: () async {
                  final title = _titleCtrl.text.trim().isEmpty
                      ? 'Asistan_Ses'
                      : _titleCtrl.text.trim();
                  final art = await c.createAndDownloadAudioFile(
                    _contentCtrl.text,
                    title: title,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        art != null
                            ? '🎵 Ses dosyası indirildi: ${art.title}'
                            : '⚠️ Ses dosyası oluşturulamadı.',
                      ),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.library_music_rounded,
                  size: 18,
                  color: Color(0xFFA855F7),
                ),
                label: const Text('🎵 Ses İndir'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageStudioSection(
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    final imageArtifacts = c.artifacts.where((a) => a.isImage).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard3D(
          enable3DTilt: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '🎨 Yapay Zeka Görsel & Poster Üretici',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _imagePromptCtrl,
                style: const TextStyle(color: Colors.white),
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Üretilecek görseli tarif edin (örn: Kuantum laboratuvarında parlayan 3D kristal yapay zeka küresi)...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _imageStyles.map((st) {
                  final active = _selectedImageStyle == st;
                  return ChoiceChip(
                    selected: active,
                    label: Text(st),
                    selectedColor: preset.secondary,
                    labelStyle: TextStyle(
                      color: active ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => setState(() => _selectedImageStyle = st),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: preset.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: c.isGenerating ? null : _generateImage,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  c.isGenerating
                      ? 'Görsel İşleniyor...'
                      : 'Yüksek Çözünürlüklü Görsel Üret',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (imageArtifacts.isNotEmpty)
          ...imageArtifacts.map((art) => _buildArchiveTile(c, art, preset)),
      ],
    );
  }

  Widget _buildArtifactArchiveSection(
    AsistanController c,
    AsistanThemePreset preset,
  ) {
    if (c.artifacts.isEmpty) {
      return GlassCard3D(
        enable3DTilt: false,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Henüz üretilmiş bir belge veya görsel yok. Belge veya Görsel sekmesinden hemen oluşturabilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }
    return Column(
      children: c.artifacts
          .map((art) => _buildArchiveTile(c, art, preset))
          .toList(),
    );
  }

  Widget _buildArchiveTile(
    AsistanController c,
    GeneratedArtifact art,
    AsistanThemePreset preset,
  ) {
    final exists = File(art.filePath).existsSync();
    return GlassCard3D(
      margin: const EdgeInsets.only(bottom: 10),
      enable3DTilt: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (art.isImage && exists) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(art.filePath),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              CircleAvatar(
                backgroundColor: preset.primary.withValues(alpha: 0.2),
                child: Icon(
                  art.isImage
                      ? Icons.image_rounded
                      : Icons.insert_drive_file_rounded,
                  color: preset.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      art.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${art.format.toUpperCase()} • ${(art.sizeBytes / 1024).toStringAsFixed(1)} KB',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => c.openArtifact(art),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: Colors.white,
                ),
                tooltip: 'Aç',
              ),
              IconButton(
                onPressed: () => c.shareArtifact(art),
                icon: Icon(Icons.share_rounded, color: preset.primary),
                tooltip: 'Paylaş',
              ),
              IconButton(
                onPressed: () => c.saveArtifactToDevice(art),
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                tooltip: 'Cihaza Kaydet',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
