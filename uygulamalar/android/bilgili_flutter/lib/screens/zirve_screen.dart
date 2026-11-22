import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/quiz_models.dart';
import '../services/native_bridge.dart';
import '../state/arena_controller.dart';

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

const _altin = Color(0xFFF2C14E);
const _lacivert = Color(0xFF0B1450);
const _gece = Color(0xFF03061C);
const _turuncu = Color(0xFFFF9A1F);
const _dogruYesil = Color(0xFF22B455);
const _yanlisKirmizi = Color(0xFFD6333F);

enum _Evre { soru, bekle, acikla, bitti }

class ZirveScreen extends StatefulWidget {
  final ArenaController controller;
  final Topic konu;
  const ZirveScreen({super.key, required this.controller, this.konu = Topic.mixed});

  @override
  State<ZirveScreen> createState() => _ZirveScreenState();
}

class _ZirveScreenState extends State<ZirveScreen> with SingleTickerProviderStateMixin {
  final _rng = Random();
  late List<Question> _sorular;
  late Map<Difficulty, Question> _yedek;
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
  int _kazanc = 0;
  String _bitisNedeni = '';
  late final AnimationController _isik =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  ArenaController get ctrl => widget.controller;
  Question get _q => _sorular[_i];

  @override
  void initState() {
    super.initState();
    _yeniOyun();
  }

  @override
  void dispose() {
    _saat?.cancel();
    _isik.dispose();
    super.dispose();
  }

  void _ses(String tur) => NativeBridge.playSfx(tur, enabled: ctrl.sfxEnabled, haptics: ctrl.hapticsEnabled);

