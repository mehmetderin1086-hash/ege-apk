// Lise düzeyinde, yalnız metinden oluşan 400 aile. Her aile 5.000 ayrı vaka
// üretir; toplam 2.000.000 soru. İlk 200 aile 3.9.0 sürümünde, sonraki 200
// aile 3.10.0 sürümünde eklendi. Yazım ve denetim kuralları
// tool/lise_metin/YAZIM_KILAVUZU.md dosyasındadır.
import 'common.dart';
import 'lise_metin/analiz.dart';
import 'lise_metin/bilisim.dart';
import 'lise_metin/biyoloji.dart';
import 'lise_metin/biyoloji_ek.dart';
import 'lise_metin/cografya_ek.dart';
import 'lise_metin/cografya_tarih.dart';
import 'lise_metin/dil.dart';
import 'lise_metin/dil_ek.dart';
import 'lise_metin/fizik_ek.dart';
import 'lise_metin/fizik_elektrik.dart';
import 'lise_metin/fizik_mekanik.dart';
import 'lise_metin/geometri.dart';
import 'lise_metin/geometri_ek.dart';
import 'lise_metin/kimya.dart';
import 'lise_metin/kimya_ek.dart';
import 'lise_metin/mat_ileri.dart';
import 'lise_metin/mat_temel.dart';
import 'lise_metin/sayilar.dart';
import 'lise_metin/tarih_felsefe.dart';
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
  ...lmSayilar,
  ...lmAnaliz,
  ...lmGeometriEk,
  ...lmBilisim,
  ...lmFizikEk,
  ...lmKimyaEk,
  ...lmBiyolojiEk,
  ...lmCografyaEk,
  ...lmTarihFelsefe,
  ...lmDilEk,
];
