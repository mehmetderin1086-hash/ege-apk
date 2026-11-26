import '../common.dart';
import 'audio_english_3k.dart';
import 'interactive_studio_3k.dart';
import 'visual_studio_4k.dart';

export 'audio_english_3k.dart';
export 'interactive_studio_3k.dart';
export 'visual_studio_4k.dart';

/// Bilgili 3.20 — Yeni Nesil 10.000 Soruluk Görsel, Sesli İngilizce ve
/// Çok Biçimli Etkileşimli Soru Bankası.
///
/// Dağılım:
/// - 4.000 Yeni Nesil Görsel Stüdyo (Bayrak, Saat, Pasta Grafiği, Koordinat/Vektör, Bohr Atom, Müzik Portesi, 3×3 Matris)
/// - 3.000 Sesli İngilizce Stüdyosu (Günlük Diyalog, Kelime/Deyim, IELTS Sayı/Tarih, Sesli Dikte, Telaffuz)
/// - 3.000 Çok Biçimli Etkileşimli (Eşleştirme, Sıralama/Word Order, Çoklu Seçim, Doğru/Yanlış, Boşluk Doldurma)
final List<AdvancedFamily> studio10kFamilies = List<AdvancedFamily>.unmodifiable([
  ...visualStudio4kFamilies,
  ...audioEnglish3kFamilies,
  ...interactiveStudio3kFamilies,
]);
