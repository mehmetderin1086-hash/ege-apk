// PDF Studio — ana uygulama kontrolcüsü.
import { icon } from './icons.js';
import { el, fmtSize, toast, showOverlay, hideOverlay, updateOverlayProgress, download, modal, registerWindowDrop, getWindowDrop } from './ui.js';
import * as api from './api.js';
import { TOOLS, TOOLS_BY_ID, CATEGORIES, acceptAttr } from './tools.js';
import { openEditor } from './editor.js';
import { openOrganizer } from './organizer.js';

const app = {
  content: null,
  sidebar: null,
  currentTool: null,
  files: [],   // yüklenen dosyalar (simple/input akışı)
  opts: {},
};

// ============================ BAŞLANGIÇ ============================
export function init() {
  buildShell();
  applyTheme(localStorage.getItem('pdfstudio_theme') || 'light');
  renderHome();
  refreshSessionCount();
  initGlobalDrop();
}

// Pencerenin herhangi bir yerine bırakılan dosya, tarayıcının belgeden çıkıp
// PDF'i açmasına (ve çalışmanın kaybolmasına) yol açıyordu; drop'u yakalayıp
// aktif dropzone'a yönlendiriyoruz.
let globalDropReady = false;
let dragDepth = 0;
function initGlobalDrop() {
  if (globalDropReady) return;   // editörden dönüşte init() yeniden çağrılır
  globalDropReady = true;
  const hasFiles = (e) => [...(e.dataTransfer?.types || [])].includes('Files');
  window.addEventListener('dragover', (e) => { if (hasFiles(e)) e.preventDefault(); });
  window.addEventListener('dragenter', (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragDepth++;
    if (getWindowDrop()) document.body.classList.add('drag-active');
  });
  window.addEventListener('dragleave', () => {
    dragDepth = Math.max(0, dragDepth - 1);
    if (dragDepth === 0) document.body.classList.remove('drag-active');
  });
  window.addEventListener('drop', (e) => {
    dragDepth = 0;
    document.body.classList.remove('drag-active');
    if (!hasFiles(e)) return;
    e.preventDefault();
    if (e.target.closest?.('.dropzone')) return;   // dropzone kendi dinleyicisiyle işledi
    const files = [...(e.dataTransfer?.files || [])];
    const target = getWindowDrop();
    if (files.length && target) target.onFiles(files);
  });
}

function buildShell() {
  const root = document.getElementById('app');
  root.innerHTML = '';

  // Kenar çubuğu
  const nav = el('div', { class: 'side-nav' });
  nav.append(navLink('home', 'Ana Sayfa', () => { closeMobileNav(); renderHome(); }, true));
  for (const cat of CATEGORIES) {
    nav.append(el('div', { class: 'side-group-title', text: cat.title }));
    for (const t of TOOLS.filter(x => x.cat === cat.id)) {
      nav.append(navLink(t.icon, t.title, () => { closeMobileNav(); openTool(t.id); }, false, t.id));
    }
  }
  const sidebar = el('aside', { class: 'sidebar', id: 'sidebar' }, [
    el('div', { class: 'brand', onclick: () => { closeMobileNav(); renderHome(); } }, [
      el('div', { class: 'brand-logo', html: icon('file', 'ic', 20) }),
      el('div', { class: 'brand-name', html: 'PDF <span>Studio</span>' }),
    ]),
    nav,
    el('div', { class: 'side-foot', html: '🔒 Tüm işlemler bilgisayarınızda yapılır.<br>Dosyalarınız çevrimdışı kalır.' }),
  ]);
  app.sidebar = sidebar;

  // Üst çubuk
  const searchInput = el('input', { type: 'text', placeholder: 'Araç ara… (birleştir, sıkıştır, imza)', 'aria-label': 'Araç ara' });
  searchInput.addEventListener('input', () => renderHome(searchInput.value));
  searchInput.addEventListener('focus', () => renderHome(searchInput.value));
  const themeBtn = el('button', { class: 'icon-btn', title: 'Tema değiştir', onclick: toggleTheme, id: 'themeBtn', html: icon('moon', 'ic', 19) });
  const filesBtn = el('button', { class: 'icon-btn session-files-btn', title: 'Oturum dosyaları', onclick: openSessionFiles, id: 'sessionFilesBtn', html: icon('layers', 'ic', 19) + '<span class="session-count" hidden>0</span>' });
  const topbar = el('header', { class: 'topbar' }, [
    el('button', { class: 'hamburger', onclick: openMobileNav, html: icon('menu', 'ic', 22) }),
    el('div', { class: 'searchbox' }, [
      el('span', { class: 'ic', html: icon('search', 'ic', 18) }),
      searchInput,
    ]),
    el('div', { class: 'topbar-spacer' }),
    filesBtn,
    themeBtn,
  ]);

  const content = el('main', { class: 'content', id: 'content' });
  app.content = content;

  root.append(el('div', { class: 'app' }, [
    sidebar,
    el('div', { class: 'main' }, [topbar, content]),
  ]));
}

function navLink(ic, label, onClick, active, toolId) {
  return el('div', { class: 'side-link' + (active ? ' active' : ''), 'data-tool': toolId || '', onclick: (e) => { setActiveNav(e.currentTarget); onClick(); }, html: icon(ic, 'ic', 19) + `<span>${label}</span>` });
}
function setActiveNav(node) {
  app.sidebar.querySelectorAll('.side-link').forEach(l => l.classList.remove('active'));
  if (node) node.classList.add('active');
}
function openMobileNav() { app.sidebar.classList.add('open'); if (!document.querySelector('.scrim')) { const s = el('div', { class: 'scrim', onclick: closeMobileNav }); document.body.append(s); } }
function closeMobileNav() { app.sidebar.classList.remove('open'); document.querySelector('.scrim')?.remove(); }

// ============================ TEMA ============================
function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('pdfstudio_theme', theme);
  const btn = document.getElementById('themeBtn');
  if (btn) btn.innerHTML = icon(theme === 'dark' ? 'sun' : 'moon', 'ic', 19);
}
function toggleTheme() {
  const cur = document.documentElement.getAttribute('data-theme');
  applyTheme(cur === 'dark' ? 'light' : 'dark');
}

