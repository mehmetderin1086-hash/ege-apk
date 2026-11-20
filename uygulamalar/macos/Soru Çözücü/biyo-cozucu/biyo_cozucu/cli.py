"""Komut satırı arayüzü.

Ağır bağımlılıklar (torch, mlx, fastapi) modül düzeyinde değil, ilgili komutun
içinde import edilir — `biyo-cozucu --help` bir saniyenin altında açılmalı.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def _kok(argumanlar) -> Path:
    from .cozucu import VARSAYILAN_KOK

    return Path(argumanlar.veri or VARSAYILAN_KOK)


def _motor_turu(argumanlar) -> str:
    """Bayrak > `BIYO_MOTOR` > ``mlx``.

    Argparse'a sabit bir varsayılan koymak ortam değişkenini sessizce etkisiz
    bırakırdı. Boş/yalnız boşluk olan değişken tanımsız sayılır; kabuk
    profillerinde `export BIYO_MOTOR=` sık görülür ve modelsiz çalışmaya
    düşmek yerine belgelenen varsayılana dönmek gerekir.
    """
    secilen = argumanlar.motor or os.environ.get("BIYO_MOTOR", "")
    return (secilen.strip() or "mlx").casefold()


# Kullanıcıya giden yolların (coz, sunucu) oylama varsayılanı. Ölçüm: tek
# atışta güven doğruyu yanlıştan ayırmıyor (0,891 / 0,872), 3'lü oylamada fark
# 0,254'e çıkıyor ve 3/3 birleşen sorularda doğruluk %87,5. Bedeli ~3 kat süre.
VARSAYILAN_DENEME = 3
# Oylamalı koşuda güven dağılımı genişliyor; bu eşik risk-kapsama eğrisinden
# okundu (0,70 → kapsama %40, doğruluk %87,5).
VARSAYILAN_INCELEME_ESIGI = 0.70


def _cozucu_kur(argumanlar, *, motor_gerekli: bool):
    from .cozucu import Ayarlar, Cozucu
    from .motor import MotorHatasi, motor_yukle

    secilen = _motor_turu(argumanlar)
    motor = None
    if motor_gerekli and secilen != "yok":
        try:
            motor = motor_yukle(secilen)
        except MotorHatasi as exc:
            print(f"Uyarı: motor kurulamadı ({exc}). Model olmadan devam ediliyor.",
                  file=sys.stderr)
    varsayilan = Ayarlar()
    sicaklik = getattr(argumanlar, "sicaklik", None)
    ayarlar = Ayarlar(
        ornek_sayisi=getattr(argumanlar, "ornek_sayisi", 3),
        oz_kontrol=getattr(argumanlar, "oz_kontrol", False),
        sicaklik=varsayilan.sicaklik if sicaklik is None else sicaklik,
        deneme_sayisi=getattr(argumanlar, "deneme", None) or VARSAYILAN_DENEME,
        inceleme_esigi=VARSAYILAN_INCELEME_ESIGI,
    )
    return Cozucu.kur(
        _kok(argumanlar),
        motor=motor,
        gomme_yukle=not getattr(argumanlar, "gommesiz", False),
        ayarlar=ayarlar,
    )


# --- komutlar ---------------------------------------------------------------


def _cmd_ornek_ekle(argumanlar) -> int:
    from .depo import Depo
    from .hafiza.etiketleme import bloklari_ayristir, kural_ile_etiketle
    from .modeller import Ornek

    kok = _kok(argumanlar)
    depo = Depo(kok / "biyo.db")

    kayitlar: list[dict] = []
    if argumanlar.dosya:
        for yol in argumanlar.dosya:
            metin = Path(yol).read_text(encoding="utf-8")
            if yol.endswith(".jsonl"):
                kayitlar.extend(
                    json.loads(s) for s in metin.splitlines() if s.strip()
                )
            elif yol.endswith(".json"):
                veri = json.loads(metin)
                kayitlar.extend(veri if isinstance(veri, list) else [veri])
            else:
                bulunan = bloklari_ayristir(metin)
                if not bulunan:
                    print(f"{yol}: 'SORU: … ÇÖZÜM: …' bloğu bulunamadı.", file=sys.stderr)
                kayitlar.extend(bulunan)
    elif argumanlar.soru and argumanlar.cozum:
        kayitlar.append(
            {
                "soru": argumanlar.soru,
                "cozum": argumanlar.cozum,
                "cevap": argumanlar.cevap or "",
            }
        )
    else:
        print("En az bir --dosya ya da --soru/--cozum çifti verin.", file=sys.stderr)
        return 2

    ornekler = []
    atlanan = 0
    for kayit in kayitlar:
        konu = str(kayit.get("konu") or "")
        tur = str(kayit.get("cozum_turu") or "")
        if not konu or not tur:
            kural_konu, kural_tur = kural_ile_etiketle(
                str(kayit.get("soru", "")), str(kayit.get("cozum", ""))
            )
            konu = konu or kural_konu
            tur = tur or kural_tur
        ornek = Ornek(
            soru=str(kayit.get("soru", "")).strip(),
            cozum=str(kayit.get("cozum", "")).strip(),
            cevap=str(kayit.get("cevap", "")).strip(),
            cevap_turu=str(kayit.get("cevap_turu") or "acik_uclu"),
            secenekler=dict(kayit.get("secenekler") or {}),
            konu=konu,
            cozum_turu=tur,
            etiketler=list(kayit.get("etiketler") or []),
            kaynak=str(kayit.get("kaynak") or (argumanlar.kaynak or "")),
            # Etiketi kim koyduysa o yazılmalı: `paket-al` çıktısı `cozum_turu`
            # taşıdığı için, bu alan okunmasaydı binlerce örnek insan gözden
            # geçirmiş gibi "elle" işaretlenirdi.
            etiket_kaynagi=str(
                kayit.get("etiket_kaynagi")
                or ("kural" if not kayit.get("cozum_turu") else "elle")
            ),
            # Görüntü imzası: `paket-al` görselleri depoya yazıp imzayı buraya
            # koyuyor. Alan okunmazsa paket görselleri sessizce kaybolur.
            gorsel=str(kayit.get("gorsel") or ""),
        )
        if not ornek.soru or not ornek.cozum:
            atlanan += 1
            continue
        ornekler.append(ornek)

    eklenen, guncellenen, yazilamayan = _ornekleri_yaz(
        depo, ornekler, uzerine_yaz=argumanlar.uzerine_yaz
    )
    atlanan += yazilamayan
    depo.denetim_yaz("ornek_ekle", f"eklenen={eklenen} guncellenen={guncellenen}")
    print(f"Eklendi: {eklenen} · Güncellendi: {guncellenen} · Atlandı: {atlanan}")
    print(f"Toplam örnek: {depo.ornek_sayisi()}")
    if not argumanlar.indekssiz:
        _indeksi_kur(kok, gommesiz=argumanlar.gommesiz)
    return 0


def _ornekleri_yaz(depo, ornekler: list, *, uzerine_yaz: bool) -> tuple[int, int, int]:
    """Örnekleri depoya yazar → (eklenen, güncellenen, atlanan).

    `ornek-ekle` ve `paket-al --uygula` aynı işi yaptığı için tek yerde:
    ikisinde de yinelenen soru sessizce yutulmamalı, sayılmalı.
    """
    eklenen = guncellenen = atlanan = 0
    onceki = depo.ornek_sayisi()
    for ornek in ornekler:
        try:
            depo.ornek_ekle(ornek, uzerine_yaz=uzerine_yaz)
        except ValueError as exc:
            atlanan += 1
            print(f"Atlandı: {exc}", file=sys.stderr)
            continue
        simdiki = depo.ornek_sayisi()
        if simdiki > onceki:
            eklenen += 1
        else:
            guncellenen += 1
        onceki = simdiki
    return eklenen, guncellenen, atlanan


def _indeksi_kur(kok: Path, *, gommesiz: bool) -> None:
    from .depo import Depo
    from .gomme import gomlemci_yukle
    from .hafiza.indeks import OrnekIndeksi

    depo = Depo(kok / "biyo.db")
    gomlemci = None if gommesiz else gomlemci_yukle()
    if gomlemci is None and not gommesiz:
        print("Not: gömme modeli yüklenemedi; indeks yalnız sözcüksel (BM25) olacak.",
              file=sys.stderr)
    ornekler = depo.ornekler()
    if gomlemci is not None and len(ornekler) > 200:
        # Gömme çağrısı ilerleme çubuğu basmıyor; binlerce örnekte kullanıcı
        # dakikalarca çıktısız kalıyordu.
        print(f"{len(ornekler)} örnek gömülüyor, bu birkaç dakika sürebilir…")
    indeks = OrnekIndeksi.kur(ornekler, gomlemci)
    indeks.kaydet(kok / "indeks")
    print(
        f"İndeks kuruldu: {len(indeks)} örnek · "
        f"anlamsal katman: {'var' if indeks.anlamsal_hazir else 'yok'}"
    )


def _alinacak_dosyalar(ham_yollar: list[str]) -> list[Path]:
    """Verilen yolları işlenecek dosya listesine açar.

    Dizinler özyinelemeli taranır ve yalnız DESTEKLENEN uzantılar alınır:
    bir kitaplık klasöründe kapak görselleri, `.DS_Store` ve not dosyaları
    olur; hepsini ayrıştırıcıya vermek her koşuda onlarca sahte hata üretirdi.
    Gizli dosya ve dizinler atlanır.
    """
    from .alim.cikarim import DESTEKLENEN_UZANTILAR

    dosyalar: list[Path] = []
    for ham in ham_yollar:
        yol = Path(ham).expanduser()
        if yol.is_dir():
            for aday in sorted(yol.rglob("*")):
                if aday.is_file() and aday.suffix.casefold() in DESTEKLENEN_UZANTILAR:
                    if any(p.startswith(".") for p in aday.relative_to(yol).parts):
                        continue
                    dosyalar.append(aday)
        else:
            # Açıkça verilen tek dosya uzantısına bakılmadan denenir: kullanıcı
            # ne istediğini biliyor, hata mesajını `metni_cikar` versin.
            dosyalar.append(yol)
    # Aynı dosya iki kez verilmişse (hem doğrudan hem klasör içinden) bir kez işle.
    return list(dict.fromkeys(dosyalar))


def _cmd_al(argumanlar) -> int:
    """Kitap/çözüm kaynağından referans örnek alır.

    Varsayılan **önizleme**: `--uygula` verilmedikçe hiçbir şey yazılmaz.
    Kitap taraması gürültülüdür; yanlış ayrıştırılmış bir çözümün kalıcı
    referans örneğe dönüşmesi modeli sürekli yanlış yönlendirir.

    Dizin verilebilir: altındaki desteklenen dosyalar özyinelemeli taranır.
    """
    from .alim import AlimHatasi, adaylari_cikar, metni_cikar
    from .depo import Depo
    from .hafiza.etiketleme import kural_ile_etiketle
    from .modeller import Ornek

    kok = _kok(argumanlar)
    depo = Depo(kok / "biyo.db") if argumanlar.uygula else None

    tum_adaylar: list[dict] = []
    eklenen = guncellenen = atlanan = elenen = 0
    okunamayan: list[str] = []
    yinelenen_kaynak = 0
    gorulen_imzalar: set[str] = set()

    yollar = _alinacak_dosyalar(argumanlar.dosya)
    if not yollar:
        print("İşlenecek desteklenen dosya bulunamadı.", file=sys.stderr)
        return 1
    if len(yollar) > 1 and not argumanlar.json:
        print(f"{len(yollar)} dosya işlenecek.")

    for ham_yol in yollar:
        try:
            kaynak = metni_cikar(
                ham_yol,
                ad=argumanlar.kaynak or "",
                ocr=argumanlar.ocr,
                ocr_motoru=argumanlar.ocr_motoru,
            )
        except AlimHatasi as exc:
            # Tek bozuk dosya bütün klasörü düşürmemeli: bir kitaplık dolusu
            # taramada bir PDF'in bozuk olması sıradan, işin durması değil.
            okunamayan.append(f"{ham_yol}: {exc}")
            print(f"{ham_yol}: {exc}", file=sys.stderr)
            continue

        # İçerik imzası dosya ADINA değil içeriğe bağlı; yeniden adlandırılan
        # ya da iki klasöre kopyalanmış aynı kitap ikinci kez işlenmez.
        if kaynak.imza in gorulen_imzalar or (
            depo is not None and depo.kaynak_alindi_mi(kaynak.imza)
        ):
            yinelenen_kaynak += 1
            if not argumanlar.json:
                print(f"{kaynak.ad}: aynı içerik daha önce alınmış, atlandı.")
            continue
        gorulen_imzalar.add(kaynak.imza)

        for uyari in kaynak.uyarilar:
            print(f"Uyarı ({kaynak.ad}): {uyari}", file=sys.stderr)

        adaylar = adaylari_cikar(kaynak.metin, kaynak=kaynak)
        # `--json` modunda stdout yalnız JSON olmalı; ilerleme satırları onu
        # ayrıştırılamaz hâle getirirdi.
        print(
            f"{kaynak.ad} [{kaynak.tur}]: {len(adaylar)} aday bulundu",
            file=sys.stderr if argumanlar.json else sys.stdout,
        )

        for aday in adaylar:
            kayit = aday.sozluk()
            kayit["kaynak"] = kaynak.kaynak_adi()
            tum_adaylar.append(kayit)

            if not aday.kullanilabilir_mi() or aday.guven < argumanlar.asgari_guven:
                elenen += 1
                if not argumanlar.json:
                    neden = (
                        "eksik" if not aday.kullanilabilir_mi()
                        else f"güven {aday.guven:.2f}"
                    )
                    print(f"  – atlandı ({neden}): {aday.soru[:70]}")
                continue

            if not argumanlar.json:
                yer = f" [{aday.konum}]" if aday.konum else ""
                print(f"  ✓ {aday.guven:.2f}{yer} {aday.soru[:70]}")

            if depo is None:
                continue
            konu, tur = kural_ile_etiketle(aday.soru, aday.cozum)
            ornek = Ornek(
                soru=aday.soru,
                cozum=aday.cozum,
                cevap=aday.cevap,
                secenekler=aday.secenekler,
                cevap_turu=aday.cevap_turu,
                konu=konu,
                cozum_turu=tur,
                kaynak=f"{kaynak.kaynak_adi()}{' · ' + aday.konum if aday.konum else ''}",
                etiket_kaynagi="kural",
            )
            try:
                onceki = depo.ornek_sayisi()
                depo.ornek_ekle(ornek, uzerine_yaz=argumanlar.uzerine_yaz)
                if depo.ornek_sayisi() > onceki:
                    eklenen += 1
                else:
                    guncellenen += 1
            except ValueError as exc:
                atlanan += 1
                print(f"  ! atlandı: {exc}", file=sys.stderr)

        if depo is not None:
            depo.kaynagi_isaretle(kaynak.imza)

    # Hiçbir kaynak okunamadıysa bu bir başarısızlıktır. Klasör koşusunda
    # bazıları okunduysa değil: bir kitaplıkta tek bozuk PDF olması olağan,
    # o yüzden komut sıfırla döner ama okunamayanları açıkça sayar.
    islenen = len(gorulen_imzalar)
    if okunamayan and not islenen:
        return 1

    if argumanlar.json:
        print(json.dumps(tum_adaylar, ensure_ascii=False, indent=2))
        return 0

    print(f"\nToplam aday: {len(tum_adaylar)} · elenen: {elenen}")
    if yinelenen_kaynak:
        print(f"Daha önce alınmış kaynak: {yinelenen_kaynak}")
    if okunamayan:
        # Sessiz atlama, "hepsi işlendi" izlenimi verir; sayı açıkça yazılır.
        print(f"Okunamayan dosya: {len(okunamayan)}")
        for satir in okunamayan[:5]:
            print(f"  ! {satir}")
        if len(okunamayan) > 5:
            print(f"  … ve {len(okunamayan) - 5} dosya daha")
    if depo is None:
        print("Önizleme modu — hiçbir şey yazılmadı. Yazmak için: --uygula")
        return 0

    depo.denetim_yaz("alim", f"eklenen={eklenen} guncellenen={guncellenen}")
    print(f"Eklendi: {eklenen} · Güncellendi: {guncellenen} · Çakışan: {atlanan}")
    print(f"Toplam örnek: {depo.ornek_sayisi()}")
    if eklenen or guncellenen:
        _indeksi_kur(kok, gommesiz=argumanlar.gommesiz)
    return 0


def _cmd_indeksle(argumanlar) -> int:
    _indeksi_kur(_kok(argumanlar), gommesiz=argumanlar.gommesiz)
    return 0


def _cmd_coz(argumanlar) -> int:
    cozucu = _cozucu_kur(argumanlar, motor_gerekli=True)
    soru = argumanlar.soru
    if argumanlar.dosya:
        soru = Path(argumanlar.dosya).read_text(encoding="utf-8").strip()
    if not soru:
        print("Çözülecek soru verin (--soru ya da --dosya).", file=sys.stderr)
        return 2

    secenekler = {}
    for parca in argumanlar.secenek or []:
        if "=" not in parca:
            print(f"Şık biçimi 'A=metin' olmalı: {parca}", file=sys.stderr)
            return 2
        harf, metin = parca.split("=", 1)
        secenekler[harf.strip().upper()] = metin.strip()

    gorsel_imza = ""
    if argumanlar.gorsel:
        from .gorsel import GorselDeposu, GorselHatasi

        try:
            gorsel_imza = GorselDeposu(_kok(argumanlar)).yaz(
                Path(argumanlar.gorsel).expanduser().read_bytes()
            )
        except (OSError, GorselHatasi) as exc:
            print(f"Görsel okunamadı: {exc}", file=sys.stderr)
            return 2

    cozum = cozucu.coz(
        soru,
        secenekler=secenekler or None,
        gorsel=gorsel_imza,
        gorsel_modu=argumanlar.gorsel_modu,
    )
    if argumanlar.json:
        print(json.dumps(cozum.sozluk(), ensure_ascii=False, indent=2))
        return 0

    print(f"\n{'=' * 60}")
    for i, adim in enumerate(cozum.adimlar, 1):
        print(f"{i}. {adim}")
    print(f"{'-' * 60}")
    print(f"Cevap  : {cozum.cevap or '(yok)'}")
    print(f"Güven  : {cozum.guven:.2f}{'  [İNCELE]' if cozum.incele else ''}")
    print(f"Yöntem : {cozum.uretim_yontemi}  ·  {cozum.model or 'model yok'}")
    if cozum.gorsel_turu:
        kullanildi = "kullanıldı" if cozum.gorsel_kullanildi else "metin yolu"
        print(
            f"Görsel : {cozum.gorsel_turu} · {kullanildi} · "
            f"{cozum.dogrulama_durumu or 'doğrulanmadı'}"
        )
    if cozum.gorsel_kanit_ozeti:
        print(
            f"Kanıt  : {cozum.gorsel_kanit_ozeti} "
            f"(algılama {cozum.algilama_guveni:.2f})"
        )
    if cozum.kitap_kaynaklari:
        print("Kullanılan ders kitabı kaynakları:")
        for kaynak in cozum.kitap_kaynaklari:
            print(f"  {kaynak}")
    if cozum.kanitlar:
        print("Kullanılan referanslar:")
        for kanit in cozum.kanitlar:
            not_ = kanit.siralama_notu()
            ek = f", {not_}" if not_ else ""
            print(f"  {kanit.etiket} {kanit.kaynak_adi()}  (benzerlik {kanit.skor:.2f}{ek})")
    for uyari in cozum.uyarilar:
        print(f"  ! {uyari}")
    return 0


def _cmd_disa_aktar(argumanlar) -> int:
    from .depo import Depo
    from .gomme import gomlemci_yukle
    from .veri.disa_aktar import egitim_verisi_yaz

    kok = _kok(argumanlar)
    depo = Depo(kok / "biyo.db")
    ornekler = depo.ornekler()
    if not ornekler:
        print("Hafızada örnek yok; önce `ornek-ekle` çalıştırın.", file=sys.stderr)
        return 1

    hedef = Path(argumanlar.cikti or (kok / "egitim" / (argumanlar.etiket or "surum")))
    gomlemci = None if argumanlar.gommesiz else gomlemci_yukle()
    ozet = egitim_verisi_yaz(
        ornekler,
        hedef,
        etiket=argumanlar.etiket or hedef.name,
        kanitli=not argumanlar.kanitsiz,
        kanit_sayisi=argumanlar.kanit_sayisi,
        **(
            {}
            if argumanlar.kanit_azami_adim is None
            else {"kanit_azami_adim": argumanlar.kanit_azami_adim}
        ),
        gomlemci=gomlemci,
    )
    depo.egitim_surumu_ekle(
        ozet.etiket, str(ozet.dizin), ozet.egitim, ozet.dogrulama,
        notlar=f"kanitli={ozet.kanitli}",
    )
    print(
        f"Yazıldı → {ozet.dizin}\n"
        f"  train.jsonl : {ozet.egitim}\n"
        f"  valid.jsonl : {ozet.dogrulama}\n"
        f"  test.jsonl  : {ozet.test} (kör değerlendirme için ham örnek)"
    )
    return 0


def _cmd_degerlendir(argumanlar) -> int:
    from .degerlendirme import kor_kosu
    from .gorsel_zeka import VARSAYILAN_GORSEL_MODU
    from .modeller import Ornek

    cozucu = _cozucu_kur(argumanlar, motor_gerekli=True)
    if argumanlar.test_dosyasi:
        satirlar = Path(argumanlar.test_dosyasi).read_text(encoding="utf-8").splitlines()
        ornekler = [Ornek(**json.loads(s)) for s in satirlar if s.strip()]
    else:
        from .veri.disa_aktar import bol

        _egitim, _dogrulama, ornekler = bol(cozucu.depo.ornekler())
    if not ornekler:
        print("Değerlendirilecek örnek bulunamadı.", file=sys.stderr)
        return 1
    # Süzgeç limitten ÖNCE: tersi olsaydı `--limit 20 --yalniz-gorselli` önce
    # ilk 20 örneği alır, içinde görselli çıkmazsa boş küme verirdi.
    if getattr(argumanlar, "yalniz_gorselli", False):
        ornekler = [o for o in ornekler if o.gorsel]
    elif getattr(argumanlar, "yalniz_gorselsiz", False):
        ornekler = [o for o in ornekler if not o.gorsel]
    if not ornekler:
        print("Süzgeçten sonra örnek kalmadı.", file=sys.stderr)
        return 1
    if argumanlar.limit:
        ornekler = ornekler[: argumanlar.limit]

    def _ilerleme(sira: int, toplam: int, sonuc) -> None:
        isaret = "✓" if sonuc.cevap_dogru else "✗"
        print(f"[{sira}/{toplam}] {isaret} {sonuc.soru[:60]}…", file=sys.stderr)

    ozet = kor_kosu(
        cozucu,
        ornekler,
        ilerleme=_ilerleme if argumanlar.ayrintili else None,
        gorsel_modu=getattr(argumanlar, "gorsel_modu", VARSAYILAN_GORSEL_MODU),
    )
    print(ozet.rapor(esik=argumanlar.esik))
    if argumanlar.cikti:
        Path(argumanlar.cikti).write_text(
            json.dumps(
                {
                    "toplam": ozet.toplam,
                    "dogruluk": ozet.dogruluk,
                    "ortalama_ortusme": ozet.ortalama_ortusme,
                    "tur_bazli": ozet.tur_bazli,
                    "sonuclar": [s.__dict__ for s in ozet.sonuclar],
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"Ayrıntılı sonuç → {argumanlar.cikti}")
    return 0


def _depo_koku() -> Path:
    """Kod deposunun kökü — `olcumler/` orada durur, veri kökünde değil.

    Ölçüm kayıtları git ile SÜRÜMLENMELİ: değerleri tek başlarına değil, hangi
    kod değişikliğinin yanında durduklarında. Veri kökü (`~/.biyo-cozucu`)
    sürüm kontrolü dışında ve `.gitignore`'da `*.db` var; oraya yazmak kaydı
    geçmişsiz bırakırdı.
    """
    return Path(__file__).resolve().parent.parent


def _dilim_yolu(argumanlar) -> Path:
    from .olcum import DILIM_DIZINI

    ad = getattr(argumanlar, "dilim", None) or "dilim-v1"
    if ad.endswith(".json"):
        return Path(ad)
    return _depo_koku() / DILIM_DIZINI / f"{ad}.json"


def _cmd_olcum(argumanlar) -> int:
    """Dondurulmuş dilim üzerinde kör koşu + önceki koşuyla fark raporu."""
    from .degerlendirme import kor_kosu
    from .gorsel_zeka import VARSAYILAN_GORSEL_MODU
    from .olcum import Dilim, OlcumKaydi, farkla, kod_surumu, son_kayit

    kok = _depo_koku()
    cozucu = _cozucu_kur(argumanlar, motor_gerekli=True)
    havuz = cozucu.depo.ornekler()

    if argumanlar.dilimi_dondur:
        from .veri.disa_aktar import bol

        _egitim, _dogrulama, test = bol(havuz)
        if not test:
            print("Dondurulacak test dilimi boş.", file=sys.stderr)
            return 1
        dilim = Dilim.ornekelerden(
            test,
            argumanlar.dilimi_dondur,
            aciklama="bol() test diliminin dondurulmuş hâli",
        )
        yol = dilim.yaz(kok)
        print(f"Dilim donduruldu: {yol} ({len(dilim.imzalar)} soru, imza {dilim.imza()})")
        return 0

    # Etiket zorunlu: etiketsiz bir kayıt, aylar sonra "hangi değişikliğin
    # ölçümü bu?" sorusuna cevap veremeyen ölü bir sayı yığınıdır.
    if not (argumanlar.etiket or "").strip():
        print(
            "--etiket zorunlu (ör. --etiket kalitim-araci): kaydın neyi ölçtüğü "
            "sonradan geri getirilemez.",
            file=sys.stderr,
        )
        return 1

    dilim_yolu = _dilim_yolu(argumanlar)
    if not dilim_yolu.is_file():
        print(
            f"Dilim bulunamadı: {dilim_yolu}\n"
            f"Önce dondur: biyo-cozucu olcum --dilimi-dondur {dilim_yolu.stem}",
            file=sys.stderr,
        )
        return 1
    dilim = Dilim.yukle(dilim_yolu)
    ornekler, eksik = dilim.cozumle(havuz)
    if eksik and not argumanlar.eksige_izin:
        print(
            f"Dilimdeki {len(eksik)} soru hafızada yok; koşu karşılaştırılabilir "
            f"olmaz. Yine de koşmak için --eksige-izin.",
            file=sys.stderr,
        )
        return 1
    if eksik:
        print(f"Uyarı: {len(eksik)} soru eksik, dilim daraltıldı.", file=sys.stderr)
    if not ornekler:
        print("Koşulacak örnek kalmadı.", file=sys.stderr)
        return 1
    if argumanlar.limit:
        ornekler = ornekler[: argumanlar.limit]

    def _ilerleme(sira: int, toplam: int, sonuc) -> None:
        isaret = "✓" if sonuc.cevap_dogru else "✗"
        print(f"[{sira}/{toplam}] {isaret} {sonuc.soru[:60]}…", file=sys.stderr)

    # Görsel modu ölçüme AKTARILMALI: `kor_kosu` parametreyi kabul ediyordu
    # ama `olcum` hiç geçirmiyordu, yani her ölçüm sessizce tek bir modda
    # koşuyordu. Kayda da yazılıyor — iki koşu ancak aynı modda kıyaslanabilir.
    gorsel_modu = getattr(argumanlar, "gorsel_modu", None) or VARSAYILAN_GORSEL_MODU
    ozet = kor_kosu(
        cozucu, ornekler, ilerleme=_ilerleme, gorsel_modu=gorsel_modu
    )
    model = getattr(cozucu.motor, "ad", "") or _motor_turu(argumanlar)
    kayit = OlcumKaydi.ozetten(
        ozet,
        etiket=argumanlar.etiket,
        model=str(model),
        dilim=dilim,
        kod=kod_surumu(kok),
        ayarlar={
            "motor": _motor_turu(argumanlar),
            "deneme": cozucu.ayarlar.deneme_sayisi,
            "sicaklik": cozucu.ayarlar.sicaklik,
            "inceleme_esigi": cozucu.ayarlar.inceleme_esigi,
            "oz_kontrol": cozucu.ayarlar.oz_kontrol,
            "ornek_sayisi": cozucu.ayarlar.ornek_sayisi,
            "gorsel_modu": gorsel_modu,
            "limit": argumanlar.limit or 0,
        },
    )
    yol = kayit.yaz(kok)
    cozucu.depo.kosu_kaydet(
        ozet,
        etiket=argumanlar.etiket,
        model=str(model),
        dilim=dilim.ad,
        dilim_imzasi=dilim.imza(),
        dosya=str(yol.relative_to(kok)),
    )
    print(ozet.rapor(esik=argumanlar.esik))
    print(f"\nÖlçüm kaydı → {yol.relative_to(kok)}")

    onceki = son_kayit(kok, haric=yol)
    if onceki is None:
        print("\nKarşılaştırılacak önceki koşu yok — bu kayıt taban olarak kullanılacak.")
        return 0
    fark = farkla(onceki, kayit)
    print("\n" + fark.rapor())
    sorunlar = fark.gerileme(tolerans=argumanlar.tolerans)
    if sorunlar:
        print("\nGERİLEME:", file=sys.stderr)
        for sorun in sorunlar:
            print(f"  - {sorun}", file=sys.stderr)
        if argumanlar.kapi:
            return 1
    return 0


def _cmd_olcum_fark(argumanlar) -> int:
    """İki ölçüm kaydını karşılaştırır (koşu yapmaz)."""
    from .olcum import OlcumKaydi, farkla

    try:
        onceki = OlcumKaydi.oku(Path(argumanlar.onceki))
        yeni = OlcumKaydi.oku(Path(argumanlar.yeni))
    except (OSError, ValueError, TypeError) as exc:
        print(f"Ölçüm kaydı okunamadı: {exc}", file=sys.stderr)
        return 1
    fark = farkla(onceki, yeni)
    print(fark.rapor())
    sorunlar = fark.gerileme(tolerans=argumanlar.tolerans)
    if sorunlar:
        print("\nGERİLEME:", file=sys.stderr)
        for sorun in sorunlar:
            print(f"  - {sorun}", file=sys.stderr)
        if argumanlar.kapi:
            return 1
    return 0


def _cmd_kalibre(argumanlar) -> int:
    """Tür bazlı güven çarpanlarını DOĞRULAMA diliminden öğrenir.

    Neden test dilimi değil: tabloyu test kümesinden öğrenip aynı kümede
    ölçmek, ölçümü kendi kendini doğrulayan bir şeye çevirir. Doğrulama
    dilimi zaten bunun için ayrılmış.
    """
    from .cozucu import KALIBRASYON_DOSYASI
    from .degerlendirme import kor_kosu
    from .veri.disa_aktar import bol

    cozucu = _cozucu_kur(argumanlar, motor_gerekli=True)
    # Diskte tablo varsa onu YOK SAY: kalibre edilmiş güvenle kalibrasyon
    # öğrenmek çarpanları üst üste bindirir ve her koşuda güveni daha da
    # aşağı çeker.
    cozucu.ayarlar.tur_guvenilirligi = {}
    _egitim, dogrulama, _test = bol(cozucu.depo.ornekler())
    if argumanlar.limit:
        dogrulama = dogrulama[: argumanlar.limit]
    if not dogrulama:
        print("Doğrulama dilimi boş.", file=sys.stderr)
        return 1

    print(f"{len(dogrulama)} doğrulama sorusunda kalibrasyon koşusu…", file=sys.stderr)
    ozet = kor_kosu(cozucu, dogrulama)

    asgari = argumanlar.asgari_ornek
    tablo: dict[str, float] = {}
    # Tablo, çarpanın UYGULANACAĞI anahtara göre öğrenilir: modelin kendi tür
    # tahmini. `ozet.tur_bazli` referans türe göre gruplanır (rapor öyle
    # okunmalı) ama etiketleyici 217 soruda 29 kez yanılıyor; tabloyu referans
    # türle öğrenip tahmin türüyle uygulamak o sorularda yanlış türün
    # çarpanını bindiriyordu.
    uretilen_bazli: dict[str, dict[str, float]] = {}
    for sonuc in ozet.sonuclar:
        anahtar = sonuc.uretilen_turu or sonuc.cozum_turu
        kayit = uretilen_bazli.setdefault(anahtar, {"adet": 0.0, "dogru": 0.0})
        kayit["adet"] += 1
        kayit["dogru"] += 1 if sonuc.cevap_dogru else 0
    for kayit in uretilen_bazli.values():
        kayit["dogruluk"] = kayit["dogru"] / kayit["adet"] if kayit["adet"] else 0.0

    for tur, veri in uretilen_bazli.items():
        adet = int(veri["adet"])
        if adet < asgari:
            # Az örnekli türde ölçülen doğruluk gürültü; çarpan yazmak
            # sistemi rastgele bir türde susturmak olurdu.
            continue
        dogruluk = veri["dogruluk"]
        # Çarpan doğrudan doğruluk DEĞİL: güven zaten 0,9 bandında, çarpanı
        # 0,18 yapmak o türü tümden susturur. Hedef sıralamayı korumak —
        # en iyi tür 1,0'da kalsın, zayıf tür oranla insin.
        tablo[tur] = round(min(1.0, dogruluk / max(ozet.dogruluk, 1e-6)), 3)

    yol = _kok(argumanlar) / KALIBRASYON_DOSYASI
    yol.write_text(
        json.dumps(
            {
                "olculen_dogruluk": round(ozet.dogruluk, 4),
                "ornek_sayisi": ozet.toplam,
                # Köken: tablo yalnız öğrenildiği modelle anlamlı. Model adı
                # olmadan bir tablo, model değişse bile sessizce uygulanmaya
                # devam ediyordu.
                "model": str(getattr(cozucu.motor, "ad", "") or ""),
                "tarih": __import__("datetime").date.today().isoformat(),
                "anahtar": "uretilen_turu",
                "tur_guvenilirligi": tablo,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Doğrulama doğruluğu: {ozet.dogruluk:.1%} ({ozet.dogru}/{ozet.toplam})")
    print("Tür güvenilirliği (çarpan):")
    for tur, carpan in sorted(tablo.items(), key=lambda x: x[1]):
        adet = int(uretilen_bazli[tur]["adet"])
        dogruluk = uretilen_bazli[tur]["dogruluk"]
        print(f"  {tur:22s} {carpan:.3f}   (doğruluk {dogruluk:.0%}, {adet} örnek)")
    atlanan = [t for t in uretilen_bazli if t not in tablo]
    if atlanan:
        print(f"Az örnekli olduğu için atlanan türler: {', '.join(sorted(atlanan))}")
    print(f"Kalibrasyon → {yol}")
    return 0


def _cmd_durum(argumanlar) -> int:
    from .depo import Depo
    from .hafiza.indeks import OrnekIndeksi

    kok = _kok(argumanlar)
    depo = Depo(kok / "biyo.db")
    ozet = depo.ozet()
    print(f"Veri kökü : {kok}")
    print(f"Örnek     : {ozet['ornek']}")
    print(f"Çözüm     : {ozet['cozum']}")
    print(f"Önbellek  : {ozet['onbellek']} girdi · {ozet['onbellek_isabeti']} isabet")
    indeks_dizini = kok / "indeks"
    if OrnekIndeksi.hazir_mi(indeks_dizini):
        indeks = OrnekIndeksi.yukle(indeks_dizini)
        print(
            f"İndeks    : {len(indeks)} örnek · "
            f"anlamsal {'var' if indeks.anlamsal_hazir else 'yok'} "
            f"({indeks.gomme_modeli or '—'})"
        )
    else:
        print("İndeks    : kurulmamış (`biyo-cozucu indeksle`)")
    from .alim import kuyruk as kuyruk_birimi

    kuyruk_ozeti = kuyruk_birimi.ozet(kok)
    if kuyruk_ozeti.dosya_sayisi:
        print(
            f"Kuyruk    : {kuyruk_ozeti.bekleyen} bekleyen · "
            f"{kuyruk_ozeti.onayli} onaylı ({kuyruk_ozeti.dosya_sayisi} dosya)"
        )
    if ozet["konu_dagilimi"]:
        print("Konular   :")
        for konu, adet in list(ozet["konu_dagilimi"].items())[:10]:
            print(f"  {konu:32s} {adet}")
    if ozet["cozum_turu_dagilimi"]:
        print("Çözüm türü:")
        for tur, adet in ozet["cozum_turu_dagilimi"].items():
            print(f"  {tur:32s} {adet}")

    from .kapsam import kapsami_cikar

    print()
    print(kapsami_cikar(depo.kapsam_matrisi()).metin())
    return 0


def _cmd_arsiv_coz(argumanlar) -> int:
    """Soru Kesici arşivindeki soruları çözer.

    Varsayılan **önizleme**: `--coz` verilmedikçe yalnız arşivin künyesi
    yazılır. Çözme, soru başına bir model çağrısı demek; 1200 soruluk bir
    arşivde bu saatlerce sürebilir, yanlışlıkla başlatılmamalı.
    """
    from .alim import AlimHatasi
    from .alim.soru_kesici import arsivi_ac, ozet
    from .gorsel import GorselDeposu, GorselHatasi

    kok = _kok(argumanlar)
    try:
        with arsivi_ac(argumanlar.arsiv) as (_veri_kok, sorular):
            kunye = ozet(sorular)
            print(f"Arşiv: {Path(argumanlar.arsiv).name}")
            print(
                f"Soru: {kunye['soru']} · görselli: {kunye['gorselli']} · "
                f"şıklı: {kunye['sikli']}"
            )
            if kunye["kaynaklar"]:
                print("Kaynak: " + ", ".join(kunye["kaynaklar"][:3]))
            for konu, adet in list(kunye["konu_dagilimi"].items())[:8]:
                print(f"  {konu:34s} {adet}")

            if argumanlar.asgari_guven:
                sorular = [s for s in sorular if s.guven >= argumanlar.asgari_guven]
            if argumanlar.limit:
                sorular = sorular[: argumanlar.limit]

            if not argumanlar.coz:
                print(f"\nÇözülecek soru: {len(sorular)}")
                print("Önizleme modu — hiçbir soru çözülmedi. Çözmek için: --coz")
                return 0

            cozucu = _cozucu_kur(argumanlar, motor_gerekli=True)
            gorsel_deposu = GorselDeposu(kok)
            cozulen = incelemeye_dusen = hatali = 0
            print(f"\n{len(sorular)} soru çözülüyor…")
            for sira, soru in enumerate(sorular, 1):
                gorsel_imza = ""
                if soru.gorsel_yolu is not None:
                    try:
                        gorsel_imza = gorsel_deposu.yaz(soru.gorsel_yolu.read_bytes())
                    except (OSError, GorselHatasi) as exc:
                        print(f"  ! {soru.dosya}: görsel alınamadı ({exc})",
                              file=sys.stderr)
                try:
                    cozum = cozucu.coz(
                        soru.soru,
                        secenekler=soru.secenekler or None,
                        gorsel=gorsel_imza,
                        # Kesme güveni çözüm güvenine tavan olur: kötü kesilmiş
                        # bir soru yüksek güvenle cevaplanmamalı.
                        kaynak_guveni=soru.guven,
                    )
                except Exception as exc:  # noqa: BLE001 - tek soru koşuyu düşürmesin
                    hatali += 1
                    print(f"  ! {soru.dosya}: {exc}", file=sys.stderr)
                    continue
                cozulen += 1
                incelemeye_dusen += bool(cozum.incele)
                isaret = "?" if cozum.incele else "✓"
                print(f"  {isaret} [{sira}/{len(sorular)}] {soru.soru[:64]}")

            print(
                f"\nÇözülen: {cozulen} · incelemeye düşen: {incelemeye_dusen} · "
                f"hatalı: {hatali}"
            )
            print("Çözümler arayüzdeki Çözümler sekmesinde onayını bekliyor;")
            print("onayladıkların referans örneğe dönüşür.")
    except AlimHatasi as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


def _cmd_paket_al(argumanlar) -> int:
    """Hazır soru-çözüm paketini referans örneğe çevirir.

    Varsayılan **önizleme**: `--jsonl` ya da `--uygula` verilmedikçe hiçbir şey
    yazılmaz, yalnız paketin künyesi basılır. Bin küstü örneği hafızaya almak
    geri alınması zahmetli bir iş; konu eşlemesi ve kalite bayrakları önce
    gözden geçirilebilmeli.
    """
    from .alim import AlimHatasi
    from .alim.soru_kesici import gecici_acilmis
    from .depo import Depo
    from .gorsel import GorselDeposu, GorselHatasi
    from .veri.paketler import PaketHatasi, kayitlari_cevir

    kok = _kok(argumanlar)
    try:
        with gecici_acilmis(argumanlar.arsiv) as arsiv_kok:
            kunye_yolu = _paket_kunyesi(arsiv_kok)
            veri = json.loads(kunye_yolu.read_text(encoding="utf-8"))
            if not isinstance(veri, dict):
                raise PaketHatasi(f"{kunye_yolu.name}: beklenen bir JSON nesnesi.")
            kayitlar = kayitlari_cevir(
                veri,
                kaynak=argumanlar.kaynak or "",
                tur="" if argumanlar.tur == "oto" else argumanlar.tur,
                sablonu_ayikla=argumanlar.sablonu_ayikla,
            )
            secilen = _paketi_suz(kayitlar, guven=argumanlar.guven)
            _paket_kunyesini_bas(
                Path(argumanlar.arsiv).name, kunye_yolu.name, kayitlar, secilen
            )
            if not argumanlar.jsonl and not argumanlar.uygula:
                print("\nÖnizleme modu — hiçbir şey yazılmadı.")
                print("Yazmak için: --jsonl <yol> ve/veya --uygula")
                return 0

            gorsel_hatasi = 0
            if not argumanlar.gorselsiz:
                depo_gorsel = GorselDeposu(kok)
                for kayit in secilen:
                    if not kayit.gorsel_yolu:
                        continue
                    try:
                        veri_baytlari = (arsiv_kok / kayit.gorsel_yolu).read_bytes()
                        kayit.ornek.gorsel = depo_gorsel.yaz(veri_baytlari)
                    except (OSError, GorselHatasi):
                        # Tek tek basmak 150 görselde okunmaz bir duvar üretirdi.
                        gorsel_hatasi += 1
                if gorsel_hatasi:
                    print(
                        f"Görsel yazılamadı: {gorsel_hatasi} kayıt "
                        "(Pillow kurulu mu? uv sync --extra vizyon)",
                        file=sys.stderr,
                    )

            if argumanlar.jsonl:
                hedef = Path(argumanlar.jsonl).expanduser()
                hedef.parent.mkdir(parents=True, exist_ok=True)
                with hedef.open("w", encoding="utf-8") as dosya:
                    for kayit in secilen:
                        satir = {
                            anahtar: deger
                            for anahtar, deger in kayit.ornek.sozluk().items()
                            if anahtar not in {"id", "olusturma"} and deger
                        }
                        dosya.write(json.dumps(satir, ensure_ascii=False) + "\n")
                print(f"\nJSONL yazıldı: {hedef} ({len(secilen)} örnek)")

            if argumanlar.uygula:
                depo = Depo(kok / "biyo.db")
                eklenen, guncellenen, atlanan = _ornekleri_yaz(
                    depo,
                    [k.ornek for k in secilen],
                    uzerine_yaz=argumanlar.uzerine_yaz,
                )
                depo.denetim_yaz(
                    "paket_al", f"eklenen={eklenen} guncellenen={guncellenen}"
                )
                print(
                    f"Eklendi: {eklenen} · Güncellendi: {guncellenen} · "
                    f"Atlandı: {atlanan}"
                )
                print(f"Toplam örnek: {depo.ornek_sayisi()}")
                if not argumanlar.indekssiz:
                    _indeksi_kur(kok, gommesiz=argumanlar.gommesiz)
    except (AlimHatasi, PaketHatasi) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except json.JSONDecodeError as exc:
        print(f"Paket künyesi okunamadı: {exc}", file=sys.stderr)
        return 2
    return 0


def _cmd_jsonl_al(argumanlar) -> int:
    """Serbest şemalı JSONL soru dosyalarını referans örneğe çevirir.

    `paket-al` üç belirli paket şemasını ele alıyor; bu komut alan adlarını
    aday listelerinden bulan genel dönüştürücüyü (`veri.genel_paket`)
    kullanıyor ve birden çok dosyayı tek seferde alabiliyor.

    Aynı disiplin: varsayılan **önizleme**, yazmak için `--uygula` gerekiyor.
    """
    from .depo import Depo
    from .veri.genel_paket import jsonl_cevir
    from .veri.paketler import PaketHatasi

    kok = _kok(argumanlar)
    yollar: list[Path] = []
    for desen in argumanlar.dosyalar:
        genisletilmis = sorted(Path().glob(desen)) if any(
            j in desen for j in "*?["
        ) else [Path(desen)]
        yollar.extend(p for p in genisletilmis if p.suffix.lower() in {".jsonl", ".json"})
    if not yollar:
        print("Alınacak JSONL dosyası bulunamadı.", file=sys.stderr)
        return 1

    tum_kayitlar = []
    print(f"{'dosya':46} {'kayıt':>7} {'konusuz':>8} {'bayraklı':>9}")
    for yol in yollar:
        try:
            kayitlar = jsonl_cevir(yol, kaynak=argumanlar.kaynak or yol.stem)
        except PaketHatasi as exc:
            print(f"{yol.name}: {exc}", file=sys.stderr)
            continue
        secilen = _paketi_suz(kayitlar, guven=argumanlar.guven)
        konusuz = sum(1 for k in secilen if not k.ornek.konu)
        bayrakli = sum(1 for k in secilen if k.uyarilar)
        print(f"{yol.name[:46]:46} {len(secilen):>7} {konusuz:>8} {bayrakli:>9}")
        tum_kayitlar.extend(secilen)

    if not tum_kayitlar:
        print("Süzgeçten sonra kayıt kalmadı.", file=sys.stderr)
        return 1

    from collections import Counter

    konular = Counter(k.ornek.konu or "(yok)" for k in tum_kayitlar)
    turler = Counter(k.ornek.cozum_turu for k in tum_kayitlar)
    cevap_turleri = Counter(k.ornek.cevap_turu for k in tum_kayitlar)
    print(f"\nToplam çevrilen: {len(tum_kayitlar)}")
    print("Cevap türü:", dict(cevap_turleri))
    print("Çözüm türü:", dict(turler.most_common()))
    print("Konu dağılımı (ilk 10):")
    for konu, adet in konular.most_common(10):
        print(f"  {adet:>5}  {konu}")

    if not argumanlar.uygula:
        print("\nÖnizleme modu — hiçbir şey yazılmadı. Yazmak için: --uygula")
        return 0

    depo = Depo(kok / "biyo.db")
    onceki = depo.ornek_sayisi()
    eklenen, guncellenen, atlanan = _ornekleri_yaz(
        depo, [k.ornek for k in tum_kayitlar], uzerine_yaz=argumanlar.uzerine_yaz
    )
    depo.denetim_yaz("jsonl_al", f"eklenen={eklenen} guncellenen={guncellenen}")
    print(
        f"\nEklendi: {eklenen} · Güncellendi: {guncellenen} · Atlandı: {atlanan}"
    )
    print(f"Toplam örnek: {onceki} → {depo.ornek_sayisi()}")
    if not argumanlar.indekssiz:
        _indeksi_kur(kok, gommesiz=argumanlar.gommesiz)
    return 0


def _paket_kunyesi(kok: Path):
    """Paketin yapılandırılmış künyesini bulur (en büyük .json)."""
    from .veri.paketler import PaketHatasi

    adaylar = [y for y in sorted(kok.rglob("*.json")) if y.is_file()]
    if not adaylar:
        raise PaketHatasi(
            "Pakette .json künyesi bulunamadı. Bu bir soru-çözüm paketi mi?"
        )
    # Paketlerde tek künye var; birden fazlaysa soruları taşıyan en büyüğüdür
    # (yanındakiler kontrol özeti gibi küçük yardımcı dosyalar).
    return max(adaylar, key=lambda y: y.stat().st_size)


# `--guven` kademesinin kabul ettiği güven adları.
_GUVEN_KADEMELERI = {
    "yuksek": {"Yüksek"},
    "orta": {"Yüksek", "Orta"},
    "hepsi": {"Yüksek", "Orta", "Düşük"},
}

# `hepsi` dışında elenen bayraklar: ayrıştırma bütünlüğü bozuk ya da cevabı
# kaynakla çelişen kayıt, hafızaya referans olarak girmemeli.
_ELENEN_BAYRAKLAR = {"eksik_secenek", "cevap_uyusmazligi"}


def _paketi_suz(kayitlar: list, *, guven: str) -> list:
    kabul = _GUVEN_KADEMELERI[guven]
    if guven == "hepsi":
        return list(kayitlar)
    return [
        k
        for k in kayitlar
        if k.guven in kabul and not (_ELENEN_BAYRAKLAR & set(k.uyarilar))
    ]


def _paket_kunyesini_bas(
    arsiv_adi: str, kunye_adi: str, kayitlar: list, secilen: list
) -> None:
    from .veri.paketler import ozet as paket_ozeti

    kunye = paket_ozeti(kayitlar)
    uzunluk = kunye["cozum_uzunlugu"]
    print(f"Paket: {arsiv_adi} · künye: {kunye_adi}")
    print(
        f"Soru: {kunye['soru']} · şıklı: {kunye['sikli']} · "
        f"cevaplı: {kunye['cevapli']} · görselli: {kunye['gorselli']}"
    )
    print(
        f"Çözüm uzunluğu: ort {uzunluk['ortalama']} · azami {uzunluk['azami']} · "
        f"kanıt olarak kırpılacak: {uzunluk['kirpilacak']}"
    )
    print("Konu dağılımı:")
    for konu, adet in list(kunye["konu_dagilimi"].items())[:10]:
        print(f"  {konu:34s} {adet}")
    print("Çözüm türü dağılımı:")
    for tur, adet in kunye["tur_dagilimi"].items():
        print(f"  {tur:34s} {adet}")
    if kunye["uyarilar"]:
        print("Kalite işaretleri:")
        for bayrak, adet in kunye["uyarilar"].items():
            print(f"  {bayrak:34s} {adet}")
    print(f"\nSüzgeçten geçen: {len(secilen)}/{len(kayitlar)}")


def _cmd_set_listele(argumanlar) -> int:
    """Kayıtlı açık veri setlerini ve her birinin durumunu gösterir."""
    from .veri.acik_setler import KAYITLI_SETLER

    print(f"{'Set':<14} {'Dil':<4} {'Eğitim':<8} Durum")
    for veri_seti in KAYITLI_SETLER.values():
        egitim = "evet" if veri_seti.egitime_uygun else "hayır"
        print(
            f"{veri_seti.ad:<14} {veri_seti.dil:<4} {egitim:<8} "
            f"{veri_seti.durum_ozeti()}   ({veri_seti.lisans})"
        )
        engel = veri_seti.engel()
        if engel:
            print(f"{'':<14} → {engel}")
    return 0


def _cmd_set_al(argumanlar) -> int:
    """Açık bir veri setinden referans örnek üretir (önizleme ya da yazma)."""
    from .depo import Depo
    from .veri.acik_setler import LisansHatasi, VeriSetiHatasi, ornekleri_al

    try:
        ornekler = ornekleri_al(
            argumanlar.ad,
            bolum=argumanlar.bolum,
            amac=argumanlar.amac,
            limit=argumanlar.limit,
            yalniz_biyoloji=not argumanlar.tum_konular,
        )
    except (LisansHatasi, VeriSetiHatasi, NotImplementedError, KeyError) as exc:
        print(str(exc).strip("'"), file=sys.stderr)
        return 2

    print(f"{len(ornekler)} örnek üretildi ({argumanlar.ad}).")
    if not argumanlar.uygula:
        for ornek in ornekler[:3]:
            print(f"  · {ornek.soru[:90]}")
        print("Hiçbir şey yazılmadı. Hafızaya almak için --uygula ekleyin.")
        return 0

    depo = Depo(_kok(argumanlar) / "biyo.db")
    eklenen = atlanan = 0
    for ornek in ornekler:
        try:
            depo.ornek_ekle(ornek)
            eklenen += 1
        except ValueError:
            atlanan += 1  # aynı soru zaten hafızada
    print(f"Eklenen: {eklenen} · Atlanan (yinelenen): {atlanan}")
    if eklenen:
        _indeksi_kur(_kok(argumanlar), gommesiz=argumanlar.gommesiz)
    return 0


def _cmd_kitap_al(argumanlar) -> int:
    """Ders kitabı PDF'ini pasajlara çevirip hafızaya yazar."""
    from .depo import Depo
    from .veri.kitap import kitabi_al

    kok = _kok(argumanlar)
    depo = Depo(kok / "biyo.db")
    onceki = depo.pasaj_say(kaynak=argumanlar.kaynak)
    if onceki:
        print(f"'{argumanlar.kaynak}' için {onceki} pasaj zaten kayıtlı; "
              "aynı metinler atlanacak.")

    son_ozet = None

    def _ilerleme(no: int, son: int, ozet) -> None:
        # Uzun koşuda tek satırlık ilerleme; ayrıntı sona saklanıyor.
        print(
            f"\r[{no}/{son}] pasaj {ozet.pasaj} · atlanan {ozet.atlanan} · "
            f"OCR {ozet.ocr_sayfasi} · boş {ozet.bos_sayfa} · "
            f"OCR boş {ozet.ocr_bos}",
            end="", file=sys.stderr, flush=True,
        )

    try:
        for ozet in kitabi_al(
            argumanlar.pdf,
            depo,
            kaynak=argumanlar.kaynak,
            baslangic=argumanlar.baslangic,
            bitis=argumanlar.bitis or None,
            ocr=argumanlar.ocr,
            ocr_motoru=argumanlar.ocr_motoru,
            ilerleme=_ilerleme,
        ):
            son_ozet = ozet
    except KeyboardInterrupt:
        # Yarıda kesmek veri kaybettirmez: her sayfa anında yazıldı.
        print("\nDurduruldu; okunan sayfalar hafızada kaldı.", file=sys.stderr)
    except (OSError, RuntimeError, FileNotFoundError) as exc:
        print(f"\nKitap alınamadı: {exc}", file=sys.stderr)
        return 1
    print(file=sys.stderr)

    if son_ozet is None:
        print("Hiç pasaj üretilmedi (sayfalar boş ya da aralık geçersiz).")
        return 1
    print(
        f"Okunan sayfa: {son_ozet.okunan_sayfa}/{son_ozet.sayfa} · "
        f"yeni pasaj: {son_ozet.pasaj} · zaten kayıtlı: {son_ozet.atlanan} · "
        f"OCR'lanan: {son_ozet.ocr_sayfasi} · boş: {son_ozet.bos_sayfa} · "
        f"OCR boş döndü: {son_ozet.ocr_bos} · hatalı: {son_ozet.hata}"
    )
    # Sessiz kayba karşı açık uyarı: OCR'lanan sayfaların büyük kısmı boş
    # döndüyse koşu "başarılı" görünür ama kitap alınmamıştır.
    fazla_ocr_bosu = bool(
        son_ozet.ocr_bos
        and son_ozet.ocr_bos > son_ozet.ocr_sayfasi * 0.2
    )
    if fazla_ocr_bosu:
        print(
            f"UYARI: OCR'lanan {son_ozet.ocr_sayfasi} sayfanın "
            f"{son_ozet.ocr_bos}'i boş döndü. OCR arka ucu düşmüş olabilir; "
            "eksik sayfalar için komutu yeniden çalıştırın "
            "(kayıtlı pasajlar atlanır).",
            file=sys.stderr,
        )
    print(f"Toplam pasaj ('{argumanlar.kaynak}'): {depo.pasaj_say(kaynak=argumanlar.kaynak)}")
    if not argumanlar.indekssiz:
        print("Pasaj indeksi bir sonraki çözümde kendiliğinden kurulacak.")
    # Her sayfa anında yazıldığı için kısmi sonuçlar güvende. Bununla birlikte
    # çağıran (ör. 40 sayfalık Campbell dilimleyicisi) eksik grubu yeniden
    # deneyebilsin diye kısmi okuma kaybını başarı koduyla gizleme. Aynı
    # pasajlar yinelenen olarak atlandığından tüm dilimi yinelemek güvenlidir.
    if son_ozet.hata or fazla_ocr_bosu:
        return 1
    return 0


