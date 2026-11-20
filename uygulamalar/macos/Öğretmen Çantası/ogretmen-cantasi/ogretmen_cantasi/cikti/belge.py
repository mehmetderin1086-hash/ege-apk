"""Yazdırılabilir belgelerin HTML gövdelerini üretir.

Aynı gövde iki yere gider: tarayıcıda "yazdır" önizlemesine ve PyMuPDF ile
üretilen PDF dosyasına. Tek kaynak olması, ekranda görüp onayladığın planla
teslim ettiğin PDF'in ayrışmamasını sağlıyor.
"""

from __future__ import annotations

from html import escape

from ..notlar import TUR_ADLARI, OgrenciKarnesi
from ..plan.gunluk import GunlukPlan
from ..plan.yillik import TUR_TATIL, PlanSatiri
from ..sinav import Sinav
from ..takvim import AY_ADLARI

# Tablo sütunlarına genişlik VERİLMEZ. PyMuPDF Story yüzde genişliği hiç
# uygulamıyor (sütunu şerit gibi daraltıp metni sayfanın soluna taşırıyordu),
# punto genişliği ise tabloyu yazım alanının dışına itiyor. Genişlik
# verilmediğinde Story tabloyu yazım alanına yayıp sütunları içeriğe göre
# paylaştırıyor; dokuz sütunlu yıllık plan dahil hepsi düzgün çıkıyor
# (sayfa görüntüsü alınarak doğrulandı).


def _liste(ogeler: list[str], ayirici: str = ", ") -> str:
    return escape(ayirici.join(o for o in ogeler if o))


def _tarih_araligi(baslangic: str, bitis: str) -> str:
    try:
        _, ay, gun = baslangic.split("-")
        yil2, ay2, gun2 = bitis.split("-")
    except ValueError:
        return escape(f"{baslangic} – {bitis}")
    if ay == ay2:
        return f"{int(gun)}–{int(gun2)} {AY_ADLARI[int(ay) - 1]}"
    return f"{int(gun)} {AY_ADLARI[int(ay) - 1]} – {int(gun2)} {AY_ADLARI[int(ay2) - 1]} {yil2}"


def _ustbilgi(baslik: str, altbilgi: str = "") -> str:
    parcalar = [f"<h1>{escape(baslik)}</h1>"]
    if altbilgi:
        parcalar.append(f'<p class="orta kucuk">{escape(altbilgi)}</p>')
    return "".join(parcalar)


def _imza_blogu(ogretmen: str, mudur: str = "") -> str:
    return (
        '<table class="imza"><tr>'
        f'<td class="orta">{escape(ogretmen)}<br/>Biyoloji Öğretmeni</td>'
        f'<td class="orta">{escape(mudur or "…………………")}<br/>Okul Müdürü</td>'
        "</tr></table>"
    )


# --- ünitelendirilmiş yıllık plan (klasik MEB biçimi) --------------------

# Genişlikler İÇERİK genişliğidir: Story her hücreye ayrıca dolgu (7pt) ve
# kenarlık (2pt) ekliyor, yani 9 sütunlu tabloda ~81pt fazladan yer gidiyor.
# Toplam bu payla birlikte yatay A4'ün yazım alanına (782pt) sığar.
MEB_SUTUNLARI = (
    "Ay",
    "Hafta",
    "Saat",
    "Tema / Öğrenme Çıktısı",
    "Süreç Bileşenleri",
    "Yöntem ve Teknikler",
    "Araç-Gereç",
    "Ölçme ve Değerlendirme",
    "Diğer Derslerle İlişkilendirme",
    "Belirli Gün ve Haftalar",
    "Açıklama",
)


