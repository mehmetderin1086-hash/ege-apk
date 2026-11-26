import '../common.dart';
import 'audio_english_25k.dart';
import 'interactive_studio_25k.dart';
import 'visual_expand_25k.dart';
import 'visual_new_engines_25k.dart';

export 'audio_english_25k.dart';
export 'interactive_studio_25k.dart';
export 'visual_expand_25k.dart';
export 'visual_new_engines_25k.dart';

/// Bilgili 3.21 — 100.000 Soruluk Metin Dışı Yeni Nesil Stüdyo Bankası.
///
/// Dağılım (Toplam 100.000):
/// - 25.000 Genişletilmiş Görsel Stüdyo (Bayrak, Saat, Pasta Grafiği, Koordinat/Vektör, Bohr Atom, Müzik Portesi, 3×3 Matris)
/// - 25.000 5 Yeni Vektörel Görsel Motor (Mantık Kapıları & Elektrik Devresi, Venn Şeması, Pusula Navigasyonu, Renk & Spektrum, 2 Oktav Piyano)
/// - 25.000 Sesli İngilizce Stüdyosu (14 Senaryolu Diyalog, A2–C1 Kelime/Deyim, IELTS Sayı/İndirim, Dikte, Telaffuz)
/// - 25.000 Çok Biçimli Etkileşimli (3D Tahmin Sürgüsü, 3D Sesli İngilizce & Türkçe Harf Dizme, Mega Eşleştirme, Sıralama/Word Order, Çoklu Seçim, Doğru/Yanlış, Boşluk Doldurma)
final List<AdvancedFamily> studioVisual50kFamilies = List<AdvancedFamily>.unmodifiable([
  ...visualExpand25kFamilies,
  ...visualNewEngines25kFamilies,
]);

final List<AdvancedFamily> studio100kFamilies = List<AdvancedFamily>.unmodifiable([
  ...visualExpand25kFamilies,
  ...visualNewEngines25kFamilies,
  ...audioEnglish25kFamilies,
  ...interactiveStudio25kFamilies,
]);
