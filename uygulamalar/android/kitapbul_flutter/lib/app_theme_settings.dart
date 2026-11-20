import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const String kDynamicTimeWallpaper = 'auto_time';

enum LibraryThemePreset {
  indigoRoyal(
    id: 'indigo',
    label: 'Kraliyet İndigo',
    seed: Color(0xFF4F46E5),
    secondary: Color(0xFF7C3AED),
    defaultWallpaper: 'assets/images/bg_yildizli_kutuphane.webp',
  ),
  crimsonRepublic(
    id: 'crimson',
    label: 'Cumhuriyet Bordosu',
    seed: Color(0xFFBE123C),
    secondary: Color(0xFFE11D48),
    defaultWallpaper: 'assets/images/bg_sonbahar_okuma.webp',
  ),
  emeraldAtrium(
    id: 'emerald',
    label: 'Zümrüt Kütüphane',
    seed: Color(0xFF059669),
    secondary: Color(0xFF0D9488),
    defaultWallpaper: 'assets/images/bg_gece_calisma.webp',
  ),
  ottomanAmber(
    id: 'amber',
    label: 'Klasik Kehribar',
    seed: Color(0xFFB45309),
    secondary: Color(0xFFD97706),
    defaultWallpaper: 'assets/images/bg_osmanli_kutuphane.webp',
  ),
  oceanSapphire(
    id: 'sapphire',
    label: 'Okyanus Safiri',
    seed: Color(0xFF0284C7),
    secondary: Color(0xFF2563EB),
    defaultWallpaper: 'assets/images/bg_sabah_ferah.webp',
  ),
  plumOrchid(
    id: 'plum',
    label: 'Gece Orkidesi',
    seed: Color(0xFF7E22CE),
    secondary: Color(0xFFC026D3),
    defaultWallpaper: 'assets/images/catalog_tools_bg.jpg',
  );

  const LibraryThemePreset({
    required this.id,
    required this.label,
    required this.seed,
    required this.secondary,
    required this.defaultWallpaper,
  });

  final String id;
  final String label;
  final Color seed;
  final Color secondary;
  final String defaultWallpaper;

  static LibraryThemePreset fromId(String? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return indigoRoyal;
  }
}

enum WallpaperClarity {
  vivid('canli', 'Canlı Manzara', 'Arka plan resmi belirgin parlar'),
  balanced('dengeli', 'Dengeli', 'Resim ve metin arasında yumuşak denge'),
  reading('okuma', 'Okuma Modu', 'Yoğun perde ile en yüksek yazı netliği');

  const WallpaperClarity(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;

  static WallpaperClarity fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return vivid;
  }
}

enum EffectIntensity {
  rich('zengin', 'Zengin Efekt', 'Yıldız, ışık hüzmesi, parıltı ve bokeh'),
  subtle('sade', 'Sade', 'Yumuşak parıltı ve hafif ışık tanecikleri'),
  off('kapali', 'Kapalı', 'Statik sakin arka plan');

  const EffectIntensity(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;

  static EffectIntensity fromId(String? id) {
    for (final e in values) {
      if (e.id == id) return e;
    }
    return rich;
  }
}

enum AtmospherePack {
  autoTime(
    id: 'oto_zaman',
    label: 'Zamanına Göre Akış',
    subtitle: 'Sabah ferah, öğle sonbahar, akşam Osmanlı kubbesi, gece yıldızlar',
    preset: LibraryThemePreset.indigoRoyal,
    wallpaper: kDynamicTimeWallpaper,
    clarity: WallpaperClarity.vivid,
    intensity: EffectIntensity.rich,
  ),
  starlight(
    id: 'yildizli',
    label: 'Yıldızlı Akademi',
    subtitle: 'Gökyüzü kubbeli gece kütüphanesi & altın yıldız parıltıları',
    preset: LibraryThemePreset.indigoRoyal,
    wallpaper: 'assets/images/bg_yildizli_kutuphane.webp',
    clarity: WallpaperClarity.vivid,
    intensity: EffectIntensity.rich,
  ),
  ottoman(
    id: 'osmanli',
    label: 'Osmanlı Kıraathanesi',
    subtitle: 'Tarihî kubbe, vitray ışık hüzmeleri ve bakır fener sıcaklığı',
    preset: LibraryThemePreset.ottomanAmber,
    wallpaper: 'assets/images/bg_osmanli_kutuphane.webp',
    clarity: WallpaperClarity.vivid,
    intensity: EffectIntensity.rich,
  ),
  autumn(
    id: 'sonbahar',
    label: 'Sonbahar Köşesi',
    subtitle: 'Altın yapraklı kemerli pencere & sıcak okuma koltuğu',
    preset: LibraryThemePreset.crimsonRepublic,
    wallpaper: 'assets/images/bg_sonbahar_okuma.webp',
    clarity: WallpaperClarity.balanced,
    intensity: EffectIntensity.rich,
  ),
  morning(
    id: 'sabah',
    label: 'Ferah Okuma Salonu',
    subtitle: 'Güneşli meşe kitaplıklar, ferah sabah ışığı ve safir tonlar',
    preset: LibraryThemePreset.oceanSapphire,
    wallpaper: 'assets/images/bg_sabah_ferah.webp',
    clarity: WallpaperClarity.balanced,
    intensity: EffectIntensity.subtle,
  ),
  emerald(
    id: 'zumrut',
    label: 'Gece Zümrüt Masa',
    subtitle: 'Yeşil masa lambası altında sakin tefekkür ve odak çalışma',
    preset: LibraryThemePreset.emeraldAtrium,
    wallpaper: 'assets/images/bg_gece_calisma.webp',
    clarity: WallpaperClarity.vivid,
    intensity: EffectIntensity.rich,
  );

