"""biyo-cozucu yerel modelini cevap anahtarı üretimine bağlar.

Çalışan bir biyo-cozucu sunucusu (masaüstü .app, 8020-8030) varsa onu kullanır;
yoksa sunucuyu kendi venv'inden alt süreç olarak başlatır (8031-8040) ve
/healthz hazır olana dek bekler. Yalnız kendi başlattığı süreci kapatır.
"""

from __future__ import annotations

import atexit
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlparse

from .yapay_zeka import (
    YapayZekaCevabi,
    YapayZekaHatasi,
    _anahtar_yanitini_ayristir,
    _json_istek,
    _json_metnini_ayikla,
    anahtar_istegi_kur,
)

# Yerel model (4B) bulut istemindeki 12 alanlı iç içe şemayı tutturamıyor:
# ölçüldü, `yontem_adimlari` listesinin İÇİNE `"sonuc": "..."` çifti sokup
# JSON'u bozuyor ve LoRA'nın çoktan seçmeli alışkanlığından "Doğru cevap B
# seçeneğidir" gibi artıklar üretiyor. Bu istem yalnız üç alan ister ve
# rubriği düz metin listesi olarak alır (`_anahtar_yanitini_ayristir` bunu
# zaten destekliyor).
YEREL_ANAHTAR_SISTEM_ISTEMI = (
    "Sen deneyimli bir Türk biyoloji öğretmenisin. Verilen soru için örnek "
    "cevabı ve puanlanabilir rubrik ölçütlerini üret. "
    "SADECE şu JSON'u döndür, başka hiçbir şey yazma: "
    '{"cevaplar":[{"no":1,"cevap":"kısa örnek cevap",'
    '"rubrik":["aranan bilgi 1","aranan bilgi 2"]}]}. '
    "Kurallar: rubrik DÜZ METİN listesidir, nesne değil. Her ölçüt en fazla "
    "12 kelimelik tek bir somut bilgi olsun; 've' ile iki beklentiyi "
    "birleştirme. 'Doğru belirtilmesi', 'açıklanması' gibi meta ölçüt yazma; "
    "beklenen gerçek bilgiyi yaz. Şık harfi ('Doğru cevap B') yazma; soru "
    "açık uçludur. RAG kanıtları verilmişse yalnız o kanıtlarda desteklenen "
    "olguları kullan, bilgi uydurma. JSON dışında açıklama, başlık veya "
    "düşünce yazma."
)

# İlk üretim isteği modeli tembel yükler; /healthz hazır olsa bile dakikalar
# sürebilir. Sonraki istekler sıcak modelde çalışır.
ILK_URETIM_ZAMANASIMI = 300.0
URETIM_ZAMANASIMI = 120.0
_BASLATMA_TAVANI = 60.0

# Sunucu bulma → port ayırma → süreç başlatma dizisi kilitle serileştirilir:
# FastAPI thread pool'undan iki istek aynı anda gelirse ikisi de "sunucu yok"
# görüp ayrı süreç başlatır, ikinci atama birincinin Popen'ını kaybederdi.
_baslatma_kilidi = threading.Lock()
_surec: subprocess.Popen | None = None
_surec_adresi: str | None = None
_model_sicak = False

# Devre kesici: başlatma bir kez çöktüyse rag_anahtar'ın soru başına yeniden
# denemeleri her seferinde 60 sn'lik health-poll bedeli ödemesin. Soğuma
# süresi geçince yeniden denenir (kullanıcı kurulumu düzeltmiş olabilir).
_HATA_SOGUMASI = 120.0
_baslatma_hatasi: str | None = None
_baslatma_hatasi_zamani = 0.0

# Çalışan .app, /api/v1/uret ucundan eski bir sürüm olabilir. Böyle bir adres
# 404 verdiğinde kara listeye alınır ve kendi alt sürecimiz başlatılır;
# kullanıcı .app'i güncelleyene kadar özellik çalışmaya devam eder.
_desteklemeyen_adresler: set[str] = set()


def _biyo_kok() -> Path:
    return Path(
        os.environ.get("SINAV_OKUR_BIYO_KOK", "~/Developer/biyo-cozucu")
    ).expanduser()