def yillik_plan_meb(
    satirlar: list[PlanSatiri],
    *,
    okul: str,
    sube_adi: str,
    ogretim_yili: str,
    ogretmen: str,
    ders: str = "Biyoloji",
    genel_toplam: int | None = None,
    imza_goster: bool = True,
    sayfa_no: tuple[int, int] | None = None,
) -> str:
    basliklar = "".join(
        f"<th>{escape(ad)}</th>" for ad in MEB_SUTUNLARI
    )
    govde: list[str] = []
    onceki_ay = ""
    for satir in satirlar:
        ay = "" if satir.ay == onceki_ay else satir.ay
        onceki_ay = satir.ay
        if satir.tur == TUR_TATIL:
            govde.append(
                f'<tr><td>{escape(ay)}</td>'
                f"<td>{_tarih_araligi(satir.baslangic, satir.bitis)}</td>"
                f'<td class="orta">—</td>'
                f'<td class="baslik-serit">{escape(satir.aciklama)}</td>'
                "<td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>"
            )
            continue
        # Bir kazanım birkaç hafta sürdüğünde tam metnini her satıra yeniden
        # yazmak planı okunmaz hâle getiriyor; devam eden haftalar yalnız kodla
        # ve "devam" notuyla gösterilir. Yaygın plan yazma pratiği de budur.
        kazanimlar = "<br/>".join(
            f"<b>{escape(kod)}</b> (devam)"
            if kod in satir.devam_kodlari
            else f"<b>{escape(kod)}</b> {escape(ifade)}"
            for kod, ifade in zip(satir.kazanim_kodlari, satir.kazanim_ifadeleri, strict=False)
        ) or escape(satir.aciklama)
        yeni_bilesenler = satir.yeni_kazanim_bilesenleri()
        bilesenler = "<br/>".join(escape(b) for b in yeni_bilesenler)
        govde.append(
            "<tr>"
            f"<td>{escape(ay)}</td>"
            f"<td>{_tarih_araligi(satir.baslangic, satir.bitis)}</td>"
            f'<td class="orta">{satir.ders_saati}</td>'
            f"<td>{('<b>' + escape(satir.tema_adi) + '</b><br/>') if satir.tema_adi else ''}{kazanimlar}</td>"
            f'<td class="kucuk">{bilesenler}</td>'
            f"<td>{_liste(satir.yontem_teknik)}</td>"
            f"<td>{_liste(satir.arac_gerec)}</td>"
            f"<td>{_liste(satir.olcme_degerlendirme)}</td>"
            f'<td class="kucuk">{_liste(satir.disiplinler_arasi)}</td>'
            f'<td class="kucuk">{_liste(satir.belirli_gunler)}</td>'
            f'<td class="kucuk">{escape(satir.aciklama)}</td>'
            "</tr>"
        )

    toplam = genel_toplam if genel_toplam is not None else sum(s.ders_saati for s in satirlar)
    sayfa_metni = (
        f'<p class="kucuk orta">Sayfa {sayfa_no[0]} / {sayfa_no[1]}</p>'
        if sayfa_no
        else ""
    )
    return (
        _ustbilgi(
            f"{ogretim_yili} EĞİTİM ÖĞRETİM YILI ÜNİTELENDİRİLMİŞ YILLIK DERS PLANI",
            f"{okul} — {sube_adi} sınıfı {ders} dersi",
        )
        + f"<table><tr>{basliklar}</tr>{''.join(govde)}</table>"
        + f'<p class="kucuk">Toplam ders saati: {toplam}</p>'
        + sayfa_metni
        + (_imza_blogu(ogretmen) if imza_goster else "")
    )


def yillik_plan_meb_sayfalari(
    satirlar: list[PlanSatiri],
    *,
    okul: str,
    sube_adi: str,
    ogretim_yili: str,
    ogretmen: str,
    ders: str = "Biyoloji",
    sayfa_basina_satir: int = 2,
) -> list[str]:
    """Her fiziksel sayfada başlığı tekrarlayan, satır bölmeyen MEB sayfaları."""
    parcalar = [
        satirlar[i : i + sayfa_basina_satir]
        for i in range(0, len(satirlar), sayfa_basina_satir)
    ] or [[]]
    toplam = sum(s.ders_saati for s in satirlar)
    return [
        yillik_plan_meb(
            parca,
            okul=okul,
            sube_adi=sube_adi,
            ogretim_yili=ogretim_yili,
            ogretmen=ogretmen,
            ders=ders,
            genel_toplam=toplam,
            imza_goster=sira == len(parcalar),
            sayfa_no=(sira, len(parcalar)),
        )
        for sira, parca in enumerate(parcalar, start=1)
    ]


