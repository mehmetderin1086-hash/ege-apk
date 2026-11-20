"""sinav-okur komut satırı arayüzü.

Alt komutlar:
  fontlar    Bir dizindeki fontların Türkçe kapsamını denetler
  veri       Sentetik el yazısı eğitim verisi üretir
  referans   Ders kitaplarından referans gömme indeksi kurar
  gercekveri HuggingFace Türkçe el yazısı setini eğitim formatına indirir
  satirpaketi İzinli gerçek satır paketini doğrulayıp eğitim biçimine aktarır
  theveri    T-H-E Version VI özgün Türkçe karakterlerini dışa aktarır
  rapor      Sınavın not dökümünü Excel'e aktarır
  disaaktar  Düzeltilmiş verileri yeniden eğitim için JSONL'e aktarır
  kalibrasyon Öğretmen düzeltmelerinden OCR güven kalibrasyonu eğitir
  tezgah     Altın örnek regresyon tezgâhı: yerel CER/eşleşme/puan MAE ölçümü
  model-kur  Colab'da eğitilen TrOCR modelini modeller/trocr-tr'ye kurar
  webapp     Gözden geçirme arayüzünü başlatır
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _cmd_fontlar(a: argparse.Namespace) -> int:
    from .veri import fontlari_dogrula

    rapor = fontlari_dogrula(a.dizin)
    if not rapor:
        print("Font bulunamadı."); return 1
    uygun = 0
    for yol, eksik in rapor.items():
        ad = Path(yol).name
        if not eksik:
            print(f"  ✓ {ad}"); uygun += 1
        else:
            gosterim = "".join(eksik[:12]) + ("…" if len(eksik) > 12 else "")
            print(f"  ✗ {ad} — eksik: {gosterim}")
    print(f"\n{uygun}/{len(rapor)} font Türkçe-uygun.")
    return 0


def _cmd_veri(a: argparse.Namespace) -> int:
    from .veri import veri_uret

    if not a.test_amacli:
        print(
            "Engellendi: font-render veri gerçek model eğitiminde kullanılamaz. "
            "Yalnız demo/regresyon için --test-amacli verin.",
            file=sys.stderr,
        )
        return 2
    ek = Path(a.ek_terimler).read_text(encoding="utf-8").split() if a.ek_terimler else None
    sonuc = veri_uret(a.cikti, a.fontlar, adet=a.adet, tohum=a.tohum, ek_terimler=ek)
    print(f"Üretilen satır: {sonuc['uretilen']}")
    print(f"Kullanılan font: {sonuc['font_sayisi']}")
    print(f"Etiketler: {sonuc['labels']}")
    return 0


def _cmd_referans(a: argparse.Namespace) -> int:
    from .puanlama import gomlemci_yukle
    from .referans import KitapDeposu

    gomlemci = gomlemci_yukle()
    if gomlemci is None:
        print("Hata: referans indeksi için sentence-transformers gerekli "
              "(uv sync --extra gomme).", file=sys.stderr)
        return 1
    depo = KitapDeposu.kur(a.kaynaklar, gomlemci)
    depo.kaydet(a.cikti)
    print(f"{len(depo.pasajlar)} pasaj indekslendi → {a.cikti}")
    return 0


def _cmd_gercekveri(a: argparse.Namespace) -> int:
    from .veri import ON_AYARLAR, VeriSetiOnAyar, hf_labels_uret

    if a.listele:
        print("Bilinen Türkçe el yazısı setleri (ön-ayar → repo):")
        for anahtar, oa in ON_AYARLAR.items():
            print(f"  {anahtar:14} {oa.repo_id} [{oa.tip}/{oa.lisans}] — {oa.not_}")
        return 0
    hedef = a.set
    if hedef in ON_AYARLAR:
        onayar = hedef
    else:
        onayar = VeriSetiOnAyar(repo_id=hedef, split=a.split,
                                goruntu_anahtari=a.goruntu_anahtari,
                                metin_anahtari=a.metin_anahtari)
    sonuc = hf_labels_uret(
        onayar, a.cikti, azami=a.azami, onek=a.onek, amac=a.amac
    )
    print(f"{sonuc['repo']}: {sonuc['yazilan']} yazıldı, {sonuc['atlanan']} atlandı "
          f"[{sonuc['tip']}/{sonuc['lisans']}] → {sonuc['labels']}")
    return 0


def _cmd_theveri(a: argparse.Namespace) -> int:
    from .veri import the_karakter_aktar

    sonuc = the_karakter_aktar(
        a.csv, a.cikti, test_orani=a.test_orani, tohum=a.tohum
    )
    print(f"T-H-E Version VI: {sonuc['yazilan']} özgün karakter, "
          f"{sonuc['sinif']} Türkçe sınıf → {sonuc['labels']}")
    print(f"Veri manifesti: {sonuc['manifest']}")
    return 0


def _cmd_satirpaketi(a: argparse.Namespace) -> int:
    from .veri import satir_paketi_aktar

    sonuc = satir_paketi_aktar(
        a.labels,
        a.cikti,
        lisans=a.lisans,
        izin_belgesi=a.izin_belgesi,
        kaynak_url=a.kaynak_url,
    )
    print(
        f"{sonuc['satir']} gerçek satır / {sonuc['yazar']} anonim yazar aktarıldı; "
        f"yazar-ayrık bölmeler: {'doğrulandı' if sonuc['bolmeler_dogrulandi'] else 'girdide yok'}"
    )
    print(f"Etiketler: {sonuc['labels']}")
    print(f"Manifest:  {sonuc['manifest']}")
    return 0


def _cmd_rapor(a: argparse.Namespace) -> int:
    from .depo import Depo
    from .rapor import excel_dokum

    yol = excel_dokum(Depo(a.db), a.sinav, a.cikti)
    print(f"Not dökümü: {yol}")
    return 0


def _cmd_disaaktar(a: argparse.Namespace) -> int:
    from .depo import Depo

    n = Depo(a.db).egitim_verisi_disa_aktar(a.cikti, a.sinav)
    print(f"{n} düzeltilmiş örnek {a.cikti} dosyasına yazıldı.")
    return 0


def _cmd_tezgah(a: argparse.Namespace) -> int:
    from .depo import Depo
    from .tezgah import (
        altin_ornekleri_uret,
        anlik_goruntu_yaz,
        kapsam_supurmesi,
        perf_ozeti,
        tezgah_calistir,
    )

    if a.perf:
        veri_kok = Path(a.db).resolve().parent / "sinav_okur_veri"
        ozet = perf_ozeti(veri_kok / "serbest_taslaklar")
        print(
            f"{ozet['taslak_sayisi']} taslak · {ozet['sayfa_sayisi']} sayfa · "
            f"ortalama sayfa-OCR süresi {ozet['ort_sayfa_ms'] / 1000:.1f} sn"
        )
        for m in ozet["motorlar"]:
            print(
                f"  {m['motor']:<10} {m['istek']} istek · "
                f"ort {m['ort_ms'] / 1000:.1f} sn · "
                f"toplam {m['toplam_ms'] / 1000:.1f} sn · {m['hata']} hata"
            )
        return 0

    from .htr import taniyici_yukle

    depo = Depo(a.db)
    if a.altin_uret:
        uret = altin_ornekleri_uret(depo, a.sinav, kaynak=a.kaynak)
        kaynaklar = ", ".join(
            f"{ad}: {sayi}" for ad, sayi in uret["kaynak_sayimi"].items() if sayi
        )
        print(
            f"Altın set: +{uret['eklenen']} yeni, {uret['guncellenen']} "
            f"güncellenen, {uret['atlanan']} atlanan, "
            f"toplam {uret['toplam']} örnek."
            + (f" ({kaynaklar})" if kaynaklar else "")
        )
    if not depo.altin_ornekler(a.sinav):
        print(
            "Altın örnek yok. Öğretmen düzeltmesi olan bir kutu ya da "
            "onaylanmış kâğıt gerekiyor; sonra --altin-uret ile üretin."
        )
        return 2
    taniyici = taniyici_yukle(a.taniyici)
    sonuc = tezgah_calistir(
        depo,
        taniyici,
        sinav_kimlik=a.sinav,
        taniyici_adi=a.taniyici,
        zincir=a.zincir,
    )
    if a.supurme:
        sonuc["kapsam_supurmesi"] = kapsam_supurmesi(sonuc["satirlar"])
    yol = anlik_goruntu_yaz(a.olcum_dizini, sonuc)
    m = sonuc["metrikler"]
    print(
        f"{m['ornek']} örnek · ort. CER {m['ort_cer']} · "
        f"tam eşleşme {m['tam_eslesme_orani']} · "
        f"puan MAE {m['puan'].get('puan_mae')}"
    )
    puan = m["puan"]
    if puan.get("rubrik_mae") is not None or puan.get("ocr_puan_mae") is not None:
        print(
            f"  hata bütçesi → anahtar/rubrik MAE {puan.get('rubrik_mae')} · "
            f"okuma MAE {puan.get('ocr_puan_mae')}"
        )
    if puan.get("otomatik_kapsama") is not None:
        print(
            f"  kapı → otomatik kapsama %{puan['otomatik_kapsama'] * 100:.1f} · "
            f"yanlış kabul {puan.get('yanlis_otomatik_kabul')} "
            f"(puan bazlı {puan.get('yanlis_puanli_otomatik_kabul')})"
        )
    kazanc = m.get("katman_kazanci") or {}
    if kazanc.get("cer_kazanci") is not None:
        print(
            f"  katman kazancı → ham CER {kazanc['ort_cer_ham']} → "
            f"üretim {kazanc['ort_cer_uretim']} "
            f"({kazanc['cer_kazanci']:+.4f}); sözlük {kazanc['sozluk_dokunan']} "
            f"kutuya, sıralama {kazanc['siralama_dokunan']} kutuya dokundu"
        )
    for uyari in sonuc["uyarilar"]:
        print(f"UYARI: {uyari}")
    if a.supurme:
        print("Güven eşiği süpürmesi (kapsam → doğruluk):")
        for satir in sonuc["kapsam_supurmesi"]:
            print(
                f"  ≥{satir['esik']:.2f}: kapsam %{satir['kapsam'] * 100:.1f} "
                f"({satir['ornek']} örnek) · CER {satir['ort_cer']} · "
                f"tam eşleşme {satir['tam_eslesme_orani']}"
            )
    karsilastirma = sonuc["karsilastirma"]
    gerilemeler = karsilastirma["gerilemeler"]
    for g in gerilemeler:
        print(f"GERİLEME: {g}")
    print(f"Anlık görüntü: {yol}")
    # Küçük altın sette gerileme uyarıdır; kapıyı kırmızıya boyamaz.
    return 1 if karsilastirma.get("sert") else 0


def _cmd_motor_karsilastir(a: argparse.Namespace) -> int:
    from .depo import Depo
    from .motor_karsilastirma import motorlari_karsilastir

    motorlar = (
        [m.strip() for m in a.motorlar.split(",") if m.strip()]
        if a.motorlar
        else None
    )
    sonuc = motorlari_karsilastir(
        Depo(a.db),
        sinav_kimlik=a.sinav,
        motorlar=motorlar,
        azami_ornek=a.azami_ornek,
    )
    if not sonuc["motorlar"]:
        print(
            "Karşılaştırılacak altın örnek yok. Önce birkaç cevabı elle "
            "düzeltip 'sinav-okur tezgah --altin-uret' çalıştırın."
        )
        return 2
    print(f"{sonuc['ornek']} altın örnek üzerinde ölçüldü:\n")
    print(f"  {'motor':<16}{'CER':>8}{'süre':>9}  not")
    for satir in sonuc["motorlar"]:
        if "cer" not in satir:
            print(f"  {satir['motor']:<16}{'—':>8}{'—':>9}  {satir['hata']}")
            continue
        not_metni = (
            f"{satir['hata_sayisi']} okuma hatası"
            if satir["hata_sayisi"]
            else ""
        )
        print(
            f"  {satir['motor']:<16}{satir['cer']:>8.3f}"
            f"{satir['ort_sn']:>8.1f}s  {not_metni}"
        )
    if sonuc["en_iyi"]:
        print(f"\nEn düşük hata: {sonuc['en_iyi']}")
    for uyari in sonuc["uyarilar"]:
        print(f"UYARI: {uyari}")
    return 0


def _cmd_motor_sagligi(a: argparse.Namespace) -> int:
    from .ocr import (
        SAGLIK_AZAMI_HATA_ORANI,
        devre_kesiciyi_sifirla,
        motor_saglik_yolu,
        motor_sagligi_oku,
        motor_saglikli_mi,
    )

    if a.sifirla:
        devre_kesiciyi_sifirla(saglik_da=True)
        print(f"Motor sağlık kaydı sıfırlandı: {motor_saglik_yolu()}")
        return 0
    saglik = motor_sagligi_oku()
    if not saglik:
        print("Motor sağlık kaydı boş; henüz alt süreç OCR'ı çalışmamış.")
        return 0
    print(f"Kayıt: {motor_saglik_yolu()}")
    for motor, kayit in sorted(saglik.items()):
        istek = int(kayit.get("istek", 0))
        hata = int(kayit.get("hata", 0))
        oran = hata / istek if istek else 0.0
        durum = "sağlıklı" if motor_saglikli_mi(motor, saglik) else "ELENDİ"
        print(
            f"  {motor:<10} {istek} istek · {hata} hata · "
            f"%{oran * 100:.0f} · {durum}"
        )
    print(
        f"Eleme eşiği: hata oranı > %{SAGLIK_AZAMI_HATA_ORANI * 100:.0f}. "
        "Elenen motor 'besli' profilinde yine denenir."
    )
    return 0


def _cmd_kalibrasyon(a: argparse.Namespace) -> int:
    import json as _json

    from .depo import Depo
    from .ogrenme import ocr_kalibrasyonunu_guncelle

    depo = Depo(a.db)
    if a.jsonl_cikti:
        from .ogrenme import ocr_kalibrasyon_kumesi

        ornekler = depo.kalibrasyon_ornekleri(a.sinav)
        ham, etiket = ocr_kalibrasyon_kumesi(ornekler)
        with open(a.jsonl_cikti, "w", encoding="utf-8") as f:
            for h, e in zip(ham, etiket):
                f.write(_json.dumps({"ham_guven": h, "dogru": bool(e)}) + "\n")
        print(f"{len(ham)} ham örnek {a.jsonl_cikti} dosyasına yazıldı.")
    sonuc = ocr_kalibrasyonunu_guncelle(
        depo,
        a.cikti,
        sinav_kimlik=a.sinav,
        asgari_ornek=a.asgari_ornek,
        yalniz_duzeltmeler=a.yalniz_duzeltmeler,
        kuru=a.kuru,
    )
    print(_json.dumps(sonuc, ensure_ascii=False, indent=2))
    return 0 if sonuc.get("uygulandi") or a.kuru else 1


def _cmd_modelkur(a: argparse.Namespace) -> int:
    """Colab'da eğitilen TrOCR zip'ini modeller/trocr-tr dizinine kurar."""
    import shutil
    import tempfile
    import zipfile

    hedef = Path(a.hedef).expanduser().resolve()
    kaynak = Path(a.zip).expanduser()
    if not kaynak.is_file():
        print(f"HATA: zip bulunamadı: {kaynak}", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as gecici:
        gecici_yol = Path(gecici)
        with zipfile.ZipFile(kaynak) as z:
            for ad in z.namelist():
                # zip-slip: arşiv dışına yazmayı engelle
                if Path(ad).is_absolute() or ".." in Path(ad).parts:
                    print(f"HATA: güvensiz arşiv girdisi: {ad}", file=sys.stderr)
                    return 1
            z.extractall(gecici_yol)
        adaylar = [p.parent for p in gecici_yol.rglob("config.json")]
        if not adaylar:
            print("HATA: arşivde config.json içeren model dizini yok.", file=sys.stderr)
            return 1
        model_dizini = min(adaylar, key=lambda p: len(p.parts))
        if hedef.exists():
            shutil.rmtree(hedef)
        hedef.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(model_dizini), str(hedef))
    dosyalar = sorted(p.name for p in hedef.iterdir())
    print(f"Model kuruldu: {hedef}")
    print(f"Dosyalar: {', '.join(dosyalar)}")
    print("Topluluk OCR ve --taniyici trocr bu modeli otomatik kullanır.")
    return 0


def _cmd_webapp(a: argparse.Namespace) -> int:
    import uvicorn

    from .webapp import uygulama_kur

    app = uygulama_kur(a.db, a.kirp_dizini, a.veri_dizini)
    uvicorn.run(app, host=a.host, port=a.port)
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="sinav-okur", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    alt = p.add_subparsers(dest="komut", required=True)

    ft = alt.add_parser("fontlar", help="Font Türkçe kapsamı denetle")
    ft.add_argument("dizin"); ft.set_defaults(fn=_cmd_fontlar)

    v = alt.add_parser("veri", help="Yalnız demo/test için font-render veri üret")
    v.add_argument("-o", "--cikti", default="sentetik_veri")
    v.add_argument("-f", "--fontlar", required=True)
    v.add_argument("-n", "--adet", type=int, default=2000)
    v.add_argument("--tohum", type=int, default=0)
    v.add_argument("--ek-terimler", dest="ek_terimler")
    v.add_argument(
        "--test-amacli", action="store_true",
        help="çıktının gerçek eğitim verisi olmadığını kabul ederek demo/test üret",
    )
    v.set_defaults(fn=_cmd_veri)

    rf = alt.add_parser("referans", help="Ders kitaplarından referans indeksi kur")
    rf.add_argument("kaynaklar", nargs="+", help="PDF/txt ders kitabı dosyaları")
    rf.add_argument("-o", "--cikti", default="referans_indeks")
    rf.set_defaults(fn=_cmd_referans)

    gv = alt.add_parser("gercekveri", help="HF Türkçe el yazısı setini indir (labels.jsonl)")
    gv.add_argument("set", nargs="?", default="", help="ön-ayar anahtarı (ör. the) veya HF repo id")
    gv.add_argument("--listele", action="store_true", help="bilinen setleri listele")
    gv.add_argument("-o", "--cikti", default="gercek_veri")
    gv.add_argument("--split", default="train")
    gv.add_argument("--azami", type=int, help="en fazla bu kadar örnek")
    gv.add_argument("--onek", default="", help="birden çok set aynı dizine eklenirken önek")
    gv.add_argument("--goruntu-anahtari", dest="goruntu_anahtari")
    gv.add_argument("--metin-anahtari", dest="metin_anahtari")
    gv.add_argument(
        "--amac", choices=["eval", "egitim"], default="eval",
        help="eğitim yalnız gerçekliği ve lisansı doğrulanmış ön-ayarlarda açılır",
    )
    gv.set_defaults(fn=_cmd_gercekveri)

    tv = alt.add_parser("theveri", help="T-H-E version6.csv özgün karakterlerini dışa aktar")
    tv.add_argument("csv", help="T-H-E version6.csv (git-lfs pull ile inen)")
    tv.add_argument("-o", "--cikti", default="the_karakter_verisi")
    tv.add_argument("--test-orani", type=float, default=0.1)
    tv.add_argument("--tohum", type=int, default=42)
    tv.set_defaults(fn=_cmd_theveri)

    sp = alt.add_parser(
        "satirpaketi",
        help="İzinli gerçek satır paketini doğrula ve labels.jsonl biçimine aktar",
    )
    sp.add_argument("labels", help="image/text/writer_id[/split] içeren kaynak JSONL")
    sp.add_argument("-o", "--cikti", default="gercek_satir_verisi")
    sp.add_argument("--lisans", required=True, help="izin/lisans tanımı")
    sp.add_argument("--izin-belgesi", required=True, help="yerel izin/lisans kanıtı")
    sp.add_argument("--kaynak-url", required=True, help="veri veya çalışma kaynak URL'si")
    sp.set_defaults(fn=_cmd_satirpaketi)

    r = alt.add_parser("rapor", help="Not dökümü Excel üret")
    r.add_argument("sinav"); r.add_argument("-o", "--cikti", default="notlar.xlsx")
    r.add_argument("--db", default="sinav_okur.db"); r.set_defaults(fn=_cmd_rapor)

    d = alt.add_parser("disaaktar", help="Düzeltilmiş veriyi JSONL'e aktar")
    d.add_argument("-o", "--cikti", default="egitim_verisi.jsonl")
    d.add_argument("--sinav"); d.add_argument("--db", default="sinav_okur.db")
    d.set_defaults(fn=_cmd_disaaktar)

    mk = alt.add_parser(
        "motor-karsilastir",
        help="Kurulu OCR motorlarını KENDİ altın setinizde CER'e göre sırala",
    )
    mk.add_argument("--db", default="sinav_okur.db")
    mk.add_argument("--sinav", help="yalnız bu sınavın altın örnekleri")
    mk.add_argument(
        "--motorlar",
        help="virgülle ayrılmış motor listesi (vars. vision + alt süreç motorları)",
    )
    mk.add_argument(
        "--azami-ornek", type=int,
        help="ilk N örnekle sınırla (yavaş motorlarda hızlı deneme)",
    )
    mk.set_defaults(fn=_cmd_motor_karsilastir)

    ms = alt.add_parser(
        "motor-sagligi",
        help="OCR motorlarının kalıcı başarı/hata kaydını göster veya sıfırla",
    )
    ms.add_argument(
        "--sifirla", action="store_true",
        help="kaydı temizle (elenen motorlar yeniden denenir)",
    )
    ms.set_defaults(fn=_cmd_motor_sagligi)

    kal = alt.add_parser(
        "kalibrasyon",
        help="Öğretmen düzeltmelerinden OCR güven kalibrasyonu eğit",
    )
    kal.add_argument("--db", default="sinav_okur.db")
    kal.add_argument(
        "--cikti",
        default=str(Path(__file__).resolve().parents[1] / "modeller" / "ocr_kalibrasyon.json"),
    )
    kal.add_argument("--sinav", help="yalnız bu sınavın kutularıyla eğit")
    kal.add_argument("--asgari-ornek", type=int, default=200)
    kal.add_argument(
        "--yalniz-duzeltmeler", action="store_true",
        help="onaylı-dokunulmamış kutuları dışla, yalnız açık düzeltmeleri kullan",
    )
    kal.add_argument(
        "--kuru", action="store_true", help="yalnız metrikleri göster, yazma"
    )
    kal.add_argument(
        "--jsonl-cikti", help="ham (ham_guven,dogru) kümesini JSONL olarak da dök"
    )
    kal.set_defaults(fn=_cmd_kalibrasyon)

    tz = alt.add_parser(
        "tezgah",
        help="Altın örnek regresyon tezgâhı: yerel CER/eşleşme/puan MAE ölçümü",
    )
    tz.add_argument("--db", default="sinav_okur.db")
    tz.add_argument("--sinav", help="yalnız bu sınavın altın örnekleri")
    tz.add_argument(
        "--taniyici", default="coklu",
        help="taniyici türü (coklu/vision/trocr/mlx/keras-karakter/keras-ctc/yapay)",
    )
    tz.add_argument(
        "--altin-uret", action="store_true",
        help="önce insan-doğrulanmış kutulardan altın örnek üret",
    )
    tz.add_argument(
        "--kaynak", default="hepsi", choices=["onay", "duzeltme", "hepsi"],
        help=(
            "altın örnek kaynağı: onaylanmış kâğıtlar, öğretmenin metnini "
            "düzelttiği kutular ya da ikisi (varsayılan)"
        ),
    )
    tz.add_argument(
        "--zincir", default="uretim", choices=["ham", "uretim", "ikisi"],
        help=(
            "ölçülecek okuma yolu: ham (çıplak OCR), uretim (bağlam+sözlük+"
            "sıralama) ya da ikisi (katman kazancı raporlanır)"
        ),
    )
    tz.add_argument(
        "--supurme", action="store_true",
        help="güven eşiği → kapsam/doğruluk süpürme tablosu (yalnız rapor)",
    )
    tz.add_argument(
        "--perf", action="store_true",
        help="kayıtlı taslakların sayfa-OCR motor süre kırılımını göster",
    )
    tz.add_argument(
        "--olcum-dizini",
        default=str(Path(__file__).resolve().parents[1] / "olcumler"),
        help="anlık görüntü dizini (varsayılan: proje kökü/olcumler)",
    )
    tz.set_defaults(fn=_cmd_tezgah)

    mk = alt.add_parser("model-kur", help="Colab TrOCR zip'ini modeller/ altına kur")
    mk.add_argument("zip", help="Colab'dan inen trocr-tr.zip")
    mk.add_argument(
        "--hedef",
        default=str(Path(__file__).resolve().parents[1] / "modeller" / "trocr-tr"),
        help="kurulum dizini (varsayılan: proje kökü/modeller/trocr-tr)",
    )
    mk.set_defaults(fn=_cmd_modelkur)

    w = alt.add_parser("webapp", help="Gözden geçirme arayüzü")
    w.add_argument("--db", default="sinav_okur.db")
    w.add_argument("--kirp-dizini", default="kirpintlar")
    w.add_argument(
        "--veri-dizini",
        help="yüklenen yazılıların ve uygulama verilerinin güvenli dizini",
    )
    w.add_argument("--host", default="127.0.0.1"); w.add_argument("--port", type=int, default=8000)
    w.set_defaults(fn=_cmd_webapp)

    a = p.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    raise SystemExit(main())
