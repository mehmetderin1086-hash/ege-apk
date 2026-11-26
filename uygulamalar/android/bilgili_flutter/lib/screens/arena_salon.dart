import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/quiz_models.dart';
import '../services/native_bridge.dart';
import '../state/arena_controller.dart';
import '../state/arena_rooms.dart';
import '../theme/arena_design.dart';

const _altin = StudioPalette.gold;
const _altinParlak = StudioPalette.goldBright;
const _lacivert = StudioPalette.navyMid;
const _gece = StudioPalette.night;

/// Salon ekranlarının ortak İstanbul × Zirve Merdiveni 3D stüdyo zemini.
class _Zemin extends StatelessWidget {
  final ArenaController ctrl;
  final Widget child;
  final String istanbulSahne;
  const _Zemin({
    required this.ctrl,
    required this.child,
    this.istanbulSahne = 'assets/images/istanbul_galata.webp',
  });

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
        overrideAssetPath: wp.id.startsWith('istanbul_') ? wp.assetPath : istanbulSahne,
        child: SafeArea(child: child),
      ),
    );
  }
}

class _GeriDugmesi extends StatelessWidget {
  const _GeriDugmesi();
  @override
  Widget build(BuildContext context) => _Yuvarlak(
        ikon: Icons.chevron_left_rounded,
        onTap: () => Navigator.of(context).maybePop(),
        anlam: 'Geri',
      );
}

class _Yuvarlak extends StatelessWidget {
  final IconData ikon;
  final VoidCallback onTap;
  final String anlam;
  const _Yuvarlak({required this.ikon, required this.onTap, required this.anlam});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: anlam,
        child: ArenaPressDepth(
          depthOffset: 1.8,
          child: InkResponse(
            onTap: onTap,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [StudioPalette.navyLight, StudioPalette.navyDark],
                ),
                border: Border.all(color: _altin, width: 1.8),
                boxShadow: [
                  BoxShadow(color: _altin.withValues(alpha: 0.28), blurRadius: 10),
                  const BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: Icon(ikon, color: _altinParlak, size: 28),
            ),
          ),
        ),
      );
}