# --- Maarif Modeli tema tablosu -----------------------------------------


def yillik_plan_maarif(
    tema_verileri: list[dict],
    *,
    okul: str,
    sube_adi: str,
    ogretim_yili: str,
    ogretmen: str,
) -> str:
    bolumler: list[str] = []
    for tema in tema_verileri:
        satirlar = [
            ("DERS SAATİ", str(tema["ders_saati"])),
            ("ALAN BECERİLERİ", ", ".join(tema["alan_becerileri"])),
            ("KAVRAMSAL BECERİLER", ", ".join(tema["kavramsal_beceriler"])),
            ("EĞİLİMLER", ", ".join(tema["egilimler"])),
            ("SOSYAL-DUYGUSAL ÖĞRENME BECERİLERİ", ", ".join(tema["sosyal_duygusal_beceriler"])),
            ("DEĞERLER", ", ".join(tema["degerler"])),
            ("OKURYAZARLIK BECERİLERİ", ", ".join(tema["okuryazarlik_becerileri"])),
            ("DİSİPLİNLER ARASI İLİŞKİLER", ", ".join(tema["disiplinler_arasi"])),
            ("BECERİLER ARASI İLİŞKİLER", ", ".join(tema["beceriler_arasi"])),
        ]
        ust = "".join(
            f"<tr><th>{escape(ad)}</th><td>{escape(deger)}</td></tr>"
            for ad, deger in satirlar
        )
        ciktilar = "".join(
            f'<tr><td><b>{escape(c["kod"])}</b> {escape(c["ifade"])}</td>'
            f'<td class="kucuk">'
            + "<br/>".join(f'{escape(b["harf"])}) {escape(b["ifade"])}' for b in c["surec_bilesenleri"])
            + "</td></tr>"
            for c in tema["ogrenme_ciktilari"]
        )
        bolumler.append(
            f'<h2>{tema["no"]}. TEMA: {escape(tema["ad"])}</h2>'
            f'<p class="kucuk">{escape(tema["aciklama"])}</p>'
            f"<table>{ust}</table>"
            "<h3>Öğrenme Çıktıları ve Süreç Bileşenleri</h3>"
            f"<table>{ciktilar}</table>"
            "<h3>İçerik Çerçevesi</h3>"
            f'<p class="kucuk">{escape(tema["icerik_cercevesi"])}</p>'
            "<h3>Anahtar Kavramlar</h3>"
            f'<p class="kucuk">{escape(", ".join(tema["anahtar_kavramlar"]))}</p>'
            "<h3>Öğrenme Kanıtları (Ölçme ve Değerlendirme)</h3>"
            f'<p class="kucuk">{escape(tema["ogrenme_kanitlari"])}</p>'
        )

    return (
        _ustbilgi(
            f"{ogretim_yili} — TEMA TABANLI YILLIK PLAN",
            f"{okul} — {sube_adi} sınıfı Biyoloji dersi (Türkiye Yüzyılı Maarif Modeli)",
        )
        + "".join(bolumler)
        + _imza_blogu(ogretmen)
    )


# --- günlük ders planı ---------------------------------------------------


