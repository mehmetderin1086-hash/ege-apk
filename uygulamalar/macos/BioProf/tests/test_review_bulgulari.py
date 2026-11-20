"""Çapraz incelemede bulunan hataların regresyon testleri.

Her test, düzeltmeden önce gerçekten başarısız olan somut bir senaryodur.
"""

from __future__ import annotations

import asyncio

import pytest

from bioprof.api.native import NativeAPIError
from bioprof.application import _visible_delta
from bioprof.rag.answering import _claim_supported, _recover_label
from bioprof.services.repositories import Repository
from bioprof.studio.llm_writer import StudioLLMWriter
from bioprof.studio.podcast import PodcastScriptBuilder
from tests.conftest import FakeRetriever, fake_evidence


def test_baska_notebookun_gecmisi_isteme_giremez(app) -> None:
    # Notebook A'nın isteğine B'nin conversation_id'si verilirse, B'nin
    # mesajları modele gitmeden reddedilmeli.
    with app.database.session() as session:
        repository = Repository(session)
        a = repository.create_notebook("A").id
        b = repository.create_notebook("B").id
        sohbet_b = repository.create_conversation(b, "B sohbeti").id
        repository.add_message(sohbet_b, "user", "B'nin gizli sorusu")

    with pytest.raises(NativeAPIError) as hata:
        app._recent_history(a, sohbet_b)
    assert hata.value.status_code == 409

    with pytest.raises(NativeAPIError):
        asyncio.run(app._ask(a, {"question": "Soru?", "conversation_id": sohbet_b}))


def test_kendi_sohbetinin_gecmisi_okunur(app) -> None:
    with app.database.session() as session:
        repository = Repository(session)
        notebook = repository.create_notebook("A").id
        sohbet = repository.create_conversation(notebook, "başlık").id
        repository.add_message(sohbet, "user", "Mitokondri nedir?")
    assert app._recent_history(notebook, sohbet) == [("user", "Mitokondri nedir?")]


def test_bagimsiz_olumsuzluk_ters_polariteyi_engeller() -> None:
    # "değildir" bir fiil eki değil ayrı sözcük; hangi kavramı olumsuzladığı
    # gövdesinden okunamaz, bu yüzden kavram eşlemesi onu göremiyordu.
    assert not _claim_supported(
        "Mitokondri hücrenin enerji santralidir.",
        "Mitokondri hücrenin enerji santrali değildir ve ATP üretiminde rol alır.",
    )
    assert _claim_supported(
        "Mitokondri hücrenin enerji santralidir.",
        "Mitokondri hücrenin enerji santralidir ve ATP üretiminde rol alır.",
    )
    assert _claim_supported(
        "Elektron taşıma zinciri doğrudan ATP üretmez.",
        "Elektron taşıma zinciri doğrudan ATP üretmez; enerjiyi basamaklara böler.",
    )


def test_kurtarma_ayri_cumlelerden_toplanan_iddiayi_reddeder() -> None:
    # Etiketi biz taktığımız için ölçüt dar: iddia tek bir kanıt cümlesinden
    # gelmeli. Blok geneline bakmak bu yanlış cümleyi kanıtlı gösteriyordu.
    kanit = [
        fake_evidence(
            "S1", "İnsülin glukoz düzeyini düşürür. Glukagon glukoz düzeyini artırır."
        )
    ]
    assert _recover_label("İnsülin glukoz düzeyini artırır.", kanit) is None
    assert _recover_label("İnsülin glukoz düzeyini düşürür.", kanit) == "S1"


