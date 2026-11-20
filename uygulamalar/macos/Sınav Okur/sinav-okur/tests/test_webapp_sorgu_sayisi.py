"""N+1 sorgu desenlerinin geri gelmesine karşı kapı.

Ölçüldü: sınav sayfası kâğıt başına iki sorgu yapıyordu (30 kâğıt = 60
sorgu, her biri kutu tablosunu baştan tarayarak) ve geri bildirim ekranı
her kâğıt için tüm sınavın cevaplarını yeniden okuyordu.
"""

from __future__ import annotations

import pytest

pytest.importorskip("cv2")
pytest.importorskip("fastapi")

from fastapi.testclient import TestClient

from sinav_okur.depo import Depo
from sinav_okur.modeller import (
    CevapAnahtari,
    PuanSonucu,
    RubrikKalemi,
    Sinav,
    Soru,
    SoruTipi,
    TanimaSonucu,
)
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu
from sinav_okur.webapp import uygulama_kur

KIMLIK = "SORGU"
KAGIT_SAYISI = 20


def _kur(tmp_path) -> Depo:
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(
        Sinav(
            kimlik=KIMLIK,
            baslik="Biyoloji",
            sorular=[
                Soru(
                    no=n,
                    tip=SoruTipi.KISA_CEVAP,
                    metin=f"{n}. soru",
                    puan=10.0,
                    anahtar=CevapAnahtari(
                        rubrik=[RubrikKalemi(f"ölçüt {n}", 10.0)]
                    ),
                    kazanımlar=[f"K{n}"],
                )
                for n in (1, 2, 3)
            ],
        )
    )
    for sira in range(KAGIT_SAYISI):
        kutular = [
            KutuSonucu(
                soru_no=n,
                tanima=TanimaSonucu(metin=f"ölçüt {n}", guven=0.9),
                puan=PuanSonucu(10.0, 10.0, 0.9),
            )
            for n in (1, 2, 3)
        ]
        kagit_id = depo.kagit_kaydet(
            KagitSonucu(
                sinav_kimlik=KIMLIK, islenen_sayfalar=[1], kutular=kutular
            ),
            ogrenci_ad=f"Öğrenci {sira}",
        )
        depo.kagit_onayla(kagit_id)
    return depo


def test_sinav_sayfasi_kagit_basina_sorgu_yapmaz(tmp_path):
    _kur(tmp_path)
    app = uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    istemci = TestClient(app)
    # Sayaç UYGULAMANIN kendi depo örneğine bağlanmalı; ayrı bir Depo
    # nesnesi hiçbir şey yakalamaz ve test sessizce yeşil yanar.
    depo = app.state.baglam.depo

    with depo.sorgulari_say() as sorgular:
        yanit = istemci.get(f"/sinav/{KIMLIK}")

    assert yanit.status_code == 200
    assert sorgular, "sayaç uygulamanın sorgularını görmeli"
    kutu_sorgulari = [s for s in sorgular if "FROM kutu" in s]
    assert len(kutu_sorgulari) < KAGIT_SAYISI, (
        f"kâğıt başına kutu sorgusu yapılıyor: {len(kutu_sorgulari)} sorgu "
        f"/ {KAGIT_SAYISI} kâğıt"
    )


def test_toplu_geri_bildirim_kazanim_analizini_bir_kez_yapar(tmp_path, monkeypatch):
    _kur(tmp_path)
    sayac = {"cagri": 0}
    from sinav_okur import analiz

    asil = analiz.kazanim_analizi

    def sayan(*args, **kwargs):
        sayac["cagri"] += 1
        return asil(*args, **kwargs)

    monkeypatch.setattr(analiz, "kazanim_analizi", sayan)
    istemci = TestClient(
        uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    )

    yanit = istemci.get(f"/sinav/{KIMLIK}/geri-bildirimler")

    assert yanit.status_code == 200
    assert sayac["cagri"] == 1, (
        f"{KAGIT_SAYISI} kâğıt için {sayac['cagri']} kez kazanım analizi "
        "yapıldı; bir kez yeter"
    )


def test_sicak_sorgular_indeks_kullaniyor(tmp_path):
    """Kâğıt/kutu sorguları tam tablo taraması yapmamalı."""
    depo = _kur(tmp_path)

    with depo._islem() as con:
        kutu_plani = con.execute(
            "EXPLAIN QUERY PLAN SELECT * FROM kutu WHERE kagit_id=1"
        ).fetchall()
        kagit_plani = con.execute(
            "EXPLAIN QUERY PLAN SELECT * FROM kagit WHERE sinav_kimlik=?",
            (KIMLIK,),
        ).fetchall()

    assert "USING INDEX" in kutu_plani[0][-1]
    assert "USING INDEX" in kagit_plani[0][-1]


def test_sorgu_sayaci_yalitilmis(tmp_path):
    """Sayaç örnek niteliğidir; blok bitince iz sürme kapanır."""
    depo = _kur(tmp_path)


    with depo.sorgulari_say() as icerideki:
        depo.kagitlar(KIMLIK)
    depo.kagitlar(KIMLIK)

    assert icerideki, "blok içinde sorgular kaydedilmeli"
    assert depo._sorgu_kaydi is None
