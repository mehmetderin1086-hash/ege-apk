"""Yazdırma sayfaları: etiketler, üye kartları, gecikme listeleri.

Öneksiz HTML route'ları — security.py muafiyet listesinde OLMADIKLARI için
oturum çerezi zorunludur. Tüm kullanıcı verisi html.escape ile kaçışlanır;
şablon motoru bilinçli olarak yok (bağımlılıksız çizgi). Üye verisi içerdiği
için yanıtlar önbelleğe alınmaz (Cache-Control: no-store).
"""

from __future__ import annotations

import html
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import HTMLResponse

from kitapkatalog.barcode128 import svg as barcode_svg
from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["print"])

# Tek koşuda basılacak azami kalem — dev katalogda tarayıcıyı kilitlememek
# için; kırpma yapılırsa sayfa başında açıkça söylenir.
_MAX_LABELS = 1000
_MAX_CARDS = 400


def _state(request: Request) -> WebState:
    return request.app.state.web


def _esc(value: Any) -> str:
    return html.escape(str(value or ""), quote=True)


def _page(title: str, body: str) -> HTMLResponse:
    content = f"""<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<title>{_esc(title)}</title>
<link rel="stylesheet" href="/static/print.css">
</head>
<body>
<div class="ekran-cubuk">
  <strong>{_esc(title)}</strong>
  <button onclick="window.print()">🖨️ Yazdır</button>
  <span class="ipucu">Yazdırma ayarlarında kenar boşluklarını "Yok/None" seçin.</span>
</div>
{body}
</body>
</html>"""
    return HTMLResponse(content, headers={"Cache-Control": "no-store"})


def _shorten(text: str, limit: int = 28) -> str:
    text = text or ""
    return text if len(text) <= limit else text[: limit - 1] + "…"


@router.get("/print/hold-slip")
def print_hold_slip(request: Request, hold_id: int = Query(..., ge=1)) -> HTMLResponse:
    state = _state(request)
    hold = state.loans.get_hold(hold_id)
    if hold is None:
        raise HTTPException(status_code=404, detail="Rezervasyon bulunamadı")
    school_name = state.settings.get("school_name") or "Okul Kütüphanesi"
    body = f"""<section class="mektup">
<h2>{_esc(school_name)}</h2>
<p class="mektup-tarih">Ayırma Fişi</p>
<table>
<tbody>
<tr><th>Kitap</th><td>{_esc(hold.title)}</td></tr>
<tr><th>Üye</th><td>{_esc(hold.member_name)}{f" ({_esc(hold.school_number)})" if hold.school_number else ""}</td></tr>
<tr><th>Durum</th><td>{_esc(hold.status)}</td></tr>
<tr><th>Son Alma Tarihi</th><td>{_esc(hold.expires_at or "—")}</td></tr>
</tbody>
</table>
<p>Kitap banko arkasında bu fişle birlikte bekletilir; son alma tarihine kadar
teslim alınmazsa rezervasyon sıradaki üyeye devredilir.</p>
</section>"""
    return _page("Ayırma Fişi", body)