// ============================ ANA SAYFA ============================
function renderHome(filter = '') {
  setActiveNav(app.sidebar.querySelector('.side-link'));
  const q = (filter || '').trim().toLocaleLowerCase('tr');
  const c = app.content;
  c.innerHTML = '';

  const container = el('div', { class: 'container' });

  if (!q) {
    container.append(el('div', { class: 'hero' }, [
      el('h1', { html: 'Tüm PDF araçları <span class="grad">tek çatı altında</span>' }),
      el('p', { text: 'Birleştir, böl, sıkıştır, dönüştür, düzenle, imzala ve daha fazlası. Hepsi ücretsiz, hızlı ve tamamen bilgisayarınızda.' }),
      el('div', { class: 'hero-badges' }, [
        heroBadge('check', 'Kurulum gerektirmez'),
        heroBadge('check', 'Gizlilik odaklı'),
        heroBadge('check', TOOLS.length + ' güçlü araç'),
      ]),
    ]));
  }

  const matched = TOOLS.filter(t =>
    !q || t.title.toLocaleLowerCase('tr').includes(q) || t.desc.toLocaleLowerCase('tr').includes(q));

  if (matched.length === 0) {
    container.append(el('div', { style: 'text-align:center;padding:60px', class: 'prop-empty' }, [
      el('div', { html: icon('search', 'ic', 48) }),
      el('p', { text: `"${filter}" için araç bulunamadı.` }),
    ]));
  }

  for (const cat of CATEGORIES) {
    const tools = matched.filter(t => t.cat === cat.id);
    if (!tools.length) continue;
    container.append(el('div', { class: 'cat-title' }, [
      el('h2', { text: cat.title }),
      el('span', { class: 'count', text: tools.length }),
      el('div', { class: 'bar' }),
    ]));
    const grid = el('div', { class: 'tool-grid' });
    for (const t of tools) grid.append(toolCard(t));
    container.append(grid);
  }

  c.append(container);
  c.scrollTop = 0;
}

function heroBadge(ic, text) {
  return el('div', { class: 'hero-badge', html: icon(ic, 'ic', 15) + `<span>${text}</span>` });
}

function toolCard(t) {
  const card = el('div', { class: 'tool-card', onclick: () => openTool(t.id) }, [
    el('div', { class: `tool-ic ${t.color}`, html: icon(t.icon, 'ic', 24) }),
    el('h3', { text: t.title }),
    el('p', { text: t.desc }),
  ]);
  if (t.badge) card.append(el('span', { class: 'tool-badge-new', text: t.badge }));
  return card;
}

// ============================ ARAÇ AÇMA ============================
function openTool(id, { preloaded } = {}) {
  const tool = TOOLS_BY_ID[id];
  if (!tool) return;
  app.currentTool = tool;
  app.files = preloaded || [];   // zincirlemede önceki aracın çıktısıyla başla
  app.opts = {};
  // varsayılan seçenekler
  for (const f of tool.fields || []) app.opts[f.key] = f.default;

  // sidebar aktif
  const link = app.sidebar.querySelector(`.side-link[data-tool="${id}"]`);
  setActiveNav(link);

  if (tool.kind === 'editor') { openEditor(tool); return; }
  if (tool.kind === 'organizer') { openOrganizer(tool); return; }

  renderToolView(tool);
}

function toolHeader(tool) {
  return el('div', { class: 'tool-header' }, [
    el('button', { class: 'icon-btn back', title: 'Geri', onclick: () => renderHome(), html: icon('back', 'ic', 20) }),
    el('div', { class: `tool-ic ${tool.color}`, html: icon(tool.icon, 'ic', 26) }),
    el('div', {}, [
      el('h1', { text: tool.title }),
      el('p', { text: tool.desc }),
    ]),
  ]);
}

function renderToolView(tool) {
  const c = app.content;
  c.innerHTML = '';
  const container = el('div', { class: 'container' });
  container.append(toolHeader(tool));

  if (tool.kind === 'input') { container.append(renderInputFlow(tool)); }
  else if (tool.kind === 'compare') { container.append(renderCompareFlow(tool)); }
  else if (tool.kind === 'metadata') { container.append(renderMetadataFlow(tool)); }
  else if (tool.kind === 'forms') { container.append(renderFormsFlow(tool)); }
  else if (tool.kind === 'forms-extract') { container.append(renderFormsExtractFlow(tool)); }
  else { container.append(renderSimpleFlow(tool)); }

  c.append(container);
  c.scrollTop = 0;
}

// ============================ DOSYA YÜKLEME ============================
function makeDropzone(tool, onFiles) {
  const input = el('input', { type: 'file', class: 'hidden', accept: acceptAttr(tool.accept), multiple: tool.multiple ? 'multiple' : null });
  input.addEventListener('change', () => { if (input.files.length) onFiles([...input.files]); input.value = ''; });
  const dz = el('div', { class: 'dropzone', onclick: () => input.click() }, [
    el('div', { class: 'dz-ic', html: icon('uploadcloud', 'ic', 62) }),
    el('h3', { text: tool.multiple ? 'Dosyaları buraya sürükleyin' : 'Dosyayı buraya sürükleyin' }),
    el('p', { text: acceptHint(tool.accept) }),
    el('button', { class: 'btn btn-primary', html: icon('upload', 'ic', 18) + 'Dosya Seç' }),
    input,
  ]);
  ;['dragover', 'dragenter'].forEach(ev => dz.addEventListener(ev, (e) => { e.preventDefault(); dz.classList.add('drag'); }));
  ;['dragleave', 'drop'].forEach(ev => dz.addEventListener(ev, (e) => { e.preventDefault(); dz.classList.remove('drag'); }));
  dz.addEventListener('drop', (e) => { const fs = [...(e.dataTransfer?.files || [])]; if (fs.length) onFiles(fs); });
  registerWindowDrop(dz, onFiles);
  return dz;
}

function acceptHint(accept) {
  const names = { pdf: 'PDF', image: 'JPG, PNG, WEBP…', office: 'Word (.docx)' };
  return 'veya bilgisayardan seçin · ' + (accept || ['pdf']).map(a => names[a] || a).join(', ');
}

