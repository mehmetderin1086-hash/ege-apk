// OPAC: öğrenci arama ekranı — salt okunur, oturumsuz.

import { bindTabs, show } from "./ui.js";

const ara = document.getElementById("opac-ara");
const sonuc = document.getElementById("opac-sonuc");
const bilgi = document.getElementById("opac-bilgi");
const kategori = document.getElementById("opac-kategori");
const rafta = document.getElementById("opac-rafta");

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (ch) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]
  );

let timer = null;
let sekme = ""; // "" arama · "new" yeni gelenler · "popular" popüler · "lists" listeler
let searchSeq = 0; // geç gelen eski yanıt yeni sonuçları ezmesin
let searchController = null;

function render(data) {
  bilgi.textContent = data.total === 0
    ? "Hiç kitap bulamadık. Başka bir kelimeyle dener misin? 🔎"
    : `${data.total} sonuç`;
  sonuc.innerHTML = data.items
    .map((book) => {
      const available = book.available > 0;
      const siraNotu = book.holds_waiting > 0 ? ` — ${book.holds_waiting} kişi sırada` : "";
      const durum = available
        ? `<span class="opac-durum var">✓ Rafta (${book.available}/${book.total_copies})</span>`
        : `<span class="opac-durum yok">Ödünçte${esc(siraNotu)}</span>`;
      const yer = book.locations.length > 0 ? ` · Yer: ${esc(book.locations.join(", "))}` : "";
      const kapak = book.has_cover
        ? `<img class="opac-kapak" loading="lazy" src="/api/opac/cover/${book.edition_id}" alt=""
             onerror="this.classList.add('opac-kapak-bos');this.outerHTML='<div class=&quot;opac-kapak opac-kapak-bos&quot;>📕</div>'">`
        : '<div class="opac-kapak opac-kapak-bos">📕</div>';
      return `
      <div class="opac-kart">
        ${kapak}
        <div class="opac-kart-metin">
          <h3>${esc(book.title)}</h3>
          <div class="opac-meta">${esc(book.authors || "—")}${book.publisher ? " · " + esc(book.publisher) : ""}${book.category ? " · " + esc(book.category) : ""}${book.publication_date ? " · " + esc(book.publication_date) : ""}</div>
          <div>${durum}${yer}</div>
        </div>
      </div>`;
    })
    .join("");
}

function listBookCover(book) {
  return book.has_cover
    ? `<img loading="lazy" src="/api/opac/cover/${book.edition_id}" alt=""
         onerror="this.classList.add('opac-kapak-bos');this.outerHTML='<div class=&quot;opac-kapak-bos&quot;>📕</div>'">`
    : '<div class="opac-kapak-bos">📕</div>';
}

function renderLists(data) {
  const lists = data.items;
  bilgi.textContent = lists.length === 0 ? "Henüz herkese açık okuma listesi yok." : "";
  sonuc.innerHTML = lists
    .map(
      (list) => `
      <div class="opac-liste-kart">
        <h3>${esc(list.name)}</h3>
        ${list.description ? `<p class="opac-meta">${esc(list.description)}</p>` : ""}
        <div class="opac-liste-vitrin">
          ${list.items
            .map(
              (book) => `
              <div class="opac-liste-kitap">
                ${listBookCover(book)}
                <div>${esc(book.title)}</div>
              </div>`
            )
            .join("") || '<p class="hint">Bu listede henüz kitap yok.</p>'}
        </div>
      </div>`
    )
    .join("");
}

async function loadLists() {
  searchController?.abort();
  const controller = new AbortController();
  searchController = controller;
  const seq = ++searchSeq;
  try {
    const response = await fetch("/api/opac/lists", { signal: controller.signal });
    if (!response.ok) throw new Error("Listeler yüklenemedi");
    const data = await response.json();
    if (seq !== searchSeq) return;
    renderLists(data);
  } catch (error) {
    if (error.name === "AbortError") return;
    if (seq !== searchSeq) return;
    bilgi.textContent = "Listeler yüklenirken bir sorun oluştu; tekrar deneyin.";
  }
}

async function search() {
  if (sekme === "lists") { await loadLists(); return; }
  searchController?.abort();
  const controller = new AbortController();
  searchController = controller;
  const seq = ++searchSeq;
  const query = ara.value.trim();
  // Sekmelerde boş sorgu serbest (liste görünümü); aramada en az 2 karakter.
  if (!sekme && query.length < 2) {
    sonuc.innerHTML = "";
    bilgi.textContent = "";
    return;
  }
  const params = new URLSearchParams();
  if (query.length >= 2) params.set("q", query);
  if (kategori.value) params.set("category", kategori.value);
  if (rafta.checked) params.set("available", "true");
  if (sekme) params.set("sort", sekme);
  try {
    const response = await fetch(`/api/opac/search?${params}`, { signal: controller.signal });
    if (!response.ok) throw new Error("Arama başarısız");
    const data = await response.json();
    if (seq !== searchSeq) return;
    render(data);
  } catch (error) {
    if (error.name === "AbortError") return;
    if (seq !== searchSeq) return;
    bilgi.textContent = "Arama sırasında bir sorun oluştu; tekrar deneyin.";
  }
}

async function fillCategories() {
  try {
    const response = await fetch("/api/opac/categories");
    if (!response.ok) return;
    const values = await response.json();
    kategori.innerHTML =
      '<option value="">Tüm kategoriler</option>' +
      values.map((value) => `<option value="${esc(value)}">${esc(value)}</option>`).join("");
  } catch { /* kategori süzgeci olmadan da çalışır */ }
}

ara.addEventListener("input", () => {
  clearTimeout(timer);
  timer = setTimeout(search, 300);
});
kategori.addEventListener("change", search);
rafta.addEventListener("change", search);
const filtreSatiri = document.querySelector(".opac-filtre");

bindTabs(document.getElementById("opac-sekmeler"), (button) => {
  sekme = button.dataset.sekme;
  const listsMode = sekme === "lists";
  show(ara, !listsMode);
  show(filtreSatiri, !listsMode);
  search();
});

fillCategories();