@router.get("/print/certificate")
def print_certificate(
    request: Request,
    challenge_id: int = Query(..., ge=1),
    member_id: int = Query(..., ge=1),
) -> HTMLResponse:
    """Okuma yarışması başarı sertifikası (A4 yatay, bağımlılıksız SVG çerçeve)."""

    state = _state(request)
    try:
        challenge = state.challenges.get(challenge_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Yarışma bulunamadı") from exc
    standings = state.challenges.standings(challenge_id)
    entry = next(
        (row for row in standings["standings"] if row["member_id"] == member_id), None
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Üye bu yarışmada yer almıyor")
    certificate = state.database.fetchone(
        "SELECT rank FROM challenge_certificate WHERE challenge_id = ? AND member_id = ?",
        (challenge_id, member_id),
    )
    rank = certificate["rank"] if certificate and certificate["rank"] else None
    school_name = state.settings.get("school_name") or "Okul Kütüphanesi"
    today = datetime.now(UTC).date().strftime("%d.%m.%Y")
    rank_line = f"<p class='sertifika-derece'>🏅 {rank}. sıra</p>" if rank else ""
    class_line = f" ({_esc(entry['class_name'])})" if entry["class_name"] else ""
    body = f"""<section class="sertifika">
<svg class="sertifika-cerceve" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
  <rect x="1" y="1" width="98" height="98" fill="none" stroke="#b8860b" stroke-width="0.8"/>
  <rect x="2.6" y="2.6" width="94.8" height="94.8" fill="none" stroke="#b8860b" stroke-width="0.25"/>
</svg>
<div class="sertifika-icerik">
<p class="sertifika-okul">{_esc(school_name)}</p>
<h1>Okuma Sertifikası</h1>
<p class="sertifika-ad">{_esc(entry["member_name"])}{class_line}</p>
<p>"{_esc(challenge.name)}" okuma yarışmasında
<strong>{int(entry["book_count"])}</strong> kitap okuyarak bu belgeyi almaya
hak kazanmıştır.</p>
{rank_line}
<p class="sertifika-tarih">{_esc(today)}</p>
<div class="mektup-imza"><div class="imza-cizgi">Kütüphane Sorumlusu</div></div>
</div>
</section>"""
    return _page("Okuma Sertifikası", body)


@router.get("/print/inventory-ledger")
def print_inventory_ledger(request: Request, year: str = "") -> HTMLResponse:
    """MEB tarzı kütüphane demirbaş defteri (yatay A4).

    ``year`` verilirse yalnız o yıl edinilen nüshalar (edinme tarihi yoksa
    kayıt tarihi esas alınır); verilmezse tüm koleksiyon dökülür.
    """

    state = _state(request)
    if year and not (len(year) == 4 and year.isdigit()):
        raise HTTPException(status_code=400, detail="year 4 haneli yıl olmalı")
    clause, params = "", []
    if year:
        clause = "AND substr(COALESCE(NULLIF(c.acquisition_date, ''), c.created_at), 1, 4) = ?"
        params = [year]
    rows = state.database.fetchall(
        f"""
        SELECT c.inventory_code, c.acquisition_method, c.acquisition_date,
               c.acquisition_price, c.created_at, c.status AS copy_status,
               e.title, e.publisher, e.publication_date,
               (SELECT GROUP_CONCAT(co.display_name, '; ')
                FROM edition_contributor AS ec
                JOIN contributor AS co ON co.id = ec.contributor_id
                WHERE ec.edition_id = e.id AND ec.role = 'author') AS authors,
               (SELECT d.reason FROM discard_record AS d
                WHERE d.copy_id = c.id ORDER BY d.id DESC LIMIT 1) AS discard_reason
        FROM copy AS c JOIN edition AS e ON e.id = c.edition_id
        WHERE 1=1 {clause}
        ORDER BY COALESCE(NULLIF(c.acquisition_date, ''), c.created_at), c.inventory_code
        """,
        params,
    )
    method_labels = {"satin_alma": "Satın alma", "bagis": "Bağış", "devir": "Devir"}
    reason_labels = {
        "yipranma": "Yıpranma",
        "kayip": "Kayıp",
        "guncelligini_yitirme": "Güncelliğini yitirme",
        "diger": "Diğer",
    }
    school_name = state.settings.get("school_name") or "Okul Kütüphanesi"
    body_rows = "".join(
        f"""<tr>
<td class="sag">{index}</td>
<td>{_esc(row["inventory_code"] or "—")}</td>
<td>{_esc(row["title"])}</td>
<td>{_esc(row["authors"] or "—")}</td>
<td>{_esc(row["publisher"] or "—")}</td>
<td>{_esc((row["publication_date"] or "")[:4] or "—")}</td>
<td>{_esc(method_labels.get(row["acquisition_method"] or "", row["acquisition_method"] or "—"))}</td>
<td>{_esc((row["acquisition_date"] or row["created_at"] or "")[:10])}</td>
<td class="sag">{_esc(row["acquisition_price"] or "—")}</td>
<td>{_esc(reason_labels.get(row["discard_reason"] or "", row["discard_reason"] or ""))}</td>
</tr>"""
        for index, row in enumerate(rows, start=1)
    )
    title_suffix = f" — {year}" if year else ""
    body = f"""<section class="defter">
<h2>{_esc(school_name)} · Kütüphane Demirbaş Defteri{_esc(title_suffix)}</h2>
<p class="ipucu">Toplam {len(rows)} nüsha · Döküm tarihi: {datetime.now(UTC).date().isoformat()}</p>
<table>
<thead><tr>
<th class="sag">Sıra</th><th>Demirbaş No</th><th>Eser Adı</th><th>Yazar</th>
<th>Yayınevi</th><th>Yıl</th><th>Edinme Yolu</th><th>Edinme Tarihi</th>
<th class="sag">Fiyat</th><th>Düşüm</th>
</tr></thead>
<tbody>{body_rows}</tbody>
</table>
</section>""" if rows else '<p class="uyari">Kapsamda nüsha yok.</p>'
    return _page("Demirbaş Defteri", body)


@router.get("/print/annual-report")
def print_annual_report(request: Request, start: str = "", end: str = "") -> HTMLResponse:
    """Yıl sonu istatistik raporunun yazdırılabilir sürümü."""

    state = _state(request)
    if not start or not end:
        today = datetime.now(UTC).date()
        school_year_start = today.year if today.month >= 9 else today.year - 1
        start = start or f"{school_year_start}-09-01"
        end = end or today.isoformat()
    report = state.reports.annual(start=start, end=end)
    school_name = state.settings.get("school_name") or "Okul Kütüphanesi"

    def table(headers: list[str], rows: list[list[Any]]) -> str:
        head = "".join(f"<th>{_esc(h)}</th>" for h in headers)
        body = "".join(
            "<tr>" + "".join(f"<td>{_esc(cell)}</td>" for cell in row) + "</tr>"
            for row in rows
        )
        return f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>"

    collection = report["collection"]
    circulation = report["circulation"]
    buckets = report["age_analysis"]["buckets"]
    sections = [
        f"""<h2>{_esc(school_name)} · Yıl Sonu Kütüphane Raporu</h2>
<p class="ipucu">Dönem: {_esc(start)} → {_esc(end)}</p>""",
        "<h3>Koleksiyon</h3>"
        + table(
            ["Eser", "Baskı", "Nüsha", "Dönemde Eklenen"],
            [[collection["works"], collection["editions"], collection["copies"],
              collection["copies_added"]]],
        ),
        "<h3>Dolaşım</h3>"
        + table(
            ["Ödünç", "İade", "Okuyan Üye"],
            [[circulation["loans"], circulation["returns"], circulation["readers"]]],
        ),
        "<h3>Aylık Ödünç</h3>"
        + table(["Ay", "Ödünç"], [[m["month"], m["loans"]] for m in report["monthly"]]),
        "<h3>En Çok Okunan 10 Kitap</h3>"
        + table(
            ["Kitap", "Ödünç", "Farklı Okur"],
            [[b["title"], b["loan_count"], b["reader_count"]] for b in report["top_books"]],
        ),
        "<h3>En Çok Okuyan 10 Üye</h3>"
        + table(
            ["Üye", "Sınıf", "Ödünç"],
            [[r["member_name"], r["class_name"] or "—", r["loan_count"]]
             for r in report["top_readers"]],
        ),
        "<h3>Sınıf Bazında</h3>"
        + table(
            ["Sınıf", "Ödünç", "Okuyan"],
            [[c["class_name"], c["loan_count"], c["reader_count"]]
             for c in report["by_class"]],
        ),
        "<h3>Kategori Dağılımı</h3>"
        + table(
            ["Kategori", "Baskı"],
            [[c["category"], c["n"]] for c in report["categories"]],
        ),
        "<h3>Koleksiyon Yaş Analizi</h3>"
        + table(
            ["0-4 yaş", "5-9 yaş", "10-19 yaş", "20+ yaş", "Yılı bilinmeyen"],
            [[buckets["0-4"], buckets["5-9"], buckets["10-19"], buckets["20+"],
              report["age_analysis"]["unknown"]]],
        ),
        "<h3>Düşüm Özeti</h3>"
        + (
            table(["Sebep", "Adet"], [[d["reason"], d["n"]] for d in report["discards"]])
            if report["discards"]
            else '<p class="ipucu">Dönemde düşüm yok.</p>'
        ),
    ]
    body = f'<section class="defter">{"".join(sections)}</section>'
    return _page("Yıl Sonu Raporu", body)


@router.get("/print/labels")
def print_labels(
    request: Request,
    scope: str = Query(default="all", pattern="^(all|location|edition)$"),
    location: str = "",
    edition_id: int | None = None,
) -> HTMLResponse:
    state = _state(request)
    clause, parameters = "", []
    if scope == "location":
        if not location.strip():
            raise HTTPException(status_code=400, detail="location gerekli")
        clause = "AND c.location = ?"
        parameters = [location.strip()]
    elif scope == "edition":
        if not edition_id:
            raise HTTPException(status_code=400, detail="edition_id gerekli")
        clause = "AND c.edition_id = ?"
        parameters = [edition_id]
    rows = state.database.fetchall(
        f"""
        SELECT c.inventory_code, c.location, e.title
        FROM copy AS c JOIN edition AS e ON e.id = c.edition_id
        WHERE c.status = 'active' AND c.inventory_code IS NOT NULL
          AND c.inventory_code <> '' {clause}
        ORDER BY e.title COLLATE NOCASE, c.inventory_code
        """,
        parameters,
    )
    missing = state.database.fetchone(
        f"""
        SELECT COUNT(*) FROM copy AS c
        WHERE c.status = 'active'
          AND (c.inventory_code IS NULL OR c.inventory_code = '') {clause}
        """,
        parameters,
    )
    missing_count = int(missing[0]) if missing else 0

    notes = []
    if missing_count:
        notes.append(
            f"⚠️ Kapsamda demirbaş numarası olmayan {missing_count} nüsha var; "
            'Yazdır sayfasındaki "Kod ver" adımından sonra yeniden basın.'
        )
    truncated = len(rows) > _MAX_LABELS
    if truncated:
        notes.append(
            f"⚠️ {len(rows)} etiketten ilk {_MAX_LABELS} tanesi basılıyor; "
            "kalanı dolap kapsamıyla parça parça yazdırın."
        )
        rows = rows[:_MAX_LABELS]
    labels_parts: list[str] = []
    unencodable: list[str] = []
    for row in rows:
        try:
            barcode = barcode_svg(row["inventory_code"], module=1.6, height=34)
        except ValueError:
            # Tek bozuk kod (örn. Türkçe harf) bütün sayfayı düşürmesin.
            unencodable.append(str(row["inventory_code"]))
            continue
        labels_parts.append(
            f"""<div class="etiket">
<div class="etiket-baslik">{_esc(_shorten(row["title"]))}</div>
{barcode}
{f'<div class="etiket-konum">{_esc(row["location"])}</div>' if row["location"] else ""}
</div>"""
        )
    if unencodable:
        sample = ", ".join(unencodable[:3])
        notes.append(
            f"⚠️ {len(unencodable)} nüshanın kodu barkoda çevrilemeyen karakter "
            f"içeriyor ve atlandı (örn. {sample}). Kodlarda yalnız rakam/İngilizce "
            "harf kullanın."
        )
    labels = "".join(labels_parts)
    note_html = "".join(f'<p class="uyari">{_esc(note)}</p>' for note in notes)
    body = f"""{note_html}
<div class="etiket-sayfa">{labels}</div>
{'<p class="uyari">Basılacak etiket yok.</p>' if not labels_parts else ''}"""
    return _page("Demirbaş Etiketleri", body)


@router.get("/print/member-cards")
def print_member_cards(
    request: Request,
    class_name: str = "",
    member_type: str = Query(default="", pattern="^(student|staff)?$"),
) -> HTMLResponse:
    state = _state(request)
    school_name = state.settings.get("school_name") or "Okul Kütüphanesi"
    items, _total = state.members.search(
        "",
        class_name=class_name.strip() or None,
        member_type=member_type or None,
        active=True,
        limit=_MAX_CARDS,
        offset=0,
    )
    numbered = [member for member in items if member.school_number]
    skipped = len(items) - len(numbered)
    card_parts: list[str] = []
    unencodable: list[str] = []
    for member in numbered:
        try:
            barcode = barcode_svg(member.school_number, module=1.8, height=38)
        except ValueError:
            unencodable.append(member.school_number)
            continue
        card_parts.append(
            f"""<div class="kart">
<div class="kart-okul">{_esc(school_name)}</div>
<div class="kart-ad">{_esc(member.full_name)}</div>
<div class="kart-sinif">{_esc(member.class_name or ("Personel" if member.member_type == "staff" else ""))}</div>
{barcode}
</div>"""
        )
    cards = "".join(card_parts)
    notes = []
    if skipped:
        notes.append(f"⚠️ Okul numarası olmayan {skipped} üye atlandı.")
    if unencodable:
        notes.append(
            f"⚠️ {len(unencodable)} üyenin numarası barkoda çevrilemeyen karakter "
            f"içeriyor ve atlandı (örn. {', '.join(unencodable[:3])})."
        )
    if len(items) == _MAX_CARDS:
        notes.append(
            f"⚠️ Tek koşuda en çok {_MAX_CARDS} kart basılır; sınıf seçerek daraltın."
        )
    note_html = "".join(f'<p class="uyari">{_esc(note)}</p>' for note in notes)
    body = f"""{note_html}
<div class="kart-sayfa">{cards}</div>
{'<p class="uyari">Basılacak kart yok.</p>' if not card_parts else ''}"""
    return _page("Üye Kartları", body)


@router.get("/print/overdue")
def print_overdue(request: Request) -> HTMLResponse:
    state = _state(request)
    now = datetime.now(UTC)
    today = now.date().isoformat()
    records = state.loans.list_overdue()
    groups: dict[str, list[Any]] = {}
    for record in records:
        key = record.member_class or (
            "Personel" if record.member_type == "staff" else "Sınıfsız"
        )
        groups.setdefault(key, []).append(record)

    sections = []
    for class_name in sorted(groups):
        rows = "".join(
            f"""<tr>
<td>{_esc(record.member_name)}</td>
<td>{_esc(record.member_number or "—")}</td>
<td>{_esc(record.title_snapshot)}</td>
<td>{_esc(record.due_at)}</td>
<td class="sag">{record.days_overdue(now)} gün</td>
</tr>"""
            for record in sorted(groups[class_name], key=lambda item: item.member_name)
        )
        sections.append(
            f"""<section class="sinif-blok">
<h2>{_esc(class_name)} — Gecikmiş Kitap Listesi</h2>
<p class="ipucu">Tarih: {_esc(today)} · Sınıf öğretmenine teslim içindir.</p>
<table>
<thead><tr><th>Öğrenci</th><th>No</th><th>Kitap</th><th>Son Gün</th><th class="sag">Gecikme</th></tr></thead>
<tbody>{rows}</tbody>
</table>
</section>"""
        )
    body = (
        "".join(sections)
        if sections
        else '<p class="uyari">Gecikmiş kitap yok. 🎉</p>'
    )
    return _page("Gecikme Listeleri", body)


@router.get("/print/letters")
def print_letters(
    request: Request,
    kind: str = Query("overdue"),
    member_id: int | None = Query(None, ge=1),
) -> HTMLResponse:
    """Veli mektupları: e-posta gönderilemeyen çevrimdışı kurulumda kâğıt kanal.

    ``member_id`` verilirse tek mektup, verilmezse geciken her üye için bir
    mektup (sayfa başına bir üye) basılır.
    """

    if kind != "overdue":
        raise HTTPException(status_code=400, detail="Bilinmeyen mektup türü")
    state = _state(request)
    now = datetime.now(UTC)
    today = now.date().strftime("%d.%m.%Y")
    school_name = state.settings.get("school_name") or "Okul Kütüphanesi"

    by_member: dict[int, list[Any]] = {}
    for record in state.loans.list_overdue():
        if member_id is not None and record.member_id != member_id:
            continue
        by_member.setdefault(record.member_id, []).append(record)
    if member_id is not None and not by_member:
        raise HTTPException(status_code=404, detail="Bu üyenin geciken kitabı yok")

    letters = []
    for records in by_member.values():
        first = records[0]
        rows = "".join(
            f"""<tr>
<td>{_esc(record.title_snapshot)}</td>
<td>{_esc(record.inventory_code_snapshot or "—")}</td>
<td>{_esc(record.due_at)}</td>
<td class="sag">{record.days_overdue(now)} gün</td>
</tr>"""
            for record in sorted(records, key=lambda item: item.due_at)
        )
        class_line = f" ({_esc(first.member_class)})" if first.member_class else ""
        letters.append(
            f"""<section class="mektup">
<h2>{_esc(school_name)}</h2>
<p class="mektup-tarih">Tarih: {_esc(today)}</p>
<p>Sayın Velimiz,</p>
<p>Öğrencimiz <strong>{_esc(first.member_name)}</strong>{class_line} adına okul
kütüphanemizden ödünç alınan aşağıdaki kitapların iade süresi geçmiştir.
Kitapların en kısa sürede kütüphanemize teslim edilmesini rica ederiz.</p>
<table>
<thead><tr><th>Kitap</th><th>Demirbaş No</th><th>Son Gün</th><th class="sag">Gecikme</th></tr></thead>
<tbody>{rows}</tbody>
</table>
<p>Gösterdiğiniz ilgi ve iş birliği için teşekkür ederiz.</p>
<div class="mektup-imza">
  <div>Kütüphane Sorumlusu</div>
  <div class="imza-cizgi">İmza</div>
</div>
</section>"""
        )
    body = (
        "".join(letters)
        if letters
        else '<p class="uyari">Gecikmiş kitap yok; mektup gerekmiyor. 🎉</p>'
    )
    return _page("Veli Mektupları", body)
