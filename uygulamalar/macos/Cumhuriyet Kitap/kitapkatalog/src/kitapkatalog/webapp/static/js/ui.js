// Ortak arayüz yardımcıları: toast, onay, lightbox, form doldurma.

export function toast(message, kind = "info", ms = 3500) {
  const box = document.getElementById("toasts");
  const item = document.createElement("div");
  item.className = `toast ${kind}`;
  item.setAttribute("role", kind === "error" ? "alert" : "status");
  item.setAttribute("aria-atomic", "true");
  const text = document.createElement("span");
  text.className = "toast-message";
  text.textContent = message;
  const close = document.createElement("button");
  close.type = "button";
  close.className = "toast-close";
  close.setAttribute("aria-label", "Bildirimi kapat");
  close.textContent = "×";
  item.append(text, close);
  box.appendChild(item);
  let removeTimer;
  const remove = () => {
    clearTimeout(removeTimer);
    // Çıkış animasyonu; reduced-motion'da animationend gelmeyebilir diye
    // 300ms emniyet zamanlayıcısı (remove idempotent).
    item.classList.add("out");
    item.addEventListener("animationend", () => item.remove(), { once: true });
    setTimeout(() => item.remove(), 300);
  };
  close.addEventListener("click", remove);
  removeTimer = setTimeout(remove, ms);
}

export function confirmBox(message) {
  // Tarayıcı confirm'i yeterli ve erişilebilir; modal karmaşası kurmuyoruz.
  return Promise.resolve(window.confirm(message));
}

export function debounce(fn, ms = 250) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

// Hem metin hem öznitelik bağlamı için güvenli kaçırma (tırnaklar dahil).
export function esc(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function show(el, visible = true) {
  const wasHidden = el.hidden;
  if (!visible && !wasHidden && isManagedDialog(el)) deactivateDialog(el);
  el.hidden = !visible;
  if (visible && wasHidden && isManagedDialog(el)) activateDialog(el);
}

// Form <-> düz nesne
export function fillForm(form, values) {
  for (const element of form.elements) {
    if (!element.name) continue;
    element.value = values[element.name] ?? "";
  }
}

export function readForm(form) {
  const out = {};
  for (const element of form.elements) {
    if (!element.name) continue;
    out[element.name] = element.value.trim();
  }
  return out;
}

// Formların kaydedilmemiş değişiklik sözleşmesi için kararlı anlık görüntü.
// Checkbox/radio durumunu da value'dan ayrı tutar; böylece Ayarlar gibi
// formlar yanlışlıkla "temiz" sayılmaz. Yalnız adlandırılmış alanlar veri
// sözleşmesine dahildir; gönderim/kapatma düğmeleri bilinçli olarak dışarıda.
export function formSnapshot(form) {
  const values = [];
  for (const element of form.elements) {
    if (!element.name) continue;
    let value;
    if (element.type === "checkbox" || element.type === "radio") {
      value = Boolean(element.checked);
    } else if (element instanceof HTMLSelectElement && element.multiple) {
      value = [...element.selectedOptions].map((option) => option.value);
    } else {
      value = element.value;
    }
    values.push([element.name, element.type, value]);
  }
  return JSON.stringify(values);
}

const dialogStates = new WeakMap();

function isManagedDialog(element) {
  return element.matches?.('[role="dialog"][aria-modal="true"]');
}

function focusables(root) {
  return [...root.querySelectorAll(
    'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), ' +
    'textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
  )].filter((element) => !element.hidden && element.getClientRects().length > 0);
}

function deactivateDialog(dialog, { restore = true } = {}) {
  const state = dialogStates.get(dialog);
  if (!state) return;
  state.controller.abort();
  dialogStates.delete(dialog);
  if (restore && state.opener?.isConnected && !state.opener.hidden) {
    state.opener.focus({ preventScroll: true });
  }
}

function requestDialogClose(dialog) {
  const event = new Event("dialogcancel", { cancelable: true });
  if (dialog.dispatchEvent(event)) show(dialog, false);
}

function activateDialog(dialog, opener = document.activeElement) {
  if (dialogStates.has(dialog)) return;
  const controller = new AbortController();
  dialogStates.set(dialog, { controller, opener });
  dialog.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      requestDialogClose(dialog);
      return;
    }
    if (event.key !== "Tab") return;
    const items = focusables(dialog);
    if (items.length === 0) {
      event.preventDefault();
      dialog.focus();
      return;
    }
    const first = items[0];
    const last = items.at(-1);
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }, { signal: controller.signal });
  queueMicrotask(() => {
    const initial = dialog.querySelector("[autofocus], .drawer-head button, button, input, select, textarea");
    (initial || dialog).focus({ preventScroll: true });
  });
}

