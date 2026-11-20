"""OpenAI-uyumlu HTTP motoru testleri.

Sahte bir `urlopen` yerine **gerçek bir yerel HTTP sunucusu** kullanılıyor.
Gerekçe: bu modülün değeri tam olarak urllib'in ve SSE ayrıştırmasının doğru
sürülmesinde; `urlopen`'ı monkeypatch etmek o iki katmanı da testin dışında
bırakır ve geriye yalnız sözlük kurma kalırdı. Sunucu 127.0.0.1'de geçici bir
porta bağlanır, dolayısıyla testler yine çevrimdışı ve deterministiktir.
"""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from biyo_cozucu.motor.http_motor import HttpMotor, _gecici_mi
from biyo_cozucu.motor.temel import MotorHatasi


class _Senaryo:
    """Sunucunun her isteğe nasıl karşılık vereceğini testin belirlemesini sağlar."""

    def __init__(self) -> None:
        # İstenen model adına göre yanıt; None anahtar "diğer hepsi" demek.
        self.yanitlar: dict[str | None, tuple[int, object]] = {}
        self.akis_satirlari: list[str] = []
        self.akis_durumu = 200
        self.modeller_ucu_durumu = 200
        # Sunucunun gerçekte aldığı istekler — asıl doğrulama bunlar üzerinde.
        self.istekler: list[dict] = []
        self.basliklar: list[dict] = []

    def yanit_ver(self, model: str | None, durum: int, govde: object) -> None:
        self.yanitlar[model] = (durum, govde)


def _islem_kur(senaryo: _Senaryo):
    class Islem(BaseHTTPRequestHandler):
        def log_message(self, *_args) -> None:
            """Test çıktısını kirletmesin."""

        def do_GET(self) -> None:
            if self.path.endswith("/models"):
                self.send_response(senaryo.modeller_ucu_durumu)
                self.end_headers()
                self.wfile.write(b'{"data": []}')
            else:
                self.send_response(404)
                self.end_headers()

        def do_POST(self) -> None:
            uzunluk = int(self.headers.get("Content-Length", 0))
            govde = json.loads(self.rfile.read(uzunluk) or b"{}")
            senaryo.istekler.append(govde)
            senaryo.basliklar.append(dict(self.headers))

            if govde.get("stream"):
                if senaryo.akis_durumu != 200:
                    ham = b'{"error": "akis reddedildi"}'
                    self.send_response(senaryo.akis_durumu)
                    self.send_header("Content-Length", str(len(ham)))
                    self.end_headers()
                    self.wfile.write(ham)
                    return
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                for satir in senaryo.akis_satirlari:
                    self.wfile.write(f"{satir}\n".encode())
                self.wfile.flush()
                return

            model = govde.get("model")
            durum, yanit = senaryo.yanitlar.get(
                model, senaryo.yanitlar.get(None, (200, {}))
            )
            # ensure_ascii=False: gerçek uçlar Türkçe hata metnini kaçırmadan
            # gönderiyor; kaçırılmış gövde hata mesajı testini yalancı yapar.
            ham = (
                yanit if isinstance(yanit, str)
                else json.dumps(yanit, ensure_ascii=False)
            ).encode()
            self.send_response(durum)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(ham)))
            self.end_headers()
            self.wfile.write(ham)

    return Islem


@pytest.fixture
def senaryo() -> _Senaryo:
    return _Senaryo()


@pytest.fixture
def uc(senaryo):
    """Yerel sunucuyu başlatır ve motorun kullanacağı taban adresi verir."""
    sunucu = ThreadingHTTPServer(("127.0.0.1", 0), _islem_kur(senaryo))
    # poll_interval: `shutdown()` bu aralık kadar bekliyor. Varsayılan 0,5 sn
    # ile her testin sökümü yarım saniye sürüyor ve dosya 15 saniyeye çıkıyordu.
    is_parcacigi = threading.Thread(
        target=sunucu.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True
    )
    is_parcacigi.start()
    try:
        yield f"http://127.0.0.1:{sunucu.server_address[1]}/v1"
    finally:
        sunucu.shutdown()
        sunucu.server_close()


def _sohbet_yaniti(metin: str) -> dict:
    return {"choices": [{"message": {"content": metin}}]}


# --- yapılandırma ---------------------------------------------------------


def test_ayarlar_ortam_degiskenlerinden_okunur(monkeypatch):
    monkeypatch.setenv("BIYO_MOTOR_URL", "http://ornek:9999/v1/")
    monkeypatch.setenv("BIYO_MOTOR_MODELLER", "bir, iki ,, bir")
    monkeypatch.setenv("BIYO_MOTOR_ANAHTARI", "gizli")
    motor = HttpMotor()
    assert motor.url == "http://ornek:9999/v1", "sondaki eğik çizgi atılmalı"
    # Tekrarlar korunmadan sıra bozulmadan elenmeli: aynı modele iki kez
    # düşmek fallback denemesini boşa harcar.
    assert motor.modeller == ["bir", "iki"]
    assert motor.anahtar == "gizli"
    assert motor.ad == "bir@http://ornek:9999/v1"


