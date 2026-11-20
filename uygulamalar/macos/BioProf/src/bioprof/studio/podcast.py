"""İki sunuculu Türkçe podcast senaryosu.

Murat uzman anlatıcı, Emel meraklı sunucudur. Senaryoyu yerel LLM yazar ama
her olgusal replik, sohbetteki kanıt penceresi testinden geçmek zorundadır;
geçemeyen replik atılır. LLM erişilemezse deterministik bir iskelet üretilir
(Emel'in kalıp soruları + kanıt cümleleri) — zayıf ama kaynağa bağlı ve
çalışır.

Konuşmacı sırası TTS'e olduğu gibi verilmez: XTTS worker havuzu ses
değişiminde yeniden doğduğu için (30-60 sn) replikler konuşmacıya göre
gruplanıp sentezlenir, montajda senaryo sırasına dizilir.
"""

from __future__ import annotations

import asyncio
import json
import re
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any, Literal, Protocol

from pydantic import BaseModel, Field, ValidationError

from bioprof.rag.answering import _CITATION, HakemCallable, _claim_supported, iddia_gibi
from bioprof.rag.nli import NliCift
from bioprof.studio.artifacts import StudioEvidence, _sentences

Speaker = Literal["emel", "mazlum", "murat"]

# SesLab'daki ses adları. Emel sunucu, Mazlum Kiper ve Murat iki uzman.
SES_ADLARI: dict[str, str] = {
    "emel": "emel",
    "mazlum": "Mazlum Kiper",
    "murat": "Murat",
}
_SUNUM_ADLARI = {"emel": "Emel", "mazlum": "Mazlum", "murat": "Murat"}
UZMANLAR = ("mazlum", "murat")
# Soru/geçiş replikleri olgu taşımaz; kanıt testine sokulmazlar, ama
# olgu cümlesi gibi görünmemeleri için uzunlukları sınırlanır.
_SORU_AZAMI_KARAKTER = 180
_DUSUS_ESIGI = 0.4
_JSON_BLOK = re.compile(r"\{.*\}", re.DOTALL)
# Olgu taşıyan replik türleri: hepsi aynı kanıt doğrulamasından geçer.
_OLGU_TURLERI = frozenset({"fact", "explain", "discuss", "summary"})
# İki repliğin "aynı şeyi söylediği" sayılan içerik sözcüğü örtüşmesi.
_TEKRAR_ESIGI = 0.7
_ICERIK = re.compile(r"[^\W\d_]{4,}", re.UNICODE)


class PodcastSegment(BaseModel):
    speaker: Speaker
    text: str = Field(min_length=1, max_length=1200)
    citation_labels: list[str] = Field(default_factory=list, max_length=8)
    kind: Literal["fact", "question", "transition", "explain", "discuss", "summary"] = (
        "fact"
    )


class PodcastScript(BaseModel):
    segments: list[PodcastSegment] = Field(min_length=2, max_length=80)


# Bölüm başlığına göre kanıt getiren geri çağırım (uzun bölümlerde her alt
# başlık kendi kanıtıyla yazılır).
ChapterEvidenceProvider = Callable[[str], Awaitable[list[StudioEvidence]]]
ChapterProgress = Callable[[int, int, str, list[dict[str, Any]]], Awaitable[None]]


class ChatCallable(Protocol):
    async def __call__(
        self, messages: list[dict[str, str]], *, max_tokens: int | None = None
    ) -> str: ...


UZUNLUK_PRESETLERI = {"kisa": 12, "orta": 24, "uzun": 36}
# Replik başına JSON token payı (metin + alan adları + tırnaklar), ölçülmüş
# çıktılara göre cömert tutuldu.
_REPLIK_TOKEN_PAYI = 160
# Ölçüldü (dört üretimin ortalaması): bir replik ~7.5 sn ses. Hedef süreyi
# replik sayısına bu oranla çeviriyoruz.
SANIYE_BASINA_REPLIK = 7.5
# Tek LLM çağrısında güvenilir biçimde üretilebilen replik sayısı. Bunun
# üstünde JSON hem token sınırına dayanıyor hem tutarlılığı düşüyor, bu yüzden
# uzun bölümler ANAHAT + bölüm bölüm üretimle kuruluyor.
BOLUM_BASINA_REPLIK = 18
# Bir bölümün senaryosunu yazarken modele verilen azami kanıt bloğu.
#
# Ölçüldü (2026-08-06, Qwen3.5-4B-4bit/MLX, M4 16 GB): 24 blokluk havuz 19.008
# token istem demek ve bir bölüm 138 sn sürüyor — 48 sn'si yalnız istemi
# okumaya gidiyor, üretim de uzun bağlamda 27,9'dan 23,0 tok/sn'ye düşüyor.
# 8 blok (~6k token) ile aynı bölüm ~81 sn. Bölüm tek bir alt başlığı işlediği
# için geri kalan bloklar zaten okunup atılıyordu.
BOLUM_KANIT_SINIRI = 8
# Anahat yalnız başlık seçer; blokların tamamını okuması gerekmez. Her bloktan
# ilk birkaç cümle, tam metnin ~50 sn'lik istem işlemesini ~15 sn'ye indiriyor.
ANAHAT_KANIT_CUMLESI = 2
# XTTS Türkçe konuşma hızı: saniyede ~14 karakter (testlerdeki _gercekci_sure
# ile aynı ölçüm). Süre tahmini replik SAYISINDAN değil karakterden yapılır:
# 40 karakterlik bir soru ile 350 karakterlik bir anlatım aynı "1 replik".
KARAKTER_HIZI = 14.0
# Montajda replikler arası varsayılan boşluk (SesLab gap_ms=320 ile aynı).
_REPLIK_ARASI_SN = 0.32
# Eleme sonrası süre açığı bu orandan büyükse telafi turu atılır.
_TELAFI_ORANI = 0.1


