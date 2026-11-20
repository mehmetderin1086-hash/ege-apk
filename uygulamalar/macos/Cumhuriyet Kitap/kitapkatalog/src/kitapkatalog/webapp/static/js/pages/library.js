// Kütüphane: arama, tablo, detay çekmecesi, toplu işlemler, yeni kitap.

import { api } from "../api.js";
import {
  confirmBox, debounce, esc, fillForm, fmtCount, formSnapshot, openLightbox, readForm, show, toast,
} from "../ui.js";
import { refreshDatalists } from "../main.js";

const PAGE_SIZE = 50;
let offset = 0;
let total = 0;
let searchSeq = 0;
let currentBook = null;
let detailBaseline = "";
let newBookBaseline = "";
let currentCopyCount = 1;
let bound = false;
let listController = null;

const $ = (id) => document.getElementById(id);

// ── Görünüm anahtarı (kart ⇄ tablo) ──────────────────

const PLAKA_RENKLERI = ["#3453b8", "#5cae63", "#e0a23a", "#c96a9a", "#4fb3b0", "#9585d0"];

function plakaRengi(text) {
  let hash = 0;
  for (let i = 0; i < text.length; i += 1) hash = (hash * 31 + text.charCodeAt(i)) >>> 0;
  return PLAKA_RENKLERI[hash % PLAKA_RENKLERI.length];
}

function currentView() {
  return localStorage.getItem("kk-gorunum") === "kart" ? "kart" : "tablo";
}

function setView(view) {
  localStorage.setItem("kk-gorunum", view);
  $("gorunum-tablo").setAttribute("aria-pressed", String(view === "tablo"));
  $("gorunum-kart").setAttribute("aria-pressed", String(view === "kart"));
  show($("kitap-tablo-sarici"), view === "tablo");
  show($("kitap-izgara"), view === "kart");
}

function durumRozeti(book) {
  if (book.copy_count === 0) return '<span class="badge badge-muted">Düşüldü</span>';
  if (book.on_loan >= book.copy_count) return '<span class="badge badge-warn">Ödünçte</span>';
  return '<span class="badge badge-ok">Rafta</span>';
}

function renderGrid(items) {
  $("kitap-izgara").innerHTML = items
    .map((book) => {
      const kapak = book.covers.front
        ? `<img class="kitap-kart-kapak" loading="lazy" src="/api/books/${book.edition_id}/cover/front?thumb=1" alt="">`
        : `<div class="kitap-kart-plaka" style="background:${plakaRengi(book.title + book.authors)}">${esc((book.title || "?").trim().charAt(0).toUpperCase())}</div>`;
      return `
      <button type="button" class="kitap-kart" data-id="${book.edition_id}"
              aria-label="${esc(book.title)} kitabının ayrıntısını aç">
        ${kapak}
        <div class="kitap-kart-govde">
          <div class="kitap-kart-baslik">${esc(book.title)}</div>
          <div class="kitap-kart-yazar">${esc(book.authors || "—")}</div>
          <div class="kitap-kart-alt">${durumRozeti(book)}<span>${esc(book.location || "")}</span></div>
        </div>
      </button>`;
    })
    .join("");
}

// ── Liste ────────────────────────────────────────────

