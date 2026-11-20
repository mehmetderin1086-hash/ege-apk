"""Güvenlik işlemleri: şifreleme, şifre kaldırma, imza, düzleştirme."""
from __future__ import annotations

import io
from pathlib import Path

import fitz
import pikepdf

from .common import PdfError


def protect(
    path: Path, user_password: str, owner_password: str | None = None,
    *, allow_print: bool = True, allow_copy: bool = True,
    allow_modify: bool = False, current_password: str | None = None,
) -> bytes:
    """Belgeyi parola ile şifreler ve izinleri ayarlar (AES-256)."""
    if not user_password:
        raise PdfError("Bir açılış parolası girmelisiniz.")
    owner = owner_password or user_password
    try:
        kwargs = {}
        if current_password:
            kwargs["password"] = current_password
        with pikepdf.open(str(path), **kwargs) as pdf:
            perms = pikepdf.Permissions(
                extract=allow_copy,
                modify_annotation=allow_modify,
                modify_assembly=allow_modify,
                modify_form=allow_modify,
                modify_other=allow_modify,
                print_lowres=allow_print,
                print_highres=allow_print,
            )
            enc = pikepdf.Encryption(
                user=user_password, owner=owner, R=6, allow=perms,
            )
            buf = io.BytesIO()
            pdf.save(buf, encryption=enc)
            return buf.getvalue()
    except pikepdf.PasswordError as exc:
        raise PdfError("Mevcut parola hatalı.") from exc
    except Exception as exc:  # noqa: BLE001
        raise PdfError(f"Şifreleme başarısız: {exc}") from exc


def unlock(path: Path, password: str) -> bytes:
    """Parolayı doğrulayıp şifresiz bir kopya döndürür."""
    try:
        with pikepdf.open(str(path), password=password or "") as pdf:
            buf = io.BytesIO()
            pdf.save(buf)  # şifresiz kaydet
            return buf.getvalue()
    except pikepdf.PasswordError as exc:
        raise PdfError("Parola hatalı; belge açılamadı.") from exc
    except Exception as exc:  # noqa: BLE001
        raise PdfError(f"Şifre kaldırılamadı: {exc}") from exc


def is_encrypted(path: Path) -> bool:
    try:
        with fitz.open(path) as doc:
            return doc.needs_pass
    except Exception:  # noqa: BLE001
        return False


def place_signature(
    path: Path, image_bytes: bytes, *, page: int, x: float, y: float,
    w: float, h: float, password: str | None = None,
) -> bytes:
    """İmza görselini belirtilen sayfa/konuma yerleştirir."""
    doc = fitz.open(path)
    try:
        if doc.needs_pass:
            if not password or not doc.authenticate(password):
                raise PdfError("Belge parola korumalı; doğru parola gerekli.")
        if page < 0 or page >= doc.page_count:
            raise PdfError("Geçersiz sayfa.")
        pg = doc.load_page(page)
        rect = fitz.Rect(x, y, x + w, y + h)
        pg.insert_image(rect, stream=image_bytes, overlay=True, keep_proportion=True)
        return doc.tobytes(garbage=4, deflate=True)
    finally:
        doc.close()


def flatten(path: Path, password: str | None = None) -> bytes:
    """Anotasyonları ve form alanlarını sayfa içeriğine gömerek düzleştirir."""
    doc = fitz.open(path)
    try:
        if doc.needs_pass:
            if not password or not doc.authenticate(password):
                raise PdfError("Belge parola korumalı; doğru parola gerekli.")
        # Form alanlarını ve anotasyonları görünür içeriğe çevir
        for page in doc:
            page.wrap_contents()
        # convert_to_pdf üzerinden yeniden yaz (anotasyonları sabitlemenin güvenli yolu):
        pdf_bytes = doc.convert_to_pdf()
        with fitz.open("pdf", pdf_bytes) as flat:
            return flat.tobytes(garbage=4, deflate=True)
    finally:
        doc.close()
