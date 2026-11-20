#!/usr/bin/env python3
"""KitapKatalog v0.9.0 için izole, gerçek tarayıcı kabul turu.

Canlı katalog hiçbir zaman açılmaz: sunucu her koşumda yeni bir geçici
``KITAPKATALOG_DATA_DIR`` ile başlatılır ve kapanışta süreç/oturum temizlenir.
Ekran görüntüleri, sunucu günlüğü ve makinece okunur özet ``--artifacts``
altındaki zaman damgalı koşum dizinine yazılır.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.error
import urllib.request
from contextlib import suppress
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

_REPO_SRC = Path(__file__).resolve().parent.parent / "src"
if str(_REPO_SRC) not in sys.path:
    sys.path.insert(0, str(_REPO_SRC))

from kitapkatalog import __version__ as EXPECTED_VERSION  # noqa: E402
from kitapkatalog.database import SCHEMA_VERSION as EXPECTED_SCHEMA  # noqa: E402

SERVER_TIMEOUT_SECONDS = 40.0


@dataclass(frozen=True, slots=True)
class PageSpec:
    key: str
    heading: str
    anchor: str


PAGES = (
    PageSpec("genel", "Genel Bakış", "#genel-kartlar"),
    PageSpec("hizli", "Hızlı Kayıt", "#hk-kod"),
    PageSpec("kutuphane", "Kütüphane", "#kitap-tablo"),
    PageSpec("listeler", "Okuma Listeleri", "#liste-tablo"),
    PageSpec("aktarim", "İçe Aktarma", "#toplu-birak"),
    PageSpec("ses", "Sesli Kayıt", "#kayit-btn"),
    PageSpec("onay", "Onay Merkezi", "#onay-sekmeler"),
    PageSpec("odunc", "Ödünç İşlemleri", "#odunc-sekmeler"),
    PageSpec("uyeler", "Üyeler", "#uye-tablo"),
    PageSpec("yarisma", "Okuma Yarışması", "#yrs-secim"),
    PageSpec("harita", "Raf Haritası", "#hr-izgara"),
    PageSpec("yazdir", "Yazdır", "#yz-etiket-kapsam"),
    PageSpec("sayim", "Envanter Sayımı", "#sy-baslat"),
    PageSpec("dusum", "Düşüm Defteri", "#du-tablo"),
    PageSpec("raporlar", "Okuma Raporları", "#rp-okuyanlar"),
    PageSpec("disari", "Dışa Aktarım", "#format-sec"),
    PageSpec("ayarlar", "Ayarlar", "#ay-form"),
    # İlk ziyaret model paketi denetimi başlatabilir; diğer sayfaları geciktirmesin.
    PageSpec("motorlar", "Motor Durumu", "#motor-govde"),
)


class SmokeFailure(RuntimeError):
    """Kabul koşulunun sağlanmadığını bildirir."""


@dataclass(slots=True)
class Report:
    started_at: str
    run_dir: str
    checks: list[dict[str, Any]] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)
    browser_events: list[dict[str, Any]] = field(default_factory=list)
    screenshots: list[str] = field(default_factory=list)
    health: dict[str, Any] = field(default_factory=dict)
    seed: dict[str, Any] = field(default_factory=dict)
    browser: dict[str, Any] = field(default_factory=dict)
    server_exit_code: int | None = None
    finished_at: str | None = None

    def check(self, name: str, passed: bool, detail: Any = None) -> bool:
        item = {"name": name, "passed": bool(passed)}
        if detail not in (None, "", [], {}):
            item["detail"] = detail
        self.checks.append(item)
        if not passed:
            message = name if detail in (None, "") else f"{name}: {detail}"
            self.failures.append(message)
        return bool(passed)

    def require(self, name: str, passed: bool, detail: Any = None) -> None:
        if not self.check(name, passed, detail):
            raise SmokeFailure(self.failures[-1])


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def reserve_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"JSON nesnesi bekleniyordu: {path}")
    return payload


def fetch_health(port: int) -> dict[str, Any] | None:
    try:
        with urllib.request.urlopen(
            f"http://127.0.0.1:{port}/health", timeout=1.0
        ) as response:
            payload = json.load(response)
    except (OSError, ValueError, json.JSONDecodeError, urllib.error.URLError):
        return None
    return payload if isinstance(payload, dict) else None


def wait_for_server(
    process: subprocess.Popen[bytes], session_file: Path, port: int, report: Report
) -> dict[str, Any]:
    deadline = time.monotonic() + SERVER_TIMEOUT_SECONDS
    last_health: dict[str, Any] | None = None
    session: dict[str, Any] | None = None
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SmokeFailure(f"Sunucu readiness öncesi kapandı (kod {process.returncode})")
        if session_file.is_file():
            try:
                session = read_json(session_file)
            except (OSError, ValueError, json.JSONDecodeError):
                session = None
            if session is not None:
                last_health = fetch_health(port)
                if (
                    last_health
                    and last_health.get("app") == "kitapkatalog"
                    and last_health.get("nonce") == session.get("nonce")
                ):
                    break
        time.sleep(0.1)
    else:
        raise SmokeFailure(f"Sunucu {SERVER_TIMEOUT_SECONDS:g} saniyede hazır olmadı")

    assert session is not None and last_health is not None
    report.require("session-port", session.get("port") == port, session.get("port"))
    report.require("session-pid", session.get("pid") == process.pid, session.get("pid"))
    report.require("session-version", session.get("version") == EXPECTED_VERSION, session.get("version"))
    report.require("health-version", last_health.get("version") == EXPECTED_VERSION, last_health)
    report.require("health-schema", last_health.get("schema_version") == EXPECTED_SCHEMA, last_health)
    report.require("session-mode-0600", session_file.stat().st_mode & 0o777 == 0o600)
    report.require("session-token-present", bool(session.get("token")))
    report.health = {key: value for key, value in last_health.items() if key != "nonce"}
    return session


def browser_executable(explicit: Path | None) -> str | None:
    if explicit is not None:
        resolved = explicit.expanduser().resolve()
        if not resolved.is_file() or not os.access(resolved, os.X_OK):
            raise SmokeFailure(f"Tarayıcı çalıştırılabilir değil: {resolved}")
        return str(resolved)
    candidates = (
        Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
        Path("/Applications/Chromium.app/Contents/MacOS/Chromium"),
        Path("/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"),
    )
    return next((str(path) for path in candidates if path.is_file()), None)


def attach_browser_monitors(page: Any, report: Report, phase: dict[str, str], base_url: str) -> None:
    def on_console(message: Any) -> None:
        if message.type == "error":
            if (
                phase.get("expected_console_error") == "404"
                and "status of 404" in message.text
            ):
                return
            report.browser_events.append(
                {"kind": "console", "phase": phase["name"], "text": message.text}
            )

    def on_page_error(error: Any) -> None:
        report.browser_events.append(
            {"kind": "pageerror", "phase": phase["name"], "text": str(error)}
        )

    def on_response(response: Any) -> None:
        if response.url.startswith(base_url) and response.status >= 500:
            report.browser_events.append(
                {
                    "kind": "http-5xx",
                    "phase": phase["name"],
                    "status": response.status,
                    "url": response.url,
                }
            )

    page.on("console", on_console)
    page.on("pageerror", on_page_error)
    page.on("response", on_response)


def api_call(
    page: Any,
    report: Report,
    method: str,
    path: str,
    body: Any = None,
    expected: tuple[int, ...] = (200, 201, 202),
) -> Any:
    result = page.evaluate(
        """
        async ({method, path, body}) => {
          const options = {method, headers: {Accept: "application/json"}};
          if (body !== null) {
            options.headers["Content-Type"] = "application/json";
            options.body = JSON.stringify(body);
          }
          const response = await fetch(path, options);
          const text = await response.text();
          let payload = null;
          if (text) {
            try { payload = JSON.parse(text); } catch { payload = text; }
          }
          return {status: response.status, payload};
        }
        """,
        {"method": method, "path": path, "body": body},
    )
    name = f"api:{method}:{path.split('?')[0]}"
    report.require(name, result["status"] in expected, result)
    return result["payload"]


def navigate_desktop(page: Any, spec: PageSpec, report: Report) -> None:
    link = page.locator(f'#ana-menu a[data-page="{spec.key}"]')
    link.click()
    section = page.locator(f"#sayfa-{spec.key}")
    section.wait_for(state="visible")
    page.wait_for_timeout(120)
    report.require(
        f"desktop:{spec.key}:heading",
        section.locator("h1").first.inner_text().strip() == spec.heading,
    )
    report.require(f"desktop:{spec.key}:anchor", page.locator(spec.anchor).count() == 1)
    report.require(
        f"desktop:{spec.key}:single-page", page.locator("section.page:not([hidden])").count() == 1
    )
    report.require(
        f"desktop:{spec.key}:aria-current", link.get_attribute("aria-current") == "page"
    )


def audit_visible_page(page: Any, expected_heading: str) -> dict[str, Any]:
    return page.evaluate(
        r"""
        ({expectedHeading}) => {
          const issues = [];
          const visible = (element) => {
            if (element.closest("[hidden], [aria-hidden=true], [inert]")) return false;
            const style = getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden") return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          };
          const ids = [...document.querySelectorAll("[id]")].map((element) => element.id);
          const duplicates = [...new Set(ids.filter((id, index) => ids.indexOf(id) !== index))];
          if (duplicates.length) issues.push(`yinelenen id: ${duplicates.join(", ")}`);

          const section = document.querySelector("section.page:not([hidden])");
          const headings = section ? [...section.querySelectorAll("h1")].filter(visible) : [];
          if (!section) issues.push("görünür sayfa yok");
          if (headings.length !== 1) issues.push(`görünür h1 sayısı ${headings.length}`);
          else if (headings[0].textContent.trim() !== expectedHeading) {
            issues.push(`h1 '${headings[0].textContent.trim()}'`);
          }

          const controls = [...document.querySelectorAll(
            "button, a[href], input:not([type=hidden]), select, textarea"
          )].filter(visible);
          const unnamed = controls.filter((element) => {
            const labelledBy = (element.getAttribute("aria-labelledby") || "")
              .split(/\s+/).filter(Boolean)
              .map((id) => document.getElementById(id)?.textContent || "").join(" ");
            const labels = element.labels ? [...element.labels].map((label) => label.textContent).join(" ") : "";
            const native = element.matches("button, a")
              ? element.textContent
              : element.matches("input[type=submit], input[type=reset], input[type=button]")
                ? element.value : "";
            return ![element.getAttribute("aria-label"), labelledBy, labels,
                     element.getAttribute("title"), native]
              .some((value) => String(value || "").trim());
          }).map((element) => element.id || element.outerHTML.slice(0, 70));
          if (unnamed.length) issues.push(`adsız denetim: ${unnamed.slice(0, 8).join(", ")}`);

          const rootWidth = Math.max(document.documentElement.scrollWidth, document.body.scrollWidth);
          if (rootWidth > innerWidth + 1) issues.push(`yatay taşma ${rootWidth}px > ${innerWidth}px`);
          if (!document.documentElement.lang.toLowerCase().startsWith("tr")) issues.push("html lang tr değil");
          if (!document.title.trim()) issues.push("belge başlığı boş");
          return {issues, controls: controls.length, root_width: rootWidth, viewport_width: innerWidth};
        }
        """,
        {"expectedHeading": expected_heading},
    )


def screenshot(page: Any, report: Report, run_dir: Path, name: str) -> None:
    destination = run_dir / name
    page.screenshot(path=str(destination), full_page=True)
    report.screenshots.append(destination.name)


def seed_realistic_data(page: Any, report: Report) -> None:
    settings = next(spec for spec in PAGES if spec.key == "ayarlar")
    navigate_desktop(page, settings, report)
    page.locator('#ay-form [name="school_name"]').fill("Atatürk Anadolu Lisesi")
    page.locator("#ay-form button[type=submit]").click()
    page.locator("#okul-adi").wait_for(state="visible")
    report.require("ui:settings-school-name", page.locator("#okul-adi").inner_text() == "Atatürk Anadolu Lisesi")

    shelf = api_call(
        page,
        report,
        "POST",
        "/api/shelves",
        {
            "name": "Dolap A",
            "grid_row": 0,
            "grid_col": 0,
            "capacity": 120,
            "color": "#3453b8",
            "notes": "Türk ve dünya romanları",
        },
    )

    library = next(spec for spec in PAGES if spec.key == "kutuphane")
    navigate_desktop(page, library, report)
    page.locator("#btn-yeni-kitap").click()
    dialog = page.locator("#modal-yeni")
    dialog.wait_for(state="visible")
    values = {
        "isbn": "9789750718533",
        "title": "Kürk Mantolu Madonna",
        "authors": "Sabahattin Ali",
        "publisher": "Yapı Kredi Yayınları",
        "publication_date": "2023",
        "page_count": "160",
        "language": "Türkçe",
        "category": "Türk Edebiyatı",
        "location": "Dolap A",
        "copy_count": "3",
    }
    for name, value in values.items():
        dialog.locator(f'[name="{name}"]').fill(value)
    dialog.locator("button[type=submit]").click()
    dialog.wait_for(state="hidden")
    page.locator("#kitap-govde").get_by_text("Kürk Mantolu Madonna", exact=True).wait_for()
    report.check("ui:create-book", True)

    first_search = api_call(page, report, "GET", "/api/books?identifier=9789750718533")
    report.require("ui:create-book-visible-api", first_search["total"] == 1, first_search)
    first_book = api_call(
        page, report, "GET", f'/api/books/{first_search["items"][0]["edition_id"]}'
    )

    members = next(spec for spec in PAGES if spec.key == "uyeler")
    navigate_desktop(page, members, report)
    page.locator("#uye-yeni").click()
    member_form = page.locator("#uye-form")
    member_values = {
        "school_number": "1042",
        "first_name": "Elif",
        "last_name": "Yılmaz",
        "class_name": "10-A",
        "notes": "E2E örnek öğrenci",
    }
    for name, value in member_values.items():
        member_form.locator(f'[name="{name}"]').fill(value)
    member_form.locator("button[type=submit]").click()
    page.locator("#uye-tablo").get_by_text("Elif Yılmaz", exact=True).wait_for()
    report.check("ui:create-member", True)
    student = api_call(page, report, "GET", "/api/members/by-number/1042")

    second_book = api_call(
        page,
        report,
        "POST",
        "/api/books",
        {
            "title": "Beyaz Gemi",
            "authors": "Cengiz Aytmatov",
            "isbn": "9789753638029",
            "publisher": "Ötüken Neşriyat",
            "publication_date": "2021",
            "page_count": 176,
            "language": "Türkçe",
            "category": "Dünya Edebiyatı",
            "location": "Dolap A",
            "copy_count": 2,
            "auto_inventory": True,
        },
    )
    api_call(
        page,
        report,
        "PATCH",
        f'/api/books/{second_book["edition_id"]}',
        {"changes": {"review_status": "review"}},
    )
    staff = api_call(
        page,
        report,
        "POST",
        "/api/members",
        {
            "member_type": "staff",
            "school_number": "P-001",
            "first_name": "Ayşe",
            "last_name": "Demir",
            "class_name": "Öğretmen",
            "notes": "E2E örnek personel",
        },
    )
    api_call(page, report, "POST", "/api/copies/assign-codes", {"scope": "all"})
    first_book = api_call(page, report, "GET", f'/api/books/{first_book["edition_id"]}')
    second_book = api_call(page, report, "GET", f'/api/books/{second_book["edition_id"]}')
    copies = first_book["copies"]
    second_code = second_book["copies"][0]["inventory_code"]
    report.require("seed:three-coded-copies", len(copies) == 3 and all(item["inventory_code"] for item in copies), copies)
    report.require("seed:second-book-code", bool(second_code), second_book["copies"])
    loan_request = {
        "school_number": "1042",
        "code": copies[0]["inventory_code"],
        "request_id": "e2e-seed-checkout-0001",
    }
    loan = api_call(
        page,
        report,
        "POST",
        "/api/loans",
        loan_request,
    )
    replayed_loan = api_call(page, report, "POST", "/api/loans", loan_request)
    report.require(
        "circulation:idempotent-checkout-replay",
        replayed_loan["id"] == loan["id"],
        {"first": loan["id"], "replay": replayed_loan["id"]},
    )
    stocktake = api_call(
        page,
        report,
        "POST",
        "/api/stocktake/sessions",
        {"name": "2026 Ağustos Smoke Sayımı", "scope_location": "Dolap A"},
    )
    scan = api_call(
        page,
        report,
        "POST",
        f'/api/stocktake/sessions/{stocktake["id"]}/scans',
        {"code": copies[1]["inventory_code"]},
    )
    discard = api_call(
        page,
        report,
        "POST",
        "/api/discards",
        {
            "copy_id": copies[2]["id"],
            "reason": "yipranma",
            "note": "Kapak ve sırt ağır yıpranmış",
        },
    )
    report.seed = {
        "books": [first_book["edition_id"], second_book["edition_id"]],
        "members": [student["id"], staff["id"]],
        "shelf": shelf["id"],
        "loan": loan["id"],
        "stocktake": stocktake["id"],
        "scan": scan["scan_id"],
        "discard": discard["id"],
        "second_code": second_code,
    }


def exercise_v8_ui_contracts(page: Any, report: Report, phase: dict[str, str]) -> None:
    """Prove the v8 data-loss guard and circulation counter in real Chromium."""

    phase["name"] = "desktop:v8-unsaved-guard"
    settings = next(spec for spec in PAGES if spec.key == "ayarlar")
    navigate_desktop(page, settings, report)
    school = page.locator('#ay-form [name="school_name"]')
    saved_name = school.input_value()
    draft_name = f"{saved_name} — kaydedilmemiş taslak"
    school.fill(draft_name)
    rejected_prompts: list[str] = []

    def reject_navigation(dialog: Any) -> None:
        rejected_prompts.append(dialog.message)
        dialog.dismiss()

    page.once("dialog", reject_navigation)
    library_link = page.locator('#ana-menu a[data-page="kutuphane"]')
    library_link.click()
    page.wait_for_timeout(150)
    report.require("ui:dirty-stay:prompt", bool(rejected_prompts), rejected_prompts)
    report.require("ui:dirty-stay:hash", page.url.endswith("#ayarlar"), page.url)
    report.require("ui:dirty-stay:form", school.input_value() == draft_name, school.input_value())
    report.require(
        "ui:dirty-stay:focus",
        page.evaluate("() => document.activeElement?.dataset?.page") == "kutuphane",
        page.evaluate("() => document.activeElement?.id || document.activeElement?.dataset?.page"),
    )

    accepted_prompts: list[str] = []

    def accept_navigation(dialog: Any) -> None:
        accepted_prompts.append(dialog.message)
        dialog.accept()

    page.once("dialog", accept_navigation)
    library_link.click()
    page.locator("#sayfa-kutuphane").wait_for(state="visible")
    report.require("ui:dirty-leave:prompt", bool(accepted_prompts), accepted_prompts)
    report.require("ui:dirty-leave:navigated", page.url.endswith("#kutuphane"), page.url)

    phase["name"] = "desktop:v8-circulation-log"
    loans_page = next(spec for spec in PAGES if spec.key == "odunc")
    navigate_desktop(page, loans_page, report)
    member_input = page.locator("#od-uye-ara")
    member_input.fill("P-001")
    member_input.press("Enter")
    page.locator("#od-uye-kart").wait_for(state="visible")
    report.require("ui:counter-member", page.locator("#od-uye-ad").inner_text() == "Ayşe Demir")

    checkout_input = page.locator("#od-ver-kod")
    checkout_input.fill(str(report.seed["second_code"]))
    checkout_input.press("Enter")
    first = page.locator("#od-son-islemler > li").nth(0)
    first.wait_for(state="visible")
    page.wait_for_function(
        "() => document.querySelector('#od-son-islemler > li')?.classList.contains('success')"
    )
    report.require("ui:counter-checkout-log", "Beyaz Gemi" in first.inner_text(), first.inner_text())
    report.require("ui:counter-checkout-focus", page.evaluate("() => document.activeElement?.id") == "od-ver-kod")

    return_input = page.locator("#od-iade-kod")
    return_input.fill(str(report.seed["second_code"]))
    return_input.press("Enter")
    page.wait_for_function(
        "() => document.querySelectorAll('#od-son-islemler > li.success').length === 2"
    )
    report.require("ui:counter-return-focus", page.evaluate("() => document.activeElement?.id") == "od-iade-kod")

    phase["expected_console_error"] = "404"
    try:
        return_input.fill("E2E-OLMAYAN-KOD")
        return_input.press("Enter")
        page.wait_for_function(
            "() => document.querySelectorAll('#od-son-islemler > li.error').length === 1"
        )
    finally:
        phase.pop("expected_console_error", None)
    entries = page.locator("#od-son-islemler > li")
    report.require("ui:counter-log-count", entries.count() == 3, entries.count())
    report.require(
        "ui:counter-log-order",
        [entries.nth(index).locator(".banko-islem-tur").inner_text() for index in range(3)]
        == ["Ödünç", "İade", "İade"],
    )
    report.require("ui:counter-error-visible", "Başarısız" in entries.nth(2).inner_text())
    report.require("ui:counter-error-focus", page.evaluate("() => document.activeElement?.id") == "od-iade-kod")

    # Sunucu mutasyonu tamamladıktan sonra yanıtın ağda kaybolmasını taklit et.
    # UI, yeni UUID üretmeden aynı request_id ile yeniden denemeli; böylece
    # uzatma sayacı iki POST'a rağmen yalnız bir artar.
    seed_loan_id = int(report.seed["loan"])
    page.evaluate(
        """
        ({loanId}) => {
          const original = window.fetch.bind(window);
          window.__kitapKatalogE2EOriginalFetch = original;
          let dropped = false;
          window.fetch = async (...args) => {
            const input = args[0];
            const rawUrl = typeof input === "string" ? input : input.url;
            const method = String(args[1]?.method || input?.method || "GET").toUpperCase();
            const response = await original(...args);
            const path = new URL(rawUrl, location.href).pathname;
            if (!dropped && method === "POST" && path === `/api/loans/${loanId}/extend`) {
              dropped = true;
              throw new TypeError("E2E: sunucu yanıtı istemciye ulaşmadı");
            }
            return response;
          };
        }
        """,
        {"loanId": seed_loan_id},
    )
    extend_button = page.locator(
        f'#od-tablo tr[data-loan="{seed_loan_id}"] button[data-extend="{seed_loan_id}"]'
    )
    extend_button.wait_for(state="visible")
    extend_button.click()
    retry_button = page.locator(
        '#od-son-islemler > li:last-child button[data-retry]'
    )
    retry_button.wait_for(state="visible")
    report.require(
        "ui:idempotent-retry-offered",
        "Aynı işlemi güvenle yeniden dene" in retry_button.inner_text(),
        retry_button.inner_text(),
    )
    retry_button.click()
    page.wait_for_function(
        """
        () => document.querySelector("#od-son-islemler > li:last-child")
          ?.classList.contains("success")
        """
    )
    active_loans = api_call(page, report, "GET", "/api/loans?status=active&limit=20")
    renewed = next(item for item in active_loans["items"] if int(item["id"]) == seed_loan_id)
    report.require(
        "ui:idempotent-response-loss-single-renewal",
        int(renewed["renewal_count"]) == 1,
        renewed,
    )
    page.evaluate(
        """
        () => {
          if (window.__kitapKatalogE2EOriginalFetch) {
            window.fetch = window.__kitapKatalogE2EOriginalFetch;
            delete window.__kitapKatalogE2EOriginalFetch;
          }
        }
        """
    )

    # Aynı Uzat düğmesine hızlı çift tıklama yeni iki UUID/iki mutation
    # üretmemeli. İlk click satırı eşzamanlı olarak kilitler; ikinci click
    # tek bir oturum günlüğü girdisi ve tek sayaç artışı bırakır.
    log_count_before_double_click = page.locator("#od-son-islemler > li").count()
    extend_button = page.locator(
        f'#od-tablo tr[data-loan="{seed_loan_id}"] button[data-extend="{seed_loan_id}"]'
    )
    extend_button.wait_for(state="visible")
    extend_button.dblclick()
    expected_log_count = log_count_before_double_click + 1
    page.wait_for_function(
        f"""
        () => document.querySelectorAll("#od-son-islemler > li").length ===
              {expected_log_count}
          && document.querySelector("#od-son-islemler > li:last-child")
              ?.classList.contains("success")
        """
    )
    report.require(
        "ui:double-click-single-transaction-log",
        page.locator("#od-son-islemler > li").count() == expected_log_count,
        page.locator("#od-son-islemler > li").count(),
    )
    active_loans = api_call(page, report, "GET", "/api/loans?status=active&limit=20")
    renewed = next(item for item in active_loans["items"] if int(item["id"]) == seed_loan_id)
    report.require(
        "ui:double-click-single-renewal",
        int(renewed["renewal_count"]) == 2,
        renewed,
    )


def exercise_desktop(page: Any, report: Report, run_dir: Path, phase: dict[str, str]) -> None:
    for index, spec in enumerate(PAGES, start=1):
        phase["name"] = f"desktop:{spec.key}"
        navigate_desktop(page, spec, report)
        audit = audit_visible_page(page, spec.heading)
        report.check(f"desktop:{spec.key}:accessibility-overflow", not audit["issues"], audit)
        screenshot(page, report, run_dir, f"desktop-{index:02d}-{spec.key}.png")


def exercise_mobile(page: Any, report: Report, run_dir: Path, phase: dict[str, str]) -> None:
    button = page.locator("#menu-dugme")
    sidebar = page.locator("#ana-menu")
    main = page.locator("#ana-icerik")
    report.require("mobile:menu-button-visible", button.is_visible())
    report.require("mobile:initially-closed", button.get_attribute("aria-expanded") == "false")

    button.click()
    report.require("mobile:escape-open", button.get_attribute("aria-expanded") == "true")
    page.keyboard.press("Escape")
    report.require("mobile:escape-close", button.get_attribute("aria-expanded") == "false")
    report.require("mobile:escape-focus-return", page.evaluate("() => document.activeElement?.id") == "menu-dugme")

    for index, spec in enumerate(PAGES, start=1):
        phase["name"] = f"mobile:{spec.key}"
        button.click()
        report.require(f"mobile:{spec.key}:menu-open", button.get_attribute("aria-expanded") == "true")
        report.require(f"mobile:{spec.key}:main-inert", main.get_attribute("inert") is not None)
        report.require(f"mobile:{spec.key}:sidebar-active", sidebar.get_attribute("inert") is None)
        link = sidebar.locator(f'a[data-page="{spec.key}"]')
        link.click()
        section = page.locator(f"#sayfa-{spec.key}")
        section.wait_for(state="visible")
        page.wait_for_timeout(120)
        report.require(f"mobile:{spec.key}:menu-close", button.get_attribute("aria-expanded") == "false")
        report.require(f"mobile:{spec.key}:sidebar-inert", sidebar.get_attribute("inert") is not None)
        report.require(f"mobile:{spec.key}:main-active", main.get_attribute("inert") is None)
        report.require(f"mobile:{spec.key}:heading", section.locator("h1").first.inner_text().strip() == spec.heading)
        report.require(f"mobile:{spec.key}:anchor", page.locator(spec.anchor).count() == 1)
        report.require(f"mobile:{spec.key}:aria-current", link.get_attribute("aria-current") == "page")
        audit = audit_visible_page(page, spec.heading)
        report.check(f"mobile:{spec.key}:accessibility-overflow", not audit["issues"], audit)
        screenshot(page, report, run_dir, f"mobile-{index:02d}-{spec.key}.png")


def exercise_opac(
    context: Any, report: Report, run_dir: Path, phase: dict[str, str], base_url: str
) -> None:
    phase["name"] = "desktop:opac"
    page = context.new_page()
    attach_browser_monitors(page, report, phase, base_url)
    page.goto(f"{base_url}/opac", wait_until="networkidle")
    page.locator("#opac-ara").fill("Kürk")
    page.locator("#opac-bilgi").get_by_text("sonuç", exact=False).wait_for()
    report.require(
        "opac:search-result",
        page.locator("#opac-sonuc").get_by_text("Kürk Mantolu Madonna", exact=True).count() == 1,
    )
    width = page.evaluate("() => Math.max(document.documentElement.scrollWidth, document.body.scrollWidth)")
    report.check("opac:no-horizontal-overflow", width <= 1441, {"root_width": width})
    screenshot(page, report, run_dir, "desktop-opac.png")
    page.close()


def final_data_checks(page: Any, report: Report) -> None:
    books = api_call(page, report, "GET", "/api/books?limit=20")
    members = api_call(page, report, "GET", "/api/members?active=true&limit=20")
    loans = api_call(page, report, "GET", "/api/loans?status=active&limit=20")
    shelves = api_call(page, report, "GET", "/api/shelves")
    stocktakes = api_call(page, report, "GET", "/api/stocktake/sessions")
    discards = api_call(page, report, "GET", "/api/discards?limit=20")
    report.check("data:books", books["total"] == 2, books["total"])
    report.check("data:members", members["total"] == 2, members["total"])
    report.check("data:active-loans", loans["total"] == 1, loans["total"])
    report.check("data:shelves", len(shelves) == 1, len(shelves))
    report.check("data:stocktakes", len(stocktakes) == 1, len(stocktakes))
    report.check("data:discards", discards["total"] == 1, discards["total"])


def stop_server(process: subprocess.Popen[bytes] | None, timeout: float = 15.0) -> int | None:
    if process is None:
        return None
    if process.poll() is None:
        with suppress(ProcessLookupError):
            # Masaüstü başlatıcının eski sürümü emekliye ayırırken
            # kullandığı gerçek sinyali de kabul turunda doğrula.
            os.killpg(process.pid, signal.SIGTERM)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            return process.wait(timeout=5)
    return process.returncode


def write_summary(report: Report, run_dir: Path) -> None:
    report.finished_at = utc_now()
    (run_dir / "summary.json").write_text(
        json.dumps(asdict(report), ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--artifacts",
        type=Path,
        required=True,
        help="Ekran görüntüsü, özet ve sunucu günlüğü için üst dizin",
    )
    parser.add_argument("--headed", action="store_true", help="Tarayıcıyı görünür aç")
    parser.add_argument(
        "--browser-executable",
        type=Path,
        default=None,
        help="Chrome/Chromium çalıştırılabilir dosyası (varsayılan: otomatik keşif)",
    )
    return parser.parse_args(argv)


def run(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        from playwright.sync_api import sync_playwright
    except ModuleNotFoundError:
        print(
            "Playwright eksik. `uv sync --extra dev` çalıştırın; sistem Chrome yoksa "
            "ayrıca `uv run playwright install chromium` gerekir.",
            file=sys.stderr,
        )
        return 2

    project_root = Path(__file__).resolve().parents[1]
    artifact_root = args.artifacts.expanduser().resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    run_dir = artifact_root / f"web-e2e-{stamp}-{os.getpid()}"
    run_dir.mkdir(mode=0o700)
    report = Report(started_at=utc_now(), run_dir=str(run_dir))
    process: subprocess.Popen[bytes] | None = None
    log_handle: Any = None
    session_file: Path | None = None

    try:
        with tempfile.TemporaryDirectory(prefix="kitapkatalog-web-e2e-") as temporary:
            temporary_root = Path(temporary).resolve()
            data_dir = temporary_root / "data"
            data_dir.mkdir(mode=0o700)
            session_file = data_dir / "web_session.json"
            report.require("isolation:absolute-temp-root", temporary_root.is_absolute())
            report.require("isolation:data-under-temp", data_dir.is_relative_to(temporary_root))

            port = reserve_loopback_port()
            environment = os.environ.copy()
            environment.update(
                {
                    "KITAPKATALOG_DATA_DIR": str(data_dir),
                    "KITAPKATALOG_MODEL_DIR": str(data_dir / "models"),
                    "HF_HOME": str(temporary_root / "hf-cache"),
                    "TORCH_HOME": str(temporary_root / "torch-cache"),
                    "HF_HUB_OFFLINE": "1",
                    "TRANSFORMERS_OFFLINE": "1",
                    "HF_DATASETS_OFFLINE": "1",
                    "KITAPKATALOG_NETWORK_DISABLED": "1",
                    "NO_PROXY": "127.0.0.1,localhost",
                    "no_proxy": "127.0.0.1,localhost",
                }
            )
            log_handle = (run_dir / "server.log").open("wb")
            process = subprocess.Popen(
                [
                    sys.executable,
                    "-m",
                    "kitapkatalog.webapp.server",
                    "--port",
                    str(port),
                    "--no-browser",
                ],
                cwd=project_root,
                env=environment,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            session = wait_for_server(process, session_file, port, report)
            base_url = f"http://127.0.0.1:{port}"
            executable = browser_executable(args.browser_executable)

            with sync_playwright() as playwright:
                launch: dict[str, Any] = {"headless": not args.headed}
                if executable is not None:
                    launch["executable_path"] = executable
                browser = playwright.chromium.launch(**launch)
                report.browser = {
                    "engine": "chromium",
                    "version": browser.version,
                    "executable": executable or "playwright-bundled",
                    "headed": bool(args.headed),
                }

                desktop = browser.new_context(
                    viewport={"width": 1440, "height": 1000},
                    locale="tr-TR",
                    color_scheme="light",
                )
                phase = {"name": "desktop:bootstrap"}
                page = desktop.new_page()
                attach_browser_monitors(page, report, phase, base_url)
                page.goto(
                    f'{base_url}/?token={session["token"]}',
                    wait_until="networkidle",
                )
                report.require("auth:token-removed-from-url", "token=" not in page.url, page.url)
                report.require("desktop:title", page.title() == "Cumhuriyet Kitap", page.title())
                report.require(
                    "desktop:runtime-version",
                    f"v{EXPECTED_VERSION}" in page.locator("#uygulama-surumu").inner_text(),
                )
                seed_realistic_data(page, report)
                exercise_v8_ui_contracts(page, report, phase)
                exercise_desktop(page, report, run_dir, phase)
                exercise_opac(desktop, report, run_dir, phase, base_url)
                desktop.close()

                dark = browser.new_context(
                    viewport={"width": 1440, "height": 1000},
                    locale="tr-TR",
                    color_scheme="dark",
                )
                phase = {"name": "desktop:dark"}
                page = dark.new_page()
                attach_browser_monitors(page, report, phase, base_url)
                page.goto(
                    f'{base_url}/?token={session["token"]}',
                    wait_until="networkidle",
                )
                page.locator('#ana-menu a[data-page="kutuphane"]').click()
                page.locator("#sayfa-kutuphane").wait_for(state="visible")
                dark_state = page.evaluate(
                    """
                    () => ({
                      preferred: matchMedia("(prefers-color-scheme: dark)").matches,
                      background: getComputedStyle(document.body).backgroundColor,
                      foreground: getComputedStyle(document.body).color,
                    })
                    """
                )
                report.require("dark:preferred-scheme", dark_state["preferred"], dark_state)
                report.require(
                    "dark:distinct-colors",
                    dark_state["background"] != dark_state["foreground"],
                    dark_state,
                )
                screenshot(page, report, run_dir, "desktop-dark-kutuphane.png")
                dark.close()

                mobile = browser.new_context(
                    viewport={"width": 390, "height": 844},
                    locale="tr-TR",
                    color_scheme="light",
                )
                phase = {"name": "mobile:bootstrap"}
                page = mobile.new_page()
                attach_browser_monitors(page, report, phase, base_url)
                page.goto(
                    f'{base_url}/?token={session["token"]}',
                    wait_until="networkidle",
                )
                exercise_mobile(page, report, run_dir, phase)
                final_data_checks(page, report)
                mobile.close()
                browser.close()

            report.check("browser:no-errors", not report.browser_events, report.browser_events)
            report.server_exit_code = stop_server(process)
            process = None
            report.check(
                "server:clean-exit", report.server_exit_code in (0, -signal.SIGTERM), report.server_exit_code
            )
            report.check("server:session-removed", not session_file.exists())
    except Exception as error:
        message = f"{type(error).__name__}: {error}"
        if message not in report.failures:
            report.failures.append(message)
        (run_dir / "traceback.txt").write_text(traceback.format_exc(), encoding="utf-8")
    finally:
        if process is not None:
            report.server_exit_code = stop_server(process)
        if log_handle is not None:
            log_handle.close()
        if session_file is not None and session_file.exists():
            report.failures.append("Sunucu kapanışında oturum dosyası kaldı")
        write_summary(report, run_dir)

    passed = not report.failures
    print(f"KitapKatalog web E2E: {'BAŞARILI' if passed else 'BAŞARISIZ'}")
    print(f"Artefaktlar: {run_dir}")
    if report.failures:
        for failure in report.failures:
            print(f"- {failure}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(run())
