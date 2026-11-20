// Arayüz yardımcıları: toast, kaplama, biçimlendirme, DOM kısayolları.
import { icon } from './icons.js';

export function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') node.className = v;
    else if (k === 'html') node.innerHTML = v;
    else if (k === 'text') node.textContent = v;
    else if (k.startsWith('on') && typeof v === 'function') node.addEventListener(k.slice(2), v);
    else if (v !== null && v !== undefined) node.setAttribute(k, v);
  }
  for (const c of [].concat(children)) {
    if (c == null) continue;
    node.append(c.nodeType ? c : document.createTextNode(c));
  }
  return node;
}

export function fmtSize(bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(2) + ' MB';
}

// ---- Toast ----
let toastWrap;
export function toast(message, type = 'info', duration = 3600) {
  if (!toastWrap) {
    toastWrap = el('div', { class: 'toasts' });
    document.body.append(toastWrap);
  }
  const icons = { success: 'checkcircle', error: 'x', warn: 'info', info: 'info' };
  const t = el('div', { class: `toast ${type}` }, [
    el('span', { class: 't-ic', html: icon(icons[type] || 'info', 't-ic', 20) }),
    el('span', { class: 't-msg', text: message }),
  ]);
  const dismiss = () => {
    t.style.animation = 'slideIn .3s reverse forwards';
    setTimeout(() => t.remove(), 300);
  };
  // Hata bildirimleri kullanıcı kapatana dek ekranda kalır; diğerleri kendiliğinden söner.
  if (type === 'error') {
    t.append(el('button', { class: 't-close', title: 'Kapat', onclick: dismiss, html: icon('x', 'ic', 14) }));
  } else {
    setTimeout(dismiss, duration);
  }
  toastWrap.append(t);
}

// ---- Yükleniyor kaplaması ----
let overlayNode;
export function showOverlay(text = 'İşleniyor…', sub = 'Lütfen bekleyin', { progress = false } = {}) {
  hideOverlay();
  const card = el('div', { class: 'overlay-card' }, [
    el('div', { class: 'spinner' }),
    el('p', { text }),
    el('small', { text: sub }),
  ]);
  if (progress) {
    card.append(el('div', { class: 'overlay-progress' }, [
      el('div', { class: 'overlay-progress-bar', 'data-progress-bar': '1' }),
    ]), el('div', { class: 'overlay-progress-pct', 'data-progress-pct': '1', text: '%0' }));
  }
  overlayNode = el('div', { class: 'overlay' }, [card]);
  document.body.append(overlayNode);
}
export function updateOverlayProgress(pct) {
  if (!overlayNode) return;
  const bar = overlayNode.querySelector('[data-progress-bar]');
  const lbl = overlayNode.querySelector('[data-progress-pct]');
  if (bar) bar.style.width = pct + '%';
  if (lbl) lbl.textContent = '%' + pct;
}
export function hideOverlay() {
  if (overlayNode) { overlayNode.remove(); overlayNode = null; }
}

// ---- Pencere geneli sürükle-bırak hedefi ----
// Aktif görünümdeki dropzone kendini kaydeder; app.js'teki pencere düzeyi drop
// dinleyicisi, dropzone dışına bırakılan dosyaları buraya yönlendirir.
let windowDrop = null;
export function registerWindowDrop(elNode, onFiles) { windowDrop = { el: elNode, onFiles }; }
export function getWindowDrop() {
  return windowDrop && windowDrop.el.isConnected ? windowDrop : null;
}

// ---- Basit modal ----
export function modal({ title, bodyNode, footNode, onClose, wide }) {
  const scrim = el('div', { class: 'modal-scrim' });
  const m = el('div', { class: 'modal' + (wide ? ' wide' : '') });
  const close = () => { scrim.remove(); onClose && onClose(); };
  m.append(
    el('div', { class: 'modal-head' }, [
      el('h3', { text: title }),
      el('button', { class: 'icon-btn', onclick: close, html: icon('x', 'ic', 18) }),
    ]),
    el('div', { class: 'modal-body' }, [bodyNode]),
  );
  if (footNode) m.append(el('div', { class: 'modal-foot' }, [footNode]));
  scrim.append(m);
  scrim.addEventListener('click', (e) => { if (e.target === scrim) close(); });
  document.body.append(scrim);
  return { close, node: m };
}

export function download(url, filename) {
  const a = el('a', { href: url, download: filename || '' });
  document.body.append(a);
  a.click();
  a.remove();
}