async function refreshList() {
  listController?.abort();
  const controller = new AbortController();
  listController = controller;
  const seq = ++searchSeq;
  const params = new URLSearchParams({
    q: $("ara").value.trim(),
    limit: PAGE_SIZE,
    offset,
  });
  for (const [param, id] of [
    ["category", "f-kategori"], ["language", "f-dil"],
    ["review_status", "f-durum"], ["missing", "f-eksik"],
    ["location", "f-dolap"], ["availability", "f-musait"],
    ["year_from", "f-yil-min"], ["year_to", "f-yil-max"],
  ]) {
    const value = $(id).value;
    if (value) params.set(param, value);
  }
  const sort = $("f-sirala").value;
  if (sort && sort !== "relevance") params.set("sort", sort);
  let page;
  try {
    page = await api.get(`/api/books?${params}`, { signal: controller.signal });
  } catch (error) {
    if (error.name === "AbortError") return;
    throw error;
  }
  if (seq !== searchSeq) return; // Geç gelen eski yanıt yeniyi ezmesin.
  total = page.total;
  const body = $("kitap-govde");
  body.innerHTML = page.items
    .map(
      (book) => `
      <tr data-id="${book.edition_id}" tabindex="0" role="button" data-key-activate
          aria-label="${esc(book.title)} kitabının ayrıntısını aç">
        <td class="col-check"><input type="checkbox" class="sec" data-id="${book.edition_id}" aria-label="Seç"></td>
        <td class="col-thumb">${
          book.covers.front
            ? `<img class="thumb" loading="lazy" src="/api/books/${book.edition_id}/cover/front?thumb=1" alt="">`
            : '<div class="thumb-empty">📕</div>'
        }</td>
        <td><strong>${esc(book.title)}</strong>${book.subtitle ? `<br><small>${esc(book.subtitle)}</small>` : ""}</td>
        <td>${esc(book.authors)}</td>
        <td>${esc(book.publisher ?? "")}</td>
        <td>${esc(book.publication_date ?? "")}</td>
        <td>${esc(book.category ?? "")}</td>
        <td>${book.copy_count}${book.on_loan ? `<br><small class="hint">${book.on_loan} ödünçte</small>` : ""}${book.discarded_copies ? `<br><small class="hint">${book.discarded_copies} düşülmüş</small>` : ""}</td>
        <td>${esc(book.location ?? "")}</td>
        <td><span class="status-pill ${book.review_status === "completed" ? "ok" : "review"}">${esc(book.review_status_label)}</span></td>
        <td class="col-islem">
          <button class="btn-icon" data-edit="${book.edition_id}" title="Düzenle"
                  aria-label="${esc(book.title)} kitabını düzenle">✏️</button>
          <button class="btn-icon" data-del="${book.edition_id}" title="Sil"
                  aria-label="${esc(book.title)} kitabını sil">🗑️</button>
        </td>
      </tr>`
    )
    .join("");
  renderGrid(page.items);
  show($("kitap-bos"), page.items.length === 0);
  $("sayfa-bilgi").textContent =
    total === 0 ? "0 kayıt" : `${offset + 1}–${Math.min(offset + PAGE_SIZE, total)} / ${fmtCount(total)}`;
  $("sayfa-geri").disabled = offset === 0;
  $("sayfa-ileri").disabled = offset + PAGE_SIZE >= total;
  $("kitap-sonuc-sayisi").textContent = total === 0 ? "0 kayıt" : `${fmtCount(total)} kayıt`;
  const filtersActive = [...document.querySelectorAll(".filter-row select, .filter-row input")]
    .some((el) => el.value && el.id !== "f-sirala");
  show($("kitap-filtre-temizle"), filtersActive);
  updateBulkBar();
}

function selectedIds() {
  return [...document.querySelectorAll(".sec:checked")].map((el) => Number(el.dataset.id));
}

function updateBulkBar() {
  const count = selectedIds().length;
  show($("toplu-cubuk"), count > 0);
  $("toplu-sayi").textContent = `${count} kayıt seçili`;
}

// ── Detay çekmecesi ──────────────────────────────────

const FACE_LABELS = { front: "Ön", front_inside: "Ön iç", back_inside: "Arka iç", back: "Arka" };

async function openDetail(editionId) {
  if (!(await guardDirty())) return;
  const book = await api.get(`/api/books/${editionId}`);
  currentBook = book;
  currentCopyCount = book.copy_count;
  $("detay-baslik").textContent = `No ${book.edition_id}`;
  const covers = $("detay-kapaklar");
  covers.innerHTML = Object.entries(FACE_LABELS)
    .map(([face, label]) =>
      book.covers[face]
        ? `<figure><button type="button" class="cover-button" data-full="/api/books/${editionId}/cover/${face}"
                    aria-label="${label} kapağı büyüt"><img src="/api/books/${editionId}/cover/${face}?thumb=1" alt="${label} kapak"></button><figcaption>${label}</figcaption></figure>`
        : ""
    )
    .join("");
  covers.querySelectorAll(".cover-button").forEach((button) =>
    button.addEventListener("click", () => openLightbox(button.dataset.full, button.querySelector("img").alt))
  );
  fillForm($("detay-form"), book);
  $("adet-deger").textContent = currentCopyCount;
  $("detay-etiketler").href = `/print/labels?scope=edition&edition_id=${book.edition_id}`;
  renderCopies(book);
  renderLoanHistory(book.edition_id).catch(() => {});
  renderHoldQueue(book.edition_id).catch(() => {});
  fillListOptions().catch(() => {});
  detailBaseline = snapshot();
  show($("detay"), true);
}

