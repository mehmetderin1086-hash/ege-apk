"""Onay kuyruğu — videodan çıkarılan adayların hafıza öncesi bekleme alanı.

Kuyruk SQLite değil JSONL dosyalarıdır (`<kök>/kuyruk/<tarih>-<video_id>.jsonl`):
geçici veri kalıcı şemaya girseydi göç yükü doğardı; whisper Türkçe terimleri
bozabildiği için kullanıcı satırı düz metin editöründe de düzeltebilmeli; proje
zaten JSONL alışverişine dayalı. Onaylanan dosya `alinan/` altına arşivlenir.

Yazımlar atomiktir (.tmp + os.replace). Ayrıştırılamayan satırlar okurken
sayılır, yeniden yazarken OLDUĞU GİBİ korunur — "başarılı" görünüp veri silen
bir kuyruk, en pahalı hata sınıfıdır.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import threading
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

DURUMLAR = ("bekliyor", "onay", "ret", "alindi")
SURUM = 1

# Web/CLI düzenlemesinin dokunabildiği alanlar. `video_id`, `kaynak_imzasi`,
# `guven`, `dayanak`, `olusturma` bilinçli olarak DIŞARIDA: bunlar çıkarımın
# kanıt zinciridir; düzenlenebilir olsalardı "model bunu nereden çıkardı"
# sorusunun yanıtı kaybolurdu.
DUZENLENEBILIR_ALANLAR = {
    "soru", "cozum", "cevap", "secenekler", "cevap_turu", "konu",
    "cozum_turu", "notu",
}
_METIN_ALANLARI = {"soru", "cozum", "cevap"}

# Kayıt sözlüğünde tanınan anahtarlar; gerisi `ekstra`da korunur.
_BILINEN_ALANLAR = {
    "surum", "kimlik", "durum", "video_id", "video_basligi", "kanal", "url",
    "kaynak_imzasi", "kaynak", "konum", "baslangic_sn", "soru", "secenekler",
    "cevap", "cozum", "cevap_turu", "konu", "cozum_turu", "guven", "dayanak",
    "yontem", "uyarilar", "not", "olusturma", "ornek_id",
}

_kilit_sozlugu_kilidi = threading.Lock()
_dosya_kilitleri: dict[str, threading.Lock] = {}


def yeni_kimlik() -> str:
    """Kayıt için kalıcı kimlik.

    Sıra numarası kimlik OLARAK KULLANILAMAZ: aktarım döngüsü dosyayı okuyup
    yavaş bir işten (gömme + indeksleme) sonra yeniden yazıyor; arada geçerli
    kayıt sayısı değişirse (bir kaydın sorusu boşaltılınca kayıt okunamaz
    hâle gelir) tüm eşleme kayar ve hiç yazılmamış bir kayıt "alindi"
    damgası yiyip sessizce kaybolur.
    """
    return uuid.uuid4().hex[:12]


@contextmanager
def _dosya_kilidi(yol: Path) -> Iterator[None]:
    """Kuyruk dosyasını oku-değiştir-yaz boyunca kilitler.

    İki katman gerekiyor: FastAPI'nin senkron rotaları gerçek bir iş parçacığı
    havuzunda paralel koştuğu için iplik kilidi, CLI ile arayüz aynı anda
    çalışabildiği için de `flock`. Kilit olmadan iki yazıcı aynı geçici
    dosyayı kullanıp birbirinin yazımını yarıda kesebiliyordu.
    """
    anahtar = str(yol.resolve() if yol.exists() else yol.absolute())
    with _kilit_sozlugu_kilidi:
        kilit = _dosya_kilitleri.setdefault(anahtar, threading.Lock())
    with kilit:
        yol.parent.mkdir(parents=True, exist_ok=True)
        kilit_yolu = yol.with_suffix(yol.suffix + ".lock")
        with kilit_yolu.open("w") as bayrak:
            fcntl.flock(bayrak, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(bayrak, fcntl.LOCK_UN)


@dataclass
class KuyrukKaydi:
    """Kuyruktaki tek aday — onaylanınca `Ornek`'e çevrilir."""

    soru: str
    cozum: str = ""
    cevap: str = ""
    cevap_turu: str = ""
    secenekler: dict[str, str] = field(default_factory=dict)
    konu: str = ""
    cozum_turu: str = ""
    durum: str = "bekliyor"
    video_id: str = ""
    video_basligi: str = ""
    kanal: str = ""
    url: str = ""
    kaynak_imzasi: str = ""
    kaynak: str = ""
    konum: str = ""
    baslangic_sn: float | None = None
    guven: float = 0.5
    dayanak: float = 1.0
    yontem: str = "model"           # model | kural
    uyarilar: list[str] = field(default_factory=list)
    notu: str = ""                  # onaylayanın serbest notu
    olusturma: str = ""
    ornek_id: int | None = None
    surum: int = SURUM
    # Kalıcı kimlik: konum değil kayıt kimliği. Bkz. `yeni_kimlik`.
    kimlik: str = field(default_factory=yeni_kimlik)
    # Şemanın tanımadığı alanlar (kullanıcının elle eklediği ya da ileri
    # sürümden gelen). Yeniden yazımda korunur; modül dosyanın elle
    # düzenlenebilir olduğunu vaat ediyor, sessizce alan silmemeli.
    ekstra: dict = field(default_factory=dict)

    def izleme_adresi(self) -> str:
        """Onay arayüzündeki derin bağlantı — insanın kanıt denetimi."""
        if not self.video_id:
            return self.url
        adres = f"https://youtu.be/{self.video_id}"
        if self.baslangic_sn and self.baslangic_sn > 0:
            adres += f"?t={int(self.baslangic_sn)}"
        return adres

    def guvenli_izleme_adresi(self) -> str:
        """`href`e konulabilecek adres; şema denetimli.

        `url` alanı elle düzenlenebilir bir JSONL'den geliyor ve HTML kaçışı
        `javascript:` şemasını durdurmaz. Video kimliği varsa adres zaten
        bizim kurduğumuz sabit biçimde; yoksa yalnız http(s) geçirilir.
        """
        adres = self.izleme_adresi()
        return adres if adres.startswith(("https://", "http://")) else ""

    def sozluk(self) -> dict:
        veri = {
            **self.ekstra,
            "surum": self.surum,
            "kimlik": self.kimlik,
            "durum": self.durum,
            "video_id": self.video_id,
            "video_basligi": self.video_basligi,
            "kanal": self.kanal,
            "url": self.url,
            "kaynak_imzasi": self.kaynak_imzasi,
            "kaynak": self.kaynak,
            "konum": self.konum,
            "baslangic_sn": self.baslangic_sn,
            "soru": self.soru,
            "secenekler": dict(self.secenekler),
            "cevap": self.cevap,
            "cozum": self.cozum,
            "cevap_turu": self.cevap_turu,
            "konu": self.konu,
            "cozum_turu": self.cozum_turu,
            "guven": self.guven,
            "dayanak": self.dayanak,
            "yontem": self.yontem,
            "uyarilar": list(self.uyarilar),
            "not": self.notu,
            "olusturma": self.olusturma,
        }
        if self.ornek_id is not None:
            veri["ornek_id"] = self.ornek_id
        return veri