def _kayit_yolu() -> Path:
    if os.name == "nt" and os.environ.get("LOCALAPPDATA"):
        return (
            Path(os.environ["LOCALAPPDATA"])
            / "Cumhuriyet" / "sinavokur" / "data" / "logs" / "biyo-motor.log"
        )
    return Path.home() / "Library" / "Logs" / "SinavOkur" / "biyo-motor.log"


def _biyo_calistirilabilir() -> Path:
    """biyo-cozucu'yu başlatacak araç: SINAV_OKUR_BIYO_PY env > platform varsayılanı.

    macOS'ta kurulu venv'in konsol betiği doğrudan çalıştırılabilir; Windows'ta
    paketlenen çalışma zamanı yalnız yorumlayıcıdır ve modül olarak çağrılır
    (bkz. ``_sunucuyu_baslat``).
    """
    ozel = os.environ.get("SINAV_OKUR_BIYO_PY")
    if ozel:
        return Path(ozel).expanduser()
    if os.name == "nt":
        return _biyo_kok() / "runtime" / "python.exe"
    return _biyo_kok() / ".venv" / "bin" / "biyo-cozucu"


_VARSAYILAN_PORTLAR = list(range(8031, 8040))


def _alt_surec_portlari() -> list[int]:
    # 8040 Öğretmen Çantası'na ait (yerel port defteri); aralık 8039'da biter.
    ham = os.environ.get("SINAV_OKUR_BIYO_PORTLAR", "").strip()
    if not ham:
        return list(_VARSAYILAN_PORTLAR)
    try:
        if "-" in ham:
            bas, _, son = ham.partition("-")
            return list(range(int(bas), int(son) + 1))
        return [int(x) for x in ham.split(",") if x.strip()]
    except ValueError:
        # Bozuk ayar, durum sorgusuyla birlikte /yukle ve /referans
        # sayfalarını da 500'e düşürmemeli; varsayılana dönülür.
        return list(_VARSAYILAN_PORTLAR)


def _aday_adresler() -> list[str]:
    ozel = os.environ.get("SINAV_OKUR_BIYO_URL", "").strip().rstrip("/")
    if ozel:
        return [ozel]
    # Önce masaüstü .app aralığı (8020-8030), sonra kendi alt süreç aralığı:
    # önceki oturumdan kalmış bir alt süreç de bu tarama ile yeniden bulunur.
    return [
        f"http://127.0.0.1:{port}"
        for port in [*range(8020, 8031), *_alt_surec_portlari()]
    ]


def yerel_sunucu_bul() -> str | None:
    """Çalışan bir biyo-cozucu sunucusunun adresini döndür; sunucu BAŞLATMAZ."""
    for adres in _aday_adresler():
        if urlparse(adres).hostname not in {"127.0.0.1", "localhost", "::1"}:
            continue
        if adres in _desteklemeyen_adresler:
            continue
        try:
            saglik = _json_istek(f"{adres}/healthz", timeout=0.5)
        except YapayZekaHatasi:
            continue
        if saglik.get("app") == "biyo-cozucu":
            return adres
    return None


def _bos_port() -> int:
    for port in _alt_surec_portlari():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as soket:
            try:
                soket.bind(("127.0.0.1", port))
            except OSError:
                continue
            return port
    raise YapayZekaHatasi(
        "Yerel motor için boş port kalmadı (SINAV_OKUR_BIYO_PORTLAR)."
    )


def _kayit_kuyrugu(satir_sayisi: int = 8) -> str:
    try:
        satirlar = _kayit_yolu().read_text(encoding="utf-8").splitlines()
        return "\n".join(satirlar[-satir_sayisi:])
    except OSError:
        return ""


def _baslatma_hatasini_kaydet(mesaj: str) -> YapayZekaHatasi:
    global _baslatma_hatasi, _baslatma_hatasi_zamani
    _baslatma_hatasi = mesaj
    _baslatma_hatasi_zamani = time.monotonic()
    return YapayZekaHatasi(mesaj)