def _cmd_kitap_listele(argumanlar) -> int:
    from .depo import Depo

    depo = Depo(_kok(argumanlar) / "biyo.db")
    kaynaklar = depo.pasaj_kaynaklari()
    if not kaynaklar:
        print("Hafızada ders kitabı yok. Eklemek için: biyo-cozucu kitap-al <pdf> --kaynak <ad>")
        return 0
    print(f"Toplam pasaj: {depo.pasaj_say()}")
    for ad, adet in kaynaklar.items():
        print(f"  {ad:40s} {adet}")
    return 0


def _cmd_model_kur(argumanlar) -> int:
    """Colab'dan gelen zip'i (birleştirilmiş model veya LoRA adaptörü) kurar."""
    import zipfile

    kaynak = Path(argumanlar.zip).expanduser()
    hedef = Path(argumanlar.hedef or (_kok(argumanlar) / "modeller" / kaynak.stem))
    if not kaynak.is_file():
        print(f"Dosya bulunamadı: {kaynak}", file=sys.stderr)
        return 1
    hedef.mkdir(parents=True, exist_ok=True)
    cozulmus_hedef = hedef.resolve()

    with zipfile.ZipFile(kaynak) as arsiv:
        for uye in arsiv.infolist():
            # zip-slip: arşiv içindeki "../" yolları hedefin dışına yazabilir.
            varis = (cozulmus_hedef / uye.filename).resolve()
            if not str(varis).startswith(str(cozulmus_hedef)):
                print(f"Güvenlik: arşiv hedef dışına yazmaya çalıştı ({uye.filename})",
                      file=sys.stderr)
                return 1
        arsiv.extractall(cozulmus_hedef)

    print(f"Kuruldu → {cozulmus_hedef}")
    print("Kullanmak için:")
    print(f"  export BIYO_MLX_MODEL={cozulmus_hedef}")
    print("  veya adaptör ise: export BIYO_MLX_ADAPTOR=" + str(cozulmus_hedef))
    return 0


