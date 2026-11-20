// Okuma listeleri: liste CRUD, kitap/üye atama, ilerleme çubuğu, OPAC görünürlüğü, şablon.

import { api } from "../api.js";
import { confirmBox, esc, fillForm, formSnapshot, progressBar, readForm, show, toast } from "../ui.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");

let bound = false;
let listController = null;
let lists = [];
let editingId = null;
let formBaseline = "";
let currentListId = null;

// ── Liste tablosu ────────────────────────────────────

async function refreshList() {
  listController?.abort();
  const controller = new AbortController();
  listController = controller;
  let data;
  try {
    data = await api.get("/api/lists", { signal: controller.signal });
  } catch (error) {
    if (error.name === "AbortError") return;
    throw error;
  }
  lists = data.items;
  $("liste-tablo").innerHTML = lists
    .map(
      (list) => `
      <tr data-id="${list.id}">
        <td><strong>${esc(list.name)}</strong></td>
        <td>${esc(list.description || "—")}</td>
        <td>${list.item_count}</td>
        <td>${list.is_opac_visible ? "✓" : "—"}</td>
        <td class="col-islem">
          <button class="btn" data-ac="${list.id}">Aç</button>
          <button class="btn" data-duzenle="${list.id}">Düzenle</button>
          <button class="btn-icon" data-sil="${list.id}" title="Sil" aria-label="${esc(list.name)} listesini sil">🗑️</button>
        </td>
      </tr>`
    )
    .join("");
  show($("liste-bos"), lists.length === 0);
}

// ── Yeni/Düzenle formu ────────────────────────────────

function formSnapshotValue() {
  return formSnapshot($("liste-form"));
}

export function isDirty() {
  return Boolean(!$("liste-form-kart").hidden && formBaseline && formBaseline !== formSnapshotValue());
}

export function canLeave() {
  if (!isDirty()) return Promise.resolve(true);
  return confirmBox("Kaydedilmemiş liste değişiklikleri var. Vazgeçilsin mi?");
}

function openForm(list = null) {
  editingId = list ? list.id : null;
  $("liste-form-baslik").textContent = list ? `Düzenle: ${list.name}` : "Yeni Liste";
  $("liste-form").reset();
  if (list) fillForm($("liste-form"), { ...list, is_opac_visible: list.is_opac_visible });
  formBaseline = formSnapshotValue();
  show($("liste-form-kart"), true);
  $("liste-form").querySelector("[name=name]").focus();
}

async function saveForm() {
  const form = $("liste-form");
  const values = readForm(form);
  const payload = {
    name: values.name,
    description: values.description || null,
    is_opac_visible: form.querySelector("[name=is_opac_visible]").checked,
  };
  if (editingId) {
    await api.patch(`/api/lists/${editingId}`, payload);
    toast("Liste güncellendi ✓", "success");
  } else {
    await api.post("/api/lists", payload);
    toast("Liste eklendi ✓", "success");
  }
  formBaseline = "";
  show($("liste-form-kart"), false);
  await refreshList();
}

// ── Detay çekmecesi ───────────────────────────────────

function renderItems(items) {
  $("ld-kitaplar").innerHTML = items
    .map(
      (item) => `<li data-edition="${item.edition_id}">${esc(item.title)}
        <button type="button" class="btn-icon" data-kitap-cikar="${item.edition_id}" title="Listeden çıkar"
                aria-label="${esc(item.title)} kitabını listeden çıkar">✕</button></li>`
    )
    .join("");
  show($("ld-kitaplar-bos"), items.length === 0);
}

function renderMembers(progressItems) {
  $("ld-uyeler").innerHTML = progressItems
    .map(
      (entry) => `
      <li data-member="${entry.member_id}">
        <div>${esc(entry.member_name)}${entry.class_name ? ` (${esc(entry.class_name)})` : ""}
          — ${entry.completed}/${entry.total}
          <button type="button" class="btn-icon" data-uye-cikar="${entry.member_id}" title="Atamayı kaldır"
                  aria-label="${esc(entry.member_name)} atamasını kaldır">✕</button>
        </div>
        ${progressBar(entry.fraction)}
      </li>`
    )
    .join("");
  show($("ld-uyeler-bos"), progressItems.length === 0);
}

async function openDetail(listId) {
  const detail = await api.get(`/api/lists/${listId}`);
  currentListId = listId;
  $("ld-ad").textContent = detail.name;
  $("ld-aciklama").textContent = detail.description || "";
  $("ld-opac-gorunur").checked = Boolean(detail.is_opac_visible);
  renderItems(detail.items);
  const progress = await api.get(`/api/lists/${listId}/progress`);
  renderMembers(progress.items);
  show($("liste-detay"), true);
}

async function refreshDetail() {
  if (currentListId === null) return;
  await openDetail(currentListId);
}

async function addBookByQuery(query) {
  const trimmed = query.trim();
  if (!trimmed) { toast("Önce kitap adı girin", "error"); return; }
  const results = await api.get(`/api/books?q=${encodeURIComponent(trimmed)}&limit=5`);
  if (results.items.length === 0) { toast("Bu adla kitap bulunamadı", "error"); return; }
  if (results.items.length > 1) { toast("Birden çok eşleşme var; daha özel yazın", "error"); return; }
  await api.post(`/api/lists/${currentListId}/items`, { edition_id: results.items[0].edition_id });
  toast(`✓ "${results.items[0].title}" listeye eklendi`, "success");
  $("ld-kitap-ara").value = "";
  await refreshDetail();
  await refreshList();
}