void _salonuKapat(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

void _yardim(BuildContext context, String baslik, String metin) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _lacivert,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: _altin, width: 1.8),
      ),
      title: Text(baslik, style: const TextStyle(color: _altinParlak, fontWeight: FontWeight.w900)),
      content: Text(metin, style: const TextStyle(color: Colors.white, height: 1.38)),
      actions: [
        Studio3DButton(
          label: 'Tamam',
          shimmer: false,
          fontSize: 13.5,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          onPressed: () => Navigator.pop(c),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Oyun modları
// ---------------------------------------------------------------------------

class OyunModlariScreen extends StatelessWidget {
  final ArenaController controller;
  const OyunModlariScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return _Zemin(
      ctrl: controller,
      istanbulSahne: 'assets/images/istanbul_galata.webp',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(
            children: const [
              _GeriDugmesi(),
              Expanded(
                child: Text(
                  'Çok Oyunculu Salon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _altinParlak,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                  ),
                ),
              ),
              SizedBox(width: 46),
            ],
          ),
          const SizedBox(height: 18),
          _ModKarti(
            renk: StudioPalette.sapphire,
            gorsel: 'assets/images/istanbul_ortakoy.webp',
            baslik: 'Bire Bir',
            aciklama: 'Bir rakiple aynı sorulara karşı yarış, puanı yüksek olan kazansın.',
            ikon: Icons.sports_kabaddi_rounded,
            egim: -1,
            onTap: () => _rakipKur(context, 1),
          ),
          const SizedBox(height: 14),
          _ModKarti(
            renk: StudioPalette.amber,
            gorsel: 'assets/images/istanbul_skyline.webp',
            baslik: 'Çoklu',
            aciklama: 'Dört rakiple 5 kişilik odada oyna, sıralamada zirveye çık.',
            ikon: Icons.groups_rounded,
            egim: 1,
            onTap: () => _rakipKur(context, 4),
          ),
          const SizedBox(height: 14),
          _ModKarti(
            renk: StudioPalette.emerald,
            gorsel: 'assets/images/istanbul_dolmabahce.webp',
            baslik: 'Özel Oda',
            aciklama: 'Ayarları seç, oda numarasını paylaş; 10 kişiye kadar birlikte oyna.',
            ikon: Icons.meeting_room_rounded,
            egim: -1,
            yardim: () => _yardim(
              context,
              'Özel Oda',
              'Oda numarası kategoriyi, soru sayısını, süreyi ve soruları taşır. Aynı numarayı kendi telefonuna giren arkadaşların aynı soruları aynı sırayla çözer; puanlarınızı karşılaştırabilirsiniz.\n\n'
              'Odaya birden çok oyuncu eklerseniz aynı telefonda sırayla oynarsınız: her oyuncu kendi sorularını cevaplar ve sonda kürsü gösterilir.',
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OzelOdaScreen(controller: controller, oda: OdaAyari.yeni()))),
          ),
          const SizedBox(height: 22),
          _OdaNoGir(controller: controller),
        ],
      ),
    );
  }

  Future<void> _rakipKur(BuildContext context, int rakipSayisi) async {
    final Set<Topic> kategoriler = Set<Topic>.of(controller.setup.effectiveTopics);
    var soru = 7;
    var sure = 20;
    final basla = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _lacivert,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        side: BorderSide(color: _altin, width: 1.8),
      ),
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                rakipSayisi == 1 ? 'Bire Bir' : 'Çoklu Oda',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _altinParlak),
              ),
              const SizedBox(height: 12),
              Text(
                kategoriler.isEmpty
                    ? 'Kategoriler: Karışık (Birden fazla seçebilirsin)'
                    : 'Seçili Kategoriler (${kategoriler.length})',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _altinParlak),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _salonKonuCipi('Karışık', kategoriler.isEmpty, () => yenile(kategoriler.clear)),
                    for (final t in controller.availableTopics) ...[
                      const SizedBox(width: 6),
                      _salonKonuCipi(t.label, kategoriler.contains(t), () {
                        yenile(() {
                          if (!kategoriler.remove(t)) kategoriler.add(t);
                        });
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _AyarSatiri(
                soru: soru,
                sure: sure,
                onSoru: (v) => yenile(() => soru = v),
                onSure: (v) => yenile(() => sure = v),
              ),
              const SizedBox(height: 20),
              Studio3DButton(
                label: rakipSayisi == 1 ? 'Rakip Bul' : 'Odaya Katıl',
                icon: Icons.bolt_rounded,
                expand: true,
                fontSize: 18,
                onPressed: () => Navigator.pop(c, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (basla != true || !context.mounted) return;
    final rng = Random();
    final havuz = [...rakipAdlari]..shuffle(rng);
    final rakipler = havuz.take(rakipSayisi).toList();
    final hazir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EslesmeDiyalogu(rakipler: rakipler),
    );
    if (hazir != true || !context.mounted) return;
    _salonuKapat(context);
    controller.startRakipMaci(
      rakipler: rakipler,
      topic: kategoriler.length == 1 ? kategoriler.first : Topic.mixed,
      topics: kategoriler.isEmpty ? null : Set<Topic>.of(kategoriler),
      soru: soru,
      sure: sure,
    );
  }

  Widget _salonKonuCipi(String etiket, bool secili, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(
              colors: secili
                  ? const [_altinParlak, _altin]
                  : const [StudioPalette.navyTop, StudioPalette.navyDark],
            ),
            border: Border.all(color: secili ? Colors.white : _altin.withValues(alpha: 0.45)),
          ),
          child: Text(
            etiket,
            style: TextStyle(
              fontSize: 12,
              fontWeight: secili ? FontWeight.w900 : FontWeight.w700,
              color: secili ? _gece : Colors.white,
            ),
          ),
        ),
      );
}

class _ModKarti extends StatelessWidget {
  final Color renk;
  final String gorsel;
  final String baslik;
  final String aciklama;
  final IconData ikon;
  final int egim;
  final VoidCallback onTap;
  final VoidCallback? yardim;
  const _ModKarti({
    required this.renk,
    required this.gorsel,
    required this.baslik,
    required this.aciklama,
    required this.ikon,
    required this.egim,
    required this.onTap,
    this.yardim,
  });