def _cmd_sunucu(argumanlar) -> int:
    try:
        import uvicorn
    except ImportError:
        print("Web arayüzü için: uv sync --extra web", file=sys.stderr)
        return 1
    from .webapp import uygulama_kur

    uygulama = uygulama_kur(
        kok=_kok(argumanlar),
        motor_turu=_motor_turu(argumanlar),
        gommesiz=argumanlar.gommesiz,
    )
    uvicorn.run(uygulama, host=argumanlar.adres, port=argumanlar.port)
    return 0


# --- ayrıştırıcı ------------------------------------------------------------


# Tek kuyruk dosyasında bu kadar kayıt olmaz; aşan aralık yazım hatasıdır.
AZAMI_SIRA_ARALIGI = 10_000

# Bu süreyi aşan videolarda yerel döküm önerilmez: 60 dakikalık ses ~10 dakika
# döküm ve ~115 MB WAV demek; 10 saatlik bir ders videosunda bu ~100 dakikaya
# ve ~1 GB'a çıkıyor. Bkz. `colab/02_youtube_dokum.ipynb`.
COLAB_ESIGI_SN = 60 * 60


def _siralari_ayristir(metin: str) -> list[int]:
    """"1,3,5-9" biçimindeki sıra listesini açar."""
    siralar: list[int] = []
    for parca in metin.split(","):
        parca = parca.strip()
        if not parca:
            continue
        if "-" in parca:
            bas, _, son = parca.partition("-")
            bas_no, son_no = int(bas), int(son)
            # Aralık önce SINIRLANIR, sonra açılır: "1-99999999" yazım
            # hatası doğrulamaya varmadan belleği şişirirdi.
            if son_no - bas_no > AZAMI_SIRA_ARALIGI:
                raise ValueError(
                    f"Aralık çok geniş: {parca} (en fazla {AZAMI_SIRA_ARALIGI})"
                )
            siralar.extend(range(bas_no, son_no + 1))
        else:
            siralar.append(int(parca))
    return siralar