async function doUpload(files, tool, onDone) {
  showOverlay('Yükleniyor…', files.length + ' dosya', { progress: true });
  try {
    const res = await api.upload(files, updateOverlayProgress);
    refreshSessionCount();
    hideOverlay();
    // kabul edilen türe göre filtrele
    const accepted = res.files.filter(f => tool.accept.includes(f.kind) || tool.accept.includes('any'));
    if (accepted.length === 0) { toast('Bu araç için uygun dosya türü seçilmedi.', 'error'); return; }
    onDone(accepted);
  } catch (e) {
    hideOverlay();
    toast(e.message, 'error');
  }
}

// ============================ SIMPLE AKIŞI ============================
function renderSimpleFlow(tool) {
  const wrap = el('div');
  const stage = el('div');   // dropzone veya çalışma alanı
  wrap.append(stage);

  const showUpload = () => {
    stage.innerHTML = '';
    stage.append(makeDropzone(tool, (files) => doUpload(files, tool, (accepted) => {
      app.files = tool.multiple ? [...app.files, ...accepted] : [accepted[0]];
      showWorkspace();
    })));
  };

  const showWorkspace = () => {
    stage.innerHTML = '';
    const layout = el('div', { class: 'work-layout' });
    const errHost = el('div');

    // Sol: dosya listesi
    const left = el('div');
    const listWrap = el('div', { class: 'file-list' });
    renderFileList(tool, listWrap, () => { if (app.files.length === 0) showUpload(); });
    left.append(listWrap);
    if (tool.multiple) {
      left.append(el('div', { class: 'file-add-more', style: 'margin-top:10px', onclick: () => {
        const input = el('input', { type: 'file', class: 'hidden', accept: acceptAttr(tool.accept), multiple: 'multiple' });
        input.addEventListener('change', () => { if (input.files.length) doUpload([...input.files], tool, (acc) => { app.files.push(...acc); renderFileList(tool, listWrap, () => {}); }); });
        input.click();
      }, html: icon('plus', 'ic', 16) + 'Daha fazla dosya ekle' }));
    }

    // Sağ: seçenekler + işle
    const right = el('div');
    right.append(errHost);
    const panel = el('div', { class: 'options-panel' });
    panel.append(el('h3', { text: 'Ayarlar' }));
    panel.append(el('p', { class: 'op-sub', text: tool.fields?.length ? 'Aşağıdaki ayarları özelleştirin.' : 'Ek ayar gerekmiyor.' }));
    const fieldsHost = el('div');
    renderFields(tool, fieldsHost);
    panel.append(fieldsHost);
    const runBtn = el('button', { class: 'btn btn-primary btn-block btn-lg', style: 'margin-top:8px', html: icon('zap', 'ic', 19) + processLabel(tool) });
    runBtn.addEventListener('click', () => runProcess(tool, runBtn, errHost));
    panel.append(runBtn);
    right.append(panel);

    layout.append(left, right);
    stage.append(layout);
  };

  // Zincirlemeyle gelen ön-yüklü dosya varsa dropzone atlanır
  if (app.files.length) showWorkspace(); else showUpload();
  return wrap;
}

function processLabel(tool) {
  const map = { merge: 'Birleştir', split: 'Böl', compress: 'Sıkıştır', ocr: 'OCR Uygula', repair: 'Onar' };
  return map[tool.id] || 'İşle ve İndir';
}

function renderFileList(tool, host, onEmpty) {
  host.innerHTML = '';
  if (app.files.length === 0) { onEmpty && onEmpty(); return; }
  app.files.forEach((f, idx) => {
    const item = el('div', { class: 'file-item', draggable: tool.reorder ? 'true' : null, 'data-idx': idx });
    const thumb = el('div', { class: 'file-thumb', html: icon(f.kind === 'image' ? 'image' : 'file', 'ic', 20) });
    if (f.kind === 'pdf') { const im = el('img', { src: api.renderUrl(f.file_id, 0, 'thumb'), class: 'file-thumb', alt: '' }); im.onerror = () => im.replaceWith(thumb); item.append(im); }
    else if (f.kind === 'image') { const im = el('img', { src: api.downloadUrl(f.file_id), class: 'file-thumb', alt: '' }); item.append(im); }
    else item.append(thumb);
    item.append(
      el('div', { class: 'file-meta' }, [
        el('div', { class: 'file-name', text: f.name }),
        el('div', { class: 'file-sub', text: (f.pages ? f.pages + ' sayfa · ' : '') + fmtSize(f.size) }),
      ]),
    );
    if (tool.reorder) item.append(el('span', { class: 'file-drag-handle', html: icon('grip', 'ic', 18) }));
    item.append(el('button', { class: 'file-remove', title: 'Kaldır', onclick: () => { app.files.splice(idx, 1); renderFileList(tool, host, onEmpty); }, html: icon('x', 'ic', 16) }));

    if (tool.reorder) enableReorder(item, tool, host, onEmpty);
    host.append(item);
  });
}

function enableReorder(item, tool, host, onEmpty) {
  item.addEventListener('dragstart', (e) => { item.classList.add('dragging'); e.dataTransfer.setData('text/plain', item.dataset.idx); });
  item.addEventListener('dragend', () => item.classList.remove('dragging'));
  item.addEventListener('dragover', (e) => e.preventDefault());
  item.addEventListener('drop', (e) => {
    e.preventDefault();
    const from = +e.dataTransfer.getData('text/plain');
    const to = +item.dataset.idx;
    if (from === to) return;
    const [moved] = app.files.splice(from, 1);
    app.files.splice(to, 0, moved);
    renderFileList(tool, host, onEmpty);
  });
}

// ============================ SEÇENEK ALANLARI ============================
function renderFields(tool, host) {
  host.innerHTML = '';
  const fields = tool.fields || [];
  let rowBuffer = [];
  const flushRow = () => {
    if (rowBuffer.length) { host.append(el('div', { style: 'display:flex;gap:10px' }, rowBuffer)); rowBuffer = []; }
  };
  for (const f of fields) {
    if (f.showIf && !f.showIf(app.opts)) continue;
    const node = renderField(tool, f, host);
    if (f.half) { node.style.flex = '1'; rowBuffer.push(node); if (rowBuffer.length === 2) flushRow(); }
    else { flushRow(); host.append(node); }
  }
  flushRow();
}