@dataclass(frozen=True)
class PodcastAyarlari:
    """Builder'ın ayar yüzeyi; modül sabitleri varsayılan değerlerdir.

    Config'e taşınan sabitler: deneme yapmak için kod düzenlemek gerekmesin.
    """

    saniye_basina_replik: float = SANIYE_BASINA_REPLIK
    bolum_basina_replik: int = BOLUM_BASINA_REPLIK
    bolum_kanit_siniri: int = BOLUM_KANIT_SINIRI
    karakter_hizi: float = KARAKTER_HIZI
    telafi_turu: int = 2


def tahmini_sure(segments: list[dict[str, Any]], *, karakter_hizi: float = KARAKTER_HIZI) -> float:
    """Segment listesinin yaklaşık ses süresi (saniye), karakter tabanlı."""
    if not segments:
        return 0.0
    konusma = sum(len(str(segment.get("text", ""))) for segment in segments) / max(
        0.001, karakter_hizi
    )
    return konusma + (len(segments) - 1) * _REPLIK_ARASI_SN


@dataclass(frozen=True)
class PodcastStili:
    """Bir bölümün dokusu: kimin ne kadar konuştuğu ve hangi türlerin ağırlığı."""

    ad: str
    aciklama: str
    yonerge: str
    yapı: str


PODCAST_STILLERI: dict[str, PodcastStili] = {
    "sohbet": PodcastStili(
        ad="Sohbet",
        aciklama="Sunucu sorar, iki uzman sırayla açıklar. Dengeli ve akıcı.",
        yonerge=(
            "Doku: rahat bir sohbet. Emel sık sık soru sorar, uzmanlar kısa ve "
            "anlaşılır yanıtlar verir. Replikler kısa tutulur."
        ),
        yapı=(
            "1. Emel konuyu tanıtır (transition).\n"
            "2. Soru-cevap turları: Emel sorar (question), bir uzman yanıtlar (fact).\n"
            "3. Arada bir uzman 2-3 replik anlatır (explain).\n"
            "4. Uzmanlar bir konuda karşılıklı konuşur (discuss).\n"
            "5. Kapanışta kısa özet (summary) ve Emel'in vedası (transition)."
        ),
    ),
    "ders": PodcastStili(
        ad="Ders anlatımı",
        aciklama="Uzman ağırlıklı, kesintisiz anlatım blokları. Ders havası.",
        yonerge=(
            "Doku: ders. Uzmanlar uzun ve bağlantılı bloklar hâlinde anlatır; "
            "Emel yalnız bölüm başlarında ve sonlarında konuşur. Anlatım "
            "adım adım ilerler, kavramlar sırayla kurulur."
        ),
        yapı=(
            "1. Emel bölümün konusunu duyurur (transition).\n"
            "2. Bir uzman 4-6 replik ARKA ARKAYA anlatır (explain).\n"
            "3. Diğer uzman örnek/deney ekler (explain veya discuss).\n"
            "4. Bölüm sonunda kısa toparlama (summary)."
        ),
    ),
    "tartisma": PodcastStili(
        ad="Uzman tartışması",
        aciklama="İki uzman karşılıklı; farklı açılar, ekleme ve karşılaştırma.",
        yonerge=(
            "Doku: panel. Mazlum ve Murat aynı konuyu farklı açılardan ele alır, "
            "birbirinin sözüne ekleme yapar, karşılaştırır. Emel moderatördür ve "
            "az konuşur. Uzmanlar birbirinin adını kullanır."
        ),
        yapı=(
            "1. Emel tartışma konusunu açar (transition).\n"
            "2. Mazlum ve Murat DÖNÜŞÜMLÜ konuşur (discuss); her replik "
            "öncekine bağlanır.\n"
            "3. Emel arada yön verir (question).\n"
            "4. Ortak sonuç (summary)."
        ),
    ),
    "tekrar": PodcastStili(
        ad="Hızlı tekrar",
        aciklama="Sınav öncesi pekiştirme: kısa, yoğun, madde madde.",
        yonerge=(
            "Doku: hızlı tekrar. Replikler KISA ve bilgi yoğun. Süsleme yok, "
            "her replik tek bir bilgi verir. Emel başlıkları sayar, uzmanlar "
            "tek cümleyle karşılık verir."
        ),
        yapı=(
            "1. Emel 'bu bölümde şunları tekrar ediyoruz' der (transition).\n"
            "2. Emel başlığı söyler (question), uzman tek cümleyle özetler "
            "(summary).\n"
            "3. Bu ikili sırayla devam eder.\n"
            "4. Kapanışta en kritik üç madde (summary)."
        ),
    ),
    "roportaj": PodcastStili(
        ad="Derinlemesine söyleşi",
        aciklama="Sunucu ısrarla sorar, uzman derinleşir. Merak odaklı.",
        yonerge=(
            "Doku: söyleşi. Emel meraklı ve ısrarcıdır: 'peki neden', 'bunu bir "
            "de şöyle sorayım' gibi takip soruları sorar. Uzman her seferinde "
            "biraz daha derinleşir."
        ),
        yapı=(
            "1. Emel konuyu açan geniş bir soru sorar (question).\n"
            "2. Uzman yanıtlar (fact), Emel TAKİP sorusu sorar (question).\n"
            "3. Aynı konuda 3-4 tur derinleşilir.\n"
            "4. Emel toparlayıcı bir soru sorar, uzman özetler (summary)."
        ),
    ),
}
VARSAYILAN_STIL = "sohbet"


def replik_hedefi(*, target_minutes: float | None, length: str) -> int:
    """Hedef replik sayısı: dakika verilmişse ondan, yoksa preset'ten."""
    if target_minutes:
        return max(4, round(target_minutes * 60 / SANIYE_BASINA_REPLIK))
    return UZUNLUK_PRESETLERI.get(length, UZUNLUK_PRESETLERI["orta"])


