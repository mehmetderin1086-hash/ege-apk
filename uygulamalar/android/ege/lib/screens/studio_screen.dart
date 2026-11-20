import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/jarvis_models.dart';
import '../services/device_bridge.dart';
import '../state/jarvis_controller.dart';
import '../widgets/markdown_message.dart';
import 'works_screen.dart';
import '../widgets/chat_palette.dart';

class StudioScreen extends StatefulWidget {
  final JarvisController controller;

  const StudioScreen({super.key, required this.controller});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  late final TextEditingController _memoryCtrl;
  final TextEditingController _imagePromptCtrl = TextEditingController();
  final TextEditingController _researchCtrl = TextEditingController();
  bool _generating = false;
  bool _generatingImage = false;
  String _selectedImageModel = 'gpt-image-2.5-flare';
  String _selectedImageSize = '1024x1024';
  Uint8List? _generatedImageBytes;
  String? _generatedImagePath;
  String? _generatedImageCaption;
  String _generatedImageExt = 'png';

  @override
  void initState() {
    super.initState();
    _memoryCtrl = TextEditingController(
      text: widget.controller.settings.memoryText,
    );
  }

  @override
  void didUpdateWidget(covariant StudioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mem = widget.controller.settings.memoryText;
    if (_memoryCtrl.text != mem && !FocusScope.of(context).hasFocus) {
      _memoryCtrl.text = mem;
    }
  }

