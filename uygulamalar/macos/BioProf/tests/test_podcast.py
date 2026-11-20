"""Podcast hattı: senaryo doğrulaması ve sessiz ses kaybına karşı kapılar."""

from __future__ import annotations

import asyncio
import io
import json
import re
import wave
from pathlib import Path

import pytest

from bioprof.providers.base import ProviderUnavailableError
from bioprof.studio.artifacts import (
    MasteredAudio,
    StudioEngine,
    StudioEvidence,
    StudioExportError,
    StudioMediaRenderer,
)
from bioprof.studio.podcast import PodcastScriptBuilder

_METIN = (
    "Mitokondri, ökaryot hücrelerde bulunan çift zarlı bir organeldir. "
    "Hücresel solunum yoluyla ATP üretiminden sorumludur. "
    "Kloroplast yalnızca bitki hücrelerinde bulunur."
)


def _records() -> list[StudioEvidence]:
    return [
        StudioEvidence(
            label="S1", text=_METIN, source_title="Hücre", citation_id="cit-1"
        )
    ]


def _wav(seconds: float = 1.0, rate: int = 24_000, *, silent: bool = False) -> bytes:
    """Duyulur genlikte sahte konuşma; silent=True tam boyda sessizlik üretir."""
    ornek = b"\x00\x00" if silent else b"\x00\x20"
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(ornek * int(rate * seconds))
    return buffer.getvalue()


def _gercekci_sure(text: str) -> float:
    """Türkçe konuşma hızına yakın sahte süre (~14 karakter/saniye)."""
    return max(0.4, len(text) / 14.0)


def _script(segments: list[dict]) -> str:
    return json.dumps({"segments": segments}, ensure_ascii=False)


def _builder(cevap):
    async def chat(messages, *, max_tokens=None):
        if isinstance(cevap, Exception):
            raise cevap
        return cevap if isinstance(cevap, str) else cevap.pop(0)

    return PodcastScriptBuilder(chat)


def _build(builder: PodcastScriptBuilder):
    return asyncio.run(builder.build("Mitokondri", _records()))


def test_gecerli_senaryo_kabul_edilir() -> None:
    raw = _script(
        [
            {"speaker": "emel", "text": "Bugün mitokondriyi konuşuyoruz.", "kind": "question"},
            {
                "speaker": "murat",
                "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                "kind": "fact",
                "citation_labels": ["S1"],
            },
        ]
    )
    segments, uyarilar, llm = _build(_builder(raw))
    assert llm is True
    assert [item["speaker"] for item in segments] == ["emel", "murat"]
    # Değişmez segment kimliği: montaj üretim sırasına değil buna bakar.
    assert [item["index"] for item in segments] == [0, 1]
    assert segments[1]["citation"] == "[S1]"
    assert not uyarilar


def test_desteksiz_replik_dusurulur() -> None:
    raw = _script(
        [
            {"speaker": "emel", "text": "Başlayalım.", "kind": "question"},
            {
                "speaker": "murat",
                "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                "kind": "fact",
                "citation_labels": ["S1"],
            },
            {
                "speaker": "murat",
                "text": "Mitokondri fotosentez yaparak glikoz üretir.",
                "kind": "fact",
                "citation_labels": ["S1"],
            },
        ]
    )
    segments, uyarilar, _ = _build(_builder([raw, raw]))
    assert all("fotosentez" not in item["text"] for item in segments)
    assert any("çıkarıldı" in uyari or "kanıtsız" in uyari for uyari in uyarilar)


def test_uydurulan_etiket_reddedilir() -> None:
    raw = _script(
        [
            {"speaker": "emel", "text": "Başlayalım.", "kind": "question"},
            {
                "speaker": "murat",
                "text": "Mitokondri ribozom üretir.",
                "kind": "fact",
                "citation_labels": ["S7"],
            },
        ]
    )
    segments, _, _ = _build(_builder([raw, raw]))
    assert all("ribozom" not in item["text"] for item in segments)


def test_soru_repligi_olgu_tasiyamaz() -> None:
    uzun_olgu = "Mitokondri " + "çok uzun bir olgu cümlesi " * 12
    raw = _script(
        [
            {"speaker": "emel", "text": uzun_olgu, "kind": "question"},
            {
                "speaker": "murat",
                "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                "kind": "fact",
                "citation_labels": ["S1"],
            },
        ]
    )
    segments, _, _ = _build(_builder([raw, raw]))
    assert all("çok uzun bir olgu" not in item["text"] for item in segments)


def test_bozuk_json_iskelete_duser() -> None:
    segments, uyarilar, llm = _build(_builder(["bu JSON değil", "yine değil"]))
    assert llm is False
    assert segments and segments[0]["speaker"] == "emel"
    assert any("Kalıp senaryoya" in uyari for uyari in uyarilar)


def test_llm_yokken_iskelet_uretilir() -> None:
    segments, uyarilar, llm = asyncio.run(
        PodcastScriptBuilder(None).build("Mitokondri", _records())
    )
    assert llm is False
    konusmacilar = {item["speaker"] for item in segments}
    assert "emel" in konusmacilar and konusmacilar <= {"emel", "mazlum", "murat"}
    assert any("kalıp senaryo" in uyari for uyari in uyarilar)


def test_llm_hatasi_iskelete_duser() -> None:
    segments, _, llm = _build(_builder(ProviderUnavailableError("model kapalı")))
    assert llm is False
    assert segments


def _podcast_artifact():
    return StudioEngine().generate("podcast", title="Mitokondri", evidence=_records())


