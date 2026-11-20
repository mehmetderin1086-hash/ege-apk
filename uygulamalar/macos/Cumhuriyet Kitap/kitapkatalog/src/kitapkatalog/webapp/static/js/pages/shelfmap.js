// Raf haritası: dolap ızgarası, dolap CRUD, eşleşmemiş konumların evlatlığı.

import { api } from "../api.js";
import { confirmBox, esc, show, toast } from "../ui.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");

let bound = false;
let shelves = [];

function shelfBox(shelf) {
  const capacity = shelf.capacity;
  const doluluk = capacity
    ? `<div class="bar-track ${shelf.copies > capacity ? "hd-doluluk-asim" : ""}" title="${shelf.copies}/${capacity}">
         <div class="bar-fill" style="width:${Math.min(100, Math.round((shelf.copies / capacity) * 100))}%"></div>
       </div>`
    : "";
  const style = shelf.color ? ` style="border-top-color:${esc(shelf.color)}"` : "";
  const cell =
    shelf.grid_row !== null
      ? ` data-cell style="grid-row:${shelf.grid_row + 1};grid-column:${shelf.grid_col + 1};${shelf.color ? `border-top-color:${esc(shelf.color)}` : ""}"`
      : style;
  return `
    <div class="harita-dolap" data-ad="${esc(shelf.name)}"${cell} tabindex="0" role="button"
         data-key-activate aria-label="${esc(shelf.name)} dolabındaki kitapları aç">
      <button class="btn-icon hd-duzenle" data-duzenle="${shelf.id}" title="Düzenle"
              aria-label="${esc(shelf.name)} dolabını düzenle">✏️</button>
      <h3>${esc(shelf.name)}</h3>
      <div class="hd-sayilar">${shelf.copies} nüsha · ${shelf.editions} eser${shelf.on_loan ? ` · ${shelf.on_loan} ödünçte` : ""}</div>
      ${doluluk}
    </div>`;
}

async function refresh() {
  const data = await api.get("/api/shelves/map");
  shelves = data.shelves;
  const placed = shelves.filter((shelf) => shelf.grid_row !== null);
  const free = shelves.filter((shelf) => shelf.grid_row === null);

  const grid = $("hr-izgara");
  if (placed.length > 0) {
    const cols = Math.max(...placed.map((shelf) => shelf.grid_col)) + 1;
    grid.style.gridTemplateColumns = `repeat(${cols}, minmax(130px, 1fr))`;
  }
  grid.innerHTML = placed.map(shelfBox).join("");
  show(grid, placed.length > 0);

  $("hr-yerlesmemis").innerHTML = free.map(shelfBox).join("");
  show($("hr-yerlesmemis-kutu"), free.length > 0);

  const options = shelves
    .map((shelf) => `<option value="${shelf.id}">${esc(shelf.name)}</option>`)
    .join("");
  $("hr-eslesmemis").innerHTML = data.unmatched
    .map(
      (item) => `
      <div class="eslesmemis-satir" data-ad="${esc(item.name)}">
        <span class="es-ad">${esc(item.name)}</span>
        <span class="hint">${item.copies} nüsha</span>
        <button class="btn" data-dolap-yap>Dolap yap</button>
        ${shelves.length ? `<select data-hedef>${options}</select><button class="btn" data-tasi>Taşı</button>` : ""}
      </div>`
    )
    .join("");
  show($("hr-eslesmemis-bos"), data.unmatched.length === 0);
}

function fillForm(shelf) {
  $("hr-duzenle-id").value = shelf ? shelf.id : "";
  $("hr-form-baslik").textContent = shelf ? `✏️ ${shelf.name}` : "➕ Dolap Ekle";
  $("hr-ad").value = shelf ? shelf.name : "";
  $("hr-satir").value = shelf && shelf.grid_row !== null ? shelf.grid_row : "";
  $("hr-sutun").value = shelf && shelf.grid_col !== null ? shelf.grid_col : "";
  $("hr-kapasite").value = shelf && shelf.capacity ? shelf.capacity : "";
  if (shelf && shelf.color) $("hr-renk").value = shelf.color;
  $("hr-not").value = shelf && shelf.notes ? shelf.notes : "";
  show($("hr-sil"), Boolean(shelf));
}

function readForm() {
  const num = (id) => ($(id).value === "" ? null : Number($(id).value));
  return {
    name: $("hr-ad").value.trim(),
    grid_row: num("hr-satir"),
    grid_col: num("hr-sutun"),
    capacity: num("hr-kapasite"),
    color: $("hr-renk").value,
    notes: $("hr-not").value.trim() || null,
  };
}

async function save() {
  const editId = $("hr-duzenle-id").value;
  const payload = readForm();
  if (!payload.name) {
    toast("Dolap adı gerekli", "error");
    return;
  }
  if (editId) {
    await api.patch(`/api/shelves/${editId}`, payload);
    toast("Dolap güncellendi ✓", "success");
  } else {
    await api.post("/api/shelves", payload);
    toast("Dolap eklendi ✓", "success");
  }
  fillForm(null);
  await refresh();
}

function bind() {
  if (bound) return;
  bound = true;

  const boxClick = async (event) => {
    const editButton = event.target.closest("[data-duzenle]");
    if (editButton) {
      const shelf = shelves.find((item) => item.id === Number(editButton.dataset.duzenle));
      if (shelf) fillForm(shelf);
      return;
    }
    const box = event.target.closest(".harita-dolap");
    if (!box) return;
    // Kütüphane sayfası bu köprüden dolap filtresini devralır.
    sessionStorage.setItem("kk-dolap-filtre", box.dataset.ad);
    location.hash = "#kutuphane";
  };
  $("hr-izgara").addEventListener("click", (event) => boxClick(event).catch(err));
  $("hr-yerlesmemis").addEventListener("click", (event) => boxClick(event).catch(err));

  $("hr-kaydet").addEventListener("click", () => save().catch(err));
  $("hr-yeni").addEventListener("click", () => fillForm(null));
  $("hr-sil").addEventListener("click", async () => {
    const editId = $("hr-duzenle-id").value;
    if (!editId) return;
    if (!(await confirmBox("Dolap kaydı silinsin mi? Kitapların konum metni korunur."))) return;
    try {
      await api.del(`/api/shelves/${editId}`);
      toast("Dolap silindi", "success");
      fillForm(null);
      await refresh();
    } catch (error) { err(error); }
  });

  $("hr-eslesmemis").addEventListener("click", async (event) => {
    const row = event.target.closest(".eslesmemis-satir");
    if (!row) return;
    const name = row.dataset.ad;
    try {
      if (event.target.closest("[data-dolap-yap]")) {
        await api.post("/api/shelves", { name });
        toast(`"${name}" dolabı oluşturuldu ✓`, "success");
      } else if (event.target.closest("[data-tasi]")) {
        const target = row.querySelector("[data-hedef]");
        const result = await api.post(`/api/shelves/${target.value}/adopt`, { location: name });
        toast(`${result.moved} nüsha taşındı ✓`, "success");
      } else return;
      await refresh();
    } catch (error) { err(error); }
  });
}

export function enter() {
  bind();
  refresh().catch(err);
}

export function leave() {}