function renderField(tool, f, host) {
  const wrap = el('div', { class: 'field' });
  const rerender = () => renderFields(tool, host);
  if (f.type !== 'checkbox') wrap.append(el('label', { text: f.label }));

  if (f.type === 'text' || f.type === 'password') {
    const inp = el('input', { class: 'input', type: f.type, value: app.opts[f.key] ?? '', placeholder: f.placeholder || '' });
    inp.addEventListener('input', () => app.opts[f.key] = inp.value);
    wrap.append(inp);
  } else if (f.type === 'number') {
    const inp = el('input', { class: 'input', type: 'number', value: app.opts[f.key] ?? 0, min: f.min, max: f.max, step: f.step || 1 });
    inp.addEventListener('input', () => app.opts[f.key] = inp.value);
    wrap.append(inp);
  } else if (f.type === 'textarea' || f.type === 'pages') {
    if (f.type === 'pages') {
      const inp = el('input', { class: 'input', type: 'text', value: app.opts[f.key] ?? '', placeholder: f.placeholder || '' });
      inp.addEventListener('input', () => app.opts[f.key] = inp.value);
      wrap.append(inp);
    } else {
      const ta = el('textarea', { class: 'input', placeholder: f.placeholder || '', style: f.big ? 'min-height:180px' : '' });
      ta.value = app.opts[f.key] ?? '';
      ta.addEventListener('input', () => app.opts[f.key] = ta.value);
      wrap.append(ta);
    }
  } else if (f.type === 'select') {
    const sel = el('select', { class: 'select' });
    for (const o of f.options) sel.append(el('option', { value: o.value, text: o.label, selected: String(app.opts[f.key]) === String(o.value) ? 'selected' : null }));
    sel.addEventListener('change', () => { app.opts[f.key] = sel.value; if (f.affectsVisibility) rerender(); });
    wrap.append(sel);
  } else if (f.type === 'segment') {
    const seg = el('div', { class: 'seg' });
    for (const o of f.options) {
      const b = el('button', { class: String(app.opts[f.key]) === String(o.value) ? 'active' : '', text: o.label });
      b.addEventListener('click', () => { app.opts[f.key] = o.value; rerender(); });
      seg.append(b);
    }
    wrap.append(seg);
  } else if (f.type === 'checkbox') {
    const cb = el('input', { type: 'checkbox' });
    cb.checked = !!app.opts[f.key];
    cb.addEventListener('change', () => { app.opts[f.key] = cb.checked; rerender(); });
    wrap.append(el('label', { class: 'check' }, [cb, el('span', { class: 'box' }), el('span', { class: 'lbl', text: f.label })]));
  } else if (f.type === 'color') {
    const ci = el('input', { type: 'color', value: app.opts[f.key] || '#000000' });
    const tx = el('input', { class: 'input', type: 'text', value: app.opts[f.key] || '#000000', style: 'flex:1' });
    ci.addEventListener('input', () => { app.opts[f.key] = ci.value; tx.value = ci.value; });
    tx.addEventListener('input', () => { app.opts[f.key] = tx.value; ci.value = tx.value; });
    wrap.append(el('div', { class: 'color-row' }, [ci, tx]));
  } else if (f.type === 'range') {
    const val = el('span', { class: 'range-val', text: (app.opts[f.key] ?? f.default) + (f.unit || '') });
    const rg = el('input', { type: 'range', min: f.min, max: f.max, step: f.step || 1, value: app.opts[f.key] ?? f.default });
    rg.addEventListener('input', () => { app.opts[f.key] = rg.value; val.textContent = rg.value + (f.unit || ''); });
    wrap.append(el('div', { class: 'range-row' }, [rg, val]));
  } else if (f.type === 'imageupload') {
    const status = el('div', { class: 'file-sub', style: 'margin-top:8px', text: app.opts[f.key + '_name'] || 'Henüz görsel seçilmedi.' });
    const input = el('input', { type: 'file', class: 'hidden', accept: 'image/*' });
    input.addEventListener('change', async () => {
      if (!input.files.length) return;
      showOverlay('Görsel yükleniyor…');
      try { const r = await api.upload([input.files[0]]); const im = r.files[0]; app.opts[f.key] = im.file_id; app.opts[f.key + '_name'] = im.name; status.textContent = '✓ ' + im.name; }
      catch (e) { toast(e.message, 'error'); }
      hideOverlay();
    });
    const btn = el('button', { class: 'btn btn-ghost btn-sm', html: icon('image', 'ic', 16) + 'Görsel Seç', onclick: () => input.click() });
    wrap.append(btn, status, input);
  }

  if (f.hint) wrap.append(el('div', { class: 'hint', text: f.hint }));
  return wrap;
}

