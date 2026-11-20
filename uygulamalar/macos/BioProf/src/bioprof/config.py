from __future__ import annotations

import ipaddress
from functools import lru_cache
from pathlib import Path
from urllib.parse import urlparse

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError


def default_data_dir() -> Path:
    return Path.home() / "Library" / "Application Support" / "BioProf"


def default_model_cache_dir() -> Path:
    return Path.home() / "Library" / "Caches" / "BioProf" / "models"


def _loopback_url(value: str) -> bool:
    hostname = (urlparse(value).hostname or "").strip("[]").casefold()
    if hostname == "localhost":
        return True
    try:
        return ipaddress.ip_address(hostname).is_loopback
    except ValueError:
        return False


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="BIOPROF_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "BioProf"
    host: str = "127.0.0.1"
    port: int = 8766
    data_dir: Path = Field(default_factory=default_data_dir)
    model_cache_dir: Path = Field(default_factory=default_model_cache_dir)
    database_url: str | None = None
    log_level: str = "INFO"
    privacy_mode: str = "local_first"
    allow_raw_mode: bool = False
    allow_remote_egress: bool = False
    allow_openai_compat_remote: bool = False

    # 8000 is PDF Studio on this machine; SesLab was moved to 8010 to end
    # the clash. A stale default here sent voice traffic to the wrong
    # service whenever the runtime .env was missing.
    seslab_base_url: str = "http://127.0.0.1:8010"
    cliproxy_base_url: str = "http://127.0.0.1:8317"
    cliproxy_key_name: str = "BioProf CLI Proxy API Key"
    generic_openai_base_url: str | None = None
    generic_openai_api_key: str | None = None
    default_provider: str = "local_evidence"
    default_model: str = "bioprof-evidence"
    # Yerel LLM: BioProf venv'inde mlx yoksa mlx sunucusu bu yorumlayıcıyla
    # başlatılır (biyo-cozucu venv'i). Yol yoksa local_model sadece kapalı görünür.
    local_llm_python: Path = Field(
        default_factory=lambda: (
            Path.home() / "Developer" / "biyo-cozucu" / ".venv" / "bin" / "python"
        )
    )
    local_llm_default_profile: str = "sohbet"
    # 0 = idle kapanışı yok. Süre dolunca model süreci öldürülüp bellek iade edilir.
    local_llm_idle_timeout: float = 600.0
    local_embeddings: bool = False
    embedding_model: str = "BAAI/bge-m3"

    chunk_target_chars: int = 2400
    chunk_overlap_chars: int = 240
    retrieval_candidates: int = 50
    rerank_candidates: int = 30
    # The CrossEncoderReranker adapter existed but nothing could reach it:
    # the retriever accepted a reranker argument that was never supplied and
    # no setting turned it on. Off by default (it loads a model), but now
    # reachable via BIOPROF_LOCAL_RERANKER=true.
    local_reranker: bool = False
    reranker_model: str = "BAAI/bge-reranker-v2-m3"
    max_evidence: int = 10
    minimum_dense_score: float = 0.12
    # Kademeli NLI hakemi: kelime-eşleşme kapısını geçemeyen iddialar küçük
    # bir çok dilli entailment modeliyle yeniden yargılanır.
    # Eşik altın setle ölçüldü (bioprof nli-esik, 2026-08-07, 48 çift): 0.95,
    # kötü kategorilerde (polarite/sayı/terim karışımı) 0 yanlış kabul verip
    # 16/16 doğru parafrazı kurtaran en düşük eşik. Eşik değiştirilecekse
    # ölçüm yeniden koşulmalı.
    nli_enabled: bool = True
    nli_model: str = "MoritzLaurer/mDeBERTa-v3-base-mnli-xnli"
    nli_esik: float = Field(default=0.95, ge=0.5, le=0.99)
    # Çelişki ayrı kapı: entailment yüksek olsa bile çelişki bunu aşarsa ret.
    nli_karsi_esik: float = Field(default=0.35, ge=0.01, le=0.9)
    # Tek yanıt/bölüm başına yargılanacak azami çift; fazlası yargısız reddedilir.
    nli_azami_cift: int = Field(default=64, ge=1, le=512)
    # Podcast üretim ayarları; varsayılanlar studio/podcast.py'daki ölçülmüş
    # sabitlerle aynıdır, deneme için kod düzenlemek gerekmesin diye buradalar.
    podcast_saniye_basina_replik: float = Field(default=7.5, gt=0)
    podcast_bolum_basina_replik: int = Field(default=18, ge=4, le=60)
    podcast_bolum_kanit_siniri: int = Field(default=8, ge=1, le=64)
    podcast_karakter_hizi: float = Field(default=14.0, gt=0)
    podcast_telafi_turu: int = Field(default=2, ge=0, le=5)
    # Gözlemlenen üretim/süre oranı (~30 dk podcast ≈ 40 dk üretim): arayüzdeki
    # süre tahmini bu katsayıyla hesaplanır.
    podcast_uretim_katsayisi: float = Field(default=1.35, gt=0)
    use_qdrant: bool = True
    heavy_concurrency: int = 1
    max_upload_mb: int = 250
    max_audio_upload_mb: int = 100
    max_json_request_mb: int = Field(default=8, ge=1, le=1024)
    training_import_roots: str = ""

    @field_validator("database_url")
    @classmethod
    def database_must_be_sqlite(cls, value: str | None) -> str | None:
        if value is None:
            return None
        try:
            url = make_url(value)
        except ArgumentError as exc:
            raise ValueError("Geçerli bir SQLAlchemy veritabanı URL'si gerekli") from exc
        if url.get_backend_name() != "sqlite":
            raise ValueError("BioProf yalnız SQLite veritabanlarını destekler")
        return value

    @field_validator("seslab_base_url", "cliproxy_base_url")
    @classmethod
    def local_service_urls_are_loopback(cls, value: str) -> str:
        if not _loopback_url(value):
            raise ValueError("SesLab ve CLI Proxy yalnız loopback URL kullanabilir")
        return value.rstrip("/")

    @property
    def db_url(self) -> str:
        if self.database_url:
            return self.database_url
        return f"sqlite:///{self.data_dir / 'bioprof.sqlite3'}"

    @property
    def objects_dir(self) -> Path:
        return self.data_dir / "objects"

    @property
    def artifacts_dir(self) -> Path:
        return self.data_dir / "artifacts"

    @property
    def vector_dir(self) -> Path:
        return self.data_dir / "qdrant"

    @property
    def quarantine_dir(self) -> Path:
        return self.data_dir / "quarantine"

    def ensure_directories(self) -> None:
        for path in (
            self.data_dir,
            self.objects_dir,
            self.artifacts_dir,
            self.vector_dir,
            self.quarantine_dir,
            self.model_cache_dir,
        ):
            path.mkdir(parents=True, exist_ok=True)
            path.chmod(0o700)


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.ensure_directories()
    return settings
