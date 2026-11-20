// Onay Merkezi: eşleştirme onayı + kitap bilgisi incelemesi + kalibrasyon.

import { api } from "../api.js";
import {
  bindTabs, confirmBox, esc, fillForm, formSnapshot, openLightbox, readForm, show, toast,
} from "../ui.js";
import { refreshDatalists } from "../main.js";

const $ = (id) => document.getElementById(id);
let bound = false;
let pollTimer = null;
let reviewItems = [];
let activeReviewId = null;
let reviewBaseline = "";
let audioPlayer = null;
let pollBusy = false;
let onayTabs = null;

const err = (error) => toast(error.message || String(error), "error");
const FACE_LABELS = { front: "Ön", front_inside: "Ön iç", back_inside: "Arka iç", back: "Arka" };

// ── Eşleştirme onayı ─────────────────────────────────

async function refreshPairs() {
  const items = await api.get("/api/pair-reviews");
  $("eslesme-sayi").textContent = items.length;
  show($("eslesme-sayi"), items.length > 0);
  show($("eslesme-bos"), items.length === 0);
  $("eslesme-liste").innerHTML = items
    .map(
      (item) => `
      <div class="pair-card" data-item="${item.id}">
        <div class="card-head">
          <h2>${esc(item.pair_key)}</h2>
          <div class="btn-group">
            <button class="btn btn-primary" data-decide="1" data-item="${item.id}">Onayla ✓</button>
            <button class="btn btn-danger" data-decide="0" data-item="${item.id}">Reddet ✕</button>
          </div>
        </div>
        <div class="pair-covers">${Object.entries(FACE_LABELS)
          .filter(([face]) => item.faces[face])
          .map(
            ([face, label]) => `
            <figure>
              <button type="button" class="cover-button" data-full="/api/items/${item.id}/image/${face}"
                      aria-label="${label} yüzünü büyüt">
                <img src="/api/items/${item.id}/image/${face}?thumb=1" alt="${label}">
              </button>
              <figcaption>${label}<br><small>${esc(item.faces[face])}</small></figcaption>
            </figure>`
          )
          .join("")}</div>
        <p class="pair-meta">Yöntem: ${esc(item.pairing_basis)} · Güven: %${Math.round(item.pairing_confidence * 100)}</p>
      </div>`
    )
    .join("");
  $("eslesme-liste").querySelectorAll(".cover-button").forEach((button) =>
    button.addEventListener("click", () => openLightbox(button.dataset.full, button.querySelector("img").alt))
  );
}

async function decidePair(itemId, approved) {
  if (!approved && !(await confirmBox("Eşleştirme reddedilecek ve öğe hata kuyruğuna düşecek. Emin misiniz?"))) return;
  await api.post(`/api/pair-reviews/${itemId}`, { approved });
  toast(approved ? "Eşleştirme onaylandı ✓" : "Eşleştirme reddedildi", "success");
  refreshPairs().catch(err);
}

// ── Bilgi incelemesi ─────────────────────────────────

const REVIEW_PAGE = 50;
let reviewOffset = 0;

async function refreshReviewList({ autoOpen = true } = {}) {
  let data = await api.get(`/api/review/books?limit=${REVIEW_PAGE}&offset=${reviewOffset}`);
  // Sayfanın son kaydı onaylanınca boş sayfada kalma; bir sayfa geri çekil.
  if (data.items.length === 0 && reviewOffset > 0) {
    reviewOffset = Math.max(0, Math.min(reviewOffset - REVIEW_PAGE, (Math.ceil(data.total / REVIEW_PAGE) - 1) * REVIEW_PAGE));
    data = await api.get(`/api/review/books?limit=${REVIEW_PAGE}&offset=${reviewOffset}`);
  }
  reviewItems = data.items;
  const total = data.total ?? data.count;
  $("bilgi-sayi").textContent = total;
  show($("bilgi-sayi"), total > 0);
  show($("bilgi-bos"), total === 0);
  show($("bilgi-sayfalama"), total > REVIEW_PAGE);
  $("bilgi-sayfa-bilgi").textContent =
    total === 0 ? "" : `${reviewOffset + 1}–${Math.min(reviewOffset + REVIEW_PAGE, total)} / ${total}`;
  $("bilgi-sayfa-geri").disabled = reviewOffset === 0;
  $("bilgi-sayfa-ileri").disabled = reviewOffset + REVIEW_PAGE >= total;
  $("bilgi-liste").innerHTML = reviewItems
    .map(
      (book) => `
      <li data-id="${book.edition_id}" class="${book.edition_id === activeReviewId ? "active" : ""}"
          tabindex="0" role="button" data-key-activate aria-label="${esc(book.title)} kaydını incele">
        <strong>${esc(book.title)}</strong><br>
        <span class="src">${esc(book.authors || "—")} · ${book.source}</span>
      </li>`
    )
    .join("");
  if (autoOpen && !activeReviewId && reviewItems.length > 0) openReview(reviewItems[0].edition_id);
  if (reviewItems.length === 0) show($("bilgi-detay"), false);
}