// ============================ İŞLEME ============================
// Hata, toast'ta kaybolmak yerine ayar panelinin üstünde kalıcı bir kartta
// gösterilir; kullanıcı ayarları değiştirip yeniden deneyebilir.
function showErrorCard(host, error, onRetry) {
  host.innerHTML = '';
  const card = el('div', { class: 'error-card' }, [
    el('div', { class: 'ec-head' }, [
      el('span', { class: 'ec-ic', html: icon('info', 'ic', 18) }),
      el('strong', { text: 'İşlem başarısız' + (error.status ? ` (HTTP ${error.status})` : '') }),
      el('button', { class: 'icon-btn ec-close', title: 'Kapat', onclick: () => { host.innerHTML = ''; }, html: icon('x', 'ic', 15) }),
    ]),
    el('p', { text: error.message }),
    el('button', { class: 'btn btn-ghost btn-sm', html: icon('rotate', 'ic', 15) + 'Tekrar Dene', onclick: onRetry }),
  ]);
  host.append(card);
  card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

async function runProcess(tool, btn, errHost) {
  if (errHost) errHost.innerHTML = '';
  // doğrulama
  if (tool.minFiles && app.files.length < tool.minFiles) { toast(`En az ${tool.minFiles} dosya gerekli.`, 'warn'); return; }
  if (tool.requireField && !((app.opts[tool.requireField] || '').toString().trim())) {
    toast('Lütfen gerekli alanı doldurun.', 'warn'); return;
  }
  if (tool.id === 'watermark' && app.opts.wtype === 'image' && !app.opts.image_file_id) { toast('Lütfen bir filigran görseli seçin.', 'warn'); return; }
  if (tool.id === 'batch' && app.opts.operation === 'protect' && !(app.opts.new_password || '').trim()) { toast('Lütfen bir açılış parolası girin.', 'warn'); return; }
  if (tool.id === 'batch' && app.opts.operation === 'watermark-text' && !(app.opts.text || '').trim()) { toast('Lütfen filigran metnini girin.', 'warn'); return; }

  const endpoint = tool.dynamicEndpoint ? tool.dynamicEndpoint(app.opts) : tool.endpoint;
  const payload = tool.build ? tool.build(app.files, app.opts) : { file_id: app.files[0]?.file_id };

  btn.classList.add('loading');
  if (tool.slow) showOverlay('İşleniyor…', 'Bu işlem biraz sürebilir (OCR/dönüştürme).');
  try {
    const res = await api.post(endpoint, payload);
    renderResult(tool, res);
  } catch (e) {
    if (errHost) showErrorCard(errHost, e, () => runProcess(tool, btn, errHost));
    else toast(e.message, 'error');
  } finally {
    btn.classList.remove('loading');
    hideOverlay();
  }
}

function renderResult(tool, res) {
  const c = app.content;
  c.innerHTML = '';
  const container = el('div', { class: 'container' });
  container.append(toolHeader(tool));

  const card = el('div', { class: 'result-card' });
  card.append(el('div', { class: 'result-icon', html: icon('checkcircle', 'ic', 40) }));
  card.append(el('h2', { text: 'İşlem tamamlandı!' }));
  card.append(el('p', { text: res.message || 'Dosyanız hazır.' }));

  if (res.meta && res.meta.reduction_percent > 0) {
    card.append(el('div', { class: 'reduction-chip', html: icon('compress', 'ic', 15) + `Boyut %${res.meta.reduction_percent} azaldı (${fmtSize(res.meta.original_size)} → ${fmtSize(res.meta.new_size)})` }));
  }

  const filesWrap = el('div', { class: 'result-files' });
  for (const o of res.outputs) {
    const kindColor = { pdf: 'c-red', office: 'c-blue', image: 'c-pink', text: 'c-slate', zip: 'c-amber' }[o.kind] || 'c-violet';
    const kindIcon = { pdf: 'file', office: 'word', image: 'image', text: 'filetext', zip: 'layers' }[o.kind] || 'file';
    const row = el('div', { class: 'result-file' }, [
      el('div', { class: `rf-ic ${kindColor}`, html: icon(kindIcon, 'ic', 20) }),
      el('div', { class: 'rf-meta' }, [
        el('div', { class: 'rf-name', text: o.name }),
        el('div', { class: 'rf-size', text: fmtSize(o.size) }),
      ]),
    ]);
    if (chainTargets(o).length) {
      row.append(el('button', { class: 'btn btn-ghost btn-sm', title: 'Bu çıktıyı başka bir araçta kullan', html: icon('zap', 'ic', 15) + 'Başka araçta aç', onclick: () => openChainPicker(o) }));
    }
    row.append(el('button', { class: 'btn btn-primary btn-sm', html: icon('download', 'ic', 16) + 'İndir', onclick: () => download(o.download_url, o.name) }));
    filesWrap.append(row);
  }
  card.append(filesWrap);

  const actions = el('div', { class: 'result-actions' });
  if (res.outputs.length > 1) {
    actions.append(el('button', { class: 'btn btn-primary', html: icon('download', 'ic', 18) + 'Tümünü İndir', onclick: () => res.outputs.forEach((o, i) => setTimeout(() => download(o.download_url, o.name), i * 350)) }));
  }
  actions.append(el('button', { class: 'btn btn-ghost', html: icon('back', 'ic', 18) + 'Yeni İşlem', onclick: () => openTool(tool.id) }));
  actions.append(el('button', { class: 'btn btn-ghost', html: icon('home', 'ic', 18) + 'Ana Sayfa', onclick: () => renderHome() }));
  card.append(actions);

  container.append(card);
  c.append(container);
  c.scrollTop = 0;
  toast(res.message || 'İşlem tamamlandı.', 'success');
  refreshSessionCount();
}

// ============================ ZİNCİRLEME ============================
// Çıktı zaten oturumda kayıtlı; başka bir araca yeniden yüklemeden aktarılır.
// Yalnız standart (dropzone'lu) akışlar hedef olabilir; editör/düzenleyici gibi
// özel akışlar kendi dosya seçimini yönetir.
function chainTargets(output) {
  return TOOLS.filter(t => t.kind === 'simple' && (t.accept || []).includes(output.kind));
}

function openChainPicker(output) {
  const list = el('div', { class: 'chain-list' });
  const dialog = modal({ title: `"${output.name}" ile devam et`, bodyNode: list });
  for (const t of chainTargets(output)) {
    list.append(el('button', { class: 'chain-item', onclick: () => {
      dialog.close();
      openTool(t.id, { preloaded: [{ file_id: output.file_id, name: output.name, size: output.size, kind: output.kind }] });
    } }, [
      el('div', { class: `tool-ic ${t.color}`, html: icon(t.icon, 'ic', 20) }),
      el('div', {}, [
        el('div', { class: 'chain-title', text: t.title }),
        el('div', { class: 'chain-desc', text: t.desc }),
      ]),
    ]));
  }
}

// ============================ OTURUM DOSYALARI ============================
async function refreshSessionCount() {
  const badge = document.querySelector('#sessionFilesBtn .session-count');
  if (!badge) return;
  try {
    const data = await api.sessionFiles();
    const count = data.files?.length || 0;
    badge.textContent = count > 99 ? '99+' : String(count);
    badge.hidden = count === 0;
  } catch (error) {
    if (error.status === 404) api.clearSessionId();
    badge.hidden = true;
  }
}

async function openSessionFiles() {
  const body = el('div', { class: 'session-center' }, [
    el('div', { class: 'session-loading', text: 'Dosyalar yükleniyor…' }),
  ]);
  const dialog = modal({ title: 'Oturum Dosyaları', bodyNode: body, wide: true });

  const render = async () => {
    try {
      const data = await api.sessionFiles();
      body.innerHTML = '';
      const files = data.files || [];
      body.append(el('div', { class: 'session-summary' }, [
        el('div', {}, [
          el('strong', { text: `${files.length} dosya` }),
          el('span', { text: ` · ${fmtSize(data.total_size || 0)} geçici alan` }),
        ]),
        files.length ? el('button', { class: 'btn btn-ghost btn-sm session-clear', html: icon('trash', 'ic', 16) + 'Tümünü Temizle' }) : null,
      ]));

      if (!files.length) {
        body.append(el('div', { class: 'session-empty' }, [
          el('div', { html: icon('layers', 'ic', 38) }),
          el('strong', { text: 'Henüz oturum dosyası yok' }),
          el('p', { text: 'Yüklediğiniz ve oluşturduğunuz dosyalar burada görünür.' }),
        ]));
        refreshSessionCount();
        return;
      }

      const list = el('div', { class: 'session-file-list' });
      for (const file of files) {
        const row = el('div', { class: 'session-file-row' }, [
          el('div', { class: `session-kind ${file.kind}`, html: icon(file.kind === 'image' ? 'image' : 'file', 'ic', 19) }),
          el('div', { class: 'session-file-meta' }, [
            el('div', { class: 'session-file-name', text: file.name }),
            el('div', { class: 'file-sub', text: fmtSize(file.size) }),
          ]),
          el('button', { class: 'icon-btn session-download', title: 'İndir', onclick: () => download(api.downloadUrl(file.file_id), file.name), html: icon('download', 'ic', 17) }),
          el('button', { class: 'icon-btn session-delete', title: 'Sil', html: icon('trash', 'ic', 17) }),
        ]);
        row.querySelector('.session-delete').addEventListener('click', async (event) => {
          const button = event.currentTarget;
          button.disabled = true;
          try {
            await api.deleteSessionFile(file.file_id);
            row.remove();
            toast('Dosya silindi.', 'success');
            await render();
          } catch (error) {
            button.disabled = false;
            toast(error.message, 'error');
          }
        });
        list.append(row);
      }
      body.append(list);

      body.querySelector('.session-clear')?.addEventListener('click', async (event) => {
        if (!window.confirm('Bu oturumdaki tüm yükleme ve çıktılar kalıcı olarak silinsin mi?')) return;
        const button = event.currentTarget;
        const original = button.innerHTML;
        button.disabled = true;
        button.textContent = 'Temizleniyor…';
        try {
          await api.clearSession();
          app.files = [];
          dialog.close();
          refreshSessionCount();
          toast('Tüm geçici dosyalar silindi.', 'success');
          // Ekrandaki araç görünümü artık silinmiş file_id'lere işaret eder;
          // bayat "İşle"/"Başka araçta aç" düğmeleri kalmasın diye ana sayfaya dön.
          renderHome();
        } catch (error) {
          button.disabled = false;
          button.innerHTML = original;
          toast(error.message, 'error');
        }
      });
      refreshSessionCount();
    } catch (error) {
      if (error.status === 404) api.clearSessionId();
      body.innerHTML = '';
      body.append(el('div', { class: 'session-empty' }, [
        el('p', { text: error.status === 404
          ? 'Önceki oturumun süresi dolmuş. Yeni bir dosya yükleyerek başlayabilirsiniz.'
          : 'Dosyalar şu anda yüklenemedi. Sunucu bağlantısını kontrol edip yeniden deneyin.' }),
      ]));
      refreshSessionCount();
    }
  };

  await render();
}

// ============================ INPUT AKIŞI (metin/html) ============================
function renderInputFlow(tool) {
  const wrap = el('div', { style: 'max-width:760px' });
  const panel = el('div', { class: 'options-panel', style: 'position:static' });
  const fieldsHost = el('div');
  renderFields(tool, fieldsHost);
  panel.append(fieldsHost);
  const btn = el('button', { class: 'btn btn-primary btn-lg btn-block', style: 'margin-top:8px', html: icon('topdf', 'ic', 19) + "PDF'e Dönüştür" });
  btn.addEventListener('click', () => runProcess(tool, btn));
  panel.append(btn);
  wrap.append(panel);
  return wrap;
}

// ============================ KARŞILAŞTIRMA AKIŞI ============================
function renderCompareFlow(tool) {
  const wrap = el('div');
  const state = { a: null, b: null };
  const grid = el('div', { class: 'compare-grid' });
  const resultHost = el('div');

  const compareBtn = el('button', { class: 'btn btn-primary btn-lg', disabled: 'disabled', html: icon('search', 'ic', 18) + 'Metinleri Karşılaştır' });
  const visualBtn = el('button', { class: 'btn btn-ghost btn-lg', disabled: 'disabled', html: icon('image', 'ic', 18) + 'Görsel Fark (PNG)' });
  const draws = {};
  const pending = { a: false, b: false };   // yükleme sürerken slot rezerve
  const addFiles = async (key, files) => {
    if (pending[key]) return;
    pending[key] = true;
    showOverlay('Yükleniyor…', files[0].name, { progress: true });
    try {
      const res = await api.upload(files.slice(0, 1), updateOverlayProgress);
      refreshSessionCount();
      const accepted = res.files.filter(f => f.kind === 'pdf');
      if (!accepted.length) toast('Lütfen bir PDF dosyası seçin.', 'error');
      else { state[key] = accepted[0]; draws[key](); }
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      pending[key] = false;
      hideOverlay();
      syncButtons();
    }
  };
  // İki dropzone tek windowDrop kaydını ezmesin: pencereye bırakılan dosya
  // her zaman İLK BOŞ (ve yüklemesi sürmeyen) slota gider.
  const routeWindowDrop = () => registerWindowDrop(grid, (files) => {
    const key = (!state.a && !pending.a) ? 'a' : ((!state.b && !pending.b) ? 'b' : null);
    if (key) addFiles(key, files);
  });
  const syncButtons = () => {
    const ready = state.a && state.b;
    compareBtn.disabled = !ready;
    visualBtn.disabled = !ready;
    routeWindowDrop();
  };

  const slot = (key, label) => {
    const host = el('div', { class: 'compare-slot' });
    const draw = () => {
      host.innerHTML = '';
      host.append(el('h3', { class: 'compare-slot-title', text: label }));
      if (!state[key]) {
        host.append(makeDropzone(tool, (files) => addFiles(key, files)));
      } else {
        const f = state[key];
        const item = el('div', { class: 'file-item' });
        const thumb = el('img', { src: api.renderUrl(f.file_id, 0, 'thumb'), class: 'file-thumb', alt: '' });
        thumb.onerror = () => thumb.replaceWith(el('div', { class: 'file-thumb', html: icon('file', 'ic', 20) }));
        item.append(thumb,
          el('div', { class: 'file-meta' }, [
            el('div', { class: 'file-name', text: f.name }),
            el('div', { class: 'file-sub', text: (f.pages ? f.pages + ' sayfa · ' : '') + fmtSize(f.size) }),
          ]),
          el('button', { class: 'file-remove', title: 'Kaldır', onclick: () => { state[key] = null; resultHost.innerHTML = ''; draw(); syncButtons(); }, html: icon('x', 'ic', 16) }));
        host.append(item);
      }
    };
    draws[key] = draw;
    draw();
    return host;
  };
  grid.append(slot('a', 'Birinci PDF (A)'), slot('b', 'İkinci PDF (B)'));
  routeWindowDrop();

  const payload = () => ({ file_id_a: state.a.file_id, file_id_b: state.b.file_id });

  compareBtn.addEventListener('click', async () => {
    showOverlay('Karşılaştırılıyor…', 'Sayfa metinleri inceleniyor');
    try {
      const rep = await api.post('/api/compare/text', payload());
      renderCompareReport(resultHost, state, rep);
    } catch (e) { toast(e.message, 'error'); }
    hideOverlay();
  });

  visualBtn.addEventListener('click', async () => {
    showOverlay('Görsel fark çıkarılıyor…', 'Sayfalar piksel piksel karşılaştırılıyor');
    try {
      const res = await api.post('/api/compare/visual', payload());
      hideOverlay();
      if (!res.outputs.length) { toast(res.message, 'info'); return; }
      renderResult(tool, res);
    } catch (e) { hideOverlay(); toast(e.message, 'error'); }
  });

  wrap.append(grid, el('div', { class: 'compare-actions' }, [compareBtn, visualBtn]), resultHost);
  return wrap;
}

function renderCompareReport(host, state, rep) {
  host.innerHTML = '';
  const s = rep.summary;
  const pct = Math.round(s.overall_similarity * 100);
  const card = el('div', { class: 'options-panel', style: 'position:static;margin-top:18px' });
  card.append(el('h3', { text: s.identical ? 'Belgeler özdeş' : 'Karşılaştırma Raporu' }));
  card.append(el('div', { class: 'compare-summary' }, [
    el('span', { class: 'cmp-chip', text: `A: ${s.page_count_a} sayfa` }),
    el('span', { class: 'cmp-chip', text: `B: ${s.page_count_b} sayfa` }),
    el('span', { class: 'cmp-chip ' + (pct === 100 ? 'ok' : pct >= 70 ? 'mid' : 'bad'), text: `Genel benzerlik %${pct}` }),
  ]));

  for (const p of rep.page_pairs) {
    const ppct = Math.round(p.similarity * 100);
    const row = el('div', { class: 'cmp-row' });
    const head = el('div', { class: 'cmp-row-head' }, [
      el('strong', { text: `Sayfa ${p.page}` }),
      p.missing_in
        ? el('span', { class: 'cmp-badge bad', text: p.missing_in === 'a' ? 'Yalnız B’de var' : 'Yalnız A’da var' })
        : el('span', { class: 'cmp-badge ' + (ppct === 100 ? 'ok' : ppct >= 70 ? 'mid' : 'bad'), text: `%${ppct}` }),
    ]);
    row.append(head);
    if (!p.missing_in && (p.added.length || p.removed.length)) {
      const detail = el('div', { class: 'cmp-detail', hidden: 'hidden' });
      for (const ln of p.removed) detail.append(el('div', { class: 'cmp-line removed', text: '− ' + ln }));
      for (const ln of p.added) detail.append(el('div', { class: 'cmp-line added', text: '+ ' + ln }));
      head.append(el('button', { class: 'btn btn-ghost btn-sm', text: `${p.removed.length + p.added.length} satır farkı`, onclick: () => { detail.hidden = !detail.hidden; } }));
      row.append(detail);
    }
    card.append(row);
  }
  host.append(card);
  card.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

// ============================ META VERİ AKIŞI ============================
function renderMetadataFlow(tool) {
  const wrap = el('div');
  const stage = el('div');
  wrap.append(stage);
  stage.append(makeDropzone(tool, (files) => doUpload(files, tool, async (accepted) => {
    app.files = [accepted[0]];
    showOverlay('Meta veriler okunuyor…');
    let md = {};
    try { md = await api.info(accepted[0].file_id); } catch (e) { toast(e.message, 'error'); }
    hideOverlay();
    stage.innerHTML = '';
    const meta = md.metadata || {};
    const panel = el('div', { class: 'options-panel', style: 'position:static;max-width:620px' });
    panel.append(el('h3', { text: 'Belge Meta Verileri' }));
    panel.append(el('p', { class: 'op-sub', text: (md.page_count || 0) + ' sayfa · ' + accepted[0].name }));
    const fieldDefs = [
      ['title', 'Başlık'], ['author', 'Yazar'], ['subject', 'Konu'],
      ['keywords', 'Anahtar Kelimeler'], ['creator', 'Oluşturan'], ['producer', 'Üretici'],
    ];
    const inputs = {};
    for (const [k, label] of fieldDefs) {
      const inp = el('input', { class: 'input', type: 'text', value: meta[k] || '' });
      inputs[k] = inp;
      panel.append(el('div', { class: 'field' }, [el('label', { text: label }), inp]));
    }
    const btn = el('button', { class: 'btn btn-primary btn-lg btn-block', html: icon('save', 'ic', 18) + 'Kaydet' });
    btn.addEventListener('click', async () => {
      const fields = {}; for (const [k] of fieldDefs) fields[k] = inputs[k].value;
      btn.classList.add('loading');
      try { const res = await api.post('/api/security/metadata', { file_id: app.files[0].file_id, fields }); renderResult(tool, res); }
      catch (e) { toast(e.message, 'error'); }
      btn.classList.remove('loading');
    });
    panel.append(btn);
    stage.append(panel);
  })));
  return wrap;
}

// ============================ FORM DOLDURMA AKIŞI ============================
function renderFormsFlow(tool) {
  const wrap = el('div');
  const stage = el('div');
  wrap.append(stage);
  stage.append(makeDropzone(tool, (files) => doUpload(files, tool, async (accepted) => {
    app.files = [accepted[0]];
    showOverlay('Form alanları okunuyor…');
    let data = { fields: [] };
    try { data = await api.get(`/api/forms/fields/${accepted[0].file_id}`); } catch (e) { toast(e.message, 'error'); }
    hideOverlay();
    stage.innerHTML = '';
    if (!data.fields || data.fields.length === 0) {
      stage.append(el('div', { class: 'result-card' }, [
        el('div', { class: 'result-icon', style: 'background:var(--amber-soft);color:var(--amber)', html: icon('info', 'ic', 40) }),
        el('h2', { text: 'Form alanı bulunamadı' }),
        el('p', { text: 'Bu PDF doldurulabilir form alanı (AcroForm) içermiyor.' }),
        el('button', { class: 'btn btn-ghost', html: icon('back', 'ic', 18) + 'Geri', onclick: () => openTool(tool.id) }),
      ]));
      return;
    }
    const panel = el('div', { class: 'options-panel', style: 'position:static;max-width:640px' });
    panel.append(el('h3', { text: `${data.fields.length} form alanı bulundu` }));
    panel.append(el('p', { class: 'op-sub', text: 'Değerleri girin ve kaydedin.' }));
    const inputs = {};
    for (const fld of data.fields) {
      if (fld.type === 'imza' || fld.type === 'buton') continue;
      const field = el('div', { class: 'field' });
      field.append(el('label', { text: `${fld.name} (${fld.type}, s.${fld.page + 1})` }));
      if (fld.type === 'onay-kutusu') {
        const cb = el('input', { type: 'checkbox' }); cb.checked = /^(1|true|on|yes|evet)$/i.test(fld.value || '');
        inputs[fld.name] = () => cb.checked ? 'true' : 'false';
        field.append(el('label', { class: 'check' }, [cb, el('span', { class: 'box' }), el('span', { class: 'lbl', text: 'İşaretli' })]));
      } else if (fld.options && fld.options.length) {
        const sel = el('select', { class: 'select' });
        for (const op of fld.options) sel.append(el('option', { value: op, text: op, selected: op === fld.value ? 'selected' : null }));
        inputs[fld.name] = () => sel.value; field.append(sel);
      } else {
        const inp = el('input', { class: 'input', type: 'text', value: fld.value || '' });
        inputs[fld.name] = () => inp.value; field.append(inp);
      }
      panel.append(field);
    }
    const flatten = el('input', { type: 'checkbox' });
    panel.append(el('label', { class: 'check' }, [flatten, el('span', { class: 'box' }), el('span', { class: 'lbl', text: 'Doldurduktan sonra düzleştir (değiştirilemez yap)' })]));
    const btn = el('button', { class: 'btn btn-primary btn-lg btn-block', style: 'margin-top:10px', html: icon('check', 'ic', 18) + 'Formu Doldur' });
    btn.addEventListener('click', async () => {
      const values = {}; for (const [k, getter] of Object.entries(inputs)) values[k] = getter();
      btn.classList.add('loading');
      try { const res = await api.post('/api/forms/fill', { file_id: app.files[0].file_id, values, flatten: flatten.checked }); renderResult(tool, res); }
      catch (e) { toast(e.message, 'error'); }
      btn.classList.remove('loading');
    });
    panel.append(btn);
    stage.append(panel);
  })));
  return wrap;
}

// ============================ FORM VERİSİ ÇIKARMA ============================
function renderFormsExtractFlow(tool) {
  const wrap = el('div');
  const stage = el('div');
  wrap.append(stage);
  stage.append(makeDropzone(tool, (files) => doUpload(files, tool, async (accepted) => {
    app.files = [accepted[0]];
    showOverlay('Veriler çıkarılıyor…');
    let data = { data: {} };
    try { data = await api.get(`/api/forms/extract/${accepted[0].file_id}`); } catch (e) { toast(e.message, 'error'); }
    hideOverlay();
    stage.innerHTML = '';
    const entries = Object.entries(data.data || {});
    const panel = el('div', { class: 'options-panel', style: 'position:static;max-width:640px' });
    panel.append(el('h3', { text: entries.length ? `${entries.length} alan bulundu` : 'Form verisi bulunamadı' }));
    if (entries.length) {
      const table = el('div', { style: 'display:flex;flex-direction:column;gap:6px;margin:12px 0' });
      for (const [k, v] of entries) {
        table.append(el('div', { style: 'display:flex;gap:12px;padding:9px 12px;background:var(--bg-soft);border-radius:9px' }, [
          el('strong', { style: 'flex:0 0 40%;font-size:13px', text: k }),
          el('span', { style: 'font-size:13px;color:var(--text-soft)', text: v || '—' }),
        ]));
      }
      panel.append(table);
      const json = JSON.stringify(data.data, null, 2);
      panel.append(el('button', { class: 'btn btn-primary btn-block', html: icon('download', 'ic', 18) + 'JSON olarak indir', onclick: () => {
        const blob = new Blob([json], { type: 'application/json' });
        download(URL.createObjectURL(blob), accepted[0].name.replace(/\.pdf$/i, '') + '_form.json');
      } }));
    } else {
      panel.append(el('p', { class: 'op-sub', text: 'Bu belgede doldurulmuş form verisi yok.' }));
    }
    panel.append(el('button', { class: 'btn btn-ghost btn-block', style: 'margin-top:10px', html: icon('back', 'ic', 18) + 'Geri', onclick: () => openTool(tool.id) }));
    stage.append(panel);
  })));
  return wrap;
}

window.addEventListener('DOMContentLoaded', init);
