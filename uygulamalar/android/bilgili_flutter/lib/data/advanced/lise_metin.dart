// Lise düzeyinde, yalnız metinden oluşan 200 aile. Her aile 5.000 ayrı vaka
// üretir; toplam 1.000.000 soru. Yazım ve denetim kuralları
// tool/lise_metin/YAZIM_KILAVUZU.md dosyasındadır.
import 'common.dart';
import 'lise_metin/biyoloji.dart';
import 'lise_metin/cografya_tarih.dart';
import 'lise_metin/dil.dart';
import 'lise_metin/fizik_elektrik.dart';
import 'lise_metin/fizik_mekanik.dart';
import 'lise_metin/geometri.dart';
import 'lise_metin/kimya.dart';
import 'lise_metin/mat_ileri.dart';
import 'lise_metin/mat_temel.dart';
import 'lise_metin/veri_olasilik.dart';

final liseMetinFamilies = <AdvancedFamily>[
  ...lmMatTemel,
  ...lmMatIleri,
  ...lmGeometri,
  ...lmVeriOlasilik,
  ...lmFizikMekanik,
  ...lmFizikElektrik,
  ...lmKimya,
  ...lmBiyoloji,
  ...lmCografyaTarih,
  ...lmDil,
];
