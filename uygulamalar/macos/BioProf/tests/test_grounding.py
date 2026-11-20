"""Kanıta bağlılık sınırları — BioProf'un asıl değer önerisi burada.

Özgün test paketi iCloud tahliyesinde kayboldu (bkz. README yanındaki git
geçmişi). Bu dosya kaybolan kapsamın tamamını geri getirmiyor; grounding
katmanının yanlış bir ifadeyi geçirebileceği yolları kapatıyor.
"""

from __future__ import annotations

import pytest

from bioprof.rag.answering import (
    _claim_supported,
    _normalized_span,
    _olumsuz_mu,
    cited_labels,
)

KANIT = (
    "Bitkilerde fotosentez kloroplast organelinde gerçekleşir ve "
    "karbondioksit ile sudan glukoz üretir."
)


class TestBirebirVeParafraz:
    def test_birebir_alinti_kabul_edilir(self):
        assert _claim_supported(
            "fotosentez kloroplast organelinde gerçekleşir", KANIT
        )

    def test_ek_farkiyla_parafraz_kabul_edilir(self):
        # Türkçe eklemeli: "üretir" ve "üretilir" aynı olguyu söyler.
        assert _claim_supported(
            "Kloroplast organelinde fotosentez gerçekleşir, glukoz üretilir.",
            KANIT,
        )

    def test_sozcuk_sirasi_degisimi_kabul_edilir(self):
        assert _claim_supported(
            "Glukoz üretimi kloroplast organelinde fotosentez ile gerçekleşir",
            KANIT,
        )


class TestOlumsuzlukSizmasi:
    """Geçerli bir kaynak etiketiyle ters ifade aklanamamalı."""

    def test_ek_ile_olumsuzlanan_iddia_reddedilir(self):
        assert not _claim_supported(
            "Fotosentez kloroplast organelinde gerçekleşmez", KANIT
        )

    def test_sozcukle_olumsuzlanan_iddia_reddedilir(self):
        assert not _claim_supported(
            "Fotosentez kloroplast organelinde gerçekleşir değildir glukoz",
            KANIT,
        )

    def test_kaynak_olumsuzken_olumlu_iddia_reddedilir(self):
        olumsuz_kanit = (
            "Fotosentez kloroplast organelinde gerçekleşmez ve glukoz üretmez."
        )
        assert not _claim_supported(
            "Fotosentez kloroplast organelinde gerçekleşir ve glukoz üretir",
            olumsuz_kanit,
        )

    @pytest.mark.parametrize(
        "sozcuk",
        ["gerçekleşmez", "üretmiyor", "oluşmamış", "gelişmeyecek", "değildir"],
    )
    def test_olumsuzluk_bicimleri_taninir(self, sozcuk):
        assert _olumsuz_mu(sozcuk)

    @pytest.mark.parametrize("sozcuk", ["temmuz", "gerçekleşir", "üretim", "hücre"])
    def test_olumlu_sozcukler_olumsuz_sayilmaz(self, sozcuk):
        assert not _olumsuz_mu(sozcuk)


class TestSayiSizmasi:
    def test_kaynakta_olmayan_sayi_reddedilir(self):
        kanit = "İnsan somatik hücresi 23 kromozom çifti içerir yapısında."
        assert not _claim_supported(
            "İnsan somatik hücresi 46 kromozom çifti içerir yapısında", kanit
        )

    def test_kaynaktaki_sayi_kabul_edilir(self):
        kanit = "İnsan somatik hücresi 23 kromozom çifti içerir yapısında."
        assert _claim_supported(
            "İnsan somatik hücresinde 23 kromozom çifti bulunur içerir yapısında",
            kanit,
        )


class TestSinirDurumlar:
    def test_alakasiz_iddia_reddedilir(self):
        assert not _claim_supported("Mitokondri ATP üretir hücrede", KANIT)

    def test_cok_kisa_iddia_reddedilir(self):
        # İki içerik sözcüğü tesadüfen de eşleşebilir; yargı için yetersiz.
        assert not _claim_supported("fotosentez gerçekleşir", KANIT)

    def test_bos_girdi_reddedilir(self):
        assert not _claim_supported("", KANIT)
        assert not _claim_supported("fotosentez kloroplast gerçekleşir", "")

    def test_dagilmis_sozcukler_tek_pencerede_degilse_reddedilir(self):
        dagitilmis = (
            "Fotosentez önemli bir olaydır. " + "Ara cümle. " * 30
            + "Kloroplast bir organeldir. " + "Başka cümle. " * 30
            + "Glukoz bir şekerdir."
        )
        assert not _claim_supported(
            "Fotosentez kloroplast organelinde glukoz üretir", dagitilmis
        )