async function openReview(editionId) {
  if (activeReviewId && editionId !== activeReviewId && !(await canLeave())) return false;
  const book = await api.get(`/api/review/${editionId}`);
  activeReviewId = editionId;
  $("bilgi-liste").querySelectorAll("li").forEach((li) =>
    li.classList.toggle("active", Number(li.dataset.id) === editionId)
  );
  const covers = $("bilgi-kapaklar");
  covers.innerHTML = Object.entries(FACE_LABELS)
    .filter(([face]) => book.covers[face])
    .map(
      ([face, label]) => `
      <figure>
        <button type="button" class="cover-button" data-full="/api/books/${editionId}/cover/${face}"
                aria-label="${label} kapağı büyüt">
          <img src="/api/books/${editionId}/cover/${face}?thumb=1" alt="${label}">
        </button>
        <figcaption>${label}</figcaption>
      </figure>`
    )
    .join("");
  covers.querySelectorAll(".cover-button").forEach((button) =>
    button.addEventListener("click", () => openLightbox(button.dataset.full, button.querySelector("img").alt))
  );
  const voiceBox = $("bilgi-ses");
  if (book.voice) {
    $("bilgi-transkript").textContent = book.voice.transcript || "";
    show(voiceBox, true);
  } else show(voiceBox, false);
  fillForm($("bilgi-form"), book);
  renderReasons(book.review_reasons);
  renderFieldAlternatives(book.field_alternatives);
  renderIsbnEvidence(book.isbn_evidence);
  reviewBaseline = formSnapshot($("bilgi-form"));
  show($("bilgi-detay"), true);
  return true;
}

// ── Kanıt gösterimi: sebep çipleri, alan/ISBN alternatifleri, span önizleme ──

function renderReasons(reasons) {
  const box = $("bilgi-sebepler");
  show(box, Boolean(reasons && reasons.length));
  box.innerHTML = (reasons || [])
    .map((reason) => `<span class="rapor-rozet uyari">${esc(reason)}</span>`)
    .join("");
}

function altButtonsHtml(fieldKey, alternatives) {
  return alternatives
    .map((alt) => {
      const pct = alt.confidence != null ? `%${Math.round(alt.confidence * 100)}` : "";
      const label = FACE_LABELS[alt.cover_role] || alt.source_label || "";
      const engines = (alt.engine_evidence || []).join(", ");
      const meta = [pct, engines, label].filter(Boolean).join(" · ");
      const cls = alt.conflict ? "field-alt-btn conflict" : "field-alt-btn";
      const preview = alt.has_polygon
        ? `<button type="button" class="field-alt-preview" data-preview="${esc(alt.span_id)}"
                   data-label="${esc(label || "Kanıt")}" aria-label="Kanıtı büyüt">🔍</button>`
        : "";
      return `<span class="field-alt-item">
        <button type="button" class="${cls}" data-alt-field="${esc(fieldKey)}" data-alt-value="${esc(alt.value)}">
          ${esc(alt.value)}${meta ? ` <small>${esc(meta)}</small>` : ""}
        </button>${preview}
      </span>`;
    })
    .join("");
}