def test_soru_kiligindaki_olgu_dogrulanmadan_gecemez() -> None:
    import json

    raw = json.dumps(
        {
            "segments": [
                {
                    "speaker": "emel",
                    "text": "İnsülin kan şekerini artırır, değil mi Murat?",
                    "kind": "question",
                },
                {
                    "speaker": "murat",
                    "text": "Mitokondri, hücrenin enerji santrali olarak görev yapar.",
                    "kind": "fact",
                    "citation_labels": ["S1"],
                },
            ]
        },
        ensure_ascii=False,
    )

    async def chat(messages, *, max_tokens=None):
        return raw

    kayitlar = [
        type(fake_evidence())  # tip ipucu için; gerçek kayıtlar aşağıda
    ]
    del kayitlar
    from bioprof.studio.artifacts import StudioEvidence

    records = [
        StudioEvidence(
            label="S1",
            text="Mitokondri, hücrenin enerji santrali olarak görev yapar.",
            source_title="Hücre",
            citation_id="cit-1",
        )
    ]
    segments, _, _ = asyncio.run(PodcastScriptBuilder(chat).build("Konu", records))
    assert all("kan şekerini artırır" not in item["text"] for item in segments)


def test_olgusal_baslik_kanita_karsi_sinanir() -> None:
    from bioprof.studio.artifacts import StudioEvidence

    records = [
        StudioEvidence(
            label="S1",
            text="Mitokondri, hücrenin enerji santrali olarak görev yapar.",
            source_title="Hücre",
            citation_id="cit-1",
        )
    ]

    async def chat(messages, *, max_tokens=None):
        return (
            "# Özet\n\n"
            "## İnsülin kan şekerini yükselterek dokulara enerji sağlar\n\n"
            "- Mitokondri, hücrenin enerji santrali olarak görev yapar [S1]."
        )

    metin, _ = asyncio.run(
        StudioLLMWriter(chat).rewrite("summary", "# Özet\n\n- taslak [S1].", records)
    )
    assert "İnsülin kan şekerini yükselterek" not in metin
    assert "# Özet" in metin


def test_kisa_bolum_basligi_korunur() -> None:
    from bioprof.studio.artifacts import StudioEvidence

    records = [
        StudioEvidence(
            label="S1",
            text="Mitokondri, hücrenin enerji santrali olarak görev yapar.",
            source_title="Hücre",
            citation_id="cit-1",
        )
    ]

    async def chat(messages, *, max_tokens=None):
        return (
            "# Özet\n\n## Genel bakış\n\n"
            "- Mitokondri, hücrenin enerji santrali olarak görev yapar [S1]."
        )

    metin, _ = asyncio.run(
        StudioLLMWriter(chat).rewrite("summary", "# Özet\n\n- taslak [S1].", records)
    )
    assert "## Genel bakış" in metin


def test_akista_dusunme_metni_sizmaz() -> None:
    # Sunucu <think> içeriğini content olarak akıtırsa taslakta görünmemeli.
    parcalar = ["<think>uzun", " düşünce</think>Görü", "nen yanıt."]
    gorunen = []
    thinking = False
    for parca in parcalar:
        text, thinking = _visible_delta(parca, thinking)
        gorunen.append(text)
    assert "".join(gorunen) == "Görünen yanıt."
    assert thinking is False


def test_akista_kapanmamis_dusunme_hicbir_sey_gostermez() -> None:
    text, thinking = _visible_delta("<think>hâlâ düşünüyorum", False)
    assert text == ""
    assert thinking is True


def test_podcast_llm_kapaliysa_sohbet_kesilmez(app) -> None:
    # Podcast işi TTS öncesi modeli kapatır; süren bir sohbet varsa dokunmamalı.
    app._retriever = lambda session: FakeRetriever([fake_evidence()])
    kapatildi = {"n": 0}

    async def sahte_unload():
        kapatildi["n"] += 1

    app._unload_local_model = sahte_unload
    app._llm_inflight = 1
    asyncio.run(app._release_llm_for_audio())
    assert kapatildi["n"] == 0

    app._llm_inflight = 0
    asyncio.run(app._release_llm_for_audio())
    assert kapatildi["n"] == 1


