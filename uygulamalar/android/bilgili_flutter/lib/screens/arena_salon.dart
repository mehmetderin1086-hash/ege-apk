import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/quiz_models.dart';
import '../services/native_bridge.dart';
import '../state/arena_controller.dart';
import '../state/arena_rooms.dart';

const _yesil = Color(0xFF8DD14F);
const _koyu = Color(0xFF1B1F2E);

/// Salon ekranlarının ortak zemini: temanın geçişi, yoksa koyu düz renk.
class _Zemin extends StatelessWidget {
  final ArenaController ctrl;
  final Widget child;
  const _Zemin({required this.ctrl, required this.child});

  @override
  Widget build(BuildContext context) {
    final wp = ctrl.currentWallpaper;
    final renkler = wp.gradient ?? [Color.lerp(wp.surface, wp.primary, .18)!, wp.ink];
    return Scaffold(
      backgroundColor: wp.ink,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomCenter, colors: renkler)),
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
        child: InkResponse(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF7B3FF0), Color(0xFF4B12B8)]),
              border: Border.all(color: Colors.white.withValues(alpha: .25), width: 2),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Icon(ikon, color: Colors.white, size: 30),
          ),
        ),
      );
}

void _salonuKapat(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

void _yardim(BuildContext context, String baslik, String metin) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(baslik),
      content: Text(metin),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Align(alignment: Alignment.centerLeft, child: _GeriDugmesi()),
          const SizedBox(height: 20),
          _ModKarti(
            renk: const Color(0xFF1E5BE6),
            baslik: 'Bire Bir',
            aciklama: 'Bir rakiple aynı sorulara karşı yarış, puanı yüksek olan kazansın.',
            ikon: Icons.sports_kabaddi_rounded,
            egim: -1,
            onTap: () => _rakipKur(context, 1),
          ),
          const SizedBox(height: 14),
          _ModKarti(
            renk: const Color(0xFFF39A12),
            baslik: 'Çoklu',
            aciklama: 'Dört rakiple 5 kişilik odada oyna, sıralamada zirveye çık.',
            ikon: Icons.groups_rounded,
            egim: 1,
            onTap: () => _rakipKur(context, 4),
          ),
          const SizedBox(height: 14),
          _ModKarti(
            renk: const Color(0xFF12C25A),
            baslik: 'Özel Oda',
            aciklama: 'Ayarları seç, oda numarasını paylaş; 10 kişiye kadar birlikte oyna.',
            ikon: Icons.meeting_room_rounded,
            egim: -1,
            yardim: () => _yardim(context, 'Özel Oda',
                'Oda numarası kategoriyi, soru sayısını, süreyi ve soruları taşır. Aynı numarayı kendi telefonuna giren arkadaşların aynı soruları aynı sırayla çözer; puanlarınızı karşılaştırabilirsiniz.\n\n'
                'Odaya birden çok oyuncu eklerseniz aynı telefonda sırayla oynarsınız: her oyuncu kendi sorularını cevaplar ve sonda kürsü gösterilir.'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OzelOdaScreen(controller: controller, oda: OdaAyari.yeni()))),
          ),
          const SizedBox(height: 26),
          _OdaNoGir(controller: controller),
        ],
      ),
    );
  }

  Future<void> _rakipKur(BuildContext context, int rakipSayisi) async {
    var kategori = Topic.mixed;
    var soru = 7;
    var sure = 20;
    final basla = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF2A1478),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rakipSayisi == 1 ? 'Bire Bir' : 'Çoklu Oda',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 16),
              _KategoriSecici(secili: kategori, onSec: (t) => yenile(() => kategori = t)),
              const SizedBox(height: 16),
              _AyarSatiri(soru: soru, sure: sure, onSoru: (v) => yenile(() => soru = v), onSure: (v) => yenile(() => sure = v)),
              const SizedBox(height: 20),
              _BuyukDugme(metin: rakipSayisi == 1 ? 'Rakip Bul' : 'Odaya Katıl', onTap: () => Navigator.pop(c, true)),
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
    controller.startRakipMaci(rakipler: rakipler, topic: kategori, soru: soru, sure: sure);
  }
}