def sozlukten_kayit(veri: dict) -> KuyrukKaydi | None:
    soru = str(veri.get("soru") or "").strip()
    if not soru:
        return None
    durum = str(veri.get("durum") or "bekliyor")
    if durum not in DURUMLAR:
        durum = "bekliyor"
    ham_baslangic = veri.get("baslangic_sn")
    ornek_id = veri.get("ornek_id")
    # Kimliksiz eski dosyalar: içerikten türet ki aynı dosya iki kez
    # okunduğunda aynı kimliği versin (rastgele üretmek, ilk yeniden
    # yazımdan önce yapılan eşlemeleri bozardı).
    kimlik = str(veri.get("kimlik") or "").strip() or hashlib.sha256(
        f"{veri.get('video_id', '')}|{soru}".encode()
    ).hexdigest()[:12]
    return KuyrukKaydi(
        soru=soru,
        cozum=str(veri.get("cozum") or ""),
        cevap=str(veri.get("cevap") or ""),
        cevap_turu=str(veri.get("cevap_turu") or ""),
        secenekler={
            str(k): str(v) for k, v in (veri.get("secenekler") or {}).items()
        },
        konu=str(veri.get("konu") or ""),
        cozum_turu=str(veri.get("cozum_turu") or ""),
        durum=durum,
        video_id=str(veri.get("video_id") or ""),
        video_basligi=str(veri.get("video_basligi") or ""),
        kanal=str(veri.get("kanal") or ""),
        url=str(veri.get("url") or ""),
        kaynak_imzasi=str(veri.get("kaynak_imzasi") or ""),
        kaynak=str(veri.get("kaynak") or ""),
        konum=str(veri.get("konum") or ""),
        baslangic_sn=(
            float(ham_baslangic)
            if isinstance(ham_baslangic, (int, float))
            else None
        ),
        guven=float(veri.get("guven") or 0.0),
        dayanak=float(veri.get("dayanak") or 0.0),
        yontem=str(veri.get("yontem") or "model"),
        uyarilar=[str(u) for u in (veri.get("uyarilar") or [])],
        notu=str(veri.get("not") or ""),
        olusturma=str(veri.get("olusturma") or ""),
        ornek_id=int(ornek_id) if isinstance(ornek_id, int) else None,
        surum=int(veri.get("surum") or SURUM),
        kimlik=kimlik,
        ekstra={k: v for k, v in veri.items() if k not in _BILINEN_ALANLAR},
    )


