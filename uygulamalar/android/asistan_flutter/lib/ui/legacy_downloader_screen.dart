import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/asistan_controller.dart';
import '../services/scraper_downloader_service.dart';
import 'theme_asistan.dart';

class LegacyDownloaderScreen extends StatefulWidget {
  final AsistanController controller;

  const LegacyDownloaderScreen({super.key, required this.controller});

  @override
  State<LegacyDownloaderScreen> createState() => _LegacyDownloaderScreenState();
}

class _LegacyDownloaderScreenState extends State<LegacyDownloaderScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _ttsTextCtrl = TextEditingController();
  final TextEditingController _ttsTitleCtrl = TextEditingController(
    text: 'Asistan_Ses_Kaydi',
  );

  String _activeTab = 'all'; // all, image, audio, video, document, text
  bool _showTtsCreator = false;
  bool _wifiOnly = false;
  String _queueStatus = '';

  Future<void> _enqueueDownload() async {
    final result = await widget.controller.invokeNative('enqueueDownload', {
      'url': _inputCtrl.text.trim(),
      'wifiOnly': _wifiOnly,
    });
    if (!mounted) return;
    setState(
      () => _queueStatus = result is Map
          ? result['message']?.toString() ?? 'İşlem tamamlanamadı.'
          : 'Android indirme hizmetine ulaşılamadı.',
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _ttsTextCtrl.dispose();
    _ttsTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _triggerScrape({
    String? mediaFilter,
    String? presetQuery,
  }) async {
    if (presetQuery != null && _inputCtrl.text.trim().isEmpty) {
      _inputCtrl.text = presetQuery;
    }
    final query = _inputCtrl.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lütfen bir web sitesi adresi (URL) veya aranacak konu (örn: İstanbul resimleri, klasik müzik) yazın.',
          ),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.runWebScrapeOrSearch(
      query,
      mediaFilter: mediaFilter ?? 'all',
    );
    if (mediaFilter != null && mediaFilter != 'all') {
      setState(() => _activeTab = mediaFilter);
    } else {
      setState(() => _activeTab = 'all');
    }
  }

  ScrapedMediaType? _tabToMediaType(String tab) {
    return switch (tab) {
      'image' => ScrapedMediaType.image,
      'audio' => ScrapedMediaType.audio,
      'video' => ScrapedMediaType.video,
      'document' => ScrapedMediaType.document,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = c.themePreset;
    final res = c.lastScrapeResult;

    final filterType = _tabToMediaType(_activeTab);
    final filteredItems = res == null
        ? <ScrapedMediaItem>[]
        : res.items
              .where((item) => filterType == null || item.type == filterType)
              .toList();
    final selectedCount = filteredItems.where((e) => e.selected).length;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
        children: [
          GlassCard3D(
            enable3DTilt: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dosya bağlantısından indir',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                TextField(
                  controller: _inputCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'https://…/dosya.zip',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Yalnızca Wi-Fi'),
                  value: _wifiOnly,
                  onChanged: (v) => setState(() => _wifiOnly = v),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _enqueueDownload,
                      child: const Text('Kuyruğa ekle'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await c.invokeNative('showSystemDownloads');
                        if (ok == true || !mounted) return;
                        setState(
                          () => _queueStatus =
                              'Android indirme ekranı açılamadı.',
                        );
                      },
                      child: const Text('İndirmeleri göster'),
                    ),
                  ],
                ),
                if (_queueStatus.isNotEmpty) Text(_queueStatus),
                const Text(
                  'Arka plan indirmesi Android tarafından yönetilir. Bağlantı doğrudan dosyaya ait olmalıdır.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 1. Header & Status Card
          GlassCard3D(
            borderColor: p.primary.withValues(alpha: 0.45),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.primary.withValues(alpha: 0.18),
                      ),
                      child: Icon(
                        Icons.cloud_download_rounded,
                        color: p.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Evrensel İndirici, Web Kazıma & Toplu (Bulk) İndir',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Resim • Video (MP4) • Ses (MP3/WAV) • PDF/Ofis • Web Kazıma',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFF10B981).withValues(alpha: 0.14),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    c.lastDownloadStatus,
                    style: const TextStyle(
                      color: Color(0xFF6EE7B7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (c.isBulkDownloading && c.bulkTotalCount > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: c.bulkCompletedCount / c.bulkTotalCount,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. Simple URL / Topic Input Box
          GlassCard3D(
            borderColor: p.secondary.withValues(alpha: 0.45),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1️⃣ Web Sitesi Linki (URL) veya İndirilecek Konu Yazın:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _inputCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14.5),
                  onSubmitted: (_) => _triggerScrape(),
                  decoration: InputDecoration(
                    hintText: 'https://... veya konu (örn: İstanbul manzarası, klasik müzik, uzay)...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(Icons.link_rounded, color: p.primary),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Panodan Yapıştır',
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                          onPressed: () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            if (data?.text != null &&
                                data!.text!.trim().isNotEmpty) {
                              setState(() {
                                _inputCtrl.text = data.text!.trim();
                              });
                            }
                          },
                        ),
                        if (_inputCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              color: Colors.white54,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _inputCtrl.clear()),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: c.isScraping ? null : () => _triggerScrape(),
                    icon: c.isScraping
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.travel_explore_rounded, size: 22),
                    label: Text(
                      c.isScraping
                          ? 'Taranıyor ve Kazınıyor...'
                          : '🔍 Siteyi Kazı / Medya Dosyalarını Bul',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '2️⃣ Veya Tek Dokunuşla Kategori Seçip Hemen Bulun:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickMediaButton(
                      icon: Icons.image_search_rounded,
                      label: '🖼️ Toplu Resim Bul',
                      color: const Color(0xFF38BDF8),
                      onTap: () => _triggerScrape(
                        mediaFilter: 'image',
                        presetQuery: 'İstanbul Boğazı manzaraları',
                      ),
                    ),
                    _QuickMediaButton(
                      icon: Icons.library_music_rounded,
                      label: '🎵 Ses & Müzik (MP3/OGG) Bul',
                      color: const Color(0xFFA855F7),
                      onTap: () => _triggerScrape(
                        mediaFilter: 'audio',
                        presetQuery: 'Classical piano music',
                      ),
                    ),
                    _QuickMediaButton(
                      icon: Icons.ondemand_video_rounded,
                      label: '🎬 Video (MP4/WebM) Bul',
                      color: const Color(0xFFF43F5E),
                      onTap: () => _triggerScrape(
                        mediaFilter: 'video',
                        presetQuery: 'Space NASA earth',
                      ),
                    ),
                    _QuickMediaButton(
                      icon: Icons.picture_as_pdf_rounded,
                      label: '📄 PDF & Belge Bul',
                      color: const Color(0xFFF59E0B),
                      onTap: () => _triggerScrape(
                        mediaFilter: 'document',
                        presetQuery: 'Artificial intelligence report',
                      ),
                    ),
                    _QuickMediaButton(
                      icon: Icons.record_voice_over_rounded,
                      label: '🔊 Metni Ses Dosyasına (WAV/MP3) Çevir',
                      color: const Color(0xFF10B981),
                      onTap: () =>
                          setState(() => _showTtsCreator = !_showTtsCreator),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. Optional Text-to-Audio File Generator Box
          if (_showTtsCreator) ...[
            const SizedBox(height: 12),
            GlassCard3D(
              borderColor: const Color(0xFF10B981).withValues(alpha: 0.5),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.graphic_eq_rounded, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Metni Ses Dosyasına (MP3 / WAV) Dönüştür & İndir',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ttsTitleCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: const InputDecoration(
                      labelText: 'Ses Dosyası Adı',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ttsTextCtrl,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: const InputDecoration(
                      hintText: 'Ses dosyasına dönüştürüp telefonunuza indirmek istediğiniz metni buraya yazın veya yapıştırın...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () async {
                        final txt = _ttsTextCtrl.text.trim();
                        if (txt.isEmpty) return;
                        final art = await c.createAndDownloadAudioFile(
                          txt,
                          title: _ttsTitleCtrl.text.trim().isEmpty
                              ? 'Asistan_Ses'
                              : _ttsTitleCtrl.text.trim(),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              art != null
                                  ? '✅ Ses dosyası indirildi: ${art.title}'
                                  : '⚠️ Ses dosyası oluşturulamadı.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text(
                        '🎵 Ses Dosyası Olarak Oluştur & İndir',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 4. Scrape / Search Results & Bulk Download Controls
          if (res != null) ...[
            const SizedBox(height: 14),
            GlassCard3D(
              borderColor: p.primary.withValues(alpha: 0.45),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    res.pageTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Category Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChipTab(
                          label: 'Tümü (${res.items.length})',
                          active: _activeTab == 'all',
                          accent: p.primary,
                          onTap: () => setState(() => _activeTab = 'all'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChipTab(
                          label:
                              '🖼️ Resimler (${res.countByType(ScrapedMediaType.image)})',
                          active: _activeTab == 'image',
                          accent: const Color(0xFF38BDF8),
                          onTap: () => setState(() => _activeTab = 'image'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChipTab(
                          label:
                              '🎵 Sesler (${res.countByType(ScrapedMediaType.audio)})',
                          active: _activeTab == 'audio',
                          accent: const Color(0xFFA855F7),
                          onTap: () => setState(() => _activeTab = 'audio'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChipTab(
                          label:
                              '🎬 Videolar (${res.countByType(ScrapedMediaType.video)})',
                          active: _activeTab == 'video',
                          accent: const Color(0xFFF43F5E),
                          onTap: () => setState(() => _activeTab = 'video'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChipTab(
                          label:
                              '📄 Belgeler (${res.countByType(ScrapedMediaType.document)})',
                          active: _activeTab == 'document',
                          accent: const Color(0xFFF59E0B),
                          onTap: () => setState(() => _activeTab = 'document'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChipTab(
                          label: '📝 Kazınan Metin & Ofis Çıktısı',
                          active: _activeTab == 'text',
                          accent: const Color(0xFF10B981),
                          onTap: () => setState(() => _activeTab = 'text'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_activeTab == 'text') ...[
                    const Text(
                      'Kazınan / Araştırılan Metni Tek Tuşla Ofis veya Ses Dosyası Olarak İndirin:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final fmt in [
                          ('pdf', '📕 PDF İndir', const Color(0xFFEF4444)),
                          ('docx', '📘 Word İndir', const Color(0xFF3B82F6)),
                          ('xlsx', '📊 Excel İndir', const Color(0xFF10B981)),
                          ('pptx', '📽️ Sunum İndir', const Color(0xFFF59E0B)),
                          ('csv', '📋 CSV İndir', const Color(0xFF06B6D4)),
                        ])
                          ActionChip(
                            backgroundColor: fmt.$3.withValues(alpha: 0.18),
                            side: BorderSide(
                              color: fmt.$3.withValues(alpha: 0.55),
                            ),
                            label: Text(
                              fmt.$2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: () async {
                              final art = await c.exportCanvasAsDocument(
                                title: res.pageTitle,
                                content: res.cleanText,
                                format: fmt.$1,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '✅ ${art.title} (${art.format.toUpperCase()}) İndirilenler/Asistan klasörüne kaydedildi!',
                                  ),
                                ),
                              );
                            },
                          ),
                        ActionChip(
                          backgroundColor: const Color(0xFFA855F7)
                              .withValues(alpha: 0.2),
                          side: const BorderSide(color: Color(0xFFA855F7)),
                          label: const Text(
                            '🎵 Ses (WAV/MP3) İndir',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () async {
                            await c.createAndDownloadAudioFile(
                              res.cleanText,
                              title: res.pageTitle,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 340),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black38,
                        border: Border.all(color: Colors.white12),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          res.cleanText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Bulk Selection & Bulk Download Action Bar
                    Row(
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          onPressed: () {
                            final allSelected =
                                filteredItems.isNotEmpty &&
                                filteredItems.every((e) => e.selected);
                            c.toggleSelectAllScrapedItems(
                              !allSelected,
                              filterType: filterType,
                            );
                          },
                          icon: Icon(
                            filteredItems.isNotEmpty &&
                                    filteredItems.every((e) => e.selected)
                                ? Icons.deselect_rounded
                                : Icons.select_all_rounded,
                            size: 18,
                          ),
                          label: Text(
                            filteredItems.isNotEmpty &&
                                    filteredItems.every((e) => e.selected)
                                ? 'Seçimi Kaldır'
                                : 'Tümünü Seç',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed:
                                (c.isBulkDownloading || selectedCount == 0)
                                ? null
                                : () async {
                                    final count = await c
                                        .bulkDownloadSelectedItems(
                                          filterType: filterType,
                                        );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '🎉 $count dosya "İndirilenler / Asistan" klasörüne toplu indirildi!',
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(
                              Icons.downloading_rounded,
                              size: 20,
                            ),
                            label: Text(
                              c.isBulkDownloading
                                  ? 'İndiriliyor (${c.bulkCompletedCount}/${c.bulkTotalCount})...'
                                  : '📥 Seçilenleri Toplu İndir ($selectedCount Dosya)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (filteredItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'Bu kategoride dosya bulunamadı. Diğer sekmeleri kontrol edin veya yeni bir arama yapın.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return _ScrapedMediaTile(item: item, controller: c);
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickMediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickMediaButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChipTab extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _FilterChipTab({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active
              ? accent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: active ? accent : Colors.white12,
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ScrapedMediaTile extends StatelessWidget {
  final ScrapedMediaItem item;
  final AsistanController controller;

  const _ScrapedMediaTile({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final badgeColor = switch (item.type) {
      ScrapedMediaType.image => const Color(0xFF38BDF8),
      ScrapedMediaType.audio => const Color(0xFFA855F7),
      ScrapedMediaType.video => const Color(0xFFF43F5E),
      ScrapedMediaType.document => const Color(0xFFF59E0B),
      ScrapedMediaType.other => const Color(0xFF10B981),
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: item.downloaded
              ? const Color(0xFF10B981).withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: item.selected,
            activeColor: const Color(0xFF10B981),
            onChanged: (v) =>
                controller.toggleScrapedItemSelection(item, v ?? false),
          ),
          // Thumbnail or Media Icon
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 54,
              height: 54,
              child: item.thumbnailUrl != null
                  ? Image.network(
                      item.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _fallbackBox(badgeColor),
                    )
                  : _fallbackBox(badgeColor),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: badgeColor.withValues(alpha: 0.2),
                      ),
                      child: Text(
                        '${item.typeBadge} • .${item.extension.toUpperCase()}',
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (item.sizeBytes != null && item.sizeBytes! > 0)
                      Text(
                        '${(item.sizeBytes! / 1024).toStringAsFixed(0)} KB',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    Text(
                      item.sourceLabel,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (item.downloaded && item.savedPath != null)
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981)
                    .withValues(alpha: 0.22),
                foregroundColor: const Color(0xFF6EE7B7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onPressed: () {
                controller.invokeNative('openFile', {
                  'path': item.savedPath,
                  'mimeType': item.mimeType,
                });
              },
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text(
                'Aç',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: badgeColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onPressed: () async {
                final art = await controller.downloadSingleScrapedItem(item);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      art != null
                          ? '✅ İndirildi: ${art.title} (İndirilenler/${item.subFolder})'
                          : '⚠️ Dosya indirilemedi.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text(
                'İndir',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackBox(Color color) {
    final icon = switch (item.type) {
      ScrapedMediaType.image => Icons.image_rounded,
      ScrapedMediaType.audio => Icons.audiotrack_rounded,
      ScrapedMediaType.video => Icons.movie_creation_rounded,
      ScrapedMediaType.document => Icons.description_rounded,
      ScrapedMediaType.other => Icons.insert_drive_file_rounded,
    };
    return Container(
      color: color.withValues(alpha: 0.16),
      child: Icon(icon, color: color, size: 26),
    );
  }
}