// Okuma listesi seçicisi — yalnız isim + id, üye/atama verisi çekmez.
async function fillListOptions() {
  const select = $("detay-liste-sec");
  const data = await api.get("/api/lists");
  select.innerHTML = data.items.length
    ? data.items.map((list) => `<option value="${list.id}">${esc(list.name)}</option>`).join("")
    : '<option value="">Önce bir liste oluşturun</option>';
}

async function addCurrentBookToList() {
  if (!currentBook) return;
  const select = $("detay-liste-sec");
  if (!select.value) { toast("Önce en az bir okuma listesi oluşturun", "error"); return; }
  try {
    await api.post(`/api/lists/${select.value}/items`, { edition_id: currentBook.edition_id });
    toast(`✓ "${select.options[select.selectedIndex].text}" listesine eklendi`, "success");
  } catch (error) { err(error); }
}

const DISCARD_REASONS =
  '<option value="yipranma">Yıpranma</option><option value="kayip">Kayıp</option>' +
  '<option value="guncelligini_yitirme">Güncelliğini yitirme</option><option value="diger">Diğer</option>';

const ACQUISITION_METHODS = [
  ["", "Edinme yöntemi seçilmedi"],
  ["satin_alma", "Satın alma"],
  ["bagis", "Bağış"],
  ["devir", "Devir"],
];

function acquisitionMethodOptions(selected) {
  return ACQUISITION_METHODS
    .map(([value, text]) => `<option value="${value}" ${value === (selected || "") ? "selected" : ""}>${esc(text)}</option>`)
    .join("");
}

function renderCopies(book) {
  const copies = book.copies || [];
  $("detay-nushalar").innerHTML = copies
    .map((copy) => {
      const label = copy.inventory_code || `Nüsha ${copy.id}`;
      if (copy.status === "discarded") {
        return `<li class="pasif">${esc(label)} — düşülmüş</li>`;
      }
      return `<li data-copy="${copy.id}">
        <div class="nusha-satir-ust">
          ${esc(label)}
          <input data-konum="${copy.id}" list="dl-dolap" value="${esc(copy.location || "")}"
                 placeholder="Dolap" title="Bu nüshanın dolabı (Enter ile kaydet)" class="nusha-konum">
          <button type="button" class="btn" data-dus="${copy.id}">Düş</button>
        </div>
        <span class="dus-form" hidden>
          <select data-gerekce="${copy.id}">${DISCARD_REASONS}</select>
          <button type="button" class="btn btn-danger" data-dus-onay="${copy.id}">Onayla</button>
        </span>
        <details class="nusha-edinme">
          <summary>Edinme bilgisi</summary>
          <div class="form-grid">
            <label>Yöntem <select data-acq-method="${copy.id}">${acquisitionMethodOptions(copy.acquisition_method)}</select></label>
            <label>Tarih <input type="date" data-acq-date="${copy.id}" value="${esc(copy.acquisition_date || "")}"></label>
            <label>Fiyat <input data-acq-price="${copy.id}" value="${esc(copy.acquisition_price || "")}" placeholder="Örn. 125.50"></label>
          </div>
        </details>
      </li>`;
    })
    .join("");
}

function fmtLoanDate(value) {
  if (!value) return "—";
  return value.slice(0, 10).split("-").reverse().join(".");
}

