import 'dart:math';

import 'package:flutter/material.dart';

import '../models/quiz_models.dart';

/// Özel oda ayarları. Altı haneli oda numarası ayarları ve soru tohumunu
/// taşır: aynı numarayı giren herkes aynı soruları aynı sırayla çözer.
class OdaAyari {
  static const soruSecenekleri = [7, 14, 21];
  static const sureSecenekleri = [20, 40];
  static List<Topic> get kategoriler => [Topic.mixed, ...Topic.poolCategories];

  final Topic kategori;
  final int soruSayisi;
  final int sure;
  final int tohum;

  const OdaAyari({
    this.kategori = Topic.mixed,
    this.soruSayisi = 7,
    this.sure = 20,
    required this.tohum,
  });

  static const _kategoriTaban = 32;
  static const _ust = 1000000;

  factory OdaAyari.yeni({Topic kategori = Topic.mixed, int soruSayisi = 7, int sure = 20, Random? rng}) {
    final r = rng ?? Random();
    final enCok = _ust ~/ (_kategoriTaban * soruSecenekleri.length * sureSecenekleri.length);
    return OdaAyari(kategori: kategori, soruSayisi: soruSayisi, sure: sure, tohum: r.nextInt(enCok));
  }

  OdaAyari copyWith({Topic? kategori, int? soruSayisi, int? sure}) => OdaAyari(
        kategori: kategori ?? this.kategori,
        soruSayisi: soruSayisi ?? this.soruSayisi,
        sure: sure ?? this.sure,
        tohum: tohum,
      );

  /// Altı haneli oda numarası.
  String get kod {
    final k = kategoriler.indexOf(kategori);
    final s = soruSecenekleri.indexOf(soruSayisi);
    final t = sureSecenekleri.indexOf(sure);
    final n = ((tohum * sureSecenekleri.length + t) * soruSecenekleri.length + s) * _kategoriTaban + k;
    // Hanelerin her odada farklı görünmesi için sabit bir permütasyon uygulanır.
    final karisik = (n * 7919 + 104729) % _ust;
    return karisik.toString().padLeft(6, '0');
  }

  /// Oda numarasını çözer; geçersizse null döner.
  static OdaAyari? coz(String girdi) {
    final temiz = girdi.replaceAll(RegExp(r'\D'), '');
    if (temiz.length != 6) return null;
    final karisik = int.parse(temiz);
    // 7919'un 10^6 modundaki tersi.
    const ters = 17679;
    var n = ((karisik - 104729) % _ust + _ust) % _ust;
    n = (n * ters) % _ust;
    final k = n % _kategoriTaban;
    n ~/= _kategoriTaban;
    final s = n % soruSecenekleri.length;
    n ~/= soruSecenekleri.length;
    final t = n % sureSecenekleri.length;
    final tohum = n ~/ sureSecenekleri.length;
    if (k >= kategoriler.length) return null;
    return OdaAyari(
      kategori: kategoriler[k],
      soruSayisi: soruSecenekleri[s],
      sure: sureSecenekleri[t],
      tohum: tohum,
    );
  }
}

/// Rakip adları: Bire Bir ve Çoklu modlarda bilgisayar rakipleri.
const rakipAdlari = [
  'Ada', 'Deniz', 'Kerem', 'Elif', 'Mert', 'Zeynep', 'Arda', 'Defne', 'Emir', 'Ece',
  'Bora', 'Nehir', 'Kaan', 'Lina', 'Efe', 'Duru', 'Can', 'Asya', 'Umut', 'Yağmur',
];

/// Süreli bir etkinlik: belli bir konuda sabit sayıda soru, sınırlı deneme.
class EtkinlikTemasi {
  final String ad;
  final Topic konu;
  final IconData ikon;
  final List<Color> renkler;
  const EtkinlikTemasi(this.ad, this.konu, this.ikon, this.renkler);
}