class TestYardimcilar:
    def test_normalize_noktalama_ve_buyuk_harf_ayirmaz(self):
        assert _normalized_span("Fotosentez, KLOROPLASTTA!") == (
            "fotosentez kloroplastta"
        )

    def test_atif_etiketleri_cikarilir(self):
        assert cited_labels("Bir ifade [S1] ve başkası [s2] [S1]") == ["S1", "S2"]


class TestUretilenMetinYolu:
    """`build()` gerçek bir sağlayıcının ürettiği düzyazıyla ne yapıyor?

    Yerel `local_evidence` sağlayıcısı bilinçli olarak alıntı döndürür, yani
    bu yol yalnız gerçek bir LLM bağlıyken çalışır. Eski kural (yalnız birebir
    aralık) hiçbir üretilmiş cümleyi kabul edemediği için strict mod her
    seferinde alıntı dökümüne düşüyordu — sağlayıcı fiilen devre dışıydı.
    """

    def _kanit(self):
        from bioprof.domain.models import CitationAnchor, Evidence

        return [
            Evidence(
                label="S1",
                text=KANIT,
                score=0.9,
                anchor=CitationAnchor(
                    id="a1",
                    source_id="s1",
                    source_sha256="0" * 64,
                    chunk_id="c1",
                    quote=KANIT,
                    source_title="Campbell Biyoloji",
                ),
            )
        ]

    def _kur(self):
        from bioprof.rag.answering import StrictEvidenceAnswerBuilder

        return StrictEvidenceAnswerBuilder()

    def test_parafrazli_uretim_kabul_edilir(self):
        zarf = self._kur().build(
            "Fotosentez nerede olur?",
            self._kanit(),
            provider="test",
            model="test",
            # Atıf cümlenin İÇİNDE: cümle bölücü noktadan sonrasını ayrı
            # parça sayar, etiket dışarıda kalırsa iddia kaynaksız görünür.
            generated_text=(
                "Kloroplast organelinde fotosentez gerçekleşir ve glukoz "
                "üretilir [S1]."
            ),
        )
        assert zarf.evidence_status == "supported"
        assert zarf.claims and zarf.claims[0].supported
        assert "kanıtlar:" not in zarf.answer_markdown

    def test_ters_cevrilmis_uretim_alintiya_duser(self):
        zarf = self._kur().build(
            "Fotosentez nerede olur?",
            self._kanit(),
            provider="test",
            model="test",
            generated_text="Fotosentez kloroplast organelinde gerçekleşmez [S1].",
        )
        # Desteklenmeyen tek iddia kalınca üretim tümden reddedilir.
        assert "kanıtlar:" in zarf.answer_markdown


