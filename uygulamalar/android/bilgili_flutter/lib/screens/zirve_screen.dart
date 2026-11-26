import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/quiz_models.dart';
import '../services/native_bridge.dart';
import '../state/arena_controller.dart';
import '../theme/arena_design.dart';

/// Zirve Merdiveni: 15 basamaklı, giderek zorlaşan bilgi yarışması.
/// Yanlış cevapta son baraj puanına düşülür; istenen anda çekilip
/// kazanılan puan alınabilir. Dört joker vardır.
class ZirveMerdiveni {
  static const odul = [100, 250, 500, 1000, 2000, 3500, 5000, 7500, 10000, 25000, 50000, 100000, 250000, 500000, 1000000];
  static const barajlar = {4, 9};

  /// [basamak] tane soru doğru bilindiyse güvenceye alınmış puan.
  static int guvence(int basamak) {
    var g = 0;
    for (final b in barajlar) {
      if (basamak > b) g = odul[b];
    }
    return g;
  }

  static int sure(int i) => i < 5 ? 30 : (i < 10 ? 45 : 0);
}

String puanYaz(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

const _altin = StudioPalette.gold;
const _lacivert = StudioPalette.navyMid;
const _gece = StudioPalette.night;
const _yanlisKirmizi = StudioPalette.crimson;

enum _Evre { giris, soru, bekle, acikla, bitti }

class ZirveScreen extends StatefulWidget {
  final ArenaController controller;
  final Topic konu;
  final Set<Topic> konular;
  const ZirveScreen({
    super.key,
    required this.controller,
    this.konu = Topic.mixed,
    this.konular = const {},
  });

  @override
  State<ZirveScreen> createState() => _ZirveScreenState();
}

class _ZirveScreenState extends State<ZirveScreen> {
  final _rng = Random();
  late List<Question> _sorular;
  late Map<Difficulty, Question> _yedek;
  late Set<Topic> _seciliKonular;
  bool _hazir = false;
  int _i = 0;
  _Evre _evre = _Evre.soru;
  int? _secim;
  Set<int> _gizli = {};
  bool _yariKullanildi = false, _salonKullanildi = false, _danismanKullanildi = false, _degistirKullanildi = false;
  List<int>? _salonOylari;
  String? _danismanSozu;
  int _kalan = 0;
  Timer? _saat;
  Timer? _sonMuzik;
  int _kazanc = 0;
  String _bitisNedeni = '';

  ArenaController get ctrl => widget.controller;
  Question get _q => _sorular[_i];

  static const _klipler = ['zirve_soru', 'zirve_sec', 'zirve_dogru', 'zirve_yanlis', 'zirve_baraj', 'zirve_zafer', 'zirve_joker', 'zirve_cekil'];

  @override
  void initState() {
    super.initState();
    _seciliKonular = widget.konular.isNotEmpty
        ? Set<Topic>.of(widget.konular.where((t) => t != Topic.mixed && t != Topic.custom))
        : (widget.konu != Topic.mixed && widget.konu != Topic.custom ? {widget.konu} : <Topic>{});
    // Efektleri önceden yükle (sessiz çalma ilk gecikmeyi önler).
    for (final k in _klipler) {
      NativeBridge.playClip(k, enabled: ctrl.sfxEnabled, volume: 0);
    }
    _yeniOyun();
  }

  @override
  void dispose() {
    _saat?.cancel();
    _sonMuzik?.cancel();
    ctrl.ozelMuzikAyarla(null);
    super.dispose();
  }

  void _ses(String tur) => NativeBridge.playSfx(tur, enabled: false, haptics: ctrl.hapticsEnabled);

  /// Zirve Merdiveni'ne özgü ses efekti; titreşim ayarı da uygulanır.
  void _klip(String ad, {String titresim = 'tick'}) {
    NativeBridge.playClip('zirve_$ad', enabled: ctrl.sfxEnabled, volume: .9);
    _ses(titresim);
  }

  void _muzik(String? parca) => ctrl.ozelMuzikAyarla(parca == null ? 'sessiz' : 'zirve_$parca');

  void _yeniOyun() {
    final paket = ctrl.zirveSorulari(
      topic: _seciliKonular.length == 1 ? _seciliKonular.first : Topic.mixed,
      topics: _seciliKonular.isEmpty ? null : _seciliKonular,
    );
    if (paket == null) {
      setState(() => _hazir = false);
      return;
    }
    setState(() {
      _sorular = paket.sorular.map((q) => q.shuffled(_rng)).toList();
      _yedek = {for (final e in paket.yedek.entries) e.key: e.value.shuffled(_rng)};
      _hazir = true;
      _i = 0;
      _kazanc = 0;
      _yariKullanildi = _salonKullanildi = _danismanKullanildi = _degistirKullanildi = false;
      _bitisNedeni = '';
      _evre = _Evre.giris;
    });
    _saat?.cancel();
    _sonMuzik?.cancel();
    _muzik('giris');
  }

  void _konuDegistir(Topic t) {
    setState(() {
      if (t == Topic.mixed) {
        _seciliKonular.clear();
      } else if (!_seciliKonular.remove(t)) {
        _seciliKonular.add(t);
      }
    });
    _yeniOyun();
  }

  void _soruyaBasla() {
    _saat?.cancel();
    setState(() {
      _evre = _Evre.soru;
      _secim = null;
      _gizli = {};
      _salonOylari = null;
      _danismanSozu = null;
      _kalan = ZirveMerdiveni.sure(_i);
    });
    _muzik('gerilim_${_i < 5 ? 1 : (_i < 10 ? 2 : 3)}');
    _klip('soru');
    if (_kalan > 0) {
      _saat = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _evre != _Evre.soru) return;
        setState(() => _kalan--);
        if (_kalan <= 5 && _kalan > 0) NativeBridge.playSfx('tick', enabled: ctrl.sfxEnabled, haptics: false, volume: .4);
        if (_kalan <= 0) {
          t.cancel();
          _muzik(null);
          _klip('yanlis', titresim: 'timeout');
          _bitir(dogru: false, neden: 'Süre doldu.');
        }
      });
    }
  }

  Future<void> _sec(int i) async {
    if (_evre != _Evre.soru || _gizli.contains(i)) return;
    setState(() => _secim = i);
    final kesin = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (c) => _StudyoDiyalog(
        baslik: 'Kesin cevabın mı?',
        metin: '${String.fromCharCode(65 + i)}: ${_q.options[i]}',
        evet: 'Kesin',
        hayir: 'Vazgeç',
      ),
    );
    if (!mounted || _evre != _Evre.soru) return;
    if (kesin != true) {
      setState(() => _secim = null);
      return;
    }
    _saat?.cancel();
    setState(() => _evre = _Evre.bekle);
    _muzik(null);
    _klip('sec');
    await Future<void>.delayed(Duration(milliseconds: _i < 5 ? 900 : 1800));
    if (!mounted) return;
    final dogru = i == _q.answer;
    setState(() => _evre = _Evre.acikla);
    final sonSoru = dogru && _i == 14;
    final barajSorusu = dogru && ZirveMerdiveni.barajlar.contains(_i);
    _klip(sonSoru ? 'zafer' : (barajSorusu ? 'baraj' : (dogru ? 'dogru' : 'yanlis')),
        titresim: dogru ? 'correct' : 'wrong');
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    if (!dogru) {
      _bitir(dogru: false, neden: 'Yanlış cevap.');
    } else if (_i == 14) {
      _kazanc = ZirveMerdiveni.odul[14];
      _bitir(dogru: true, neden: 'Zirveye ulaştın!');
    } else {
      _kazanc = ZirveMerdiveni.odul[_i];
      final baraj = ZirveMerdiveni.barajlar.contains(_i);
      if (baraj) {
        await showDialog<void>(
          context: context,
          builder: (c) => _StudyoDiyalog(
            baslik: 'Baraj geçildi!',
            metin: '${puanYaz(_kazanc)} puan artık güvencede. Yanlış cevap versen de bu puanla ayrılırsın.',
            evet: 'Devam',
          ),
        );
        if (!mounted) return;
      }
      setState(() => _i++);
      _soruyaBasla();
    }
  }

  void _bitir({required bool dogru, required String neden}) {
    _saat?.cancel();
    if (!dogru && neden != 'Çekildin.') _kazanc = ZirveMerdiveni.guvence(_i);
    final basamak = dogru ? 15 : _i;
    ctrl.zirveKaydet(kazanc: _kazanc, basamak: basamak);
    setState(() {
      _evre = _Evre.bitti;
      _bitisNedeni = neden;
    });
    _sonMuzik?.cancel();
    _sonMuzik = Timer(Duration(seconds: dogru ? 6 : 3), () {
      if (mounted && _evre == _Evre.bitti) _muzik('giris');
    });
  }

  Future<void> _cekil() async {
    if (_evre != _Evre.soru) return;
    final kazanc = _i == 0 ? 0 : ZirveMerdiveni.odul[_i - 1];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => _StudyoDiyalog(
        baslik: 'Çekilmek istiyor musun?',
        metin: '${puanYaz(kazanc)} puanla yarışmadan ayrılırsın.',
        evet: 'Çekil',
        hayir: 'Devam et',
      ),
    );
    if (ok != true || !mounted || _evre != _Evre.soru) return;
    _kazanc = kazanc;
    _muzik(null);
    _klip('cekil');
    _bitir(dogru: false, neden: 'Çekildin.');
  }

  // --- Jokerler ---------------------------------------------------------

  double get _bilmeOrani => switch (_q.difficulty) {
        Difficulty.easy => .9,
        Difficulty.medium => .75,
        Difficulty.hard => .55,
      };

  void _yariYariya() {
    if (_yariKullanildi || _evre != _Evre.soru) return;
    final yanlislar = [for (var k = 0; k < 4; k++) if (k != _q.answer && !_gizli.contains(k)) k]..shuffle(_rng);
    setState(() {
      _yariKullanildi = true;
      _gizli = {..._gizli, ...yanlislar.take(max(0, yanlislar.length - 1))};
    });
    _klip('joker', titresim: 'joker');
  }

  void _salon() {
    if (_salonKullanildi || _evre != _Evre.soru) return;
    final acik = [for (var k = 0; k < 4; k++) if (!_gizli.contains(k)) k];
    final agirlik = <int, double>{};
    for (final k in acik) {
      agirlik[k] = 5 + _rng.nextDouble() * 20;
    }
    agirlik[_q.answer] = (agirlik[_q.answer] ?? 0) + 100 * _bilmeOrani * (0.6 + _rng.nextDouble() * 0.5);
    final toplam = agirlik.values.fold<double>(0, (a, b) => a + b);
    final oylar = List<int>.filled(4, 0);
    for (final e in agirlik.entries) {
      oylar[e.key] = (e.value / toplam * 100).round();
    }
    final fark = 100 - oylar.reduce((a, b) => a + b);
    oylar[_q.answer] += fark;
    setState(() {
      _salonKullanildi = true;
      _salonOylari = oylar;
    });
    _klip('joker', titresim: 'joker');
  }

  void _danisman() {
    if (_danismanKullanildi || _evre != _Evre.soru) return;
    final biliyor = _rng.nextDouble() < _bilmeOrani;
    final acik = [for (var k = 0; k < 4; k++) if (!_gizli.contains(k) && k != _q.answer) k];
    final tahmin = biliyor || acik.isEmpty ? _q.answer : acik[_rng.nextInt(acik.length)];
    final emin = biliyor ? 70 + _rng.nextInt(26) : 35 + _rng.nextInt(25);
    final harf = String.fromCharCode(65 + tahmin);
    setState(() {
      _danismanKullanildi = true;
      _danismanSozu = emin >= 80
          ? '"Bundan oldukça eminim: $harf. %$emin eminim."'
          : '"Tam emin değilim ama $harf olabilir. Ancak %$emin eminim."';
    });
    _klip('joker', titresim: 'joker');
  }

  void _degistir() {
    if (_degistirKullanildi || _evre != _Evre.soru) return;
    final yeni = _yedek[_q.difficulty];
    if (yeni == null) return;
    setState(() {
      _degistirKullanildi = true;
      _sorular[_i] = yeni;
    });
    _klip('joker', titresim: 'joker');
    _soruyaBasla();
  }

  // --- Görünüm ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final wp = ctrl.currentWallpaper;
    return Scaffold(
      backgroundColor: _gece,
      body: ArenaAmbientBackground(
        wallpaper: wp,
        clarity: ctrl.wallpaperClarity,
        intensity: ctrl.effectIntensity,
        reduceMotion: ctrl.reduceMotion,
        overrideAssetPath: wp.id.startsWith('istanbul_')
            ? wp.assetPath
            : 'assets/images/istanbul_kiz_kulesi.webp',
        child: SafeArea(
          child: !_hazir
              ? _yetersiz()
              : switch (_evre) {
                  _Evre.giris => _acilis(),
                  _Evre.bitti => _sonuc(),
                  _ => _oyun(),
                },
        ),
      ),
    );
  }

  String get _seciliKonuOzeti {
    if (_seciliKonular.isEmpty) return 'Tüm 23 Kategori (Karışık)';
    final adlar = Topic.poolCategories.where(_seciliKonular.contains).map((t) => t.label).toList();
    if (adlar.length <= 2) return adlar.join(' + ');
    return '${adlar[0]}, ${adlar[1]} +${adlar.length - 2} alan';
  }

  Widget _acilis() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Geri',
                style: IconButton.styleFrom(
                  backgroundColor: StudioPalette.navyTop.withValues(alpha: 0.72),
                  side: const BorderSide(color: _altin, width: 1.2),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: StudioPalette.navyDark.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: _altin.withValues(alpha: 0.7)),
                ),
                child: const Text(
                  'İSTANBUL SAHNESİ',
                  style: TextStyle(
                    color: StudioPalette.goldBright,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Center(child: Studio3DOrbitEmblem(icon: Icons.stairs_rounded, size: 88)),
          const SizedBox(height: 10),
          const Text(
            'Zirve Merdiveni',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: StudioPalette.goldBright,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black87, blurRadius: 12)],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '15 soru, giderek zorlaşır. 5. ve 10. basamaklar baraj.\nDört jokerin var; istediğin an çekilebilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14.5, height: 1.38),
          ),
          const SizedBox(height: 14),
          Center(
            child: Studio3DPlaque(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              chamfer: 12,
              child: Column(
                children: [
                  Text(
                    'Zirve ödülü: ${puanYaz(ZirveMerdiveni.odul.last)} puan',
                    style: const TextStyle(color: StudioPalette.goldBright, fontWeight: FontWeight.w900),
                  ),
                  if (ctrl.zirveEnIyi > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'En iyi kazancın: ${puanYaz(ctrl.zirveEnIyi)} puan',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Studio3DButton(
            label: 'Başla',
            icon: Icons.play_arrow_rounded,
            onPressed: _soruyaBasla,
            variant: StudioButtonVariant.gold,
            expand: true,
            fontSize: 20,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: _merdiveniGoster,
              icon: const Icon(Icons.format_list_numbered_rounded, color: _altin),
              label: const Text('Ödül merdivenini gör',
                  style: TextStyle(color: StudioPalette.goldBright, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 14),
          // Çoklu kategori seçici (Zirve Merdiveni'nde de birden fazla kategori seçilebilir!)
          ArenaGlassCard(
            tint: _altin,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.category_rounded, color: StudioPalette.goldBright, size: 17),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Kategoriler: $_seciliKonuOzeti',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_seciliKonular.isNotEmpty)
                      InkWell(
                        onTap: () => _konuDegistir(Topic.mixed),
                        child: const Text('Temizle',
                            style: TextStyle(color: _altin, fontSize: 11.5, fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _zirveKonuCipi(Topic.mixed, _seciliKonular.isEmpty),
                      for (final t in ctrl.availableTopics) ...[
                        const SizedBox(width: 6),
                        _zirveKonuCipi(t, _seciliKonular.contains(t)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _zirveKonuCipi(Topic t, bool secili) => ArenaPressDepth(
        depthOffset: 1.5,
        child: InkWell(
          onTap: () => _konuDegistir(t),
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                colors: secili
                    ? const [StudioPalette.goldBright, StudioPalette.gold]
                    : const [Color(0xE01A2A88), Color(0xE0081044)],
              ),
              border: Border.all(
                color: secili ? Colors.white : _altin.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.icon, size: 14, color: secili ? _gece : StudioPalette.goldBright),
                const SizedBox(width: 5),
                Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: secili ? FontWeight.w900 : FontWeight.w700,
                    color: secili ? _gece : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _yetersiz() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ArenaGlassCard(
            tint: _altin,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Bu konuda merdiven için yeterli soru yok.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18)),
              const SizedBox(height: 16),
              Studio3DButton(
                label: 'Geri dön',
                onPressed: () => Navigator.of(context).maybePop(),
                variant: StudioButtonVariant.gold,
              ),
            ]),
          ),
        ),
      );

  Widget _oyun() {
    final sure = ZirveMerdiveni.sure(_i);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(children: [
            IconButton(
              tooltip: 'Çık',
              style: IconButton.styleFrom(
                backgroundColor: StudioPalette.navyTop.withValues(alpha: 0.7),
                side: BorderSide(color: _altin.withValues(alpha: 0.5)),
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => const _StudyoDiyalog(
                      baslik: 'Yarışmadan çık', metin: 'Çıkarsan bu tur kaydedilmez.', evet: 'Çık', hayir: 'Kal'),
                );
                if (ok == true && mounted) Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
            Expanded(
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: _MerdivenRozeti(i: _i, onTap: _merdiveniGoster)),
              ),
            ),
            TextButton.icon(
              onPressed: _evre == _Evre.soru ? _cekil : null,
              icon: const Icon(Icons.flag_rounded, color: _altin),
              label: const Text('Çekil', style: TextStyle(color: StudioPalette.goldBright, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Studio3DJokerOrb(icon: Icons.contrast_rounded, label: '50:50', used: _yariKullanildi, onTap: _yariYariya),
            Studio3DJokerOrb(icon: Icons.bar_chart_rounded, label: 'Salon', used: _salonKullanildi, onTap: _salon),
            Studio3DJokerOrb(icon: Icons.support_agent_rounded, label: 'Danışman', used: _danismanKullanildi, onTap: _danisman),
            Studio3DJokerOrb(icon: Icons.swap_horiz_rounded, label: 'Değiştir', used: _degistirKullanildi, onTap: _degistir),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_salonOylari != null) _SalonGrafigi(oylar: _salonOylari!, gizli: _gizli),
                if (_danismanSozu != null) _DanismanBalonu(soz: _danismanSozu!),
                const SizedBox(height: 4),
                if (sure > 0)
                  Center(child: _SureHalkasi(kalan: _kalan, toplam: sure))
                else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Süre sınırı yok', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                    ),
                  ),
                const SizedBox(height: 8),
                Studio3DEntrance(
                  key: ValueKey('zirve_q_${_q.id}_$_i'),
                  child: _SoruKutusu(
                    baslik: 'Soru ${_i + 1} · ${puanYaz(ZirveMerdiveni.odul[_i])} puan',
                    metin: _q.text,
                  ),
                ),
                const SizedBox(height: 12),
                for (var k = 0; k < _q.options.length; k++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Studio3DOptionPlaque(
                      letter: String.fromCharCode(65 + k),
                      text: _gizli.contains(k) ? '' : _q.options[k],
                      state: _durum(k),
                      fontSize: 15.5,
                      onTap: _gizli.contains(k) ? null : () => _sec(k),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  StudioOptionState _durum(int k) {
    if (_gizli.contains(k)) return StudioOptionState.hidden;
    if (_evre == _Evre.acikla) {
      if (k == _q.answer) return StudioOptionState.correct;
      if (k == _secim) return StudioOptionState.wrong;
      return StudioOptionState.normal;
    }
    if (k == _secim) return StudioOptionState.selected;
    return StudioOptionState.normal;
  }

  void _merdiveniGoster() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _lacivert,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: _altin, width: 1.8),
      ),
      builder: (c) => SafeArea(child: _MerdivenListesi(i: _i)),
    );
  }

  Widget _sonuc() {
    final zirve = _kazanc == ZirveMerdiveni.odul.last;
    final q = _q;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          children: [
            Center(
              child: Studio3DOrbitEmblem(
                icon: zirve ? Icons.emoji_events_rounded : Icons.stars_rounded,
                size: 94,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _bitisNedeni,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 16),
            Studio3DPlaque(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Column(children: [
                const Text('Kazancın', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                Text(
                  '${puanYaz(_kazanc)} puan',
                  style: const TextStyle(color: StudioPalette.goldBright, fontSize: 34, fontWeight: FontWeight.w900),
                ),
                Text(
                  'Ulaşılan basamak: ${zirve ? 15 : _i} / 15',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(
              'En iyi kazancın: ${puanYaz(ctrl.zirveEnIyi)} puan',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
            if (!zirve && _bitisNedeni != 'Çekildin.') ...[
              const SizedBox(height: 18),
              _SoruKutusu(
                baslik: 'Doğru cevap: ${String.fromCharCode(65 + q.answer)}) ${q.options[q.answer]}',
                metin: q.explanation,
              ),
            ],
            const SizedBox(height: 22),
            Studio3DButton(
              label: 'Yeniden Oyna',
              icon: Icons.replay_rounded,
              onPressed: _yeniOyun,
              variant: StudioButtonVariant.gold,
              expand: true,
              fontSize: 18,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Ana sayfaya dön',
                    style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        ConfettiCelebrationOverlay(active: !ctrl.reduceMotion && _kazanc >= 2000),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bileşenler
// ---------------------------------------------------------------------------

class _SoruKutusu extends StatelessWidget {
  final String baslik;
  final String metin;
  const _SoruKutusu({required this.baslik, required this.metin});
  @override
  Widget build(BuildContext context) => Studio3DPlaque(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
        chamfer: 18,
        child: Column(children: [
          Text(
            baslik,
            textAlign: TextAlign.center,
            style: const TextStyle(color: StudioPalette.goldBright, fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            metin,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.35),
          ),
        ]),
      );
}

class _SureHalkasi extends StatelessWidget {
  final int kalan;
  final int toplam;
  const _SureHalkasi({required this.kalan, required this.toplam});
  @override
  Widget build(BuildContext context) => Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [StudioPalette.navyTop, _gece]),
          boxShadow: [
            BoxShadow(
              color: (kalan <= 5 ? _yanlisKirmizi : _altin).withValues(alpha: 0.45),
              blurRadius: 16,
            ),
          ],
        ),
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 62,
            height: 62,
            child: CircularProgressIndicator(
              value: toplam == 0 ? 0 : kalan / toplam,
              strokeWidth: 5,
              backgroundColor: Colors.white12,
              color: kalan <= 5 ? _yanlisKirmizi : _altin,
            ),
          ),
          Text('$kalan', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _SalonGrafigi extends StatelessWidget {
  final List<int> oylar;
  final Set<int> gizli;
  const _SalonGrafigi({required this.oylar, required this.gizli});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ArenaGlassCard(
          tint: _altin,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(children: [
            const Text('Salon oylaması', style: TextStyle(color: StudioPalette.goldBright, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var k = 0; k < 4; k++)
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(gizli.contains(k) ? '' : '%${oylar[k]}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Container(
                          width: 28,
                          height: 70 * oylar[k] / 100 + 2,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [StudioPalette.goldBright, StudioPalette.goldDeep],
                            ),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(String.fromCharCode(65 + k),
                            style: const TextStyle(color: StudioPalette.goldBright, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                ],
              ),
            ),
          ]),
        ),
      );
}

class _DanismanBalonu extends StatelessWidget {
  final String soz;
  const _DanismanBalonu({required this.soz});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ArenaGlassCard(
          tint: _altin,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.support_agent_rounded, color: StudioPalette.goldBright, size: 30),
            const SizedBox(width: 10),
            Expanded(child: Text('Danışman: $soz', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}

class _MerdivenRozeti extends StatelessWidget {
  final int i;
  final VoidCallback onTap;
  const _MerdivenRozeti({required this.i, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Ödül merdiveni, basamak ${i + 1}',
        child: ArenaPressDepth(
          depthOffset: 1.8,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _altin, width: 1.6),
                gradient: const LinearGradient(colors: [StudioPalette.navyTop, StudioPalette.navyDark]),
                boxShadow: [BoxShadow(color: _altin.withValues(alpha: 0.25), blurRadius: 10)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.stairs_rounded, color: StudioPalette.goldBright, size: 18),
                const SizedBox(width: 6),
                Text('${i + 1}/15 · ${puanYaz(ZirveMerdiveni.odul[i])}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ),
      );
}

class _MerdivenListesi extends StatelessWidget {
  final int i;
  const _MerdivenListesi({required this.i});
  @override
  Widget build(BuildContext context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        children: [
          const Center(
            child: Text('Ödül Merdiveni', style: TextStyle(color: StudioPalette.goldBright, fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 10),
          for (var k = 14; k >= 0; k--)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: k == i
                    ? const LinearGradient(colors: [StudioPalette.amber, Color(0xFFCC6400)])
                    : null,
                borderRadius: BorderRadius.circular(14),
                border: k == i ? Border.all(color: Colors.white70) : null,
              ),
              child: Row(children: [
                SizedBox(
                  width: 34,
                  child: Text('${k + 1}',
                      style: TextStyle(color: k < i ? _altin : Colors.white70, fontWeight: FontWeight.w800)),
                ),
                if (k < i) const Icon(Icons.check_rounded, color: _altin, size: 16),
                const Spacer(),
                Text('${puanYaz(ZirveMerdiveni.odul[k])} puan',
                    style: TextStyle(
                      color: ZirveMerdiveni.barajlar.contains(k) ? Colors.white : (k == i ? Colors.white : _altin),
                      fontWeight: ZirveMerdiveni.barajlar.contains(k) ? FontWeight.w900 : FontWeight.w700,
                    )),
                if (ZirveMerdiveni.barajlar.contains(k))
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.shield_rounded, color: Colors.white, size: 16),
                  ),
              ]),
            ),
          const SizedBox(height: 8),
          const Text('Kalkanlı basamaklar barajdır: geçtikten sonra yanlış cevapta o puanla ayrılırsın.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      );
}

class _StudyoDiyalog extends StatelessWidget {
  final String baslik;
  final String metin;
  final String evet;
  final String? hayir;
  const _StudyoDiyalog({required this.baslik, required this.metin, required this.evet, this.hayir});
  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: _lacivert,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: _altin, width: 2)),
        title: Text(baslik, style: const TextStyle(color: StudioPalette.goldBright, fontWeight: FontWeight.w900)),
        content: Text(metin, style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          if (hayir != null)
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text(hayir!, style: const TextStyle(color: Colors.white70))),
          Studio3DButton(
            label: evet,
            onPressed: () => Navigator.pop(context, true),
            variant: StudioButtonVariant.gold,
            shimmer: false,
            fontSize: 14,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
        ],
      );
}