function clearFieldAlternatives() {
  $("bilgi-form").querySelectorAll(".field-alt[data-dynamic]").forEach((el) => el.remove());
}

function renderFieldAlternatives(fieldAlternatives) {
  clearFieldAlternatives();
  for (const [key, alternatives] of Object.entries(fieldAlternatives || {})) {
    if (!alternatives.length) continue;
    const input = $("bilgi-form").elements[key];
    if (!input) continue;
    const span = document.createElement("span");
    span.className = "field-alt";
    span.dataset.dynamic = "1";
    span.innerHTML = altButtonsHtml(key, alternatives);
    input.insertAdjacentElement("afterend", span);
  }
}

function renderIsbnEvidence(isbnEvidence) {
  $("bilgi-isbn-kanit").innerHTML =
    isbnEvidence && isbnEvidence.length ? altButtonsHtml("isbn", isbnEvidence) : "";
}

export function isDirty() {
  return Boolean(
    activeReviewId && !$("bilgi-detay").hidden && reviewBaseline &&
    reviewBaseline !== formSnapshot($("bilgi-form"))
  );
}

export function canLeave() {
  if (!isDirty()) return Promise.resolve(true);
  return confirmBox("İnceleme formunda kaydedilmemiş değişiklikler var. Vazgeçilsin mi?");
}

async function saveReviewAndNext() {
  if (!activeReviewId) return;
  const values = readForm($("bilgi-form"));
  const payload = { changes: { ...values }, isbn: values.isbn, location: values.location, approve: true };
  delete payload.changes.isbn;
  delete payload.changes.location;
  await api.post(`/api/review/${activeReviewId}/save`, payload);
  toast("Kaydedildi ve onaylandı ✓", "success");
  const index = reviewItems.findIndex((book) => book.edition_id === activeReviewId);
  activeReviewId = null;
  reviewBaseline = "";
  await refreshReviewList({ autoOpen: false });
  refreshCalibration().catch(() => {});
  refreshDatalists();
  // Sıradaki kayda geç (liste yenilendi; aynı konumdaki sonraki öğe).
  if (reviewItems.length > 0) {
    const next = reviewItems[Math.min(index, reviewItems.length - 1)];
    openReview(next.edition_id).catch(err);
  } else {
    show($("bilgi-detay"), false);
  }
}

// ── Dış öneriler ──────────────────────────────────────

let externalSuggestions = [];
const SUGGESTION_FIELD_MAP = { title: "title", publisher: "publisher", publication_date: "publication_date", page_count: "page_count", language: "language" };

function suggestionFieldsHtml(payload) {
  const items = Object.entries(SUGGESTION_FIELD_MAP)
    .filter(([key]) => payload[key])
    .map(([key]) => `<li>${esc(key)}: <strong>${esc(payload[key])}</strong></li>`);
  if (payload.authors?.length) items.unshift(`<li>authors: <strong>${esc(payload.authors.join("; "))}</strong></li>`);
  return items.join("");
}

async function refreshExternalSuggestions() {
  externalSuggestions = await api.get("/api/external-suggestions?status=pending");
  $("disoneri-sayi").textContent = externalSuggestions.length;
  show($("disoneri-sayi"), externalSuggestions.length > 0);
  show($("disoneri-bos"), externalSuggestions.length === 0);
  $("disoneri-liste").innerHTML = externalSuggestions
    .map(
      (item) => `
      <div class="card oneri-kart" data-id="${item.id}">
        <div class="oneri-govde">
          <div class="card-head">
            <h3>${esc(item.matched_title || `ISBN ${item.isbn13}`)}</h3>
            <span class="badge badge-info">dış kaynak · ${esc(item.source)}</span>
          </div>
          <p class="hint">ISBN ${esc(item.isbn13)}${item.matched_title ? " · katalogla eşleşti" : " · katalogda eşleşme yok"}</p>
          <ul class="oneri-alan-liste">${suggestionFieldsHtml(item.payload || {})}</ul>
          <div class="btn-group">
            ${item.edition_id ? `<button class="btn btn-primary" data-oneri-doldur="${item.id}">İncelemede doldur</button>` : ""}
            <button class="btn" data-oneri-reddet="${item.id}">Reddet</button>
          </div>
        </div>
      </div>`
    )
    .join("");
}

