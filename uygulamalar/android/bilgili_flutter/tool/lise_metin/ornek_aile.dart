// Lise metin aileleri için başvuru örneği. Uygulamaya dâhil değildir;
// yeni aile yazarken biçim ve denetim beklentilerini gösterir.
import 'package:bilgili_flutter/data/advanced/lise_metin/ortak.dart';

const _baskentler = [
  ('Türkiye', 'Ankara'), ('Fransa', 'Paris'), ('İtalya', 'Roma'),
  ('İspanya', 'Madrid'), ('Almanya', 'Berlin'), ('Yunanistan', 'Atina'),
  ('Japonya', 'Tokyo'), ('Mısır', 'Kahire'), ('Norveç', 'Oslo'),
  ('Avusturya', 'Viyana'), ('Polonya', 'Varşova'), ('Portekiz', 'Lizbon'),
  ('Macaristan', 'Budapeşte'), ('Finlandiya', 'Helsinki'), ('İrlanda', 'Dublin'),
  ('Çekya', 'Prag'), ('İsveç', 'Stokholm'), ('Danimarka', 'Kopenhag'),
  ('Hollanda', 'Amsterdam'), ('Belçika', 'Brüksel'), ('Romanya', 'Bükreş'),
  ('Bulgaristan', 'Sofya'), ('Sırbistan', 'Belgrad'), ('Hırvatistan', 'Zagreb'),
  ('Ukrayna', 'Kiev'), ('Gürcistan', 'Tiflis'), ('Azerbaycan', 'Bakü'),
  ('İran', 'Tahran'), ('Irak', 'Bağdat'), ('Suriye', 'Şam'),
  ('Ürdün', 'Amman'), ('Lübnan', 'Beyrut'), ('Tunus', 'Tunus'),
  ('Fas', 'Rabat'), ('Kenya', 'Nairobi'), ('Peru', 'Lima'),
];

final ornekAileler = <AdvancedFamily>[
  // Sayısal aile: a, b, c görünür verileri belirler; her üçlü ayrı bir
  // hesap ve ayrı bir kök üretir. Çeldiriciler tipik hatalardan gelir.
  lmAile(
    'ornek_ortalama_hiz',
    'İki etaplı yolculukta ortalama hız',
    Topic.physics,
    Difficulty.medium,
    BloomLevel.uygulama,
    (a, b, c) {
      // Ortalama m tam sayı çıksın diye hızlar m çevresinde süreyle
      // dengelenir: t1·(m − d·t2) + t2·(m + d·t1) = m·(t1 + t2).
      final m = 70 + a; // 70 … 94 km/sa
      final t1 = 1 + b % 4; // 1 … 4 saat
      final t2 = 1 + b ~/ 4; // 1 … 5 saat
      final d = c + 1; // 1 … 10
      final v1 = m - d * t2, v2 = m + d * t1; // 20 … 134 km/sa: tren için gerçekçi
      final yol = v1 * t1 + v2 * t2;
      return sayisal(
        'Bir tren yolun ilk bölümünü $t1 saat boyunca $v1 km/sa, ikinci bölümünü '
        '$t2 saat boyunca $v2 km/sa sabit hızla gidiyor. Yolculuğun tamamındaki '
        'ortalama hız kaç km/sa olur?',
        m,
        [(v1 + v2) ~/ 2, v2 - v1, yol ~/ t1],
        'Toplam yol $v1·$t1 + $v2·$t2 = $yol km, toplam süre ${t1 + t2} saattir. '
        'Ortalama hız $yol / ${t1 + t2} = $m km/sa olur.',
        unit: 'km/sa',
        positive: true,
      );
    },
    exam: ExamKind.tyt,
    lesson: 'Fizik',
  ),
  // Sözel aile: 36 ögeden üçlü seçkiler (C(36, 3) = 7.140 ≥ 5.000) kökü
  // tekleştirir; dizilim de sıra numarasına bağlıdır.
  lmSirali(
    'ornek_baskent',
    'Ülke ve başkent eşleştirmesi',
    Topic.geography,
    Difficulty.easy,
    BloomLevel.hatirlama,
    (i) {
      final uclu = kombinasyon(_baskentler, 3, i);
      final d = ucluDizilimler[i % 6];
      final x = [for (final j in d) uclu[j]];
      final dogru = x.map((e) => e.$2).join(' – ');
      return secenekli(
        'I. ${x[0].$1}\nII. ${x[1].$1}\nIII. ${x[2].$1}\n'
        'Bu ülkelerin başkentleri numara sırasıyla hangi seçenekte doğru verilmiştir?',
        dogru,
        [
          '${x[1].$2} – ${x[0].$2} – ${x[2].$2}',
          '${x[0].$2} – ${x[2].$2} – ${x[1].$2}',
          '${x[2].$2} – ${x[1].$2} – ${x[0].$2}',
        ],
        '${x.map((e) => '${e.$1}: ${e.$2}').join(', ')}.',
      );
    },
    lesson: 'Coğrafya',
  ),
];