def _sistem_istemi(stil: str = VARSAYILAN_STIL) -> str:
    """Yalnız stile bağlı, çağrıdan çağrıya DEĞİŞMEYEN yönerge.

    Bölüm bilgisi ve hedef replik sayısı bilerek buraya konmuyor: mlx_lm.server
    istemin en uzun ortak ÖNEKİNİ önbelleğe alıyor, sistem istemi de en başta
    duruyor. Değişen her ayrıntı buraya girdiğinde aynı bölümün ikinci denemesi
    19 bin tokenlık istemi baştan işlemek zorunda kalıyordu (ölçüldü: 48 sn).
    Değişkenler kullanıcı iletisinin SONUNA taşındı.
    """
    secili = PODCAST_STILLERI.get(stil, PODCAST_STILLERI[VARSAYILAN_STIL])
    return (
        "Üç kişilik bir Türkçe biyoloji podcast'inin senaryosunu yazıyorsun.\n\n"
        "KONUŞMACILAR:\n"
        "- Emel: sunucu. Soru sorar, konuyu açar, bölümler arasında geçiş "
        "yapar. Kendisi olgu ANLATMAZ.\n"
        "- Mazlum: uzman. Kavramı tanımlar, mekanizmayı anlatır.\n"
        "- Murat: ikinci uzman. Örnek verir, deney/tarihçe aktarır, Mazlum'un "
        "anlattığına ekleme yapar.\n\n"
        f"{secili.yonerge}\n\n"
        f"BÖLÜM YAPISI:\n{secili.yapı}\n\n"
        "KURALLAR:\n"
        "1. Yalnız KANITLAR bölümündeki bilgiyi kullan; yeni olgu, sayı veya "
        "isim uydurma.\n"
        "2. Olgu içeren HER repliğe dayandığı kanıtın etiketini yaz "
        '("citation_labels": ["S1"]). Olgu türleri: fact, explain, discuss, '
        "summary.\n"
        '3. Emel\'in replikleri "question" ya da "transition" olsun ve etiket '
        "taşımasın; Emel olgu cümlesi kurmaz.\n"
        "4. Replikler konuşma dilinde olsun; kanıt cümlelerini olduğu gibi "
        "okuma, kendi cümlelerinle anlat. Kanıttaki terim, ad ve sayıları "
        "aynen koru.\n"
        "5. Uzmanlar birbirinin adını kullanabilir ('Haklısın Murat', "
        "'Mazlum'un dediği gibi').\n"
        "6. Tanı, tedavi, doz veya kişisel sağlık önerisi verme.\n"
        "7. Yapıdaki replik türlerinin her birini en az bir kez kullan.\n\n"
        "YALNIZ şu biçimde JSON döndür, başka hiçbir şey yazma:\n"
        '{"segments": ['
        '{"speaker": "emel", "text": "...", "kind": "transition", "citation_labels": []}, '
        '{"speaker": "mazlum", "text": "...", "kind": "explain", "citation_labels": ["S1"]}, '
        '{"speaker": "murat", "text": "...", "kind": "discuss", "citation_labels": ["S2"]}'
        "]}"
    )


def _kullanici_istemi(
    title: str,
    evidence_text: str,
    *,
    hedef: int | None = None,
    bolum_bilgisi: str = "",
    islenmis: list[dict[str, Any]] | None = None,
) -> str:
    """Kanıt önce, çağrıya özgü yönerge SONRA.

    Sıra önemli: aynı bölümün ikinci denemesinde kanıt bloğu birebir aynı
    kaldığı için istem önbelleği tutuyor ve yalnız kuyruk yeniden işleniyor.
    """
    istem = f"KONU: {title}\n\nKANITLAR:\n{evidence_text}\n"
    if bolum_bilgisi:
        istem += f"\n{bolum_bilgisi.strip()}\n"
    if islenmis:
        # İkinci deneme aynı şeyi yeniden yazarsa yineleme süzgeci eler ve
        # çağrı tümüyle boşa gider; kabul edilenler kısaca hatırlatılıyor.
        gecmis = "\n".join(f"- {str(item.get('text', ''))[:90]}" for item in islenmis[-12:])
        istem += (
            "\nBU BÖLÜMDE ZATEN ANLATILANLAR — tekrar etme, bunların ÜSTÜNE "
            f"yeni replikler yaz:\n{gecmis}\n"
        )
    if hedef:
        istem += f"\nYaklaşık {hedef} replik yaz.\n"
    return istem + "\nJSON:"


class PodcastOutline(BaseModel):
    chapters: list[str] = Field(min_length=1, max_length=40)


def _anahat_istemi(hedef_bolum: int, dakika: float) -> str:
    return (
        "Bir Türkçe biyoloji podcast bölümünün ANAHATINI çıkarıyorsun.\n\n"
        f"Bölüm {dakika:.0f} dakika sürecek ve {hedef_bolum} alt başlığa "
        "ayrılacak.\n\n"
        "KURALLAR:\n"
        "1. Alt başlıklar KANITLAR'da gerçekten işlenen konulardan seçilmeli; "
        "kanıtta karşılığı olmayan başlık yazma.\n"
        "2. Başlıklar mantıklı bir öğrenme sırasında olsun: önce temel kavram, "
        "sonra mekanizma, sonra örnek ve uygulama.\n"
        "3. Her başlık kendi başına 3-5 dakika konuşulabilecek genişlikte "
        "olsun; birbirinin aynısı olmasın.\n"
        "4. Başlıklar kısa olsun (en fazla 8 kelime).\n\n"
        'YALNIZ şu biçimde JSON döndür: {"chapters": ["...", "..."]}'
    )