async function fillReviewFromSuggestion(suggestionId) {
  const suggestion = externalSuggestions.find((item) => item.id === suggestionId);
  if (!suggestion?.edition_id) return;
  onayTabs?.select($("onay-tab-bilgi"), { focus: true });
  const opened = await openReview(suggestion.edition_id);
  if (!opened) return;
  const form = $("bilgi-form");
  const payload = suggestion.payload || {};
  for (const [source, field] of Object.entries(SUGGESTION_FIELD_MAP)) {
    const input = form.elements[field];
    if (input && payload[source] && !input.value) input.value = payload[source];
  }
  toast("Öneri değerleri forma dolduruldu; gözden geçirip kaydedin.");
}

async function dismissSuggestion(suggestionId) {
  await api.post(`/api/external-suggestions/${suggestionId}/dismiss`);
  refreshExternalSuggestions().catch(err);
}

// ── Başarısız öğeler ─────────────────────────────────

async function refreshFailedItems() {
  const jobs = await api.get("/api/imports");
  const withFailures = jobs.filter((job) => job.failed_items > 0);
  show($("bilgi-basarisiz-bos"), withFailures.length === 0);
  if (withFailures.length === 0) {
    $("bilgi-basarisiz-liste").innerHTML = "";
    return;
  }
  const details = await Promise.all(withFailures.map((job) => api.get(`/api/imports/${job.id}`)));
  $("bilgi-basarisiz-liste").innerHTML = details
    .map(
      (detail) => `
      <div class="basarisiz-oge" data-job="${detail.job.id}">
        <div class="card-head">
          <h3>${esc(detail.job.name)}</h3>
          <button class="btn" data-retry-all="${detail.job.id}">Bütün hatalıları yeniden dene</button>
        </div>
        ${detail.failed_items
          .map(
            (item) => `
          <div class="basarisiz-oge-satir">
            <span>${esc(item.pair_key)} <span class="hata">— ${esc(item.last_error || "")}</span></span>
            <button class="btn" data-retry="${item.id}">Yeniden dene</button>
          </div>`
          )
          .join("")}
      </div>`
    )
    .join("");
}

async function retryFailedItem(itemId) {
  await api.post(`/api/imports/items/${itemId}/retry`);
  toast("Öğe yeniden kuyruğa alındı", "success");
  refreshFailedItems().catch(err);
}

async function retryAllFailed(jobId) {
  const result = await api.post(`/api/imports/${jobId}/retry-failed`);
  toast(`${result.requeued} öğe yeniden kuyruğa alındı`, "success");
  refreshFailedItems().catch(err);
}

// ── Kalibrasyon ──────────────────────────────────────

async function refreshCalibration() {
  const status = await api.get("/api/calibration/status");
  $("calib-bar").max = status.minimum_samples;
  $("calib-bar").value = Math.min(status.label_count, status.minimum_samples);
  const enough = status.label_count >= status.minimum_samples;
  $("calib-metin").textContent = enough
    ? `${status.label_count} örnek hazır${status.profile_trusted ? " · profil etkin ✓" : ""}`
    : `${status.label_count} / ${status.minimum_samples} örnek`;
  $("calib-uret").disabled = !enough || status.job?.status === "running";
  if (status.job?.status === "running") $("calib-metin").textContent = status.job.message || "Üretiliyor…";
}

// ── Bağlama ──────────────────────────────────────────

