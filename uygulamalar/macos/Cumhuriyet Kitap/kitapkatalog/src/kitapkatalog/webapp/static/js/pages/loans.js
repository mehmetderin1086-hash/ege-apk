// Ödünç işlemleri: barkodla ver/iade, aktif-geciken-geçmiş listeleri.

import { api } from "../api.js";
import { bindTabs, confirmBox, debounce, esc, fmtCount, show, toast } from "../ui.js";
import { attachScanner } from "../scanner.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");
const PAGE_SIZE = 50;
const MAX_SESSION_TRANSACTIONS = 30;

let bound = false;
let selectedMember = null;
let tab = "active";
let offset = 0;
let memberSearchController = null;
let tableController = null;
let transactionSequence = 0;
const sessionTransactions = [];
const inFlightLoanActions = new Map();

const TRANSACTION_LABELS = {
  checkout: "Ödünç",
  return: "İade",
  extend: "Uzatma",
};

function transactionTime() {
  return new Intl.DateTimeFormat("tr-TR", {
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).format(new Date());
}

function renderTransaction(entry, { scroll = false } = {}) {
  const list = $("od-son-islemler");
  let item = list.querySelector(`[data-sequence="${entry.sequence}"]`);
  if (!item) {
    item = document.createElement("li");
    item.dataset.sequence = String(entry.sequence);
    item.setAttribute("aria-atomic", "true");
    list.appendChild(item);
  }
  item.className = `banko-islem ${entry.status}`;
  const state = entry.status === "pending"
    ? "İşleniyor…"
    : entry.status === "success" ? "Başarılı ✓" : "Başarısız";
  item.innerHTML = `
    <span class="banko-islem-tur">${TRANSACTION_LABELS[entry.kind]}</span>
    <span class="banko-islem-main">
      <strong>${esc(entry.title)}</strong>
      <span class="banko-islem-meta">
        <span class="banko-islem-kod">Kod: ${esc(entry.code || "—")}</span>
        <span>Üye: ${esc(entry.member || "—")}</span>
        <time>${esc(entry.time)}</time>
        ${entry.detail ? `<span>${esc(entry.detail)}</span>` : ""}
      </span>
    </span>
    <span class="banko-islem-durum">${state}</span>
    ${entry.status === "error" && entry.retryAction
      ? `<button class="btn banko-islem-yeniden" type="button" data-retry="${entry.sequence}">
           Aynı işlemi güvenle yeniden dene
         </button>`
      : ""}
    ${entry.holdReady
      ? `<button class="btn banko-islem-fis" type="button" data-hold-slip="${entry.holdReady.hold_id}">
           🖨️ Ayırma fişi yazdır (${esc(entry.holdReady.member_name)})
         </button>`
      : ""}`;
  show($("od-son-islemler-bos"), sessionTransactions.length === 0);
  $("od-son-islem-sayi").textContent = `${sessionTransactions.length} / ${MAX_SESSION_TRANSACTIONS}`;
  if (scroll) item.scrollIntoView({
    block: "nearest",
    behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
  });
}

function startTransaction(kind, code, member) {
  const entry = {
    sequence: ++transactionSequence,
    requestId: crypto.randomUUID(),
    kind,
    code,
    member,
    time: transactionTime(),
    title: "İşleniyor…",
    detail: "",
    status: "pending",
    running: false,
    retryAction: null,
  };
  sessionTransactions.push(entry);
  if (sessionTransactions.length > MAX_SESSION_TRANSACTIONS) {
    sessionTransactions.shift();
    $("od-son-islemler").firstElementChild?.remove();
  }
  renderTransaction(entry, { scroll: true });
  return entry;
}

function finishTransaction(entry, changes) {
  Object.assign(entry, changes);
  renderTransaction(entry);
}

function isRetryableTransactionError(error) {
  const status = Number(error?.status);
  return !Number.isInteger(status) || status >= 500;
}

async function executeTransaction({
  entry, request, onSuccess, failureTitle, restoreFocus, onSettled,
}) {
  if (entry.running) return;
  entry.running = true;
  entry.retryAction = null;
  finishTransaction(entry, {
    status: "pending",
    title: entry.title === "İşleniyor…" ? entry.title : "Yeniden deneniyor…",
    detail: "",
  });
  try {
    const loan = await request(entry.requestId);
    await onSuccess(loan);
  } catch (error) {
    if (isRetryableTransactionError(error)) {
      entry.retryAction = () => executeTransaction({
        entry, request, onSuccess, failureTitle, restoreFocus, onSettled,
      });
    }
    finishTransaction(entry, {
      status: "error",
      title: failureTitle,
      detail: error.message || String(error),
    });
    err(error);
  } finally {
    entry.running = false;
    restoreFocus?.();
    if (!entry.retryAction) onSettled?.();
  }
}

function setLoanActionPending(loanId, pending) {
  const row = $("od-tablo").querySelector(`tr[data-loan="${loanId}"]`);
  row?.querySelectorAll("button[data-return], button[data-extend]").forEach((button) => {
    button.disabled = pending;
    if (pending) button.setAttribute("aria-busy", "true");
    else button.removeAttribute("aria-busy");
  });
}

function scannerFocusRestorer(inputId) {
  const input = $(inputId);
  const restore = document.activeElement === input;
  return () => {
    if (!restore || $("sayfa-odunc").hidden) return;
    requestAnimationFrame(() => input.focus({ preventScroll: true }));
  };
}

function fmtDate(value) {
  if (!value) return "—";
  return value.slice(0, 10).split("-").reverse().join(".");
}

// ── Üye seçimi ───────────────────────────────────────

async function searchMembers() {
  memberSearchController?.abort();
  const controller = new AbortController();
  memberSearchController = controller;
  const query = $("od-uye-ara").value.trim();
  const list = $("od-uye-sonuc");
  if (query.length < 2) { show(list, false); return; }
  let data;
  try {
    data = await api.get(`/api/members?q=${encodeURIComponent(query)}&limit=8`, {
      signal: controller.signal,
    });
  } catch (error) {
    if (error.name === "AbortError") return;
    throw error;
  }
  list.innerHTML = data.items
    .map(
      (member) => `
      <li data-id="${member.id}" tabindex="0" role="button" data-key-activate
          aria-label="${esc(member.full_name)} üyesini seç">
        <strong>${esc(member.full_name)}</strong>
        <span class="src">${esc(member.school_number || "personel")} · ${esc(member.class_name || "—")}</span>
      </li>`
    )
    .join("");
  show(list, data.items.length > 0);
}

async function resolveMemberInput() {
  const value = $("od-uye-ara").value.trim();
  if (!value) return;
  // Önce okul numarası TAM eşleşmesi: kart/numara okutma tek adımda üye seçer.
  try {
    const member = await api.get(`/api/members/by-number/${encodeURIComponent(value)}`);
    await selectMember(member.id);
    return;
  } catch {
    // Numara değil ya da kayıtlı değil; ada göre aramaya düş.
  }
  const data = await api.get(`/api/members?q=${encodeURIComponent(value)}&limit=8`);
  if (data.items.length === 1) {
    await selectMember(data.items[0].id);
  } else if (data.items.length === 0) {
    toast("Bu numarayla/adla üye bulunamadı", "error");
  } else {
    toast("Birden çok eşleşme var; listeden seçin", "info");
  }
}

function clearMember() {
  selectedMember = null;
  show($("od-uye-kart"), false);
  show($("od-uye-sonuc"), false);
  $("od-uye-ara").value = "";
  $("od-uye-ara").focus();
}

async function selectMember(memberId) {
  const member = await api.get(`/api/members/${memberId}`);
  selectedMember = member;
  show($("od-uye-sonuc"), false);
  $("od-uye-ara").value = member.full_name;
  $("od-uye-ad").textContent = member.full_name;
  $("od-uye-detay").textContent =
    `${member.school_number ? "No " + member.school_number + " · " : ""}${member.class_name || ""}`;
  show($("od-uye-kart"), true);
  await refreshMemberLoans();
  $("od-ver-kod").focus();
}

async function refreshMemberLoans() {
  if (!selectedMember) return;
  const data = await api.get(`/api/loans?status=active&member_id=${selectedMember.id}&limit=20`);
  const overdue = data.items.filter((loan) => loan.overdue);
  const warning = $("od-uye-uyari");
  if (overdue.length > 0) {
    warning.textContent = `⚠️ ${overdue.length} gecikmiş kitabı var!`;
    show(warning, true);
  } else show(warning, false);
  $("od-uye-aktif").innerHTML = data.items
    .map(
      (loan) =>
        `<li>${esc(loan.title)} · son gün ${fmtDate(loan.due_at)}${loan.overdue ? " 🔴" : ""}</li>`
    )
    .join("");
}

// ── Ver / iade ───────────────────────────────────────

async function checkout(code) {
  const member = selectedMember;
  const restoreFocus = scannerFocusRestorer("od-ver-kod");
  const entry = startTransaction("checkout", code, member?.full_name || "Üye seçilmedi");
  if (!member) {
    finishTransaction(entry, {
      status: "error", title: "Ödünç verilemedi", detail: "Önce üye seçin.",
    });
    toast("Önce üye seçin", "error");
    restoreFocus();
    return;
  }
  await executeTransaction({
    entry,
    request: (requestId) => api.post("/api/loans", {
      member_id: member.id,
      code,
      request_id: requestId,
    }),
    onSuccess: async (loan) => {
      finishTransaction(entry, {
        status: "success",
        title: loan.title,
        member: loan.member_name,
        code: loan.inventory_code || code,
        detail: `Son gün ${fmtDate(loan.due_at)}`,
      });
      toast(`✓ "${loan.title}" → ${loan.member_name} (son gün ${fmtDate(loan.due_at)})`, "success");
      await Promise.all([refreshMemberLoans(), refreshTable(), refreshBadges()]).catch(err);
    },
    failureTitle: "Ödünç verilemedi",
    restoreFocus,
  });
}

async function returnByCode(code) {
  const restoreFocus = scannerFocusRestorer("od-iade-kod");
  const entry = startTransaction("return", code, "Üye çözümleniyor");
  await executeTransaction({
    entry,
    request: (requestId) => api.post("/api/loans/return-by-code", {
      code,
      request_id: requestId,
    }),
    onSuccess: async (loan) => {
      const late = loan.days_overdue > 0 ? ` (${loan.days_overdue} gün gecikmeli)` : "";
      finishTransaction(entry, {
        status: "success",
        title: loan.title,
        member: loan.member_name,
        code: loan.inventory_code || code,
        detail: loan.days_overdue > 0 ? `${loan.days_overdue} gün gecikmeli` : "Zamanında iade",
        holdReady: loan.hold_ready || null,
      });
      $("od-iade-sonuc").textContent = `✓ "${loan.title}" iade alındı — ${loan.member_name}${late}`;
      toast("İade alındı ✓", "success");
      if (loan.hold_ready) {
        toast(`📦 Rezervasyon hazır: ${loan.hold_ready.member_name} bekliyor`, "info");
      }
      await Promise.all([refreshMemberLoans(), refreshTable(), refreshBadges()]).catch(err);
      if (tab === "holds") refreshHoldsTable().catch(err);
    },
    failureTitle: "İade alınamadı",
    restoreFocus,
  });
}

// ── Liste ────────────────────────────────────────────

async function refreshTable() {
  tableController?.abort();
  const controller = new AbortController();
  tableController = controller;
  const params = new URLSearchParams({
    status: tab,
    q: $("od-liste-ara").value.trim(),
    limit: PAGE_SIZE,
    offset,
  });
  let data;
  try {
    data = await api.get(`/api/loans?${params}`, { signal: controller.signal });
  } catch (error) {
    if (error.name === "AbortError") return;
    throw error;
  }
  let items = data.items;
  const grouped = tab === "overdue" && $("od-grupla").checked;
  if (grouped) {
    items = [...items].sort((a, b) =>
      (a.member_class || "ZZZ").localeCompare(b.member_class || "ZZZ", "tr") ||
      a.member_name.localeCompare(b.member_name, "tr")
    );
  }
  let lastClass = null;
  $("od-tablo").innerHTML = items
    .map((loan) => {
      let header = "";
      if (grouped) {
        const cls = loan.member_class || (loan.member_type === "staff" ? "Personel" : "Sınıfsız");
        if (cls !== lastClass) {
          lastClass = cls;
          const count = items.filter(
            (item) => (item.member_class || (item.member_type === "staff" ? "Personel" : "Sınıfsız")) === cls
          ).length;
          header = `<tr class="grup-baslik"><td colspan="7">${esc(cls)} (${count} kitap)</td></tr>`;
        }
      }
      const status = loan.returned_at
        ? `İade: ${fmtDate(loan.returned_at)}`
        : loan.overdue
          ? `<span class="geciken">${loan.days_overdue} gün gecikti</span>`
          : "Ödünçte";
      const actionPending = inFlightLoanActions.has(String(loan.id));
      const pendingAttributes = actionPending ? ' disabled aria-busy="true"' : "";
      const actions = loan.returned_at
        ? ""
        : `<button class="btn" data-return="${loan.id}"${pendingAttributes}>İade</button>
           <button class="btn" data-extend="${loan.id}"${pendingAttributes}>Uzat</button>`;
      return `${header}
      <tr data-loan="${loan.id}" data-title="${esc(loan.title)}"
          data-member="${esc(loan.member_name)}" data-code="${esc(loan.inventory_code || `#${loan.id}`)}">
        <td>${esc(loan.title)}${loan.inventory_code ? `<br><small>${esc(loan.inventory_code)}</small>` : ""}</td>
        <td>${esc(loan.member_name)}</td>
        <td>${esc(loan.member_class || "—")}</td>
        <td>${fmtDate(loan.loaned_at)}</td>
        <td>${fmtDate(loan.due_at)}</td>
        <td>${status}</td>
        <td>${actions}</td>
      </tr>`;
    })
    .join("");
  show($("od-bos"), data.total === 0);
  $("od-sayfa-bilgi").textContent =
    data.total === 0
      ? "0 kayıt"
      : `${offset + 1}–${Math.min(offset + PAGE_SIZE, data.total)} / ${fmtCount(data.total)}`;
  $("od-sayfa-geri").disabled = offset === 0;
  $("od-sayfa-ileri").disabled = offset + PAGE_SIZE >= data.total;
}

// ── Rezervasyonlar ───────────────────────────────────

let holdsController = null;

async function refreshHoldsTable() {
  holdsController?.abort();
  const controller = new AbortController();
  holdsController = controller;
  let active, ready;
  try {
    [active, ready] = await Promise.all([
      api.get("/api/holds?status=active", { signal: controller.signal }),
      api.get("/api/holds?status=ready", { signal: controller.signal }),
    ]);
  } catch (error) {
    if (error.name === "AbortError") return;
    throw error;
  }
  const items = [...active.items, ...ready.items].sort((a, b) =>
    a.created_at.localeCompare(b.created_at)
  );
  $("od-rezervasyon-tablo").innerHTML = items
    .map(
      (hold) => `
      <tr data-hold="${hold.id}">
        <td>${esc(hold.title)}</td>
        <td>${esc(hold.member_name)}${hold.school_number ? `<br><small>${esc(hold.school_number)}</small>` : ""}</td>
        <td>${hold.status === "ready" ? "Hazır — alınmayı bekliyor" : "Sırada"}</td>
        <td>${hold.expires_at ? fmtDate(hold.expires_at) : "—"}</td>
        <td>
          ${hold.status === "ready" ? `<button class="btn" data-hold-fis="${hold.id}">🖨️ Fiş</button>` : ""}
          <button class="btn" data-hold-iptal="${hold.id}">İptal</button>
        </td>
      </tr>`
    )
    .join("");
  show($("od-rezervasyon-bos"), items.length === 0);
  $("od-rezervasyon-sayi").textContent = items.length;
  show($("od-rezervasyon-sayi"), items.length > 0);
}

async function refreshBadges() {
  try {
    const stats = await api.get("/api/loans/stats");
    $("od-aktif-sayi").textContent = stats.active;
    show($("od-aktif-sayi"), stats.active > 0);
    $("od-geciken-sayi").textContent = stats.overdue;
    show($("od-geciken-sayi"), stats.overdue > 0);
  } catch { /* geçici */ }
}

function bind() {
  if (bound) return;
  bound = true;

  $("od-uye-ara").addEventListener("input", debounce(() => searchMembers().catch(err), 250));
  $("od-uye-ara").addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    resolveMemberInput().catch(err);
  });
  $("od-uye-sonuc").addEventListener("click", (event) => {
    const item = event.target.closest("li[data-id]");
    if (item) selectMember(Number(item.dataset.id)).catch(err);
  });
  $("od-uye-birak").addEventListener("click", clearMember);

  attachScanner($("od-ver-kod"), checkout, { refocus: false });
  attachScanner($("od-iade-kod"), (code) => returnByCode(code), { refocus: false });
  $("od-son-islemler").addEventListener("click", (event) => {
    const slipButton = event.target.closest("button[data-hold-slip]");
    if (slipButton) {
      window.open(`/print/hold-slip?hold_id=${slipButton.dataset.holdSlip}`, "_blank");
      return;
    }
    const button = event.target.closest("button[data-retry]");
    if (!button) return;
    const entry = sessionTransactions.find(
      (candidate) => candidate.sequence === Number(button.dataset.retry)
    );
    entry?.retryAction?.();
  });

  bindTabs($("odunc-sekmeler"), (button) => {
    tab = button.dataset.odtab;
    offset = 0;
    show($("od-gecikme-yazdir"), tab === "overdue");
    show($("od-grupla-kutu"), tab === "overdue");
    if (tab === "holds") refreshHoldsTable().catch(err);
    else refreshTable().catch(err);
  });
  $("od-rezervasyon-tablo").addEventListener("click", async (event) => {
    const slipId = event.target.dataset.holdFis;
    if (slipId) {
      window.open(`/print/hold-slip?hold_id=${slipId}`, "_blank");
      return;
    }
    const cancelId = event.target.dataset.holdIptal;
    if (!cancelId) return;
    if (!(await confirmBox("Bu rezervasyon iptal edilecek. Emin misiniz?"))) return;
    try {
      await api.post(`/api/holds/${cancelId}/cancel`);
      toast("Rezervasyon iptal edildi", "success");
      await Promise.all([refreshHoldsTable(), refreshBadges()]);
    } catch (error) {
      err(error);
    }
  });
  $("od-gecikme-yazdir").addEventListener("click", () => window.open("/print/overdue", "_blank"));
  $("od-grupla").addEventListener("change", () => refreshTable().catch(err));
  $("od-liste-ara").addEventListener("input", debounce(() => { offset = 0; refreshTable().catch(err); }, 250));
  $("od-sayfa-geri").addEventListener("click", () => { offset = Math.max(0, offset - PAGE_SIZE); refreshTable().catch(err); });
  $("od-sayfa-ileri").addEventListener("click", () => { offset += PAGE_SIZE; refreshTable().catch(err); });

  $("od-tablo").addEventListener("click", (event) => {
    const returnId = event.target.dataset.return;
    const extendId = event.target.dataset.extend;
    if (!returnId && !extendId) return;
    const row = event.target.closest("tr[data-loan]");
    const kind = returnId ? "return" : "extend";
    const loanId = returnId || extendId;
    const actionKey = String(loanId);
    if (inFlightLoanActions.has(actionKey)) return;
    const entry = startTransaction(
      kind,
      row?.dataset.code || `#${loanId}`,
      row?.dataset.member || "—"
    );
    inFlightLoanActions.set(actionKey, entry);
    setLoanActionPending(actionKey, true);
    executeTransaction({
      entry,
      request: (requestId) => api.post(
        `/api/loans/${loanId}/${returnId ? "return" : "extend"}`,
        { request_id: requestId }
      ),
      onSuccess: async (loan) => {
        if (returnId) {
          finishTransaction(entry, {
            status: "success", title: loan.title, member: loan.member_name,
            code: loan.inventory_code || entry.code, detail: "Listeden iade alındı",
            holdReady: loan.hold_ready || null,
          });
          toast("İade alındı ✓", "success");
          if (loan.hold_ready) {
            toast(`📦 Rezervasyon hazır: ${loan.hold_ready.member_name} bekliyor`, "info");
          }
        } else {
          finishTransaction(entry, {
            status: "success", title: loan.title, member: loan.member_name,
            code: loan.inventory_code || entry.code, detail: `Son gün ${fmtDate(loan.due_at)}`,
          });
          toast(`Süre uzatıldı → ${fmtDate(loan.due_at)} ✓`, "success");
        }
        await Promise.all([refreshTable(), refreshBadges(), refreshMemberLoans()]).catch(err);
        if (tab === "holds") refreshHoldsTable().catch(err);
      },
      failureTitle: returnId ? "İade alınamadı" : "Süre uzatılamadı",
      onSettled: () => {
        if (inFlightLoanActions.get(actionKey) === entry) {
          inFlightLoanActions.delete(actionKey);
          setLoanActionPending(actionKey, false);
        }
      },
    });
  });
}

export function enter() {
  bind();
  show($("od-son-islemler-bos"), sessionTransactions.length === 0);
  $("od-son-islem-sayi").textContent = `${sessionTransactions.length} / ${MAX_SESSION_TRANSACTIONS}`;
  refreshTable().catch(err);
  refreshBadges();
  refreshHoldsTable().catch(err);
}

export function leave() {
  memberSearchController?.abort();
  tableController?.abort();
  holdsController?.abort();
}