def _anahat_yukle(raw: str) -> PodcastOutline:
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\n?|```$", "", text).strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = _JSON_BLOK.search(text)
        if match is None:
            raise ValueError("Model geçerli anahat döndürmedi") from None
        data = json.loads(match.group(0))
    return PodcastOutline.model_validate(data)


def _kanit_metni(records: list[StudioEvidence]) -> str:
    return "\n\n".join(
        f'<untrusted_evidence id="{item.label}">\n[{item.label}] '
        f"{item.source_title}\n{item.text}\n</untrusted_evidence>"
        for item in records
    )


def _ozet_kanit_metni(records: list[StudioEvidence]) -> str:
    """Anahat için kısaltılmış kanıt görünümü: blok başına ilk birkaç cümle.

    Etiketler korunur, çünkü anahat başlıkları kanıtta gerçekten işlenen
    konulardan seçilmeli; ama başlık seçmek için blokların tamamı gerekmiyor.
    """
    parcalar = []
    for item in records:
        cumleler = _sentences(item.text)[:ANAHAT_KANIT_CUMLESI]
        ozet = " ".join(cumleler) if cumleler else item.text.strip()
        parcalar.append(
            f'<untrusted_evidence id="{item.label}">\n[{item.label}] '
            f"{item.source_title}\n{ozet}\n</untrusted_evidence>"
        )
    return "\n\n".join(parcalar)


def _bolum_kanitlari(
    records: list[StudioEvidence],
    *,
    sira: int,
    kendi_kaniti: bool,
    sinir: int = BOLUM_KANIT_SINIRI,
) -> list[StudioEvidence]:
    """Bir bölümün göreceği kanıt penceresi.

    Bölüm kendi kanıtını çektiyse en alakalı ilk bloklar alınır. Paylaşılan
    havuzdan besleniyorsa her bölüme KAYAN bir pencere verilir: sabit ilk N
    bloğu vermek bütün bölümlere aynı bilgiyi anlattırır, yineleme süzgeci de
    üretim bedeli ödendikten sonra temizlerdi.
    """
    if len(records) <= sinir:
        return records
    if kendi_kaniti:
        return records[:sinir]
    bas = ((sira - 1) * sinir) % len(records)
    return (records + records)[bas : bas + sinir]


def _json_yukle(raw: str) -> PodcastScript:
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\n?|```$", "", text).strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = _JSON_BLOK.search(text)
        if match is not None:
            try:
                data = json.loads(match.group(0))
            except json.JSONDecodeError:
                data = {"segments": _tam_segmentler(text)}
        else:
            data = {"segments": _tam_segmentler(text)}
    if not data.get("segments"):
        raise ValueError("Model geçerli JSON senaryo döndürmedi")
    return PodcastScript.model_validate(data)


def _tam_segmentler(text: str) -> list[dict[str, Any]]:
    """Yarıda kesilmiş JSON'dan tamamlanmış replikleri toplar.

    Uzun senaryolarda üretim token sınırında kesilebiliyor ve tek bir eksik
    parantez yüzünden kabul edilmiş onlarca replik çöpe gidiyordu. Yalnız
    kendi içinde kapanmış nesneler alınır; yarım kalan sonuncusu atılır.
    """
    decoder = json.JSONDecoder()
    segments: list[dict[str, Any]] = []
    index = text.find("[")
    if index < 0:
        return segments
    position = index + 1
    while position < len(text):
        start = text.find("{", position)
        if start < 0:
            break
        try:
            value, end = decoder.raw_decode(text, start)
        except json.JSONDecodeError:
            break
        if isinstance(value, dict):
            segments.append(value)
        position = end
    return segments


