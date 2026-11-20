"""YouTube soru çözümü videolarından ses alımı (yt-dlp + whisper.cpp).

yt-dlp Python paketi `youtube` ekstrasıyla kurulabilir ama her hâlde alt
süreç olarak çağrılır: `--dump-single-json` / `-f bestaudio` sözleşmesi
kararlıdır, `yt_dlp.YoutubeDL`'in iç yapısı değil; extractor'lar sık
bozulduğu için kullanıcı ikiliyi projeden bağımsız güncelleyebilmeli ve
bozuk bir extractor CLI'nin kendisini değil alt süreci düşürmeli.

Ses geçici, transkript kalıcıdır: asıl pahalı iş yazıya dökme. Transkript
`<kök>/youtube/transkript/<video_id>.json`'da saklanır; kuyruk silinip
çıkarım yeniden yapılmak istendiğinde indirme ve döküm tekrarlanmaz.

Çözümleme zinciri: BIYO_YTDLP → PATH'teki `yt-dlp` → `python -m yt_dlp`.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

from .cikarim import AZAMI_BOYUT_MB, AlimHatasi, Kaynak, Parca

# Künye çekme saniyeler sürer; indirme uzun videoda dakikalar alabilir.
KUNYE_ZAMAN_ASIMI_SN = 120
INDIRME_ZAMAN_ASIMI_SN = 3600

_YOUTUBE_ALANLARI = {
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
}


@dataclass
class YoutubeVideo:
    """Bir videonun künyesi — indirme ve atıf için gereken asgari bilgi."""

    video_id: str
    baslik: str = ""
    kanal: str = ""
    sure_sn: float = 0.0
    url: str = ""

    @property
    def imza(self) -> str:
        return video_imzasi(self.video_id)

    def izleme_adresi(self) -> str:
        return self.url or f"https://www.youtube.com/watch?v={self.video_id}"

    def kaynak_adi(self) -> str:
        """`Ornek.kaynak` alanına yazılacak insan-okunur atıf tabanı."""
        ad = self.baslik or self.video_id
        return f"YouTube: {ad} — {self.kanal}" if self.kanal else f"YouTube: {ad}"


def video_imzasi(video_id: str) -> str:
    """Kaynak-düzeyi yineleme koruması için imza.

    Dosya İÇERİĞİNE bağlı değil, bilinçli olarak: format seçimi değişince
    içerik imzası kayar ve ses dosyası döküm sonrası silindiği için yeniden
    hesaplanamaz. Video kimliği ise kalıcı.
    """
    return hashlib.sha256(f"youtube:{video_id}".encode()).hexdigest()[:16]


def _ytdlp_komutu() -> list[str]:
    ham = os.environ.get("BIYO_YTDLP", "")
    if ham:
        return [ham]
    bulunan = shutil.which("yt-dlp")
    if bulunan:
        return [bulunan]
    try:
        import yt_dlp  # noqa: F401
    except ImportError:
        raise AlimHatasi(
            "yt-dlp bulunamadı. `uv sync --extra youtube` ile kurun "
            "ya da yolu BIYO_YTDLP ile verin."
        ) from None
    return [sys.executable, "-m", "yt_dlp"]


def _url_dogrula(url: str) -> str:
    """Yalnız YouTube adreslerine izin verir — CLI ve web aynı kapıdan geçer."""
    try:
        parcalar = urlsplit(url.strip())
        alan_ham = parcalar.hostname
    except ValueError as exc:
        # Bozuk adres (`http://[` gibi) `urlsplit`ten ValueError kaldırıyor;
        # çağıranlar `AlimHatasi` bekliyor ve web rotası bunu yakalamadığı
        # için 500 dönüyordu.
        raise AlimHatasi(f"Adres çözümlenemedi: {url!r} ({exc})") from exc
    if parcalar.scheme not in {"http", "https"}:
        raise AlimHatasi(f"Geçersiz adres: {url!r} (http/https bekleniyor).")
    alan = (alan_ham or "").casefold()
    if alan not in _YOUTUBE_ALANLARI:
        raise AlimHatasi(f"Yalnız YouTube adresleri destekleniyor: {url!r}")
    return url.strip()


def _ytdlp_calistir(argumanlar: list[str], *, zaman_asimi: float) -> str:
    komut = _ytdlp_komutu() + argumanlar
    try:
        sonuc = subprocess.run(  # noqa: S603 - komut bizim denetimimizde
            komut, capture_output=True, text=True, timeout=zaman_asimi
        )
    except subprocess.TimeoutExpired as exc:
        raise AlimHatasi(f"yt-dlp zaman aşımına uğradı ({int(zaman_asimi)} sn).") from exc
    except OSError as exc:
        raise AlimHatasi(f"yt-dlp çalıştırılamadı: {exc}") from exc
    if sonuc.returncode != 0:
        ayrinti = (sonuc.stderr or "").strip()[-400:]
        raise AlimHatasi(f"yt-dlp başarısız (kod {sonuc.returncode}): {ayrinti}")
    return sonuc.stdout


def _videoya_cevir(veri: dict) -> YoutubeVideo | None:
    video_id = str(veri.get("id") or "").strip()
    if not video_id:
        return None
    # `duration` playlist girdilerinde null gelebiliyor (canlı yayın, silinmiş).
    ham_sure = veri.get("duration")
    return YoutubeVideo(
        video_id=video_id,
        baslik=str(veri.get("title") or "").strip(),
        kanal=str(veri.get("channel") or veri.get("uploader") or "").strip(),
        sure_sn=float(ham_sure) if isinstance(ham_sure, (int, float)) else 0.0,
        url=str(veri.get("webpage_url") or veri.get("url") or "").strip(),
    )


def kunye_getir(url: str, *, limit: int = 0) -> list[YoutubeVideo]:
    """Tek video ya da playlist'in künyesini indirmeden çeker.

    `--flat-playlist`: playlist girdileri için ayrı ayrı sayfa çekilmez,
    yoksa 50 videoluk bir listenin künyesi dakikalar alırdı.
    """
    adres = _url_dogrula(url)
    cikti = _ytdlp_calistir(
        ["--dump-single-json", "--flat-playlist", "--no-warnings", adres],
        zaman_asimi=KUNYE_ZAMAN_ASIMI_SN,
    )
    try:
        veri = json.loads(cikti)
    except json.JSONDecodeError as exc:
        raise AlimHatasi(f"yt-dlp künyesi çözümlenemedi: {exc}") from exc

    girdiler = veri.get("entries")
    if not isinstance(girdiler, list):
        girdiler = [veri]
    videolar: list[YoutubeVideo] = []
    for girdi in girdiler:
        # Silinmiş/gizli videolar playlist'te `null` girdi olarak görünür.
        if not isinstance(girdi, dict):
            continue
        video = _videoya_cevir(girdi)
        if video is not None:
            videolar.append(video)
        if limit > 0 and len(videolar) >= limit:
            break
    if not videolar:
        raise AlimHatasi(f"Adreste işlenebilir video bulunamadı: {url!r}")
    return videolar


def sesi_indir(video: YoutubeVideo, hedef: Path) -> Path:
    """Videonun yalnız ses akışını indirir, dosya yolunu döndürür.

    `--extract-audio` bilinçli olarak YOK: whisper yolu (`sesi_yaziya_dok`)
    zaten ffmpeg ile 16 kHz mono WAV üretiyor; araya bir mp3 dönüşümü sokmak
    çift transcode olur ve kalite kaybettirir.
    """
    hedef.mkdir(parents=True, exist_ok=True)
    _ytdlp_calistir(
        [
            "-f", "bestaudio/best",
            "--no-playlist",
            "--no-warnings",
            "--max-filesize", f"{AZAMI_BOYUT_MB}M",
            "-o", str(hedef / "%(id)s.%(ext)s"),
            video.izleme_adresi(),
        ],
        zaman_asimi=INDIRME_ZAMAN_ASIMI_SN,
    )
    # Uzantı formata göre değişir (m4a/webm/opus); kimlikle ararız.
    bulunanlar = sorted(hedef.glob(f"{video.video_id}.*"))
    dosyalar = [d for d in bulunanlar if d.is_file() and not d.name.endswith(".part")]
    if not dosyalar:
        # `--max-filesize` aşımı hata koduyla değil sessizce dosyasız biter.
        raise AlimHatasi(
            f"{video.video_id}: ses dosyası inmedi "
            f"(video {AZAMI_BOYUT_MB} MB sınırını aşıyor olabilir)."
        )
    return dosyalar[0]


def transkript_yolu(kok: Path, video_id: str) -> Path:
    return kok / "youtube" / "transkript" / f"{video_id}.json"


def _transkripti_kaydet(yol: Path, video: YoutubeVideo, parcalar: list[Parca]) -> None:
    yol.parent.mkdir(parents=True, exist_ok=True)
    veri = {
        "video_id": video.video_id,
        "baslik": video.baslik,
        "kanal": video.kanal,
        "sure_sn": video.sure_sn,
        "parcalar": [
            {
                "metin": p.metin,
                "baslangic_sn": p.baslangic_sn,
                "bitis_sn": p.bitis_sn,
            }
            for p in parcalar
        ],
    }
    gecici = yol.with_suffix(".tmp")
    gecici.write_text(json.dumps(veri, ensure_ascii=False), encoding="utf-8")
    os.replace(gecici, yol)


def _transkripti_yukle(yol: Path) -> list[Parca] | None:
    try:
        veri = json.loads(yol.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    ham = veri.get("parcalar")
    if not isinstance(ham, list):
        return None
    parcalar = [
        Parca(
            metin=str(p.get("metin", "")),
            baslangic_sn=p.get("baslangic_sn"),
            bitis_sn=p.get("bitis_sn"),
        )
        for p in ham
        if isinstance(p, dict)
    ]
    return parcalar or None


def transkripti_ice_aktar(kaynak_yol: Path, kok: Path) -> tuple[str, int, float]:
    """Dışarıda (Colab) üretilmiş transkripti önbelleğe kurar.

    Uzun videolarda yazıya dökme yerel makinede sürdürülemiyor: 10 saatlik bir
    ders videosu ~100 dakika döküm, 1 GB'lık WAV ve whisper HTTP çağrısında
    1 saatlik zaman aşımı demek. Colab'de GPU ile dökülüp buraya taşınabilsin
    diye önbellek dosyası doğrudan içe aktarılabiliyor; `videoyu_dok` önbellek
    dolu olduğunda indirmeyi de dökümü de atlıyor.

    Döner: (video_id, parça sayısı, toplam süre).
    """
    try:
        veri = json.loads(kaynak_yol.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AlimHatasi(f"{kaynak_yol.name}: okunamadı ({exc})") from exc
    if not isinstance(veri, dict):
        raise AlimHatasi(f"{kaynak_yol.name}: JSON nesnesi bekleniyordu.")

    # Kimlik dosyanın içinden gelir; yoksa dosya adından (Colab çıktısı
    # `<video_id>.json` olarak adlandırılıyor).
    video_id = str(veri.get("video_id") or kaynak_yol.stem).strip()
    if not video_id:
        raise AlimHatasi(f"{kaynak_yol.name}: video_id bulunamadı.")

    ham = veri.get("parcalar")
    if not isinstance(ham, list) or not ham:
        raise AlimHatasi(f"{kaynak_yol.name}: 'parcalar' listesi boş ya da yok.")
    parcalar: list[Parca] = []
    for girdi in ham:
        if not isinstance(girdi, dict):
            continue
        metin = str(girdi.get("metin") or girdi.get("text") or "").strip()
        if not metin:
            continue
        parcalar.append(
            Parca(
                metin=metin,
                baslangic_sn=_sayiya_cevir(girdi.get("baslangic_sn", girdi.get("start"))),
                bitis_sn=_sayiya_cevir(girdi.get("bitis_sn", girdi.get("end"))),
            )
        )
    if not parcalar:
        raise AlimHatasi(f"{kaynak_yol.name}: metni olan parça yok.")

    video = YoutubeVideo(
        video_id=video_id,
        baslik=str(veri.get("baslik") or veri.get("title") or ""),
        kanal=str(veri.get("kanal") or veri.get("channel") or ""),
        sure_sn=_sayiya_cevir(veri.get("sure_sn", veri.get("duration"))) or 0.0,
    )
    _transkripti_kaydet(transkript_yolu(kok, video_id), video, parcalar)
    son = parcalar[-1].bitis_sn or 0.0
    return video_id, len(parcalar), video.sure_sn or son


def _sayiya_cevir(deger) -> float | None:
    if isinstance(deger, (int, float)):
        return float(deger)
    return None


def videoyu_dok(
    video: YoutubeVideo,
    *,
    kok: Path,
    yeniden: bool = False,
    sesi_sakla: bool = False,
    dokum_ilerlemesi: Callable[[int, int], None] | None = None,
) -> Kaynak:
    """İndir + yazıya dök; önbellekte transkript varsa ikisini de atlar."""
    onbellek = transkript_yolu(kok, video.video_id)
    if not yeniden and onbellek.is_file():
        parcalar = _transkripti_yukle(onbellek)
        if parcalar is not None:
            return Kaynak(
                ad=video.kaynak_adi(),
                tur="youtube",
                imza=video.imza,
                parcalar=parcalar,
            )

    from .ses import sesi_yaziya_dok

    if sesi_sakla:
        ses_dizini = kok / "youtube" / "ses"
        ses = sesi_indir(video, ses_dizini)
        parcalar = sesi_yaziya_dok(ses, ilerleme=dokum_ilerlemesi)
    else:
        with tempfile.TemporaryDirectory(prefix="biyo-youtube-") as gecici:
            ses = sesi_indir(video, Path(gecici))
            parcalar = sesi_yaziya_dok(ses, ilerleme=dokum_ilerlemesi)

    _transkripti_kaydet(onbellek, video, parcalar)
    return Kaynak(
        ad=video.kaynak_adi(),
        tur="youtube",
        imza=video.imza,
        parcalar=parcalar,
    )


def dok_hepsi(
    videolar: list[YoutubeVideo],
    *,
    kok: Path,
    yeniden: bool = False,
    sesi_sakla: bool = False,
    ilerleme: Callable[[YoutubeVideo, int, int], None] | None = None,
) -> tuple[list[tuple[YoutubeVideo, Kaynak]], list[str]]:
    """Videoları sırayla döker → (başarılılar, hatalar).

    Playlist'te tek bozuk video (silinmiş, bölge kilidi, boyut aşımı) akışı
    durdurmamalı; hata metni toplanır, kalanlar işlenir.
    """
    sonuclar: list[tuple[YoutubeVideo, Kaynak]] = []
    hatalar: list[str] = []
    for sira, video in enumerate(videolar, start=1):
        if ilerleme is not None:
            ilerleme(video, sira, len(videolar))
        try:
            sonuclar.append((video, videoyu_dok(
                video, kok=kok, yeniden=yeniden, sesi_sakla=sesi_sakla
            )))
        except AlimHatasi as exc:
            hatalar.append(f"{video.video_id}: {exc}")
    return sonuclar, hatalar