// Kitabın ödünç geçmişi — yalnız kütüphaneci ekranında (OPAC bu uca erişemez).
async function renderLoanHistory(editionId) {
  const data = await api.get(`/api/loans?edition_id=${editionId}&status=all&limit=20`);
  $("detay-odunc").innerHTML = data.items
    .map(
      (loan) =>
        `<li>${esc(loan.member_name)}${loan.member_class ? ` (${esc(loan.member_class)})` : ""} · ` +
        `${fmtLoanDate(loan.loaned_at)} → ${loan.returned_at ? fmtLoanDate(loan.returned_at) : "üzerinde"}` +
        `${loan.overdue ? ` <span class="geciken">${loan.days_overdue} gün gecikti</span>` : ""}</li>`
    )
    .join("");
  show($("detay-odunc-bos"), data.total === 0);
}

function snapshot() {
  return `${formSnapshot($("detay-form"))}|${currentCopyCount}`;
}

function newBookSnapshot() {
  return formSnapshot($("yeni-form"));
}

function detailIsDirty() {
  return Boolean(currentBook && !$("detay").hidden && detailBaseline !== snapshot());
}

function newBookIsDirty() {
  return Boolean($("modal-yeni").open && newBookBaseline && newBookBaseline !== newBookSnapshot());
}

export function isDirty() {
  return detailIsDirty() || newBookIsDirty();
}

export function canLeave() {
  if (!isDirty()) return Promise.resolve(true);
  return confirmBox("Kaydedilmemiş kitap değişiklikleri var. Vazgeçilsin mi?");
}

async function guardDirty() {
  if (!detailIsDirty()) return true;
  return confirmBox("Kaydedilmemiş değişiklikler var. Vazgeçilsin mi?");
}

async function saveDetail(approve = false) {
  const values = readForm($("detay-form"));
  const payload = {
    changes: { ...values },
    isbn: values.isbn,
    authors: values.authors,
    location: values.location,
    copy_count: currentCopyCount,
  };
  delete payload.changes.isbn;
  delete payload.changes.authors;
  delete payload.changes.location;
  // Form alanı değişmediyse location GÖNDERME: set_location tüm nüshaları
  // ezdiğinden, nüsha bazlı düzenlenen konumlar kaybolurdu.
  if ((values.location || "") === (currentBook.location || "")) delete payload.location;
  if (approve) payload.changes.review_status = "completed";
  const book = await api.patch(`/api/books/${currentBook.edition_id}`, payload);
  currentBook = book;
  detailBaseline = snapshot();
  toast(approve ? "Kaydedildi ve onaylandı ✓" : "Kaydedildi ✓", "success");
  refreshList();
  refreshDatalists();
}

// Bekleyen rezervasyonlar — rafta nüsha kalmadığında sıraya girmiş üyeler.
async function renderHoldQueue(editionId) {
  const data = await api.get(`/api/holds?edition_id=${editionId}`);
  const waiting = data.items.filter((hold) => hold.status === "active" || hold.status === "ready");
  $("detay-rezervasyon-liste").innerHTML = waiting
    .map((hold) => {
      const kimlik = hold.school_number ? ` (${esc(hold.school_number)})` : "";
      const durum = hold.status === "ready"
        ? `hazır — son alma ${fmtLoanDate(hold.expires_at)}`
        : "sırada";
      return `<li>${esc(hold.member_name)}${kimlik} — ${durum}</li>`;
    })
    .join("");
  show($("detay-rezervasyon-bos"), waiting.length === 0);
  $("detay-rezervasyon-sayi").textContent = waiting.length;
  show($("detay-rezervasyon-sayi"), waiting.length > 0);
}

async function addToHoldQueue() {
  if (!currentBook) return;
  const input = $("detay-siraya-uye");
  const query = input.value.trim();
  if (!query) { toast("Önce üye no ya da adı girin", "error"); return; }
  let member = null;
  try {
    member = await api.get(`/api/members/by-number/${encodeURIComponent(query)}`);
  } catch { /* okul numarası değil; ada göre aramaya düş */ }
  if (!member) {
    const results = await api.get(`/api/members?q=${encodeURIComponent(query)}&limit=2`);
    if (results.items.length === 1) member = results.items[0];
    else if (results.items.length === 0) { toast("Bu numarayla/adla üye bulunamadı", "error"); return; }
    else { toast("Birden çok eşleşme var; okul numarasıyla arayın", "error"); return; }
  }
  try {
    await api.post("/api/holds", {
      member_id: member.id, edition_id: currentBook.edition_id, request_id: crypto.randomUUID(),
    });
    toast(`✓ ${member.full_name} sıraya eklendi`, "success");
    input.value = "";
    await renderHoldQueue(currentBook.edition_id);
  } catch (error) { err(error); }
}