def kuyruk_dizini(kok: Path) -> Path:
    dizin = kok / "kuyruk"
    dizin.mkdir(parents=True, exist_ok=True)
    return dizin


def alinmis_dizini(kok: Path) -> Path:
    dizin = kuyruk_dizini(kok) / "alinan"
    dizin.mkdir(parents=True, exist_ok=True)
    return dizin


def dosya_adi(video_id: str, *, zaman: datetime | None = None) -> str:
    zaman = zaman or datetime.now()
    return f"{zaman:%Y%m%d-%H%M%S}-{video_id}.jsonl"


def dosyalar(kok: Path) -> list[Path]:
    """Bekleyen kuyruk dosyaları (arşiv hariç), ada göre sıralı."""
    return sorted(p for p in kuyruk_dizini(kok).glob("*.jsonl") if p.is_file())


def bul(kok: Path, ad: str) -> Path | None:
    """Adı kuyruk dizinindeki dosyalarla eşleştirir.

    Web rotası dosya adını istekten alıyor; adı doğrudan yola çevirmek yerine
    yalnız dizindeki gerçek dosyalarla eşleştirmek yol kaçışını (`../…`)
    baştan imkânsız kılar.
    """
    ad = Path(ad).name
    for yol in dosyalar(kok):
        if yol.name == ad:
            return yol
    return None


def kuyrukta_mi(kok: Path, video_id: str) -> bool:
    """Videonun bekleyen bir kuyruk dosyası var mı?

    `kaynagi_isaretle` yalnız onay aktarımında çağrıldığından, kuyruğa yazılmış
    ama henüz onaylanmamış video depo kaydında görünmez; ikinci `youtube-al`
    koşusunun aynı videoyu yeniden dökmemesi için buraya da bakılır.
    """
    return any(kuyruk_dizini(kok).glob(f"*-{video_id}.jsonl"))


def _atomik_yaz(yol: Path, govde: str) -> None:
    """Geçici dosya + `os.replace`.

    Geçici ad YAZICIYA özel: dosya başına tek `.tmp` adı kullanmak, iki
    eşzamanlı yazıcının birbirinin geçici dosyasını kırpmasına ve
    `os.replace`in yarım dosyayı gerçek ada taşımasına yol açıyordu.
    """
    yol.parent.mkdir(parents=True, exist_ok=True)
    gecici = yol.with_suffix(
        f"{yol.suffix}.{os.getpid()}.{threading.get_ident()}.tmp"
    )
    try:
        gecici.write_text(govde, encoding="utf-8")
        os.replace(gecici, yol)
    finally:
        gecici.unlink(missing_ok=True)


def yaz(yol: Path, kayitlar: list[KuyrukKaydi]) -> None:
    govde = "".join(
        json.dumps(k.sozluk(), ensure_ascii=False) + "\n" for k in kayitlar
    )
    with _dosya_kilidi(yol):
        _atomik_yaz(yol, govde)


