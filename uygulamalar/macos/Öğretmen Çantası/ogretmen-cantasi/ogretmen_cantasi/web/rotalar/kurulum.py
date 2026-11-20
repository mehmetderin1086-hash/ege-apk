"""Öğretim yılı, takvim, şube ve ders programı kurulumu."""

from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import FastAPI, Form, Request, UploadFile
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse

from ... import depo, servis
from ... import takvim as tk
from ...okuma import ders_programi as dp_okuma
from ...okuma import tablo as tablo_okuma
from ..ortak import (
    TABLO_YUKLEME_SINIRI,
    _form_revizyonu,
    _ortak,
    _revizyon_ilerlet,
    _sinirli_oku,
    _yuklenen_dosya,
    sablonlar,
)


def bagla(uygulama: FastAPI) -> None:
    @uygulama.post("/ogretim-yili/aktiflestir")
    def ogretim_yili_aktiflestir(
        istek: Request, yil_id: Annotated[int, Form()]
    ):
        servis.ogretim_yili_aktiflestir(istek.state.db, yil_id)
        return RedirectResponse("/", status_code=303)

    @uygulama.get("/kurulum", response_class=HTMLResponse)
    def kurulum(istek: Request, mesaj: str = ""):
        baglanti = istek.state.db
        yil = servis.aktif_yil(baglanti)
        varsayilan = tk.varsayilan_ogretim_yili(date.today().year if date.today().month >= 7 else date.today().year - 1)
        tatiller = servis.tatilleri_oku(baglanti, yil.id) if yil else []
        return sablonlar.TemplateResponse(
            istek,
            "kurulum.html",
            _ortak(
                istek,
                varsayilan=varsayilan,
                tatiller=tatiller,
                program=servis.ders_programini_oku(baglanti, yil.id) if yil else [],
                mesaj=mesaj,
                gun_adlari=tk.GUN_ADLARI,
                izgara_saat=servis.izgara_saat_sayisi(baglanti, yil.id) if yil else 8,
                program_revizyonu=depo.revizyon_oku(
                    baglanti, f"program:{yil.id}"
                )
                if yil
                else 0,
            ),
        )

    @uygulama.post("/kurulum/yil")
    def kurulum_yil(
        istek: Request,
        ad: Annotated[str, Form()],
        d1_baslangic: Annotated[str, Form()],
        d1_bitis: Annotated[str, Form()],
        d2_baslangic: Annotated[str, Form()],
        d2_bitis: Annotated[str, Form()],
    ):
        try:
            tarihler = [date.fromisoformat(t) for t in (d1_baslangic, d1_bitis, d2_baslangic, d2_bitis)]
        except ValueError:
            return RedirectResponse("/kurulum?mesaj=Tarih+biçimi+anlaşılmadı", status_code=303)
        if not (tarihler[0] < tarihler[1] < tarihler[2] < tarihler[3]):
            # Sıralama bozuksa plan sessizce boş çıkıyordu.
            return RedirectResponse(
                "/kurulum?mesaj=Tarihler+sırayla+artmalı:+1.+dönem+başlangıç+<+bitiş+<+2.+dönem+başlangıç+<+bitiş",
                status_code=303,
            )
        servis.ogretim_yili_kur(
            istek.state.db,
            ad,
            tk.Donem(1, tarihler[0], tarihler[1]),
            tk.Donem(2, tarihler[2], tarihler[3]),
        )
        return RedirectResponse("/kurulum?mesaj=Öğretim+yılı+kaydedildi", status_code=303)

    @uygulama.post("/kurulum/tatil")
    def kurulum_tatil(
        istek: Request,
        baslangic: Annotated[str, Form()],
        bitis: Annotated[str, Form()],
        aciklama: Annotated[str, Form()],
        tur: Annotated[str, Form()] = tk.TUR_OKUL,
    ):
        baglanti = istek.state.db
        yil = servis.yili_zorunlu_al(baglanti)
        gunler = tk.aralik_gunleri(
            date.fromisoformat(baslangic), date.fromisoformat(bitis or baslangic), tur, aciklama
        )
        servis.tatil_ekle(baglanti, yil.id, gunler)
        return RedirectResponse("/kurulum?mesaj=Takvime+eklendi", status_code=303)

    @uygulama.post("/kurulum/tatil/{tatil_id}/sil")
    def kurulum_tatil_sil(istek: Request, tatil_id: int):
        servis.tatil_sil(istek.state.db, tatil_id)
        return RedirectResponse("/kurulum?mesaj=Silindi", status_code=303)

    @uygulama.post("/kurulum/sube")
    def kurulum_sube(istek: Request, ad: Annotated[str, Form()], sinif: Annotated[int, Form()]):
        baglanti = istek.state.db
        yil = servis.yili_zorunlu_al(baglanti)
        servis.sube_ekle(baglanti, yil.id, ad.strip().upper(), sinif, ogretim_yili_adi=yil.ad)
        return RedirectResponse("/kurulum?mesaj=Şube+eklendi", status_code=303)

    @uygulama.post("/kurulum/sube/{sube_id}/sil")
    def kurulum_sube_sil(istek: Request, sube_id: int):
        servis.sube_sil(istek.state.db, sube_id)
        return RedirectResponse("/kurulum?mesaj=Şube+silindi", status_code=303)

    @uygulama.post("/kurulum/program/yukle")
    async def kurulum_program_yukle(istek: Request, dosya: UploadFile):
        baglanti = istek.state.db
        yil = servis.yili_zorunlu_al(baglanti)
        icerik = await _sinirli_oku(dosya, TABLO_YUKLEME_SINIRI)
        try:
            with _yuklenen_dosya(dosya, icerik) as gecici:
                sonuc = dp_okuma.ders_programi_coz(tablo_okuma.tabloyu_oku(gecici))
        except tablo_okuma.OkunamadiError as hata:
            return RedirectResponse(f"/kurulum?mesaj={hata}", status_code=303)

        hucreler: list[tuple[int, int, int]] = []
        for sube_adi in sonuc.subeler:
            sinif = int(sube_adi.split("-")[0])
            sube_id = servis.sube_ekle(baglanti, yil.id, sube_adi, sinif, ogretim_yili_adi=yil.ad)
            hucreler += [
                (sube_id, h.gun, h.ders_saati) for h in sonuc.hucreler if h.sube_adi == sube_adi
            ]
        if hucreler:
            # Dosyadan yükleme de program revizyonunu ilerletmeli (aksi hâlde
            # açık kalmış eski ızgara formu yüklenen programı geri ezebilir);
            # yazma ile sürüm artışı aynı işlemde kalır.
            with depo.islem(baglanti, immediate=True):
                servis.ders_programi_yaz(baglanti, hucreler)
                _revizyon_ilerlet(baglanti, f"program:{yil.id}", None)
        return RedirectResponse(
            f"/kurulum?mesaj={' '.join(sonuc.uyarilar) or 'Ders programı okundu'}", status_code=303
        )

    @uygulama.post("/kurulum/program/izgara")
    async def kurulum_program_izgara(istek: Request):
        baglanti = istek.state.db
        yil = servis.yili_zorunlu_al(baglanti)
        veri = await istek.form()
        # Izgara hangi yıl görüntülenirken doldurulduysa o yıla yazılmalı:
        # form yıl kimliği taşımayınca, başka sekmede yıl değiştirildiğinde
        # eski yılın hücreleri yeni yılın programını ezebiliyordu.
        form_yili = str(veri.get("yil_id", "")).strip()
        if form_yili and form_yili != str(yil.id):
            return PlainTextResponse(
                "Bu ızgara başka bir öğretim yılı açıkken dolduruldu; sayfayı "
                "yenileyip aktif yılın programını düzenleyin.",
                status_code=409,
            )
        beklenen_revizyon = _form_revizyonu(veri)
        subeler = {s.ad: s.id for s in servis.subeleri_oku(baglanti, yil.id)}
        hucreler: list[tuple[int, int, int]] = []
        taninmayanlar: list[str] = []
        izgara_alanlari = 0
        gonderilen_azami_saat = 0
        for anahtar, deger in veri.items():
            if not anahtar.startswith("h_"):
                continue
            izgara_alanlari += 1
            _, gun, saat = anahtar.split("_")
            # Aralık, BOŞ hücreleri de sayarak gönderilen tüm alanlardan
            # çıkarılır: boş bir hücre "bu saati temizle" demektir.
            gonderilen_azami_saat = max(gonderilen_azami_saat, int(saat))
            if not str(deger).strip():
                continue
            ad = str(deger).strip().upper()
            sube_id = subeler.get(ad)
            if sube_id:
                hucreler.append((sube_id, int(gun), int(saat)))
            else:
                # Tanınmayan ad SESSİZCE ATLANMAZ: eskiden bir yazım hatası
                # hücreyi düşürüyor, silme yine çalışıyor ve bütün ders
                # programı "kaydedildi" mesajıyla siliniyordu.
                taninmayanlar.append(ad)

        if not izgara_alanlari:
            # Izgara alanı hiç gelmemişse bu bir ızgara kaydetme isteği değil;
            # silme yapılmaz. (Şablon alanları her zaman basar, ama kodun
            # davranışı forma bağlı kalmamalı.)
            return RedirectResponse(
                "/kurulum?mesaj=Izgara+verisi+gelmedi,+ders+programı+değiştirilmedi",
                status_code=303,
            )
        if taninmayanlar and not hucreler:
            return RedirectResponse(
                "/kurulum?mesaj=Hiçbir hücre tanınmadı, ders programı DEĞİŞTİRİLMEDİ. "
                f"Tanınmayan: {', '.join(sorted(set(taninmayanlar))[:6])}. "
                "Şube adlarını yukarıdaki listedeki gibi yazın.",
                status_code=303,
            )

        # Silme ve yazma tek işlemde; ızgarada hiç hücresi kalmayan şubenin
        # programı da temizlenmeli, o yüzden tüm şubeler hedef veriliyor.
        #
        # Silme aralığı GÖNDERİLEN FORMDAN türetilir — ne gizli bir alandan ne
        # de veritabanının o anki hâlinden. Aralık "bu istek neyi kapsıyor"
        # sorusunun cevabıdır; `izgara_saat_sayisi` ise "veritabanında şu an en
        # yüksek saat kaç" sorusununkidir. İkisi ayrışabiliyor: sayfa 8 sütunla
        # açık dururken 10 saatlik bir program yüklenir, sonra o eski sekme
        # kaydedilirse ızgaranın hiç görmediği 10. saat silinirdi. Anahtarların
        # kendisi isteğin olgusu olduğu için istemciden gelen bir sayıya
        # güvenmek anlamına gelmiyor.
        try:
            with depo.islem(baglanti, immediate=True):
                _revizyon_ilerlet(
                    baglanti, f"program:{yil.id}", beklenen_revizyon
                )
                servis.ders_programi_yaz(
                    baglanti,
                    hucreler,
                    temizlenecek_subeler=list(subeler.values()),
                    saat_araligi=(1, gonderilen_azami_saat),
                )
        except ValueError as hata:
            return PlainTextResponse(str(hata), status_code=409)
        mesaj = "Ders programı kaydedildi"
        if taninmayanlar:
            mesaj += (
                f" — {len(taninmayanlar)} hücre tanınmadı ve boş bırakıldı: "
                + ", ".join(sorted(set(taninmayanlar))[:6])
            )
        return RedirectResponse(f"/kurulum?mesaj={mesaj}", status_code=303)