def gunluk_plan_belgesi(plan: GunlukPlan, *, okul: str, ogretmen: str) -> str:
    kunye = [
        ("Ders", "Biyoloji"),
        ("Sınıf / Şube", f"{plan.sinif}. sınıf — {plan.sube_adi}"),
        ("Tarih", plan.tarih.strftime("%d.%m.%Y")),
        ("Ders Saati", ", ".join(str(s) for s in plan.ders_saatleri) + ". ders"),
        ("Süre", f"{plan.toplam_dakika} dakika"),
        ("Tema", f"{plan.tema_no}. TEMA: {plan.tema_adi}"),
    ]
    kunye_html = "".join(
        f"<tr><th>{escape(ad)}</th><td>{escape(deger)}</td></tr>"
        for ad, deger in kunye
    )

    kazanimlar = "<br/>".join(
        f"<b>{escape(kod)}</b> {escape(ifade)}"
        for kod, ifade in zip(plan.kazanim_kodlari, plan.kazanim_ifadeleri, strict=False)
    )
    bilesenler = "<br/>".join(escape(b) for b in plan.surec_bilesenleri)

    akis = "".join(
        f'<tr><td class="orta">{b.dakika} dk</td>'
        f"<td><b>{escape(b.ad)}</b></td>"
        f'<td>{escape(b.metin) or "<i>Bu bölüm için programda metin yok; kendiniz yazın.</i>"}</td></tr>'
        for b in plan.bolumler
    )

    farklilastirma = ""
    if plan.zenginlestirme or plan.destekleme:
        farklilastirma = (
            "<h3>Farklılaştırma</h3><table>"
            + (
                f'<tr><th>Zenginleştirme</th><td class="kucuk">{escape(plan.zenginlestirme)}</td></tr>'
                if plan.zenginlestirme
                else ""
            )
            + (
                f'<tr><th>Destekleme</th><td class="kucuk">{escape(plan.destekleme)}</td></tr>'
                if plan.destekleme
                else ""
            )
            + "</table>"
        )

    return (
        _ustbilgi("GÜNLÜK DERS PLANI", okul)
        + f"<table>{kunye_html}</table>"
        + "<h3>Öğrenme Çıktıları</h3>"
        + f'<div class="kutu">{kazanimlar}</div>'
        + "<h3>Süreç Bileşenleri</h3>"
        + f'<div class="kutu kucuk">{bilesenler}</div>'
        + "<h3>Ders Akışı</h3>"
        + f"<table>{akis}</table>"
        + "<h3>Yöntem, Teknik ve Araç-Gereç</h3>"
        + "<table>"
        + f'<tr><th>Yöntem-teknik</th><td>{_liste(plan.yontem_teknik)}</td></tr>'
        + f'<tr><th>Araç-gereç</th><td>{_liste(plan.arac_gerec)}</td></tr>'
        + f'<tr><th>Beceriler</th><td class="kucuk">{_liste(plan.beceriler)}</td></tr>'
        + f'<tr><th>Değerler</th><td class="kucuk">{_liste(plan.degerler)}</td></tr>'
        + "</table>"
        + farklilastirma
        + (f'<h3>Notlar</h3><p>{escape(plan.notlar)}</p>' if plan.notlar else "")
        + _imza_blogu(ogretmen)
    )


# --- sınav kâğıdı ve cevap anahtarı --------------------------------------


def sinav_kagidi(
    sinav: Sinav,
    grup: str,
    *,
    okul: str,
    ogretmen: str,
    tarih: str = "",
    yonerge: str = "",
) -> str:
    sorular = sinav.gruplar.get(grup, sinav.sorular)
    varsayilan_yonerge = (
        "Cevaplarınızı soruların altındaki boşluğa, okunaklı biçimde yazınız. "
        "Her sorunun puanı yanında belirtilmiştir. Süre: "
        f"{sinav.sure_dk} dakika."
    )
    nokta = "." * 34
    ogrenci_alani = (
        "<table><tr>"
        f"<td>Adı Soyadı: {nokta}</td>"
        f"<td>Numarası: {'.' * 14}</td>"
        f"<td>Puan: {'.' * 8}</td>"
        "</tr></table>"
    )

    govde: list[str] = []
    for sira, soru in enumerate(sorular, start=1):
        gorsel = (
            f'<p class="kucuk">[Görsel: {escape(soru.gorsel_yolu)}]</p>' if soru.gorselli else ""
        )
        # Cevap için boşluk: açık uçlu sınavda öğrencinin yazacağı alan kâğıtta
        # ayrılmalı, yoksa cevaplar kenara sıkışıp okunmaz oluyor.
        bosluk = "<br/>" * 4
        govde.append(
            f'<div class="kutu"><p><b>{sira}.</b> {escape(soru.metin)} '
            f'<span class="kucuk">({soru.puan:g} puan)</span></p>{gorsel}{bosluk}</div>'
        )

    return (
        _ustbilgi(
            f"{escape(sinav.ad)} — {grup} GRUBU",
            f"{okul} — {sinav.sube_adi} sınıfı Biyoloji dersi{(' — ' + tarih) if tarih else ''}",
        )
        + ogrenci_alani
        + f'<p class="kucuk">{escape(yonerge or varsayilan_yonerge)}</p>'
        + "".join(govde)
        + f'<p class="kucuk">Toplam: {sinav.toplam_puan:g} puan — {escape(ogretmen)}</p>'
    )