  @override
  Widget build(BuildContext context) {
    final rim = Color.lerp(renk, _altin, 0.55)!;
    return Semantics(
      button: true,
      label: '$baslik. $aciklama',
      child: ArenaPressDepth(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 152),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: rim, width: 2.0),
              boxShadow: [
                BoxShadow(color: Color.lerp(rim, Colors.black, 0.72)!, offset: const Offset(0, 5)),
                BoxShadow(color: rim.withValues(alpha: 0.28), blurRadius: 18),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      gorsel,
                      fit: BoxFit.cover,
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
                            const Color(0xF0060C34),
                            Color.alphaBlend(renk.withValues(alpha: 0.25), const Color(0xCC0B1450)),
                            const Color(0x99050929),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 14, 22),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  baslik,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: _altinParlak,
                                    shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                aciklama,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (yardim != null)
                              IconButton(
                                tooltip: 'Nasıl çalışır?',
                                onPressed: yardim,
                                icon: const Icon(Icons.help_rounded, color: _altinParlak, size: 26),
                              ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [StudioPalette.navyLight, StudioPalette.night],
                                ),
                                border: Border.all(color: rim, width: 1.8),
                              ),
                              child: Icon(ikon, size: yardim != null ? 36 : 44, color: _altinParlak),
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
        ),
      ),
    );
  }
}

class _EslesmeDiyalogu extends StatefulWidget {
  final List<String> rakipler;
  const _EslesmeDiyalogu({required this.rakipler});
  @override
  State<_EslesmeDiyalogu> createState() => _EslesmeDiyaloguState();
}