def _onbellekli_mi(kok: Path, videolar: list) -> bool:
    """Videoların dökümü zaten önbellekte mi (uyarı gereksiz mi)?"""
    from .alim.youtube import transkript_yolu

    return all(transkript_yolu(kok, v.video_id).is_file() for v in videolar)


def _kuyruk_dosyasi_bul(kok: Path, hedef: str):
    """Hedefi kuyruk dosyasına çevirir: sıra numarası ya da dosya adı."""
    from .alim import kuyruk as kuyruk_birimi

    if hedef.isdigit():
        yollar = kuyruk_birimi.dosyalar(kok)
        sira = int(hedef)
        return yollar[sira - 1] if 1 <= sira <= len(yollar) else None
    return kuyruk_birimi.bul(kok, hedef)


def _indekse_isle(kok: Path, kimlikler: list[int], *, gommesiz: bool) -> None:
    """Yeni örnekleri var olan indekse ARTIMLI işler.

    Tam yeniden kurulum koleksiyondaki her örneği yeniden gömdürür — 9 bin
    örnekte dakikalar; onay akışında bu her onaya ödenemez. İndeks yoksa ya
    da gömlemci uyumsuzsa tam kuruluma düşülür.
    """
    from .depo import Depo
    from .gomme import gomlemci_yukle
    from .hafiza.indeks import OrnekIndeksi

    if not kimlikler:
        return
    dizin = kok / "indeks"
    if not OrnekIndeksi.hazir_mi(dizin):
        _indeksi_kur(kok, gommesiz=gommesiz)
        return
    indeks = OrnekIndeksi.yukle(dizin)
    gomlemci = None if gommesiz else gomlemci_yukle()
    if gomlemci is None and indeks.anlamsal_hazir:
        # Gömlemcisiz tam kurulum anlamsal katmanı SİLERDİ; güncellemeyi
        # atlamak, indeksi bozmaktan iyidir.
        print(
            "Gömme modeli yüklenemedi; indeks güncellenmedi. "
            "`biyo-cozucu indeksle` ile yenileyin.",
            file=sys.stderr,
        )
        return
    depo = Depo(kok / "biyo.db")
    for kimlik in kimlikler:
        ornek = depo.ornek(kimlik)
        if ornek is None:
            continue
        if indeks.icerir(ornek.id):
            basarili = indeks.degistir(ornek, gomlemci)
        else:
            basarili = indeks.ekle(ornek, gomlemci)
        if not basarili:
            print("İndeks gömlemcisi uyumsuz; tam yeniden kurulum yapılıyor…",
                  file=sys.stderr)
            _indeksi_kur(kok, gommesiz=gommesiz)
            return
    indeks.kaydet(dizin)
    print(f"İndeks güncellendi: +{len(kimlikler)} örnek → {len(indeks)}")