def cevap_anahtari(sinav: Sinav, *, okul: str) -> str:
    bolumler: list[str] = []
    for grup, sorular in sinav.gruplar.items():
        satirlar = "".join(
            f'<tr><td class="orta">{sira}</td>'
            f"<td>{escape(soru.kazanim_kodu)}</td>"
            f"<td>{escape(soru.metin)}</td>"
            f'<td class="kucuk">{escape(soru.rubrik) or "Rubrik girilmedi"}</td>'
            f'<td class="orta">{soru.puan:g}</td></tr>'
            for sira, soru in enumerate(sorular, start=1)
        )
        bolumler.append(
            f"<h2>{escape(grup)} Grubu</h2>"
            "<table><tr><th>#</th><th>Kazanım</th><th>Soru</th>"
            "<th>Dereceli Puanlama Anahtarı</th><th>Puan</th></tr>"
            f"{satirlar}</table>"
        )

    belirtke = "".join(
        f"<tr><td>{escape(s.ad)}</td><td class=\"orta\">{s.hedef_yuzde:g}%</td>"
        f'<td class="orta">{s.soru_sayisi}</td><td class="orta">{s.puan:g}%</td></tr>'
        for s in sinav.belirtke
    )

    return (
        _ustbilgi(f"{escape(sinav.ad)} — CEVAP ANAHTARI VE BELİRTKE TABLOSU", okul)
        + "<h2>Belirtke Tablosu</h2>"
        + "<table><tr><th>Tema / Kazanım</th><th>Hedef</th><th>Soru</th>"
        f"<th>Gerçekleşen</th></tr>{belirtke}</table>"
        + "".join(bolumler)
    )


# --- öğrenci gelişim raporu ----------------------------------------------