def _satirlari_oku(yol: Path) -> list[tuple[str, KuyrukKaydi | None]]:
    """(ham satır, kayıt|None) çiftleri — bozuk satır ham hâliyle korunur."""
    ciftler: list[tuple[str, KuyrukKaydi | None]] = []
    try:
        metin = yol.read_text(encoding="utf-8")
    except OSError:
        return []
    for ham in metin.splitlines():
        if not ham.strip():
            continue
        try:
            veri = json.loads(ham)
        except json.JSONDecodeError:
            ciftler.append((ham, None))
            continue
        kayit = sozlukten_kayit(veri) if isinstance(veri, dict) else None
        ciftler.append((ham, kayit))
    return ciftler


def oku(yol: Path) -> tuple[list[KuyrukKaydi], int]:
    """Dosyadaki kayıtlar + ayrıştırılamayan satır sayısı."""
    ciftler = _satirlari_oku(yol)
    kayitlar = [k for _, k in ciftler if k is not None]
    return kayitlar, len(ciftler) - len(kayitlar)


def _geri_yaz(yol: Path, ciftler: list[tuple[str, KuyrukKaydi | None]]) -> None:
    govde = "".join(
        (json.dumps(k.sozluk(), ensure_ascii=False) if k is not None else ham) + "\n"
        for ham, k in ciftler
    )
    _atomik_yaz(yol, govde)


def _kaydi_sec(kayitlar: list[KuyrukKaydi], hedef: int | str) -> KuyrukKaydi:
    """Hedefi (kalıcı kimlik ya da 1 tabanlı sıra) kayda çevirir."""
    if isinstance(hedef, str):
        for kayit in kayitlar:
            if kayit.kimlik == hedef:
                return kayit
        raise ValueError(f"Kayıt bulunamadı: {hedef}")
    if not 1 <= hedef <= len(kayitlar):
        raise ValueError(
            f"Sıra {hedef} dosyada yok (1-{len(kayitlar)} arası bekleniyor)."
        )
    return kayitlar[hedef - 1]


def kimlikleri_coz(yol: Path, hedefler: list[int]) -> list[str]:
    """Sıra numaralarını kalıcı kimliklere çevirir (arayüz formu için)."""
    kayitlar, _ = oku(yol)
    return [_kaydi_sec(kayitlar, hedef).kimlik for hedef in hedefler]


def durumlari_isaretle(yol: Path, hedefler: list[int | str], durum: str) -> int:
    """Kayıtların durumunu değiştirir; hedef kimlik ya da 1 tabanlı sıra."""
    if durum not in DURUMLAR:
        raise ValueError(f"Geçersiz durum: {durum!r} (beklenen: {DURUMLAR})")
    with _dosya_kilidi(yol):
        ciftler = _satirlari_oku(yol)
        # Kayıt nesneleri `ciftler` içindekilerle AYNI nesneler; buradaki
        # değişiklik `_geri_yaz`a yansır, bozuk satırlar ham hâliyle korunur.
        kayitlar = [k for _, k in ciftler if k is not None]
        degisen = 0
        for hedef in dict.fromkeys(hedefler):
            kayit = _kaydi_sec(kayitlar, hedef)
            if kayit.durum != durum:
                kayit.durum = durum
                degisen += 1
        if degisen:
            _geri_yaz(yol, ciftler)
        return degisen


def satiri_guncelle(yol: Path, hedef: int | str, alanlar: dict) -> KuyrukKaydi:
    """Tek kaydın düzenlenebilir alanlarını günceller, kaydı döndürür."""
    with _dosya_kilidi(yol):
        return _satiri_guncelle(yol, hedef, alanlar)


def _satiri_guncelle(yol: Path, hedef: int | str, alanlar: dict) -> KuyrukKaydi:
    ciftler = _satirlari_oku(yol)
    kayitlar = [k for _, k in ciftler if k is not None]
    kayit = _kaydi_sec(kayitlar, hedef)

    degisti = False
    for ad, deger in alanlar.items():
        if ad not in DUZENLENEBILIR_ALANLAR:
            continue
        if ad == "secenekler":
            deger = {str(k): str(v) for k, v in (deger or {}).items()}
        else:
            deger = str(deger or "")
        if ad == "soru" and not deger.strip():
            # Boş soru kaydı okunamaz hâle getirir: satır "bozuk" sayılır,
            # arayüzden bir daha düzenlenemez ve altındaki kayıtların sıra
            # numaraları kayar. Reddetmek istiyorsa durum işareti var.
            raise ValueError(
                "Soru metni boş bırakılamaz; kaydı istemiyorsanız reddedin."
            )
        if getattr(kayit, ad) == deger:
            continue
        setattr(kayit, ad, deger)
        degisti = True
        if ad in _METIN_ALANLARI and "elle_duzenlendi" not in kayit.uyarilar:
            kayit.uyarilar.append("elle_duzenlendi")
    if degisti:
        _geri_yaz(yol, ciftler)
    return kayit