def _render(tmp_path: Path, synthesizer, mastering=None, **kwargs):
    # Gerçek beklemeler (XTTS checkpoint takası için) testleri dakikalarca
    # yavaşlatır; burada sıfırlanır.
    kwargs.setdefault("retry_delays", (0.0, 0.0))
    return asyncio.run(
        StudioMediaRenderer().render_podcast(
            _podcast_artifact(),
            tmp_path / "podcast",
            synthesizer=synthesizer,
            mastering=mastering,
            **kwargs,
        )
    )


def test_bos_wav_isi_kirmizi_yapar(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        return b"", "audio/wav"

    with pytest.raises(StudioExportError):
        _render(tmp_path, synth)


def test_gecersiz_wav_isi_kirmizi_yapar(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        return b"bunlar WAV baytlari degil", "audio/wav"

    with pytest.raises(StudioExportError):
        _render(tmp_path, synth)


def test_konusmaciya_gore_gruplanir(tmp_path: Path) -> None:
    çağrılar: list[str] = []

    async def synth(text, voice, verify):
        çağrılar.append(voice)
        return _wav(_gercekci_sure(text)), "audio/wav"

    _render(tmp_path, synth)
    # Ses başına tek checkpoint takası: her sesin replikleri bitişik olmalı.
    gorulen: list[str] = []
    for ses in çağrılar:
        if not gorulen or gorulen[-1] != ses:
            gorulen.append(ses)
    assert len(gorulen) == len(set(gorulen)), f"ses grupları bölünmüş: {gorulen}"
    assert len(set(çağrılar)) >= 2


def test_montaj_senaryo_sirasinda(tmp_path: Path) -> None:
    artifact = _podcast_artifact()
    sıra = [str(item["speaker"]) for item in artifact.structured_data["segments"]]

    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    result = _render(tmp_path, synth)
    srt = Path(next(f for f in result.files if f.endswith(".srt"))).read_text(encoding="utf-8")
    adlar = [
        line.split(":")[0]
        for line in srt.splitlines()
        if line.startswith(("Murat", "Emel", "Mazlum"))
    ]
    assert [ad.lower() for ad in adlar] == sıra


def test_srt_replik_sayisiyla_eslesir(tmp_path: Path) -> None:
    artifact = _podcast_artifact()
    beklenen = len(artifact.structured_data["segments"])

    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    result = _render(tmp_path, synth)
    srt = Path(next(f for f in result.files if f.endswith(".srt"))).read_text(encoding="utf-8")
    assert len([block for block in srt.strip().split("\n\n") if block]) == beklenen


def test_mastering_sure_tutarsizsa_kirmizi(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    async def kotu_mastering(chunks, gap_ms, fmt="wav"):
        # Parçaların yarısını sessizce düşüren bir mastering: "başarılı" görünüp
        # sesin yarısını kaybetme sınıfı tam olarak budur.
        return MasteredAudio(data=_wav(0.5))

    with pytest.raises(StudioExportError):
        _render(tmp_path, synth, kotu_mastering)


def test_mastering_yoksa_ham_birlestirme(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    async def yok(chunks, gap_ms, fmt="wav"):
        return None

    result = _render(tmp_path, synth, yok)
    assert result.status == "completed"
    assert Path(result.files[0]).suffix == ".wav"


def test_mastering_hatasi_uyariyla_gecer(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    async def patlayan(chunks, gap_ms, fmt="wav"):
        raise RuntimeError("SesLab 404")

    result = _render(tmp_path, synth, patlayan)
    assert result.status == "completed"
    assert any("Mastering yapılamadı" in uyari for uyari in result.warnings)


def test_seslendirme_servisi_yoksa_needs_service(tmp_path: Path) -> None:
    result = _render(tmp_path, None)
    assert result.status == "needs_service"
    assert not result.files


def test_kesik_replik_yeniden_denenir(tmp_path: Path) -> None:
    # XTTS bir repliği sessizce yarıda kesebiliyor; ilk deneme kısa gelirse
    # bir kez daha istenir. Toplam süre kapısı bunu göremez, çünkü toplam yine
    # parçaların toplamına eşittir.
    çağrı = {"n": 0}

    async def synth(text, voice, verify):
        çağrı["n"] += 1
        if çağrı["n"] == 1:
            return _wav(0.04), "audio/wav"
        return _wav(_gercekci_sure(text)), "audio/wav"

    result = _render(tmp_path, synth)
    assert result.status == "completed"
    assert any("kesik geldi" in uyari for uyari in result.warnings)


def test_israrla_kesik_replik_isi_kirmizi_yapar(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        return _wav(0.04), "audio/wav"

    with pytest.raises(StudioExportError, match="eksik seslendirildi"):
        _render(tmp_path, synth)


def test_mp3_uretilir(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    async def mastering(chunks, gap_ms, fmt="wav"):
        toplam = sum(_sure(chunk) for chunk in chunks) + (len(chunks) - 1) * gap_ms / 1000.0
        if fmt == "mp3":
            return MasteredAudio(data=_sahte_mp3(toplam))
        return MasteredAudio(
            data=_wav(toplam),
            metadata={"segment_durations": [_sure(chunk) for chunk in chunks]},
        )

    result = _render(tmp_path, synth, mastering)
    assert [Path(item).suffix for item in result.files] == [".mp3", ".wav", ".srt"]
    assert result.media_types[0] == "audio/mpeg"


def _sahte_mp3(seconds: float) -> bytes:
    """Süresi okunabilen en küçük geçerli MPEG-1 Layer III akışı."""
    # 128 kbps, 44.1 kHz → çerçeve 417 bayt, çerçeve başına 1152/44100 sn
    frame = b"\xff\xfb\x90\x00" + b"\x00" * 413
    count = max(1, round(seconds / (1152 / 44100)))
    return frame * count


def test_kesik_mp3_yayimlanmaz(tmp_path: Path) -> None:
    # MP3 birincil dosya olduğu için WAV'la aynı kapılardan geçmeli.
    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    async def mastering(chunks, gap_ms, fmt="wav"):
        toplam = sum(_sure(chunk) for chunk in chunks) + (len(chunks) - 1) * gap_ms / 1000.0
        if fmt == "mp3":
            return MasteredAudio(data=_sahte_mp3(3.0))  # kodlama yarıda kesilmiş
        return MasteredAudio(data=_wav(toplam))

    result = _render(tmp_path, synth, mastering)
    assert all(not item.endswith(".mp3") for item in result.files)
    assert any("MP3 süresi tutarsız" in uyari for uyari in result.warnings)


def test_mastering_sureleri_altyaziya_yansir(tmp_path: Path) -> None:
    # Mastering kenar sessizliğini kırpar; SRT ham TTS sürelerini kullanırsa kayar.
    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    kirpilmis: list[float] = []

    async def mastering(chunks, gap_ms, fmt="wav"):
        sureler = [max(0.3, _sure(chunk) - 0.2) for chunk in chunks]
        kirpilmis.clear()
        kirpilmis.extend(sureler)
        toplam = sum(sureler) + (len(chunks) - 1) * gap_ms / 1000.0
        if fmt == "mp3":
            return MasteredAudio(data=_sahte_mp3(toplam))
        return MasteredAudio(data=_wav(toplam), metadata={"segment_durations": sureler})

    result = _render(tmp_path, synth, mastering)
    srt = Path(next(f for f in result.files if f.endswith(".srt"))).read_text(encoding="utf-8")
    ilk_bitis = srt.splitlines()[1].split(" --> ")[1]
    saat, dakika, kalan = ilk_bitis.split(":")
    saniye, milisaniye = kalan.split(",")
    bitis = int(saat) * 3600 + int(dakika) * 60 + int(saniye) + int(milisaniye) / 1000
    assert abs(bitis - kirpilmis[0]) < 0.05


def _sure(chunk: bytes) -> float:
    with wave.open(io.BytesIO(chunk), "rb") as handle:
        return handle.getnframes() / handle.getframerate()


def test_tam_boyda_sessiz_replik_yakalanir(tmp_path: Path) -> None:
    # Süre kapısı bunu göremez: uzunluk beklendiği gibidir, ses yoktur.
    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text), silent=True), "audio/wav"

    with pytest.raises(StudioExportError, match="sessiz"):
        _render(tmp_path, synth)


def test_sessiz_replik_yeniden_denenir(tmp_path: Path) -> None:
    çağrı = {"n": 0}

    async def synth(text, voice, verify):
        çağrı["n"] += 1
        sessiz = çağrı["n"] == 1
        return _wav(_gercekci_sure(text), silent=sessiz), "audio/wav"

    result = _render(tmp_path, synth)
    assert result.status == "completed"
    assert any("sessiz geldi" in uyari for uyari in result.warnings)


def test_mastering_sessiz_ses_dondurirse_kirmizi(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        return _wav(_gercekci_sure(text)), "audio/wav"

    async def sessizlestiren(chunks, gap_ms, fmt="wav"):
        toplam = sum(_sure(chunk) for chunk in chunks) + (len(chunks) - 1) * gap_ms / 1000.0
        return MasteredAudio(data=_wav(toplam, silent=True))

    with pytest.raises(StudioExportError, match="sessiz"):
        _render(tmp_path, synth, sessizlestiren)


def test_kesik_json_tam_replikleri_kurtarir() -> None:
    # Üretim token sınırında kesilirse tek eksik parantez yüzünden kabul
    # edilmiş onlarca replik çöpe gidiyordu.
    kesik = (
        '{"segments": ['
        '{"speaker": "emel", "text": "Bugün mitokondriyi konuşuyoruz.", "kind": "question"},'
        '{"speaker": "murat", "text": "Mitokondri ökaryot hücrelerde bulunan çift '
        'zarlı bir organeldir.", "kind": "fact", "citation_labels": ["S1"]},'
        '{"speaker": "emel", "text": "Peki bu nasıl'
    )

    async def chat(messages, *, max_tokens=None):
        return kesik

    segments, _, llm = asyncio.run(PodcastScriptBuilder(chat).build("Konu", _records()))
    assert llm is True
    assert len(segments) == 2  # yarım kalan üçüncü replik atılır
    assert segments[1]["citation"] == "[S1]"


def test_token_butcesi_replik_sayisiyla_olceklenir() -> None:
    butceler: list[int | None] = []

    async def chat(messages, *, max_tokens=None):
        butceler.append(max_tokens)
        return "bu JSON değil"

    # Tek geçişte üretilen iki preset karşılaştırılır; "uzun" artık bölümlü
    # üretime gittiği için bütçesi bölüm hedefine göre hesaplanır.
    for uzunluk in ("kisa", "orta"):
        asyncio.run(PodcastScriptBuilder(chat).build("Konu", _records(), length=uzunluk))
    assert butceler[0] < butceler[-1]
    assert butceler[-1] >= 24 * 100


def test_gercek_sorular_kanit_testine_sokulmaz() -> None:
    from bioprof.studio.podcast import _olgu_tasiyor

    # Ölçüldü: bunların hepsi "olgu" sanılıp eleniyordu.
    sorular = [
        "Peki bu DNA'nın kendini eşleme yeteneği nasıl çalışıyor?",
        "Bu süreçte hatalar oluşabilir mi ve nasıl düzeltilir?",
        "Bu teoriye göre genler kromozomların üzerinde mi yer alıyor?",
        "Eşey kromozomları her organizmada aynı mı?",
        "Kromozomlarda hata oluştuğunda ne olur?",
    ]
    for soru in sorular:
        assert not _olgu_tasiyor(soru), soru

    sunum = [
        "Merhaba arkadaşlar, bugünkü konumuz DNA ve genler.",
        "Görüşmek üzere, iyi dinlemeler.",
    ]
    for metin in sunum:
        assert not _olgu_tasiyor(metin), metin


def test_onaylatilan_iddia_hala_olgu_sayilir() -> None:
    from bioprof.studio.podcast import _olgu_tasiyor

    # Soru işareti taşısa da bunlar bir olgu ileri sürüyor.
    assert _olgu_tasiyor("İnsülin kan şekerini artırır, değil mi?")
    assert _olgu_tasiyor("Mitokondri fotosentez yapar, doğru mu?")
    assert _olgu_tasiyor("Kromozom sayısı mayozda iki katına çıkar.")


def test_soru_kiligindaki_yanlis_olgu_podcaste_giremez() -> None:
    raw = _script(
        [
            {
                "speaker": "emel",
                "text": "Mitokondri fotosentez yapar, değil mi?",
                "kind": "question",
            },
            {
                "speaker": "murat",
                "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                "kind": "fact",
                "citation_labels": ["S1"],
            },
        ]
    )
    segments, _, _ = _build(_builder([raw, raw]))
    assert all("fotosentez yapar" not in item["text"] for item in segments)


def test_uc_konusmaci_ve_format_turleri_kabul_edilir() -> None:
    raw = _script(
        [
            {"speaker": "emel", "text": "Bugün mitokondriyi konuşuyoruz.", "kind": "transition"},
            {
                "speaker": "mazlum",
                "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                "kind": "explain",
                "citation_labels": ["S1"],
            },
            {
                "speaker": "murat",
                "text": "Hücresel solunum yoluyla ATP üretiminden sorumludur.",
                "kind": "discuss",
                "citation_labels": ["S1"],
            },
            {
                "speaker": "mazlum",
                "text": "Kloroplast yalnızca bitki hücrelerinde bulunur.",
                "kind": "summary",
                "citation_labels": ["S1"],
            },
        ]
    )
    segments, uyarilar, llm = _build(_builder(raw))
    assert llm is True
    assert [item["speaker"] for item in segments] == ["emel", "mazlum", "murat", "mazlum"]
    # Bölüm türü korunmalı: montaj ve altyazı dokusu buna bakabilir.
    assert [item["kind"] for item in segments] == [
        "transition",
        "explain",
        "discuss",
        "summary",
    ]
    assert not uyarilar


def test_yeni_format_turleri_de_kanit_kapisindan_gecer() -> None:
    # explain/discuss/summary "fact" kadar sıkı doğrulanmalı; aksi hâlde
    # yeni tür eklemek doğrulamayı atlatmanın yolu olurdu.
    raw = _script(
        [
            {"speaker": "emel", "text": "Başlayalım.", "kind": "question"},
            {
                "speaker": "mazlum",
                "text": "Mitokondri fotosentez yaparak glikoz üretir.",
                "kind": "explain",
                "citation_labels": ["S1"],
            },
            {
                "speaker": "murat",
                "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                "kind": "discuss",
                "citation_labels": ["S1"],
            },
        ]
    )
    segments, _, _ = _build(_builder([raw, raw]))
    assert all("fotosentez" not in item["text"] for item in segments)
    assert any("çift zarlı" in item["text"] for item in segments)


def test_iskelette_uzmanlar_donusumlu_konusur() -> None:
    kayitlar = [
        StudioEvidence(
            label=f"S{i}",
            text=f"Kanıt cümlesi {i}. Ayrıntı {i}.",
            source_title="Kaynak",
            citation_id=f"cit-{i}",
        )
        for i in range(1, 5)
    ]
    segments = asyncio.run(PodcastScriptBuilder(None).build("Konu", kayitlar))[0]
    uzman_sirasi = [s["speaker"] for s in segments if s["speaker"] != "emel"]
    # Tek sesli kalıp senaryo, LLM'li bölümün çok sesli dokusundan kopuktu.
    assert len(set(uzman_sirasi)) == 2


def test_seslab_ses_adlari_dogru_eslesir() -> None:
    from bioprof.studio.podcast import SES_ADLARI

    # SesLab'da kayıtlı adlar; yanlış ad sessizce varsayılan sese düşerdi.
    assert SES_ADLARI["mazlum"] == "Mazlum Kiper"
    assert SES_ADLARI["murat"] == "Murat"
    assert SES_ADLARI["emel"] == "emel"


def test_ayni_replik_iki_kez_seslendirilmez() -> None:
    # Model aynı kanıtı iki bölümde yeniden anlatabiliyor; kapı ikisini de
    # haklı olarak geçiriyor ve dinleyici aynı cümleyi iki kez duyuyordu.
    raw = _script(
        [
            {"speaker": "emel", "text": "Başlayalım.", "kind": "question"},
            {
                "speaker": "mazlum",
                "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                "kind": "explain",
                "citation_labels": ["S1"],
            },
            {
                "speaker": "murat",
                "text": "Mitokondri, ökaryot hücrelerde bulunan çift zarlı bir organeldir!",
                "kind": "discuss",
                "citation_labels": ["S1"],
            },
        ]
    )
    segments, _, _ = _build(_builder(raw))
    organel = [s for s in segments if "çift zarlı" in s["text"]]
    assert len(organel) == 1


def test_gecis_davetleri_olgu_sayilmaz() -> None:
    from bioprof.studio.podcast import _olgu_tasiyor

    # Sunucunun bölüm bağlayıcıları; ölçümde bunlar "olgu" sanılıp eleniyordu.
    for metin in [
        "Şimdi genetik kodun nasıl çözüldüğünü inceleyelim.",
        "Eşeye bağlı kalıtım ve rekombinasyonun önemini özetleyelim.",
        "Sırada DNA'nın paketlenmesi var, ona bakalım.",
    ]:
        assert not _olgu_tasiyor(metin), metin

    # Davet kipi olsa da olgu onaylatan replik hâlâ doğrulanır.
    assert _olgu_tasiyor("Mitokondri fotosentez yapar, değil mi?")


def test_hedef_sure_replik_sayisina_cevrilir() -> None:
    from bioprof.studio.podcast import SANIYE_BASINA_REPLIK, replik_hedefi

    # 30 dakika ≈ 240 replik (ölçülen 7.5 sn/replik).
    assert replik_hedefi(target_minutes=30, length="orta") == round(30 * 60 / SANIYE_BASINA_REPLIK)
    assert replik_hedefi(target_minutes=90, length="orta") > 600
    # Dakika verilmezse preset korunur (eski davranış).
    assert replik_hedefi(target_minutes=None, length="kisa") == 12
    assert replik_hedefi(target_minutes=None, length="orta") == 24


def test_uzun_bolum_anahat_cikarip_bolum_bolum_uretir() -> None:
    import json as _json

    cagrilar: list[str] = []

    async def chat(messages, *, max_tokens=None):
        sistem = messages[0]["content"]
        if "ANAHATINI" in sistem:
            cagrilar.append("anahat")
            return _json.dumps(
                {"chapters": ["DNA yapısı", "Replikasyon", "Genetik kod"]},
                ensure_ascii=False,
            )
        cagrilar.append("bolum")
        return _script(
            [
                {"speaker": "emel", "text": "Devam edelim.", "kind": "transition"},
                {
                    "speaker": "mazlum",
                    "text": (
                        "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir "
                        "organeldir."
                    ),
                    "kind": "explain",
                    "citation_labels": ["S1"],
                },
            ]
        )

    segments, _, llm = asyncio.run(
        PodcastScriptBuilder(chat).build("Konu", _records(), target_minutes=15)
    )
    assert llm is True
    assert cagrilar[0] == "anahat"
    # Her alt başlık için ayrı bir senaryo çağrısı + kısa kalan süre için en az
    # bir telafi çağrısı yapılmalı (yineleme süzgeci hep aynı repliği getiren bu
    # sahte modelde telafiyi ilk turda keser).
    assert cagrilar.count("bolum") >= 3
    # Bölümler arası yineleme süzgeci aynı repliği bir kez bırakır.
    assert segments


def test_bolum_basina_kendi_kaniti_cekilir() -> None:
    import json as _json

    istenen_basliklar: list[str] = []

    async def chat(messages, *, max_tokens=None):
        if "ANAHATINI" in messages[0]["content"]:
            return _json.dumps({"chapters": ["Alt başlık A", "Alt başlık B"]})
        return _script(
            [
                {
                    "speaker": "mazlum",
                    "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                    "kind": "explain",
                    "citation_labels": ["S1"],
                },
                {"speaker": "emel", "text": "Anladım.", "kind": "transition"},
            ]
        )

    async def provider(baslik: str):
        istenen_basliklar.append(baslik)
        return _records()

    asyncio.run(
        PodcastScriptBuilder(chat).build(
            "Konu", _records(), target_minutes=15, chapter_provider=provider
        )
    )
    # Tüm bölümleri aynı kanıtla yazmak, aynı bilgiyi defalarca anlatmak olurdu.
    assert istenen_basliklar == ["Alt başlık A", "Alt başlık B"]


def test_anahat_basarisizsa_bolumler_yine_uretilir() -> None:
    async def chat(messages, *, max_tokens=None):
        if "ANAHATINI" in messages[0]["content"]:
            return "bu JSON değil"
        return _script(
            [
                {
                    "speaker": "murat",
                    "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                    "kind": "explain",
                    "citation_labels": ["S1"],
                },
                {"speaker": "emel", "text": "Peki.", "kind": "transition"},
            ]
        )

    segments, uyarilar, llm = asyncio.run(
        PodcastScriptBuilder(chat).build("Konu", _records(), target_minutes=15)
    )
    assert llm is True and segments
    assert any("Anahat üretilemedi" in u for u in uyarilar)


@pytest.mark.parametrize("stil", ["sohbet", "ders", "tartisma", "tekrar", "roportaj"])
def test_her_stil_istemde_kendi_dokusunu_verir(stil: str) -> None:
    from bioprof.studio.podcast import PODCAST_STILLERI, _sistem_istemi

    istem = _sistem_istemi(stil)
    assert PODCAST_STILLERI[stil].yonerge.split(".")[0] in istem
    # Sistem istemi çağrıdan çağrıya sabit kalmalı: değişen her ayrıntı
    # (bölüm bilgisi, hedef replik sayısı) istem önbelleğini geçersiz kılar.
    assert istem == _sistem_istemi(stil)


def test_bolum_ilerlemesi_ara_kayit_tasir() -> None:
    import json as _json

    kayitlar: list[tuple[int, int, str, int]] = []

    async def chat(messages, *, max_tokens=None):
        if "ANAHATINI" in messages[0]["content"]:
            return _json.dumps({"chapters": ["A", "B"]})
        return _script(
            [
                {
                    "speaker": "mazlum",
                    "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                    "kind": "explain",
                    "citation_labels": ["S1"],
                },
                {"speaker": "emel", "text": "Peki.", "kind": "transition"},
            ]
        )

    async def ilerleme(done, total, baslik, yazilanlar):
        kayitlar.append((done, total, baslik, len(yazilanlar)))

    asyncio.run(
        PodcastScriptBuilder(chat).build(
            "Konu", _records(), target_minutes=15, progress=ilerleme
        )
    )
    # Saatlerce süren üretim yarıda kesilirse yazılmış bölümler kaybolmamalı.
    assert kayitlar[0][:3] == (0, 2, "A")
    assert kayitlar[-1][0] == 2
    assert kayitlar[-1][3] > 0  # son çağrıda yazılmış replikler taşınır


def test_tek_zaman_asimi_tum_uretimi_dusurmez(tmp_path: Path) -> None:
    # Uzun bölümlerde bir repliğin zaman aşımı, saatlerce süren üretimi
    # çöpe atıyordu. Replik yeniden denenir, ısrar ederse atlanır.
    sayac = {"n": 0}

    async def synth(text, voice, verify):
        sayac["n"] += 1
        if sayac["n"] == 2:
            raise TimeoutError("SesLab yanıt vermedi")
        return _wav(_gercekci_sure(text)), "audio/wav"

    result = _render(tmp_path, synth)
    assert result.status == "completed"
    assert any("yeniden deneniyor" in u for u in result.warnings)


def test_israrci_zaman_asiminda_replik_atlanir(tmp_path: Path) -> None:
    hedef = {"index": 1}

    async def synth(text, voice, verify):
        # Belirli bir replik her denemede patlar; diğerleri üretilir.
        if "ATLA" in text or hedef["index"] == 0:
            raise TimeoutError("kalıcı hata")
        return _wav(_gercekci_sure(text)), "audio/wav"

    artifact = _podcast_artifact()
    segs = artifact.structured_data["segments"]
    segs[1]["text"] = "ATLA " + segs[1]["text"]

    async def render():
        return await StudioMediaRenderer().render_podcast(
            artifact,
            tmp_path / "p",
            synthesizer=synth,
            mastering=None,
            retry_delays=(0.0, 0.0),
        )

    result = asyncio.run(render())
    assert result.status == "completed"
    assert any("bölümden çıkarıldı" in u for u in result.warnings)
    srt = Path(next(f for f in result.files if f.endswith(".srt"))).read_text(encoding="utf-8")
    # Altyazı sesle hizalı kalmalı: atlanan replik SRT'de de olmamalı.
    assert "ATLA" not in srt


def test_cok_fazla_atlama_isi_kirmizi_yapar(tmp_path: Path) -> None:
    async def synth(text, voice, verify):
        raise TimeoutError("servis kapalı")

    with pytest.raises(StudioExportError):
        _render(tmp_path, synth)


def _cok_kanit(adet: int) -> list[StudioEvidence]:
    """Gerçek parça boyutuna yakın (~2,3 bin karakter) kanıt havuzu."""
    return [
        StudioEvidence(
            label=f"S{i}",
            text=f"{i}. blok konusu ayırt edici bir cümledir. " + _METIN * 12,
            source_title="Hücre",
            citation_id=f"cit-{i}",
        )
        for i in range(1, adet + 1)
    ]


def test_bolum_istemi_kanit_butcesiyle_sinirlanir() -> None:
    """Bir bölüm tüm havuzu değil, kendi penceresini görmeli.

    Ölçüldü: 24 blokluk istem (19 bin token) bölüm başına 138 sn, 8 blokluk
    istem ~81 sn. Fazla bloklar okunup atılıyordu.
    """
    from bioprof.studio.podcast import BOLUM_KANIT_SINIRI

    gorulen: list[int] = []

    async def chat(messages, *, max_tokens=None):
        if "ANAHATINI" in messages[0]["content"]:
            return json.dumps({"chapters": ["A", "B", "C"]})
        istem = messages[1]["content"]
        gorulen.append(istem.count("<untrusted_evidence"))
        etiket = re.findall(r'<untrusted_evidence id="(S\d+)"', istem)[0]
        return _script(
            [
                {
                    "speaker": "mazlum",
                    "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                    "kind": "explain",
                    "citation_labels": [etiket],
                },
                {"speaker": "emel", "text": "Anladım, devam edelim.", "kind": "transition"},
            ]
        )

    havuz = _cok_kanit(24)

    async def provider(baslik: str):
        return havuz

    asyncio.run(
        PodcastScriptBuilder(chat).build(
            "Konu", havuz, target_minutes=15, chapter_provider=provider
        )
    )
    assert gorulen, "hiç bölüm yazılmadı"
    assert max(gorulen) <= BOLUM_KANIT_SINIRI


def test_anahat_kanitlari_kisaltilmis_gorur() -> None:
    """Anahat başlık seçer; blokların tamamını okuması gerekmez."""
    uzunluklar: dict[str, int] = {}

    async def chat(messages, *, max_tokens=None):
        if "ANAHATINI" in messages[0]["content"]:
            uzunluklar["anahat"] = len(messages[1]["content"])
            return json.dumps({"chapters": ["A", "B"]})
        uzunluklar.setdefault("bolum", len(messages[1]["content"]))
        return _script(
            [
                {
                    "speaker": "mazlum",
                    "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                    "kind": "explain",
                    "citation_labels": ["S1"],
                },
                {"speaker": "emel", "text": "Anladım, devam edelim.", "kind": "transition"},
            ]
        )

    havuz = _cok_kanit(8)
    asyncio.run(PodcastScriptBuilder(chat).build("Konu", havuz, target_minutes=15))
    assert uzunluklar["anahat"] < uzunluklar["bolum"]


def test_paylasilan_havuzda_her_bolum_farkli_pencere_gorur() -> None:
    """Kanıt sağlayıcı yoksa bölümlere sabit ilk N blok verilemez.

    Verilseydi bütün bölümler aynı bilgiyi anlatır, yineleme süzgeci de
    üretim bedeli ödendikten sonra temizlerdi.
    """
    pencereler: list[str] = []

    async def chat(messages, *, max_tokens=None):
        istem = messages[1]["content"]
        if "ANAHATINI" in messages[0]["content"]:
            return json.dumps({"chapters": ["A", "B"]})
        pencereler.append(istem)
        # Bölüm hangi pencereyi gördüyse ONUN ilk etiketini kullan: geçerli
        # etiket kümesi bölümden bölüme değişir.
        etiket = re.findall(r'<untrusted_evidence id="(S\d+)"', istem)[0]
        return _script(
            [
                {
                    "speaker": "mazlum",
                    "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                    "kind": "explain",
                    "citation_labels": [etiket],
                },
                {"speaker": "emel", "text": "Anladım, devam edelim.", "kind": "transition"},
            ]
        )

    asyncio.run(
        PodcastScriptBuilder(chat).build("Konu", _cok_kanit(24), target_minutes=15)
    )
    # İki bölüm + (kısa kalan süre için) olası telafi çağrıları.
    assert len(pencereler) >= 2
    # Bölümler farklı kanıt bloklarını görmeli.
    assert re.findall(r'id="(S\d+)"', pencereler[0]) != re.findall(
        r'id="(S\d+)"', pencereler[1]
    )


def test_yeniden_deneme_kabul_edilmis_replikleri_korur() -> None:
    """Kanıtsız replik oranı yüksekse bölüm sıfırdan yazılmamalı.

    Eski davranış iki denemeden yalnız uzun olanı tutuyordu: ilk denemenin
    doğrulanmış replikleri de, onları üreten süre de çöpe gidiyordu.
    """
    denemeler: list[dict] = []

    async def chat(messages, *, max_tokens=None):
        denemeler.append({"istem": messages[1]["content"], "sistem": messages[0]["content"]})
        if len(denemeler) == 1:
            # Bir geçerli replik + üç kanıtsız → düşüş oranı eşiğin üstünde.
            return _script(
                [
                    {
                        "speaker": "mazlum",
                        "text": (
                            "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir "
                            "organeldir."
                        ),
                        "kind": "explain",
                        "citation_labels": ["S1"],
                    },
                    *[
                        {
                            "speaker": "murat",
                            "text": f"Uydurma {i}: ribozom çekirdekçikte üretilir.",
                            "kind": "fact",
                            "citation_labels": ["S9"],
                        }
                        for i in range(3)
                    ],
                ]
            )
        return _script(
            [
                {
                    "speaker": "murat",
                    "text": "Hücresel solunum yoluyla ATP üretiminden sorumludur.",
                    "kind": "fact",
                    "citation_labels": ["S1"],
                },
                {"speaker": "emel", "text": "Bunu biraz açar mısın?", "kind": "question"},
            ]
        )

    segments, uyarilar, llm = asyncio.run(
        PodcastScriptBuilder(chat).build("Konu", _records(), length="kisa")
    )
    assert llm is True
    assert len(denemeler) == 2
    metinler = [s["text"] for s in segments]
    # İlk denemenin geçerli repliği KORUNMALI, ikincininki üstüne eklenmeli.
    assert any("Mitokondri" in t for t in metinler)
    assert any("ATP" in t for t in metinler)
    # Sistem istemi iki denemede birebir aynı kalmalı (istem önbelleği).
    assert denemeler[0]["sistem"] == denemeler[1]["sistem"]
    # İkinci istem, zaten anlatılanları bildirmeli ki model tekrar etmesin.
    assert "ZATEN ANLATILANLAR" in denemeler[1]["istem"]
    # Kanıt bloğu önek olarak korunmalı; yalnız kuyruk değişmeli.
    ortak = _kanit_oneki(denemeler[0]["istem"], denemeler[1]["istem"])
    assert "</untrusted_evidence>" in ortak


def _kanit_oneki(a: str, b: str) -> str:
    ortak = []
    for x, y in zip(a, b, strict=False):
        if x != y:
            break
        ortak.append(x)
    return "".join(ortak)


class TestNliHakem:
    """Kanıt penceresine sığmayan replik hakemle kurtulur; sıra korunur."""

    def _raw(self) -> str:
        return _script(
            [
                {"speaker": "emel", "text": "Bugün mitokondriyi konuşuyoruz.", "kind": "question"},
                {
                    # Kanıtta geçmeyen sözcüklerle parafraz: kelime kapısı düşürür.
                    "speaker": "murat",
                    "text": "Bu organel, hücrenin ihtiyaç duyduğu kimyasal yakıtı hazırlar.",
                    "kind": "fact",
                    "citation_labels": ["S1"],
                },
                {
                    "speaker": "mazlum",
                    "text": "Mitokondri hücresel solunum yoluyla ATP üretiminden sorumludur.",
                    "kind": "fact",
                    "citation_labels": ["S1"],
                },
            ]
        )

    def test_hakem_evet_deyince_replik_sirasiyla_geri_gelir(self) -> None:
        def hakem(ciftler):
            return [True] * len(ciftler)

        builder = PodcastScriptBuilder(_builder(self._raw())._chat, hakem=hakem)
        segments, uyarilar, llm = _build(builder)
        metinler = [item["text"] for item in segments]
        assert "kimyasal yakıtı" in metinler[1]
        assert "ATP üretiminden" in metinler[2]
        assert [item["index"] for item in segments] == [0, 1, 2]

    def test_hakem_hayir_deyince_nli_reddetti_sayilir(self) -> None:
        def hakem(ciftler):
            return [False] * len(ciftler)

        builder = PodcastScriptBuilder(_builder(self._raw())._chat, hakem=hakem)
        segments, uyarilar, llm = _build(builder)
        assert all("kimyasal yakıtı" not in item["text"] for item in segments)
        assert any("NLI hakemi doğrulayamadı" in uyari for uyari in uyarilar)

    def test_hakem_yokken_kanit_penceresi_nedeni_degismez(self) -> None:
        builder = _builder(self._raw())
        segments, uyarilar, llm = _build(builder)
        assert any("kanıt penceresine sığmadı" in uyari for uyari in uyarilar)


class TestSureTelafisi:
    """Eleme sonrası süre açığı yalnız açık kadar ek replikle kapatılır."""

    def _uzun_metin(self, n: int = 300) -> str:
        return ("Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir. " * 6)[:n]

    def test_acik_yoksa_telafi_cagrisi_yapilmaz(self) -> None:
        import json as _json

        cagrilar: list[str] = []
        cumleler = [
            "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
            "Hücresel solunum yoluyla ATP üretiminden sorumludur.",
            "Kloroplast yalnızca bitki hücrelerinde bulunur.",
        ]

        async def chat(messages, *, max_tokens=None):
            if "ANAHATINI" in messages[0]["content"]:
                return _json.dumps({"chapters": ["A", "B"]})
            if "EK TUR" in messages[1]["content"]:
                cagrilar.append("telafi")
            else:
                cagrilar.append("bolum")
            return _script(
                [
                    {
                        "speaker": "mazlum",
                        "text": cumle,
                        "kind": "explain",
                        "citation_labels": ["S1"],
                    }
                    for cumle in cumleler
                ]
            )

        from bioprof.studio.podcast import PodcastAyarlari

        # Karakter hızını çok düşük tutunca az replik bile hedefi doldurur.
        ayarlar = PodcastAyarlari(karakter_hizi=0.01)
        asyncio.run(
            PodcastScriptBuilder(chat, ayarlar=ayarlar).build(
                "Konu", _records(), target_minutes=15
            )
        )
        assert "bolum" in cagrilar
        assert "telafi" not in cagrilar

    def test_acik_varsa_ek_tur_atilir_ve_islenmis_hatirlatilir(self) -> None:
        import json as _json

        telafi_istemleri: list[str] = []

        async def chat(messages, *, max_tokens=None):
            if "ANAHATINI" in messages[0]["content"]:
                return _json.dumps({"chapters": ["A", "B"]})
            istem = messages[1]["content"]
            if "EK TUR" in istem:
                telafi_istemleri.append(istem)
                return _script(
                    [
                        {
                            "speaker": "murat",
                            "text": "Kloroplast yalnızca bitki hücrelerinde bulunur.",
                            "kind": "explain",
                            "citation_labels": ["S1"],
                        },
                        {
                            "speaker": "murat",
                            "text": "Hücresel solunum yoluyla ATP üretiminden sorumludur.",
                            "kind": "explain",
                            "citation_labels": ["S1"],
                        },
                    ]
                )
            return _script(
                [
                    {
                        "speaker": "mazlum",
                        "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                        "kind": "explain",
                        "citation_labels": ["S1"],
                    },
                    {"speaker": "emel", "text": "Devam edelim.", "kind": "transition"},
                ]
            )

        segments, _, _ = asyncio.run(
            PodcastScriptBuilder(chat).build("Konu", _records(), target_minutes=15)
        )
        assert telafi_istemleri, "süre açığına rağmen telafi çağrısı yapılmadı"
        # Kabul edilmiş replikler telafi istemine hatırlatma olarak girer.
        assert "ZATEN ANLATILANLAR" in telafi_istemleri[0]
        assert any("Kloroplast" in str(s["text"]) for s in segments)

    def test_telafi_kazanc_sifirsa_donguyu_kirar(self) -> None:
        import json as _json

        sayac = {"telafi": 0}

        async def chat(messages, *, max_tokens=None):
            if "ANAHATINI" in messages[0]["content"]:
                return _json.dumps({"chapters": ["A", "B"]})
            if "EK TUR" in messages[1]["content"]:
                sayac["telafi"] += 1
            # Hep aynı replikler: telafi turu net kazanç sağlayamaz.
            return _script(
                [
                    {
                        "speaker": "mazlum",
                        "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                        "kind": "explain",
                        "citation_labels": ["S1"],
                    },
                    {"speaker": "emel", "text": "Devam edelim.", "kind": "transition"},
                ]
            )

        _, uyarilar, _ = asyncio.run(
            PodcastScriptBuilder(chat).build("Konu", _records(), target_minutes=15)
        )
        assert sayac["telafi"] == 1  # ikinci tur açılmadan kesilmeli
        assert any("kazandıramadı" in u for u in uyarilar)

    def test_numaralar_telafi_sonrasi_ardisik_ve_benzersiz(self) -> None:
        import json as _json

        async def chat(messages, *, max_tokens=None):
            if "ANAHATINI" in messages[0]["content"]:
                return _json.dumps({"chapters": ["A", "B"]})
            if "EK TUR" in messages[1]["content"]:
                return _script(
                    [
                        {
                            "speaker": "murat",
                            "text": "Kloroplast yalnızca bitki hücrelerinde bulunur.",
                            "kind": "explain",
                            "citation_labels": ["S1"],
                        },
                        {
                            "speaker": "murat",
                            "text": "Hücresel solunum yoluyla ATP üretiminden sorumludur.",
                            "kind": "explain",
                            "citation_labels": ["S1"],
                        },
                    ]
                )
            return _script(
                [
                    {
                        "speaker": "mazlum",
                        "text": "Mitokondri ökaryot hücrelerde bulunan çift zarlı bir organeldir.",
                        "kind": "explain",
                        "citation_labels": ["S1"],
                    },
                    {"speaker": "emel", "text": "Şimdi devam edelim.", "kind": "transition"},
                ]
            )

        segments, _, _ = asyncio.run(
            PodcastScriptBuilder(chat).build("Konu", _records(), target_minutes=15)
        )
        indeksler = [s["index"] for s in segments]
        assert indeksler == list(range(len(segments)))

    def test_tahmini_sure_karakterle_olceklenir(self) -> None:
        from bioprof.studio.podcast import tahmini_sure

        kisa = [{"text": "Kısa soru?"}]
        uzun = [{"text": "x" * 700}]
        assert tahmini_sure(uzun) > tahmini_sure(kisa) * 5
        assert tahmini_sure([]) == 0.0