export function openLightbox(src, alt = "Kapak görseli") {
  const wrap = document.createElement("div");
  wrap.className = "lightbox";
  wrap.hidden = true;
  wrap.tabIndex = -1;
  wrap.setAttribute("role", "dialog");
  wrap.setAttribute("aria-modal", "true");
  wrap.setAttribute("aria-label", `${alt} önizlemesi`);
  const img = document.createElement("img");
  img.src = src;
  img.alt = alt;
  const close = document.createElement("button");
  close.type = "button";
  close.className = "lightbox-close";
  close.setAttribute("aria-label", "Önizlemeyi kapat");
  close.textContent = "✕";
  const remove = () => {
    show(wrap, false);
    wrap.remove();
  };
  close.addEventListener("click", remove);
  wrap.addEventListener("click", (event) => { if (event.target === wrap) remove(); });
  wrap.addEventListener("dialogcancel", (event) => {
    event.preventDefault();
    remove();
  });
  wrap.append(img, close);
  document.body.appendChild(wrap);
  show(wrap, true);
}

export function bindTabs(tablist, onChange = null) {
  const tabs = [...tablist.querySelectorAll(':scope > [role="tab"]')];
  const select = (selected, { focus = false, notify = true } = {}) => {
    const controlled = new Set(tabs.map((tab) => tab.getAttribute("aria-controls")).filter(Boolean));
    for (const tab of tabs) {
      const active = tab === selected;
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
      tab.classList.toggle("active", active);
      tab.classList.toggle("aktif", active);
    }
    for (const id of controlled) {
      const panel = document.getElementById(id);
      if (!panel) continue;
      show(panel, id === selected.getAttribute("aria-controls"));
      if (!panel.hidden) panel.setAttribute("aria-labelledby", selected.id);
    }
    if (focus) selected.focus();
    if (notify && onChange) onChange(selected);
  };
  for (const tab of tabs) {
    tab.addEventListener("click", () => select(tab));
    tab.addEventListener("keydown", (event) => {
      const current = tabs.indexOf(tab);
      let next = null;
      if (event.key === "ArrowRight" || event.key === "ArrowDown") next = (current + 1) % tabs.length;
      if (event.key === "ArrowLeft" || event.key === "ArrowUp") next = (current - 1 + tabs.length) % tabs.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = tabs.length - 1;
      if (next === null) return;
      event.preventDefault();
      select(tabs[next], { focus: true });
    });
  }
  const initial = tabs.find((tab) => tab.getAttribute("aria-selected") === "true") || tabs[0];
  if (initial) select(initial, { notify: false });
  return { select };
}

let keyboardActivationInstalled = false;

export function installKeyboardActivation() {
  if (keyboardActivationInstalled) return;
  keyboardActivationInstalled = true;
  document.addEventListener("keydown", (event) => {
    const target = event.target;
    if (!(target instanceof HTMLElement) || !target.hasAttribute("data-key-activate")) return;
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    target.click();
  });
}

function tableLabel(table) {
  if (table.getAttribute("aria-label")) return table.getAttribute("aria-label");
  const scope = table.closest(".card, section");
  const heading = scope?.querySelector("h1, h2, h3")?.textContent?.trim();
  return `${heading || "Veri tablosu"} — yatay kaydırılabilir`;
}

export function enhanceScrollableTables(root = document) {
  const tables = [];
  if (root instanceof HTMLTableElement && root.classList.contains("data-table")) tables.push(root);
  if (root.querySelectorAll) tables.push(...root.querySelectorAll("table.data-table"));
  for (const table of tables) {
    let wrapper = table.closest(".table-wrap");
    if (!wrapper) {
      wrapper = document.createElement("div");
      wrapper.className = "table-wrap";
      table.before(wrapper);
      wrapper.appendChild(table);
    }
    wrapper.tabIndex = 0;
    wrapper.setAttribute("role", "region");
    if (!wrapper.hasAttribute("aria-label")) wrapper.setAttribute("aria-label", tableLabel(table));
  }
}

export function observeScrollableTables() {
  enhanceScrollableTables(document);
  const observer = new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node instanceof Element) enhanceScrollableTables(node);
      }
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
  return observer;
}

export function fmtCount(value) {
  return new Intl.NumberFormat("tr-TR").format(value ?? 0);
}

// Okuma listesi/üye ilerleme çubuğu (lists.js ve members.js paylaşır).
export function progressBar(fraction) {
  const percent = Math.round(Math.min(1, Math.max(0, fraction)) * 100);
  return `<div class="bar-track" title="%${percent}"><div class="bar-fill" style="width:${percent}%"></div></div>`;
}
