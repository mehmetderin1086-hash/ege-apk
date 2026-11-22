import 'package:flutter/material.dart';
import 'arena_salon.dart';
import '../models/quiz_models.dart';
import '../state/arena_controller.dart';
import '../services/native_bridge.dart';
import '../theme/arena_design.dart';

class _SalonKarti extends StatelessWidget {
  final String baslik;
  final String alt;
  final IconData ikon;
  final List<Color> renkler;
  final VoidCallback onTap;
  const _SalonKarti({required this.baslik, required this.alt, required this.ikon, required this.renkler, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$baslik. $alt',
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 96,
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(colors: renkler, begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(alt, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
              Icon(ikon, color: Colors.white, size: 38),
            ]),
          ),
        ),
      );
}

class HomePlayTab extends StatefulWidget {
  final ArenaController controller;
  final VoidCallback onOpenAiStudioTab;
  final VoidCallback onOpenAcademyReview;

  const HomePlayTab({
    super.key,
    required this.controller,
    required this.onOpenAiStudioTab,
    required this.onOpenAcademyReview,
  });

  @override
  State<HomePlayTab> createState() => _HomePlayTabState();
}

class _HomePlayTabState extends State<HomePlayTab> {
  late final TextEditingController _customPromptCtrl;

  @override
  void initState() {
    super.initState();
    _customPromptCtrl = TextEditingController(text: widget.controller.setup.customTopicPrompt);
  }

  @override
  void dispose() {
    _customPromptCtrl.dispose();
    super.dispose();
  }

