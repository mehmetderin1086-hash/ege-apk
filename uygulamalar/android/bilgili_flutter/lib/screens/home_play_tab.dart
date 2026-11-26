import 'package:flutter/material.dart';
import 'arena_salon.dart';
import 'zirve_screen.dart';
import '../models/quiz_models.dart';
import '../state/arena_controller.dart';
import '../services/native_bridge.dart';
import '../theme/arena_design.dart';

class _ZirveKarti extends StatelessWidget {
  final int enIyi;
  final String konuOzeti;
  final VoidCallback onTap;
  const _ZirveKarti({
    required this.enIyi,
    required this.konuOzeti,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Zirve Merdiveni: 15 soru, 4 joker, 1.000.000 puanlık zirve',
        child: ArenaPressDepth(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: StudioPalette.gold, width: 2.1),
                  boxShadow: [
                    const BoxShadow(color: Color(0xFF593B04), offset: Offset(0, 5)),
                    BoxShadow(color: StudioPalette.gold.withValues(alpha: 0.36), blurRadius: 22),
                    const BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 8)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/images/istanbul_kiz_kulesi.webp',
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, -0.15),
                          excludeFromSemantics: true,
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                const Color(0xF0070D38),
                                const Color(0xD20C175C),
                                const Color(0x90050A2E),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 20,
                        right: 20,
                        height: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                StudioPalette.goldBright,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: StudioPalette.gold.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.7)),
                                    ),
                                    child: Text(
                                      'ANA SAHNE · $konuOzeti',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.7,
                                        color: StudioPalette.goldBright,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Zirve Merdiveni',
                                    style: TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w900,
                                      color: StudioPalette.goldBright,
                                      shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  const Text(
                                    '15 soru · 2 baraj · 4 joker · zirvede 1.000.000 puan',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (enIyi > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'En iyi: ${puanYaz(enIyi)} puan',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: StudioPalette.gold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Studio3DOrbitEmblem(
                              icon: Icons.stairs_rounded,
                              size: 56,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class HomePlayTab extends StatefulWidget {
  final ArenaController controller;
  final VoidCallback onOpenAcademyReview;
  final VoidCallback onOpenProgressTab;

  const HomePlayTab({
    super.key,
    required this.controller,
    required this.onOpenAcademyReview,
    required this.onOpenProgressTab,
  });

  @override
  State<HomePlayTab> createState() => _HomePlayTabState();
}

class _HomePlayTabState extends State<HomePlayTab> {
  static const _sayisalBundle = {
    Topic.mathematics,
    Topic.physics,
    Topic.chemistry,
    Topic.biology,
    Topic.statistics,
  };
  static const _sozelBundle = {
    Topic.history,
    Topic.geography,
    Topic.literature,
    Topic.socialScience,
  };
  static const _bilimTekBundle = {
    Topic.science,
    Topic.technology,
    Topic.computing,
    Topic.engineering,
    Topic.research,
  };
  static const _kulturSanatBundle = {
    Topic.culture,
    Topic.art,
    Topic.music,
    Topic.cinema,
    Topic.sport,
    Topic.nature,
  };

  void _openDuelDialog(BuildContext context) {
    final c1 = TextEditingController(text: 'Oyuncu 1');
    final c2 = TextEditingController(text: 'Oyuncu 2');
    final c3 = TextEditingController();
    final c4 = TextEditingController();
    int perPlayer = 3;
    final Set<Topic> duelTopics = Set<Topic>.of(widget.controller.setup.effectiveTopics);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioPalette.navyMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        side: BorderSide(color: StudioPalette.gold, width: 1.6),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final accent = StudioPalette.gold;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_rounded, color: StudioPalette.goldBright),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Düello & Turnuva Arenası (2–4 Kişi)',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: StudioPalette.goldBright,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aynı cihazda sırayla yarışın; birden fazla kategori seçebilirsiniz.',
                    style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.78)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _playerField(c1, '1. Oyuncu')),
                      const SizedBox(width: 10),
                      Expanded(child: _playerField(c2, '2. Oyuncu')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _playerField(c3, '3. Oyuncu (İsteğe bağlı)')),
                      const SizedBox(width: 10),
                      Expanded(child: _playerField(c4, '4. Oyuncu (İsteğe bağlı)')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Kişi Başı Soru Sayısı: $perPlayer',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: StudioPalette.goldBright,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ArenaScrollPills<int>(
                    items: const [2, 3, 5, 7],
                    selected: perPlayer,
                    labelBuilder: (n) => '$n Soru / Kişi',
                    onSelected: (n) => setSheet(() => perPlayer = n),
                    accent: accent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    duelTopics.isEmpty
                        ? 'Kategoriler: Karışık (Tümü)'
                        : 'Seçili Kategoriler (${duelTopics.length})',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: StudioPalette.goldBright,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _multiChip(
                          label: 'Karışık',
                          selected: duelTopics.isEmpty,
                          onTap: () => setSheet(duelTopics.clear),
                        ),
                        for (final t in widget.controller.availableTopics) ...[
                          const SizedBox(width: 6),
                          _multiChip(
                            label: t.label,
                            selected: duelTopics.contains(t),
                            onTap: () => setSheet(() {
                              if (!duelTopics.remove(t)) duelTopics.add(t);
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Studio3DButton(
                    label: 'Düelloyu Başlat',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    onPressed: () {
                      final names = [c1.text, c2.text, c3.text, c4.text]
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      Navigator.of(ctx).pop();
                      widget.controller.startDuelTournament(
                        names.length >= 2 ? names : ['Oyuncu 1', 'Oyuncu 2'],
                        topic: duelTopics.length == 1 ? duelTopics.first : Topic.mixed,
                        topics: duelTopics.isEmpty ? null : Set<Topic>.of(duelTopics),
                        perPlayer: perPlayer,
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _multiChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(
              colors: selected
                  ? const [StudioPalette.goldBright, StudioPalette.gold]
                  : const [Color(0xE01A2A88), Color(0xE0081044)],
            ),
            border: Border.all(
              color: selected ? Colors.white : StudioPalette.gold.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              color: selected ? StudioPalette.night : Colors.white,
            ),
          ),
        ),
      );

  Widget _playerField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
        filled: true,
        fillColor: StudioPalette.navyDark.withValues(alpha: 0.85),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: StudioPalette.gold, width: 1.5),
        ),
      ),
    );
  }

  void _launchFilteredRound(bool started) {
    if (started) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Bu seçimle eşleşen soru yok. Konuyu, soru türünü veya zorluk düzeyini değiştir.'),
    ));
  }

  void _openQuestionBankSheet(BuildContext context) {
    final ctrl = widget.controller;
    const accent = StudioPalette.gold;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioPalette.navyMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        side: BorderSide(color: StudioPalette.gold, width: 1.6),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.76,
        minChildSize: 0.50,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.library_books_rounded, color: StudioPalette.goldBright),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bilgili Soru Bankası (${ctrl.totalPoolCount} Soru)',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              Text(
                'Lise, Bloom basamağı veya konu paketlerinden birini seçip hemen yarışmaya başla.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.76)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: ctrl.offlinePacks.length,
                  itemBuilder: (ctx, i) {
                    final pack = ctrl.offlinePacks[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ArenaGlassCard(
                        tint: accent,
                        padding: const EdgeInsets.all(13),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pack.title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${pack.questions.length} soru · ${pack.models.join(" · ")}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white.withValues(alpha: 0.72),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Studio3DButton(
                              label: 'Çöz',
                              icon: Icons.play_arrow_rounded,
                              shimmer: false,
                              fontSize: 12.5,
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                ctrl.startPackRound(pack);
                              },
                            ),
                          ],
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final wp = ctrl.currentWallpaper;
    const accent = StudioPalette.gold;
    final setup = ctrl.setup;
    final selectedSet = setup.effectiveTopics;
    final topics = [Topic.mixed, ...ctrl.availableTopics];
    final headerImg = wp.assetPath ?? 'assets/images/istanbul_ortakoy.webp';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
      children: [
        // 1. İstanbul × Zirve Merdiveni Üst Stüdyo Başlığı + 3D Oyun Logosu
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.78), width: 1.7),
            boxShadow: [
              BoxShadow(color: StudioPalette.gold.withValues(alpha: 0.24), blurRadius: 18),
              const BoxShadow(color: Colors.black54, offset: Offset(0, 6), blurRadius: 14),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22.5),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    headerImg,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.35),
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => const ColoredBox(color: StudioPalette.navyMid),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xED050A2B),
                          const Color(0xBD0B1450),
                          const Color(0x700B1450),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
                  child: Row(
                    children: [
                      const Bilgili3DLogo(size: 46, showHalo: true),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bilgili',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: StudioPalette.goldBright,
                                letterSpacing: -0.4,
                                height: 1.08,
                                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [StudioPalette.navyTop, StudioPalette.navyDark],
                                    ),
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(color: StudioPalette.gold, width: 1.1),
                                  ),
                                  child: Text(
                                    '${ctrl.totalPoolCount} Soru',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      color: StudioPalette.goldBright,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    wp.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      ArenaPressDepth(
                        depthOffset: 1.6,
                        child: IconButton(
                          onPressed: ctrl.cycleWallpaper,
                          tooltip: 'İstanbul Sahnesi Değiştir',
                          style: IconButton.styleFrom(
                            backgroundColor: StudioPalette.navyTop.withValues(alpha: 0.85),
                            side: const BorderSide(color: StudioPalette.gold, width: 1.3),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.wallpaper_rounded, color: StudioPalette.goldBright, size: 19),
                        ),
                      ),
                      const SizedBox(width: 6),
                      LevelMedallion(level: ctrl.level),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2. Zirve Merdiveni Ana Sahne Kartı (En Öne Çıkan 3D Stüdyo Modu)
        _ZirveKarti(
          enIyi: ctrl.zirveEnIyi,
          konuOzeti: setup.topicsLabel,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ZirveScreen(
                controller: ctrl,
                konu: setup.topic,
                konular: selectedSet,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 3. Ana Tur Başlatıcı & Seviye Stüdyo Kartı
        ArenaGlassCard(
          tint: accent,
          highContrast: ctrl.highContrast,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 15, color: StudioPalette.goldBright),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'İSTANBUL ZİRVE SAHNESİ · SERİ ${ctrl.dailyStreak} GÜN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              const Text(
                'Her soruda yeni bir ufuk keşfet.',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Aktif seçim: ${setup.topicsLabel} · ${ctrl.countForTopics(selectedSet)} soru hazır',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Seviye ${ctrl.level}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: StudioPalette.goldBright,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${ctrl.xpInCurrentLevel} / 250 XP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: (ctrl.xpInCurrentLevel / 250.0).clamp(0.03, 1.0),
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(StudioPalette.gold),
                ),
              ),
              const SizedBox(height: 15),
              Studio3DButton(
                label: 'Turu Başlat (${setup.questionCount} Soru)',
                icon: Icons.play_arrow_rounded,
                variant: StudioButtonVariant.gold,
                expand: true,
                fontSize: 15,
                onPressed: () => _launchFilteredRound(ctrl.startConfiguredRound()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. Çok Oyunculu & Etkinlikler (İstanbul 3D Stüdyo Kartları)
        Row(
          children: [
            Expanded(
              child: ArenaImageActionButton(
                title: 'Çok Oyunculu',
                subtitle: 'Bire Bir · Çoklu · Özel Oda',
                badge: 'SALON',
                icon: Icons.groups_rounded,
                imageAsset: 'assets/images/istanbul_galata.webp',
                accent: StudioPalette.emerald,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => OyunModlariScreen(controller: ctrl)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ArenaImageActionButton(
                title: 'Etkinlikler',
                subtitle: 'Süreli konu yarışmaları',
                badge: 'CANLI',
                icon: Icons.event_available_rounded,
                imageAsset: 'assets/images/istanbul_suleymaniye.webp',
                accent: StudioPalette.amber,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => EtkinliklerScreen(controller: ctrl)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 5. Canlı Sesli Tur & Günün Turu
        Row(
          children: [
            Expanded(
              child: ArenaImageActionButton(
                title: 'Canlı Sesli Tur',
                subtitle: 'Sunucu okur, sesle bil',
                badge: 'SESLİ',
                icon: Icons.mic_rounded,
                imageAsset: 'assets/images/istanbul_skyline.webp',
                accent: const Color(0xFF4CE0D2),
                onTap: () => _launchFilteredRound(ctrl.startLiveVoiceQuiz()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ArenaImageActionButton(
                title: 'Günün Turu',
                subtitle: ctrl.isDailyChallengeDoneToday
                    ? 'Bugün tamamlandı ✓'
                    : 'Her gün 10 özel soru',
                badge: ctrl.isDailyChallengeDoneToday ? 'TAMAM' : '+120 XP',
                icon: Icons.emoji_events_rounded,
                imageAsset: 'assets/images/istanbul_dolmabahce.webp',
                accent: StudioPalette.gold,
                onTap: ctrl.startDailyChallenge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 6. İlerleme & Analiz + Düello Arenası
        Row(
          children: [
            Expanded(
              child: ArenaImageActionButton(
                title: 'İlerleme & Analiz',
                subtitle: 'Ustalık · Rozetler · Grafikler',
                badge: 'SVY ${ctrl.level}',
                icon: Icons.workspace_premium_rounded,
                imageAsset: 'assets/images/istanbul_bogaz.webp',
                accent: StudioPalette.sapphire,
                onTap: widget.onOpenProgressTab,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ArenaImageActionButton(
                title: 'Düello Arenası',
                subtitle: '2–4 kişi aynı ekranda',
                badge: 'TURNUVA',
                icon: Icons.shield_rounded,
                imageAsset: 'assets/images/istanbul_ortakoy.webp',
                accent: const Color(0xFFFF9559),
                onTap: () => _openDuelDialog(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 7. Bilgi Akademisi & 3D Bilgi Atlası
        ArenaImageActionButton(
          title: 'Bilgi Akademisi',
          subtitle: 'Soru havuzu, tekrar kartları ve defterim',
          badge: 'AKADEMİ',
          icon: Icons.auto_stories_rounded,
          imageAsset: 'assets/images/istanbul_ayasofya.webp',
          accent: StudioPalette.gold,
          height: 104,
          onTap: widget.onOpenAcademyReview,
        ),
        const SizedBox(height: 10),
        ArenaGlassCard(
          tint: const Color(0xFFFF9559),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: NativeBridge.openAtlas,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/atlas_earth.webp',
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3D Bilgi Atlası',
                      style: TextStyle(
                        color: StudioPalette.goldBright,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '4 modeli döndür, incele ve bilgini sına.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: StudioPalette.goldBright),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 8. Sesli İngilizce Stüdyosu (3.000 Yeni Soru)
        ArenaGlassCard(
          tint: const Color(0xFF58D5E3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () => _openAudioEnglishStudioSheet(context, ctrl),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF58D5E3).withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF58D5E3).withValues(alpha: 0.60)),
                ),
                child: const Icon(
                  Icons.headphones_rounded,
                  color: Color(0xFF7CEEFF),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sesli İngilizce Stüdyosu (3.000 Soru)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'US/UK Dinleme · Sesli Dikte · Telaffuz · Word Order',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF7CEEFF), size: 26),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 8b. Görsel & Etkinlik + Aralıklı Tekrar
        Row(
          children: [
            Expanded(
              child: ArenaGlassCard(
                tint: const Color(0xFF5CE09B),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                onTap: ctrl.startVisualAndActivityDiscovery,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.insights_rounded, color: Color(0xFF5CE09B), size: 17),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Görsel & Etkinlik',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Bayrak · Saat · Atom · Matris',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ArenaGlassCard(
                tint: const Color(0xFFC5A3FF),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                onTap: () {
                  if (!ctrl.startSpacedRepetitionReview()) {
                    widget.onOpenAcademyReview();
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.replay_circle_filled_rounded,
                            color: Color(0xFFC5A3FF), size: 17),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Aralıklı Tekrar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${ctrl.dueReviewCards.length} bekleyen kart',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 9. Dev Soru Bankası Banner
        ArenaGlassCard(
          tint: StudioPalette.gold,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () => _openQuestionBankSheet(context),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: StudioPalette.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.6)),
                ),
                child: const Icon(
                  Icons.library_books_rounded,
                  color: StudioPalette.goldBright,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dev Soru Bankası (${ctrl.totalPoolCount} Soru · ${ctrl.offlinePacks.length} Paket)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '23 kategori · Bloom’un basamakları · Çevrimdışı',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: StudioPalette.goldBright),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 10. Tur Kurulumu Stüdyo Paneli
        ArenaGlassCard(
          tint: accent,
          highContrast: ctrl.highContrast,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18, color: StudioPalette.goldBright),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tur Kurulumu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _presetButton('Keşif (Öğren)', () => ctrl.applyPreset('kesif'), accent),
                  _presetButton('Kısa Tur (10)', () => ctrl.applyPreset('kisa'), accent),
                  _presetButton('Maraton (24)', () => ctrl.applyPreset('maraton'), accent),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Oyun Modu',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<GameMode>(
                items: GameMode.values,
                selected: setup.mode,
                labelBuilder: (m) => m.label,
                iconBuilder: (m) => m.icon,
                onSelected: (m) => ctrl.updateSetup(setup.copyWith(mode: m)),
                accent: accent,
              ),
              const SizedBox(height: 6),
              Text(
                setup.mode.subtitle,
                style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.72)),
              ),
              if (setup.mode == GameMode.timed) ...[
                const SizedBox(height: 10),
                ArenaScrollPills<int>(
                  items: const [1, 3, 5, 10, 15],
                  selected: setup.timedMinutes,
                  labelBuilder: (m) => '$m Dakika',
                  onSelected: (m) => ctrl.updateSetup(setup.copyWith(timedMinutes: m)),
                  accent: accent,
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Soru Biçimi',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<QuestionFormat>(
                items: QuestionFormat.sunulan,
                selected: setup.format,
                labelBuilder: (f) => f.label,
                iconBuilder: (f) => f.icon,
                onSelected: (f) => ctrl.updateSetup(setup.copyWith(format: f)),
                accent: accent,
              ),
              const SizedBox(height: 14),
              const Text(
                'Zorluk',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<Difficulty?>(
                items: const [null, Difficulty.easy, Difficulty.medium, Difficulty.hard],
                selected: setup.difficulty,
                labelBuilder: (d) => d?.label ?? 'Dengeli',
                onSelected: (d) => ctrl.updateSetup(setup.copyWith(difficulty: () => d)),
                accent: accent,
              ),
              const SizedBox(height: 14),
              const Text(
                'Soru Sayısı',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<int>(
                items: const [5, 10, 15, 20, 30],
                selected: setup.questionCount,
                labelBuilder: (c) => '$c Soru',
                onSelected: (c) => ctrl.updateSetup(setup.copyWith(questionCount: c)),
                accent: accent,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 11. Çoklu Kategori & Alan Seçimi (Birden Fazla Kategori Seçilebilir!)
        ArenaGlassCard(
          tint: StudioPalette.gold,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist_rounded, color: StudioPalette.goldBright, size: 19),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Konu & Alan Seçimi (Çoklu Seçim)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                  if (selectedSet.isNotEmpty)
                    InkWell(
                      onTap: ctrl.clearSelectedTopics,
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: StudioPalette.crimson.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: StudioPalette.crimson.withValues(alpha: 0.7)),
                        ),
                        child: const Text(
                          'Temizle',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                selectedSet.isEmpty
                    ? 'Birden fazla kategoriye dokunarak kendi karma turunu oluşturabilirsin.'
                    : '${selectedSet.length} kategori seçili: ${setup.topicsLabel} (${ctrl.countForTopics(selectedSet)} soru)',
                style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.82)),
              ),
              const SizedBox(height: 9),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _bundleButton('Tümü', selectedSet.isEmpty, ctrl.clearSelectedTopics),
                    const SizedBox(width: 6),
                    _bundleButton(
                      'Sayısal',
                      _setEquals(selectedSet, _sayisalBundle),
                      () => ctrl.selectTopicBundle(_sayisalBundle),
                    ),
                    const SizedBox(width: 6),
                    _bundleButton(
                      'Sözel',
                      _setEquals(selectedSet, _sozelBundle),
                      () => ctrl.selectTopicBundle(_sozelBundle),
                    ),
                    const SizedBox(width: 6),
                    _bundleButton(
                      'Bilim & Tek',
                      _setEquals(selectedSet, _bilimTekBundle),
                      () => ctrl.selectTopicBundle(_bilimTekBundle),
                    ),
                    const SizedBox(width: 6),
                    _bundleButton(
                      'Kültür & Sanat',
                      _setEquals(selectedSet, _kulturSanatBundle),
                      () => ctrl.selectTopicBundle(_kulturSanatBundle),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topics.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.56,
          ),
          itemBuilder: (context, index) {
            final topic = topics[index];
            final selected = setup.isTopicSelected(topic);
            return Semantics(
              selected: selected,
              button: true,
              child: ArenaPressDepth(
                child: InkWell(
                  onTap: () => ctrl.toggleTopicSelection(topic),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 190),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      image: DecorationImage(
                        image: AssetImage(topic.coverImage),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          selected
                              ? StudioPalette.navyMid.withValues(alpha: 0.62)
                              : Colors.black.withValues(alpha: ctrl.highContrast ? 0.82 : 0.64),
                          BlendMode.darken,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: selected
                              ? const Color(0xFF6B4806)
                              : const Color(0xCC020412),
                          offset: const Offset(0, 3.5),
                        ),
                        BoxShadow(
                          color: selected
                              ? StudioPalette.gold.withValues(alpha: 0.42)
                              : Colors.black38,
                          blurRadius: selected ? 14 : 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                      border: Border.all(
                        color: selected
                            ? StudioPalette.goldBright
                            : StudioPalette.gold.withValues(alpha: 0.28),
                        width: selected ? 2.1 : 1.1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? StudioPalette.gold.withValues(alpha: 0.28)
                                    : StudioPalette.navyDark.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? StudioPalette.goldBright
                                      : topic.accent.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Icon(
                                topic.icon,
                                color: selected ? StudioPalette.goldBright : topic.accent,
                                size: 17,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: StudioPalette.night.withValues(alpha: 0.68),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: StudioPalette.gold.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                '${ctrl.countForTopic(topic)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: StudioPalette.goldBright,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (selected)
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: StudioPalette.goldBright,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: StudioPalette.night,
                                  size: 13,
                                ),
                              ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          topic.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: selected ? StudioPalette.goldBright : Colors.white,
                            shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          topic.invitation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: 0.78),
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

        // Dynamic Exam / Lesson Picker (tek başına Sınav Hazırlık seçiliyse)
        if (selectedSet.length == 1 && selectedSet.first == Topic.exam) ...[
          const SizedBox(height: 14),
          ArenaGlassCard(
            tint: Topic.exam.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sınav & Ders Seçimi',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Topic.exam.accent,
                  ),
                ),
                const SizedBox(height: 10),
                ArenaScrollPills<ExamKind>(
                  items: ExamKind.values,
                  selected: setup.exam,
                  labelBuilder: (e) => '${e.label} · ${e.subtitle.split(" ").first}',
                  onSelected: (e) => ctrl.updateSetup(
                    setup.copyWith(exam: e, lesson: () => null),
                  ),
                  accent: Topic.exam.accent,
                ),
                const SizedBox(height: 10),
                ArenaScrollPills<String?>(
                  items: [null, ...setup.exam.lessons],
                  selected: setup.lesson,
                  labelBuilder: (l) => l ?? 'Tüm Dersler',
                  onSelected: (l) => ctrl.updateSetup(setup.copyWith(lesson: () => l)),
                  accent: Topic.exam.accent,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool _setEquals(Set<Topic> a, Set<Topic> b) => a.length == b.length && a.containsAll(b);

  Widget _bundleButton(String label, bool active, VoidCallback onTap) => ArenaPressDepth(
        depthOffset: 1.4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                colors: active
                    ? const [StudioPalette.goldBright, StudioPalette.gold]
                    : const [Color(0xE01A2A88), Color(0xE0081044)],
              ),
              border: Border.all(
                color: active ? Colors.white : StudioPalette.gold.withValues(alpha: 0.42),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                color: active ? StudioPalette.night : Colors.white,
              ),
            ),
          ),
        ),
      );

  void _openAudioEnglishStudioSheet(BuildContext context, ArenaController ctrl) {
    final modes = <(String, String, IconData, Color, QuestionFormat?)>[
      (
        'Karışık Sesli İngilizce (10 Soru)',
        'US/UK/AU aksanlarla Dinleme + Dikte + Telaffuz karma tur',
        Icons.auto_awesome_rounded,
        StudioPalette.goldBright,
        null,
      ),
      (
        'İngilizce Dinleme & Anlama (1.800 Soru)',
        'Günlük diyaloglar, havaalanı/otel anonsları, deyimler ve IELTS sayılar',
        Icons.headphones_rounded,
        const Color(0xFF58D5E3),
        QuestionFormat.listening,
      ),
      (
        'İngilizce Sesli Dikte (600 Soru)',
        'Normal (1.0x) veya yavaş (0.7x) dinle, eksik İngilizce kelimeyi yaz',
        Icons.hearing_rounded,
        const Color(0xFF5CE09B),
        QuestionFormat.dictation,
      ),
      (
        'İngilizce Telaffuz & Konuşma (600 Soru)',
        'Mikrofonla telaffuz denetimi, sessiz harfler, minimal çiftler ve hece vurgusu',
        Icons.record_voice_over_rounded,
        const Color(0xFFFF7BAC),
        QuestionFormat.pronunciation,
      ),
      (
        'İngilizce Cümle Kurma · Word Order (300 Soru)',
        'Karışık İngilizce öbekleri doğru dilbilgisi sırasına diz',
        Icons.swap_vert_rounded,
        const Color(0xFFC5A3FF),
        QuestionFormat.ordering,
      ),
      (
        'İngilizce Deyim & Phrasal Verb Eşleştirme (350 Soru)',
        'İngilizce deyimleri ve öbek fiilleri Türkçe anlamlarıyla eşleştir',
        Icons.compare_arrows_rounded,
        const Color(0xFFFFB076),
        QuestionFormat.matching,
      ),
      (
        'Görsel İngilizce Saat Stüdyosu (240 Soru)',
        'Analog saat kadranına bakarak doğru İngilizce saat ifadesini seç',
        Icons.schedule_rounded,
        const Color(0xFF5AB2FF),
        QuestionFormat.visual,
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1240),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.9,
          minChildSize: 0.45,
          builder: (_, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: StudioPalette.gold.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.headphones_rounded, color: Color(0xFF7CEEFF), size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sesli İngilizce Stüdyosu',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Doğal Amerikan, İngiliz ve Avustralya aksanlarıyla dinle, yaz, konuş ve pekiştir.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 14),
              for (final m in modes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: ArenaGlassCard(
                    tint: m.$4,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ctrl.startAudioEnglishStudio(format: m.$5, count: 10);
                    },
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: m.$4.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(m.$3, color: m.$4, size: 19),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                m.$2,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.play_arrow_rounded, color: m.$4, size: 22),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetButton(String label, VoidCallback onTap, Color accent) {
    return ArenaPressDepth(
      depthOffset: 1.4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5.5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [StudioPalette.navyTop, StudioPalette.navyDark]),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.55)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: StudioPalette.goldBright,
            ),
          ),
        ),
      ),
    );
  }
}
