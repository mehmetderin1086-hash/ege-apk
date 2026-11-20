"""Puanlama eşikleri. Tümü öğretmen tarafından ayarlanabilir; varsayılanlar
sentetik denemelerde makul davranan muhafazakâr değerlerdir."""

from __future__ import annotations

from dataclasses import dataclass
from dataclasses import replace


@dataclass
class PuanlamaAyar:
    # Boşluk doldurma (rapidfuzz ratio, 0-100)
    bosluk_tam_esik: float = 88.0      # üstü: tam puan, otomatik
    bosluk_supheli_esik: float = 70.0  # arası: geçici tam puan + incele bayrağı
    bosluk_ret_esik: float = 55.0      # arası: 0 puan + incele; altı: 0 puan
    # Çok boşluklu sorularda tek bir parçanın doğru sayılması için gereken skor
    bosluk_kismi_esik: float = 80.0
    # Öğrenilmiş kabul yazımı önerisi için gereken asgari tekrar sayısı
    bosluk_ogrenilmis_asgari_destek: int = 2

    # Rubrik kalemi — sözcüksel eşleşme (rapidfuzz partial_ratio, 0-100)
    rubrik_sozcuksel_esik: float = 82.0
    # Sonuç tam yazılmasa da doğru kavram/yöntem izine kısmi puan verilir.
    rubrik_kismi_sozcuksel_esik: float = 55.0
    rubrik_kismi_kapsama_esigi: float = 0.38
    rubrik_azami_kismi_oran: float = 0.80
    # Rubrik kalemi — anlamsal eşleşme (kosinüs, 0-1)
    rubrik_anlamsal_esik: float = 0.60
    rubrik_kismi_anlamsal_esik: float = 0.42
    # Anlamsal katmanın rolü: "kurtarma" (varsayılan) ya da "tam".
    #
    # ÖLÇÜLDÜ (13 biyoloji çifti): eşdeğer cevaplar 0.26-0.69, FARKLI kavramlar
    # 0.17-0.69 bandında — iki dağılım örtüşüyor, hiçbir tek eşik ayırmıyor.
    # "Mayoz çeşitlilik sağlar" ↔ "mitoz kromozom sayısını korur" = 0.692,
    # yani 0.60 eşiğiyle YANLIŞ cevap tam puan alırdı. Olumsuzluk da görünmez
    # ("ATP üretir" ↔ "ATP üretmez" = 0.646). turkish-e5-large daha da kötü.
    #
    # Bu yüzden anlamsal katman varsayılan olarak yalnız KURTARMA yapar:
    # kısmi puan tabanı, kitap örtüşmesiyle haksız sıfırı önleme, akran
    # kümeleme. Tam puan kararı sözcüksel kanıt olmadan verilmez.
    anlamsal_rol: str = "kurtarma"
    # "tam" rolünde bile bu eşiğin altında anlamsal tam puan verilmez.
    rubrik_anlamsal_tam_esik: float = 0.75
    # Anlamsal tam puan için gereken asgari sözcüksel destek payı: cevap
    # kalemle hiç kelime paylaşmıyorsa benzerlik yanıltıcıdır.
    anlamsal_tam_sozcuksel_pay: float = 20.0

    # Yapısal puanlayıcılar (sıralama/eşleştirme/sayısal) — profil bunları da
    # etkiler; modül sabitleri varsayılan olarak korunur.
    siralama_konum_esigi: float = 84.0
    siralama_lcs_esigi: float = 82.0
    eslestirme_sol_esigi: float = 80.0
    eslestirme_sag_esigi: float = 84.0
    sayisal_tolerans_carpani: float = 1.0

    # Kararsızlık bandı: eşiğe bu kadar yakın kararlar güveni düşürür
    sozcuksel_band: float = 10.0
    anlamsal_band: float = 0.08

    # Bu güvenin altındaki sonuçlar insan onayına düşer
    incele_guven_esigi: float = 0.65
    # HTR tanıma güveni bunun altındaysa her durumda incele
    tanima_guven_esigi: float = 0.75
    # Soru puanının bu kadarı kararsız kalemlerdeyse incele. Kuyruğun asıl
    # sinyali budur: 1 puanlık kararsız kalem 9 puanlık kesin kalemi
    # kuyruğa sürüklemez, ama puanın çoğu kararsızsa öğretmen görür.
    kararsiz_puan_payi_esigi: float = 0.25
    # Anlamsal katman yokken rubrik yolundaki güven tavanı. incele_guven_esigi
    # ÜSTÜNDE olmalı; altında kalırsa her cevap kuyruğa düşer.
    gomlemcisiz_rubrik_tavani: float = 0.70

    def profil(self, ad: str) -> "PuanlamaAyar":
        """Öğretmenin katı/dengeli/esnek tercihini tutarlı eşiklere dönüştür.

        Arayüz bunu genel bir "Puanlama esnekliği" ayarı olarak sunuyor;
        bu yüzden yalnız rubriği değil boşluk ve yapısal eşikleri de
        değiştirmeli. (Eskiden yalnız rubriğe uygulanıyordu: boşluk
        sorularında katı/dengeli/esnek üçü de aynı puanı veriyordu.)
        """
        ad = str(ad or "dengeli").casefold()
        if ad == "kati" or ad == "katı":
            return replace(
                self,
                rubrik_sozcuksel_esik=88.0,
                rubrik_kismi_sozcuksel_esik=65.0,
                rubrik_kismi_kapsama_esigi=0.50,
                rubrik_azami_kismi_oran=0.65,
                rubrik_anlamsal_esik=0.68,
                rubrik_kismi_anlamsal_esik=0.50,
                bosluk_tam_esik=92.0,
                bosluk_supheli_esik=82.0,
                bosluk_ret_esik=62.0,
                bosluk_kismi_esik=86.0,
                siralama_konum_esigi=90.0,
                siralama_lcs_esigi=88.0,
                eslestirme_sol_esigi=88.0,
                eslestirme_sag_esigi=90.0,
            )
        if ad == "esnek":
            return replace(
                self,
                rubrik_sozcuksel_esik=76.0,
                rubrik_kismi_sozcuksel_esik=45.0,
                rubrik_kismi_kapsama_esigi=0.25,
                rubrik_azami_kismi_oran=0.90,
                rubrik_anlamsal_esik=0.55,
                rubrik_kismi_anlamsal_esik=0.36,
                bosluk_tam_esik=84.0,
                bosluk_supheli_esik=66.0,
                bosluk_ret_esik=50.0,
                bosluk_kismi_esik=74.0,
                siralama_konum_esigi=80.0,
                siralama_lcs_esigi=78.0,
                eslestirme_sol_esigi=74.0,
                eslestirme_sag_esigi=78.0,
                sayisal_tolerans_carpani=1.5,
            )
        return replace(self)
