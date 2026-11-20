import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme_settings.dart';
import 'book_visuals.dart';

Future<void> openLibraryAtmosphereStudio(
  BuildContext context, {
  required int totalBooks,
  required Future<void> Function() onResyncIPhoneSeed,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => LibraryAtmosphereStudioPage(
        totalBooks: totalBooks,
        onResyncIPhoneSeed: onResyncIPhoneSeed,
      ),
    ),
  );
}

Future<void> openReadingSanctuaryPage(
  BuildContext context, {
  required List<Map<String, dynamic>> books,
  ValueChanged<Map<String, dynamic>>? onOpenBook,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ReadingSanctuaryPage(
        books: books,
        onOpenBook: onOpenBook,
      ),
    ),
  );
}

Future<void> _persistAppTheme(AppThemeSettings next) async {
  appThemeNotifier.value = next;
  try {
    final docs = await getApplicationDocumentsDirectory();
    await AppThemeStore(docs).save(next);
  } catch (_) {
    // Test ortamında path_provider yoksa bellek içi tema güncellemesi yeterlidir.
  }
}

class LibraryAtmosphereStudioPage extends StatefulWidget {
  const LibraryAtmosphereStudioPage({
    super.key,
    required this.totalBooks,
    required this.onResyncIPhoneSeed,
  });

  final int totalBooks;
  final Future<void> Function() onResyncIPhoneSeed;

  @override
  State<LibraryAtmosphereStudioPage> createState() =>
      _LibraryAtmosphereStudioPageState();
}