// ── Olay bağlama (tek sefer) ─────────────────────────

function bind() {
  if (bound) return;
  bound = true;

  $("gorunum-tablo").addEventListener("click", () => setView("tablo"));
  $("gorunum-kart").addEventListener("click", () => setView("kart"));
  $("kitap-izgara").addEventListener("click", (event) => {
    const card = event.target.closest(".kitap-kart");
    if (card) openDetail(Number(card.dataset.id)).catch(err);
  });
  $("kitap-filtre-temizle").addEventListener("click", () => {
    for (const el of document.querySelectorAll(".filter-row select, .filter-row input")) {
      if (el.id === "f-sirala") continue;
      el.value = "";
    }
    offset = 0;
    refreshList().catch(err);
  });

  const debouncedSearch = debounce(() => { offset = 0; refreshList().catch(err); }, 250);
  $("ara").addEventListener("input", debouncedSearch);
  for (const id of ["f-kategori", "f-dil", "f-durum", "f-eksik", "f-dolap", "f-musait", "f-sirala"]) {
    $(id).addEventListener("change", () => { offset = 0; refreshList().catch(err); });
  }
  for (const id of ["f-yil-min", "f-yil-max"]) {
    $(id).addEventListener("input", debouncedSearch);
  }
  $("sayfa-geri").addEventListener("click", () => { offset = Math.max(0, offset - PAGE_SIZE); refreshList().catch(err); });
  $("sayfa-ileri").addEventListener("click", () => { offset += PAGE_SIZE; refreshList().catch(err); });

  $("kitap-govde").addEventListener("click", async (event) => {
    if (event.target.classList.contains("sec")) { updateBulkBar(); return; }
    // Satır işlem düğmeleri satır-tıklamasından ÖNCE ele alınır (return şart;
    // yoksa Sil düğmesi detayı da açar).
    const editId = event.target.dataset.edit;
    if (editId) { openDetail(Number(editId)).catch(err); return; }
    const delId = event.target.dataset.del;
    if (delId) {
      const row = event.target.closest("tr");
      const title = row?.querySelector("strong")?.textContent || "Kayıt";
      if (!(await confirmBox(`"${title}" kalıcı olarak silinecek. Emin misiniz?`))) return;
      try {
        await api.del(`/api/books/${delId}`);
        toast("Kitap silindi", "success");
        refreshList().catch(err);
      } catch (error) { err(error); }
      return;
    }
    const row = event.target.closest("tr[data-id]");
    if (row) openDetail(Number(row.dataset.id)).catch(err);
  });
  $("tumunu-sec").addEventListener("change", (event) => {
    document.querySelectorAll(".sec").forEach((el) => { el.checked = event.target.checked; });
    updateBulkBar();
  });

  // Toplu işlemler
  $("toplu-cubuk").addEventListener("click", async (event) => {
    const action = event.target.dataset.bulk;
    if (!action) return;
    const ids = selectedIds();
    try {
      let value = null;
      if (action === "delete") {
        if (!(await confirmBox(`${ids.length} kayıt kalıcı olarak silinecek. Emin misiniz?`))) return;
      } else if (action === "category" || action === "location") {
        value = await askValue(
          action === "category" ? "Kategori ata" : "Dolap ata",
          action === "category" ? "dl-kategori" : "dl-dolap"
        );
        if (value === null) return;
      } else if (ids.length > 5) {
        if (!(await confirmBox(`${ids.length} kayıt güncellenecek. Devam edilsin mi?`))) return;
      }
      const result = await api.post("/api/books/bulk", { ids, action, value });
      toast(`${result.done} kayıt güncellendi${result.errors.length ? `, ${result.errors.length} hata` : ""}`,
        result.errors.length ? "error" : "success");
      refreshList();
    } catch (error) { err(error); }
  });

  // Çekmece
  $("detay-kapat").addEventListener("click", async () => {
    if (await guardDirty()) { show($("detay"), false); currentBook = null; }
  });
  $("detay").addEventListener("dialogcancel", async (event) => {
    event.preventDefault();
    if (await guardDirty()) { show($("detay"), false); currentBook = null; }
  });
  $("detay-form").addEventListener("submit", (event) => {
    event.preventDefault();
    saveDetail(false).catch(err);
  });
  $("detay-onayla").addEventListener("click", () => saveDetail(true).catch(err));
  $("detay-sil").addEventListener("click", async () => {
    if (!(await confirmBox(`"${currentBook.title}" kalıcı olarak silinecek. Emin misiniz?`))) return;
    await api.del(`/api/books/${currentBook.edition_id}`);
    toast("Kayıt silindi", "success");
    show($("detay"), false);
    currentBook = null;
    detailBaseline = "";
    refreshList().catch(err);
  });
  $("detay-siraya-ekle").addEventListener("click", () => addToHoldQueue().catch(err));
  $("detay-listeye-ekle").addEventListener("click", () => addCurrentBookToList().catch(err));
  $("detay-siraya-uye").addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    addToHoldQueue().catch(err);
  });
  $("adet-arti").addEventListener("click", () => {
    currentCopyCount += 1;
    $("adet-deger").textContent = currentCopyCount;
  });
  $("adet-eksi").addEventListener("click", () => {
    currentCopyCount = Math.max(1, currentCopyCount - 1);
    $("adet-deger").textContent = currentCopyCount;
  });

  // Nüsha düşme (düşüm defteri)
  $("detay-nushalar").addEventListener("click", async (event) => {
    const openId = event.target.dataset.dus;
    if (openId) {
      const item = event.target.closest("li");
      item.querySelector(".dus-form").hidden = false;
      event.target.hidden = true;
      return;
    }
    const confirmId = event.target.dataset.dusOnay;
    if (!confirmId) return;
    const reason = document.querySelector(`select[data-gerekce="${confirmId}"]`).value;
    try {
      await api.post("/api/discards", { copy_id: Number(confirmId), reason });
      toast("Nüsha demirbaştan düşüldü; Düşüm sayfasından geri alınabilir.", "success");
      await openDetail(currentBook.edition_id);
      refreshList().catch(err);
    } catch (error) { err(error); }
  });

  // Nüsha bazlı dolap: change'de kaydet (formdaki "Dolap" alanı tüm nüshaları ezer,
  // buradaki input yalnız tek nüshayı günceller).
  // Enter örtük form gönderimini tetikleyip saveDetail ile TÜM nüshaların
  // konumunu ezerdi (sessiz veri kaybı); blur'a çevirip change'e bırakıyoruz.
  $("detay-nushalar").addEventListener("keydown", (event) => {
    if (event.key === "Enter" && event.target.dataset.konum) {
      event.preventDefault();
      event.target.blur();
    }
  });
  $("detay-nushalar").addEventListener("change", async (event) => {
    const target = event.target;
    const konumId = target.dataset.konum;
    if (konumId) {
      try {
        await api.patch(`/api/copies/${konumId}`, { location: target.value.trim() || null });
        toast("Nüsha konumu güncellendi ✓", "success");
        refreshDatalists();
      } catch (error) { err(error); }
      return;
    }
    const acqId = target.dataset.acqMethod || target.dataset.acqDate || target.dataset.acqPrice;
    if (!acqId) return;
    const item = target.closest("li");
    const method = item.querySelector(`[data-acq-method]`).value || null;
    const date = item.querySelector(`[data-acq-date]`).value || null;
    const price = item.querySelector(`[data-acq-price]`).value.trim() || null;
    try {
      await api.patch(`/api/copies/${acqId}`, {
        acquisition_method: method, acquisition_date: date, acquisition_price: price,
      });
      toast("Edinme bilgisi güncellendi ✓", "success");
    } catch (error) { err(error); }
  });

  // Yeni kitap
  $("btn-yeni-kitap").addEventListener("click", () => {
    $("yeni-form").reset();
    newBookBaseline = newBookSnapshot();
    $("modal-yeni").showModal();
  });
  $("yeni-vazgec").addEventListener("click", async () => {
    if (newBookIsDirty() && !(await canLeave())) return;
    newBookBaseline = "";
    $("modal-yeni").close();
  });
  $("modal-yeni").addEventListener("cancel", (event) => {
    if (!newBookIsDirty()) { newBookBaseline = ""; return; }
    event.preventDefault();
    canLeave().then((allowed) => {
      if (!allowed) return;
      newBookBaseline = "";
      $("modal-yeni").close();
    });
  });
  $("yeni-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const values = readForm($("yeni-form"));
    const { acquisition_method, acquisition_date, acquisition_price, ...rest } = values;
    try {
      const book = await api.post("/api/books", {
        ...rest,
        copy_count: Number(values.copy_count || 1),
        copy: (acquisition_method || acquisition_date || acquisition_price)
          ? { acquisition_method: acquisition_method || null, acquisition_date: acquisition_date || null, acquisition_price: acquisition_price || null }
          : undefined,
      });
      newBookBaseline = "";
      $("modal-yeni").close();
      toast(`"${book.title}" eklendi ✓`, "success");
      refreshList();
      refreshDatalists();
    } catch (error) {
      if (error.status === 409) {
        newBookBaseline = "";
        $("modal-yeni").close();
        if (await confirmBox(`${error.message}\n\nMevcut kaydın adedi 1 artırılsın mı?`)) {
          const existing = await api.get(`/api/books?identifier=${encodeURIComponent(values.isbn)}`);
          if (existing.items.length > 0) {
            await api.post(`/api/books/${existing.items[0].edition_id}/copies`);
            toast("Adet artırıldı ✓", "success");
            refreshList();
          }
        }
      } else err(error);
    }
  });

  // Klavye: Ctrl+S kaydet
  document.addEventListener("keydown", (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key === "s" && currentBook && !$("detay").hidden) {
      event.preventDefault();
      saveDetail(false).catch(err);
    }
  });
}