  @override
  void dispose() {
    _memoryCtrl.dispose();
    _imagePromptCtrl.dispose();
    _researchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runWebDeepResearch() async {
    final q = _researchCtrl.text.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce araştırılacak konu veya soruyu yazın.')),
      );
      return;
    }
    final report = await widget.controller.runDeepResearch(q);
    if (!mounted) return;
    if (report == null || !report.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(report?.error ?? 'Derin araştırma tamamlanamadı.'),
        ),
      );
      return;
    }
    if (widget.controller.studies.isNotEmpty) {
      await _showArtifactSheet(widget.controller.studies.first);
    }
  }

  Future<void> _generateStudioImage() async {
    final prompt = _imagePromptCtrl.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce bir görsel tarifi (prompt) yazın.')),
      );
      return;
    }

    setState(() => _generatingImage = true);
    final res = await widget.controller.generateStudioImage(
      modelId: _selectedImageModel,
      prompt: prompt,
      size: _selectedImageSize,
    );

    if (!mounted) return;
    if (!res.ok || res.bytes == null) {
      setState(() => _generatingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Görsel üretilemedi.')),
      );
      return;
    }

    final ext = res.mimeType.toLowerCase().contains('jpeg') ? 'jpg' : 'png';
    final savedPath = await DeviceBridge.saveGeneratedImage(
      res.bytes!,
      'jarvis_studio_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );

    if (!mounted) return;
    setState(() {
      _generatingImage = false;
      _generatedImageBytes = res.bytes;
      _generatedImagePath = savedPath;
      _generatedImageCaption = res.caption;
      _generatedImageExt = ext;
    });
  }

  Future<void> _shareGeneratedImage() async {
    final bytes = _generatedImageBytes;
    if (bytes == null) return;
    var path = _generatedImagePath;
    if (path == null || !File(path).existsSync()) {
      final tmp = File(
        '${Directory.systemTemp.path}/jarvis_studio_share.$_generatedImageExt',
      );
      await tmp.writeAsBytes(bytes);
      path = tmp.path;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: _imagePromptCtrl.text.trim(),
      ),
    );
  }

  Future<void> _openTaskPrompt({
    required String kind,
    required String cardTitle,
    required String hint,
    required String Function(String input) promptBuilder,
  }) async {
    final inputCtrl = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChatPalette.surface,
        title: Text(cardTitle),
        content: TextField(
          controller: inputCtrl,
          minLines: 3,
          maxLines: 7,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, inputCtrl.text.trim()),
            icon: const Icon(Icons.auto_awesome_rounded, size: 17),
            label: const Text('Oluştur'),
          ),
        ],
      ),
    );
    inputCtrl.dispose();

    if (!mounted || submitted == null || submitted.isEmpty) return;

    setState(() => _generating = true);
    final shortTitle = submitted.length > 36
        ? '${submitted.substring(0, 36)}...'
        : submitted;

    late final ({bool ok, StudyArtifact? artifact, String? error}) res;
    try {
      res = await widget.controller.runStudioTask(
        kind: kind,
        title: '$cardTitle: $shortTitle',
        prompt: promptBuilder(submitted),
      );
    } catch (e) {
      res = (ok: false, artifact: null, error: 'Bağlantı hatası: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }

    if (!mounted) return;

    if (!res.ok || res.artifact == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Stüdyo görevi tamamlanamadı.')),
      );
      return;
    }

    await _showArtifactSheet(res.artifact!);
  }

  Future<void> _showArtifactSheet(StudyArtifact artifact) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChatPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.94,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      artifact.title,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: ChatPalette.accent,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kopyala',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: artifact.content),
                      );
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('İçerik kopyalandı')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Paylaş',
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text: '# ${artifact.title}\n\n${artifact.content}',
                        title: artifact.title,
                      ),
                    ),
                    icon: const Icon(Icons.share_outlined, size: 19),
                  ),
                ],
              ),
              Divider(color: ChatPalette.border),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  child: MarkdownMessage(text: artifact.content),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final safe = artifact.title
                            .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '')
                            .trim()
                            .replaceAll(RegExp(r'\s+'), '_');
                        final fileName =
                            '${safe.isEmpty ? "jarvis_rapor" : safe}.md';
                        final uri = await widget.controller.saveTextToDownloads(
                          fileName,
                          '# ${artifact.title}\n\n${artifact.content}',
                        );
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              uri != null
                                  ? 'İndirilenler/Ege klasörüne kaydedildi: $fileName'
                                  : 'Dosya kaydedilemedi',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text('İndir (.md)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.controller.transferStudyToChat(artifact);
                      },
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('Sohbete Aktar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    final templates = [
      (
        kind: 'research',
        title: 'Derin Araştırma',
        subtitle: 'Konuyu başlıklar ve özetlerle analiz et',
        icon: Icons.travel_explore_rounded,
        color: ChatPalette.accent,
        hint: 'Araştırılacak konu veya soruyu yaz...',
        builder: (String q) =>
            'Aşağıdaki konuyu Türkçe olarak kapsamlı, düzenli başlıklar, temel kavramlar, avantajlar/riskler ve pratik sonuçlarla açıkla:\n\n$q',
      ),
      (
        kind: 'summary',
        title: 'Metin / Ders Özeti',
        subtitle: 'Uzun metni maddeler ve aksiyonlara dönüştür',
        icon: Icons.summarize_outlined,
        color: const Color(0xFF34D399),
        hint: 'Özetlenecek metni veya toplantı notunu yapıştır...',
        builder: (String q) =>
            'Aşağıdaki metni Türkçe olarak ana fikir, önemli noktalar ve varsa yapılacaklar listesi halinde özetle:\n\n$q',
      ),
      (
        kind: 'code',
        title: 'Kod Üret & İncele',
        subtitle: 'İstenen dilde temiz örnek kod ve açıklama',
        icon: Icons.code_rounded,
        color: const Color(0xFFA78BFA),
        hint: 'Ne tür bir kod veya hata çözümü istiyorsun?',
        builder: (String q) =>
            'Aşağıdaki yazılım isteği için temiz, çalışan örnek kod ve kısa Türkçe açıklama yaz:\n\n$q',
      ),
      (
        kind: 'translate',
        title: 'Doğal Çeviri',
        subtitle: 'Türkçe ↔ İngilizce veya belirtilen dile çeviri',
        icon: Icons.translate_rounded,
        color: ChatPalette.accent,
        hint: 'Hedef dil (isteğe bağlı) ve metni yaz...',
        builder: (String q) =>
            'Aşağıdaki metni akıcı ve doğal bir dille çevir (hedef dil belirtilmemişse Türkçe↔İngilizce çevir) ve gerekiyorsa kısa terminoloji notu ekle:\n\n$q',
      ),
      (
        kind: 'compare',
        title: 'Karşılaştırma Tablosu',
        subtitle: 'Seçenekleri Markdown tablo ile kıyasla',
        icon: Icons.table_chart_outlined,
        color: const Color(0xFFFBBF24),
        hint: 'Örn: Flutter vs React Native veya iki telefon modeli...',
        builder: (String q) =>
            'Aşağıdaki seçenekleri Markdown tablo + artı/eksi analiz + kime hangisi uygun özetiyle Türkçe karşılaştır:\n\n$q',
      ),
    ];

    final availableImageModels = <String>{
      ...c.imageModels.map((m) => m.id),
      'gemini-nano-banana-2.1',
      'gpt-image-2.6',
      'gpt-image-2.5-flare',
      'gpt-image-2.5-sunburst',
      'antigravity-gemini-image',
      'gemini-3-pro-image',
      'gemini-3.1-flash-lite-image',
      'gemini-3.1-flash-image',
    }.toList();
    if (!availableImageModels.contains(_selectedImageModel) &&
        availableImageModels.isNotEmpty) {
      _selectedImageModel = availableImageModels.first;
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        StudioHubCard(controller: c),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ChatPalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: ChatPalette.accent.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.brush_rounded, color: ChatPalette.accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Görsel Üret (Proxy Modelleri)',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: ChatPalette.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'gpt-image-2.5, antigravity-gemini-image ve Gemini Image modelleriyle doğrudan telefonda görsel üret.',
                style: TextStyle(color: ChatPalette.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedImageModel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Görsel Modeli',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final m in availableImageModels)
                          DropdownMenuItem(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _generatingImage
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _selectedImageModel = v);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedImageSize,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Boyut',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '1024x1024',
                          child: Text('1024×1024'),
                        ),
                        DropdownMenuItem(
                          value: '1536x1024',
                          child: Text('1536×1024'),
                        ),
                        DropdownMenuItem(
                          value: '1024x1536',
                          child: Text('1024×1536'),
                        ),
                      ],
                      onChanged: _generatingImage
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _selectedImageSize = v);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _imagePromptCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Örn: Boğaz köprüsü üzerinde fütüristik neon gün batımı',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generatingImage ? null : _generateStudioImage,
                  icon: _generatingImage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    _generatingImage ? 'Görsel Üretiliyor...' : 'Görsel Oluştur',
                  ),
                ),
              ),
              if (_generatedImageBytes != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _generatedImageBytes!,
                    width: double.infinity,
                    height: 240,
                    fit: BoxFit.contain,
                  ),
                ),
                if (_generatedImageCaption != null &&
                    _generatedImageCaption!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _generatedImageCaption!,
                    style: TextStyle(
                      color: ChatPalette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _shareGeneratedImage,
                        icon: const Icon(Icons.share_rounded, size: 17),
                        label: const Text('Paylaş'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final saved = await DeviceBridge.saveGeneratedImage(
                            _generatedImageBytes!,
                            'jarvis_studio_${DateTime.now().millisecondsSinceEpoch}.$_generatedImageExt',
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                saved != null
                                    ? 'Kaydedildi: $saved'
                                    : 'Cihaz deposuna kaydedilemedi.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.save_alt_rounded, size: 17),
                        label: const Text('Cihaza Kaydet'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_generating)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ChatPalette.soft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ChatPalette.accent),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Stüdyo içeriği üretiliyor...'),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ChatPalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF34D399).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.travel_explore_rounded, color: Color(0xFF34D399)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Derin Araştırma (Web + Çoklu Kaynak)',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6EE7B7),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Alt sorgular planlar, DuckDuckGo & Wikipedia üzerinden canlı sayfaları okur ve kaynakçalı kapsamlı rapor üretir.',
                style: TextStyle(color: ChatPalette.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _researchCtrl,
                enabled: !c.researchRunning,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      'Örn: Kuantum bilgisayarların mevcut şifreleme standartlarına etkisi',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _runWebDeepResearch(),
              ),
              const SizedBox(height: 10),
              if (c.researchRunning) ...[
                Text(
                  'Konu: ${c.researchQuestion}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: c.researchProgress?.fraction,
                  backgroundColor: const Color(0xFF1E293B),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${c.researchProgress?.message ?? "Araştırılıyor..."} '
                        '(${c.researchProgress?.sourcesRead ?? 0}/${c.researchProgress?.sourcesFound ?? 0} kaynak)',
                        style: TextStyle(
                          fontSize: 12,
                          color: ChatPalette.muted,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: c.cancelResearch,
                      icon: const Icon(Icons.stop_circle_outlined, size: 17),
                      label: const Text('İptal Et'),
                    ),
                  ],
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _runWebDeepResearch,
                    icon: const Icon(Icons.manage_search_rounded, size: 18),
                    label: const Text('Derin Araştırmayı Başlat'),
                  ),
                ),
            ],
          ),
        ),
        Text(
          'Hızlı Üretim Araçları',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ChatPalette.accent,
          ),
        ),
        const SizedBox(height: 10),
        for (final t in templates)
          Card(
            color: ChatPalette.surface,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: ChatPalette.border),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: t.color.withValues(alpha: 0.14),
                child: Icon(t.icon, color: t.color),
              ),
              title: Text(
                t.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                t.subtitle,
                style: TextStyle(color: ChatPalette.muted, fontSize: 12.5),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _generating
                  ? null
                  : () => _openTaskPrompt(
                        kind: t.kind,
                        cardTitle: t.title,
                        hint: t.hint,
                        promptBuilder: t.builder,
                      ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Ege Kalıcı Hafızası',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ChatPalette.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Buraya yazdığınız bilgiler ve tercihler tüm AI konuşmalarına otomatik eklenir.',
          style: TextStyle(color: ChatPalette.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _memoryCtrl,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText:
                'Örn: Adım Mehmet. Yanıtları kısa ve net ver. Flutter ve Python üzerinde çalışıyorum.',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: ChatPalette.surface,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () async {
              await c.updateSettings(
                c.settings.copyWith(memoryText: _memoryCtrl.text.trim()),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ege hafızası kaydedildi')),
                );
              }
            },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Hafızayı Kaydet'),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Kaydedilen Stüdyo Çıktıları (${c.studies.length})',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ChatPalette.accent,
          ),
        ),
        const SizedBox(height: 8),
        if (c.studies.isEmpty)
          Text(
            'Henüz kayıtlı çıktı yok.',
            style: TextStyle(color: ChatPalette.muted),
          )
        else
          for (final item in c.studies)
            Card(
              color: ChatPalette.surface,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: ChatPalette.border),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: ChatPalette.soft,
                  child: Icon(
                    item.kind == 'research'
                        ? Icons.travel_explore_rounded
                        : item.kind == 'code'
                            ? Icons.code_rounded
                            : item.kind == 'translate'
                                ? Icons.translate_rounded
                                : item.kind == 'compare'
                                    ? Icons.table_chart_outlined
                                    : Icons.summarize_outlined,
                    size: 18,
                    color: ChatPalette.accent,
                  ),
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  item.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ChatPalette.muted, fontSize: 12.5),
                ),
                onTap: () => _showArtifactSheet(item),
                trailing: IconButton(
                  tooltip: 'Sil',
                  onPressed: () => c.deleteStudy(item.id),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFFB7185),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