class _LibraryAtmosphereStudioPageState
    extends State<LibraryAtmosphereStudioPage> {
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0);

  late final TextEditingController _schoolCtrl;
  late final TextEditingController _libraryCtrl;
  late final TextEditingController _librarianCtrl;
  late final TextEditingController _principalCtrl;
  late final TextEditingController _prefixCtrl;
  late final TextEditingController _digitsCtrl;

  bool _syncing = false;
  bool _savingIdentity = false;

  @override
  void initState() {
    super.initState();
    final cfg = appThemeNotifier.value;
    _schoolCtrl = TextEditingController(text: cfg.schoolName);
    _libraryCtrl = TextEditingController(text: cfg.libraryName);
    _librarianCtrl = TextEditingController(text: cfg.librarianName);
    _principalCtrl = TextEditingController(text: cfg.principalName);
    _prefixCtrl = TextEditingController(text: cfg.accessionPrefix);
    _digitsCtrl = TextEditingController(text: cfg.accessionDigits.toString());
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    _schoolCtrl.dispose();
    _libraryCtrl.dispose();
    _librarianCtrl.dispose();
    _principalCtrl.dispose();
    _prefixCtrl.dispose();
    _digitsCtrl.dispose();
    super.dispose();
  }

  Future<void> _applySettings(AppThemeSettings next) => _persistAppTheme(next);

  Future<void> _saveSchoolIdentity() async {
    setState(() => _savingIdentity = true);
    try {
      final cfg = appThemeNotifier.value;
      final parsedDigits =
          int.tryParse(_digitsCtrl.text.trim())?.clamp(3, 8) ??
          cfg.accessionDigits;
      final updated = cfg.copyWith(
        schoolName: _schoolCtrl.text.trim().isEmpty
            ? cfg.schoolName
            : _schoolCtrl.text.trim(),
        libraryName: _libraryCtrl.text.trim().isEmpty
            ? cfg.libraryName
            : _libraryCtrl.text.trim(),
        librarianName: _librarianCtrl.text.trim(),
        principalName: _principalCtrl.text.trim(),
        accessionPrefix: _prefixCtrl.text.trim().isEmpty
            ? cfg.accessionPrefix
            : _prefixCtrl.text.trim(),
        accessionDigits: parsedDigits,
      );
      await _applySettings(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Okul ve kütüphane kimliği kaydedildi.')),
      );
    } finally {
      if (mounted) setState(() => _savingIdentity = false);
    }
  }

  Future<void> _runResync() async {
    setState(() => _syncing = true);
    try {
      await widget.onResyncIPhoneSeed();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<AppThemeSettings>(
      valueListenable: appThemeNotifier,
      builder: (context, cfg, _) {
        return AmbientLibraryBackground(
          wallpaperAsset: cfg.wallpaperAsset,
          particlesEnabled: cfg.particlesEnabled,
          clarity: cfg.clarity,
          effectIntensity: cfg.effectIntensity,
          tapRipplesEnabled: cfg.tapRipplesEnabled,
          scrollOffsetListenable: _scrollOffset,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: scheme.surface.withValues(alpha: 0.72),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              titleSpacing: 4,
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Atmosfer Stüdyosu',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
                  ),
                  Text(
                    'Canlı sahneler, efektler & cam kartlar',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Zamanına Göre Akış Paketine Dön',
                  onPressed: () =>
                      _applySettings(cfg.applyPack(AtmospherePack.autoTime)),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                ),
              ],
            ),
            body: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical) {
                  _scrollOffset.value = n.metrics.pixels;
                }
                return false;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  _StudioLivePreviewCard(cfg: cfg, totalBooks: widget.totalBooks),
                  const SizedBox(height: 16),
                  const _SectionTitle(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Tek Dokunuş Atmosfer Paketleri',
                    subtitle:
                        'Arka plan, renk teması ve ışık efektini birlikte uyarlar',
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: AtmospherePack.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final pack = AtmospherePack.values[index];
                        final selected = cfg.atmospherePackId == pack.id;
                        return _AtmospherePackTile(
                          pack: pack,
                          selected: selected,
                          onTap: () => _applySettings(cfg.applyPack(pack)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.wallpaper_rounded,
                    title: 'Arka Plan Galerisi',
                    subtitle: 'Saate göre dinamik akış veya özel kütüphane sahnesi',
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 174,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: availableWallpapers.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final wp = availableWallpapers[index];
                        final configKey = wp.$1;
                        final label = wp.$2;
                        final isDynamic = configKey == kDynamicTimeWallpaper;
                        final isPlain = configKey.isEmpty;
                        final previewAsset = isDynamic
                            ? resolveWallpaperAsset(kDynamicTimeWallpaper)
                            : configKey;
                        final subtitle = isDynamic
                            ? 'Otomatik sahne'
                            : isPlain
                            ? 'Sade zemin'
                            : 'Özel sahne';
                        return _WallpaperGalleryTile(
                          title: label,
                          subtitle: subtitle,
                          assetPath: previewAsset,
                          selected: cfg.wallpaperAsset == configKey,
                          badge: isDynamic ? 'CANLI' : null,
                          plainSwatchColor: isPlain ? cfg.preset.seed : null,
                          onTap: () => _applySettings(
                            cfg.copyWith(wallpaperAsset: configKey),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.blur_on_rounded,
                    title: 'Efekt Yoğunluğu & Arka Plan Netliği',
                    subtitle: 'Yıldız parıltıları, ışık hüzmeleri ve perde ayarı',
                  ),
                  const SizedBox(height: 10),
                  FrostedGlassSurface(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(14),
                    useBlur: cfg.glassCardsEnabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Atmosfer Efektleri',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: EffectIntensity.values.map((ei) {
                            final selected = cfg.effectIntensity == ei;
                            return ChoiceChip(
                              selected: selected,
                              avatar: Icon(_effectIcon(ei), size: 16),
                              label: Text(ei.label),
                              tooltip: ei.hint,
                              onSelected: (_) => _applySettings(
                                cfg.copyWith(
                                  effectIntensity: ei,
                                  particlesEnabled: ei != EffectIntensity.off,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Arka Plan Netliği (Perde)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: WallpaperClarity.values.map((cl) {
                            final selected = cfg.clarity == cl;
                            return ChoiceChip(
                              selected: selected,
                              avatar: Icon(_clarityIcon(cl), size: 16),
                              label: Text(cl.label),
                              tooltip: cl.hint,
                              onSelected: (_) =>
                                  _applySettings(cfg.copyWith(clarity: cl)),
                            );
                          }).toList(),
                        ),
                        const Divider(height: 22),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.auto_awesome_rounded),
                          title: const Text(
                            'Yıldız Parıltısı & Işık Hüzmeleri',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: const Text(
                            'Kayan ışık noktaları, bokeh ve kubbe hüzmeleri',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: cfg.particlesEnabled,
                          onChanged: (v) => _applySettings(
                            cfg.copyWith(
                              particlesEnabled: v,
                              effectIntensity: v &&
                                      cfg.effectIntensity == EffectIntensity.off
                                  ? EffectIntensity.rich
                                  : cfg.effectIntensity,
                            ),
                          ),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.touch_app_rounded),
                          title: const Text(
                            'Dokunma Işık Dalgaları',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: const Text(
                            'Ekrana dokununca yayılan altın ışık dalgaları',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: cfg.tapRipplesEnabled,
                          onChanged: (v) => _applySettings(
                            cfg.copyWith(tapRipplesEnabled: v),
                          ),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.layers_rounded),
                          title: const Text(
                            'Cam & Şeffaf Kart Yüzeyleri',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: const Text(
                            'Kitap kartlarının arkasından canlı sahneyi göster',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: cfg.glassCardsEnabled,
                          onChanged: (v) => _applySettings(
                            cfg.copyWith(glassCardsEnabled: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.palette_rounded,
                    title: 'Renk Paleti & Görünüm Modu',
                    subtitle: 'Aydınlık/karanlık denge ve vurgu rengi',
                  ),
                  const SizedBox(height: 10),
                  FrostedGlassSurface(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(14),
                    useBlur: cfg.glassCardsEnabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.brightness_auto_rounded, size: 17),
                                label: Text('Sistem'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode_rounded, size: 17),
                                label: Text('Aydınlık'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode_rounded, size: 17),
                                label: Text('Karanlık'),
                              ),
                            ],
                            selected: {cfg.themeMode},
                            onSelectionChanged: (sel) => _applySettings(
                              cfg.copyWith(themeMode: sel.first),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: LibraryThemePreset.values.map((preset) {
                            final selected = cfg.preset == preset;
                            return ChoiceChip(
                              selected: selected,
                              avatar: CircleAvatar(
                                backgroundColor: preset.seed,
                                radius: 9,
                                child: selected
                                    ? const Icon(
                                        Icons.check,
                                        size: 11,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              label: Text(preset.label),
                              onSelected: (_) => _applySettings(
                                cfg.copyWith(preset: preset),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.account_balance_rounded,
                    title: 'Okul Kimliği & Katalog Eşitleme',
                    subtitle: 'Resmi rapor başlıkları ve demirbaş şablonu',
                  ),
                  const SizedBox(height: 10),
                  FrostedGlassSurface(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(14),
                    useBlur: cfg.glassCardsEnabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _schoolCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Okul / Kurum Adı',
                            prefixIcon: Icon(Icons.school_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _libraryCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Kütüphane Başlığı',
                            prefixIcon: Icon(Icons.local_library_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _librarianCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Sorumlu Öğretmen',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _principalCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Okul Müdürü',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _prefixCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Demirbaş Ön Eki',
                                  prefixIcon: Icon(Icons.tag_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _digitsCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Basamak',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                _savingIdentity ? null : _saveSchoolIdentity,
                            icon: _savingIdentity
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: const Text('Kimliği Kaydet'),
                          ),
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Aktif Katalog: ${widget.totalBooks} Kitap',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Paket içi iPhone envanteriyle tek tıkla eşitle',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _syncing ? null : _runResync,
                              icon: _syncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.sync_rounded),
                              label: const Text('2.892 Eşitle'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StudioLivePreviewCard extends StatelessWidget {
  const _StudioLivePreviewCard({
    required this.cfg,
    required this.totalBooks,
  });

  final AppThemeSettings cfg;
  final int totalBooks;

  @override
  Widget build(BuildContext context) {
    final activeAsset = cfg.effectiveWallpaperAsset;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 192,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AmbientLibraryBackground(
              wallpaperAsset: activeAsset,
              particlesEnabled: cfg.particlesEnabled,
              clarity: cfg.clarity,
              effectIntensity: cfg.effectIntensity,
              tapRipplesEnabled: cfg.tapRipplesEnabled,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFFFBBF24)
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 13,
                                color: Color(0xFFFDE68A),
                              ),
                              SizedBox(width: 5),
                              Text(
                                'CANLI SAHNE ÖNİZLEMESİ',
                                style: TextStyle(
                                  color: Color(0xFFFEF3C7),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        LibraryPulseDial(
                          ratio: 0.88,
                          centerValue: '$totalBooks',
                          centerCaption: 'kitap',
                          size: 72,
                          accent: const Color(0xFFFBBF24),
                        ),
                      ],
                    ),
                    const Spacer(),
                    FrostedGlassSurface(
                      borderRadius: 16,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      tintColor: Colors.black,
                      opacity: 0.45,
                      borderColor: Colors.white.withValues(alpha: 0.28),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [cfg.preset.seed, cfg.preset.secondary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.menu_book_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cfg.libraryName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${cfg.clarity.label} • ${cfg.effectIntensity.label}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.touch_app_rounded,
                            color: Color(0xFFFDE68A),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AtmospherePackTile extends StatelessWidget {
  const _AtmospherePackTile({
    required this.pack,
    required this.selected,
    required this.onTap,
  });

  final AtmospherePack pack;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final asset = pack.wallpaper == kDynamicTimeWallpaper
        ? resolveWallpaperAsset(kDynamicTimeWallpaper)
        : pack.wallpaper;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 164,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFBBF24)
                  : Colors.white.withValues(alpha: 0.25),
              width: selected ? 2.2 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: pack.preset.seed.withValues(alpha: 0.65),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.16),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [pack.preset.seed, pack.preset.secondary],
                              ),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Icon(
                              _packIcon(pack),
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          if (selected)
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: Color(0xFFFBBF24),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        pack.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        pack.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 10.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WallpaperGalleryTile extends StatelessWidget {
  const _WallpaperGalleryTile({
    required this.title,
    required this.subtitle,
    required this.assetPath,
    required this.selected,
    required this.onTap,
    this.badge,
    this.plainSwatchColor,
  });

  final String title;
  final String subtitle;
  final String assetPath;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  final Color? plainSwatchColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 114,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFBBF24)
                  : Colors.white.withValues(alpha: 0.24),
              width: selected ? 2.4 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.34),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (assetPath.isNotEmpty)
                  Image.asset(
                    assetPath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: plainSwatchColor ?? const Color(0xFF1E1B4B),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          (plainSwatchColor ?? const Color(0xFF334155))
                              .withValues(alpha: 0.7),
                          const Color(0xFF0F172A),
                        ],
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.14),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (selected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFFFBBF24),
                              size: 18,
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: isDark ? 0.62 : 0.74),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReadingSanctuaryPage extends StatefulWidget {
  const ReadingSanctuaryPage({
    super.key,
    required this.books,
    this.onOpenBook,
  });

  final List<Map<String, dynamic>> books;
  final ValueChanged<Map<String, dynamic>>? onOpenBook;

  @override
  State<ReadingSanctuaryPage> createState() => _ReadingSanctuaryPageState();
}

class _ReadingSanctuaryPageState extends State<ReadingSanctuaryPage>
    with SingleTickerProviderStateMixin {
  static const List<({String quote, String author})> _quotes = [
    (
      quote: 'Kitaplar, sessizliğin içindeki en aydınlık dostlardır.',
      author: 'Cemil Meriç',
    ),
    (
      quote: 'Okumak, başka bir zamanın ve başka bir ruhun penceresini açmaktır.',
      author: 'Ahmet Hamdi Tanpınar',
    ),
    (
      quote: 'İyi bir kitap, kalbin karanlık köşelerine doğan bir sabah güneşidir.',
      author: 'Sabahattin Ali',
    ),
    (
      quote: 'Her yeni sayfa, insanın kendi içinde çıktığı yeni bir yolculuktur.',
      author: 'Peyami Safa',
    ),
    (
      quote:
          'Hayatta en hakiki mürşit ilimdir; kitap ise onun ölümsüz taşıyıcısıdır.',
      author: 'Gazi Mustafa Kemal Atatürk',
    ),
    (
      quote: 'Dünyayı anlamak için bir cümle, kendini bulmak için bir kütüphane yeter.',
      author: 'Oğuz Atay',
    ),
  ];

  static const List<({String label, String asset})> _sanctuaryScenes = [
    (label: 'Gece Lambası', asset: 'assets/images/bg_gece_calisma.webp'),
    (label: 'Yıldızlı Kubbe', asset: 'assets/images/bg_yildizli_kutuphane.webp'),
    (label: 'Osmanlı Salonu', asset: 'assets/images/bg_osmanli_kutuphane.webp'),
    (label: 'Sonbahar Köşesi', asset: 'assets/images/bg_sonbahar_okuma.webp'),
    (label: 'Sabah Atriumu', asset: 'assets/images/bg_sabah_ferah.webp'),
  ];

  late final AnimationController _orbBreath;
  Timer? _timer;
  int _selectedMinutes = 25;
  int _remainingSeconds = 25 * 60;
  int _elapsedFreeSeconds = 0;
  int _completedMinutesToday = 0;
  bool _running = false;
  bool _keepAwakeHint = true;
  int _quoteIndex = 0;
  int _bookSeed = 0;
  String? _overrideSceneAsset;

  @override
  void initState() {
    super.initState();
    _orbBreath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _quoteIndex = DateTime.now().minute % _quotes.length;
    _bookSeed = DateTime.now().day + DateTime.now().hour;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _orbBreath.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _activeBooks =>
      widget.books.where((b) => b['deletedAt'] == null).toList(growable: false);

  Map<String, dynamic>? get _featuredBook {
    final pool = _activeBooks;
    if (pool.isEmpty) return null;
    final available = pool
        .where((b) => (b['status'] ?? 'available') == 'available')
        .toList(growable: false);
    final list = available.isNotEmpty ? available : pool;
    return list[_bookSeed % list.length];
  }

  void _selectPreset(int minutes) {
    _timer?.cancel();
    setState(() {
      _running = false;
      _selectedMinutes = minutes;
      _remainingSeconds = minutes * 60;
      _elapsedFreeSeconds = 0;
    });
  }

  void _toggleTimer() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_selectedMinutes == 0) {
          _elapsedFreeSeconds += 1;
          if (_elapsedFreeSeconds % 60 == 0) {
            _completedMinutesToday += 1;
          }
        } else if (_remainingSeconds > 0) {
          _remainingSeconds -= 1;
          if (_remainingSeconds == 0) {
            _running = false;
            _completedMinutesToday += _selectedMinutes;
            _timer?.cancel();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Tebrikler! $_selectedMinutes dakikalık okuma seansı tamamlandı.',
                ),
              ),
            );
          }
        }
      });
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _remainingSeconds = _selectedMinutes * 60;
      _elapsedFreeSeconds = 0;
    });
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final book = _featuredBook;
    final quote = _quotes[_quoteIndex % _quotes.length];

    return ValueListenableBuilder<AppThemeSettings>(
      valueListenable: appThemeNotifier,
      builder: (context, cfg, _) {
        final wallpaper = _overrideSceneAsset ??
            (cfg.wallpaperAsset == kDynamicTimeWallpaper ||
                    cfg.wallpaperAsset.isEmpty
                ? 'assets/images/bg_gece_calisma.webp'
                : cfg.wallpaperAsset);

        final totalSecs = _selectedMinutes * 60;
        final double progress = _selectedMinutes == 0
            ? ((_elapsedFreeSeconds % 60) / 60.0)
            : (totalSecs == 0 ? 0.0 : (_remainingSeconds / totalSecs));
        final displayTime = _selectedMinutes == 0
            ? _formatDuration(_elapsedFreeSeconds)
            : _formatDuration(_remainingSeconds);

        return AmbientLibraryBackground(
          wallpaperAsset: wallpaper,
          particlesEnabled: cfg.particlesEnabled,
          clarity: cfg.clarity,
          effectIntensity: cfg.effectIntensity == EffectIntensity.off
              ? EffectIntensity.subtle
              : cfg.effectIntensity,
          tapRipplesEnabled: cfg.tapRipplesEnabled,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: scheme.surface.withValues(alpha: 0.68),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              titleSpacing: 4,
              title: const Row(
                children: [
                  Text('☽ ', style: TextStyle(fontSize: 17)),
                  Expanded(
                    child: Text(
                      'Okuma Köşesi',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: Icon(
                      _keepAwakeHint
                          ? Icons.nightlight_round
                          : Icons.bedtime_outlined,
                      size: 15,
                    ),
                    label: Text(
                      _keepAwakeHint ? 'Odak Modu' : 'Serbest',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onPressed: () {
                      setState(() => _keepAwakeHint = !_keepAwakeHint);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          content: Text(
                            _keepAwakeHint
                                ? 'Dikkat dağıtmayan okuma atmosferi aktif.'
                                : 'Serbest okuma moduna geçildi.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sanctuaryScenes.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final scene = _sanctuaryScenes[index];
                      final active = wallpaper == scene.asset;
                      return ChoiceChip(
                        selected: active,
                        label: Text(
                          scene.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onSelected: (_) => setState(
                          () => _overrideSceneAsset = scene.asset,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: WallpaperClarity.values.map((cl) {
                    return ChoiceChip(
                      selected: cfg.clarity == cl,
                      label: Text(
                        cl.label,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onSelected: (_) => _persistAppTheme(
                        cfg.copyWith(clarity: cl),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                FrostedGlassSurface(
                  borderRadius: 26,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  tintColor: Colors.black,
                  opacity: 0.44,
                  borderColor: const Color(0xFFFDE68A).withValues(alpha: 0.30),
                  useBlur: cfg.glassCardsEnabled,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFFBBF24)
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              _running
                                  ? 'OKUMA AKIŞINDA'
                                  : (_selectedMinutes == 0
                                        ? 'SERBEST KRONOMETRE'
                                        : 'ODAK SAYACI HAZIR'),
                              style: const TextStyle(
                                color: Color(0xFFFDE68A),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Bugün: $_completedMinutesToday dk',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AnimatedBuilder(
                        animation: _orbBreath,
                        builder: (context, _) {
                          return SizedBox(
                            width: 196,
                            height: 196,
                            child: CustomPaint(
                              painter: _FocusOrbPainter(
                                progress: progress.clamp(0.0, 1.0),
                                breath: _orbBreath.value,
                                active: _running,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayTime,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 38,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _selectedMinutes == 0
                                          ? 'Geçen Süre'
                                          : '$_selectedMinutes dk seans',
                                      style: TextStyle(
                                        color: const Color(0xFFFDE68A)
                                            .withValues(alpha: 0.9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [15, 25, 40, 0].map((m) {
                          final active = _selectedMinutes == m;
                          return ChoiceChip(
                            selected: active,
                            label: Text(m == 0 ? 'Serbest' : '$m dk'),
                            onSelected: (_) => _selectPreset(m),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _toggleTimer,
                            style: FilledButton.styleFrom(
                              backgroundColor: _running
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 12,
                              ),
                            ),
                            icon: Icon(
                              _running
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(_running ? 'Duraklat' : 'Başlat'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: _resetTimer,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.42),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Sıfırla'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FrostedGlassSurface(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(16),
                  tintColor: Colors.black,
                  opacity: 0.42,
                  borderColor: Colors.white.withValues(alpha: 0.24),
                  useBlur: cfg.glassCardsEnabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_stories_rounded,
                            color: Color(0xFFFBBF24),
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Günün Kitap Önerisi',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _bookSeed += 1),
                            icon: const Icon(
                              Icons.casino_rounded,
                              size: 16,
                              color: Color(0xFFFDE68A),
                            ),
                            label: const Text(
                              'Başka Öner',
                              style: TextStyle(color: Color(0xFFFDE68A)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (book != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BookCoverWidget(
                              book: book,
                              width: 72,
                              height: 106,
                              heroTag:
                                  'sanctuary-cover-${book['id'] ?? _bookSeed}',
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (book['title'] ?? 'İsimsiz Kitap')
                                        .toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (book['author'] ?? 'Yazar belirtilmemiş')
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      if ((book['category'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
                                        _MiniSanctuaryPill(
                                          text: book['category'].toString(),
                                        ),
                                      if ((book['shelf'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
                                        _MiniSanctuaryPill(
                                          text: 'Raf: ${book['shelf']}',
                                        ),
                                    ],
                                  ),
                                  if (widget.onOpenBook != null) ...[
                                    const SizedBox(height: 10),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        backgroundColor: const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.2),
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        widget.onOpenBook!(book);
                                      },
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                        size: 15,
                                        color: Color(0xFFFDE68A),
                                      ),
                                      label: const Text(
                                        'Kitap Detayını Aç',
                                        style: TextStyle(
                                          color: Color(0xFFFDE68A),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'Katalogda kitap eklendiğinde buradan günlük ilham önerileri seçilecek.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => setState(() => _quoteIndex += 1),
                  child: FrostedGlassSurface(
                    borderRadius: 22,
                    padding: const EdgeInsets.all(16),
                    tintColor: Colors.black,
                    opacity: 0.4,
                    borderColor: Colors.white.withValues(alpha: 0.22),
                    useBlur: cfg.glassCardsEnabled,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: Column(
                        key: ValueKey(_quoteIndex),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.format_quote_rounded,
                                color: Color(0xFF93C5FD),
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Edebiyat & Okuma Sözü',
                                style: TextStyle(
                                  color: Color(0xFFBFDBFE),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Değiştirmek için dokun',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '“${quote.quote}”',
                            style: const TextStyle(
                              color: Colors.white,
                              fontStyle: FontStyle.italic,
                              fontSize: 14.5,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '— ${quote.author}',
                              style: const TextStyle(
                                color: Color(0xFFFDE68A),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniSanctuaryPill extends StatelessWidget {
  const _MiniSanctuaryPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FocusOrbPainter extends CustomPainter {
  const _FocusOrbPainter({
    required this.progress,
    required this.breath,
    required this.active,
  });

  final double progress;
  final double breath;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    final auraPaint = Paint()
      ..color = (active ? const Color(0xFFFBBF24) : const Color(0xFF93C5FD))
          .withValues(alpha: 0.12 + breath * 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, radius + 8 + breath * 6, auraPaint);

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    canvas.drawCircle(center, radius, trackPaint);

    final tickPaint = Paint()..strokeWidth = 1.4;
    for (int i = 0; i < 36; i++) {
      final a = (i / 36) * math.pi * 2 - math.pi / 2;
      final isMajor = i % 3 == 0;
      tickPaint.color = Colors.white.withValues(alpha: isMajor ? 0.36 : 0.16);
      final r1 = radius + (isMajor ? 10 : 8);
      final r2 = radius + (isMajor ? 16 : 12);
      canvas.drawLine(
        Offset(center.dx + math.cos(a) * r1, center.dy + math.sin(a) * r1),
        Offset(center.dx + math.cos(a) * r2, center.dy + math.sin(a) * r2),
        tickPaint,
      );
    }

    if (progress > 0.005) {
      final sweep = math.pi * 2 * progress;
      final arcPaint = Paint()
        ..shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [
            Color(0xFFFDE68A),
            Color(0xFFF59E0B),
            Color(0xFF34D399),
            Color(0xFFFDE68A),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 7.5;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        arcPaint,
      );

      final tipAngle = -math.pi / 2 + sweep;
      final tip = Offset(
        center.dx + math.cos(tipAngle) * radius,
        center.dy + math.sin(tipAngle) * radius,
      );
      canvas.drawCircle(
        tip,
        5.5,
        Paint()..color = const Color(0xFFFEF3C7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FocusOrbPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.breath != breath ||
      oldDelegate.active != active;
}

IconData _packIcon(AtmospherePack pack) {
  return switch (pack) {
    AtmospherePack.autoTime => Icons.schedule_rounded,
    AtmospherePack.starlight => Icons.nights_stay_rounded,
    AtmospherePack.ottoman => Icons.account_balance_rounded,
    AtmospherePack.autumn => Icons.local_cafe_rounded,
    AtmospherePack.morning => Icons.wb_sunny_rounded,
    AtmospherePack.emerald => Icons.park_rounded,
  };
}

IconData _effectIcon(EffectIntensity ei) {
  return switch (ei) {
    EffectIntensity.rich => Icons.auto_awesome_rounded,
    EffectIntensity.subtle => Icons.blur_on_rounded,
    EffectIntensity.off => Icons.block_rounded,
  };
}

IconData _clarityIcon(WallpaperClarity cl) {
  return switch (cl) {
    WallpaperClarity.vivid => Icons.hd_rounded,
    WallpaperClarity.balanced => Icons.tonality_rounded,
    WallpaperClarity.reading => Icons.chrome_reader_mode_rounded,
  };
}