  void _yeniOyun() {
    final paket = ctrl.zirveSorulari(topic: widget.konu);
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
    });
    _soruyaBasla();
    _ses('start');
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
    if (_kalan > 0) {
      _saat = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _evre != _Evre.soru) return;
        setState(() => _kalan--);
        if (_kalan <= 5 && _kalan > 0) NativeBridge.playSfx('tick', enabled: ctrl.sfxEnabled, haptics: false, volume: .4);
        if (_kalan <= 0) {
          t.cancel();
          _ses('timeout');
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
    await Future<void>.delayed(Duration(milliseconds: _i < 5 ? 900 : 1800));
    if (!mounted) return;
    final dogru = i == _q.answer;
    setState(() => _evre = _Evre.acikla);
    _ses(dogru ? 'correct' : 'wrong');
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
    _ses('joker');
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
    _ses('joker');
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
    _ses('joker');
  }

  void _degistir() {
    if (_degistirKullanildi || _evre != _Evre.soru) return;
    final yeni = _yedek[_q.difficulty];
    if (yeni == null) return;
    setState(() {
      _degistirKullanildi = true;
      _sorular[_i] = yeni;
    });
    _ses('joker');
    _soruyaBasla();
  }

  // --- Görünüm ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _gece,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.35),
                radius: 1.15,
                colors: [Color(0xFF1C2C8C), _lacivert, _gece],
                stops: [0, .45, 1],
              ),
            ),
          ),
          if (!MediaQuery.disableAnimationsOf(context))
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _isik,
                builder: (_, _) => CustomPaint(painter: _IsikHuzmeleri(_isik.value)),
              ),
            ),
          SafeArea(child: !_hazir ? _yetersiz() : (_evre == _Evre.bitti ? _sonuc() : _oyun())),
        ],
      ),
    );
  }

  Widget _yetersiz() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Bu konuda merdiven için yeterli soru yok.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            _AltinDugme(metin: 'Geri dön', onTap: () => Navigator.of(context).maybePop()),
          ]),
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
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => const _StudyoDiyalog(
                      baslik: 'Yarışmadan çık', metin: 'Çıkarsan bu tur kaydedilmez.', evet: 'Çık', hayir: 'Kal'),
                );
                if (ok == true && mounted) Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
            ),
            Expanded(
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: _MerdivenRozeti(i: _i, onTap: _merdiveniGoster)),
              ),
            ),
            TextButton.icon(
              onPressed: _evre == _Evre.soru ? _cekil : null,
              icon: const Icon(Icons.flag_rounded, color: _altin),
              label: const Text('Çekil', style: TextStyle(color: _altin, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _JokerDugme(ikon: Icons.contrast_rounded, etiket: '50:50', kullanildi: _yariKullanildi, onTap: _yariYariya),
            _JokerDugme(ikon: Icons.bar_chart_rounded, etiket: 'Salon', kullanildi: _salonKullanildi, onTap: _salon),
            _JokerDugme(ikon: Icons.support_agent_rounded, etiket: 'Danışman', kullanildi: _danismanKullanildi, onTap: _danisman),
            _JokerDugme(ikon: Icons.swap_horiz_rounded, etiket: 'Değiştir', kullanildi: _degistirKullanildi, onTap: _degistir),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            children: [
              if (_salonOylari != null) _SalonGrafigi(oylar: _salonOylari!, gizli: _gizli),
              if (_danismanSozu != null) _DanismanBalonu(soz: _danismanSozu!),
              const SizedBox(height: 8),
              if (sure > 0)
                Center(child: _SureHalkasi(kalan: _kalan, toplam: sure))
              else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Süre sınırı yok', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
                  ),
                ),
              const SizedBox(height: 12),
              _SoruKutusu(
                  baslik: 'Soru ${_i + 1} · ${puanYaz(ZirveMerdiveni.odul[_i])} puan', metin: _q.text),
              const SizedBox(height: 16),
              for (var k = 0; k < _q.options.length; k++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SecenekKutusu(
                    harf: String.fromCharCode(65 + k),
                    metin: _gizli.contains(k) ? '' : _q.options[k],
                    durum: _durum(k),
                    onTap: () => _sec(k),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  _SecenekDurumu _durum(int k) {
    if (_gizli.contains(k)) return _SecenekDurumu.gizli;
    if (_evre == _Evre.acikla) {
      if (k == _q.answer) return _SecenekDurumu.dogru;
      if (k == _secim) return _SecenekDurumu.yanlis;
      return _SecenekDurumu.normal;
    }
    if (k == _secim) return _SecenekDurumu.secili;
    return _SecenekDurumu.normal;
  }

  void _merdiveniGoster() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _lacivert,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)), side: BorderSide(color: _altin)),
      builder: (c) => SafeArea(child: _MerdivenListesi(i: _i)),
    );
  }

  Widget _sonuc() {
    final zirve = _kazanc == ZirveMerdiveni.odul.last;
    final q = _q;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
      children: [
        Icon(zirve ? Icons.emoji_events_rounded : Icons.stars_rounded, size: 96, color: _altin),
        const SizedBox(height: 10),
        Text(_bitisNedeni,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: _altin, width: 2),
            gradient: const LinearGradient(colors: [Color(0xFF14207A), _lacivert]),
          ),
          child: Column(children: [
            const Text('Kazancın', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            Text('${puanYaz(_kazanc)} puan',
                style: const TextStyle(color: _altin, fontSize: 34, fontWeight: FontWeight.w900)),
            Text('Ulaşılan basamak: ${zirve ? 15 : _i} / 15',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 12),
        Text('En iyi kazancın: ${puanYaz(ctrl.zirveEnIyi)} puan',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
        if (!zirve && _bitisNedeni != 'Çekildin.') ...[
          const SizedBox(height: 18),
          _SoruKutusu(baslik: 'Doğru cevap: ${String.fromCharCode(65 + q.answer)}) ${q.options[q.answer]}', metin: q.explanation),
        ],
        const SizedBox(height: 24),
        _AltinDugme(metin: 'Yeniden Oyna', onTap: _yeniOyun),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Ana sayfaya dön', style: TextStyle(color: Colors.white70, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bileşenler
// ---------------------------------------------------------------------------

class _IsikHuzmeleri extends CustomPainter {
  final double t;
  const _IsikHuzmeleri(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    for (var k = 0; k < 3; k++) {
      final aci = sin(t * 2 * pi + k * 2.1) * .35;
      final kaynak = Offset(s.width * (.2 + .3 * k), -20);
      final boy = s.height * 1.1;
      final p = Path()
        ..moveTo(kaynak.dx, kaynak.dy)
        ..lineTo(kaynak.dx + sin(aci - .12) * boy, kaynak.dy + cos(aci - .12) * boy)
        ..lineTo(kaynak.dx + sin(aci + .12) * boy, kaynak.dy + cos(aci + .12) * boy)
        ..close();
      canvas.drawPath(
        p,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF8FB4FF).withValues(alpha: .16), Colors.transparent],
          ).createShader(Offset.zero & s),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IsikHuzmeleri old) => old.t != t;
}

class _SoruKutusu extends StatelessWidget {
  final String baslik;
  final String metin;
  const _SoruKutusu({required this.baslik, required this.metin});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _altin, width: 2),
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A2A8E), Color(0xFF070C3A)]),
          boxShadow: [BoxShadow(color: _altin.withValues(alpha: .25), blurRadius: 18)],
        ),
        child: Column(children: [
          Text(baslik, textAlign: TextAlign.center,
              style: const TextStyle(color: _altin, fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 8),
          Text(metin, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.35)),
        ]),
      );
}

enum _SecenekDurumu { normal, secili, dogru, yanlis, gizli }