function askValue(title, datalistId) {
  return new Promise((resolve) => {
    const dialog = $("modal-deger");
    $("deger-baslik").textContent = title;
    const input = $("deger-girdi");
    input.value = "";
    input.setAttribute("list", datalistId);
    dialog.returnValue = "";
    dialog.showModal();
    dialog.addEventListener("close", () => {
      resolve(dialog.returnValue === "ok" ? input.value.trim() : null);
    }, { once: true });
  });
}

// Süzgeç seçeneklerini distinct değerlerden doldur.
async function fillFilterOptions() {
  for (const [id, column] of [
    ["f-kategori", "category"], ["f-dil", "language"], ["f-dolap", "location"],
  ]) {
    try {
      const values = await api.get(`/api/meta/distinct/${column}`);
      const select = $(id);
      const chosen = select.value;
      select.innerHTML = select.options[0].outerHTML + values
        .map((value) => `<option value="${esc(value)}">${esc(value)}</option>`)
        .join("");
      select.value = chosen;
    } catch { /* boş katalog */ }
  }
}

const err = (error) => toast(error.message || String(error), "error");

export function enter() {
  bind();
  setView(currentView());
  // Raf haritasından gelen dolap filtresi köprüsü.
  const bridged = sessionStorage.getItem("kk-dolap-filtre");
  sessionStorage.removeItem("kk-dolap-filtre");
  fillFilterOptions().then(() => {
    if (bridged === null) return;
    const select = $("f-dolap");
    if (![...select.options].some((option) => option.value === bridged)) {
      select.insertAdjacentHTML("beforeend", `<option value="${esc(bridged)}">${esc(bridged)}</option>`);
    }
    select.value = bridged;
    offset = 0;
    refreshList().catch(err);
  });
  refreshList().catch(err);
}

export function leave() {
  listController?.abort();
  if ($("modal-yeni").open) $("modal-yeni").close();
  newBookBaseline = "";
  show($("detay"), false);
  currentBook = null;
  detailBaseline = "";
}