class _EslesmeDiyaloguState extends State<_EslesmeDiyalogu> {
  int _gelen = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 550), (t) {
      if (!mounted) return;
      if (_gelen >= widget.rakipler.length) {
        t.cancel();
        Navigator.of(context).pop(true);
      } else {
        setState(() => _gelen++);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _lacivert,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: _altin, width: 2),
      ),
      title: Text(
        _gelen >= widget.rakipler.length ? 'Hazır!' : 'Rakip aranıyor…',
        style: const TextStyle(color: _altinParlak, fontWeight: FontWeight.w900),
      ),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          const _Avatar(ad: 'Sen', renk: StudioPalette.amber),
          for (var i = 0; i < widget.rakipler.length; i++)
            i < _gelen
                ? _Avatar(ad: widget.rakipler[i], renk: _avatarRengi(i + 1))
                : const SizedBox(
                    width: 64,
                    height: 86,
                    child: Center(child: CircularProgressIndicator(color: _altin)),
                  ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Vazgeç', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

class _OdaNoGir extends StatelessWidget {
  final ArenaController controller;
  const _OdaNoGir({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Oda numarası gir',
      child: ArenaPressDepth(
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: () => _sor(context),
          child: Studio3DPlaque(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            chamfer: 16,
            borderColor: _altinParlak,
            gradient: const [StudioPalette.goldBright, StudioPalette.gold, Color(0xFFD18E10)],
            child: const Row(
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Oda No Gir',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _gece),
                    ),
                  ),
                ),
                Spacer(),
                Text(
                  '_ _ _ _ _ _',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _gece, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sor(BuildContext context) async {
    final kontrol = TextEditingController();
    final kod = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _lacivert,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: _altin, width: 2),
        ),
        title: const Text('Oda numarası', style: TextStyle(color: _altinParlak, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: kontrol,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w900, color: Colors.white),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(hintText: '000000', counterText: ''),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç', style: TextStyle(color: Colors.white70))),
          Studio3DButton(
            label: 'Katıl',
            shimmer: false,
            fontSize: 14,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            onPressed: () => Navigator.pop(c, kontrol.text),
          ),
        ],
      ),
    );
    if (kod == null || !context.mounted) return;
    final oda = OdaAyari.coz(kod);
    if (oda == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu oda numarası geçerli değil. Altı haneyi kontrol et.')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => OzelOdaScreen(controller: controller, oda: oda, katildi: true)));
  }
}

// ---------------------------------------------------------------------------
// Özel oda
// ---------------------------------------------------------------------------

class OzelOdaScreen extends StatefulWidget {
  final ArenaController controller;
  final OdaAyari oda;
  final bool katildi;
  const OzelOdaScreen({super.key, required this.controller, required this.oda, this.katildi = false});

  @override
  State<OzelOdaScreen> createState() => _OzelOdaScreenState();
}

class _OzelOdaScreenState extends State<OzelOdaScreen> {
  late OdaAyari _oda = widget.oda;
  final List<String> _oyuncular = ['Oyuncu 1'];

  @override
  Widget build(BuildContext context) {
    final kod = _oda.kod;
    return _Zemin(
      ctrl: widget.controller,
      istanbulSahne: 'assets/images/istanbul_bogaz.webp',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(children: const [
            _GeriDugmesi(),
            Spacer(),
            Text('Kategori', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _altinParlak)),
            Spacer(),
            SizedBox(width: 46),
          ]),
          const SizedBox(height: 10),
          _KategoriSecici(secili: _oda.kategori, onSec: (t) => setState(() => _oda = _oda.copyWith(kategori: t))),
          const SizedBox(height: 20),
          _AyarSatiri(
            soru: _oda.soruSayisi,
            sure: _oda.sure,
            onSoru: (v) => setState(() => _oda = _oda.copyWith(soruSayisi: v)),
            onSure: (v) => setState(() => _oda = _oda.copyWith(sure: v)),
          ),
          const SizedBox(height: 22),
          const Center(
            child: Text('Oda Numarası', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _altinParlak)),
          ),
          const SizedBox(height: 10),
          _OdaKodu(
            kod: kod,
            onKopyala: () {
              Clipboard.setData(ClipboardData(text: kod));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Oda numarası $kod kopyalandı.')));
            },
            onPaylas: () => NativeBridge.shareText(
              'Bilgili\'de odama gel! Oda numarası: $kod\n'
              '${_oda.kategori.label} · ${_oda.soruSayisi} soru · ${_oda.sure} sn\n'
              'Uygulamada Çok Oyunculu › Oda No Gir bölümüne bu numarayı yaz; aynı soruları çözüp puanlarımızı karşılaştıralım.',
              title: 'Bilgili Oda Daveti',
            ),
          ),
          const SizedBox(height: 30),
          _OyuncuPaneli(
            oyuncular: _oyuncular,
            onEkle: _oyuncuEkle,
            onSil: (i) => setState(() => _oyuncular.removeAt(i)),
            onAdDegistir: _adDegistir,
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              _oyuncular.length == 1
                  ? 'Numarayı paylaş, arkadaşların kendi telefonlarında aynı soruları çözsün.'
                  : '${_oyuncular.length} oyuncu bu telefonda sırayla oynayacak.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 14),
          Studio3DButton(
            label: 'Oyunu Başlat',
            icon: Icons.play_arrow_rounded,
            expand: true,
            fontSize: 20,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onPressed: _baslat,
          ),
        ],
      ),
    );
  }

  Future<String?> _adSor(String baslik, String ilk) async {
    final k = TextEditingController(text: ilk);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _lacivert,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: _altin, width: 1.8),
        ),
        title: Text(baslik, style: const TextStyle(color: _altinParlak, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: k,
          autofocus: true,
          maxLength: 16,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç', style: TextStyle(color: Colors.white70))),
          Studio3DButton(
            label: 'Tamam',
            shimmer: false,
            fontSize: 13.5,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            onPressed: () => Navigator.pop(c, k.text),
          ),
        ],
      ),
    );
  }

  Future<void> _oyuncuEkle() async {
    if (_oyuncular.length >= 10) return;
    final ad = await _adSor('Oyuncu ekle', 'Oyuncu ${_oyuncular.length + 1}');
    if (ad == null || ad.trim().isEmpty || !mounted) return;
    setState(() => _oyuncular.add(ad.trim()));
  }

  Future<void> _adDegistir(int i) async {
    final ad = await _adSor('Adı değiştir', _oyuncular[i]);
    if (ad == null || ad.trim().isEmpty || !mounted) return;
    setState(() => _oyuncular[i] = ad.trim());
  }

  void _baslat() {
    final ok = widget.controller.startOdaRound(_oda, _oyuncular);
    if (ok) {
      _salonuKapat(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu kategoride yeterli soru bulunamadı.')),
      );
    }
  }
}