  const AtmospherePack({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.preset,
    required this.wallpaper,
    required this.clarity,
    required this.intensity,
  });

  final String id;
  final String label;
  final String subtitle;
  final LibraryThemePreset preset;
  final String wallpaper;
  final WallpaperClarity clarity;
  final EffectIntensity intensity;

  static AtmospherePack? fromId(String? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

const availableWallpapers = <(String, String)>[
  (kDynamicTimeWallpaper, 'Zamanına Göre'),
  ('assets/images/bg_yildizli_kutuphane.webp', 'Yıldızlı Kubbe'),
  ('assets/images/bg_osmanli_kutuphane.webp', 'Osmanlı Kubbe'),
  ('assets/images/bg_sonbahar_okuma.webp', 'Sonbahar Köşesi'),
  ('assets/images/bg_sabah_ferah.webp', 'Sabah Salonu'),
  ('assets/images/bg_gece_calisma.webp', 'Gece Lambası'),
  ('assets/images/catalog_tools_bg.jpg', 'Kütüphane Holü'),
  ('assets/images/library_hero.jpg', 'Büyülü Kitaplık'),
  ('assets/images/school_desk_banner.jpg', 'Ödünç Bankosu'),
  ('assets/images/analytics_banner.jpg', 'Veri ve Analiz'),
  ('assets/images/duty_roster_banner.jpg', 'Okuma Masası'),
  ('assets/images/label_print_banner.jpg', 'Etiket Atölyesi'),
  ('', 'Düz (Resimsiz)'),
];

String resolveWallpaperAsset(String configured, [DateTime? now]) {
  if (configured != kDynamicTimeWallpaper) return configured;
  final hour = (now ?? DateTime.now()).hour;
  if (hour >= 6 && hour < 11) return 'assets/images/bg_sabah_ferah.webp';
  if (hour >= 11 && hour < 17) return 'assets/images/bg_sonbahar_okuma.webp';
  if (hour >= 17 && hour < 21) return 'assets/images/bg_osmanli_kutuphane.webp';
  return 'assets/images/bg_yildizli_kutuphane.webp';
}

class AppThemeSettings {
  const AppThemeSettings({
    this.preset = LibraryThemePreset.indigoRoyal,
    this.themeMode = ThemeMode.system,
    this.wallpaperAsset = kDynamicTimeWallpaper,
    this.clarity = WallpaperClarity.vivid,
    this.effectIntensity = EffectIntensity.rich,
    this.particlesEnabled = true,
    this.tapRipplesEnabled = true,
    this.glassCardsEnabled = true,
    this.atmospherePackId = 'oto_zaman',
    this.schoolName = 'Cumhuriyet Anadolu Lisesi',
    this.libraryName = 'Cumhuriyet Kütüphanesi',
    this.librarianName = '',
    this.principalName = '',
    this.accessionPrefix = 'CAL-',
    this.accessionDigits = 6,
  });

  final LibraryThemePreset preset;
  final ThemeMode themeMode;
  final String wallpaperAsset;
  final WallpaperClarity clarity;
  final EffectIntensity effectIntensity;
  final bool particlesEnabled;
  final bool tapRipplesEnabled;
  final bool glassCardsEnabled;
  final String atmospherePackId;
  final String schoolName;
  final String libraryName;
  final String librarianName;
  final String principalName;
  final String accessionPrefix;
  final int accessionDigits;

  String get effectiveWallpaperAsset => resolveWallpaperAsset(wallpaperAsset);

  EffectIntensity get effectiveIntensity =>
      particlesEnabled ? effectIntensity : EffectIntensity.off;

  AppThemeSettings copyWith({
    LibraryThemePreset? preset,
    ThemeMode? themeMode,
    String? wallpaperAsset,
    WallpaperClarity? clarity,
    EffectIntensity? effectIntensity,
    bool? particlesEnabled,
    bool? tapRipplesEnabled,
    bool? glassCardsEnabled,
    String? atmospherePackId,
    String? schoolName,
    String? libraryName,
    String? librarianName,
    String? principalName,
    String? accessionPrefix,
    int? accessionDigits,
  }) {
    return AppThemeSettings(
      preset: preset ?? this.preset,
      themeMode: themeMode ?? this.themeMode,
      wallpaperAsset: wallpaperAsset ?? this.wallpaperAsset,
      clarity: clarity ?? this.clarity,
      effectIntensity: effectIntensity ?? this.effectIntensity,
      particlesEnabled: particlesEnabled ?? this.particlesEnabled,
      tapRipplesEnabled: tapRipplesEnabled ?? this.tapRipplesEnabled,
      glassCardsEnabled: glassCardsEnabled ?? this.glassCardsEnabled,
      atmospherePackId: atmospherePackId ?? this.atmospherePackId,
      schoolName: schoolName ?? this.schoolName,
      libraryName: libraryName ?? this.libraryName,
      librarianName: librarianName ?? this.librarianName,
      principalName: principalName ?? this.principalName,
      accessionPrefix: accessionPrefix ?? this.accessionPrefix,
      accessionDigits: accessionDigits ?? this.accessionDigits,
    );
  }

  AppThemeSettings applyPack(AtmospherePack pack) {
    return copyWith(
      preset: pack.preset,
      wallpaperAsset: pack.wallpaper,
      clarity: pack.clarity,
      effectIntensity: pack.intensity,
      particlesEnabled: pack.intensity != EffectIntensity.off,
      atmospherePackId: pack.id,
    );
  }

  Map<String, dynamic> toJson() => {
    'preset': preset.id,
    'themeMode': themeMode.name,
    'wallpaperAsset': wallpaperAsset,
    'clarity': clarity.id,
    'effectIntensity': effectIntensity.id,
    'particlesEnabled': particlesEnabled,
    'tapRipplesEnabled': tapRipplesEnabled,
    'glassCardsEnabled': glassCardsEnabled,
    'atmospherePackId': atmospherePackId,
    'schoolName': schoolName,
    'libraryName': libraryName,
    'librarianName': librarianName,
    'principalName': principalName,
    'accessionPrefix': accessionPrefix,
    'accessionDigits': accessionDigits,
  };

  factory AppThemeSettings.fromJson(Map<String, dynamic> json) {
    final preset = LibraryThemePreset.fromId(json['preset'] as String?);
    final modeStr = json['themeMode'] as String? ?? 'system';
    final mode = switch (modeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final hasV2Fields = json.containsKey('clarity');
    final rawWp = json['wallpaperAsset'] as String?;
    final wp = (!hasV2Fields && rawWp != null && rawWp.endsWith('.jpg'))
        ? kDynamicTimeWallpaper
        : (rawWp ?? kDynamicTimeWallpaper);
    return AppThemeSettings(
      preset: preset,
      themeMode: mode,
      wallpaperAsset: wp,
      clarity: WallpaperClarity.fromId(json['clarity'] as String?),
      effectIntensity:
          EffectIntensity.fromId(json['effectIntensity'] as String?),
      particlesEnabled: json['particlesEnabled'] != false,
      tapRipplesEnabled: json['tapRipplesEnabled'] != false,
      glassCardsEnabled: json['glassCardsEnabled'] != false,
      atmospherePackId: (json['atmospherePackId'] as String?) ?? 'oto_zaman',
      schoolName: (json['schoolName'] as String?)?.trim().isNotEmpty == true
          ? (json['schoolName'] as String).trim()
          : 'Cumhuriyet Anadolu Lisesi',
      libraryName: (json['libraryName'] as String?)?.trim().isNotEmpty == true
          ? (json['libraryName'] as String).trim()
          : 'Cumhuriyet Kütüphanesi',
      librarianName: (json['librarianName'] as String?)?.trim() ?? '',
      principalName: (json['principalName'] as String?)?.trim() ?? '',
      accessionPrefix:
          (json['accessionPrefix'] as String?)?.trim().isNotEmpty == true
          ? (json['accessionPrefix'] as String).trim()
          : 'CAL-',
      accessionDigits: (json['accessionDigits'] is int)
          ? (json['accessionDigits'] as int).clamp(3, 8)
          : 6,
    );
  }
}

final ValueNotifier<AppThemeSettings> appThemeNotifier =
    ValueNotifier<AppThemeSettings>(const AppThemeSettings());

class AppThemeStore {
  AppThemeStore(this.directory);
  final Directory directory;

  File get file => File('${directory.path}/school_app_settings.json');

  Future<AppThemeSettings> load() async {
    try {
      if (!await file.exists()) return const AppThemeSettings();
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        final loaded = AppThemeSettings.fromJson(raw);
        appThemeNotifier.value = loaded;
        return loaded;
      }
    } catch (_) {}
    return const AppThemeSettings();
  }

  Future<void> save(AppThemeSettings settings) async {
    appThemeNotifier.value = settings;
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }
}
