// Sayım: oturum yönetimi, barkodla okutma, canlı ilerleme, rapor + Excel.

import { api, pollJob } from "../api.js";
import { confirmBox, debounce, esc, show, toast } from "../ui.js";
import { attachScanner } from "../scanner.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");

let bound = false;
let activeSession = null;
let manualSearchController = null;

const TYPE_LABELS = { isbn: "ISBN", inventory: "Demirbaş", manual: "Elle", unresolved: "⚠️ Eşleşmedi" };

async function refreshSessions() {
  const sessions = await api.get("/api/stocktake/sessions");
  const open = sessions.filter((session) => session.status === "open");
  const closed = sessions.filter((session) => session.status !== "open").slice(0, 8);
  $("sy-oturum-liste").innerHTML =
    (open.length > 0
      ? `<h2>Açık Oturumlar</h2>` +
        open
          .map(
            (session) => `
            <div class="card oturum-satir">
              <strong>${esc(session.name)}</strong>
              <span class="hint">${esc(session.scope_location || "Tüm kütüphane")} · ${session.started_at.slice(0, 10)}</span>
              <button class="btn btn-primary" data-devam="${session.id}">Devam Et</button>
            </div>`
          )
          .join("")
      : "") +
    (closed.length > 0
      ? `<h2>Kapanmış Oturumlar</h2>` +
        closed
          .map(
            (session) => `
            <div class="card oturum-satir">
              <strong>${esc(session.name)}</strong>
              <span class="hint">${session.started_at.slice(0, 10)} → ${session.closed_at ? session.closed_at.slice(0, 10) : ""}</span>
              <button class="btn" data-rapor="${session.id}">Rapor</button>
            </div>`
          )
          .join("")
      : "");
}

async function openSession(sessionId) {
  const session = await api.get(`/api/stocktake/sessions/${sessionId}`);
  activeSession = session;
  $("sy-aktif-baslik").textContent =
    `${session.name} — ${session.scope_location || "Tüm kütüphane"}`;
  show($("sy-aktif-kart"), true);
  show($("sy-rapor-kart"), false);
  renderProgress(session.progress);
  renderRecent(session.recent);
  $("sy-kod").focus();
}

function renderProgress(progress) {
  $("sy-ilerleme").value = progress.percent;
  $("sy-ilerleme-metin").textContent =
    `${progress.scanned} / ${progress.expected_on_shelf} nüsha okutuldu (%${progress.percent})` +
    (progress.on_loan > 0 ? ` · ${progress.on_loan} nüsha ödünçte` : "");
}

function renderRecent(items) {
  $("sy-son-liste").innerHTML = (items || [])
    .map(
      (scan) => `
      <tr class="${scan.code_type === "unresolved" ? "geciken-satir" : ""}">
        <td>${esc(scan.raw_code)}</td>
        <td>${esc(scan.title || "—")}</td>
        <td>${TYPE_LABELS[scan.code_type] || scan.code_type}</td>
        <td><button class="btn" data-gerial="${scan.scan_id}">Geri Al</button></td>
      </tr>`
    )
    .join("");
}

async function handleScan(code, { repeat } = {}) {
  if (!activeSession) return;
  try {
    const result = await api.post(`/api/stocktake/sessions/${activeSession.id}/scans`, { code });
    renderProgress(result.progress);
    const box = $("sy-son-mesaj");
    if (result.duplicate) {
      box.innerHTML = `<p class="uyari-metin">⚠️ ${esc(result.title || code)} — bu demirbaş bu oturumda ZATEN okutuldu; ikinci okutma sayılmadı.</p>`;
      return;
    }
    if (result.out_of_scope) {
      box.innerHTML = `<p class="uyari-metin">⚠️ ${esc(result.title || code)} bu rafa değil "${esc(result.copy_location || "?")}" konumuna kayıtlı; okutma bu oturuma sayılmadı.</p>`;
      return;
    }
    if (result.code_type === "unresolved") {
      box.innerHTML = `<p class="uyari-metin">⚠️ "${esc(code)}" eşleşmedi — kayıt yine tutuldu, raporda görünecek.</p>`;
    } else {
      const extra = repeat ? " <strong>(az önce de okutuldu!)</strong>" : "";
      const durum =
        result.surplus > 0
          ? ` — beklenenden fazla (${result.scanned}/${result.expected - result.on_loan})`
          : ` — ${result.scanned}/${result.expected - result.on_loan}`;
      box.innerHTML = `<p>✓ ${esc(result.title || code)}${durum}${extra}</p>`;
    }
    const detail = await api.get(`/api/stocktake/sessions/${activeSession.id}`);
    renderRecent(detail.recent);
  } catch (error) { err(error); }
}