class _OdaKodu extends StatelessWidget {
  final String kod;
  final VoidCallback onKopyala;
  final VoidCallback onPaylas;
  const _OdaKodu({required this.kod, required this.onKopyala, required this.onPaylas});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Studio3DPlaque(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 44),
          chamfer: 16,
          child: Semantics(
            label: 'Oda numarası ${kod.split('').join(' ')}',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final h in kod.split(''))
                  Flexible(
                    child: Column(children: [
                      Text(h, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _altinParlak)),
                      Container(width: 28, height: 2.2, color: _altin),
                    ]),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -22,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HapDugme(metin: 'Kopyala', ikon: Icons.copy_rounded, onTap: onKopyala),
                const SizedBox(width: 12),
                _HapDugme(metin: 'Paylaş', ikon: Icons.ios_share_rounded, onTap: onPaylas),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HapDugme extends StatelessWidget {
  final String metin;
  final IconData ikon;
  final VoidCallback onTap;
  const _HapDugme({required this.metin, required this.ikon, required this.onTap});
  @override
  Widget build(BuildContext context) => ArenaPressDepth(
        depthOffset: 1.6,
        child: Material(
          color: StudioPalette.navyTop,
          shape: const StadiumBorder(side: BorderSide(color: _altin, width: 1.8)),
          elevation: 6,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              child: Row(children: [
                Text(metin, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _altinParlak)),
                const SizedBox(width: 8),
                Icon(ikon, color: _altinParlak, size: 20),
              ]),
            ),
          ),
        ),
      );
}

Color _avatarRengi(int i) => const [
      Color(0xFFFF9A1F), Color(0xFF1E88E5), Color(0xFF22B455), Color(0xFFE53935), Color(0xFF8E24AA),
      Color(0xFF00ACC1), Color(0xFFF2C14E), Color(0xFF6D4C41), Color(0xFFD81B60), Color(0xFF3949AB),
    ][i % 10];

class _Avatar extends StatelessWidget {
  final String ad;
  final Color renk;
  final int? sira;
  const _Avatar({required this.ad, required this.renk, this.sira});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: renk,
                    shape: BoxShape.circle,
                    border: Border.all(color: _altin, width: 2.5),
                    boxShadow: [BoxShadow(color: renk.withValues(alpha: 0.4), blurRadius: 10)],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    ad.isEmpty ? '?' : ad.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
                if (sira != null)
                  Positioned(
                    bottom: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: _gece,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _altin),
                      ),
                      child: Text('$sira', style: const TextStyle(color: _altinParlak, fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );
}

class _OyuncuPaneli extends StatelessWidget {
  final List<String> oyuncular;
  final VoidCallback onEkle;
  final void Function(int) onSil;
  final void Function(int) onAdDegistir;
  const _OyuncuPaneli({required this.oyuncular, required this.onEkle, required this.onSil, required this.onAdDegistir});