class PodcastScriptBuilder:
    """Kanıtlardan iki sesli senaryo üretir; doğrulanamayan repliği geçirmez."""

    def __init__(
        self,
        chat: ChatCallable | None = None,
        hakem: HakemCallable | None = None,
        ayarlar: PodcastAyarlari | None = None,
    ) -> None:
        self._chat = chat
        self._hakem = hakem
        self._ayarlar = ayarlar or PodcastAyarlari()

    async def build(
        self,
        title: str,
        records: list[StudioEvidence],
        *,
        length: str = "orta",
        target_minutes: float | None = None,
        style: str = VARSAYILAN_STIL,
        chapter_provider: ChapterEvidenceProvider | None = None,
        progress: ChapterProgress | None = None,
    ) -> tuple[list[dict[str, Any]], list[str], bool]:
        """(segmentler, uyarılar, llm_yazdi) döndürür.

        Hedef replik sayısı tek çağrıda güvenle üretilebilecek sınırı aşarsa
        bölüm bölüm üretilir: önce anahat, sonra her alt başlık için kendi
        kanıtıyla ayrı bir senaryo. ``chapter_provider`` verilirse her bölüm
        kendi konusuna göre kanıt çeker; verilmezse eldeki kanıt paylaşılır.
        """
        if not records:
            raise ValueError("Podcast için kaynaklı kanıt gerekli")
        hedef = replik_hedefi(target_minutes=target_minutes, length=length)
        if self._chat is None:
            return _iskelet(title, records, hedef), [
                "Yerel model kullanılamadığı için kalıp senaryo üretildi."
            ], False
        if hedef > self._ayarlar.bolum_basina_replik * 1.5:
            return await self._uzun_bolum(
                title,
                records,
                hedef=hedef,
                style=style,
                chapter_provider=chapter_provider,
                progress=progress,
            )
        segments, warnings, llm_yazdi = await self._tek_gecis(
            title, records, hedef=hedef, style=style
        )
        # Numaralama TEK noktada (build dönüşleri): montaj index'e baktığı için
        # üretim/telafi bitmeden numara verilmez.
        return _numarala(segments), warnings, llm_yazdi

    async def _tek_gecis(
        self,
        title: str,
        records: list[StudioEvidence],
        *,
        hedef: int,
        style: str,
        bolum_bilgisi: str = "",
        onceki: list[dict[str, Any]] | None = None,
    ) -> tuple[list[dict[str, Any]], list[str], bool]:
        """NUMARASIZ segment listesi döndürür; numaralama build()'in işidir.

        ``onceki`` telafi turunda verilir: modelin daha önce kabul edilmiş
        replikleri yeniden yazmaması için isteme hatırlatma olarak girer ama
        hedef sayımına ve birikime karışmaz.
        """
        assert self._chat is not None  # build() chat'siz yolu iskelete yönlendirir
        warnings: list[str] = []
        kanit = _kanit_metni(records)
        sistem = _sistem_istemi(style)
        # Kabul edilen replikler denemeler ARASINDA birikir. Eskiden ikinci
        # deneme bölümü sıfırdan yazıyor, sonra iki denemeden yalnız uzun olanı
        # tutuluyordu: ilk denemenin doğrulanmış replikleri de, onları üreten
        # ~80 sn de çöpe gidiyordu.
        birikmis: list[dict[str, Any]] = []
        tum_dusenler: list[tuple[str, str]] = []
        for attempt in range(2):
            kalan = hedef - len(birikmis)
            if attempt and kalan <= 0:
                break
            istek = hedef if attempt == 0 else max(4, kalan)
            # Token bütçesi replik sayısıyla ölçeklenmeli: sabit bütçe uzun
            # senaryolarda JSON'u ortasında kesiyor ve tüm deneme çöpe gidiyordu.
            butce = max(1600, istek * _REPLIK_TOKEN_PAYI)
            messages = [
                {"role": "system", "content": sistem},
                {
                    "role": "user",
                    "content": _kullanici_istemi(
                        title,
                        kanit,
                        hedef=istek,
                        bolum_bilgisi=bolum_bilgisi,
                        islenmis=[*(onceki or []), *birikmis],
                    ),
                },
            ]
            try:
                raw = await self._chat(messages, max_tokens=butce)
                script = _json_yukle(raw)
            except (ValueError, ValidationError) as exc:
                warnings.append(f"Senaryo denemesi başarısız: {exc}")
                continue
            except Exception as exc:
                # Sağlayıcı/altyapı hatası: podcast tamamen düşmek yerine
                # kalıp senaryoya iner. Dar bir except listesi, beklenmeyen bir
                # hata türünde (ör. bozuk bağlam yöneticisi) yedek yolun hiç
                # devreye girmemesine yol açıyordu.
                warnings.append(f"Senaryo denemesi başarısız: {exc.__class__.__name__}: {exc}")
                continue
            # NLI hakemi bloklayan bir model çağrısı olabilir; SSE ilerleme
            # akışını kilitlememek için doğrulama iş parçacığına alınır.
            kept, dusenler = await asyncio.to_thread(
                _dogrula, script, records, self._hakem
            )
            tum_dusenler.extend(dusenler)
            if not kept:
                warnings.append("Senaryo repliklerinin hiçbiri kanıtla doğrulanamadı.")
                continue
            oncesi = len(birikmis)
            # Süzgeç birikimin TAMAMI üzerinde çalışmalı: iki denemenin aynı
            # kanıtı iki kez anlatması ancak yan yana konunca görülür.
            birikmis = _tekrarlari_ele([*birikmis, *kept])
            if len(birikmis) == oncesi:
                warnings.append("Deneme yalnız yinelenen replik getirdi.")
                continue
            toplam = len(kept) + len(dusenler)
            if toplam and len(dusenler) / toplam <= _DUSUS_ESIGI:
                break
            if attempt == 0:
                warnings.append(
                    f"Repliklerin {len(dusenler)}/{toplam} kadarı kanıtsızdı; "
                    "bölüm eksik kalan replik sayısınca tamamlandı."
                )
        if birikmis:
            if tum_dusenler:
                warnings.append(_dusus_ozeti(tum_dusenler))
            return birikmis, warnings, True
        warnings.append("Kalıp senaryoya düşüldü.")
        return _iskelet(title, records, hedef), warnings, False

    async def _anahat(
        self, title: str, records: list[StudioEvidence], *, bolum_sayisi: int, dakika: float
    ) -> list[str]:
        """Konuyu alt başlıklara böler; başarısız olursa tek başlık döndürür."""
        assert self._chat is not None
        messages = [
            {"role": "system", "content": _anahat_istemi(bolum_sayisi, dakika)},
            {
                "role": "user",
                "content": _kullanici_istemi(title, _ozet_kanit_metni(records)),
            },
        ]
        try:
            raw = await self._chat(messages, max_tokens=max(600, bolum_sayisi * 40))
            chapters = _anahat_yukle(raw).chapters
        except Exception:
            return []
        temiz = [item.strip() for item in chapters if item and item.strip()]
        # Yinelenen başlık, aynı kanıtın iki kez anlatılması demek.
        gorulen: set[str] = set()
        sonuc: list[str] = []
        for baslik in temiz:
            anahtar = baslik.casefold()
            if anahtar in gorulen:
                continue
            gorulen.add(anahtar)
            sonuc.append(baslik)
        return sonuc[:bolum_sayisi]

    async def _uzun_bolum(
        self,
        title: str,
        records: list[StudioEvidence],
        *,
        hedef: int,
        style: str,
        chapter_provider: ChapterEvidenceProvider | None,
        progress: ChapterProgress | None,
    ) -> tuple[list[dict[str, Any]], list[str], bool]:
        """Anahat çıkarıp bölüm bölüm üretir; her bölüm kendi kanıtıyla yazılır."""
        bolum_sayisi = max(2, round(hedef / self._ayarlar.bolum_basina_replik))
        dakika = hedef * self._ayarlar.saniye_basina_replik / 60
        warnings: list[str] = []
        basliklar = await self._anahat(
            title, records, bolum_sayisi=bolum_sayisi, dakika=dakika
        )
        if not basliklar:
            warnings.append("Anahat üretilemedi; bölümler ana başlıkla yazıldı.")
            basliklar = [title] * bolum_sayisi

        toplam: list[dict[str, Any]] = []
        llm_yazdi = False
        bolum_hedefi = max(6, round(hedef / len(basliklar)))
        for sira, baslik in enumerate(basliklar, start=1):
            if progress is not None:
                await progress(sira - 1, len(basliklar), baslik, toplam)
            bolum_kayitlari = records
            kendi_kaniti = False
            if chapter_provider is not None:
                try:
                    getirilen = await chapter_provider(baslik)
                    if getirilen:
                        bolum_kayitlari = getirilen
                        kendi_kaniti = True
                except Exception as exc:
                    warnings.append(f"'{baslik}' için kanıt getirilemedi: {exc}")
            bolum_kayitlari = _bolum_kanitlari(
                bolum_kayitlari,
                sira=sira,
                kendi_kaniti=kendi_kaniti,
                sinir=self._ayarlar.bolum_kanit_siniri,
            )
            bilgi = (
                f"BU BÖLÜM: {sira}/{len(basliklar)} — \"{baslik}\".\n"
                "Yalnız bu alt başlığı işle; sonraki bölümlerin konusuna girme.\n"
                + (
                    "Bu ilk bölüm: dinleyiciyi selamla ve konuyu tanıt.\n"
                    if sira == 1
                    else "Bu bölüm ortada: doğrudan konuya gir, yeniden selamlama yapma.\n"
                )
                + (
                    "Bu son bölüm: kapanış özeti ve veda ekle.\n"
                    if sira == len(basliklar)
                    else ""
                )
                + "\n"
            )
            segments, bolum_uyarilari, yazdi = await self._tek_gecis(
                f"{title} — {baslik}",
                bolum_kayitlari,
                hedef=bolum_hedefi,
                style=style,
                bolum_bilgisi=bilgi,
            )
            llm_yazdi = llm_yazdi or yazdi
            toplam.extend(segments)
            for uyari in bolum_uyarilari:
                warnings.append(f"[{sira}/{len(basliklar)}] {uyari}")
        if progress is not None:
            await progress(len(basliklar), len(basliklar), "", toplam)
        # Bölümler arası yinelenmeler ancak birleşince görülür.
        birlesik = _tekrarlari_ele(toplam)
        atilan = len(toplam) - len(birlesik)
        if atilan:
            warnings.append(f"{atilan} replik bölümler arası yineleme olduğu için çıkarıldı.")
        if llm_yazdi:
            birlesik = await self._sure_telafisi(
                title, records, birlesik, hedef=hedef, style=style, warnings=warnings
            )
        return _numarala(birlesik), warnings, llm_yazdi

    async def _sure_telafisi(
        self,
        title: str,
        records: list[StudioEvidence],
        birlesik: list[dict[str, Any]],
        *,
        hedef: int,
        style: str,
        warnings: list[str],
    ) -> list[dict[str, Any]]:
        """Eleme sonrası kalan süre açığını yalnız açık kadar ek replikle kapatır.

        30 dk istenip eleme sonrası ~20 dk kalması bu hattın ölçülmüş sorunuydu:
        hedef, replik sayısı değil SÜRE cinsinden karşılaştırılır (kısa soru ile
        uzun anlatım aynı '1 replik' değildir) ve tüm senaryo baştan yazılmaz.
        """
        hedef_sn = hedef * self._ayarlar.saniye_basina_replik
        for _ in range(self._ayarlar.telafi_turu):
            acik_sn = hedef_sn - tahmini_sure(
                birlesik, karakter_hizi=self._ayarlar.karakter_hizi
            )
            if acik_sn <= hedef_sn * _TELAFI_ORANI:
                return birlesik
            ek_hedef = max(
                4,
                min(
                    self._ayarlar.bolum_basina_replik,
                    round(acik_sn / self._ayarlar.saniye_basina_replik),
                ),
            )
            bilgi = (
                "EK TUR: bölüm hedef süresinden kısa kaldı.\n"
                "Daha önce anlatılanları TEKRAR ETME; kanıtların henüz işlenmemiş "
                "yönlerine odaklan. Selamlama ve veda YAZMA.\n"
            )
            segments, uyarilar, _ = await self._tek_gecis(
                title,
                # En az atıf almış bloklar önde: model hep aynı kanıtı anlatamasın.
                _az_kullanilan_kanitlar(
                    records, birlesik, self._ayarlar.bolum_kanit_siniri
                ),
                hedef=ek_hedef,
                style=style,
                bolum_bilgisi=bilgi,
                onceki=birlesik,
            )
            for uyari in uyarilar:
                warnings.append(f"[telafi] {uyari}")
            # Kapanış kuyruğu (özet/veda) sonda kalmalı; ek replikler ondan
            # önce araya girer.
            kes = len(birlesik)
            while kes > 0 and birlesik[kes - 1].get("kind") in ("summary", "transition"):
                kes -= 1
            oncesi = len(birlesik)
            birlesik = _tekrarlari_ele([*birlesik[:kes], *segments, *birlesik[kes:]])
            if len(birlesik) == oncesi:
                warnings.append("Süre telafisi yeni replik kazandıramadı; açık kapatılamadı.")
                return birlesik
        acik_sn = hedef_sn - tahmini_sure(
            birlesik, karakter_hizi=self._ayarlar.karakter_hizi
        )
        if acik_sn > hedef_sn * _TELAFI_ORANI:
            warnings.append(
                f"Süre açığı kapatılamadı: yaklaşık {acik_sn / 60:.1f} dk eksik."
            )
        return birlesik


