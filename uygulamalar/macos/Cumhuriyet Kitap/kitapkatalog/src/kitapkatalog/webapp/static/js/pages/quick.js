// Hızlı Kayıt: barkod okut → kayıtlıysa +1 nüsha, değilse kısa form.

import { api } from "../api.js";
import { confirmBox, debounce, esc, formSnapshot, readForm, show, toast } from "../ui.js";
import { attachScanner } from "../scanner.js";
import { refreshDatalists } from "../main.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");

let bound = false;
let pendingBook = null; // "+1 nüsha" bekleyen kayıtlı kitap
let quickFormBaseline = "";
const sessionLog = [];

async function refreshNextCode() {
  try {
    const data = await api.get("/api/quick/next-code");
    $("hk-sonraki-kod").textContent = data.next_code;
  } catch { /* önemsiz */ }
}

function renderLog() {
  $("hk-sayac").textContent = sessionLog.length;
  show($("hk-sayac"), sessionLog.length > 0);
  show($("hk-bos"), sessionLog.length === 0);
  $("hk-son-liste").innerHTML = sessionLog
    .slice(-30)
    .reverse()
    .map(
      (entry) => `
      <tr>
        <td>${esc(entry.title)}</td>
        <td>${esc(entry.codes.join(", ") || "—")}</td>
        <td>${entry.kind}</td>
      </tr>`
    )
    .join("");
}

function resetPanels({ focus = true } = {}) {
  pendingBook = null;
  quickFormBaseline = "";
  $("hk-form").reset();
  show($("hk-sonuc"), false);
  show($("hk-form-kart"), false);
  if (focus) $("hk-kod").focus();
}

export function isDirty() {
  return Boolean(
    !$("hk-form-kart").hidden && quickFormBaseline &&
    quickFormBaseline !== formSnapshot($("hk-form"))
  );
}

export function canLeave() {
  if (!isDirty()) return Promise.resolve(true);
  return confirmBox("Hızlı kayıt formunda kaydedilmemiş değişiklikler var. Vazgeçilsin mi?");
}

async function discardPanels() {
  if (!(await canLeave())) return false;
  resetPanels();
  return true;
}

async function handleCode(code, { isbn }) {
  if (isDirty() && !(await canLeave())) return;
  if (isDirty()) resetPanels({ focus: false });
  if (!isbn) {
    toast("Bu bir ISBN barkodu değil; 10 ya da 13 haneli ISBN okutun.", "error");
    return;
  }
  try {
    const data = await api.get(`/api/quick/isbn/${isbn}`);
    if (data.found) {
      pendingBook = data.book;
      const loanNote = data.on_loan > 0 ? `, ${data.on_loan} ödünçte` : "";
      $("hk-sonuc-metin").innerHTML =
        `<strong>${esc(data.book.title)}</strong> — ${esc(data.book.authors || "")}` +
        `<br>Kayıtlı: ${data.active_copies} nüsha${loanNote}. Yeni nüshaya ${esc(data.next_code)} atanacak.`;
      show($("hk-form-kart"), false);
      show($("hk-sonuc"), true);
      $("hk-nusha-ekle").focus();
    } else {
      show($("hk-sonuc"), false);
      $("hk-form").reset();
      $("hk-form").querySelector("[name=isbn]").value = isbn;
      show($("hk-benzer"), false);
      show($("hk-form-kart"), true);
      quickFormBaseline = formSnapshot($("hk-form"));
      $("hk-form").querySelector("[name=title]").focus();
    }
  } catch (error) { err(error); }
}

async function addCopy() {
  if (!pendingBook) return;
  try {
    const result = await api.post(`/api/books/${pendingBook.edition_id}/copies`, {
      count: 1,
      auto_inventory: true,
      // Yeni nüsha kitabın dolabını devralsın; yoksa raf haritasında
      // "konumsuz" görünür.
      location: pendingBook.location || null,
    });
    sessionLog.push({
      title: pendingBook.title,
      codes: result.inventory_codes,
      kind: "+1 nüsha",
    });
    toast(`✓ ${pendingBook.title} → ${result.inventory_codes.join(", ")}`, "success");
    renderLog();
    refreshNextCode();
    resetPanels();
  } catch (error) { err(error); }
}

async function saveNewBook() {
  const values = readForm($("hk-form"));
  if (!values.title?.trim()) { toast("Başlık zorunlu", "error"); return; }
  const { acquisition_method, acquisition_date, acquisition_price, ...rest } = values;
  try {
    const book = await api.post("/api/books", {
      ...rest,
      copy_count: Number(values.copy_count || 1),
      auto_inventory: true,
      copy: (acquisition_method || acquisition_date || acquisition_price)
        ? { acquisition_method: acquisition_method || null, acquisition_date: acquisition_date || null, acquisition_price: acquisition_price || null }
        : undefined,
    });
    const codes = (book.copies || []).map((copy) => copy.inventory_code).filter(Boolean);
    sessionLog.push({ title: book.title, codes, kind: "yeni kayıt" });
    toast(`✓ ${book.title} kaydedildi (${codes.join(", ")})`, "success");
    renderLog();
    refreshNextCode();
    refreshDatalists();
    resetPanels();
  } catch (error) { err(error); }
}

async function checkSimilar() {
  const title = $("hk-form").querySelector("[name=title]").value.trim();
  const box = $("hk-benzer");
  if (title.length < 3) { show(box, false); return; }
  try {
    const data = await api.get(`/api/books?q=${encodeURIComponent(title)}&limit=3`);
    if ((data.items || []).length > 0) {
      box.innerHTML =
        "⚠️ Benzer kayıtlar var: " +
        data.items.map((book) => `<strong>${esc(book.title)}</strong>`).join(" · ") +
        " — aynı kitapsa formu bırakıp barkodu/kaydı Kütüphane'den açın.";
      show(box, true);
    } else show(box, false);
  } catch { /* önemsiz */ }
}

function bind() {
  if (bound) return;
  bound = true;

  attachScanner($("hk-kod"), handleCode, { refocus: false });
  $("hk-nusha-ekle").addEventListener("click", () => addCopy());
  $("hk-vazgec").addEventListener("click", () => discardPanels().catch(err));
  document.addEventListener("keydown", (event) => {
    if ($("sayfa-hizli").hidden) return;
    if (event.key === "Escape") { discardPanels().catch(err); return; }
    if (event.key === "Enter" && pendingBook && !$("hk-sonuc").hidden
        && document.activeElement === $("hk-nusha-ekle")) {
      event.preventDefault();
      addCopy();
    }
    if ((event.ctrlKey || event.metaKey) && event.key === "Enter" && !$("hk-form-kart").hidden) {
      event.preventDefault();
      saveNewBook();
    }
  });

  $("hk-form").addEventListener("submit", (event) => {
    event.preventDefault();
    saveNewBook();
  });
  $("hk-form-vazgec").addEventListener("click", () => discardPanels().catch(err));
  $("hk-form").querySelector("[name=title]").addEventListener(
    "input", debounce(checkSimilar, 350)
  );
}

export function enter() {
  bind();
  refreshNextCode();
  renderLog();
  $("hk-kod").focus();
}

export function leave() {
  resetPanels({ focus: false });
}