  @override
  Widget build(BuildContext context) {
    return ArenaGlassCard(
      tint: _altin,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 220),
        child: Column(
          children: [
            Row(children: [
              const Spacer(),
              const Text('Oyuncular', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _altinParlak)),
              const Spacer(),
              Text('${oyuncular.length}/10', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
            ]),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 16,
              children: [
                for (var i = 0; i < oyuncular.length; i++)
                  GestureDetector(
                    onTap: () => onAdDegistir(i),
                    onLongPress: i == 0 ? null : () => onSil(i),
                    child: _Avatar(ad: oyuncular[i], renk: _avatarRengi(i), sira: i + 1),
                  ),
                if (oyuncular.length < 10)
                  Semantics(
                    button: true,
                    label: 'Oyuncu ekle',
                    child: GestureDetector(
                      onTap: onEkle,
                      child: SizedBox(
                        width: 72,
                        child: Column(children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _altin.withValues(alpha: 0.7), width: 2),
                              color: StudioPalette.navyDark.withValues(alpha: 0.6),
                            ),
                            child: const Icon(Icons.add_rounded, color: _altinParlak, size: 30),
                          ),
                          const SizedBox(height: 10),
                          const Text('Ekle', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
            if (oyuncular.length > 1)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text('Adı değiştirmek için dokun, çıkarmak için basılı tut.',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ortak ayar bileşenleri
// ---------------------------------------------------------------------------

class _KategoriSecici extends StatelessWidget {
  final Topic secili;
  final ValueChanged<Topic> onSec;
  const _KategoriSecici({required this.secili, required this.onSec});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Kategori: ${secili.label}',
      child: ArenaPressDepth(
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: () async {
            final t = await showModalBottomSheet<Topic>(
              context: context,
              backgroundColor: _lacivert,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                side: BorderSide(color: _altin, width: 1.6),
              ),
              builder: (c) => SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .7),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final k in OdaAyari.kategoriler)
                        ListTile(
                          leading: CircleAvatar(backgroundColor: k.accent, child: Icon(k.icon, color: Colors.white)),
                          title: Text(k.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          trailing: k == secili ? const Icon(Icons.check_rounded, color: _altinParlak) : null,
                          onTap: () => Navigator.pop(c, k),
                        ),
                    ],
                  ),
                ),
              ),
            );
            if (t != null) onSec(t);
          },
          child: Studio3DPlaque(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            chamfer: 15,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        secili == Topic.mixed ? StudioPalette.navyLight : secili.accent,
                        StudioPalette.navyDark,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _altin, width: 1.4),
                  ),
                  child: Icon(
                    secili == Topic.mixed ? Icons.shuffle_rounded : secili.icon,
                    color: _altinParlak,
                    size: 26,
                  ),
                ),
                Expanded(
                  child: Text(
                    secili.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: _altinParlak, size: 30),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AyarSatiri extends StatelessWidget {
  final int soru;
  final int sure;
  final ValueChanged<int> onSoru;
  final ValueChanged<int> onSure;
  const _AyarSatiri({required this.soru, required this.sure, required this.onSoru, required this.onSure});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(children: [
            const Text('Soru Sayısı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _altinParlak)),
            const SizedBox(height: 8),
            _Segment(degerler: OdaAyari.soruSecenekleri, secili: soru, etiket: (v) => '$v', onSec: onSoru),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(children: [
            const Text('Süre', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _altinParlak)),
            const SizedBox(height: 8),
            _Segment(degerler: OdaAyari.sureSecenekleri, secili: sure, etiket: (v) => '${v}sn', onSec: onSure),
          ]),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  final List<int> degerler;
  final int secili;
  final String Function(int) etiket;
  final ValueChanged<int> onSec;
  const _Segment({required this.degerler, required this.secili, required this.etiket, required this.onSec});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [StudioPalette.navyTop, StudioPalette.navyDark]),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _altin.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Row(
        children: [
          for (final v in degerler)
            Expanded(
              child: Semantics(
                selected: v == secili,
                button: true,
                label: etiket(v),
                child: GestureDetector(
                  onTap: () => onSec(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: v == secili
                          ? const LinearGradient(colors: [_altinParlak, _altin])
                          : null,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          etiket(v),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: v == secili ? _gece : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Etkinlikler
// ---------------------------------------------------------------------------

class EtkinliklerScreen extends StatefulWidget {
  final ArenaController controller;
  const EtkinliklerScreen({super.key, required this.controller});
  @override
  State<EtkinliklerScreen> createState() => _EtkinliklerScreenState();
}

class _EtkinliklerScreenState extends State<EtkinliklerScreen> {
  Timer? _saat;

  @override
  void initState() {
    super.initState();
    _saat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _saat?.cancel();
    super.dispose();
  }

  static const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

  @override
  Widget build(BuildContext context) {
    final simdi = DateTime.now();
    final guncel = EtkinlikTakvimi.guncel(simdi);
    final gelecek = EtkinlikTakvimi.gelecek(simdi);
    return _Zemin(
      ctrl: widget.controller,
      istanbulSahne: 'assets/images/istanbul_suleymaniye.webp',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Row(children: [
            const _GeriDugmesi(),
            const Expanded(
              child: Text(
                'Etkinlikler',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: _altinParlak,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                ),
              ),
            ),
            _Yuvarlak(
              ikon: Icons.question_mark_rounded,
              anlam: 'Etkinlikler nasıl çalışır?',
              onTap: () => _yardim(
                context,
                'Etkinlikler',
                'Her gün yeni bir konu etkinliği başlar ve 1–3 gün sürer. Her etkinliğin sabit bir soru sayısı ve sınırlı deneme hakkı vardır; en yüksek puanın kaydedilir.\n\n'
                'Hafta sonu etkinlikleri 50 soru ve 5 hak sunar. "Gelecek" bölümünde yakında başlayacak etkinlikleri görebilirsin.',
              ),
            ),
          ]),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text('Gelecek', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _altinParlak)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 164,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in gelecek)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: 112,
                      child: Column(children: [
                        Container(
                          width: 94,
                          height: 94,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [StudioPalette.navyLight, StudioPalette.navyDark],
                            ),
                            border: Border.all(color: _altin, width: 2.5),
                            boxShadow: [BoxShadow(color: _altin.withValues(alpha: 0.28), blurRadius: 12)],
                          ),
                          child: Icon(e.tema.ikon, color: _altinParlak, size: 42),
                        ),
                        const SizedBox(height: 6),
                        Text(e.tema.ad, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        Text('${kalanSure(e.baslangic.difference(simdi))} sonra',
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ArenaGlassCard(
            tint: _altin,
            radius: 30,
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
            child: Column(
              children: [
                Row(children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text('Güncel', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _altinParlak)),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('${simdi.day} ${_aylar[simdi.month - 1]}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ]),
                const SizedBox(height: 14),
                for (final e in guncel) ...[
                  _EtkinlikKarti(
                    etkinlik: e,
                    deneme: widget.controller.etkinlikDenemesi(e),
                    enIyi: widget.controller.etkinlikEnIyi[e.anahtar],
                    simdi: simdi,
                    onTap: () => _ac(e),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _ac(Etkinlik e) async {
    final ctrl = widget.controller;
    final kalan = e.hak - ctrl.etkinlikDenemesi(e);
    final enIyi = ctrl.etkinlikEnIyi[e.anahtar];
    final basla = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _lacivert,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: _altin, width: 2),
        ),
        title: Text(e.tema.ad, style: const TextStyle(color: _altinParlak, fontWeight: FontWeight.w900)),
        content: Text(
          '${e.tema.konu.label} konusunda ${e.soruSayisi} soru, soru başına 20 saniye.\n'
          'Kalan deneme hakkı: $kalan / ${e.hak}'
          '${enIyi != null ? '\nEn iyi puanın: $enIyi' : ''}\n'
          'Bitişe ${kalanSure(e.bitis.difference(DateTime.now()))} var.',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Kapat', style: TextStyle(color: Colors.white70))),
          if (kalan > 0)
            Studio3DButton(
              label: 'Başla',
              shimmer: false,
              fontSize: 14,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              onPressed: () => Navigator.pop(c, true),
            ),
        ],
      ),
    );
    if (basla != true || !mounted) return;
    if (ctrl.startEtkinlik(e)) {
      _salonuKapat(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu etkinlik başlatılamadı.')));
    }
  }
}

class _EtkinlikKarti extends StatelessWidget {
  final Etkinlik etkinlik;
  final int deneme;
  final int? enIyi;
  final DateTime simdi;
  final VoidCallback onTap;
  const _EtkinlikKarti({required this.etkinlik, required this.deneme, required this.enIyi, required this.simdi, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final e = etkinlik;
    final bitti = deneme >= e.hak;
    return Semantics(
      button: true,
      label: '${e.tema.ad}, ${e.soruSayisi} soru, $deneme / ${e.hak} deneme, kalan ${kalanSure(e.bitis.difference(simdi))}',
      child: ArenaPressDepth(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 176,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: _altin, width: 1.9),
              gradient: LinearGradient(
                colors: [
                  Color.lerp(e.tema.renkler.first, StudioPalette.navyTop, 0.55)!,
                  StudioPalette.navyMid,
                  StudioPalette.night,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                const BoxShadow(color: Color(0xFF4D3405), offset: Offset(0, 4.5)),
                BoxShadow(color: _altin.withValues(alpha: 0.24), blurRadius: 16),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -14,
                  bottom: -14,
                  child: Icon(e.tema.ikon, size: 160, color: _altin.withValues(alpha: 0.14)),
                ),
                Positioned(
                  left: 20,
                  top: 18,
                  right: 20,
                  child: Text(
                    e.tema.ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: _altinParlak,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  bottom: 14,
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [_altinParlak, _altin]),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        '$deneme/${e.hak}',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: _gece, fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${e.soruSayisi} Soru',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                  ]),
                ),
                Positioned(
                  right: 14,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: StudioPalette.night.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _altin.withValues(alpha: 0.6)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.schedule_rounded, color: _altinParlak, size: 19),
                      const SizedBox(width: 5),
                      Text(
                        bitti ? 'Haklar doldu' : kalanSure(e.bitis.difference(simdi)),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ]),
                  ),
                ),
                if (enIyi != null)
                  Positioned(
                    right: 18,
                    top: 62,
                    child: Text(
                      'En iyi: $enIyi',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
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