def _dogrula(
    script: PodcastScript,
    records: list[StudioEvidence],
    hakem: HakemCallable | None = None,
) -> tuple[list[dict[str, Any]], list[tuple[str, str]]]:
    """(kabul edilen replikler, [(neden, metin)]) döndürür.

    Düşen replikler yalnız sayılmıyor, nedeniyle kaydediliyor: kapının neyi
    neden elediği görünmeden ne ayarı ne de istemi düzeltmek mümkün.

    Kanıt penceresine sığmayan replikler hakem (NLI) verilmişse toplu tek
    çağrıda yeniden yargılanır; kurtulanlar senaryodaki SIRALARIYLA geri
    dikilir. Hakemin de reddettiği replik ``nli_reddetti`` nedeniyle düşer.
    """
    allowed = {item.label.upper(): item for item in records}
    kept: list[dict[str, Any]] = []
    dropped: list[tuple[str, str]] = []
    # (kept'teki takılacağı konum, replik sözlüğü, hakem çifti indeksi)
    beklemede: list[tuple[int, dict[str, Any], int]] = []
    ciftler: list[NliCift] = []
    for segment in script.segments:
        text = _CITATION.sub("", segment.text).strip()
        if not text:
            dropped.append(("bos_metin", segment.text[:80]))
            continue
        labels = [label.upper().strip("[]") for label in segment.citation_labels]
        valid = [label for label in labels if label in allowed]
        if segment.kind not in _OLGU_TURLERI:
            # Soru/geçiş repliği olgu taşımamalı. Kısa olması yetmez: "İnsülin
            # kan şekerini artırır, değil mi?" bir soru gibi etiketlenip yanlış
            # bir olguyu doğrulamadan podcast'e sokabilirdi. Bu yüzden içinde
            # kanıtla çelişebilecek bir iddia varsa kanıt testine sokulur.
            if len(text) <= _SORU_AZAMI_KARAKTER and not labels and not _olgu_tasiyor(text):
                kept.append(
                    {
                        "speaker": segment.speaker,
                        "text": text,
                        "citation": None,
                        "citation_id": None,
                        "kind": segment.kind,
                    }
                )
                continue
            if not valid:
                # Etiketsiz ama olgu taşıyan bir soru: hangi kanıtın
                # desteklediğini bul; hiçbiri desteklemiyorsa düşer.
                recovered = _kurtar(text, records)
                if recovered is None:
                    dropped.append(("soru_olgu_dogrulanmadi", text[:80]))
                    continue
                valid = [recovered]
                labels = valid
        if not valid or len(valid) != len(labels):
            neden = "etiket_yok" if not labels else "gecersiz_etiket"
            dropped.append((neden, text[:80]))
            continue
        evidence_text = " ".join(allowed[label].text for label in valid)
        first = allowed[valid[0]]
        replik = {
            "speaker": segment.speaker,
            "kind": segment.kind,
            "text": text,
            "citation": first.citation,
            "citation_id": first.citation_id,
        }
        if not _claim_supported(text, evidence_text):
            if hakem is not None:
                ciftler.append(NliCift(iddia=text, kanit=evidence_text))
                beklemede.append((len(kept), replik, len(ciftler) - 1))
            else:
                dropped.append(("kanit_penceresi", text[:80]))
            continue
        kept.append(replik)
    if beklemede and hakem is not None:
        try:
            kararlar: list[bool] | None = hakem(ciftler)
        except Exception:  # noqa: BLE001 - hakem çökerse iş değil, replik düşer
            kararlar = None
        # Sondan başa eklenir ki önceki konumlar kaymasın.
        for konum, replik, cift in reversed(beklemede):
            if kararlar is not None and kararlar[cift]:
                kept.insert(konum, replik)
            elif kararlar is None:
                dropped.append(("kanit_penceresi", str(replik["text"])[:80]))
            else:
                dropped.append(("nli_reddetti", str(replik["text"])[:80]))
    return kept, dropped