def alindi_isaretle(yol: Path, sonuclar: dict[str, int]) -> None:
    """{kalıcı kimlik: örnek id} eşlemesindeki kayıtları `alindi` yapar.

    Kimlik zorunlu, sıra numarası DEĞİL: aktarım döngüsü dosyayı okur, her
    kayıt için yavaş bir iş (gömme + indeksleme) yapar, sonra dosyayı
    yeniden okur. Arada kayıt sayısı değişirse sıra tabanlı eşleme kayar ve
    hiç yazılmamış bir kayıt "alindi" damgası yiyip sessizce kaybolur.
    """
    with _dosya_kilidi(yol):
        ciftler = _satirlari_oku(yol)
        kimlikli = {k.kimlik: k for _, k in ciftler if k is not None}
        for kimlik, ornek_id in sonuclar.items():
            kayit = kimlikli.get(kimlik)
            if kayit is None:
                continue
            kayit.durum = "alindi"
            kayit.ornek_id = ornek_id
        _geri_yaz(yol, ciftler)


@dataclass
class KuyrukOzeti:
    dosya_sayisi: int = 0
    bekleyen: int = 0
    onayli: int = 0
    reddedilen: int = 0
    alinan: int = 0
    bozuk: int = 0

    @property
    def toplam(self) -> int:
        return self.bekleyen + self.onayli + self.reddedilen + self.alinan


def ozet(kok: Path) -> KuyrukOzeti:
    sonuc = KuyrukOzeti()
    for yol in dosyalar(kok):
        kayitlar, bozuk = oku(yol)
        sonuc.dosya_sayisi += 1
        sonuc.bozuk += bozuk
        for kayit in kayitlar:
            if kayit.durum == "bekliyor":
                sonuc.bekleyen += 1
            elif kayit.durum == "onay":
                sonuc.onayli += 1
            elif kayit.durum == "ret":
                sonuc.reddedilen += 1
            else:
                sonuc.alinan += 1
    return sonuc


def ornege_cevir(kayit: KuyrukKaydi):
    """Onaylanmış kaydı `Ornek`'e çevirir; soru/çözüm boşsa None.

    Konu/tür boşsa `kural_ile_etiketle` ile YENİDEN etiketlenir: kullanıcı
    onay ekranında metni düzeltmiş olabilir ve eski etikete güvenilemez.
    """
    from ..hafiza.etiketleme import kural_ile_etiketle
    from ..modeller import Ornek
    from ..soru_turu import cevap_turunu_cikar

    if not kayit.soru.strip() or not kayit.cozum.strip():
        return None
    konu, tur = kayit.konu, kayit.cozum_turu
    if not konu or not tur:
        kural_konu, kural_tur = kural_ile_etiketle(kayit.soru, kayit.cozum)
        konu = konu or kural_konu
        tur = tur or kural_tur
    cevap_turu = kayit.cevap_turu or cevap_turunu_cikar(
        kayit.soru, kayit.secenekler, kayit.cozum
    )
    etiketler = ["youtube"]
    if kayit.video_id:
        etiketler.append(kayit.video_id)
    return Ornek(
        soru=kayit.soru.strip(),
        cozum=kayit.cozum.strip(),
        cevap=kayit.cevap.strip(),
        cevap_turu=cevap_turu,
        secenekler=dict(kayit.secenekler),
        konu=konu,
        cozum_turu=tur,
        etiketler=etiketler,
        kaynak=f"{kayit.kaynak} ({kayit.konum})" if kayit.konum else kayit.kaynak,
        etiket_kaynagi="kural",
    )


def arsivle(yol: Path, kok: Path) -> Path:
    """Dosyayı `alinan/` altına taşır; ad çakışırsa üzerine YAZMAZ."""
    hedef_dizin = alinmis_dizini(kok)
    hedef = hedef_dizin / yol.name
    ek = 1
    while hedef.exists():
        hedef = hedef_dizin / f"{yol.stem}-{ek}{yol.suffix}"
        ek += 1
    os.replace(yol, hedef)
    return hedef
