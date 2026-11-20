#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sınav üretimi ↔ optik okuyucu köprüsü — kapalı döngünün son halkası.

Kesilmiş sorulardan sınav PDF'i üretilirken (sinav_pdf.sinav_pdf_uret)
AYNI soru kümesinden eşleşen optik cevap kâğıdı da üretilir:

- Soru sayısı ve şık sayısı sınavdan türetilir (cevaplarda E varsa 5 şık).
- Kitapçık permütasyonları sinav_pdf._grup_ici_karistir ile AYNI tohumdan
  yeniden hesaplanır → her kitapçığın cevap anahtarı otomatik dolar
  (öğretmen anahtar girmeden tarayıp puanlayabilir).
- Soruların konu etiketleri (banka/konu-csv) kazanım eşlemesine yazılır;
  kitapçık soru sırası (kitapcik_sira) sınav ayarlarına kaydedilir →
  B/C/D kitapçığındaki öğrencinin kazanım analizi kanonik (A) numara
  üzerinden doğru yapılır (optik_analiz.kazanim_analizi).

Not: anahtar eşlemesi sınavın 1'den YENİDEN NUMARALANMIŞ düzenini varsayar
(sinav_pdf varsayılanı). yeniden_numarala kapalıysa basılı numaralar optik
formla örtüşmeyebilir — bu durumda uyarı döner.
"""
import optik_form
import optik_sema as osm


def secenek_sayisi(meta):
    """Sınavdaki şık sayısı: cevaplar arasında E varsa 5, yoksa 4."""
    for so in meta:
        if str(so.get("cevap") or "").strip().upper() == "E":
            return 5
    return 4


def anahtarlar_ve_sira(meta, kitapcik_sayisi, tohum):
    """Her kitapçık için cevap anahtarı + kanonik sıra eşlemesi.

    Dönüş: (anahtarlar, kitapcik_sira)
      anahtarlar: {harf: {"": {form_soru_no(str): "A"|""}}}
      kitapcik_sira: {harf: [kanonik_no, ...]} — form sırası → A (kaynak)
      numarası; kazanım analizi bu eşlemeyle kanonik numaraya döner.
    """
    import sinav_pdf
    anahtarlar, kitapcik_sira = {}, {}
    for k in range(max(1, kitapcik_sayisi)):
        harf = chr(65 + k)
        sira = sinav_pdf._grup_ici_karistir(meta, tohum, k)
        anahtarlar[harf] = {"": {
            str(i + 1): str(meta[j].get("cevap") or "").strip().upper()
            for i, j in enumerate(sira)}}
        kitapcik_sira[harf] = [j + 1 for j in sira]
    return anahtarlar, kitapcik_sira


def kazanim_haritasi(meta):
    """Kanonik (A kitapçığı) numara → konu etiketi eşlemesi.

    Dönüş: {"": {no(str): konu}} — konusu olmayan sorular atlanır."""
    harita = {}
    for i, so in enumerate(meta):
        konu = (so.get("konu") or "").strip()
        if konu:
            harita.setdefault("", {})[str(i + 1)] = konu
    return harita


def sinavdan_optik(meta, ayarlar, yol, kaydet=True):
    """Sınav soru kümesinden eşleşen optik form + anahtar + kazanım üretir.

    meta: sinav_pdf_uret'e giden soru meta listesi (cevap/konu alanlı).
    ayarlar: sınav ayarları (baslik, kurum, kitapcik, tohum,
    yeniden_numarala). Dönüş: {"pdf", "sablon_yolu", "sinav_id", "sayfa",
    "soru", "kitapcik", "anahtarli_soru", "kazanimli_soru", "uyarilar"}.

    kaydet=True → optik veritabanına sınav + kitapçık anahtarları +
    kazanım eşlemesi + kitapcik_sira yazılır (web 🔘 Optik sekmesinde
    taramaya hazır görünür).
    """
    if not meta:
        raise ValueError("optik form için soru yok")
    kitapcik = max(1, int(ayarlar.get("kitapcik") or 1))
    secenek = secenek_sayisi(meta)
    uyarilar = []
    if ayarlar.get("yeniden_numarala") is False:
        uyarilar.append("yeniden numaralama kapalı — basılı soru "
                        "numaraları optik formla örtüşmeyebilir")
    tanim = {
        "ad": ayarlar.get("baslik") or "Sınav",
        "kurum": ayarlar.get("kurum") or "",
        "kitapcik": min(kitapcik, 4),
        "yanlis_boler": int(ayarlar.get("yanlis_boler") or 0),
        "dersler": [{"ad": "", "soru": len(meta), "secenek": secenek}],
    }
    sonuc = optik_form.form_uret(tanim, yol=yol)
    anahtarlar, kitapcik_sira = anahtarlar_ve_sira(
        meta, tanim["kitapcik"], ayarlar.get("tohum"))
    kazanimlar = kazanim_haritasi(meta)
    anahtarli = sum(1 for v in anahtarlar.get("A", {}).get("", {}).values()
                    if v)
    if not anahtarli:
        uyarilar.append("sorularda cevap bilgisi yok — anahtarı elle "
                        "girin veya işaretli kâğıt tarayın")
    if kaydet:
        import optik_kayit
        conn = optik_kayit.baglan()
        try:
            optik_kayit.sinav_ekle(conn, sonuc["sablon"], {
                "kurum": tanim["kurum"],
                "yanlis_boler": tanim["yanlis_boler"],
                "kaynak": "sinav_pdf",
                "kitapcik_sira": kitapcik_sira})
            if anahtarli:
                for harf, cevaplar in anahtarlar.items():
                    optik_kayit.anahtar_koy(conn, sonuc["sinav_id"],
                                            harf, cevaplar)
            if kazanimlar:
                optik_kayit.kazanim_koy(conn, sonuc["sinav_id"],
                                        kazanimlar)
        finally:
            conn.close()
    return {"pdf": sonuc["pdf"], "sablon_yolu": sonuc["sablon_yolu"],
            "sinav_id": sonuc["sinav_id"], "sayfa": sonuc["sayfa"],
            "soru": len(meta), "kitapcik": tanim["kitapcik"],
            "anahtarli_soru": anahtarli,
            "kazanimli_soru": len(kazanimlar.get("", {})),
            "uyarilar": uyarilar,
            "anahtarlar": anahtarlar, "kitapcik_sira": kitapcik_sira,
            "kazanimlar": kazanimlar}