class TestKademeliHakem:
    """NLI hakemi: kelime-eşleşmeyi geçemeyeni toplu yargılar, geçeni görmez."""

    def _kanit(self):
        from bioprof.domain.models import CitationAnchor, Evidence

        return [
            Evidence(
                label="S1",
                text=KANIT,
                score=0.9,
                anchor=CitationAnchor(
                    id="a1",
                    source_id="s1",
                    source_sha256="0" * 64,
                    chunk_id="c1",
                    quote=KANIT,
                    source_title="Campbell Biyoloji",
                ),
            )
        ]

    def _kur(self, hakem):
        from bioprof.rag.answering import StrictEvidenceAnswerBuilder

        return StrictEvidenceAnswerBuilder(hakem=hakem)

    def test_kelime_eslesmesi_gecince_hakem_hic_cagrilmaz(self):
        cagrildi = []

        def hakem(ciftler):
            cagrildi.append(len(ciftler))
            return [True] * len(ciftler)

        zarf = self._kur(hakem).build(
            "Fotosentez nerede olur?",
            self._kanit(),
            provider="test",
            model="test",
            generated_text=(
                "Kloroplast organelinde fotosentez gerçekleşir ve glukoz "
                "üretilir [S1]."
            ),
        )
        assert zarf.evidence_status == "supported"
        assert cagrildi == []

    def test_hakem_evet_deyince_dusen_cumle_kurtulur(self):
        # Kanıtta hiç geçmeyen sözcüklerle kurulmuş bir parafraz: kelime
        # kapısı bunu KESİN düşürür, kurtarma yalnız hakemden gelebilir.
        cumle = "Yapraktaki yeşil organeller besin yapımından sorumludur [S1]."

        def hakem(ciftler):
            return [True] * len(ciftler)

        zarf = self._kur(hakem).build(
            "Fotosentez nerede olur?",
            self._kanit(),
            provider="test",
            model="test",
            generated_text=cumle,
        )
        assert zarf.evidence_status == "supported"
        assert "yeşil organeller" in zarf.answer_markdown

    def test_hakem_hayir_deyince_eski_davranis(self):
        def hakem(ciftler):
            return [False] * len(ciftler)

        zarf = self._kur(hakem).build(
            "Fotosentez nerede olur?",
            self._kanit(),
            provider="test",
            model="test",
            generated_text="Fotosentez kloroplast organelinde gerçekleşmez [S1].",
        )
        assert "kanıtlar:" in zarf.answer_markdown

    def test_hakem_yokken_davranis_birebir_ayni(self):
        zarf = self._kur(None).build(
            "Fotosentez nerede olur?",
            self._kanit(),
            provider="test",
            model="test",
            generated_text="Yapraktaki yeşil organeller besin yapımından sorumludur [S1].",
        )
        assert "kanıtlar:" in zarf.answer_markdown

    def test_etiketsiz_cumle_hakemle_atif_kazanir(self):
        # Etiketi biz taktığımız için eşik kaydırması istenmiş olmalı.
        kaydirmalar = []

        def hakem(ciftler):
            kaydirmalar.extend(cift.esik_kaydirma for cift in ciftler)
            return [True] * len(ciftler)

        zarf = self._kur(hakem).build(
            "Fotosentez nerede olur?",
            self._kanit(),
            provider="test",
            model="test",
            generated_text="Yapraktaki yeşil organeller besin yapımından sorumludur.",
        )
        assert zarf.evidence_status == "supported"
        assert "[S1]" in zarf.answer_markdown
        assert kaydirmalar and all(k > 0 for k in kaydirmalar)

    def test_uydurma_etiket_hakeme_goturulmez(self):
        cagrildi = []

        def hakem(ciftler):
            cagrildi.append(len(ciftler))
            return [True] * len(ciftler)

        zarf = self._kur(hakem).build(
            "Fotosentez nerede olur?",
            self._kanit(),
            provider="test",
            model="test",
            generated_text="Fotosentez güneşte gerçekleşir [S9].",
        )
        # Uydurma etiket güven ihlali: hakem kurtaramaz.
        assert cagrildi == []
        assert "kanıtlar:" in zarf.answer_markdown


def test_hakem_cokerse_yanit_500e_donusmez():
    """Hakem istisnası hakem yokmuş gibi davranmaya düşmeli (reranker deseni)."""
    from bioprof.domain.models import CitationAnchor, Evidence
    from bioprof.rag.answering import StrictEvidenceAnswerBuilder

    def bozuk_hakem(ciftler):
        raise OSError("model dosyası yok")

    kanit = [
        Evidence(
            label="S1",
            text=KANIT,
            score=0.9,
            anchor=CitationAnchor(
                id="a1",
                source_id="s1",
                source_sha256="0" * 64,
                chunk_id="c1",
                quote=KANIT,
                source_title="Campbell",
            ),
        )
    ]
    zarf = StrictEvidenceAnswerBuilder(hakem=bozuk_hakem).build(
        "Fotosentez nerede olur?",
        kanit,
        provider="test",
        model="test",
        generated_text="Yapraktaki yeşil organeller besin yapımından sorumludur [S1].",
    )
    # İstisna yükselmedi; kelime kapısının reddi (alıntı dökümü) geçerli.
    assert "kanıtlar:" in zarf.answer_markdown
