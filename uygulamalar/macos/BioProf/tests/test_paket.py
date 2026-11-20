"""Öğrenci paketi: zip içeriği, MANIFEST, aidiyet ve yol kapısı."""

from __future__ import annotations

import asyncio
import zipfile
from pathlib import Path

import pytest

from bioprof.api.native import NativeAPIError
from bioprof.application import BioProfApplication
from bioprof.services.paket import paket_olustur
from bioprof.services.repositories import Repository


def _artifact_kaydi(app: BioProfApplication, notebook_id: str, icerik: bytes = b"veri"):
    dosya = app.settings.artifacts_dir / notebook_id / "cikti.md"
    dosya.parent.mkdir(parents=True, exist_ok=True)
    dosya.write_bytes(icerik)
    with app.database.session() as session:
        return Repository(session).create_artifact(
            notebook_id, "summary", "Özet", str(dosya), "text/markdown"
        )


def test_zip_manifest_ve_dosyalari_icerir(app: BioProfApplication, tmp_path: Path) -> None:
    yan = app.settings.artifacts_dir / "podcast.srt"
    yan.write_text("1\n00:00:00,000 --> 00:00:01,000\nMerhaba\n")
    artifacts = [
        {
            "title": "Podcast Bölümü",
            "kind": "podcast",
            "created_at": "2026-08-07T10:00:00",
            "metadata": {"files": [str(yan)]},
        }
    ]
    zip_yolu = paket_olustur(
        artifacts, artifacts_dir=app.settings.artifacts_dir, hedef_dizin=tmp_path
    )
    with zipfile.ZipFile(zip_yolu) as arsiv:
        adlar = arsiv.namelist()
        assert "MANIFEST.md" in adlar
        assert any(ad.endswith("podcast.srt") for ad in adlar)
        manifest = arsiv.read("MANIFEST.md").decode("utf-8")
        assert "Podcast Bölümü" in manifest and "1 dosya" in manifest


def test_kok_disina_isaret_eden_yol_pakete_giremez(
    app: BioProfApplication, tmp_path: Path
) -> None:
    disarida = tmp_path / "gizli.txt"
    disarida.write_text("sızmamalı")
    artifacts = [
        {
            "title": "Kötü", "kind": "summary", "created_at": "",
            "metadata": {"files": [str(disarida), "../../../etc/hosts"]},
        }
    ]
    zip_yolu = paket_olustur(
        artifacts, artifacts_dir=app.settings.artifacts_dir, hedef_dizin=tmp_path
    )
    with zipfile.ZipFile(zip_yolu) as arsiv:
        assert arsiv.namelist() == ["MANIFEST.md"]
        assert "0 dosya" in arsiv.read("MANIFEST.md").decode("utf-8")


def test_uc_yabanci_notebook_artifacti_reddeder(app: BioProfApplication) -> None:
    with app.database.session() as session:
        repo = Repository(session)
        birinci = repo.create_notebook("Bir").id
        ikinci = repo.create_notebook("İki").id
    kayit = _artifact_kaydi(app, ikinci)
    with pytest.raises(NativeAPIError):
        asyncio.run(
            app._export_paket({"notebook_id": birinci, "artifact_ids": [kayit.id]})
        )


def test_uc_zip_uretir_ve_sayar(app: BioProfApplication) -> None:
    with app.database.session() as session:
        notebook = Repository(session).create_notebook("Paketli").id
    kayit = _artifact_kaydi(app, notebook)
    sonuc = asyncio.run(
        app._export_paket({"notebook_id": notebook, "artifact_ids": [kayit.id]})
    )
    assert sonuc["count"] == 1
    with zipfile.ZipFile(sonuc["path"]) as arsiv:
        assert any(ad.endswith("cikti.md") for ad in arsiv.namelist())


def test_bos_secim_422(app: BioProfApplication) -> None:
    with app.database.session() as session:
        notebook = Repository(session).create_notebook("Boş").id
    with pytest.raises(NativeAPIError):
        asyncio.run(app._export_paket({"notebook_id": notebook, "artifact_ids": []}))