class _SecenekKutusu extends StatelessWidget {
  final String harf;
  final String metin;
  final _SecenekDurumu durum;
  final VoidCallback onTap;
  const _SecenekKutusu({required this.harf, required this.metin, required this.durum, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (zemin, kenar) = switch (durum) {
      _SecenekDurumu.secili => (_turuncu, Colors.white),
      _SecenekDurumu.dogru => (_dogruYesil, Colors.white),
      _SecenekDurumu.yanlis => (_yanlisKirmizi, Colors.white),
      _SecenekDurumu.gizli => (const Color(0xFF080C2E), const Color(0x55F2C14E)),
      _SecenekDurumu.normal => (const Color(0xFF0D1660), _altin),
    };
    return Semantics(
      button: durum != _SecenekDurumu.gizli,
      label: durum == _SecenekDurumu.gizli ? 'Seçenek $harf elendi' : 'Seçenek $harf: $metin',
      child: GestureDetector(
        onTap: durum == _SecenekDurumu.gizli ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: zemin,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: kenar, width: 2),
            boxShadow: durum == _SecenekDurumu.normal || durum == _SecenekDurumu.gizli
                ? null
                : [BoxShadow(color: zemin.withValues(alpha: .6), blurRadius: 16)],
          ),
          child: Row(children: [
            Text('$harf:', style: TextStyle(
                color: durum == _SecenekDurumu.normal ? _altin : Colors.white,
                fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(metin,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _JokerDugme extends StatelessWidget {
  final IconData ikon;
  final String etiket;
  final bool kullanildi;
  final VoidCallback onTap;
  const _JokerDugme({required this.ikon, required this.etiket, required this.kullanildi, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Semantics(
          button: true,
          enabled: !kullanildi,
          label: 'Joker: $etiket${kullanildi ? ', kullanıldı' : ''}',
          child: GestureDetector(
            onTap: kullanildi ? null : onTap,
            child: Opacity(
              opacity: kullanildi ? .35 : 1,
              child: Column(children: [
                Container(
                  width: 58,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _altin, width: 2),
                    gradient: const LinearGradient(colors: [Color(0xFF1A2A8E), Color(0xFF070C3A)]),
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    Icon(ikon, color: Colors.white, size: 22),
                    if (kullanildi) const Icon(Icons.close_rounded, color: _yanlisKirmizi, size: 34),
                  ]),
                ),
                const SizedBox(height: 3),
                Text(etiket, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
}

class _SureHalkasi extends StatelessWidget {
  final int kalan;
  final int toplam;
  const _SureHalkasi({required this.kalan, required this.toplam});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64,
        height: 64,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value: toplam == 0 ? 0 : kalan / toplam,
            strokeWidth: 5,
            backgroundColor: Colors.white12,
            color: kalan <= 5 ? _yanlisKirmizi : _altin,
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
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _altin.withValues(alpha: .6)),
          color: const Color(0xFF070C3A),
        ),
        child: Column(children: [
          const Text('Salon oylaması', style: TextStyle(color: _altin, fontWeight: FontWeight.w800)),
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
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Container(
                        width: 26,
                        height: 70 * oylar[k] / 100 + 2,
                        decoration: BoxDecoration(
                          color: _altin,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(String.fromCharCode(65 + k),
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ],
            ),
          ),
        ]),
      );
}

class _DanismanBalonu extends StatelessWidget {
  final String soz;
  const _DanismanBalonu({required this.soz});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _altin.withValues(alpha: .6)),
          color: const Color(0xFF070C3A),
        ),
        child: Row(children: [
          const Icon(Icons.support_agent_rounded, color: _altin, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Text('Danışman: $soz', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        ]),
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
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _altin),
              color: const Color(0xFF070C3A),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.stairs_rounded, color: _altin, size: 18),
              const SizedBox(width: 6),
              Text('${i + 1}/15 · ${puanYaz(ZirveMerdiveni.odul[i])}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
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
            child: Text('Ödül Merdiveni', style: TextStyle(color: _altin, fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 10),
          for (var k = 14; k >= 0; k--)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: k == i ? _turuncu : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
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
        title: Text(baslik, style: const TextStyle(color: _altin, fontWeight: FontWeight.w900)),
        content: Text(metin, style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          if (hayir != null)
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text(hayir!, style: const TextStyle(color: Colors.white70))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _altin, foregroundColor: _gece),
            onPressed: () => Navigator.pop(context, true),
            child: Text(evet, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      );
}

class _AltinDugme extends StatelessWidget {
  final String metin;
  final VoidCallback onTap;
  const _AltinDugme({required this.metin, required this.onTap});
  @override
  Widget build(BuildContext context) => Center(
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _altin,
            foregroundColor: _gece,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            shape: const StadiumBorder(),
          ),
          onPressed: onTap,
          child: Text(metin, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ),
      );
}
