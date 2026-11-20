from biyo_cozucu.modeller import Pasaj
from biyo_cozucu.webapp.durum import Uygulama


def test_webapp_kitap_aktarimindan_sonra_pasaj_indeksini_yeniler(tmp_path):
    """Ayaktaki sunucu, sonradan aktarılan kitabı bir sonraki çözümde görür."""
    uygulama = Uygulama(tmp_path, motor_turu="yok", gommesiz=True)
    uygulama.depo.pasaj_ekle(
        Pasaj(
            metin="Glomerüler filtrasyon kapiller basınç ile belirlenir. " * 4,
            kaynak="Guyton",
            sayfa=16,
        )
    )

    ilk = uygulama.cozucu().pasaj_indeksi
    assert ilk is not None
    assert len(ilk) == 1

    uygulama.depo.pasaj_ekle(
        Pasaj(
            metin="Kalp debisi kalbin dakikada pompaladığı kan miktarıdır. " * 4,
            kaynak="Guyton",
            sayfa=15,
        )
    )

    yenilenmis = uygulama.cozucu().pasaj_indeksi
    assert yenilenmis is not None
    assert len(yenilenmis) == 2
    assert yenilenmis is not ilk