def ogrenci_raporu(
    karne: OgrenciKarnesi | None,
    devamsizlik: dict | None,
    denemeler: list[dict],
    kazanimlar: list[dict],
    *,
    okul: str,
    sube_adi: str,
    numara: str,
    ogretmen: str,
    tarih_metni: str,
) -> str:
    """Veli görüşmesine götürülen tek sayfalık gelişim raporu.

    Rapor yalnız kayıtlı veriyi taşır: girilmemiş not, girilmemiş deneme ya da
    puanlanmamış sınav satır olarak hiç görünmez — boş alanı doldurup "gerçek
    gibi görünen" belge üretmek bu programın yapmadığı şeydir.
    """
    parcalar = [
        _ustbilgi("Öğrenci Gelişim Raporu — Biyoloji", f"{okul} · {tarih_metni}"),
        "<table><tr>"
        f"<td><b>Öğrenci:</b> {escape(karne.ad_soyad if karne else '')}</td>"
        f'<td><b>Numara:</b> {escape(numara or "—")}</td>'
        f"<td><b>Şube:</b> {escape(sube_adi)}</td>"
        "</tr></table>",
    ]

    if karne:
        satirlar = []
        for donem in (1, 2):
            sonuc = karne.donemler.get(donem)
            if sonuc is None:
                continue
            for puan in sonuc.puanlar:
                if puan.deger is None or not puan.resmi:
                    continue
                satirlar.append(
                    f"<tr><td>{donem}. dönem</td>"
                    f"<td>{escape(TUR_ADLARI.get(puan.tur, puan.tur))}</td>"
                    f"<td>{escape(puan.ad)}</td><td class='orta'>{puan.deger:g}</td></tr>"
                )
            if sonuc.ortalama is not None:
                satirlar.append(
                    f'<tr class="baslik-serit"><td>{donem}. dönem</td><td colspan="2">Dönem puanı</td>'
                    f"<td class='orta'>{sonuc.ortalama:g}</td></tr>"
                )
        parcalar.append("<h2>Notlar</h2>")
        if satirlar:
            parcalar.append(
                "<table><tr><th>Dönem</th><th>Tür</th><th>Değerlendirme</th><th>Puan</th></tr>"
                + "".join(satirlar)
                + "</table>"
            )
            if karne.yil_sonu is not None:
                parcalar.append(f"<p><b>Yıl sonu başarı puanı:</b> {karne.yil_sonu:g}</p>")
        else:
            parcalar.append("<p class='kucuk'>Henüz girilmiş resmî not yok.</p>")
        if karne.ic_takip_ortalamasi is not None:
            parcalar.append(
                f"<p class='kucuk'>İç takip ortalaması: {karne.ic_takip_ortalamasi:g} "
                "(resmî ortalamaya dahil değildir).</p>"
            )

    # `toplam_ders` şartı: yoklaması hiç alınmamış öğrencide devam_orani None
    # gelir ve ":g" biçimlemesi 500 verirdi; kayıtsız bölüm hiç basılmaz.
    if devamsizlik and devamsizlik.get("toplam_ders"):
        uyari = devamsizlik.get("uyari") or ""
        oran = devamsizlik.get("devam_orani")
        parcalar.append(
            "<h2>Devamsızlık</h2>"
            "<table><tr><th>Gelmedi (gün)</th><th>Gelmedi (saat)</th>"
            "<th>İzinli (saat)</th><th>Geç (saat)</th><th>Devam oranı</th></tr>"
            f"<tr><td class='orta'>{devamsizlik['yok_gun']:g}</td>"
            f"<td class='orta'>{devamsizlik['yok_saat']}</td>"
            f"<td class='orta'>{devamsizlik['izinli_saat']}</td>"
            f"<td class='orta'>{devamsizlik['gec_saat']}</td>"
            f"<td class='orta'>{f'%{oran:g}' if oran is not None else '—'}</td></tr></table>"
            + (f"<p class='kucuk'>{escape(uyari)}</p>" if uyari else "")
        )

    if denemeler:
        satirlar = [
            f"<tr><td>{escape(d['ad'])}</td><td class='orta'>{escape(d['tarih'] or '—')}</td>"
            f"<td class='orta'>{d['dogru']}</td><td class='orta'>{d['yanlis']}</td>"
            f"<td class='orta'>{d['bos']}</td><td class='orta'>{d['net']:g}</td></tr>"
            for d in denemeler
        ]
        parcalar.append(
            "<h2>Deneme Sınavları (Biyoloji)</h2>"
            "<table><tr><th>Deneme</th><th>Tarih</th><th>Doğru</th><th>Yanlış</th>"
            "<th>Boş</th><th>Net</th></tr>" + "".join(satirlar) + "</table>"
        )

    if kazanimlar:
        satirlar = [
            f"<tr><td>{escape(k['kod'])}</td><td>{escape(k['ifade'])}</td>"
            f"<td class='orta'>%{k['yuzde']:g}</td><td class='orta'>{escape(k['durum'])}</td></tr>"
            for k in kazanimlar
            if k["yuzde"] is not None
        ]
        parcalar.append(
            "<h2>Kazanım Başarısı (sınavlardaki son durum)</h2>"
            "<table><tr><th>Kazanım</th><th>Açıklama</th><th>Başarı</th><th>Durum</th></tr>"
            + "".join(satirlar)
            + "</table>"
        )

    parcalar.append(_imza_blogu(ogretmen))
    return "".join(parcalar)