def _baslatma_komutu(calistirilabilir: Path, port: int, motor: str) -> list[str]:
    """Sunucuyu başlatacak argv listesi; kabuk sarmalayıcı yalnız macOS'ta.

    macOS'ta ortam.sh, ``BIYO_MLX_MODEL`` gibi model yollarını taşır; masaüstü
    .app ile aynı ortamda çalışmak için login kabuğu üzerinden yükleniyor.
    Windows'ta ortam.sh yok; paketlenen yorumlayıcı modül olarak doğrudan
    çağrılır, login kabuğu gerekmez.
    """
    if sys.platform == "darwin":
        komut_metni = (
            "source ~/.biyo-cozucu/ortam.sh 2>/dev/null; "
            f"exec {shlex.quote(str(calistirilabilir))} sunucu "
            f"--adres 127.0.0.1 --port {port} --motor {shlex.quote(motor)}"
        )
        return ["/bin/zsh", "-lc", komut_metni]
    return [
        str(calistirilabilir), "-m", "biyo_cozucu.cli", "sunucu",
        "--adres", "127.0.0.1", "--port", str(port), "--motor", motor,
    ]


def yerel_sunucu_baslat() -> str:
    """biyo-cozucu sunucusunu alt süreç olarak başlat ve hazır olana dek bekle."""
    with _baslatma_kilidi:
        return _sunucuyu_baslat()


def _sunucuyu_baslat() -> str:
    global _surec, _surec_adresi, _baslatma_hatasi
    if (
        _baslatma_hatasi
        and time.monotonic() - _baslatma_hatasi_zamani < _HATA_SOGUMASI
    ):
        raise YapayZekaHatasi(_baslatma_hatasi)
    if (
        _surec is not None
        and _surec.poll() is None
        and _surec_adresi
        and yerel_sunucu_bul() == _surec_adresi
    ):
        return _surec_adresi
    # Kilidi beklerken başka bir iş parçacığı sunucuyu ayağa kaldırmış
    # olabilir; ikinci bir süreç başlatmadan önce yeniden bak.
    mevcut = yerel_sunucu_bul()
    if mevcut is not None:
        return mevcut
    if _surec is not None:
        # Süreç yaşıyor ama /healthz 0,5 sn'de yanıtlamadı (bellek baskısı).
        # Referansın üzerine yazmak, modeliyle birlikte RAM'de kalan takipsiz
        # bir sunucu bırakırdı; 16 GB'ta iki MLX sunucusu makineyi boğar.
        _sureci_sonlandir(_surec)
        _surec = None
        _surec_adresi = None

    calistirilabilir = _biyo_calistirilabilir()
    if not calistirilabilir.is_file():
        raise _baslatma_hatasini_kaydet(
            "biyo-cozucu kurulumu bulunamadı: "
            f"{calistirilabilir} yok. SINAV_OKUR_BIYO_KOK veya "
            "SINAV_OKUR_BIYO_PY ile yolu belirtin."
        )

    port = _bos_port()
    motor = os.environ.get("SINAV_OKUR_BIYO_MOTOR", "mlx")
    kayit = _kayit_yolu()
    kayit.parent.mkdir(parents=True, exist_ok=True)
    komut = _baslatma_komutu(calistirilabilir, port, motor)
    with kayit.open("ab") as kayit_dosyasi:
        surec = subprocess.Popen(
            komut,
            stdout=kayit_dosyasi,
            stderr=subprocess.STDOUT,
            cwd=_biyo_kok(),
        )

    adres = f"http://127.0.0.1:{port}"
    son = time.monotonic() + _BASLATMA_TAVANI
    while time.monotonic() < son:
        if surec.poll() is not None:
            raise _baslatma_hatasini_kaydet(
                "biyo-cozucu sunucusu başlatılamadı "
                f"(çıkış kodu {surec.returncode}). Son kayıt:\n{_kayit_kuyrugu()}"
            )
        try:
            saglik = _json_istek(f"{adres}/healthz", timeout=0.5)
            if saglik.get("app") == "biyo-cozucu":
                break
        except YapayZekaHatasi:
            pass
        time.sleep(0.4)
    else:
        _sureci_sonlandir(surec)
        raise _baslatma_hatasini_kaydet(
            "biyo-cozucu sunucusu zamanında hazır olmadı. "
            f"Son kayıt:\n{_kayit_kuyrugu()}"
        )

    if _surec is None:
        atexit.register(yerel_sunucuyu_kapat)
    _surec = surec
    _surec_adresi = adres
    _baslatma_hatasi = None
    return adres


def _sureci_sonlandir(surec: subprocess.Popen) -> None:
    """Süreci kapat ve MUTLAKA reap et; aksi hâlde zombi kalır."""
    if surec.poll() is not None:
        surec.wait()
        return
    surec.terminate()
    try:
        surec.wait(timeout=5)
    except subprocess.TimeoutExpired:
        surec.kill()
        try:
            surec.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass


