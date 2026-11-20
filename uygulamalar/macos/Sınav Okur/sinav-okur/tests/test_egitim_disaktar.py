import json

from sinav_okur.depo import Depo
from sinav_okur.modeller import PuanSonucu, Sinav, TanimaSonucu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def _sonuc(kirp):
    return KagitSonucu(
        sinav_kimlik="BİYO",
        islenen_sayfalar=[1],
        kutular=[
            KutuSonucu(
                soru_no=1,
                tanima=TanimaSonucu("hucre", 0.7),
                puan=PuanSonucu(1, 1, 0.7),
                kirp_yolu=str(kirp),
            )
        ],
    )


def test_yalniz_izinli_anonim_yazar_disa_aktarilir(tmp_path):
    kirp = tmp_path / "satir.png"
    kirp.write_bytes(b"png-gerekmez")
    db = Depo(tmp_path / "t.db")
    db.sinav_kaydet(
        Sinav(
            kimlik="BİYO",
            baslik="Test",
            sorular=[
                {
                    "no": 1,
                    "tip": "bosluk_doldurma",
                    "metin": "Hücre?",
                    "puan": 1,
                    "anahtar": {"dogru_cevaplar": ["hücre"]},
                }
            ],
        )
    )

    izinsiz = db.kagit_kaydet(_sonuc(kirp), ogrenci_ad="Ad Soyad")
    db.kutu_guncelle(db.kutular(izinsiz)[0]["id"], duzeltilmis_metin="hücre")

    izinli = db.kagit_kaydet(
        _sonuc(kirp),
        ogrenci_ad="Başka Ad",
        ogrenci_no="123",
        yazar_grubu="yazar-007",
        egitim_izni=True,
    )
    db.kutu_guncelle(db.kutular(izinli)[0]["id"], duzeltilmis_metin="hücre")

    cikti = tmp_path / "egitim.jsonl"
    assert db.egitim_verisi_disa_aktar(cikti) == 1
    kayit = json.loads(cikti.read_text(encoding="utf-8"))
    assert kayit["writer_id"] == "yazar-007"
    assert kayit["text"] == "hücre"
    assert "Ad" not in cikti.read_text(encoding="utf-8")
    manifest = json.loads(
        (tmp_path / "egitim.jsonl.manifest.json").read_text(encoding="utf-8")
    )
    assert manifest["contains_direct_identifiers"] is False
    assert manifest["writers"] == 1


def test_eski_db_sutunlari_kayipsiz_eklenir(tmp_path):
    import sqlite3

    yol = tmp_path / "eski.db"
    con = sqlite3.connect(yol)
    con.execute(
        "CREATE TABLE kagit (id INTEGER PRIMARY KEY, sinav_kimlik TEXT, "
        "ogrenci_ad TEXT, ogrenci_no TEXT, kaynak_dosya TEXT, "
        "olusturuldu TEXT, onaylandi INTEGER)"
    )
    con.commit()
    con.close()
    Depo(yol)
    con = sqlite3.connect(yol)
    kolonlar = {r[1] for r in con.execute("PRAGMA table_info(kagit)")}
    con.close()
    assert {"yazar_grubu", "egitim_izni"} <= kolonlar
