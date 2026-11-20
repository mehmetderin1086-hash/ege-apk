// Gezinme + sayfa modülleri + genel iş göstergesi.

import { api } from "./api.js";
import { confirmBox, esc, installKeyboardActivation, observeScrollableTables, show } from "./ui.js";
import * as overview from "./pages/overview.js";
import * as library from "./pages/library.js";
import * as lists from "./pages/lists.js";
import * as challenges from "./pages/challenges.js";
import * as imports from "./pages/imports.js";
import * as voice from "./pages/voice.js";
import * as approval from "./pages/approval.js";
import * as exportsPage from "./pages/exports.js";
import * as engines from "./pages/engines.js";
import * as members from "./pages/members.js";
import * as loans from "./pages/loans.js";
import * as stocktake from "./pages/stocktake.js";
import * as discards from "./pages/discards.js";
import * as quick from "./pages/quick.js";
import * as reports from "./pages/reports.js";
import * as settingsPage from "./pages/settings.js";
import * as shelfmap from "./pages/shelfmap.js";
import * as printing from "./pages/printing.js";

const PAGES = {
  genel: overview,
  hizli: quick,
  kutuphane: library,
  listeler: lists,
  aktarim: imports,
  ses: voice,
  onay: approval,
  odunc: loans,
  yarisma: challenges,
  harita: shelfmap,
  yazdir: printing,
  sayim: stocktake,
  dusum: discards,
  raporlar: reports,
  uyeler: members,
  disari: exportsPage,
  motorlar: engines,
  ayarlar: settingsPage,
};

let current = null;
let initialNavigation = true;
let approvedHash = null;
let navigationBusy = false;

const mobileMedia = window.matchMedia("(max-width: 900px)");
const sidebar = document.getElementById("ana-menu");
const menuButton = document.getElementById("menu-dugme");
const menuOverlay = document.getElementById("menu-overlay");
const mainContent = document.getElementById("ana-icerik");
let mobileMenuOpen = false;

function mobileFocusables() {
  return [menuButton, ...sidebar.querySelectorAll('a[href], button:not([disabled])')]
    .filter((element) => element.getClientRects().length > 0);
}

function setMobileMenu(open, { restoreFocus = true } = {}) {
  mobileMenuOpen = mobileMedia.matches && open;
  sidebar.classList.toggle("open", mobileMenuOpen);
  menuButton.setAttribute("aria-expanded", String(mobileMenuOpen));
  menuButton.setAttribute("aria-label", mobileMenuOpen ? "Ana menüyü kapat" : "Ana menüyü aç");
  show(menuOverlay, mobileMenuOpen);
  document.body.classList.toggle("nav-open", mobileMenuOpen);
  if (mobileMedia.matches) {
    sidebar.inert = !mobileMenuOpen;
    sidebar.setAttribute("aria-hidden", String(!mobileMenuOpen));
    mainContent.inert = mobileMenuOpen;
  } else {
    sidebar.inert = false;
    sidebar.removeAttribute("aria-hidden");
    mainContent.inert = false;
  }
  document.getElementById("alt-nav-menu")?.setAttribute("aria-expanded", String(mobileMenuOpen));
  if (mobileMenuOpen) {
    const first = sidebar.querySelector("a.active") || sidebar.querySelector("a, button");
    first?.focus({ preventScroll: true });
  } else if (restoreFocus && mobileMedia.matches) {
    menuButton.focus({ preventScroll: true });
  }
}

function bindMobileMenu() {
  menuButton.addEventListener("click", () => setMobileMenu(!mobileMenuOpen));
  // Alt gezinme çubuğundaki "Menü" düğmesi aynı off-canvas mekanizmasını tetikler.
  document.getElementById("alt-nav-menu")?.addEventListener("click", () => setMobileMenu(!mobileMenuOpen));
  menuOverlay.addEventListener("click", () => setMobileMenu(false));
  sidebar.addEventListener("click", (event) => {
    // Hash bağlantıları merkezi gezinme koruması onaylandıktan sonra kapanır.
    // OPAC gibi dış bağlantılar ise mevcut davranışı sürdürür.
    if (event.target.closest('a:not([href^="#"])') && mobileMedia.matches) {
      setMobileMenu(false, { restoreFocus: false });
    }
  });
  document.addEventListener("keydown", (event) => {
    if (!mobileMenuOpen) return;
    if (event.key === "Escape") {
      event.preventDefault();
      setMobileMenu(false);
      return;
    }
    if (event.key !== "Tab") return;
    const items = mobileFocusables();
    if (!items.length) return;
    const first = items[0];
    const last = items.at(-1);
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  });
  mobileMedia.addEventListener("change", () => setMobileMenu(false, { restoreFocus: false }));
  setMobileMenu(false, { restoreFocus: false });
}