def yerel_sunucuyu_kapat() -> None:
    """Yalnız kendi başlattığımız alt süreci kapat; .app'e dokunma."""
    global _surec, _surec_adresi, _model_sicak
    with _baslatma_kilidi:
        if _surec is not None:
            _sureci_sonlandir(_surec)
        _surec = None
        _surec_adresi = None
        _model_sicak = False


def yerel_motor_durumu() -> dict:
    """Arayüz rozeti için durum; sunucu BAŞLATMAZ."""
    try:
        adres = yerel_sunucu_bul()
    except (ValueError, TypeError) as exc:
        # SINAV_OKUR_BIYO_PORTLAR bozuk yazılmış olabilir; durum sorgusu
        # /yukle ve /referans sayfalarını da beslediği için 500'e dönüşmemeli.
        return {
            "hazir": False,
            "kullanilabilir": False,
            "mesaj": f"Yerel motor ayarı okunamadı: {exc}",
        }
    if adres is not None:
        return {
            "hazir": True,
            "kullanilabilir": True,
            "mesaj": f"Yerel motor hazır · {adres}",
        }
    # Son başlatma denemesi çöktüyse motoru "kullanılabilir" sayma: üretici
    # seçimi buna bakıyor ve bozuk bir yerel motor, çalışan Claude API'yi
    # gölgeleyip her soruyu sessizce puanlanamaz taslağa düşürürdü.
    if (
        _baslatma_hatasi
        and time.monotonic() - _baslatma_hatasi_zamani < _HATA_SOGUMASI
    ):
        return {
            "hazir": False,
            "kullanilabilir": False,
            "mesaj": f"Yerel motor başlatılamadı: {_baslatma_hatasi.splitlines()[0]}",
        }
    calistirilabilir = _biyo_calistirilabilir()
    if calistirilabilir.is_file():
        return {
            "hazir": False,
            "kullanilabilir": True,
            "mesaj": "Yerel motor kurulu; ilk kullanımda başlatılacak.",
        }
    return {
        "hazir": False,
        "kullanilabilir": False,
        "mesaj": "biyo-cozucu kurulumu bulunamadı; yerel motor kapalı.",
    }


def _bozuk_json_kurtar(metin: str) -> dict | None:
    """Küçük modelin bozduğu anahtar JSON'undan no/cevap/rubrik'i kurtarır.

    Ölçülen bozulma: model bir dizinin içine ``"sonuc": "..."`` çifti sokup
    JSON'u geçersiz kılıyor. Cevap veya ölçüt UYDURULMAZ; yalnız metinde
    zaten yazan alanlar okunur, hiçbiri bulunamazsa None döner.
    """
    def _coz(ham: str) -> str:
        # json.loads tek bir dizeyi çözerken kaçışları da Türkçe harfleri de
        # doğru işler; unicode_escape "ü"yü bozuyordu.
        try:
            return str(json.loads(f'"{ham}"'))
        except ValueError:
            return ham

    kayitlar = []
    for parca in re.finditer(
        r'"no"\s*:\s*(\d+).*?"cevap"\s*:\s*"((?:[^"\\]|\\.)*)"'
        r'.*?"rubrik"\s*:\s*\[(.*?)\]',
        metin,
        re.DOTALL,
    ):
        no, cevap, ham_rubrik = parca.groups()
        olcutler = [
            _coz(x)
            for x in re.findall(r'"((?:[^"\\]|\\.)*)"', ham_rubrik)
            if x.strip()
        ]
        # Nesne biçimli rubrikte alan adları da tırnaklıdır; onları ele.
        olcutler = [
            x
            for x in olcutler
            if x
            not in {
                "olcut",
                "esanlamlilar",
                "kategori",
                "celiskiler",
                "metin",
            }
        ]
        if olcutler:
            kayitlar.append(
                {"no": int(no), "cevap": _coz(cevap), "rubrik": olcutler}
            )
    return {"cevaplar": kayitlar} if kayitlar else None


def _sohbet_isaretlerini_temizle(metin: str) -> str:
    """Modelin bıraktığı sohbet şablonu işaretlerini at (ölçüldü: <|im_end|>)."""
    for isaret in ("<|im_end|>", "<|endoftext|>", "<|im_start|>"):
        metin = metin.replace(isaret, " ")
    return metin.strip()