class _ModKarti extends StatelessWidget {
  final Color renk;
  final String baslik;
  final String aciklama;
  final IconData ikon;
  final int egim;
  final VoidCallback onTap;
  final VoidCallback? yardim;
  const _ModKarti({
    required this.renk,
    required this.baslik,
    required this.aciklama,
    required this.ikon,
    required this.egim,
    required this.onTap,
    this.yardim,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$baslik. $aciklama',
      child: GestureDetector(
        onTap: onTap,
        child: ClipPath(
          clipper: _EgikKenar(egim),
          child: Container(
            constraints: const BoxConstraints(minHeight: 168),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [renk, Color.lerp(renk, Colors.black, .18)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            padding: const EdgeInsets.fromLTRB(22, 34, 14, 34),
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
                        child: Text(baslik, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                      const SizedBox(height: 6),
                      Text(aciklama, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3)),
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
                        icon: const Icon(Icons.help_rounded, color: Colors.white70, size: 28),
                      ),
                    Icon(ikon, size: yardim != null ? 60 : 76, color: Colors.white),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EgikKenar extends CustomClipper<Path> {
  final int egim;
  const _EgikKenar(this.egim);
  @override
  Path getClip(Size s) {
    const r = 28.0;
    const d = 22.0;
    final ust = egim < 0 ? 0.0 : d;
    final alt = egim < 0 ? s.height - d : s.height;
    return Path()
      ..moveTo(r, egim < 0 ? 0 : d)
      ..lineTo(s.width - r, egim < 0 ? 0 : 0)
      ..quadraticBezierTo(s.width, 0, s.width, r)
      ..lineTo(s.width, alt - r)
      ..quadraticBezierTo(s.width, alt, s.width - r, alt)
      ..lineTo(r, s.height)
      ..quadraticBezierTo(0, s.height, 0, s.height - r)
      ..lineTo(0, ust + r)
      ..quadraticBezierTo(0, ust, r, ust)
      ..close();
  }

  @override
  bool shouldReclip(covariant _EgikKenar old) => old.egim != egim;
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
      backgroundColor: const Color(0xFF2A1478),
      title: Text(_gelen >= widget.rakipler.length ? 'Hazır!' : 'Rakip aranıyor…', style: const TextStyle(color: Colors.white)),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          const _Avatar(ad: 'Sen', renk: Color(0xFFFF6A13)),
          for (var i = 0; i < widget.rakipler.length; i++)
            i < _gelen
                ? _Avatar(ad: widget.rakipler[i], renk: _avatarRengi(i + 1))
                : const SizedBox(width: 64, height: 86, child: Center(child: CircularProgressIndicator(color: _yesil))),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç'))],
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
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: () => _sor(context),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          decoration: BoxDecoration(
            color: const Color(0xFF12C25A),
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: const Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Oda No Gir', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
              Spacer(),
              Text('_ _ _ _ _ _', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
            ],
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
        title: const Text('Oda numarası'),
        content: TextField(
          controller: kontrol,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(hintText: '000000', counterText: ''),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, kontrol.text), child: const Text('Katıl')),
        ],
      ),
    );
    if (kod == null || !context.mounted) return;
    final oda = OdaAyari.coz(kod);
    if (oda == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu oda numarası geçerli değil. Altı haneyi kontrol et.')));
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            const _GeriDugmesi(),
            const Spacer(),
            const Text('Kategori', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            const SizedBox(width: 48),
          ]),
          const SizedBox(height: 10),
          _KategoriSecici(secili: _oda.kategori, onSec: (t) => setState(() => _oda = _oda.copyWith(kategori: t))),
          const SizedBox(height: 22),
          _AyarSatiri(
            soru: _oda.soruSayisi,
            sure: _oda.sure,
            onSoru: (v) => setState(() => _oda = _oda.copyWith(soruSayisi: v)),
            onSure: (v) => setState(() => _oda = _oda.copyWith(sure: v)),
          ),
          const SizedBox(height: 26),
          const Center(child: Text('Oda Numarası', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
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
          const SizedBox(height: 22),
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
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          _BuyukDugme(metin: 'Oyunu Başlat', onTap: _baslat),
        ],
      ),
    );
  }

  Future<String?> _adSor(String baslik, String ilk) async {
    final k = TextEditingController(text: ilk);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(baslik),
        content: TextField(
          controller: k,
          autofocus: true,
          maxLength: 16,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, k.text), child: const Text('Tamam')),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu kategoride yeterli soru bulunamadı.')));
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
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 18),
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 46),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Semantics(
            label: 'Oda numarası ${kod.split('').join(' ')}',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final h in kod.split(''))
                  Flexible(
                    child: Column(children: [
                      Text(h, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
                      Container(width: 30, height: 2, color: Colors.white),
                    ]),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -24,
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
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF2A0E86),
        shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 2)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Row(children: [
              Text(metin, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(width: 8),
              Icon(ikon, color: Colors.white, size: 22),
            ]),
          ),
        ),
      );
}