function pageName(hash = location.hash) {
  const target = (hash || "#genel").slice(1).split("/")[0];
  return PAGES[target] ? target : "genel";
}

function pageHash(name = current) {
  return `#${name && PAGES[name] ? name : "genel"}`;
}

function currentModule() {
  return current ? PAGES[current] : null;
}

function hasUnsavedChanges() {
  const module = currentModule();
  if (!module?.isDirty) return false;
  try { return Boolean(module.isDirty()); }
  catch { return true; } // Veri kaybı yerine güvenli tarafta kal.
}

async function canLeaveCurrentPage() {
  const module = currentModule();
  if (!module) return true;
  if (module.canLeave) return Boolean(await module.canLeave());
  if (!hasUnsavedChanges()) return true;
  return confirmBox("Kaydedilmemiş değişiklikler var. Vazgeçilsin mi?");
}

function restoreFocus(element) {
  if (element instanceof HTMLElement && element.isConnected && !element.hidden) {
    element.focus({ preventScroll: true });
  }
}

function commitNavigation(hash = location.hash) {
  const name = pageName(hash);
  if (current && PAGES[current].leave) PAGES[current].leave();
  current = name;
  for (const key of Object.keys(PAGES)) {
    show(document.getElementById(`sayfa-${key}`), key === name);
  }
  document.querySelectorAll(".sidebar a, #alt-nav a").forEach((a) => {
    const active = a.dataset.page === name;
    a.classList.toggle("active", active);
    if (active) a.setAttribute("aria-current", "page");
    else a.removeAttribute("aria-current");
  });
  PAGES[name].enter();
  if (!initialNavigation) {
    requestAnimationFrame(() => mainContent.focus({ preventScroll: true }));
  }
  initialNavigation = false;
}

async function requestHashNavigation(targetHash, opener = document.activeElement) {
  const canonicalHash = pageHash(pageName(targetHash));
  if (canonicalHash === pageHash()) {
    if (mobileMedia.matches) setMobileMenu(false, { restoreFocus: false });
    mainContent.focus({ preventScroll: true });
    return;
  }
  if (navigationBusy) return;
  navigationBusy = true;
  try {
    if (!(await canLeaveCurrentPage())) {
      restoreFocus(opener);
      return;
    }
    if (mobileMedia.matches) setMobileMenu(false, { restoreFocus: false });
    approvedHash = canonicalHash;
    if (location.hash === canonicalHash) {
      approvedHash = null;
      commitNavigation(canonicalHash);
    } else {
      location.hash = canonicalHash;
    }
  } finally {
    navigationBusy = false;
  }
}

async function handleHashChange() {
  const requestedHash = pageHash(pageName(location.hash));
  if (approvedHash === requestedHash) {
    approvedHash = null;
    commitNavigation(requestedHash);
    return;
  }
  const priorHash = pageHash();
  const priorFocus = document.activeElement;
  if (!(await canLeaveCurrentPage())) {
    history.replaceState(null, "", `${location.pathname}${location.search}${priorHash}`);
    restoreFocus(priorFocus);
    return;
  }
  commitNavigation(requestedHash);
}

function bindProtectedNavigation() {
  document.addEventListener("click", (event) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey ||
        event.shiftKey || event.altKey) return;
    const link = event.target.closest('a[href^="#"]');
    if (!link || link.target || link.hasAttribute("download")) return;
    const targetHash = link.getAttribute("href");
    const targetName = (targetHash || "").slice(1).split("/")[0];
    // İçerik-atlama ve sayfa içi bağlantılar doğal tarayıcı davranışını korur.
    if (!PAGES[targetName]) return;
    event.preventDefault();
    requestHashNavigation(targetHash, link);
  });
  window.addEventListener("hashchange", () => { handleHashChange(); });
  window.addEventListener("beforeunload", (event) => {
    if (!hasUnsavedChanges()) return;
    event.preventDefault();
    event.returnValue = "";
  });
}