def yerel_uret(
    mesajlar: list[dict],
    *,
    sicaklik: float = 0.2,
    azami_token: int = 2048,
    zamanasimi: float | None = None,
) -> str:
    """Yerel motora tek üretim isteği gönder; gerekirse sunucuyu başlat."""
    global _model_sicak
    sure = zamanasimi or (
        URETIM_ZAMANASIMI if _model_sicak else ILK_URETIM_ZAMANASIMI
    )
    veri = {
        "mesajlar": mesajlar,
        "sicaklik": sicaklik,
        "azami_token": azami_token,
    }
    # Her eski sürüm sunucu bir denemeyi tüketir; aday havuzu bittiğinde
    # kendi alt sürecimize düşülür. Sabit iki deneme, iki eski .app varken
    # kendi sürecimizi hiç başlatmadan hata verirdi.
    azami_deneme = len(_aday_adresler()) + 1
    for _deneme in range(azami_deneme):
        adres = yerel_sunucu_bul() or yerel_sunucu_baslat()
        try:
            yanit = _json_istek(f"{adres}/api/v1/uret", veri=veri, timeout=sure)
        except YapayZekaHatasi as exc:
            if "HTTP 404" not in str(exc) or adres == _surec_adresi:
                # _json_istek hatayı genel "Yerel sunucu" adıyla yazıyor;
                # mesajda hangi yerel sunucu olduğu görünsün.
                raise YapayZekaHatasi(
                    "Yerel motor isteği başarısız: "
                    + str(exc).replace("Yerel sunucu", "biyo-cozucu")
                ) from exc
            # Eski sürüm bir .app: bu adresi bırak, kendi sürecimizi kur.
            _desteklemeyen_adresler.add(adres)
            continue
        metin = _sohbet_isaretlerini_temizle(str(yanit.get("metin", "")))
        if not metin:
            raise YapayZekaHatasi("Yerel motor boş yanıt döndürdü.")
        _model_sicak = True
        return metin
    raise YapayZekaHatasi(
        "Yerel motor sunucusunda /api/v1/uret ucu yok; biyo-cozucu "
        "uygulamasını güncelleyin."
    )


def yerel_cevap_anahtarlari_uret(
    sorular: list[tuple[int, str, float]],
    *,
    ders: str = "",
    model: str | None = None,
    kanitlar: dict[int, list[dict[str, str]]] | None = None,
) -> list[YapayZekaCevabi]:
    """cevap_anahtarlari_uret ile aynı protokol; üretim yerel motorda.

    Küçük yerel model uzun grupları atlayabildiği için sorular hep tek tek
    gönderilir ve soru başına iki deneme yapılır. ``model`` protokol uyumu
    için durur; yerel motorda model seçimi sunucu tarafındadır.
    """
    del model
    if not sorular:
        return []
    sinirli = [
        {"no": int(no), "soru": str(metin)[:7000], "puan": float(puan)}
        for no, metin, puan in sorular[:30]
    ]
    tum_cevaplar: list[YapayZekaCevabi] = []
    for soru in sinirli:
        beklenen = {soru["no"]}
        kullanici = anahtar_istegi_kur([soru], ders=ders, kanitlar=kanitlar)
        mesajlar = [
            {"role": "system", "content": YEREL_ANAHTAR_SISTEM_ISTEMI},
            {"role": "user", "content": kullanici},
        ]
        son_hata: YapayZekaHatasi | None = None
        for _deneme in range(2):
            try:
                metin = yerel_uret(mesajlar)
            except YapayZekaHatasi as exc:
                son_hata = exc
                continue
            try:
                veri = _json_metnini_ayikla(metin)
            except YapayZekaHatasi as exc:
                veri = _bozuk_json_kurtar(metin)
                if veri is None:
                    son_hata = exc
                    continue
            sonuclar = _anahtar_yanitini_ayristir(veri, beklenen)
            if {x.soru_no for x in sonuclar} == beklenen:
                tum_cevaplar.extend(sonuclar)
                break
            son_hata = YapayZekaHatasi(
                f"Yerel motor {soru['no']}. soru için cevap üretmedi."
            )
        else:
            raise son_hata or YapayZekaHatasi("Yerel motor yanıt üretemedi.")
    return tum_cevaplar
