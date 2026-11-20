"""Sessizce yanlış davranan yapılandırma yollarının sınırları.

Bu üç sınıfın ortak noktası: hepsi yanlış çalışırken hiçbir yerde işaret
vermiyordu — tek belirti cevapların kötüleşmesiydi.
"""

from __future__ import annotations

from bioprof.config import Settings
from bioprof.rag.dense import DeterministicDenseBackend, HashingEmbedder, build_embedder
from bioprof.rag.retrieval import HybridRetriever


class _SahteEmbedder:
    model_name = "sahte-model"
    dimension = 8

    def embed(self, texts):
        return [[0.0] * self.dimension for _ in texts]


class TestGommeDusmesi:
    def test_qdrant_yokken_yapilandirilmis_embedder_korunur(self):
        """Geri dönüş yolu hashing vekiline DÜŞMEMELİ.

        `DeterministicDenseBackend(session)` embedder'sız kurulunca BGE-M3
        ile çalışan bir kurulum sessizce 384 boyutlu vekile iniyordu.
        """
        embedder = _SahteEmbedder()
        retriever = HybridRetriever(
            Settings(), session=None, dense_backend=None, embedder=embedder
        )
        assert isinstance(retriever.dense_backend, DeterministicDenseBackend)
        assert retriever.dense_backend.embedder is embedder

    def test_embedder_verilmezse_ayarlardan_kurulur(self):
        retriever = HybridRetriever(
            Settings(local_embeddings=False), session=None, dense_backend=None
        )
        assert isinstance(retriever.dense_backend.embedder, HashingEmbedder)

    def test_yerel_gomme_kapaliysa_hashing_beklenir(self):
        assert isinstance(build_embedder(Settings(local_embeddings=False)), HashingEmbedder)


class TestSeslabPortu:
    def test_varsayilan_pdf_studio_portuna_gitmez(self):
        """8000'i bu makinede PDF Studio dinliyor; SesLab 8010'a taşındı."""
        assert Settings().seslab_base_url.endswith(":8010")


class TestRerankerErisimi:
    def test_ayar_var_ve_varsayilan_kapali(self):
        # Adaptör sınıfı vardı ama onu açan hiçbir yol yoktu.
        ayarlar = Settings()
        assert ayarlar.local_reranker is False
        assert ayarlar.reranker_model

    def test_acilinca_retriever_reranker_alir(self):
        from bioprof.rag.retrieval import CrossEncoderReranker

        reranker = CrossEncoderReranker("test-model")
        retriever = HybridRetriever(
            Settings(), session=None, dense_backend=object(), reranker=reranker
        )
        assert retriever.reranker is reranker
