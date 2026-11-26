import 'package:flutter/material.dart';
import '../services/native_bridge.dart';
import '../state/arena_controller.dart';
import '../theme/arena_design.dart';

class SettingsTab extends StatelessWidget {
  final ArenaController controller;
  const SettingsTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final wp = controller.currentWallpaper;
    final accent = wp.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        ArenaSceneHeader(title: 'Atmosfer, Ses & Ayarlar', description: 'Duvar kâğıtları, efektler, müzikler, sesli yanıt ve tam yedekleme', scene: 'atrium'),
        const SizedBox(height: 14),

        // İstanbul Sahne & Arka Plan Galerisi
        ArenaGlassCard(
          tint: StudioPalette.gold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.landscape_rounded, color: StudioPalette.goldBright, size: 18),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'İstanbul Sahne & Arka Plan Galerisi',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 124,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ArenaWallpapers.catalog.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final item = ArenaWallpapers.catalog[i];
                    final selected = item.id == controller.wallpaperId;
                    return ArenaPressDepth(
                      depthOffset: 1.8,
                      child: InkWell(
                        onTap: () => controller.selectWallpaper(item.id),
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 132,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? StudioPalette.goldBright
                                  : StudioPalette.gold.withValues(alpha: 0.35),
                              width: selected ? 2.2 : 1.1,
                            ),
                            boxShadow: [
                              if (selected)
                                BoxShadow(
                                  color: StudioPalette.gold.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                ),
                              const BoxShadow(color: Colors.black54, offset: Offset(0, 3)),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (item.assetPath != null)
                                  Image.asset(item.assetPath!, fit: BoxFit.cover)
                                else
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: item.gradient ?? [item.surface, item.ink],
                                      ),
                                    ),
                                  ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        const Color(0xD903061C),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (selected)
                                        Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: StudioPalette.goldBright,
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            size: 13,
                                            color: StudioPalette.night,
                                          ),
                                        ),
                                      const Spacer(),
                                      Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: selected ? StudioPalette.goldBright : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        item.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          color: Colors.white70,
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
                  },
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'İstanbul Arka Plan Netliği',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<WallpaperClarity>(
                items: WallpaperClarity.values,
                selected: controller.wallpaperClarity,
                labelBuilder: (c) => c.label,
                onSelected: (c) => controller.updatePreferences(clarity: c),
                accent: accent,
              ),
              const SizedBox(height: 12),
              const Text(
                '3D Stüdyo Işıkları & Efekt Yoğunluğu',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<EffectIntensity>(
                items: EffectIntensity.values,
                selected: controller.effectIntensity,
                labelBuilder: (e) => e.label,
                onSelected: (e) => controller.updatePreferences(intensity: e),
                accent: accent,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Audio & Voice Settings
        ArenaGlassCard(
          tint: const Color(0xFFF6C453),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Müzik, Ses Efektleri & Canlı Sunucu',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: controller.menuMusicEnabled,
                activeTrackColor: accent,
                title: const Text(
                  'Menü Arka Plan Müziği',
                  style: TextStyle(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onChanged: (v) => controller.updatePreferences(menuMusic: v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: controller.gameMusicEnabled,
                activeTrackColor: accent,
                title: const Text(
                  'Yarışma Tur Müziği',
                  style: TextStyle(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onChanged: (v) => controller.updatePreferences(gameMusic: v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: controller.sfxEnabled,
                activeTrackColor: accent,
                title: const Text(
                  'Oyun Ses Efektleri',
                  style: TextStyle(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onChanged: (v) => controller.updatePreferences(sfx: v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: controller.hapticsEnabled,
                activeTrackColor: accent,
                title: const Text(
                  'Dokunsal Titreşim (Haptic)',
                  style: TextStyle(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onChanged: (v) => controller.updatePreferences(haptics: v),
              ),
              const SizedBox(height: 8),
              const Text(
                'Seslendirme Motoru & Sunucu Sesi (Edge Neural TTS)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<String>(
                items: const ['tr-TR-AhmetNeural', 'tr-TR-EmelNeural', 'system'],
                selected: controller.ttsVoice,
                labelBuilder: (v) {
                  switch (v) {
                    case 'tr-TR-AhmetNeural':
                      return 'Edge TTS · Ahmet (Varsayılan)';
                    case 'tr-TR-EmelNeural':
                      return 'Edge TTS · Emel';
                    default:
                      return 'Sistem TTS (Çevrimdışı)';
                  }
                },
                onSelected: (v) => controller.updatePreferences(voice: v),
                accent: const Color(0xFFF6C453),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sunucu Okuma Hızı: ${controller.ttsSpeechRate.toStringAsFixed(2)}x',
                      style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => NativeBridge.speak(
                      'Merhaba, ben Ahmet. Bilgili yarışma stüdyosuna hoş geldin! Sesli yanıt sistemi hazır.',
                      language: 'tr-TR',
                      voice: controller.ttsVoice,
                      rate: controller.ttsSpeechRate,
                      awaitCompletion: false,
                    ),
                    icon: const Icon(Icons.volume_up_rounded, size: 16),
                    label: const Text(
                      'Sesi Test Et',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              Slider(
                value: controller.ttsSpeechRate.clamp(0.75, 1.45),
                min: 0.75,
                max: 1.45,
                activeColor: accent,
                onChanged: (v) => controller.updatePreferences(speechRate: v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: controller.liveVoiceExplain,
                activeTrackColor: accent,
                title: const Text(
                  'Canlı Turda Açıklamaları Sesli Oku',
                  style: TextStyle(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onChanged: (v) => controller.updatePreferences(liveExplain: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Accessibility
        ArenaGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Okunabilirlik & Erişilebilirlik',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: controller.highContrast,
                activeTrackColor: accent,
                title: const Text(
                  'Yüksek Kontrastlı Kart Kenarları',
                  style: TextStyle(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onChanged: (v) => controller.updatePreferences(contrast: v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: controller.reduceMotion,
                activeTrackColor: accent,
                title: const Text(
                  'Hareketli Efektleri Azalt',
                  style: TextStyle(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onChanged: (v) => controller.updatePreferences(motion: v),
              ),
              const SizedBox(height: 4),
              Text(
                'Soru Yazı Boyutu Ölçeği: ${(controller.readingScale * 100).round()}%',
                style: const TextStyle(fontSize: 12.5, color: Colors.white70),
              ),
              Slider(
                value: controller.readingScale.clamp(0.9, 1.3),
                min: 0.9,
                max: 1.3,
                divisions: 4,
                activeColor: accent,
                onChanged: (v) => controller.updatePreferences(scale: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Full Backup & Reset
        ArenaGlassCard(
          tint: const Color(0xFF5CE09B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tam Yedekleme (.bilgilibackup)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'XP, seviye, tekrar kartları, bilgi defteri, çalışma profilleri ve kişisel soru paketlerini tek dosyada yedekle.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Studio3DButton(
                      label: 'Dışa Aktar',
                      icon: Icons.archive_rounded,
                      variant: StudioButtonVariant.emerald,
                      expand: true,
                      fontSize: 13.5,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      onPressed: () async {
                        final ok = await controller.exportFullBackup();
                        if (context.mounted && ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Tam yedek başarıyla kaydedildi!')),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Studio3DButton(
                      label: 'Geri Yükle',
                      icon: Icons.restore_rounded,
                      variant: StudioButtonVariant.navy,
                      shimmer: false,
                      expand: true,
                      fontSize: 13.5,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      onPressed: () async {
                        final msg = await controller.restoreFullBackup();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: StudioPalette.navyDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.45)),
                      ),
                      title: const Text(
                        'İlerleme Sıfırlansın mı?',
                        style: TextStyle(
                          color: StudioPalette.goldBright,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      content: const Text(
                        'XP, geçmiş turlar ve tekrar kartların sıfırlanacak. Yerleşik akademik soru bankası korunur.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Vazgeç'),
                        ),
                        Studio3DButton(
                          label: 'Sıfırla',
                          variant: StudioButtonVariant.crimson,
                          shimmer: false,
                          fontSize: 13.5,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await controller.resetAllProgress();
                  }
                },
                icon: const Icon(Icons.restart_alt_rounded, color: StudioPalette.crimson, size: 18),
                label: const Text(
                  'İlerlemeyi ve Geçmişi Sıfırla',
                  style: TextStyle(color: StudioPalette.crimson, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 3D Marka & Sürüm Plaketi
        ArenaGlassCard(
          tint: StudioPalette.gold,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Bilgili3DLogo(size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bilgili · İstanbul Zirve Stüdyosu',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sürüm 3.21.0 · ${controller.totalPoolCount} çevrimdışı görsel, sesli & etkileşimli soru · 23 kategori',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.74),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