_SORU_SOZCUGU = re.compile(
    r"\b(ne|nasıl|neden|niçin|niye|hangi|kim|kaç|nerede|nereye|nereden|"
    r"mi|mı|mu|mü|midir|mıdır|mudur|müdür)\b",
    re.IGNORECASE | re.UNICODE,
)
# "…artırır, değil mi?" bir soru değil, onaylatılmak istenen bir iddiadır.
_ONAY_KALIPLARI = ("değil mi", "degil mi", "öyle mi", "oyle mi", "doğru mu", "dogru mu",
                   "yanlış mı", "yanlis mi", "haklı mıyım", "sanırım", "galiba")
# Açılış/kapanış kalıpları olgu iddia etmez.
_SUNUM_KALIPLARI = ("merhaba", "hoş geldiniz", "hos geldiniz", "bugünkü konumuz",
                    "bugün konumuz", "bu bölümde", "görüşmek üzere", "gorusmek uzere",
                    "iyi dinlemeler", "teşekkürler", "tesekkurler", "hoşça kalın")


_ISTEK_KIPI = re.compile(
    r"\b\w+(?:elim|alım|alim|eyim|ayım|ayim|sene|sana)\b[^.!?]*[.!?]?\s*$",
    re.IGNORECASE | re.UNICODE,
)


def _olgu_tasiyor(text: str) -> bool:
    """Soru/geçiş repliği doğrulanması gereken bir olgu iddia ediyor mu?

    Ölçüldü: yalnız "yeterli sözcük + çekimli yüklem" ölçütü Türkçe soruların
    neredeyse tamamını olgu sanıyordu ("Bu süreçte hatalar oluşabilir mi?"),
    16 düşen replikten 12'si bu yüzden eleniyordu. Soru soran bir replik bilgi
    ister, iddia etmez; iddia eden soru ise onay kalıbıyla gelir.
    """
    alcak = text.casefold()
    if any(kalip in alcak for kalip in _ONAY_KALIPLARI):
        return True  # bildirim + onay: olgu gibi doğrulanır
    if any(kalip in alcak for kalip in _SUNUM_KALIPLARI):
        return False
    if text.rstrip().endswith("?") and _SORU_SOZCUGU.search(alcak):
        return False  # gerçek soru
    # "Şimdi genetik kodun çözülmesini inceleyelim." bir geçiş davetidir, olgu
    # değil. İstek kipiyle biten replikler sunucunun bölüm bağlayıcılarıdır ve
    # ölçümde düşenlerin kayda değer bölümü buydu.
    if _ISTEK_KIPI.search(text.strip()):
        return False
    return iddia_gibi(text)