async function manualSearch() {
  manualSearchController?.abort();
  const controller = new AbortController();
  manualSearchController = controller;
  const query = $("sy-elle-ara").value.trim();
  const list = $("sy-elle-sonuc");
  if (query.length < 2) { show(list, false); return; }
  let data;
  try {
    data = await api.get(`/api/books?q=${encodeURIComponent(query)}&limit=6`, {
      signal: controller.signal,
    });
  } catch (error) {
    if (error.name === "AbortError") return;
    throw error;
  }
  list.innerHTML = (data.items || [])
    .map(
      (book) => `
      <li data-edition="${book.edition_id}" tabindex="0" role="button" data-key-activate
          aria-label="${esc(book.title)} kitabını elle işaretle">
        <strong>${esc(book.title)}</strong>
        <span class="src">${esc(book.authors || "—")}</span>
      </li>`
    )
    .join("");
  show(list, true);
}

async function markManually(editionId) {
  show($("sy-elle-sonuc"), false);
  $("sy-elle-ara").value = "";
  try {
    const result = await api.post(`/api/stocktake/sessions/${activeSession.id}/scans`, {
      code: "",
      manual_edition_id: editionId,
    });
    renderProgress(result.progress);
    toast(`✓ ${result.title} elle işaretlendi`, "success");
    const detail = await api.get(`/api/stocktake/sessions/${activeSession.id}`);
    renderRecent(detail.recent);
  } catch (error) { err(error); }
}

async function showReport(sessionId) {
  const report = await api.get(`/api/stocktake/sessions/${sessionId}/report`);
  activeSession = activeSession && activeSession.id === sessionId ? activeSession : { id: sessionId };
  const totals = report.totals;
  $("sy-rapor-ozet").innerHTML =
    `<strong>${esc(report.session.name)}</strong> · ${esc(report.session.scope_location || "Tüm kütüphane")} · ` +
    `Beklenen ${totals.expected} · Ödünçte ${totals.on_loan} · Okutulan ${totals.scanned} · ` +
    `<span class="geciken">Eksik ${totals.missing}</span> · Fazla ${totals.surplus} · ` +
    `Elle sayım ${totals.manual_check} · Eşleşmeyen ${totals.unresolved}` +
    `<br><small class="hint">Rapor anındaki katalog durumuna göre: ${report.generated_at.slice(0, 16).replace("T", " ")}</small>`;

  const rows = (lines, cols) =>
    lines.map((line) => `<tr>${cols.map((col) => `<td>${esc(String(line[col] ?? "—"))}</td>`).join("")}</tr>`).join("");
  const missing = report.lines.filter((line) => line.missing > 0);
  const surplus = report.lines.filter((line) => line.surplus > 0);
  let html = "";
  if (missing.length > 0) {
    html += `<h3>Eksikler (${missing.length})</h3>
      <table class="data-table"><thead><tr><th>Kitap</th><th>Beklenen</th><th>Ödünçte</th><th>Okutulan</th><th>Eksik</th></tr></thead>
      <tbody>${rows(missing, ["title", "expected", "on_loan", "scanned", "missing"])}</tbody></table>`;
  }
  if (surplus.length > 0) {
    html += `<h3>Fazlalar (${surplus.length})</h3>
      <table class="data-table"><thead><tr><th>Kitap</th><th>Beklenen</th><th>Okutulan</th><th>Fazla</th></tr></thead>
      <tbody>${rows(surplus, ["title", "expected", "scanned", "surplus"])}</tbody></table>`;
  }
  if (report.manual_check.length > 0) {
    html += `<h3>Elle sayım gerekir — ISBN'siz (${report.manual_check.length})</h3>
      <table class="data-table"><thead><tr><th>Kitap</th><th>Beklenen</th></tr></thead>
      <tbody>${rows(report.manual_check, ["title", "expected"])}</tbody></table>`;
  }
  if (report.unresolved.length > 0) {
    html += `<h3>Eşleşmeyen okutmalar (${report.unresolved.length})</h3>
      <table class="data-table"><thead><tr><th>Kod</th><th>Zaman</th></tr></thead>
      <tbody>${rows(report.unresolved, ["raw_code", "created_at"])}</tbody></table>`;
  }
  if (!html) html = "<p>🎉 Eksik yok, fazla yok — sayım temiz.</p>";
  $("sy-rapor-icerik").innerHTML = html;
  $("sy-excel").dataset.session = sessionId;
  const transfer = $("sy-dusum-aktar");
  transfer.dataset.session = sessionId;
  transfer.dataset.missing = totals.missing;
  // Toplu düşüm yalnız KAPALI oturumda (açıkken rapor değişmeye devam eder).
  show(transfer, totals.missing > 0 && report.session.status === "closed");
  show($("sy-rapor-kart"), true);
}