def test_podcast_ikinci_denemesi_coker_degil_iskelete_duser() -> None:
    """build_chat tek kullanımlık bağlam yöneticisi alırsa ikinci deneme çökerdi."""
    from contextlib import asynccontextmanager

    from bioprof.studio.artifacts import StudioEvidence
    from bioprof.studio.llm_writer import build_chat

    @asynccontextmanager
    async def guard():
        yield None

    class SahteSaglayici:
        def __init__(self) -> None:
            self.calls = 0

        async def chat(self, payload):
            self.calls += 1
            return type("R", (), {"text": "bu JSON değil"})()

    provider = SahteSaglayici()
    chat = build_chat(provider, "model", guard)
    records = [
        StudioEvidence(
            label="S1",
            text="Mitokondri, hücrenin enerji santrali olarak görev yapar.",
            source_title="Hücre",
            citation_id="cit-1",
        )
    ]
    segments, uyarilar, llm = asyncio.run(PodcastScriptBuilder(chat).build("Konu", records))
    # İki deneme de gerçekten sağlayıcıya ulaşmalı, sonra kalıp senaryoya inilmeli.
    assert provider.calls == 2
    assert llm is False
    assert segments


def test_kurtarma_tek_kelimelik_yanlisi_reddeder() -> None:
    # %85 eşiği ayırt edici tek terimin uydurma olmasına izin veriyordu;
    # etiketi biz taktığımız için kurtarmada tam kapsama isteniyor.
    kanit = [
        fake_evidence(
            "S1",
            "Mitokondri hücrede ATP üretiminin gerçekleştiği organeldir ve "
            "kendi DNA'sını taşır.",
        )
    ]
    assert (
        _recover_label(
            "Bu organel kendi DNA'sını taşır ve fotosentez gerçekleştirir.", kanit
        )
        is None
    )
    assert _recover_label("Mitokondri kendi DNA'sını taşır.", kanit) == "S1"


def test_studio_yazari_notebook_onayi_olmadan_uzaga_gitmez(app) -> None:
    # /ask uzak sağlayıcıda notebook onayı arıyordu; Stüdyo yolu aramıyordu.
    class UzakSaglayici:
        name = "uzak"
        requires_egress = True

        async def chat(self, payload):
            raise AssertionError("Onaysız notebook'ta uzak sağlayıcı çağrılmamalı")

    app.providers.policy.allow_remote_egress = True
    app.providers.register(UzakSaglayici())
    app.settings.default_provider = "uzak"
    with app.database.session() as session:
        notebook = Repository(session).create_notebook("Yerel", remote_egress_approved=False)
        session.expunge(notebook)
    assert asyncio.run(app.studio_writer(notebook)) is None


def test_kanit_limiti_istek_basina_ayarlanir(app) -> None:
    from bioprof.api.native import StudioRequest

    cagrilar: list[int | None] = []

    class KayitliRetriever:
        def search(self, *args, limit=None, **kwargs):
            cagrilar.append(limit)
            return [fake_evidence()]

    # Stüdyo işi artık StudioService'te; retriever fabrikası da orada değişmeli.
    app.studio_service._retriever = lambda session: KayitliRetriever()
    with app.database.session() as session:
        notebook = Repository(session).create_notebook("Kanıt").id

    ortak = {"notebook_id": notebook, "kind": "summary", "title": "Başlık"}
    asyncio.run(app.studio_service.job("job-1", dict(ortak)))
    asyncio.run(app.studio_service.job("job-2", {**ortak, "max_evidence": 16}))
    assert cagrilar == [app.settings.max_evidence, 16]

    # Sınır dışı değer istek şemasında reddedilir.
    with pytest.raises(ValueError):
        StudioRequest(notebook_id="n", kind="podcast", title="t", max_evidence=0)
    with pytest.raises(ValueError):
        StudioRequest(notebook_id="n", kind="podcast", title="t", max_evidence=51)