// Ortak autocomplete listelerini doldur (sayfalar arası paylaşılır).
export async function refreshDatalists() {
  const map = {
    "dl-yayinevi": "publisher",
    "dl-kategori": "category",
    "dl-dil": "language",
    "dl-dolap": "location",
    "dl-yazar": "author",
  };
  await Promise.all(Object.entries(map).map(async ([id, column]) => {
    try {
      const values = await api.get(`/api/meta/distinct/${column}`);
      const datalist = document.getElementById(id);
      datalist.replaceChildren(...values.slice(0, 200).map((value) => {
        const option = document.createElement("option");
        option.value = value;
        return option;
      }));
    } catch { /* açılışta katalog boş olabilir */ }
  }));
}

// Onay rozetini ve alt-sol iş göstergesini periyodik tazele.
let globalIndicatorsBusy = false;
const GLOBAL_INDICATOR_INTERVAL_MS = 15_000;

async function refreshGlobalIndicators() {
  if (document.hidden || globalIndicatorsBusy) return;
  globalIndicatorsBusy = true;
  try {
    const summary = await api.get("/api/status/summary");
    const { badges, jobs } = summary;
    const badge = document.getElementById("onay-rozet");
    const total = badges.pairs + badges.review;
    badge.textContent = total;
    show(badge, total > 0);

    const overdueBadge = document.getElementById("odunc-rozet");
    overdueBadge.textContent = badges.overdue;
    show(overdueBadge, badges.overdue > 0);

    const notifBadge = document.getElementById("bildirim-rozet");
    notifBadge.textContent = badges.notifications;
    show(notifBadge, badges.notifications > 0);

    const running = Object.values(jobs).filter((job) => job.status === "running");
    const indicator = document.getElementById("is-gosterge");
    show(indicator, running.length > 0);
    if (running.length > 0) {
      document.getElementById("is-gosterge-metin").textContent =
        running.map((job) => job.message || job.title).join(" · ");
    }
  } catch { /* sunucu meşgul olabilir; sonraki turda tekrar */ }
  finally { globalIndicatorsBusy = false; }
}

// ── Bildirim merkezi ─────────────────────────────────
const bildirimCekmece = document.getElementById("bildirim-cekmece");
const bildirimListe = document.getElementById("bildirim-liste");

function fmtNotificationTime(value) {
  if (!value) return "";
  try {
    return new Intl.DateTimeFormat("tr-TR", { dateStyle: "short", timeStyle: "short" }).format(
      new Date(value)
    );
  } catch {
    return value;
  }
}

function notificationTargetHash(item) {
  if (item.kind === "backup_failed") return "#ayarlar";
  if (item.member_id) return "#uyeler";
  return "#genel";
}

function renderNotifications(items) {
  bildirimListe.innerHTML = items
    .map((item) => {
      const unread = !item.read_at;
      return `
      <li class="bildirim-oge${unread ? " okunmamis" : ""}" data-id="${item.id}">
        <a href="${notificationTargetHash(item)}" class="bildirim-link">
          <strong>${esc(item.title)}</strong>
          <div class="hint">${esc(item.body || "")}</div>
          <time>${esc(fmtNotificationTime(item.created_at))}</time>
        </a>
        <div class="bildirim-eylemler">
          ${unread ? `<button class="btn-icon" type="button" data-oku="${item.id}" aria-label="Okundu işaretle">✓</button>` : ""}
          <button class="btn-icon" type="button" data-kapat="${item.id}" aria-label="Bildirimi kaldır">✕</button>
        </div>
      </li>`;
    })
    .join("");
  show(document.getElementById("bildirim-bos"), items.length === 0);
}

async function loadNotifications() {
  const unreadOnly = document.getElementById("bildirim-okunmamis").checked;
  const data = await api.get(`/api/notifications?unread=${unreadOnly}`);
  renderNotifications(data.items);
}