function bind() {
  if (bound) return;
  bound = true;

  onayTabs = bindTabs($("onay-sekmeler"));

  $("disoneri-liste").addEventListener("click", (event) => {
    const doldurId = event.target.dataset.oneriDoldur;
    if (doldurId) { fillReviewFromSuggestion(Number(doldurId)).catch(err); return; }
    const reddetId = event.target.dataset.oneriReddet;
    if (reddetId) dismissSuggestion(Number(reddetId)).catch(err);
  });

  $("eslesme-liste").addEventListener("click", (event) => {
    const decide = event.target.dataset.decide;
    if (decide !== undefined) {
      decidePair(Number(event.target.dataset.item), decide === "1").catch(err);
    }
  });

  $("bilgi-liste").addEventListener("click", (event) => {
    const item = event.target.closest("li[data-id]");
    if (item) openReview(Number(item.dataset.id)).catch(err);
  });
  $("bilgi-sayfa-geri").addEventListener("click", async () => {
    if (!(await canLeave())) return;
    reviewOffset = Math.max(0, reviewOffset - REVIEW_PAGE);
    activeReviewId = null;
    reviewBaseline = "";
    refreshReviewList().catch(err);
  });
  $("bilgi-sayfa-ileri").addEventListener("click", async () => {
    if (!(await canLeave())) return;
    reviewOffset += REVIEW_PAGE;
    activeReviewId = null;
    reviewBaseline = "";
    refreshReviewList().catch(err);
  });
  $("bilgi-form").addEventListener("submit", (event) => {
    event.preventDefault();
    saveReviewAndNext().catch(err);
  });
  $("bilgi-form").addEventListener("click", (event) => {
    const altButton = event.target.closest(".field-alt-btn");
    if (altButton) {
      const input = $("bilgi-form").elements[altButton.dataset.altField];
      if (input) input.value = altButton.dataset.altValue;
      return;
    }
    const previewButton = event.target.closest(".field-alt-preview");
    if (previewButton) {
      openLightbox(
        `/api/review/${activeReviewId}/span-crop/${encodeURIComponent(previewButton.dataset.preview)}`,
        previewButton.dataset.label || "Kanıt önizlemesi"
      );
    }
  });
  $("bilgi-basarisiz-liste").addEventListener("click", (event) => {
    const retryAll = event.target.dataset.retryAll;
    const retry = event.target.dataset.retry;
    if (retryAll) retryAllFailed(retryAll).catch(err);
    else if (retry) retryFailedItem(Number(retry)).catch(err);
  });
  document.addEventListener("keydown", (event) => {
    // Kısayol yalnız Onay sayfası VE Bilgi paneli gerçekten görünürken çalışır;
    // aksi hâlde başka sayfadaki Cmd+Enter görünmez bir kaydı onaylayabilir.
    const active = !$("sayfa-onay").hidden && !$("onay-bilgi").hidden && !$("bilgi-detay").hidden;
    if ((event.ctrlKey || event.metaKey) && event.key === "Enter" && active) {
      event.preventDefault();
      saveReviewAndNext().catch(err);
    }
  });

  $("bilgi-ses-cal").addEventListener("click", () => {
    if (audioPlayer) { audioPlayer.pause(); audioPlayer = null; return; }
    audioPlayer = new Audio(`/api/review/${activeReviewId}/audio`);
    audioPlayer.play().catch(() => toast("Ses çalınamadı", "error"));
    audioPlayer.addEventListener("ended", () => { audioPlayer = null; });
  });

  $("calib-uret").addEventListener("click", async () => {
    try {
      await api.post("/api/calibration/fit");
      toast("Kalibrasyon profili üretiliyor…");
      refreshCalibration();
    } catch (error) { err(error); }
  });
}

export function enter() {
  bind();
  refreshPairs().catch(err);
  refreshReviewList().catch(err);
  refreshCalibration().catch(() => {});
  refreshFailedItems().catch(() => {});
  refreshExternalSuggestions().catch(() => {});
  pollTimer = setInterval(async () => {
    if (document.hidden || pollBusy) return;
    pollBusy = true;
    try {
      await Promise.all([refreshPairs(), refreshCalibration()]);
    } catch { /* sonraki turda yeniden dene */ }
    finally { pollBusy = false; }
  }, 3000);
}

export function leave() {
  clearInterval(pollTimer);
  pollTimer = null;
  if (audioPlayer) { audioPlayer.pause(); audioPlayer = null; }
  activeReviewId = null;
  reviewBaseline = "";
  show($("bilgi-detay"), false);
}