def _kuyruk_kaydi(video, aday, yontem: str):
    """SoruAdayi + video künyesinden kuyruk kaydı üretir."""
    from datetime import datetime

    from .alim.kuyruk import KuyrukKaydi
    from .hafiza.etiketleme import kural_ile_etiketle

    konu, tur = kural_ile_etiketle(aday.soru, aday.cozum)
    return KuyrukKaydi(
        soru=aday.soru,
        cozum=aday.cozum,
        cevap=aday.cevap,
        cevap_turu=aday.cevap_turu,
        secenekler=dict(aday.secenekler),
        konu=konu,
        cozum_turu=tur,
        video_id=video.video_id,
        video_basligi=video.baslik,
        kanal=video.kanal,
        url=video.izleme_adresi(),
        kaynak_imzasi=video.imza,
        kaynak=video.kaynak_adi(),
        konum=aday.konum,
        baslangic_sn=aday.baslangic_sn,
        guven=aday.guven,
        dayanak=aday.dayanak,
        yontem=yontem,
        uyarilar=list(aday.uyarilar),
        olusturma=datetime.now().isoformat(timespec="seconds"),
    )


def _cmd_youtube_al(argumanlar) -> int:
    """YouTube soru çözümü videolarını onay KUYRUĞUNA çıkarır.

    Varsayılan **önizleme**: yalnız künye çekilir (saniyeler). `--uygula`
    indirir, yazıya döker, soruları çıkarır ve kuyruğa yazar — hafızaya
    DEĞİL: hafızaya yazım yalnız `kuyruk-onayla` ile olur. Böylece kimse
    20 videoluk bir playlist'i körlemesine başlatmaz ve hiçbir model çıktısı
    insan onayı olmadan referans örneğe dönüşmez.
    """
    from .alim import kuyruk as kuyruk_birimi
    from .alim.cikarim import AlimHatasi
    from .alim.konusma import PENCERE_KARAKTERI, sorulari_cikar
    from .alim.youtube import kunye_getir, videoyu_dok
    from .depo import Depo

    kok = _kok(argumanlar)
    depo = Depo(kok / "biyo.db")

    videolar = []
    for url in argumanlar.url:
        try:
            videolar.extend(kunye_getir(url, limit=argumanlar.limit or 0))
        except AlimHatasi as exc:
            print(f"{url}: {exc}", file=sys.stderr)
    tekil = list({v.video_id: v for v in videolar}.values())
    if argumanlar.limit:
        tekil = tekil[: argumanlar.limit]
    if not tekil:
        return 1

    durumlar: dict[str, str] = {}
    for video in tekil:
        if depo.kaynak_alindi_mi(video.imza):
            durumlar[video.video_id] = "alınmış"
        elif kuyruk_birimi.kuyrukta_mi(kok, video.video_id):
            durumlar[video.video_id] = "kuyrukta"
        else:
            durumlar[video.video_id] = "yeni"

    toplam_sure = sum(v.sure_sn for v in tekil)
    if not argumanlar.json:
        print(f"{len(tekil)} video:")
        for sira, video in enumerate(tekil, start=1):
            sure = (
                f"{int(video.sure_sn) // 60:d}:{int(video.sure_sn) % 60:02d}"
                if video.sure_sn
                else "?"
            )
            print(
                f"  {sira:2d}. [{durumlar[video.video_id]:8s}] {sure:>7s}  "
                f"{(video.baslik or video.video_id)[:64]}"
            )
        if toplam_sure:
            # large-v3-turbo bu makinede kabaca gerçek zamanın 1/6'sı hızında.
            tahmini_dk = max(1, int(toplam_sure / 60 / 6))
            print(f"Toplam süre: {int(toplam_sure) // 60} dk · tahmini döküm: ~{tahmini_dk} dk")
            uzunlar = [v for v in tekil if v.sure_sn > COLAB_ESIGI_SN]
            if uzunlar and not _onbellekli_mi(kok, uzunlar):
                # Kullanıcı bunu bir saat bekledikten sonra değil, şimdi
                # bilmeli: uzun videoda yerel döküm hem çok yavaş hem bellek
                # yiyor (10 saatlik video ≈ 1 GB WAV).
                print(
                    f"\nUyarı: {len(uzunlar)} video {COLAB_ESIGI_SN // 60} dakikadan uzun. "
                    "Yerel döküm çok sürer; Colab'de dökmeniz önerilir:\n"
                    "  1) colab/02_youtube_dokum.ipynb defterini GPU ile çalıştırın\n"
                    "  2) uv run biyo-cozucu transkript-al <inen>.json\n"
                    "  3) bu komutu --uygula ile yeniden çalıştırın (döküm atlanır)",
                    file=sys.stderr,
                )

    if not argumanlar.uygula:
        print("Önizleme — hiçbir şey indirilmedi. İndirme ve döküm için --uygula ekleyin.")
        return 0

    islenecek = [
        v for v in tekil if argumanlar.yeniden or durumlar[v.video_id] == "yeni"
    ]
    atlanan_video = len(tekil) - len(islenecek)
    if not islenecek:
        print("İşlenecek yeni video yok (hepsi alınmış ya da kuyrukta).")
        return 0

    motor = None
    if not argumanlar.kural:
        from .motor import MotorHatasi, motor_yukle

        secilen = _motor_turu(argumanlar)
        if secilen != "yok":
            try:
                motor = motor_yukle(secilen)
            except MotorHatasi as exc:
                print(
                    f"Uyarı: motor kurulamadı ({exc}); kural tabanlı çıkarıma düşülüyor.",
                    file=sys.stderr,
                )

    islenen = 0
    toplam_aday = elenen = 0
    hatalar: list[str] = []
    tum_kayitlar: list[dict] = []
    cikti = sys.stderr if argumanlar.json else sys.stdout
    for video in islenecek:
        ad = video.baslik or video.video_id
        try:
            from .alim.youtube import transkript_yolu

            onbellekli = (
                not argumanlar.yeniden and transkript_yolu(kok, video.video_id).is_file()
            )
            print(
                f"{ad}: {'önbellekteki döküm kullanılıyor' if onbellekli else 'indiriliyor ve yazıya dökülüyor'}…",
                file=cikti,
            )
            def _dokum_ilerlemesi(dilim: int, toplam: int, _ad: str = ad) -> None:
                if toplam > 1:
                    print(f"  {_ad}: döküm {dilim}/{toplam} dilim", file=cikti, flush=True)

            kaynak = videoyu_dok(
                video,
                kok=kok,
                yeniden=argumanlar.yeniden,
                sesi_sakla=argumanlar.sesi_sakla,
                dokum_ilerlemesi=_dokum_ilerlemesi,
            )
            def _cikarim_ilerlemesi(pencere: int, toplam: int, _ad: str = ad) -> None:
                # Uzun videoda çıkarım saatler sürüyor; her pencerede satır
                # basmak da gürültü. Onda birlik adımlarda haber ver.
                adim = max(1, toplam // 10)
                if toplam > 1 and (pencere % adim == 0 or pencere == toplam):
                    print(
                        f"  {_ad}: çıkarım {pencere}/{toplam} pencere",
                        file=cikti, flush=True,
                    )

            adaylar, yontem = sorulari_cikar(
                kaynak,
                motor,
                boyut=argumanlar.pencere or PENCERE_KARAKTERI,
                ilerleme=_cikarim_ilerlemesi,
            )
        except AlimHatasi as exc:
            hatalar.append(f"{video.video_id}: {exc}")
            print(f"{ad}: {exc}", file=sys.stderr)
            continue
        islenen += 1
        uygun = [a for a in adaylar if a.guven >= argumanlar.asgari_guven]
        elenen += len(adaylar) - len(uygun)
        if not uygun:
            print(f"{ad}: aday çıkmadı.", file=cikti)
            continue
        kayitlar = [_kuyruk_kaydi(video, aday, yontem) for aday in uygun]
        yol = kuyruk_birimi.kuyruk_dizini(kok) / kuyruk_birimi.dosya_adi(video.video_id)
        kuyruk_birimi.yaz(yol, kayitlar)
        toplam_aday += len(kayitlar)
        tum_kayitlar.extend(k.sozluk() for k in kayitlar)
        print(f"{ad}: {len(kayitlar)} aday → {yol.name} [{yontem}]", file=cikti)

    if argumanlar.json:
        print(json.dumps(tum_kayitlar, ensure_ascii=False, indent=2))
        return 0 if islenen else 1

    print(f"\nKuyruğa yazılan aday: {toplam_aday} · elenen: {elenen}")
    if atlanan_video:
        print(f"Atlanan video (alınmış/kuyrukta): {atlanan_video}")
    if hatalar:
        print(f"İşlenemeyen video: {len(hatalar)}")
    if toplam_aday:
        print("Gözden geçirmek için: biyo-cozucu kuyruk")
    # `_cmd_al` disiplini: kısmi başarı 0, hiçbir video işlenemediyse 1.
    return 0 if islenen else 1


def _cmd_transkript_al(argumanlar) -> int:
    """Colab'de üretilmiş döküm dosyalarını yerel önbelleğe kurar.

    Uzun videolarda yazıya dökme yerel makinede sürdürülemiyor (10 saatlik
    video ≈ 100 dk döküm, 1 GB WAV, whisper çağrısında 1 saatlik zaman aşımı).
    Colab GPU'da dökülen transkript buraya alınınca `youtube-al --uygula`
    indirmeyi ve dökümü atlayıp doğrudan soru çıkarımına geçer.
    """
    from .alim.cikarim import AlimHatasi
    from .alim.youtube import transkripti_ice_aktar

    kok = _kok(argumanlar)
    yollar: list[Path] = []
    for ham in argumanlar.dosya:
        yol = Path(ham).expanduser()
        if yol.is_dir():
            yollar.extend(sorted(yol.glob("*.json")))
        else:
            yollar.append(yol)
    if not yollar:
        print("İçe aktarılacak .json dosyası bulunamadı.", file=sys.stderr)
        return 1

    alinan = 0
    hatalar: list[str] = []
    for yol in yollar:
        try:
            video_id, parca, sure = transkripti_ice_aktar(yol, kok)
        except AlimHatasi as exc:
            hatalar.append(str(exc))
            print(f"! {exc}", file=sys.stderr)
            continue
        alinan += 1
        dakika = int(sure) // 60
        print(f"✓ {video_id}: {parca} parça · {dakika} dk")

    print(f"\nİçe aktarılan transkript: {alinan}")
    if hatalar:
        print(f"Alınamayan dosya: {len(hatalar)}")
    if alinan:
        print("Soruları çıkarmak için: biyo-cozucu youtube-al <url> --uygula")
    return 0 if alinan else 1


def _cmd_kuyruk(argumanlar) -> int:
    """Onay kuyruğunu listeler; `--onayla/--reddet` ile satır işaretler."""
    from .alim import kuyruk as kuyruk_birimi

    kok = _kok(argumanlar)

    if not argumanlar.hedef:
        yollar = kuyruk_birimi.dosyalar(kok)
        genel = kuyruk_birimi.ozet(kok)
        if argumanlar.json:
            print(json.dumps(
                {
                    "dosyalar": [y.name for y in yollar],
                    "bekleyen": genel.bekleyen,
                    "onayli": genel.onayli,
                    "reddedilen": genel.reddedilen,
                    "alinan": genel.alinan,
                    "bozuk": genel.bozuk,
                },
                ensure_ascii=False, indent=2,
            ))
            return 0
        if not yollar:
            print("Kuyruk boş. Doldurmak için: biyo-cozucu youtube-al <url> --uygula")
            return 0
        for sira, yol in enumerate(yollar, start=1):
            kayitlar, _bozuk = kuyruk_birimi.oku(yol)
            bekleyen = sum(1 for k in kayitlar if k.durum == "bekliyor")
            onayli = sum(1 for k in kayitlar if k.durum == "onay")
            baslik = kayitlar[0].video_basligi if kayitlar else ""
            print(
                f"{sira:2d}. {yol.name}  "
                f"bekleyen {bekleyen} · onaylı {onayli} · toplam {len(kayitlar)}"
                f"{'  ' + baslik[:44] if baslik else ''}"
            )
        print(
            f"\nToplam: bekleyen {genel.bekleyen} · onaylı {genel.onayli} · "
            f"ret {genel.reddedilen} · alınan {genel.alinan}"
        )
        if genel.bozuk:
            print(f"Bozuk satır: {genel.bozuk}", file=sys.stderr)
        return 0

    yol = _kuyruk_dosyasi_bul(kok, argumanlar.hedef)
    if yol is None:
        print(f"Kuyruk dosyası bulunamadı: {argumanlar.hedef}", file=sys.stderr)
        return 1

    try:
        if argumanlar.onayla:
            degisen = kuyruk_birimi.durumlari_isaretle(
                yol, _siralari_ayristir(argumanlar.onayla), "onay"
            )
            print(f"Onaylandı: {degisen} kayıt")
        if argumanlar.reddet:
            degisen = kuyruk_birimi.durumlari_isaretle(
                yol, _siralari_ayristir(argumanlar.reddet), "ret"
            )
            print(f"Reddedildi: {degisen} kayıt")
        if argumanlar.tumu:
            kayitlar, _ = kuyruk_birimi.oku(yol)
            bekleyenler = [
                sira for sira, k in enumerate(kayitlar, start=1) if k.durum == "bekliyor"
            ]
            if bekleyenler:
                degisen = kuyruk_birimi.durumlari_isaretle(yol, bekleyenler, "onay")
                print(f"Onaylandı: {degisen} kayıt")
    except ValueError as exc:
        print(f"Hata: {exc}", file=sys.stderr)
        return 2

    kayitlar, bozuk = kuyruk_birimi.oku(yol)
    if argumanlar.json:
        print(json.dumps([k.sozluk() for k in kayitlar], ensure_ascii=False, indent=2))
        return 0
    isaretler = {"bekliyor": "·", "onay": "✓", "ret": "✗", "alindi": "→"}
    for sira, kayit in enumerate(kayitlar, start=1):
        uyari = f"  !{','.join(kayit.uyarilar)}" if kayit.uyarilar else ""
        yer = kayit.konum or "—"
        print(
            f"{sira:3d}. {isaretler.get(kayit.durum, '?')} "
            f"{kayit.guven:.2f} [{yer:>6s}] {kayit.soru[:66]}{uyari}"
        )
    if bozuk:
        print(f"Bozuk satır: {bozuk} (dosyada korunuyor)", file=sys.stderr)
    print(f"\nİzleme bağlantıları için: kuyruk {argumanlar.hedef} --json")
    print("İşaretlemek için: --onayla 1,3,5-9 · --reddet 2,4 · --tumu")
    print("Hafızaya aktarmak için: biyo-cozucu kuyruk-onayla")
    return 0


def _cmd_kuyruk_onayla(argumanlar) -> int:
    """`durum=onay` kayıtları hafızaya aktarır, indeksi artımlı günceller.

    Kaynak imzası (`kaynagi_isaretle`) BURADA yazılır, çıkarım anında değil:
    kuyruğa yazıp onaylanmadan silinen bir video sonsuza dek "alınmış"
    görünmemeli. Aktarım sonrası bitmiş dosya `alinan/` altına arşivlenir.
    """
    from .alim import kuyruk as kuyruk_birimi
    from .depo import Depo

    kok = _kok(argumanlar)
    if argumanlar.hepsi:
        yollar = kuyruk_birimi.dosyalar(kok)
    else:
        yollar = []
        for hedef in argumanlar.hedef:
            yol = _kuyruk_dosyasi_bul(kok, hedef)
            if yol is None:
                print(f"Kuyruk dosyası bulunamadı: {hedef}", file=sys.stderr)
                return 1
            yollar.append(yol)
    if not yollar:
        print("Hedef verilmedi; tüm dosyalar için --hepsi kullanın.", file=sys.stderr)
        return 1

    depo = Depo(kok / "biyo.db")
    kimlikler: list[int] = []
    eklenen = guncellenen = atlanan = 0
    for yol in yollar:
        kayitlar, _bozuk = kuyruk_birimi.oku(yol)
        secilen = {}
        for sira, kayit in enumerate(kayitlar, start=1):
            if kayit.durum == "onay":
                secilen[sira] = kayit
                continue
            if kayit.durum != "bekliyor":
                continue
            # `--uyarisiz`: kalite filtrelerinin hiçbirine takılmamış kayıtlar.
            # Güven eşiği bunun yerine geçmiyor — temiz bir kaydın güveni de
            # düşük olabilir (model emin değildir) ve eşik onu da eler.
            if argumanlar.uyarisiz and not kayit.uyarilar:
                if (
                    argumanlar.asgari_guven is None
                    or kayit.guven >= argumanlar.asgari_guven
                ):
                    secilen[sira] = kayit
                continue
            if (
                argumanlar.asgari_guven is not None
                and kayit.guven >= argumanlar.asgari_guven
            ):
                secilen[sira] = kayit
        if not secilen:
            continue

        # Eşleme KALICI KİMLİKLE tutulur: aşağıdaki döngü kayıt başına gömme
        # ve indeksleme yapıyor, dosya bu sırada değişebilir ve sıra tabanlı
        # eşleme kayarak yanlış kaydı "alindi" damgalardı.
        sonuclar: dict[str, int] = {}
        yazilan_imzalar: set[str] = set()
        for sira, kayit in secilen.items():
            ornek = kuyruk_birimi.ornege_cevir(kayit)
            if ornek is None:
                atlanan += 1
                print(f"  ! atlandı (boş soru/çözüm): {yol.name} #{sira}", file=sys.stderr)
                continue
            try:
                onceki = depo.ornek_sayisi()
                kimlik = depo.ornek_ekle(ornek, uzerine_yaz=argumanlar.uzerine_yaz)
            except ValueError as exc:
                atlanan += 1
                print(f"  ! atlandı: {exc}", file=sys.stderr)
                continue
            if depo.ornek_sayisi() > onceki:
                eklenen += 1
            else:
                guncellenen += 1
            sonuclar[kayit.kimlik] = kimlik
            kimlikler.append(kimlik)
            if kayit.kaynak_imzasi:
                yazilan_imzalar.add(kayit.kaynak_imzasi)

        if sonuclar:
            kuyruk_birimi.alindi_isaretle(yol, sonuclar)
            for imza in yazilan_imzalar:
                depo.kaynagi_isaretle(imza)
        kalan, _ = kuyruk_birimi.oku(yol)
        if (
            not argumanlar.arsivleme
            and kalan
            and all(k.durum in {"alindi", "ret"} for k in kalan)
        ):
            hedef_yol = kuyruk_birimi.arsivle(yol, kok)
            print(f"Arşivlendi: {yol.name} → {hedef_yol.parent.name}/")

    if not kimlikler and not atlanan:
        print(
            "Aktarılacak onaylı kayıt yok. Önce `biyo-cozucu kuyruk <dosya> "
            "--onayla 1,2,…` ile işaretleyin."
        )
        return 0

    depo.denetim_yaz(
        "kuyruk_onayla",
        f"eklenen={eklenen} guncellenen={guncellenen} atlanan={atlanan}",
    )
    print(f"Eklendi: {eklenen} · Güncellendi: {guncellenen} · Atlandı: {atlanan}")
    print(f"Toplam örnek: {depo.ornek_sayisi()}")
    if kimlikler and not argumanlar.indekssiz:
        _indekse_isle(kok, kimlikler, gommesiz=argumanlar.gommesiz)
    return 0


def _cmd_kuyruk_sil(argumanlar) -> int:
    """Kuyruk dosyalarını siler; bekleyen kayıt varsa onay ister."""
    from .alim import kuyruk as kuyruk_birimi

    kok = _kok(argumanlar)
    yollar: list[Path] = []
    if argumanlar.reddedilenler:
        for yol in kuyruk_birimi.dosyalar(kok):
            kayitlar, _ = kuyruk_birimi.oku(yol)
            if kayitlar and all(k.durum == "ret" for k in kayitlar):
                yollar.append(yol)
    for hedef in argumanlar.hedef:
        yol = _kuyruk_dosyasi_bul(kok, hedef)
        if yol is None:
            print(f"Kuyruk dosyası bulunamadı: {hedef}", file=sys.stderr)
            return 1
        yollar.append(yol)
    if not yollar:
        print("Silinecek dosya yok.")
        return 0

    for yol in dict.fromkeys(yollar):
        kayitlar, _ = kuyruk_birimi.oku(yol)
        bekleyen = sum(1 for k in kayitlar if k.durum in {"bekliyor", "onay"})
        if bekleyen and not argumanlar.zorla:
            if not sys.stdin.isatty():
                print(
                    f"{yol.name}: {bekleyen} bekleyen kayıt var; --zorla ile silin.",
                    file=sys.stderr,
                )
                return 1
            yanit = input(f"{yol.name}: {bekleyen} bekleyen kayıt var. Silinsin mi? [e/H] ")
            if yanit.strip().casefold() not in {"e", "evet"}:
                print("Vazgeçildi.")
                continue
        yol.unlink()
        print(f"Silindi: {yol.name}")
    return 0


def ayristirici() -> argparse.ArgumentParser:
    ana = argparse.ArgumentParser(
        prog="biyo-cozucu",
        description="Referans çözümlerden öğrenip biyoloji sorusu çözen yerel sistem",
    )
    ana.add_argument("--veri", help="Veri kökü (varsayılan ~/.biyo-cozucu)")
    ana.add_argument("--gommesiz", action="store_true",
                     help="Gömme modelini yükleme (yalnız BM25 erişimi)")
    alt = ana.add_subparsers(dest="komut", required=True)

    p = alt.add_parser("ornek-ekle", help="Referans soru+çözüm örneği ekle")
    p.add_argument("dosya", nargs="*", help="Metin (SORU:/ÇÖZÜM:), .json veya .jsonl")
    p.add_argument("--soru")
    p.add_argument("--cozum")
    p.add_argument("--cevap")
    p.add_argument("--kaynak", help="Örneklerin geldiği kitap/deneme adı")
    p.add_argument("--uzerine-yaz", action="store_true", help="Aynı soru varsa güncelle")
    p.add_argument("--indekssiz", action="store_true", help="Eklemeden sonra indeksleme")
    p.set_defaults(islev=_cmd_ornek_ekle)

    p = alt.add_parser(
        "al", help="Kitap/çözüm kaynağından örnek al (PDF, Word, ses, video)"
    )
    p.add_argument("dosya", nargs="+", help="PDF, .docx, .txt, ses veya video")
    p.add_argument("--kaynak", help="Atıfta görünecek ad (varsayılan: dosya adı)")
    p.add_argument("--asgari-guven", type=float, default=0.6,
                   help="Bu güvenin altındaki adaylar eklenmez (varsayılan 0.6)")
    p.add_argument("--uygula", action="store_true",
                   help="Adayları gerçekten hafızaya yaz (varsayılan: yalnız önizleme)")
    p.add_argument("--uzerine-yaz", action="store_true", help="Aynı soru varsa güncelle")
    p.add_argument("--ocr", default="oto", choices=["oto", "kapali", "zorla"],
                   help="Taranmış sayfalarda OCR (varsayılan: oto)")
    p.add_argument("--ocr-motoru", default="",
                   choices=["", "surya", "easyocr", "paddle", "tesseract"],
                   help="OCR motoru (varsayılan: kurulu olanlardan en iyisi)")
    p.add_argument("--json", action="store_true", help="Adayları JSON olarak bas")
    p.set_defaults(islev=_cmd_al)

    p = alt.add_parser("indeksle", help="Erişim indeksini yeniden kur")
    p.set_defaults(islev=_cmd_indeksle)

    p = alt.add_parser("coz", help="Bir soruyu çöz")
    p.add_argument("soru", nargs="?")
    p.add_argument("--dosya", help="Soruyu dosyadan oku")
    p.add_argument("--secenek", action="append", help="Şık: A=metin (tekrarlanabilir)")
    p.add_argument(
        "--gorsel", help="Soruya ait şekil/grafik dosyası (--motor vlm gerekir)"
    )
    p.add_argument(
        "--gorsel-modu",
        default="auto",
        choices=["auto", "zorla", "yok"],
        help="Görsel yönlendirme: otomatik, zorunlu veya kapalı",
    )
    p.add_argument(
        "--motor", default=None,
        choices=["mlx", "vlm", "karma", "http", "sahte", "yok"]
    )
    p.add_argument("--ornek-sayisi", type=int, default=3)
    p.add_argument("--oz-kontrol", action="store_true",
                   help="İkinci bir model geçişiyle çözümü denetle")
    p.add_argument("--json", action="store_true")
    p.set_defaults(islev=_cmd_coz)

    p = alt.add_parser("disa-aktar", help="LoRA eğitim verisi üret (chat jsonl)")
    p.add_argument("--cikti", help="Hedef dizin")
    p.add_argument("--etiket", help="Sürüm etiketi")
    p.add_argument("--kanitsiz", action="store_true",
                   help="Eğitim kayıtlarına referans örnek ekleme")
    p.add_argument("--kanit-sayisi", type=int, default=2)
    # Çıkarımdaki `Ayarlar.kanit_azami_adim` ile aynı tutulmalı; ikisi
    # ayrışırsa model eğitimde gördüğünden farklı bir bağlamla çalıştırılır.
    p.add_argument(
        "--kanit-azami-adim", type=int, default=None,
        help="Kanıt yanıtlarının azami adım sayısı (0 = sınırsız)",
    )
    p.set_defaults(islev=_cmd_disa_aktar)

    p = alt.add_parser("degerlendir", help="Kör değerlendirme koşusu")
    p.add_argument("--test-dosyasi", help="test.jsonl (yoksa kararlı bölmeden alınır)")
    p.add_argument("--limit", type=int)
    p.add_argument("--cikti", help="Ayrıntılı sonucu JSON olarak yaz")
    # `vlm` buraya da girmeli: test kümesinin ~%30'u görsel/şema bağımlı ve
    # eksik olduğu için görselli koşu yalnız BIYO_MOTOR ortam değişkeniyle
    # yapılabiliyordu.
    p.add_argument("--motor", default=None,
        choices=["mlx", "vlm", "karma", "http", "sahte", "yok"])
    p.add_argument("--ornek-sayisi", type=int, default=3)
    p.add_argument("--ayrintili", action="store_true")
    # Görselli dilim (16 soru) ile görselsiz dilim (109) ayrı ölçülebilmeli:
    # görsel motorun kazancı yalnız kendi diliminde görünür, tüm kümeye
    # karıştırıldığında %13'lük ağırlıkla seyrelir ve karar verilemez.
    gorsel_suzgec = p.add_mutually_exclusive_group()
    gorsel_suzgec.add_argument(
        "--yalniz-gorselli", action="store_true",
        help="Yalnız şekli olan soruları çöz (görsel motor ölçümü)",
    )
    gorsel_suzgec.add_argument(
        "--yalniz-gorselsiz", action="store_true",
        help="Yalnız şekilsiz soruları çöz (metin modeli ölçümü)",
    )
    p.add_argument(
        "--gorsel-modu",
        choices=["auto", "zorla", "yok"],
        default="auto",
        help="Görsel yönlendirme: akıllı seçim, her görseli zorla veya kapat",
    )
    p.add_argument(
        "--oz-kontrol", action="store_true",
        help="Her çözümü ikinci bir model geçişiyle denetle (soru başına +1 çağrı)",
    )
    p.add_argument(
        "--deneme", type=int, default=None,
        help="Her soruyu N kez çözüp cevapları oyla (süreyi N katına çıkarır)",
    )
    p.add_argument(
        "--esik", type=float, default=None,
        help="Bu güvenin altındaki çözümler cevaplanmamış sayılır (seçici doğruluk)",
    )
    # Koşunun amacı tek bir doğruluk sayısı değil, koşular ARASI fark. Çözüm
    # yolunun varsayılan 0.2 sıcaklığında aynı ayar farklı sonuç veriyor:
    # 12 soruluk kümede boş cevap sayısı ölçümden ölçüme 3 ile 6 arasında
    # değişti ve gerçek bir iyileşmeyi gürültüden ayırmak imkânsızlaştı.
    # Sıfırda iki ardışık koşu birebir aynı sonucu veriyor (doğrulandı).
    p.add_argument(
        "--sicaklik", type=float, default=0.0,
        help="Üretim sıcaklığı; koşular karşılaştırılabilir olsun diye varsayılan 0",
    )
    p.set_defaults(islev=_cmd_degerlendir)

    p = alt.add_parser(
        "kalibre",
        help="Tür bazlı güven çarpanlarını doğrulama diliminden öğren",
    )
    p.add_argument(
        "--motor", default=None,
        choices=["mlx", "vlm", "karma", "http", "sahte", "yok"]
    )
    p.add_argument("--ornek-sayisi", type=int, default=3)
    p.add_argument("--limit", type=int, help="Doğrulama diliminden en fazla N soru")
    p.add_argument(
        "--asgari-ornek", type=int, default=8,
        help="Bir türe çarpan yazmak için gereken en az örnek sayısı",
    )
    p.add_argument("--sicaklik", type=float, default=0.0)
    p.set_defaults(islev=_cmd_kalibre)

    # `degerlendir` keşif içindir (limit, süzgeç, serbest çıktı); `olcum` ise
    # KAYIT tutar: sabit dilim, sürümlenen dosya, önceki koşuyla fark. İkisi
    # ayrı duruyor çünkü keşif koşusunun geçmişe yazılması geçmişi kirletir.
    p = alt.add_parser("olcum", help="Dondurulmuş dilimde kör koşu + fark raporu")
    p.add_argument("--etiket", default="",
        help="Koşunun adı (ne ölçüldüğü) — kayıt bununla adlandırılır")
    p.add_argument("--dilim", default="dilim-v1", help="Dilim manifesti adı ya da yolu")
    p.add_argument("--dilimi-dondur", default=None, metavar="AD",
        help="Mevcut test dilimini bu adla dondur ve çık (koşu yapmaz)")
    p.add_argument("--eksige-izin", action="store_true",
        help="Dilimdeki bazı sorular hafızada yoksa yine de koş")
    p.add_argument("--limit", type=int)
    p.add_argument("--motor", default=None,
        choices=["mlx", "vlm", "karma", "http", "sahte", "yok"])
    p.add_argument("--ornek-sayisi", type=int, default=3)
    p.add_argument("--oz-kontrol", action="store_true")
    p.add_argument("--deneme", type=int, default=None)
    p.add_argument("--esik", type=float, default=None)
    p.add_argument("--gorsel-modu", default=None,
        choices=["auto", "zorla", "yok"],
        help="Görselin modele verilme kipi; kayda yazılır, koşular ancak "
             "aynı kiple kıyaslanabilir")
    # Ölçümde sıcaklık 0: koşunun amacı tek bir doğruluk sayısı değil koşular
    # ARASI fark, ve rastgelelik farkı gürültüye boğar.
    p.add_argument("--sicaklik", type=float, default=0.0)
    p.add_argument("--kapi", action="store_true",
        help="Gerileme varsa çıkış kodu 1 (commit/CI kapısı)")
    p.add_argument("--tolerans", type=float, default=0.03,
        help="Bu orandan büyük doğruluk düşüşü gerileme sayılır")
    p.set_defaults(islev=_cmd_olcum)

    p = alt.add_parser("olcum-fark", help="İki ölçüm kaydını karşılaştır")
    p.add_argument("--onceki", required=True)
    p.add_argument("--yeni", required=True)
    p.add_argument("--kapi", action="store_true")
    p.add_argument("--tolerans", type=float, default=0.03)
    p.set_defaults(islev=_cmd_olcum_fark)

    p = alt.add_parser("durum", help="Hafıza ve indeks durumu")
    p.set_defaults(islev=_cmd_durum)

    p = alt.add_parser(
        "arsiv-coz", help="Soru Kesici arşivindeki soruları çöz (zip ya da klasör)"
    )
    p.add_argument("arsiv", help="soru_NN.png + sorular.json içeren zip/klasör")
    p.add_argument(
        "--coz", action="store_true",
        help="Soruları gerçekten çöz (varsayılan yalnız künye önizlemesi)",
    )
    p.add_argument("--limit", type=int, help="En fazla bu kadar soru çöz")
    p.add_argument(
        "--asgari-guven", type=float, default=0.0,
        help="Soru Kesici'nin kırpma güveni bu değerin altındakileri atla",
    )
    p.add_argument(
        "--motor", default=None,
        choices=["mlx", "vlm", "karma", "http", "sahte", "yok"]
    )
    p.add_argument("--ornek-sayisi", type=int, default=3)
    p.set_defaults(islev=_cmd_arsiv_coz)

    p = alt.add_parser(
        "paket-al", help="Hazır soru-çözüm paketini referans örneğe çevir (zip/klasör/json)"
    )
    p.add_argument("arsiv", help="Yapılandırılmış çözüm JSON'u içeren zip, klasör ya da .json")
    p.add_argument(
        "--tur", default="oto", choices=["oto", "palme", "ayt", "tyt"],
        help="Paket şeması (varsayılan: künyeden tanı)",
    )
    p.add_argument("--kaynak", default=None, help="Örneklere yazılacak atıf metni")
    p.add_argument("--jsonl", default=None, help="Türetilmiş örnekleri bu dosyaya yaz")
    p.add_argument(
        "--guven", default="orta", choices=["hepsi", "orta", "yuksek"],
        help="Kalite kademesi; 'hepsi' bozuk ayrıştırmaları da alır",
    )
    p.add_argument(
        "--sablonu-ayikla", action="store_true",
        help="Çözümün korpusta tekrarlayan şablon satırlarını düşür",
    )
    p.add_argument("--gorselsiz", action="store_true", help="Soru görsellerini alma")
    p.add_argument(
        "--uygula", action="store_true",
        help="Örnekleri doğrudan hafızaya da yaz (varsayılan yalnız önizleme)",
    )
    p.add_argument("--uzerine-yaz", action="store_true")
    p.add_argument("--indekssiz", action="store_true")
    p.add_argument("--gommesiz", action="store_true")
    p.set_defaults(islev=_cmd_paket_al)

    # `paket-al` üç belirli paket şemasını ele alıyor; bu komut alan adlarını
    # aday listelerinden bulan genel dönüştürücüyle çalışır ve birden çok
    # dosyayı tek seferde alır.
    p = alt.add_parser("jsonl-al", help="Serbest şemalı JSONL soru dosyalarını al")
    p.add_argument("dosyalar", nargs="+", help="JSONL/JSON dosyaları (joker desteklenir)")
    p.add_argument("--kaynak", default="", help="Kaynak etiketi (boşsa dosya adı)")
    p.add_argument(
        "--guven", default="orta", choices=["hepsi", "orta", "yuksek"],
        help="Bu kademenin altındaki kayıtları ele",
    )
    p.add_argument("--uygula", action="store_true", help="Hafızaya yaz")
    p.add_argument("--uzerine-yaz", action="store_true")
    p.add_argument("--indekssiz", action="store_true")
    p.add_argument("--gommesiz", action="store_true")
    p.set_defaults(islev=_cmd_jsonl_al)

    p = alt.add_parser(
        "youtube-al",
        help="YouTube soru çözümü videosunu/playlist'ini onay kuyruğuna çıkar",
    )
    p.add_argument("url", nargs="+", help="Video ya da playlist adresi")
    p.add_argument(
        "--uygula", action="store_true",
        help="İndir, yazıya dök ve adayları KUYRUĞA yaz (varsayılan: yalnız künye)",
    )
    p.add_argument("--limit", type=int, default=0, help="Playlist'ten en fazla N video")
    p.add_argument(
        "--motor", default=None,
        choices=["mlx", "vlm", "karma", "http", "sahte", "yok"],
    )
    p.add_argument(
        "--kural", action="store_true",
        help="Modeli hiç kullanma, kural tabanlı çıkarım",
    )
    p.add_argument(
        "--pencere", type=int, default=0,
        help="Döküm penceresi karakter boyu (varsayılan 3600, ölçümle seçildi)",
    )
    p.add_argument(
        "--asgari-guven", type=float, default=0.0,
        help="Bu güvenin altındaki adaylar kuyruğa yazılmaz (varsayılan: hepsi)",
    )
    p.add_argument(
        "--yeniden", action="store_true",
        help="Transkript önbelleğini yok say, dökümü yeniden yap",
    )
    p.add_argument(
        "--sesi-sakla", action="store_true",
        help="İndirilen ses dosyasını <kök>/youtube/ses altında tut",
    )
    p.add_argument("--json", action="store_true", help="Kuyruk kayıtlarını JSON bas")
    p.set_defaults(islev=_cmd_youtube_al)

    p = alt.add_parser(
        "transkript-al",
        help="Colab'de üretilmiş döküm JSON'unu yerel önbelleğe kur",
    )
    p.add_argument("dosya", nargs="+", help="<video_id>.json dosyaları ya da dizin")
    p.set_defaults(islev=_cmd_transkript_al)

    p = alt.add_parser("kuyruk", help="Onay kuyruğunu listele / kayıt işaretle")
    p.add_argument("hedef", nargs="?", help="Kuyruk dosyası adı ya da sıra numarası")
    p.add_argument("--onayla", default="", help="Onaylanacak sıralar: 1,3,5-9")
    p.add_argument("--reddet", default="", help="Reddedilecek sıralar: 2,4")
    p.add_argument("--tumu", action="store_true", help="Bekleyen tüm kayıtları onayla")
    p.add_argument("--json", action="store_true")
    p.set_defaults(islev=_cmd_kuyruk)

    p = alt.add_parser(
        "kuyruk-onayla", help="Onaylanmış kuyruk kayıtlarını hafızaya aktar"
    )
    p.add_argument("hedef", nargs="*", help="Kuyruk dosyası adları/sıraları")
    p.add_argument("--hepsi", action="store_true", help="Tüm kuyruk dosyalarını işle")
    p.add_argument(
        "--asgari-guven", type=float, default=None,
        help="Bekleyen kayıtlardan bu güvenin üstündekileri de aktar",
    )
    p.add_argument(
        "--uyarisiz", action="store_true",
        help="Kalite uyarısı almamış bekleyen kayıtları da aktar",
    )
    p.add_argument("--uzerine-yaz", action="store_true")
    p.add_argument("--indekssiz", action="store_true")
    p.add_argument("--gommesiz", action="store_true")
    p.add_argument(
        "--arsivleme", action="store_true", help="Biten dosyayı arşivleme"
    )
    p.set_defaults(islev=_cmd_kuyruk_onayla)

    p = alt.add_parser("kuyruk-sil", help="Kuyruk dosyalarını sil")
    p.add_argument("hedef", nargs="*", help="Kuyruk dosyası adları/sıraları")
    p.add_argument(
        "--reddedilenler", action="store_true",
        help="Tümü reddedilmiş dosyaları da sil",
    )
    p.add_argument("--zorla", action="store_true", help="Bekleyen kayıt olsa da sorma")
    p.set_defaults(islev=_cmd_kuyruk_sil)

    p = alt.add_parser(
        "kitap-al", help="Ders kitabı PDF'ini kavram pasajı olarak hafızaya al"
    )
    p.add_argument("pdf", help="Ders kitabı PDF yolu")
    p.add_argument(
        "--kaynak", required=True,
        help='Kitap adı; atıfta görünür (ör. "Campbell Biyoloji")',
    )
    p.add_argument("--baslangic", type=int, default=1, help="İlk sayfa (1 tabanlı)")
    p.add_argument("--bitis", type=int, default=0, help="Son sayfa (0 = sonuna kadar)")
    p.add_argument(
        "--ocr", default="oto", choices=["oto", "kapali", "zorla"],
        help="Taranmış sayfalarda OCR (varsayılan: yalnız metin katmanı yoksa)",
    )
    p.add_argument("--ocr-motoru", default="", help="surya | easyocr | paddle | tesseract")
    p.add_argument("--indekssiz", action="store_true", help="Pasaj indeksini yenileme")
    p.set_defaults(islev=_cmd_kitap_al)

    p = alt.add_parser("kitap-listele", help="Hafızadaki ders kitabı kaynakları")
    p.set_defaults(islev=_cmd_kitap_listele)

    p = alt.add_parser("set-listele", help="Kayıtlı açık veri setleri ve durumları")
    p.set_defaults(islev=_cmd_set_listele)

    p = alt.add_parser("set-al", help="Açık veri setinden referans örnek üret")
    p.add_argument("ad", help="set-listele ile görülebilir")
    p.add_argument(
        "--amac", default="degerlendirme", choices=["egitim", "degerlendirme"],
        help="Lisans kapısı buna göre uygulanır (NC/ND setler eğitime giremez)",
    )
    p.add_argument("--bolum", default="train")
    p.add_argument("--limit", type=int, default=500)
    p.add_argument(
        "--tum-konular", action="store_true",
        help="Biyoloji süzgecini kapat (varsayılan yalnız biyoloji)",
    )
    p.add_argument(
        "--uygula", action="store_true",
        help="Örnekleri hafızaya yaz (varsayılan yalnız önizleme)",
    )
    p.set_defaults(islev=_cmd_set_al)

    p = alt.add_parser("model-kur", help="Colab'dan gelen model/adaptör zip'ini kur")
    p.add_argument("zip")
    p.add_argument("--hedef")
    p.set_defaults(islev=_cmd_model_kur)

    p = alt.add_parser("sunucu", help="Web arayüzünü başlat")
    p.add_argument("--adres", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8000)
    # Arayüz şekil yüklemeyi destekliyor (`webapp/cozum.py`), bu yüzden görsel
    # motorlar burada da seçilebilmeli: aksi hâlde kullanıcı şekli yüklüyor,
    # motor onu okuyamıyor ve soru sessizce şekilsiz çözülüyordu.
    p.add_argument(
        "--motor", default=None,
        choices=["mlx", "vlm", "karma", "http", "sahte", "yok"]
    )
    p.set_defaults(islev=_cmd_sunucu)

    return ana


def main(argv: list[str] | None = None) -> int:
    argumanlar = ayristirici().parse_args(argv)
    try:
        return int(argumanlar.islev(argumanlar) or 0)
    finally:
        # Yazıya dökme sunucusu tembel başlatılıyor ve süreç boyunca yaşıyor;
        # komut biterken kapatılmazsa 574 MB'lık modeli tutan bir artık süreç
        # geride kalıyor. Ölçüldü: birkaç koşu sonrası PPID'si 1 olan iki
        # whisper-server 635 MB tutuyordu. Modül hiç kullanılmadıysa import
        # bile edilmez.
        _dokum_sunucusunu_kapat()


def _dokum_sunucusunu_kapat() -> None:
    modul = sys.modules.get("biyo_cozucu.alim.ses")
    if modul is not None:
        modul.kapat()


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