function bind() {
  if (bound) return;
  bound = true;

  $("sy-baslat").addEventListener("click", async () => {
    try {
      const session = await api.post("/api/stocktake/sessions", {
        name: $("sy-ad").value,
        scope_location: $("sy-kapsam").value,
      });
      $("sy-ad").value = "";
      toast("Sayım oturumu açıldı ✓", "success");
      await refreshSessions();
      await openSession(session.id);
    } catch (error) { err(error); }
  });

  $("sy-oturum-liste").addEventListener("click", (event) => {
    const devam = event.target.dataset.devam;
    const rapor = event.target.dataset.rapor;
    if (devam) openSession(Number(devam)).catch(err);
    if (rapor) showReport(Number(rapor)).catch(err);
  });

  attachScanner($("sy-kod"), handleScan, { refocus: false });
  $("sy-elle-ara").addEventListener("input", debounce(() => manualSearch().catch(err), 250));
  $("sy-elle-sonuc").addEventListener("click", (event) => {
    const item = event.target.closest("li[data-edition]");
    if (item) markManually(Number(item.dataset.edition)).catch(err);
  });

  $("sy-son-liste").addEventListener("click", async (event) => {
    const scanId = event.target.dataset.gerial;
    if (!scanId) return;
    try {
      await api.del(`/api/stocktake/scans/${scanId}`);
      toast("Okutma geri alındı", "success");
      await openSession(activeSession.id);
    } catch (error) { err(error); }
  });

  $("sy-kapat").addEventListener("click", async () => {
    if (!activeSession) return;
    if (!(await confirmBox("Sayım oturumu kapatılacak; artık okutma yapılamaz. Emin misiniz?"))) return;
    try {
      await api.post(`/api/stocktake/sessions/${activeSession.id}/close`);
      toast("Oturum kapatıldı ✓", "success");
      show($("sy-aktif-kart"), false);
      await refreshSessions();
      await showReport(activeSession.id);
    } catch (error) { err(error); }
  });

  $("sy-dusum-aktar").addEventListener("click", async (event) => {
    const sessionId = Number(event.target.dataset.session);
    const missing = event.target.dataset.missing;
    const message =
      `${missing} eksik nüsha 'Kayıp' gerekçesiyle demirbaştan düşülecek ve deftere ` +
      `işlenecek. (Düşüm sayfasından tek tek geri alınabilir.) Emin misiniz?`;
    if (!(await confirmBox(message))) return;
    try {
      const result = await api.post("/api/discards/bulk-from-stocktake", { session_id: sessionId });
      toast(`${result.discarded} nüsha düşüme aktarıldı ✓`, "success");
      if (result.errors?.length) toast(result.errors.join(" · "), "error", 6000);
      await showReport(sessionId);
    } catch (error) { err(error); }
  });

  $("sy-rapor").addEventListener("click", () => activeSession && showReport(activeSession.id).catch(err));
  $("sy-rapor-kapat").addEventListener("click", () => show($("sy-rapor-kart"), false));

  $("sy-excel").addEventListener("click", async (event) => {
    const sessionId = event.target.dataset.session;
    if (!sessionId) return;
    try {
      await api.post(`/api/stocktake/sessions/${sessionId}/export`);
      toast("Excel hazırlanıyor…");
      const done = await pollJob("/api/exports/status", { field: "export" });
      if (done?.status === "succeeded" && done.result?.download) {
        window.location.href = `/api/exports/download/${done.result.download}`;
      } else if (done?.error) {
        toast(done.error, "error", 6000);
      }
    } catch (error) { err(error); }
  });
}

export function enter() {
  bind();
  refreshSessions().catch(err);
}

export function leave() {
  manualSearchController?.abort();
}