async function addMemberByQuery(query) {
  const trimmed = query.trim();
  if (!trimmed) { toast("Önce üye no ya da adı girin", "error"); return; }
  let member = null;
  try {
    member = await api.get(`/api/members/by-number/${encodeURIComponent(trimmed)}`);
  } catch { /* okul numarası değil; ada göre aramaya düş */ }
  if (!member) {
    const results = await api.get(`/api/members?q=${encodeURIComponent(trimmed)}&limit=2`);
    if (results.items.length === 1) member = results.items[0];
    else if (results.items.length === 0) { toast("Bu numarayla/adla üye bulunamadı", "error"); return; }
    else { toast("Birden çok eşleşme var; okul numarasıyla arayın", "error"); return; }
  }
  await api.post(`/api/lists/${currentListId}/assign`, { member_id: member.id });
  toast(`✓ ${member.full_name} atandı`, "success");
  $("ld-uye-ara").value = "";
  await refreshDetail();
}

async function importTemplate() {
  try {
    const result = await api.post("/api/lists/template/100-temel-eser", {});
    toast(
      `Şablon içe aktarıldı: ${result.matched.length} eşleşti, ${result.unmatched.length} katalogda bulunamadı.`,
      "success"
    );
    await refreshList();
  } catch (error) { err(error); }
}

// ── Olay bağlama ───────────────────────────────────────

function bind() {
  if (bound) return;
  bound = true;

  $("liste-yeni").addEventListener("click", () => openForm());
  $("liste-form-vazgec").addEventListener("click", async () => {
    if (!(await canLeave())) return;
    formBaseline = "";
    editingId = null;
    show($("liste-form-kart"), false);
  });
  $("liste-form").addEventListener("submit", (event) => {
    event.preventDefault();
    saveForm().catch(err);
  });
  $("liste-sablon").addEventListener("click", () => importTemplate());

  $("liste-tablo").addEventListener("click", async (event) => {
    const openId = event.target.dataset.ac;
    const editId = event.target.dataset.duzenle;
    const delId = event.target.dataset.sil;
    try {
      if (openId) { await openDetail(Number(openId)); return; }
      if (editId) {
        const list = lists.find((item) => item.id === Number(editId));
        if (list) openForm(list);
        return;
      }
      if (delId) {
        const list = lists.find((item) => item.id === Number(delId));
        if (!(await confirmBox(`"${list?.name || "Liste"}" kalıcı olarak silinecek. Emin misiniz?`))) return;
        await api.del(`/api/lists/${delId}`);
        toast("Liste silindi", "success");
        await refreshList();
      }
    } catch (error) { err(error); }
  });

  $("liste-detay-kapat").addEventListener("click", () => {
    show($("liste-detay"), false);
    currentListId = null;
  });
  $("liste-detay").addEventListener("dialogcancel", (event) => {
    event.preventDefault();
    show($("liste-detay"), false);
    currentListId = null;
  });
  $("ld-opac-gorunur").addEventListener("change", async (event) => {
    try {
      await api.patch(`/api/lists/${currentListId}`, { is_opac_visible: event.target.checked });
      toast(event.target.checked ? "OPAC'ta görünür ✓" : "OPAC'tan gizlendi", "success");
      await refreshList();
    } catch (error) { err(error); }
  });
  $("ld-kitap-ara").addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    addBookByQuery(event.target.value).catch(err);
  });
  $("ld-kitaplar").addEventListener("click", async (event) => {
    const editionId = event.target.dataset.kitapCikar;
    if (!editionId) return;
    try {
      await api.del(`/api/lists/${currentListId}/items/${editionId}`);
      await refreshDetail();
      await refreshList();
    } catch (error) { err(error); }
  });
  $("ld-uye-ekle").addEventListener("click", () => addMemberByQuery($("ld-uye-ara").value).catch(err));
  $("ld-uye-ara").addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    addMemberByQuery(event.target.value).catch(err);
  });
  $("ld-uyeler").addEventListener("click", async (event) => {
    const memberId = event.target.dataset.uyeCikar;
    if (!memberId) return;
    try {
      await api.del(`/api/lists/${currentListId}/assign/${memberId}`);
      await refreshDetail();
    } catch (error) { err(error); }
  });
  $("liste-sil").addEventListener("click", async () => {
    if (currentListId === null) return;
    if (!(await confirmBox("Bu liste kalıcı olarak silinecek. Emin misiniz?"))) return;
    try {
      await api.del(`/api/lists/${currentListId}`);
      toast("Liste silindi", "success");
      show($("liste-detay"), false);
      currentListId = null;
      await refreshList();
    } catch (error) { err(error); }
  });
}

export function enter() {
  bind();
  refreshList().catch(err);
}

export function leave() {
  listController?.abort();
  if (!$("liste-form-kart").hidden) {
    formBaseline = "";
    editingId = null;
    show($("liste-form-kart"), false);
  }
  show($("liste-detay"), false);
  currentListId = null;
}