def _kurtar(text: str, records: list[StudioEvidence]) -> str | None:
    """Etiketsiz bir iddiayı destekleyen kanıtı bulur; bulamazsa None."""
    for item in records:
        for sentence in _sentences(item.text):
            if _claim_supported(text, sentence):
                return item.label.upper()
    return None


_DUSUS_ADLARI = {
    "kanit_penceresi": "kanıt penceresine sığmadı",
    "nli_reddetti": "NLI hakemi doğrulayamadı (ret ya da yargı bütçesi dışı)",
    "etiket_yok": "alıntı etiketi yoktu",
    "gecersiz_etiket": "uydurma alıntı etiketi",
    "soru_olgu_dogrulanmadi": "soru kılığında doğrulanmamış olgu",
    "bos_metin": "boş metin",
}


def _dusus_ozeti(dusenler: list[tuple[str, str]]) -> str:
    from collections import Counter

    sayim = Counter(neden for neden, _ in dusenler)
    parcalar = [
        f"{adet} {_DUSUS_ADLARI.get(neden, neden)}" for neden, adet in sayim.most_common()
    ]
    return f"{len(dusenler)} replik çıkarıldı: " + ", ".join(parcalar) + "."


def _az_kullanilan_kanitlar(
    records: list[StudioEvidence], segments: list[dict[str, Any]], sinir: int
) -> list[StudioEvidence]:
    """Segmentlerde en az atıf almış kanıt blokları önde, en fazla ``sinir`` adet.

    Telafi turu hep aynı bloğu yeniden anlatmasın diye pencere kullanım
    sayısına göre dizilir; eşitlikte özgün sıra korunur. Anahtar, bölümler
    arasında değişebilen etiket değil kalıcı ``citation_id``dir.
    """
    sayim: dict[str, int] = {}
    for segment in segments:
        kimlik = segment.get("citation_id")
        if kimlik:
            sayim[str(kimlik)] = sayim.get(str(kimlik), 0) + 1
    sirali = sorted(
        enumerate(records),
        key=lambda cift: (sayim.get(str(cift[1].citation_id), 0), cift[0]),
    )
    return [kayit for _, kayit in sirali[:sinir]]


def _tekrarlari_ele(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Neredeyse aynı repliği iki kez seslendirmeyi engeller.

    Model aynı kanıt bloğunu farklı bölümlerde yeniden anlatabiliyor; kanıt
    kapısı ikisini de haklı olarak geçiriyor ve dinleyici aynı cümleyi iki
    kez duyuyordu. Örtüşme içerik sözcükleri üzerinden ölçülür.
    """
    tutulan: list[dict[str, Any]] = []
    imzalar: list[set[str]] = []
    for segment in segments:
        kelimeler = {
            kelime
            for kelime in _ICERIK.findall(str(segment["text"]).casefold())
            if len(kelime) > 3
        }
        if kelimeler and any(
            len(kelimeler & onceki) / max(1, len(kelimeler | onceki)) >= _TEKRAR_ESIGI
            for onceki in imzalar
        ):
            continue
        tutulan.append(segment)
        imzalar.append(kelimeler)
    return tutulan


def _numarala(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Değişmez segment kimliği: montaj üretim sırasına değil buna bakar."""
    return [{**segment, "index": index} for index, segment in enumerate(segments)]


def _iskelet(
    title: str, records: list[StudioEvidence], hedef: int
) -> list[dict[str, Any]]:
    """LLM olmadan üretilen kalıp senaryo: Emel sorar, uzmanlar sırayla yanıtlar."""
    segments: list[dict[str, Any]] = [
        {
            "speaker": "emel",
            "text": (
                f"Merhaba, bugünkü konumuz {title}. Murat, en baştan başlayalım: "
                "kaynaklarda öne çıkan nedir?"
            ),
            "citation": None,
            "citation_id": None,
            "kind": "question",
        }
    ]
    kalip = [
        "Peki bunun devamında ne var?",
        "Bunu biraz daha açar mısın?",
        "Bu neden önemli?",
        "Kaynakta başka ne geçiyor?",
    ]
    for index, item in enumerate(records[: max(2, (hedef - 2) // 2)]):
        if index:
            segments.append(
                {
                    "speaker": "emel",
                    "text": kalip[index % len(kalip)],
                    "citation": None,
                    "citation_id": None,
                    "kind": "question",
                }
            )
        cumleler = _sentences(item.text)
        metin = " ".join(cumleler[:2]) if cumleler else item.text.strip()
        segments.append(
            {
                # Uzmanlar dönüşümlü konuşur: tek sesli kalıp senaryo, LLM'li
                # bölümün çok sesli dokusundan kopuk duyuluyordu.
                "speaker": UZMANLAR[index % len(UZMANLAR)],
                "text": metin,
                "citation": item.citation,
                "citation_id": item.citation_id,
                "kind": "fact",
            }
        )
    segments.append(
        {
            "speaker": UZMANLAR[0],
            "text": (
                "Bugünlük bu kadar. Ayrıntılar için not defterindeki kaynak "
                "alıntılarına bakabilirsiniz."
            ),
            "citation": None,
            "citation_id": None,
            "kind": "transition",
        }
    )
    return _numarala(segments)


def script_markdown(title: str, segments: list[dict[str, Any]]) -> str:
    satirlar = [f"# {title}", "", "## Podcast senaryosu", ""]
    for segment in segments:
        ad = _SUNUM_ADLARI.get(str(segment.get("speaker")), "Konuşmacı")
        alinti = f" {segment['citation']}" if segment.get("citation") else ""
        satirlar.append(f"**{ad}:** {segment['text']}{alinti}")
        satirlar.append("")
    return "\n".join(satirlar).strip()
