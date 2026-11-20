"""Kör değerlendirme koşusunu arayüzden başlatma ve geçmişi karşılaştırma.

Koşu uzun sürer (her test örneği bir model çağrısı), bu yüzden `/coz/akis`
ile aynı SSE deseni kullanılıyor: senkron üretici, Starlette onu iş parçacığı
havuzunda koşturuyor. İlerleme görünmezse kullanıcı sayfanın donduğunu sanıp
sekmeyi kapatıyor ve dakikalarca süren koşu boşa gidiyor.
"""

from __future__ import annotations

import queue
import threading

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, StreamingResponse

from ..degerlendirme import kor_kosu
from ..veri.disa_aktar import bol
from .cozum import _sse
from .durum import Uygulama

# `bol()` her örneği imzasına göre bağımsız olarak kümelere atıyor; bu, sürüm
# karşılaştırmasının kararlı kalması için bilinçli bir tasarım. Bedeli, küçük
# koleksiyonlarda test diliminin boş çıkabilmesi: %10 oranla 30 örnek ~3 test
# örneği demek. Bu sayı kullanıcıya söylenmezse sayfa sebepsiz bozuk görünüyor.
ANLAMLI_OLCUM_ICIN_ORNEK = 30

# Onay döngüsünden gelen örneklerin `kaynak` alanı (bkz. `webapp/cozum.py`).
ONAY_KAYNAGI = "öğretmen onayı"


def _bos_test_mesaji() -> str:
    return (
        "Test kümesi boş. Kör değerlendirme hafızanın %10'unu test için ayırır "
        f"ve bu ayrım örneğin imzasına bağlıdır; anlamlı bir ölçüm için kabaca "
        f"{ANLAMLI_OLCUM_ICIN_ORNEK} referans örnek gerekiyor."
    )


def yonlendirici(durum: Uygulama, sablon) -> APIRouter:
    yonlendirici = APIRouter()

    def _test_ornekleri():
        """Kararlı bölmenin test dilimi.

        `bol()` bölmeyi sorunun imzasına bağlıyor; yeni örnek eklemek eski
        örneklerin kümesini değiştirmiyor. Bu yüzden farklı zamanlarda yapılan
        koşular karşılaştırılabilir kalıyor.
        """
        _egitim, _dogrulama, test = bol(durum.depo.ornekler())
        return test

    @yonlendirici.get("/degerlendirme", response_class=HTMLResponse)
    def degerlendirme_sayfasi(request: Request):
        test = _test_ornekleri()
        return sablon.TemplateResponse(
            request,
            "degerlendirme.html",
            {
                "durum": durum.durum(),
                "etkin": "degerlendirme",
                "kosular": durum.depo.kosular(limit=20),
                "test_sayisi": len(test),
                # Onaydan türeyen test örneği, modelin kendi eski çıktısıyla
                # karşılaştırılması demek: kör koşu erişimi engelliyor ama
                # PUANLAMANIN REFERANSI yine modelin kendi metni oluyor ve
                # doğruluk yapay olarak yükseliyor. Ölçüm bunu gizlememeli.
                "oz_turemis_test": sum(1 for o in test if o.kaynak == ONAY_KAYNAGI),
                "bos_test_mesaji": _bos_test_mesaji(),
                "motor_turu": durum.motor_turu,
            },
        )

    @yonlendirici.post("/degerlendirme/akis")
    def degerlendirme_akisi(etiket: str = Form("")):
        test = _test_ornekleri()

        def uret():
            if not test:
                yield _sse("hata", {"mesaj": _bos_test_mesaji()})
                return

            # `kor_kosu` senkron ve geri çağrısından `yield` edilemez; koşu
            # ayrı bir iş parçacığında koşup ilerlemeyi kuyruğa yazıyor, bu
            # üretici yalnız kuyruğu boşaltıyor. Aynı desen motor katmanında
            # da kullanılıyor (bkz. `motor/mlx_motor.py:uret_akis`).
            kuyruk: queue.Queue = queue.Queue()
            bitti = object()
            toplam = len(test)

            def kosuyu_calistir() -> None:
                try:
                    cozucu = durum.cozucu()
                    ozet = kor_kosu(
                        cozucu,
                        test,
                        ilerleme=lambda sira, _t, sonuc: kuyruk.put(
                            ("ilerleme", {
                                "sira": sira,
                                "toplam": toplam,
                                "dogru": bool(sonuc.cevap_dogru),
                                "soru": sonuc.soru[:80],
                            })
                        ),
                    )
                    kosu_id = durum.depo.kosu_kaydet(
                        ozet,
                        etiket=etiket.strip(),
                        model=getattr(cozucu.motor, "ad", ""),
                    )
                    html = sablon.get_template("parcalar/kosu_ozeti.html").render(
                        ozet=ozet, kosu_id=kosu_id
                    )
                    kuyruk.put(("bitti", {"html": html, "kosu_id": kosu_id}))
                except Exception as exc:  # noqa: BLE001
                    # Akış başladıktan sonra HTTP durum kodu değiştirilemez;
                    # hatayı olay olarak bildirmek tek yol.
                    kuyruk.put(("hata", {"mesaj": f"Değerlendirme başarısız: {exc}"}))
                finally:
                    kuyruk.put(bitti)

            threading.Thread(
                target=kosuyu_calistir, name="biyo-degerlendirme", daemon=True
            ).start()

            while True:
                oge = kuyruk.get()
                if oge is bitti:
                    return
                ad, veri = oge
                yield _sse(ad, veri)

        return StreamingResponse(
            uret(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache, no-transform", "X-Accel-Buffering": "no"},
        )

    return yonlendirici