def test_bos_model_listesi_varsayilana_duser(monkeypatch):
    monkeypatch.setenv("BIYO_MOTOR_MODELLER", " , ")
    assert HttpMotor(url="http://x/v1").modeller == ["yerel"]


# --- geçici / kalıcı hata ayrımı -----------------------------------------


@pytest.mark.parametrize(
    "mesaj",
    ["HTTP 429: quota", "HTTP 503: upstream", "Motor bağlantısı kurulamadı: timeout",
     "HTTP 500: capacity", "bağlantı reddedildi"],
)
def test_gecici_hatalar_taninir(mesaj):
    assert _gecici_mi(mesaj)


@pytest.mark.parametrize(
    "mesaj",
    ["HTTP 400: bozuk istek", "HTTP 401: yetkisiz", "Beklenmeyen yanıt biçimi: {}"],
)
def test_kalici_hatalar_gecici_sayilmaz(mesaj):
    assert not _gecici_mi(mesaj)


# --- uret() ---------------------------------------------------------------


def test_uret_yaniti_dondurur_ve_istegi_dogru_kurar(uc, senaryo):
    senaryo.yanit_ver("yerel", 200, _sohbet_yaniti("Cevap B"))
    motor = HttpMotor(url=uc, modeller=["yerel"], anahtar="anahtar123")

    sonuc = motor.uret([{"role": "user", "content": "Soru?"}], sicaklik=0.7, azami_token=64)

    assert sonuc == "Cevap B"
    (istek,) = senaryo.istekler
    assert istek["model"] == "yerel"
    assert istek["stream"] is False
    assert istek["temperature"] == pytest.approx(0.7)
    assert istek["max_tokens"] == 64
    assert istek["messages"] == [{"role": "user", "content": "Soru?"}]
    assert senaryo.basliklar[0]["Authorization"] == "Bearer anahtar123"


def test_anahtar_yoksa_authorization_basligi_gonderilmez(uc, senaryo):
    senaryo.yanit_ver(None, 200, _sohbet_yaniti("tamam"))
    HttpMotor(url=uc, modeller=["yerel"], anahtar="").uret([{"role": "user", "content": "x"}])
    assert "Authorization" not in senaryo.basliklar[0]


def test_bos_icerik_bos_dizgeye_cevrilir(uc, senaryo):
    """`content: null` dönen uçlar var; None çözücüde patlıyordu."""
    senaryo.yanit_ver(None, 200, {"choices": [{"message": {"content": None}}]})
    assert HttpMotor(url=uc, modeller=["yerel"]).uret([{"role": "user", "content": "x"}]) == ""


def test_beklenmeyen_yanit_bicimi_anlamli_hata_verir(uc, senaryo):
    senaryo.yanit_ver(None, 200, {"beklenmedik": True})
    motor = HttpMotor(url=uc, modeller=["yerel"])
    with pytest.raises(MotorHatasi, match="Beklenmeyen yanıt biçimi"):
        motor.uret([{"role": "user", "content": "x"}])


def test_http_hatasi_govdeyi_mesaja_tasir(uc, senaryo):
    senaryo.yanit_ver(None, 400, {"error": "model bulunamadı"})
    motor = HttpMotor(url=uc, modeller=["yerel"])
    with pytest.raises(MotorHatasi) as bilgi:
        motor.uret([{"role": "user", "content": "x"}])
    assert "HTTP 400" in str(bilgi.value)
    assert "model bulunamadı" in str(bilgi.value)


def test_baglanti_kurulamazsa_anlamli_hata(senaryo):
    """Kapalı porta istek: soket hatası MotorHatasi'na çevrilmeli."""
    motor = HttpMotor(url="http://127.0.0.1:1/v1", modeller=["yerel"], zaman_asimi=1.0)
    with pytest.raises(MotorHatasi, match="Motor bağlantısı kurulamadı"):
        motor.uret([{"role": "user", "content": "x"}])


# --- çok modelli düşme (fallback) ----------------------------------------


def test_gecici_hatada_sonraki_modele_duser(uc, senaryo):
    senaryo.yanit_ver("birinci", 503, {"error": "upstream capacity"})
    senaryo.yanit_ver("ikinci", 200, _sohbet_yaniti("ikinciden geldi"))
    motor = HttpMotor(url=uc, modeller=["birinci", "ikinci"])

    assert motor.uret([{"role": "user", "content": "x"}]) == "ikinciden geldi"
    assert [i["model"] for i in senaryo.istekler] == ["birinci", "ikinci"]


def test_kalici_hatada_sonraki_model_denenmez(uc, senaryo):
    """Sessiz düşme, yanlış modelle sonuç üretmeye yol açar — kasıtlı olarak yok."""
    senaryo.yanit_ver("birinci", 400, {"error": "bozuk istek"})
    senaryo.yanit_ver("ikinci", 200, _sohbet_yaniti("buraya gelinmemeli"))
    motor = HttpMotor(url=uc, modeller=["birinci", "ikinci"])

    with pytest.raises(MotorHatasi, match="HTTP 400"):
        motor.uret([{"role": "user", "content": "x"}])
    assert [i["model"] for i in senaryo.istekler] == ["birinci"]