function bindNotifications() {
  const openDrawer = () => {
    show(bildirimCekmece, true);
    loadNotifications().catch(() => {});
  };
  document.getElementById("bildirim-dugme").addEventListener("click", openDrawer);
  document.querySelectorAll("[data-bildirim-ac]").forEach((el) => {
    el.addEventListener("click", (event) => {
      event.preventDefault();
      openDrawer();
    });
  });
  document.getElementById("bildirim-kapat").addEventListener("click", () => show(bildirimCekmece, false));
  bildirimCekmece.addEventListener("dialogcancel", (event) => {
    event.preventDefault();
    show(bildirimCekmece, false);
  });
  document.getElementById("bildirim-okunmamis").addEventListener("change", () => {
    loadNotifications().catch(() => {});
  });
  document.getElementById("bildirim-tumunu-oku").addEventListener("click", async () => {
    await api.post("/api/notifications/read-all");
    await loadNotifications();
    refreshGlobalIndicators();
  });
  bildirimListe.addEventListener("click", async (event) => {
    const okuId = event.target.dataset.oku;
    const kapatId = event.target.dataset.kapat;
    if (okuId) {
      event.preventDefault();
      await api.post(`/api/notifications/${okuId}/read`);
      await loadNotifications();
      refreshGlobalIndicators();
      return;
    }
    if (kapatId) {
      event.preventDefault();
      await api.post(`/api/notifications/${kapatId}/dismiss`);
      await loadNotifications();
      refreshGlobalIndicators();
      return;
    }
    const link = event.target.closest("a.bildirim-link");
    if (link) {
      const id = link.closest("li[data-id]")?.dataset.id;
      if (id) await api.post(`/api/notifications/${id}/read`).catch(() => {});
    }
  });
}

// ── Tema ─────────────────────────────────────────────
const THEME_ORDER = ["system", "light", "dark"];
const THEME_LABELS = { system: "🌗 Tema", light: "☀️ Açık", dark: "🌙 Koyu" };

export function currentTheme() {
  const stored = localStorage.getItem("kk-tema");
  return stored === "light" || stored === "dark" ? stored : "system";
}

export function applyTheme(theme) {
  if (theme === "light" || theme === "dark") {
    localStorage.setItem("kk-tema", theme);
    document.documentElement.dataset.theme = theme;
  } else {
    localStorage.removeItem("kk-tema");
    delete document.documentElement.dataset.theme;
  }
  const button = document.getElementById("tema-dugme");
  if (button) button.textContent = THEME_LABELS[currentTheme()];
}

document.getElementById("tema-dugme").addEventListener("click", () => {
  const next = THEME_ORDER[(THEME_ORDER.indexOf(currentTheme()) + 1) % THEME_ORDER.length];
  applyTheme(next);
});

// ── Okul adı ─────────────────────────────────────────
export function updateSchoolName(name) {
  const element = document.getElementById("okul-adi");
  element.textContent = name || "";
  show(element, Boolean(name));
  document.title = name ? `Cumhuriyet Kitap — ${name}` : "Cumhuriyet Kitap";
}

async function loadSchoolName() {
  try {
    const settings = await api.get("/api/settings");
    updateSchoolName(settings.school_name);
  } catch { /* açılışta önemsiz */ }
}

async function loadRuntimeInfo() {
  const version = document.getElementById("uygulama-surumu");
  try {
    const health = await api.get("/health");
    version.textContent = health.version
      ? `Cumhuriyet Kitap v${health.version} · Veri şeması ${health.schema_version ?? "?"}`
      : "Cumhuriyet Kitap";
  } catch {
    version.textContent = "Sürüm doğrulanamadı";
  }
}

bindMobileMenu();
bindProtectedNavigation();
bindNotifications();
installKeyboardActivation();
observeScrollableTables();
commitNavigation();
applyTheme(currentTheme());
loadSchoolName();
loadRuntimeInfo();
refreshDatalists();
refreshGlobalIndicators();
setInterval(refreshGlobalIndicators, GLOBAL_INDICATOR_INTERVAL_MS);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) refreshGlobalIndicators();
});

// PWA kabuğu: destekleyen tarayıcıda kaydet, yoksa sessizce yok say.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/static/sw.js").catch(() => {});
}