  void _openDuelDialog(BuildContext context) {
    final c1 = TextEditingController(text: 'Oyuncu 1');
    final c2 = TextEditingController(text: 'Oyuncu 2');
    final c3 = TextEditingController();
    final c4 = TextEditingController();
    int perPlayer = 3;
    Topic duelTopic = widget.controller.setup.topic;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1324),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final accent = widget.controller.currentWallpaper.primary;
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
                      Icon(Icons.shield_rounded, color: accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Düello & Turnuva Arenası (2–4 Kişi)',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aynı cihazda sırayla yarışın; her oyuncunun puanı ve doğruluğu canlı tutulur.',
                    style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.7)),
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
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
                  ArenaScrollPills<Topic>(
                    items: const [
                      Topic.mixed,
                      Topic.science,
                      Topic.history,
                      Topic.geography,
                      Topic.culture,
                      Topic.sport,
                      Topic.cinema,
                    ],
                    selected: duelTopic,
                    labelBuilder: (t) => t.label,
                    onSelected: (t) => setSheet(() => duelTopic = t),
                    accent: accent,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () {
                      final names = [c1.text, c2.text, c3.text, c4.text]
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      Navigator.of(ctx).pop();
                      widget.controller.startDuelTournament(
                        names.length >= 2 ? names : ['Oyuncu 1', 'Oyuncu 2'],
                        topic: duelTopic,
                        perPlayer: perPlayer,
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: const Color(0xFF06101F),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text(
                      'Düelloyu Başlat',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _playerField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
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
    final accent = ctrl.currentWallpaper.primary;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1324),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
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
                  Icon(Icons.library_books_rounded, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bilgili Soru Bankası (${ctrl.totalPoolCount} Soru)',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
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
                'Lise, üniversite veya Bloom basamağına göre bir akademik paket seç. Konu ve etkinlik paketleri de çevrimdışı kullanılabilir.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.72)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: ctrl.offlinePacks.length,
                  itemBuilder: (ctx, i) {
                    final pack = ctrl.offlinePacks[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
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
                                      color: Colors.white.withValues(alpha: 0.68),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                ctrl.startPackRound(pack);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: const Color(0xFF06101F),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 18),
                              label: const Text(
                                'Çöz',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                              ),
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
    final accent = wp.primary;
    final setup = ctrl.setup;
    final topics = [Topic.mixed, ...ctrl.availableTopics, Topic.custom];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // Top Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: wp.surface, image: wp.assetPath == null ? null : DecorationImage(image: AssetImage(wp.assetPath!),
              fit: BoxFit.cover, alignment: const Alignment(0,-.5),
              colorFilter: const ColorFilter.mode(Color(0x9107111d), BlendMode.darken)),
          ),
          child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Bilgili',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: accent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '${ctrl.totalPoolCount} Soru',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Bilgi Arenası · ${wp.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.68),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: ctrl.cycleWallpaper,
              tooltip: 'Atmosfer Değiştir',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
              icon: Icon(Icons.wallpaper_rounded, color: accent, size: 20),
            ),
            const SizedBox(width: 8),
            LevelMedallion(level: ctrl.level, gold: wp.secondary),
          ],
        )),
        const SizedBox(height: 14),

        ArenaImageActionButton(
          title: 'Bilgi Akademisi',
          subtitle: 'Soru havuzu, tekrar kartları ve defterim',
          icon: Icons.auto_stories_rounded,
          imageAsset: MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context)
              ? 'assets/images/study_book.webp' : 'assets/images/study_pages.webp',
          accent: accent,
          height: 118,
          onTap: widget.onOpenAcademyReview,
        ),
        const SizedBox(height: 12),
        // Hero Card
        Card(
          margin: EdgeInsets.zero,
          color: const Color(0xff171915),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: NativeBridge.openAtlas,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: Image.asset('assets/images/atlas_earth.webp', width: 58, excludeFromSemantics: true),
            title: const Text('3D Bilgi Atlası', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            subtitle: const Text('4 modeli döndür, incele ve bilgini sına.', style: TextStyle(color: Color(0xffd8d8cf))),
            trailing: const Icon(Icons.arrow_forward_rounded, color: Color(0xffff855a)),
          ),
        ),
        const SizedBox(height: 14),
        ArenaGlassCard(
          tint: accent,
          highContrast: ctrl.highContrast,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'MERAKLA BAŞLAR · SERİ ${ctrl.dailyStreak} GÜN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Her soruda yeni bir ufuk keşfet.',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${ctrl.visualQuestionCount} görselli grafik/şema · ${ctrl.activityQuestionCount} dinleme, sıralama, eşleştirme ve telaffuz etkinliği hazır.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.74),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'Seviye ${ctrl.level}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${ctrl.xpInCurrentLevel} / 250 XP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: (ctrl.xpInCurrentLevel / 250.0).clamp(0.03, 1.0),
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _launchFilteredRound(ctrl.startConfiguredRound()),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: const Color(0xFF06101F),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 21),
                      label: Text(
                        'Turu Başlat (${setup.questionCount} Soru)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2x2 Illustrated Studio Cards
        Row(
          children: [
            Expanded(
              child: ArenaImageActionButton(
                title: 'Canlı Sesli Tur',
                subtitle: 'Sunucu okur, sesle bil',
                badge: 'SESLİ',
                icon: Icons.mic_rounded,
                imageAsset: 'assets/images/card_voice_quiz.jpg',
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
                imageAsset: 'assets/images/card_daily_trophy.jpg',
                accent: const Color(0xFFF6C453),
                onTap: ctrl.startDailyChallenge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SalonKarti(
                baslik: 'Çok Oyunculu',
                alt: 'Bire Bir · Çoklu · Özel Oda',
                ikon: Icons.groups_rounded,
                renkler: const [Color(0xFF12C25A), Color(0xFF0B7A3A)],
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => OyunModlariScreen(controller: ctrl))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SalonKarti(
                baslik: 'Etkinlikler',
                alt: 'Süreli konu yarışmaları',
                ikon: Icons.event_available_rounded,
                renkler: const [Color(0xFFF39A12), Color(0xFFB8590A)],
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => EtkinliklerScreen(controller: ctrl))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ArenaImageActionButton(
                title: 'AI Soru Stüdyosu',
                subtitle: 'CLIProxy · Tüm Modeller',
                badge: '${ctrl.availableModels.length} MODEL',
                icon: Icons.auto_fix_high_rounded,
                imageAsset: 'assets/images/scene_cyber_arena.webp',
                accent: const Color(0xFF8AB4FF),
                onTap: widget.onOpenAiStudioTab,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ArenaImageActionButton(
                title: 'Düello Arenası',
                subtitle: '2–4 kişi aynı ekranda',
                badge: 'TURNUVA',
                icon: Icons.shield_rounded,
                imageAsset: 'assets/images/scene_duel_stage.webp',
                accent: const Color(0xFFFF9559),
                onTap: () => _openDuelDialog(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Quick Interactive Discovery & Spaced Repetition Strip
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
                      'Grafik · Şema · Telaffuz',
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

        // 10,000 Question Bank Quick Launcher Banner
        ArenaGlassCard(
          tint: const Color(0xFFF6C453),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () => _openQuestionBankSheet(context),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6C453).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.library_books_rounded,
                  color: Color(0xFFF6C453),
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
                      'Lise ve üniversite · Bloom’un altı basamağı',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFF6C453)),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Round Setup Panel
        ArenaGlassCard(
          tint: accent,
          highContrast: ctrl.highContrast,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: accent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tur Kurulumu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70),
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
                style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
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
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70),
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Zorluk',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ArenaScrollPills<Difficulty?>(
                          items: const [null, Difficulty.easy, Difficulty.medium, Difficulty.hard],
                          selected: setup.difficulty,
                          labelBuilder: (d) => d?.label ?? 'Dengeli',
                          onSelected: (d) =>
                              ctrl.updateSetup(setup.copyWith(difficulty: () => d)),
                          accent: accent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Soru Sayısı',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70),
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
        const SizedBox(height: 16),

        // Category Selection Grid
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Konu & Alan Seçimi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topics.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 1.62,
          ),
          itemBuilder: (context, index) {
            final topic = topics[index];
            final selected = setup.topic == topic;
            return Semantics(selected: selected, button: true, child: ArenaPressDepth(child: InkWell(
              onTap: () => ctrl.updateSetup(setup.copyWith(topic: topic)),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  image: DecorationImage(image: AssetImage(topic.coverImage), fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: ctrl.highContrast ? .81 : .55), BlendMode.darken)),
                  boxShadow: [BoxShadow(color: selected ? topic.accent.withValues(alpha:.3) : Colors.black38,
                    blurRadius: selected ? 10 : 3, offset: const Offset(0,3))],
                  border: Border.all(
                    color: selected
                        ? topic.accent
                        : Colors.white.withValues(alpha: 0.10),
                    width: selected ? 1.5 : 1.0,
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
                            color: topic.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(topic.icon, color: topic.accent, size: 18),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${ctrl.countForTopic(topic)}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: topic.accent,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (selected)
                          Icon(Icons.check_circle_rounded, color: topic.accent, size: 17),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      topic.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      topic.invitation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            )));
          },
        ),

        // Dynamic Exam / Lesson Picker
        if (setup.topic == Topic.exam) ...[
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
                    fontWeight: FontWeight.w800,
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

        // Dynamic Custom Topic AI Prompt
        if (setup.topic == Topic.custom) ...[
          const SizedBox(height: 14),
          ArenaGlassCard(
            tint: Topic.custom.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Özel Konu ile Yapay Zekâ Turu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Topic.custom.accent,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _customPromptCtrl,
                  onChanged: (v) => ctrl.updateSetup(setup.copyWith(customTopicPrompt: v)),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Örn: Osmanlı Denizcilik Tarihi, Kuantum Fiziği, Dünya Kupası...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: ctrl.isGeneratingAiQuestions
                      ? null
                      : () {
                          ctrl.generateAiQuestionsPack(
                            topic: Topic.custom,
                            difficulty: setup.difficulty ?? Difficulty.medium,
                            format: setup.format,
                            count: 10,
                            customPrompt: _customPromptCtrl.text,
                            startImmediately: true,
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: Topic.custom.accent,
                    foregroundColor: const Color(0xFF06101F),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    ctrl.isGeneratingAiQuestions
                        ? ctrl.aiGenerationStatus
                        : 'CLIProxy ile 10 Soru Üret ve Başla',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _presetButton(String label, VoidCallback onTap, Color accent) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent),
        ),
      ),
    );
  }
}