const etkinlikTemalari = [
  EtkinlikTemasi('Batı Klasikleri', Topic.literature, Icons.menu_book_rounded, [Color(0xFF8A5A2B), Color(0xFF3B2412)]),
  EtkinlikTemasi('Denizler ve Okyanuslar', Topic.geography, Icons.sailing_rounded, [Color(0xFF1C7FA6), Color(0xFF0B3550)]),
  EtkinlikTemasi('Sağlıklı Yaşam', Topic.biology, Icons.favorite_rounded, [Color(0xFF2FB9C9), Color(0xFF0E5D78)]),
  EtkinlikTemasi('Dünya Mutfakları', Topic.culture, Icons.restaurant_rounded, [Color(0xFF9C6B3C), Color(0xFF4A2E17)]),
  EtkinlikTemasi('Hafta Sonu Karması', Topic.mixed, Icons.forest_rounded, [Color(0xFF3FA36B), Color(0xFF1E5A3A)]),
  EtkinlikTemasi('Uzay Yolculuğu', Topic.science, Icons.rocket_launch_rounded, [Color(0xFF3B3F9E), Color(0xFF14163F)]),
  EtkinlikTemasi('Osmanlı Dönemi', Topic.history, Icons.account_balance_rounded, [Color(0xFFB5822F), Color(0xFF4D3410)]),
  EtkinlikTemasi('Sayıların Dünyası', Topic.mathematics, Icons.calculate_rounded, [Color(0xFF6E4FE6), Color(0xFF2A1478)]),
  EtkinlikTemasi('Beyaz Perde', Topic.cinema, Icons.movie_rounded, [Color(0xFFB0303F), Color(0xFF4A1018)]),
  EtkinlikTemasi('Notalar', Topic.music, Icons.music_note_rounded, [Color(0xFFD0508A), Color(0xFF5B1A3B)]),
  EtkinlikTemasi('Tuvaldeki Renkler', Topic.art, Icons.palette_rounded, [Color(0xFFE07A3A), Color(0xFF6B2E0E)]),
  EtkinlikTemasi('Saha Kenarı', Topic.sport, Icons.sports_soccer_rounded, [Color(0xFF2E9E4F), Color(0xFF104A22)]),
  EtkinlikTemasi('Teknoloji Çağı', Topic.technology, Icons.memory_rounded, [Color(0xFF3A6FD8), Color(0xFF13285A)]),
  EtkinlikTemasi('Doğanın Sırları', Topic.nature, Icons.eco_rounded, [Color(0xFF5BAA3A), Color(0xFF244716)]),
  EtkinlikTemasi('Kimya Laboratuvarı', Topic.chemistry, Icons.science_rounded, [Color(0xFF2BA39A), Color(0xFF0D4743)]),
  EtkinlikTemasi('Kuvvet ve Hareket', Topic.physics, Icons.bolt_rounded, [Color(0xFF5560D6), Color(0xFF1E2266)]),
  EtkinlikTemasi('Kelime Avı', Topic.language, Icons.translate_rounded, [Color(0xFFC2459C), Color(0xFF4F1640)]),
  EtkinlikTemasi('Ekonominin Dili', Topic.economics, Icons.trending_up_rounded, [Color(0xFF2F8F6F), Color(0xFF0F3D2E)]),
  EtkinlikTemasi('Mühendis Kafası', Topic.engineering, Icons.precision_manufacturing_rounded, [Color(0xFF7A6A58), Color(0xFF2E261D)]),
  EtkinlikTemasi('Kod ve Algoritma', Topic.computing, Icons.code_rounded, [Color(0xFF3D4A66), Color(0xFF151B29)]),
  EtkinlikTemasi('Veri Dedektifi', Topic.statistics, Icons.insights_rounded, [Color(0xFF8E5AD6), Color(0xFF33175E)]),
  EtkinlikTemasi('İnsan ve Toplum', Topic.socialScience, Icons.groups_rounded, [Color(0xFFCF7F3E), Color(0xFF5A3013)]),
  EtkinlikTemasi('Sınav Provası', Topic.exam, Icons.edit_note_rounded, [Color(0xFF4058C8), Color(0xFF141F55)]),
  EtkinlikTemasi('Kaynak Avcısı', Topic.research, Icons.travel_explore_rounded, [Color(0xFF5F7F99), Color(0xFF1F3040)]),
];

/// Takvimde yer alan bir etkinlik örneği.
class Etkinlik {
  final EtkinlikTemasi tema;
  final DateTime baslangic;
  final DateTime bitis;
  final int soruSayisi;
  final int hak;
  const Etkinlik(this.tema, this.baslangic, this.bitis, this.soruSayisi, this.hak);

  String get anahtar => '${tema.ad}|${baslangic.toIso8601String().substring(0, 10)}';
  int get tohum => anahtar.codeUnits.fold<int>(23, (a, c) => (a * 31 + c) & 0x3fffffff);
  bool aktif(DateTime simdi) => !simdi.isBefore(baslangic) && simdi.isBefore(bitis);
}

/// Etkinlik takvimi: her gün bir etkinlik başlar, süresi 1–3 gün arasıdır.
/// Takvim tarihe bağlı olarak hesaplanır, internet gerektirmez.
class EtkinlikTakvimi {
  static final _epoch = DateTime(2026, 1, 1);

  static Etkinlik _gunun(int gun) {
    final tema = etkinlikTemalari[(gun * 7) % etkinlikTemalari.length];
    final sure = 1 + (gun * 5 + 3) % 3; // 1, 2 ya da 3 gün
    final bas = _epoch.add(Duration(days: gun));
    final hafta = bas.weekday >= DateTime.saturday;
    final soru = hafta ? 50 : (sure == 3 ? 20 : 30);
    return Etkinlik(tema, bas, bas.add(Duration(days: sure)), soru, hafta ? 5 : (sure == 3 ? 2 : 3));
  }

  static int _gunNo(DateTime t) => DateTime(t.year, t.month, t.day).difference(_epoch).inDays;

  static List<Etkinlik> guncel(DateTime simdi) {
    final bugun = _gunNo(simdi);
    final list = [for (var g = bugun - 2; g <= bugun; g++) _gunun(g)]
        .where((e) => e.aktif(simdi))
        .toList()
      ..sort((a, b) => b.bitis.compareTo(a.bitis));
    return list;
  }

  static List<Etkinlik> gelecek(DateTime simdi, {int adet = 3}) =>
      [for (var g = _gunNo(simdi) + 1; g <= _gunNo(simdi) + adet; g++) _gunun(g)];
}

String kalanSure(Duration d) {
  if (d.isNegative) return 'bitti';
  if (d.inDays >= 1) return '${d.inDays} gün ${d.inHours % 24} sa';
  if (d.inHours >= 1) return '${d.inHours} sa ${d.inMinutes % 60} dk';
  return '${max(1, d.inMinutes)} dk';
}