def test_tum_modeller_gecici_hata_verirse_son_hata_bildirilir(uc, senaryo):
    senaryo.yanit_ver(None, 503, {"error": "upstream capacity"})
    motor = HttpMotor(url=uc, modeller=["bir", "iki"])

    with pytest.raises(MotorHatasi, match="Hiçbir model yanıt vermedi"):
        motor.uret([{"role": "user", "content": "x"}])
    assert [i["model"] for i in senaryo.istekler] == ["bir", "iki"]


# --- uret_akis() ----------------------------------------------------------


def _sse(parca: str) -> str:
    return "data: " + json.dumps({"choices": [{"delta": {"content": parca}}]})


def test_akis_parcalari_sirayla_verir(uc, senaryo):
    senaryo.akis_satirlari = [_sse("Mito"), _sse("kondri"), "data: [DONE]"]
    motor = HttpMotor(url=uc, modeller=["yerel"])

    assert list(motor.uret_akis([{"role": "user", "content": "x"}])) == ["Mito", "kondri"]
    assert senaryo.istekler[0]["stream"] is True


def test_akis_keepalive_ve_bos_delta_satirlarini_atlar(uc, senaryo):
    """Uçlar yorum/keepalive satırı gönderiyor; bunlar parça sayılmamalı."""
    senaryo.akis_satirlari = [
        ": keepalive",
        "",
        "data: bu gecerli json degil",
        "data: " + json.dumps({"choices": [{"delta": {}}]}),
        _sse("tek parça"),
        "data: [DONE]",
    ]
    motor = HttpMotor(url=uc, modeller=["yerel"])
    assert list(motor.uret_akis([{"role": "user", "content": "x"}])) == ["tek parça"]


def test_akis_desteklenmiyorsa_sessiz_kalmaz(uc, senaryo):
    """Uç `stream=True`'yu yok sayarsa boş metin değil, açık hata gelmeli.

    Sessiz boş metin, çözücüde "model yalnız düşünce üretti" gibi yanlış bir
    teşhise dönüşüyordu.
    """
    senaryo.akis_satirlari = ["data: " + json.dumps(_sohbet_yaniti("düz yanıt"))]
    motor = HttpMotor(url=uc, modeller=["yerel"])

    with pytest.raises(MotorHatasi, match="akış"):
        list(motor.uret_akis([{"role": "user", "content": "x"}]))


def test_akista_model_dusurme_yoktur(uc, senaryo):
    """İlk parça tüketiciye gittikten sonra model değişmesi metinleri karıştırırdı."""
    senaryo.akis_satirlari = [_sse("parça"), "data: [DONE]"]
    motor = HttpMotor(url=uc, modeller=["birinci", "ikinci"])

    list(motor.uret_akis([{"role": "user", "content": "x"}]))
    assert [i["model"] for i in senaryo.istekler] == ["birinci"]


def test_akis_baglanti_hatasini_yukseltir(senaryo):
    motor = HttpMotor(url="http://127.0.0.1:1/v1", modeller=["yerel"], zaman_asimi=1.0)
    with pytest.raises(MotorHatasi):
        list(motor.uret_akis([{"role": "user", "content": "x"}]))


def test_akista_http_hatasi_govdeyle_bildirilir(uc, senaryo):
    senaryo.akis_durumu = 502
    motor = HttpMotor(url=uc, modeller=["yerel"])
    with pytest.raises(MotorHatasi) as bilgi:
        list(motor.uret_akis([{"role": "user", "content": "x"}]))
    assert "HTTP 502" in str(bilgi.value)
    assert "akis reddedildi" in str(bilgi.value)


def test_akiste_de_authorization_basligi_gonderilir(uc, senaryo):
    senaryo.akis_satirlari = [_sse("x"), "data: [DONE]"]
    motor = HttpMotor(url=uc, modeller=["yerel"], anahtar="akis-anahtari")
    list(motor.uret_akis([{"role": "user", "content": "x"}]))
    assert senaryo.basliklar[0]["Authorization"] == "Bearer akis-anahtari"


# --- hazir_mi() -----------------------------------------------------------


def test_hazir_mi_uc_ayaktayken_dogru(uc, senaryo):
    senaryo.modeller_ucu_durumu = 200
    assert HttpMotor(url=uc, modeller=["yerel"]).hazir_mi() is True


def test_hazir_mi_uc_kapaliyken_yanlis():
    assert HttpMotor(url="http://127.0.0.1:1/v1", modeller=["yerel"]).hazir_mi() is False


def test_hazir_mi_anahtarli_uca_yetki_basligi_gonderir(uc, senaryo):
    assert HttpMotor(url=uc, modeller=["yerel"], anahtar="k").hazir_mi() is True


def test_hazir_mi_uc_hata_dondururse_yanlis(uc, senaryo):
    senaryo.modeller_ucu_durumu = 500
    assert HttpMotor(url=uc, modeller=["yerel"]).hazir_mi() is False