Color _avatarRengi(int i) => const [
      Color(0xFFFF6A13), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFE53935), Color(0xFF8E24AA),
      Color(0xFF00ACC1), Color(0xFFFDD835), Color(0xFF6D4C41), Color(0xFFD81B60), Color(0xFF3949AB),
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
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: renk,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF555555), width: 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(ad.isEmpty ? '?' : ad.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                if (sira != null)
                  Positioned(
                    bottom: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFF555555), borderRadius: BorderRadius.circular(8)),
                      child: Text('$sira', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
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
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF6243D8).withValues(alpha: .7), const Color(0xFF2A1478).withValues(alpha: .6)],
        ),
      ),
      child: Column(
        children: [
          Row(children: [
            const Spacer(),
            const Text('Oyuncular', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            Text('${oyuncular.length}/10', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
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
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white54, width: 2),
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: () async {
          final t = await showModalBottomSheet<Topic>(
            context: context,
            backgroundColor: const Color(0xFF2A1478),
            isScrollControlled: true,
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
                        trailing: k == secili ? const Icon(Icons.check_rounded, color: _yesil) : null,
                        onTap: () => Navigator.pop(c, k),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (t != null) onSec(t);
        },
        child: Container(
          height: 72,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40)),
          child: Row(
            children: [
              Container(
                width: 104,
                height: 72,
                decoration: BoxDecoration(
                  color: secili == Topic.mixed ? _koyu : secili.accent,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Icon(secili == Topic.mixed ? Icons.shuffle_rounded : secili.icon, color: Colors.white, size: 40),
              ),
              Expanded(
                child: Text(secili.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: secili == Topic.mixed ? _koyu : Color.lerp(secili.accent, Colors.black, .25))),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 20),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: _koyu, size: 32),
              ),
            ],
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
            const Text('Soru Sayısı', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 10),
            _Segment(degerler: OdaAyari.soruSecenekleri, secili: soru, etiket: (v) => '$v', onSec: onSoru),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: Column(children: [
            const Text('Süre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 10),
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
      height: 50,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
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
                      color: v == secili ? _koyu : Colors.transparent,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: FittedBox(
                      child: Text(etiket(v),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: v == secili ? Colors.white : _koyu)),
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

class _BuyukDugme extends StatelessWidget {
  final String metin;
  final VoidCallback onTap;
  const _BuyukDugme({required this.metin, required this.onTap});
  @override
  Widget build(BuildContext context) => Center(
        child: Material(
          color: const Color(0xFF12C25A),
          shape: const StadiumBorder(),
          elevation: 6,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              child: Text(metin, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
        ),
      );
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Row(children: [
            const _GeriDugmesi(),
            const Expanded(
              child: Text('Etkinlikler',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
            _Yuvarlak(
              ikon: Icons.question_mark_rounded,
              anlam: 'Etkinlikler nasıl çalışır?',
              onTap: () => _yardim(context, 'Etkinlikler',
                  'Her gün yeni bir konu etkinliği başlar ve 1–3 gün sürer. Her etkinliğin sabit bir soru sayısı ve sınırlı deneme hakkı vardır; en yüksek puanın kaydedilir.\n\n'
                  'Hafta sonu etkinlikleri 50 soru ve 5 hak sunar. "Gelecek" bölümünde yakında başlayacak etkinlikleri görebilirsin.'),
            ),
          ]),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text('Gelecek', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 172,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in gelecek)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: 116,
                      child: Column(children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: e.tema.renkler),
                            border: Border.all(color: _yesil, width: 3),
                          ),
                          child: Icon(e.tema.ikon, color: Colors.white, size: 46),
                        ),
                        const SizedBox(height: 6),
                        Text(e.tema.ad, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        Text('${kalanSure(e.baslangic.difference(simdi))} sonra',
                            style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              color: Colors.white.withValues(alpha: .07),
            ),
            child: Column(
              children: [
                Row(children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Text('Güncel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text('${simdi.day} ${_aylar[simdi.month - 1]}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
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
                  const SizedBox(height: 16),
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
        title: Text(e.tema.ad),
        content: Text(
          '${e.tema.konu.label} konusunda ${e.soruSayisi} soru, soru başına 20 saniye.\n'
          'Kalan deneme hakkı: $kalan / ${e.hak}'
          '${enIyi != null ? '\nEn iyi puanın: $enIyi' : ''}\n'
          'Bitişe ${kalanSure(e.bitis.difference(DateTime.now()))} var.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Kapat')),
          if (kalan > 0) FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Başla')),
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 190,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            gradient: LinearGradient(colors: e.tema.renkler, begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 5))],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                bottom: -18,
                child: Icon(e.tema.ikon, size: 190, color: Colors.white.withValues(alpha: .16)),
              ),
              Positioned(
                left: 22,
                top: 22,
                right: 22,
                child: Text(e.tema.ad,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white,
                        shadows: [Shadow(color: Colors.black45, blurRadius: 6)])),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: Row(children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFBDBDBD), width: 3),
                    ),
                    child: Text('$deneme/${e.hak}',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF4B12B8), fontSize: 16)),
                  ),
                  const SizedBox(width: 10),
                  Text('${e.soruSayisi} Soru',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white,
                          shadows: [Shadow(color: Colors.black45, blurRadius: 6)])),
                ]),
              ),
              Positioned(
                right: 14,
                bottom: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xCC1B1F2E), borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, color: Color(0xFFFF9A2E), size: 22),
                    const SizedBox(width: 6),
                    Text(bitti ? 'Haklar doldu' : kalanSure(e.bitis.difference(simdi)),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                  ]),
                ),
              ),
              if (enIyi != null)
                Positioned(
                  right: 18,
                  top: 72,
                  child: Text('En iyi: $enIyi',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800,
                          shadows: [Shadow(color: Colors.black45, blurRadius: 6)])),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
