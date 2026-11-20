"""Responsive and accessible web UI contracts.

These tests intentionally stay browser-independent.  They protect the semantic
markup and JavaScript hooks that are easy to regress while page modules render
most rows dynamically.
"""

from __future__ import annotations

import shutil
import subprocess
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "src" / "kitapkatalog" / "webapp" / "static"


class _Markup(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.elements: list[tuple[str, dict[str, str | None]]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.elements.append((tag, dict(attrs)))


def _markup(name: str) -> _Markup:
    parser = _Markup()
    parser.feed((STATIC / name).read_text(encoding="utf-8"))
    return parser


@pytest.mark.parametrize("name", ["index.html", "opac.html"])
def test_markup_ids_and_aria_targets_are_valid(name: str) -> None:
    markup = _markup(name)
    ids = [attrs["id"] for _, attrs in markup.elements if attrs.get("id")]
    assert [item for item, count in Counter(ids).items() if count > 1] == []
    targets = set(ids)

    for _, attrs in markup.elements:
        if controls := attrs.get("aria-controls"):
            assert controls in targets
        if labelledby := attrs.get("aria-labelledby"):
            assert labelledby in targets

        if attrs.get("role") == "tab":
            assert attrs.get("id")
            assert attrs.get("aria-controls")
            assert attrs.get("aria-selected") in {"true", "false"}
            assert attrs.get("tabindex") in {"0", "-1"}

        if attrs.get("role") == "dialog":
            assert attrs.get("aria-modal") == "true"
            assert attrs.get("aria-label") or attrs.get("aria-labelledby")


def test_responsive_shell_and_local_table_scrolling_contract() -> None:
    index = (STATIC / "index.html").read_text(encoding="utf-8")
    css = (STATIC / "style.css").read_text(encoding="utf-8")

    assert 'class="skip-link" href="#ana-icerik"' in index
    assert 'id="menu-dugme"' in index
    assert 'aria-controls="ana-menu"' in index
    assert 'aria-expanded="false"' in index
    assert 'id="menu-overlay"' in index
    assert 'id="ana-icerik" tabindex="-1"' in index

    assert "@media (max-width: 900px)" in css
    assert ".sidebar.open {" in css
    assert "transform: translateX(0); visibility: visible" in css
    assert ".content { max-width: none; min-width: 0;" in css
    assert "@media (max-width: 600px)" in css
    assert ".form-grid, .single-faces { grid-template-columns: minmax(0, 1fr); }" in css
    assert "overflow-x: auto" in css
    assert "-webkit-overflow-scrolling: touch" in css
    assert "soft-pulse 2.4s ease-in-out 2" in css


def test_keyboard_dialog_tab_and_live_region_contracts() -> None:
    index = (STATIC / "index.html").read_text(encoding="utf-8")
    opac = (STATIC / "opac.html").read_text(encoding="utf-8")
    ui = (STATIC / "js" / "ui.js").read_text(encoding="utf-8")
    main = (STATIC / "js" / "main.js").read_text(encoding="utf-8")

    assert 'id="detay" class="drawer" hidden role="dialog" aria-modal="true"' in index
    assert 'id="uye-detay" class="drawer" hidden role="dialog" aria-modal="true"' in index
    assert 'id="toasts" class="toasts" aria-label="Bildirimler" aria-live="polite"' in index
    assert 'role="status" aria-live="polite"' in opac

    for token in [
        "dialogcancel",
        "state.controller.abort()",
        'event.key === "Escape"',
        'event.key !== "Tab"',
        'event.key !== "Enter" && event.key !== " "',
        'event.key === "ArrowRight"',
        'event.key === "Home"',
        'event.key === "End"',
        "MutationObserver",
    ]:
        assert token in ui

    assert 'setAttribute("aria-current", "page")' in main
    assert 'menuButton.setAttribute("aria-expanded"' in main
    assert 'sidebar.setAttribute("aria-hidden"' in main
    assert "mainContent.inert = mobileMenuOpen" in main


def test_dirty_form_navigation_contract() -> None:
    main = (STATIC / "js" / "main.js").read_text(encoding="utf-8")
    ui = (STATIC / "js" / "ui.js").read_text(encoding="utf-8")

    for token in [
        "canLeaveCurrentPage",
        "hasUnsavedChanges",
        "requestHashNavigation",
        "approvedHash",
        'window.addEventListener("beforeunload"',
        "history.replaceState",
        "restoreFocus(opener)",
    ]:
        assert token in main

    assert "export function formSnapshot(form)" in ui
    assert 'element.type === "checkbox" || element.type === "radio"' in ui

    protected_forms = {
        "js/pages/library.js": ["detay-form", "yeni-form"],
        "js/pages/approval.js": ["bilgi-form"],
        "js/pages/members.js": ["uye-form"],
        "js/pages/quick.js": ["hk-form"],
        "js/pages/settings.js": ["ay-form"],
    }
    for relative, form_ids in protected_forms.items():
        source = (STATIC / relative).read_text(encoding="utf-8")
        assert "export function isDirty()" in source
        assert "export function canLeave()" in source
        assert "formSnapshot" in source
        assert "confirmBox" in source
        for form_id in form_ids:
            assert form_id in source


def test_circulation_session_log_and_idempotency_ready_requests() -> None:
    index = (STATIC / "index.html").read_text(encoding="utf-8")
    css = (STATIC / "style.css").read_text(encoding="utf-8")
    loans = (STATIC / "js" / "pages" / "loans.js").read_text(encoding="utf-8")

    assert 'id="od-son-islemler" class="banko-log" role="log" tabindex="0"' in index
    assert 'aria-live="polite"' in index
    assert 'aria-relevant="additions text"' in index
    assert 'id="od-son-islemler-bos"' in index

    for token in [
        "MAX_SESSION_TRANSACTIONS = 30",
        "const sessionTransactions = []",
        "const inFlightLoanActions = new Map()",
        "crypto.randomUUID()",
        "startTransaction",
        "finishTransaction",
        "executeTransaction",
        "scannerFocusRestorer",
        "request(entry.requestId)",
        "Aynı işlemi güvenle yeniden dene",
        "entry.retryAction",
        "inFlightLoanActions.has(actionKey)",
        "setLoanActionPending(actionKey, true)",
        "onSettled",
        'status: "success"',
        'status: "error"',
    ]:
        assert token in loans
    # Ödünç, barkodla iade, listedeki iade ve uzatma aynı requestId ile
    # güvenle tekrar oynatılabilir; listedeki iade/uzatma ortak çalıştırıcıdadır.
    assert loans.count("request_id: requestId") >= 3

    for token in [
        ".banko-log {",
        ".banko-islem.pending",
        ".banko-islem.success",
        ".banko-islem.error",
        ".banko-islem-main",
        ".banko-islem-yeniden",
    ]:
        assert token in css
    assert "prefers-reduced-motion: reduce" in loans


def test_async_refresh_and_latest_wins_contracts() -> None:
    api = (STATIC / "js" / "api.js").read_text(encoding="utf-8")
    main = (STATIC / "js" / "main.js").read_text(encoding="utf-8")

    assert "get: (path, options = {}) => request(path, options)" in api
    assert "post: (path, body, options = {})" in api
    assert "upload: (path, formData, options = {})" in api
    assert "...options" in api

    assert "await Promise.all(Object.entries(map).map" in main
    assert 'api.get("/health")' in main
    assert "document.hidden || globalIndicatorsBusy" in main
    assert 'document.addEventListener("visibilitychange"' in main


def test_settings_load_cannot_overwrite_a_fast_user_edit() -> None:
    settings = (STATIC / "js" / "pages" / "settings.js").read_text(encoding="utf-8")

    for token in [
        "settingsLoadGeneration",
        "const generation = ++settingsLoadGeneration",
        "generation !== settingsLoadGeneration",
        'form.inert = true',
        'form.setAttribute("aria-busy", "true")',
        'form.removeAttribute("aria-busy")',
        "settingsLoadGeneration += 1",
    ]:
        assert token in settings


def test_year_end_open_loan_resolution_stays_visible_after_apply() -> None:
    index = (STATIC / "index.html").read_text(encoding="utf-8")
    members = (STATIC / "js" / "pages" / "members.js").read_text(encoding="utf-8")
    css = (STATIC / "style.css").read_text(encoding="utf-8")

    assert 'id="uye-promote-cozum" class="resolution-alert" role="alert" hidden' in index
    assert 'id="uye-promote-cozum-liste"' in index
    assert "renderPromoteResolutions(plan.needs_resolution)" in members
    assert "const resolutions = report.needs_resolution || []" in members
    assert "üzerindeki kitaplar iade edilene kadar aktif tutuldu" in members
    assert 'show($("uye-promote-onizleme"), true)' in members
    assert ".resolution-alert" in css

    latest_wins = [
        "js/pages/library.js",
        "js/pages/loans.js",
        "js/pages/members.js",
        "js/pages/stocktake.js",
        "js/opac.js",
    ]
    for relative in latest_wins:
        source = (STATIC / relative).read_text(encoding="utf-8")
        assert "AbortController" in source
        assert ".abort()" in source
        assert "signal:" in source

    for relative in ["js/pages/approval.js", "js/pages/imports.js", "js/pages/voice.js"]:
        source = (STATIC / relative).read_text(encoding="utf-8")
        assert "document.hidden || pollBusy" in source
        assert "finally { pollBusy = false; }" in source


def test_dynamic_action_targets_are_named_and_keyboard_enabled() -> None:
    actionable = [
        "js/pages/library.js",
        "js/pages/approval.js",
        "js/pages/imports.js",
        "js/pages/loans.js",
        "js/pages/members.js",
        "js/pages/shelfmap.js",
        "js/pages/stocktake.js",
    ]
    for relative in actionable:
        source = (STATIC / relative).read_text(encoding="utf-8")
        assert "data-key-activate" in source
        assert 'role="button"' in source
        assert 'tabindex="0"' in source
        assert "aria-label=" in source

    for relative in ["js/pages/library.js", "js/pages/members.js", "js/pages/shelfmap.js"]:
        source = (STATIC / relative).read_text(encoding="utf-8")
        for match in source.split('class="btn-icon"')[1:]:
            assert "aria-label=" in match.split("</button>", 1)[0]


def test_static_javascript_parses() -> None:
    node = shutil.which("node")
    if node is None:
        pytest.skip("Node.js is not installed")

    scripts = sorted((STATIC / "js").rglob("*.js"))
    assert scripts
    for script in scripts:
        result = subprocess.run(
            [node, "--check", str(script)],
            capture_output=True,
            check=False,
            text=True,
        )
        assert result.returncode == 0, f"{script.relative_to(ROOT)}\n{result.stderr}"


def test_import_shelf_and_single_document_contracts() -> None:
    """Dolap hedefi, klasör yükleme ve tek belgeli tek kitap kancaları."""

    index = (STATIC / "index.html").read_text(encoding="utf-8")
    imports = (STATIC / "js" / "pages" / "imports.js").read_text(encoding="utf-8")

    for token in [
        'id="toplu-dolap"',
        'id="toplu-klasor-dolap"',
        'id="toplu-klasor-secim"',
        "webkitdirectory",
        'id="dolap-listesi"',
        'list="dolap-listesi"',
        'id="tek-belge"',
        'name="tek-mod"',
        'id="tek-dolap"',
        'id="aktarim-rapor"',
        "<th>Dolap</th>",
    ]:
        assert token in index

    for token in [
        'form.append("shelf", shelf)',
        'form.append("folder_shelf", "1")',
        'form.append("document"',
        "file.webkitRelativePath || file.name",
        '/api/shelves',
        "/retry-failed",
        "api.del(`/api/imports/${jobId}`)",
        "api.patch(`/api/imports/",
        "job.location",
    ]:
        assert token in imports


def test_pwa_shell_and_icon_sprite_contract() -> None:
    """Faz 3: PWA bağlanması, alt gezinme, ikon sprite ve iskelet/görünüm anahtarı."""

    index = (STATIC / "index.html").read_text(encoding="utf-8")
    css = (STATIC / "style.css").read_text(encoding="utf-8")
    main = (STATIC / "js" / "main.js").read_text(encoding="utf-8")
    library = (STATIC / "js" / "pages" / "library.js").read_text(encoding="utf-8")

    # PWA bağlanması: manifest + theme-color + service worker kaydı.
    assert 'rel="manifest" href="/static/manifest.webmanifest"' in index
    assert index.count('name="theme-color"') >= 2
    assert 'navigator.serviceWorker.register("/static/sw.js")' in main

    # Alt gezinme çubuğu: id + aria bağlaması; sidebar ile birlikte aria-current alır.
    assert 'id="alt-nav"' in index
    assert 'aria-label="Alt gezinme"' in index
    assert 'id="alt-nav-menu"' in index
    assert 'aria-controls="ana-menu"' in index.split('id="alt-nav-menu"', 1)[1][:200]
    assert '".sidebar a, #alt-nav a"' in main
    assert "@media (max-width: 600px)" in css
    assert "#alt-nav { display: block; }" in css

    # İkon sprite: kritik semboller mevcut ve currentColor ile boyanıyor.
    for symbol in [
        "i-ev", "i-hizli", "i-kitap", "i-liste", "i-aktarma", "i-mikrofon", "i-onay",
        "i-odunc", "i-uye", "i-kupa", "i-raf", "i-yazdir", "i-sayim", "i-dusum",
        "i-rapor", "i-disa", "i-motor", "i-ayar", "i-arama", "i-zil", "i-arti",
        "i-carpi", "i-uyari", "i-grafik",
    ]:
        assert f'id="{symbol}"' in index
        assert f'href="#{symbol}"' in index
    assert ".icon {" in css
    assert "stroke: currentColor" in css

    # İskelet yükleme: sınıf tanımlı, genel reduced-motion kuralı animasyonu durdurur.
    assert ".skeleton {" in css
    assert "skeleton-shimmer" in css
    assert "prefers-reduced-motion: reduce" in css

    # Kütüphane görünüm anahtarı: aria-pressed durumu JS'te güncelleniyor.
    assert 'id="gorunum-tablo"' in index and 'aria-pressed="true"' in index
    assert 'id="gorunum-kart"' in index and 'aria-pressed="false"' in index
    assert 'setAttribute("aria-pressed"' in library
    assert 'localStorage.getItem("kk-gorunum")' in library


def test_dashboard_and_external_suggestions_frontend_contract() -> None:
    """Faz 3: Genel Bakış panosu ve Onay Merkezi'ndeki Dış Öneriler sekmesi."""

    index = (STATIC / "index.html").read_text(encoding="utf-8")
    overview = (STATIC / "js" / "pages" / "overview.js").read_text(encoding="utf-8")
    approval = (STATIC / "js" / "pages" / "approval.js").read_text(encoding="utf-8")

    assert 'api.get("/api/dashboard")' in overview
    for element_id in [
        "st-eser", "st-nusha", "st-odunc", "st-geciken", "st-bugun-islem",
        "st-bildirim", "st-rezervasyon", "st-okuyan",
        "grafik-koleksiyon", "grafik-kategori", "oz-geciken", "oz-yarisma-kart",
    ]:
        assert f'id="{element_id}"' in index

    assert 'id="onay-tab-disoneri"' in index
    assert 'id="onay-disoneri"' in index
    assert 'aria-controls="onay-disoneri"' in index
    assert 'api.get("/api/external-suggestions?status=pending")' in approval
    assert '/dismiss' in approval
    assert "fillReviewFromSuggestion" in approval
