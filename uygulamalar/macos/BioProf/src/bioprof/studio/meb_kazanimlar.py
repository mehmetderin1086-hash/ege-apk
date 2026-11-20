"""2018 MEB Biyoloji Dersi Öğretim Programı kazanım tablosu + eşleştirici.

Elle derlenmiş statik veridir: 9-10. sınıf kazanım düzeyinde, 11-12. sınıf
ünite düzeyinde (metin alanı boş). ÖNEMLİ: kodlar resmî programdan elle
aktarıldı; ders planına girmeden önce ÖĞRETMEN DOĞRULAMALIDIR — üretilen her
planda bu uyarı kalıcıdır. Kaynak PDF'lerden kod çıkarmak güvenilmez olduğu
için (çoğu kaynakta kod hiç yoktur) gömülü tablo tercih edildi.
"""

from __future__ import annotations

from dataclasses import dataclass

from bioprof.rag.answering import _STOPWORDS, _stem


@dataclass(frozen=True)
class Kazanim:
    kod: str
    sinif: int
    unite: str
    metin: str  # 11-12'de boş: yalnız ünite düzeyi


KAZANIMLAR: tuple[Kazanim, ...] = (
    # --- 9. SINIF ---
    Kazanim("9.1.1.1", 9, "Yaşam Bilimi Biyoloji", "Canlıların ortak özelliklerini açıklar."),
    Kazanim("9.1.2.1", 9, "Yaşam Bilimi Biyoloji", "Canlıların yapısını oluşturan organik ve inorganik bileşikleri açıklar."),
    Kazanim("9.1.2.2", 9, "Yaşam Bilimi Biyoloji", "Lipit, karbonhidrat, protein, vitamin, su ve minerallerin sağlıklı beslenme ile ilişkisini kurar."),
    Kazanim("9.2.1.1", 9, "Hücre", "Hücre teorisine ilişkin çalışmaları açıklar."),
    Kazanim("9.2.1.2", 9, "Hücre", "Hücresel yapıları ve görevlerini açıklar."),
    Kazanim("9.2.1.3", 9, "Hücre", "Hücre zarından madde geçişine ilişkin kontrollü bir deney yapar."),
    Kazanim("9.3.1.1", 9, "Canlılar Dünyası", "Canlıların çeşitliliğinin anlaşılmasında sınıflandırmanın önemini açıklar."),
    Kazanim("9.3.1.2", 9, "Canlılar Dünyası", "Canlıların sınıflandırılmasında kullanılan kategorileri ve bu kategoriler arasındaki hiyerarşiyi örneklerle açıklar."),
    Kazanim("9.3.2.1", 9, "Canlılar Dünyası", "Canlı âlemlerini ve bu âlemlerin genel özelliklerini açıklar."),
    Kazanim("9.3.2.2", 9, "Canlılar Dünyası", "Canlıların biyolojik süreçlere, ekonomiye ve teknolojiye katkılarını örneklerle açıklar."),
    Kazanim("9.3.2.3", 9, "Canlılar Dünyası", "Virüslerin genel özelliklerini açıklar."),
    # --- 10. SINIF ---
    Kazanim("10.1.1.1", 10, "Hücre Bölünmeleri", "Canlılarda hücre bölünmesinin gerekliliğini açıklar."),
    Kazanim("10.1.1.2", 10, "Hücre Bölünmeleri", "Mitozu açıklar."),
    Kazanim("10.1.1.3", 10, "Hücre Bölünmeleri", "Eşeysiz üremeyi örneklerle açıklar."),
    Kazanim("10.1.2.1", 10, "Hücre Bölünmeleri", "Mayozu açıklar."),
    Kazanim("10.1.2.2", 10, "Hücre Bölünmeleri", "Eşeyli üremeyi örneklerle açıklar."),
    Kazanim("10.2.1.1", 10, "Kalıtımın Genel İlkeleri", "Kalıtımın genel esaslarını açıklar."),
    Kazanim("10.2.1.2", 10, "Kalıtımın Genel İlkeleri", "Genetik varyasyonların biyolojik çeşitliliği açıklamadaki rolünü sorgular."),
    Kazanim("10.3.1.1", 10, "Ekosistem Ekolojisi ve Güncel Çevre Sorunları", "Ekosistemin canlı ve cansız bileşenleri arasındaki ilişkiyi açıklar."),
    Kazanim("10.3.1.2", 10, "Ekosistem Ekolojisi ve Güncel Çevre Sorunları", "Canlılardaki beslenme şekillerini örneklerle açıklar."),
    Kazanim("10.3.1.3", 10, "Ekosistem Ekolojisi ve Güncel Çevre Sorunları", "Ekosistemde madde ve enerji akışını analiz eder."),
    Kazanim("10.3.2.1", 10, "Ekosistem Ekolojisi ve Güncel Çevre Sorunları", "Güncel çevre sorunlarının sebeplerini ve olası sonuçlarını değerlendirir."),
    Kazanim("10.3.2.2", 10, "Ekosistem Ekolojisi ve Güncel Çevre Sorunları", "Birey olarak çevre sorunlarının ortaya çıkmasındaki rolünü sorgular."),
    Kazanim("10.3.3.1", 10, "Ekosistem Ekolojisi ve Güncel Çevre Sorunları", "Doğal kaynakların sürdürülebilirliğinin önemini açıklar."),
    Kazanim("10.3.3.2", 10, "Ekosistem Ekolojisi ve Güncel Çevre Sorunları", "Biyolojik çeşitliliğin yaşam için önemini sorgular."),
    # --- 11. SINIF (ünite düzeyi) ---
    Kazanim("11.1", 11, "İnsan Fizyolojisi", ""),
    Kazanim("11.2", 11, "Komünite ve Popülasyon Ekolojisi", ""),
    # --- 12. SINIF (ünite düzeyi) ---
    Kazanim("12.1", 12, "Genden Proteine", ""),
    Kazanim("12.2", 12, "Canlılarda Enerji Dönüşümleri", ""),
    Kazanim("12.3", 12, "Bitki Biyolojisi", ""),
    Kazanim("12.4", 12, "Canlılar ve Çevre", ""),
)


def _icerik_govdeleri(metin: str) -> set[str]:
    return {
        _stem(kelime)
        for kelime in metin.casefold().split()
        if len(kelime) > 3 and kelime not in _STOPWORDS
    }


def kazanim_oner(
    metinler: list[str], *, sinif: int | None = None, adet: int = 3
) -> list[Kazanim]:
    """Kanıt metinleriyle en çok gövde örtüşmesi olan kazanımları önerir.

    Skor: kazanım metni + ünite adındaki içerik gövdelerinin kanıt gövdeleriyle
    kesişim oranı. Öneri her zaman ÖNERİDİR — kod seçimini öğretmen doğrular.
    """
    kanit_govdeleri: set[str] = set()
    for metin in metinler:
        kanit_govdeleri |= _icerik_govdeleri(metin)
    if not kanit_govdeleri:
        return []
    adaylar = []
    for kazanim in KAZANIMLAR:
        if sinif is not None and kazanim.sinif != sinif:
            continue
        hedef = _icerik_govdeleri(f"{kazanim.unite} {kazanim.metin}")
        if not hedef:
            continue
        kesisim = len(hedef & kanit_govdeleri)
        if kesisim == 0:
            continue
        adaylar.append((kesisim / len(hedef), -len(hedef), kazanim))
    adaylar.sort(key=lambda uc: (-uc[0], uc[1], uc[2].kod))
    return [kazanim for _, _, kazanim in adaylar[:adet]]
