// PDF Editörü — görsel anotasyon, çizim, imza ve redaksiyon.
import { icon } from './icons.js';
import { el, toast, showOverlay, hideOverlay, updateOverlayProgress, download, modal, registerWindowDrop } from './ui.js';
import * as api from './api.js';

const BASE_PXPT = 1.34;           // zoom=1'de nokta başına piksel
const SWATCHES = ['#e11d48', '#f59e0b', '#16a34a', '#2563eb', '#7c3aed', '#0891b2', '#111827', '#ffffff'];

export async function openEditor(tool) {
  // Diğer araçlarla tutarlı dropzone'lu açılış (eskiden doğrudan dosya
  // diyaloğu açılıyor, sürükle-bırak desteklenmiyordu).
  const content = document.getElementById('content');
  content.innerHTML = '';
  const container = el('div', { class: 'container' });
  container.append(el('div', { class: 'tool-header' }, [
    el('button', { class: 'icon-btn back', title: 'Geri', onclick: () => import('./app.js').then(m => m.init()), html: icon('back', 'ic', 20) }),
    el('div', { class: `tool-ic ${tool.color}`, html: icon(tool.icon, 'ic', 26) }),
    el('div', {}, [el('h1', { text: tool.title }), el('p', { text: tool.desc })]),
  ]));
  const stage = el('div');
  container.append(stage);
  content.append(container);

  const load = async (file) => {
    showOverlay('Belge yükleniyor…', file.name, { progress: true });
    try {
      const res = await api.upload([file], updateOverlayProgress);
      const fileInfo = res.files[0];
      if (fileInfo.kind !== 'pdf') { hideOverlay(); toast('Lütfen bir PDF seçin.', 'error'); return; }
      const info = await api.info(fileInfo.file_id);
      hideOverlay();
      if (info.encrypted) { toast('Şifreli PDF’ler editörde açılamaz; önce şifreyi kaldırın.', 'error'); return; }
      new Editor(tool, fileInfo, info).mount();
    } catch (e) { hideOverlay(); toast(e.message, 'error'); }
  };

  const input = el('input', { type: 'file', class: 'hidden', accept: 'application/pdf' });
  input.addEventListener('change', () => { if (input.files[0]) load(input.files[0]); });
  const dz = el('div', { class: 'dropzone', onclick: () => input.click() }, [
    el('div', { class: 'dz-ic', html: icon('uploadcloud', 'ic', 62) }),
    el('h3', { text: 'Düzenlenecek PDF’i sürükleyin' }),
    el('p', { text: 'veya bilgisayardan seçin · PDF' }),
    el('button', { class: 'btn btn-primary', html: icon('upload', 'ic', 18) + 'Dosya Seç' }),
    input,
  ]);
  ;['dragover', 'dragenter'].forEach(ev => dz.addEventListener(ev, e => { e.preventDefault(); dz.classList.add('drag'); }));
  ;['dragleave', 'drop'].forEach(ev => dz.addEventListener(ev, e => { e.preventDefault(); dz.classList.remove('drag'); }));
  dz.addEventListener('drop', e => { const f = e.dataTransfer?.files?.[0]; if (f) load(f); });
  registerWindowDrop(dz, (files) => { if (files[0]) load(files[0]); });
  stage.append(dz);
}

let uid = 0;
const nextId = () => 'a' + (++uid);

class Editor {
  constructor(tool, fileInfo, info) {
    this.tool = tool;
    this.file = fileInfo;
    this.pages = info.pages;              // [{width,height,rotation}]
    this.zoom = 1;
    this.activeTool = tool.editorTool || 'select';
    this.annotations = [];               // nokta uzayında
    this.imageRefs = {};                 // ref -> yüklenen file_id
    this.selected = null;
    this.color = '#e11d48';
    this.fillColor = null;
    this.strokeWidth = 2;
    this.fontSize = 16;
    this.opacity = 100;
    this.drawState = null;
    this.undoStack = [];
    this.redoStack = [];
    this.dataUrls = {};                  // anno id -> data_url (snapshot'larda tutulmaz)
  }

  pxPt() { return BASE_PXPT * this.zoom; }

  // -------- Geri al / yinele --------
  // Her mutasyondan ÖNCE mevcut durumun anlık görüntüsü yığına itilir.
  // Görsel/imza anotasyonlarının base64 data_url'ları snapshot'lara katılmaz
  // (100 snapshot × birkaç MB görsel = yüzlerce MB olurdu); dataUrls kaydından
  // geri yüklemede yeniden bağlanır.
  serializeState() {
    return JSON.stringify(this.annotations, (k, v) => (k === 'data_url' ? undefined : v));
  }

  restoreState(json) {
    this.annotations = JSON.parse(json);
    for (const a of this.annotations) {
      if ((a.type === 'image' || a.type === 'signature') && this.dataUrls[a.id]) {
        a.data_url = this.dataUrls[a.id];
      }
    }
  }

  pushUndo(snapshot = null) {
    this.undoStack.push(snapshot ?? this.serializeState());
    if (this.undoStack.length > 100) this.undoStack.shift();
    this.redoStack.length = 0;
    this.syncHistoryButtons();
  }

  undo() {
    if (!this.undoStack.length) return;
    this.redoStack.push(this.serializeState());
    this.restoreState(this.undoStack.pop());
    this.selected = null;
    this.redrawAnnotations(); this.renderProps(); this.syncHistoryButtons();
  }

  redo() {
    if (!this.redoStack.length) return;
    this.undoStack.push(this.serializeState());
    this.restoreState(this.redoStack.pop());
    this.selected = null;
    this.redrawAnnotations(); this.renderProps(); this.syncHistoryButtons();
  }

  syncHistoryButtons() {
    if (this.undoBtn) this.undoBtn.disabled = !this.undoStack.length;
    if (this.redoBtn) this.redoBtn.disabled = !this.redoStack.length;
  }

  mount() {
    const root = el('div', { class: 'editor' });
    this.root = root;

    // Üst çubuk
    root.append(el('div', { class: 'editor-top' }, [
      el('button', { class: 'icon-btn', title: 'Kapat', onclick: () => this.close(), html: icon('back', 'ic', 20) }),
      el('div', { class: 'e-title', html: `${this.tool.title} <small>${this.file.name}</small>` }),
      el('div', { class: 'spacer' }),
      (this.undoBtn = el('button', { class: 'icon-btn', title: 'Geri al (⌘Z)', disabled: 'disabled', onclick: () => this.undo(), html: icon('undo', 'ic', 18) })),
      (this.redoBtn = el('button', { class: 'icon-btn', title: 'Yinele (⇧⌘Z)', disabled: 'disabled', onclick: () => this.redo(), html: `<span style="display:inline-flex;transform:scaleX(-1)">${icon('undo', 'ic', 18)}</span>` })),
      el('div', { class: 'zoom-ctl' }, [
        el('button', { title: 'Uzaklaş', onclick: () => this.setZoom(this.zoom - 0.15), html: icon('zoomout', 'ic', 18) }),
        el('span', { id: 'zoomLbl', text: '100%' }),
        el('button', { title: 'Yakınlaş', onclick: () => this.setZoom(this.zoom + 0.15), html: icon('zoomin', 'ic', 18) }),
      ]),
      el('button', { class: 'btn btn-primary', style: 'margin-left:8px', onclick: () => this.save(), html: icon('download', 'ic', 18) + 'Kaydet ve İndir' }),
    ]));

    // Sol araç rayı
    this.rail = el('div', { class: 'editor-rail' });
    this.buildRail();
    root.append(this.rail);

    // Tuval
    this.canvas = el('div', { class: 'editor-canvas' });
    this.stack = el('div', { class: 'pages-stack' });
    this.canvas.append(this.stack);
    root.append(this.canvas);

    // Sağ özellik paneli
    this.props = el('div', { class: 'editor-props' });
    root.append(this.props);

    document.body.append(root);
    this.renderPages();
    this.renderProps();

    // Genel fare olayları (taşı/boyutlandır/çiz)
    this._onMove = (e) => this.onPointerMove(e);
    this._onUp = (e) => this.onPointerUp(e);
    document.addEventListener('pointermove', this._onMove);
    document.addEventListener('pointerup', this._onUp);
    this._onKey = (e) => {
      const editingText = document.activeElement?.getAttribute?.('contenteditable') === 'true';
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        if (editingText) return;   // metin kutusunda tarayıcının kendi geri alması çalışsın
        e.preventDefault();
        if (e.shiftKey) this.redo(); else this.undo();
        return;
      }
      if (e.key === 'Delete' && this.selected && !editingText) this.deleteAnno(this.selected);
      if (e.key === 'Escape') this.close();
    };
    document.addEventListener('keydown', this._onKey);
  }

  close() {
    document.removeEventListener('pointermove', this._onMove);
    document.removeEventListener('pointerup', this._onUp);
    document.removeEventListener('keydown', this._onKey);
    this.root.remove();
    import('./app.js').then(m => m.init());
  }

  setZoom(z) {
    this.zoom = Math.max(0.4, Math.min(2.5, z));
    document.getElementById('zoomLbl').textContent = Math.round(this.zoom * 100) + '%';
    this.renderPages();
  }

  // -------- Araç rayı --------
  buildRail() {
    const tools = [
      ['select', 'cursor', 'Seç'],
      ['sep'],
      ['text', 'type', 'Metin'],
      ['freehand', 'pen', 'Çizim'],
      ['highlight', 'highlighter', 'Vurgu'],
      ['sep'],
      ['rect', 'square', 'Kutu'],
      ['ellipse', 'circle', 'Daire'],
      ['line', 'line', 'Çizgi'],
      ['arrow', 'arrow', 'Ok'],
      ['sep'],
      ['image', 'image', 'Görsel'],
      ['signature', 'sign', 'İmza'],
      ['redact', 'redact', 'Redaksiyon'],
    ];
    this.rail.innerHTML = '';
    for (const t of tools) {
      if (t[0] === 'sep') { this.rail.append(el('div', { class: 'rail-sep' })); continue; }
      const [id, ic, label] = t;
      const btn = el('button', { class: 'tool-btn' + (this.activeTool === id ? ' active' : ''), html: icon(ic, 'ic', 21) + `<span>${label}</span>` });
      btn.addEventListener('click', () => this.selectTool(id));
      this.rail.append(btn);
    }
  }

  selectTool(id) {
    if (id === 'image') { this.addImageFlow(false); return; }
    if (id === 'signature') { this.signatureFlow(); return; }
    this.activeTool = id;
    this.selected = null;
    this.buildRail();
    this.renderProps();
    this.updateLayerCursors();
  }

  updateLayerCursors() {
    this.stack.querySelectorAll('.anno-layer').forEach(l => {
      l.classList.toggle('drawing', this.activeTool !== 'select');
    });
  }

  // -------- Sayfalar --------
  renderPages() {
    const pxPt = this.pxPt();
    this.stack.innerHTML = '';
    this.pageEls = [];
    this.pages.forEach((pg, i) => {
      const w = pg.width * pxPt, h = pg.height * pxPt;
      const wrap = el('div', { class: 'page-wrap', style: `width:${w}px;height:${h}px`, 'data-page': i });
      wrap.append(el('div', { class: 'page-label', text: `Sayfa ${i + 1}` }));
      const img = el('img', { class: 'page-img', src: api.renderUrl(this.file.file_id, i), style: `width:${w}px;height:${h}px`, alt: '' });
      wrap.append(img);
      const layer = el('div', { class: 'anno-layer' + (this.activeTool !== 'select' ? ' drawing' : '') });
      const svg = el('div');
      svg.innerHTML = `<svg class="anno-svg" data-svg="${i}"></svg>`;
      layer.append(svg.firstChild);
      wrap.append(layer);
      layer.addEventListener('pointerdown', (e) => this.onLayerDown(e, i, layer));
      this.stack.append(wrap);
      this.pageEls[i] = { wrap, layer };
    });
    this.redrawAnnotations();
  }

  ptFromEvent(e, pageIndex) {
    const rect = this.pageEls[pageIndex].wrap.getBoundingClientRect();
    const pxPt = this.pxPt();
    return {
      x: (e.clientX - rect.left) / pxPt,
      y: (e.clientY - rect.top) / pxPt,
    };
  }

  // -------- Katmanda fare basımı (çizim başlat) --------
  onLayerDown(e, pageIndex, layer) {
    if (e.target.closest('.anno')) return;   // öğeye tıklandıysa taşımaya bırak
    if (this.activeTool === 'select') { this.select(null); return; }
    e.preventDefault();
    const p = this.ptFromEvent(e, pageIndex);

    if (this.activeTool === 'text') {
      const a = { id: nextId(), page: pageIndex, type: 'text', x: p.x, y: p.y, w: 180, h: this.fontSize * 1.6, text: '', fontsize: this.fontSize, color: this.color, bold: false, italic: false };
      this.pushUndo();
      this.annotations.push(a); this.redrawAnnotations(); this.select(a.id);
      setTimeout(() => { const node = this.nodeFor(a.id)?.querySelector('.anno-text'); if (node) { node.setAttribute('contenteditable', 'true'); node.focus(); } }, 20);
      return;
    }
    // Sürükleyerek çizilen tipler
    this.drawState = { pageIndex, start: p, tool: this.activeTool, id: nextId(), points: [p] };
    if (this.activeTool === 'freehand') {
      this.drawState.anno = { id: this.drawState.id, page: pageIndex, type: 'freehand', points: [[p.x, p.y]], color: this.color, width: this.strokeWidth };
      this.pushUndo();
      this.annotations.push(this.drawState.anno);
    }
  }

  onPointerMove(e) {
    // Öğe taşıma/boyutlandırma
    if (this.dragOp) { this.handleDrag(e); return; }
    if (!this.drawState) return;
    const { pageIndex, start, tool } = this.drawState;
    const p = this.ptFromEvent(e, pageIndex);
    if (tool === 'freehand') {
      this.drawState.anno.points.push([p.x, p.y]);
      this.redrawAnnotations();
      return;
    }
    // geçici önizleme
    this.previewShape(pageIndex, tool, start, p);
  }

  onPointerUp(e) {
    if (this.dragOp) {
      // Taşıma/boyutlandırma gerçekten bir şey değiştirdiyse tek adım olarak kaydet
      const { histBefore } = this.dragOp;
      if (histBefore && this.serializeState() !== histBefore) this.pushUndo(histBefore);
      this.dragOp = null;
      return;
    }
    if (!this.drawState) return;
    const { pageIndex, start, tool, id } = this.drawState;
    const p = this.ptFromEvent(e, pageIndex);
    this.clearPreview();
    if (tool === 'freehand') { this.drawState = null; this.select(id); this.renderProps(); return; }

    const dx = p.x - start.x, dy = p.y - start.y;
    let a = null;
    if (tool === 'line' || tool === 'arrow') {
      if (Math.abs(dx) + Math.abs(dy) < 4) { this.drawState = null; return; }
      a = { id, page: pageIndex, type: tool, x1: start.x, y1: start.y, x2: p.x, y2: p.y, color: this.color, width: this.strokeWidth };
    } else {
      const x = Math.min(start.x, p.x), y = Math.min(start.y, p.y), w = Math.abs(dx), h = Math.abs(dy);
      if (w < 4 || h < 4) { this.drawState = null; return; }
      if (tool === 'rect') a = { id, page: pageIndex, type: 'rect', x, y, w, h, color: this.color, fill: this.fillColor, width: this.strokeWidth };
      else if (tool === 'ellipse') a = { id, page: pageIndex, type: 'ellipse', x, y, w, h, color: this.color, fill: this.fillColor, width: this.strokeWidth };
      else if (tool === 'highlight') a = { id, page: pageIndex, type: 'highlight', x, y, w, h, color: this.color, opacity: 0.35 };
      else if (tool === 'redact') a = { id, page: pageIndex, type: 'redact', x, y, w, h };
    }
    if (a) { this.pushUndo(); this.annotations.push(a); this.redrawAnnotations(); this.select(id); this.renderProps(); }
    this.drawState = null;
  }

  previewShape(pageIndex, tool, start, p) {
    const svg = this.pageEls[pageIndex].layer.querySelector('svg');
    this.clearPreview();
    const pxPt = this.pxPt();
    const ns = 'http://www.w3.org/2000/svg';
    let node;
    const stroke = this.color, sw = this.strokeWidth * pxPt;
    if (tool === 'line' || tool === 'arrow') {
      node = document.createElementNS(ns, 'line');
      node.setAttribute('x1', start.x * pxPt); node.setAttribute('y1', start.y * pxPt);
      node.setAttribute('x2', p.x * pxPt); node.setAttribute('y2', p.y * pxPt);
      node.setAttribute('stroke', stroke); node.setAttribute('stroke-width', sw); node.setAttribute('stroke-linecap', 'round');
    } else {
      const x = Math.min(start.x, p.x) * pxPt, y = Math.min(start.y, p.y) * pxPt;
      const w = Math.abs(p.x - start.x) * pxPt, h = Math.abs(p.y - start.y) * pxPt;
      if (tool === 'ellipse') {
        node = document.createElementNS(ns, 'ellipse');
        node.setAttribute('cx', x + w / 2); node.setAttribute('cy', y + h / 2);
        node.setAttribute('rx', w / 2); node.setAttribute('ry', h / 2);
        node.setAttribute('fill', 'none'); node.setAttribute('stroke', stroke); node.setAttribute('stroke-width', sw);
      } else {
        node = document.createElementNS(ns, 'rect');
        node.setAttribute('x', x); node.setAttribute('y', y); node.setAttribute('width', w); node.setAttribute('height', h);
        node.setAttribute('fill', tool === 'highlight' ? this.color : 'none');
        node.setAttribute('fill-opacity', tool === 'highlight' ? 0.35 : 0);
        node.setAttribute('stroke', tool === 'redact' ? '#000' : stroke); node.setAttribute('stroke-width', tool === 'highlight' ? 0 : sw);
      }
    }
    node.setAttribute('data-preview', '1');
    svg.append(node);
  }

  clearPreview() {
    this.stack.querySelectorAll('[data-preview]').forEach(n => n.remove());
  }

  // -------- Anotasyonları çiz --------
  redrawAnnotations() {
    const pxPt = this.pxPt();
    // her katmanı temizle
    this.pageEls.forEach(({ layer }) => {
      layer.querySelectorAll('.anno, .redact-box').forEach(n => n.remove());
      layer.querySelector('svg').innerHTML = '';
    });
    for (const a of this.annotations) {
      const pe = this.pageEls[a.page]; if (!pe) continue;
      const layer = pe.layer;
      if (a.type === 'line' || a.type === 'arrow' || a.type === 'freehand') {
        this.drawSvgAnno(layer.querySelector('svg'), a, pxPt);
      } else {
        layer.append(this.buildBoxAnno(a, pxPt));
      }
    }
    // seçiliyi işaretle
    if (this.selected) this.nodeFor(this.selected)?.classList.add('selected');
  }

  drawSvgAnno(svg, a, pxPt) {
    const ns = 'http://www.w3.org/2000/svg';
    const g = document.createElementNS(ns, 'g');
    g.setAttribute('data-id', a.id);
    g.style.pointerEvents = 'stroke';
    g.style.cursor = 'move';
    const sw = (a.width || 2) * pxPt;
    if (a.type === 'freehand') {
      const path = document.createElementNS(ns, 'polyline');
      path.setAttribute('points', a.points.map(([x, y]) => `${x * pxPt},${y * pxPt}`).join(' '));
      path.setAttribute('fill', 'none'); path.setAttribute('stroke', a.color); path.setAttribute('stroke-width', sw);
      path.setAttribute('stroke-linecap', 'round'); path.setAttribute('stroke-linejoin', 'round');
      g.append(path);
    } else {
      const line = document.createElementNS(ns, 'line');
      line.setAttribute('x1', a.x1 * pxPt); line.setAttribute('y1', a.y1 * pxPt);
      line.setAttribute('x2', a.x2 * pxPt); line.setAttribute('y2', a.y2 * pxPt);
      line.setAttribute('stroke', a.color); line.setAttribute('stroke-width', sw); line.setAttribute('stroke-linecap', 'round');
      g.append(line);
      if (a.type === 'arrow') {
        const ang = Math.atan2(a.y2 - a.y1, a.x2 - a.x1);
        const sz = 10;
        for (const da of [Math.PI * 5 / 6, -Math.PI * 5 / 6]) {
          const hx = a.x2 + sz * Math.cos(ang + da), hy = a.y2 + sz * Math.sin(ang + da);
          const l = document.createElementNS(ns, 'line');
          l.setAttribute('x1', a.x2 * pxPt); l.setAttribute('y1', a.y2 * pxPt);
          l.setAttribute('x2', hx * pxPt); l.setAttribute('y2', hy * pxPt);
          l.setAttribute('stroke', a.color); l.setAttribute('stroke-width', sw); l.setAttribute('stroke-linecap', 'round');
          g.append(l);
        }
      }
    }
    g.addEventListener('pointerdown', (e) => { e.stopPropagation(); this.select(a.id); this.startDrag(e, a, 'move'); });
    if (this.selected === a.id) g.style.filter = 'drop-shadow(0 0 3px var(--primary))';
    svg.append(g);
  }

  buildBoxAnno(a, pxPt) {
    const node = el('div', { class: 'anno', 'data-id': a.id, style: `left:${a.x * pxPt}px;top:${a.y * pxPt}px;width:${a.w * pxPt}px;height:${a.h * pxPt}px` });
    if (a.type === 'text') {
      const t = el('div', { class: 'anno-text', style: `font-size:${a.fontsize * pxPt}px;color:${a.color};font-weight:${a.bold ? 700 : 400};font-style:${a.italic ? 'italic' : 'normal'};width:100%;height:100%` });
      t.textContent = a.text || '';
      t.addEventListener('blur', () => {
        if (t.textContent !== (a.text || '')) {
          const snap = this.serializeState();   // eski metni içeren durum
          a.text = t.textContent;
          this.pushUndo(snap);
        }
        t.removeAttribute('contenteditable');
      });
      t.addEventListener('dblclick', () => { t.setAttribute('contenteditable', 'true'); t.focus(); });
      node.append(t);
    } else if (a.type === 'rect' || a.type === 'ellipse') {
      const s = el('div', { class: 'anno-shape', style: `width:100%;height:100%;border:${a.width * pxPt}px solid ${a.color};background:${a.fill || 'transparent'};${a.type === 'ellipse' ? 'border-radius:50%' : 'border-radius:2px'}` });
      node.append(s);
    } else if (a.type === 'highlight') {
      node.classList.add('anno-highlight');
      node.style.background = a.color; node.style.opacity = a.opacity ?? 0.35;
    } else if (a.type === 'redact') {
      node.classList.add('redact-box');
    } else if (a.type === 'image' || a.type === 'signature') {
      const im = el('div', { class: 'anno-img', style: 'width:100%;height:100%' });
      im.append(el('img', { src: a.data_url, alt: '' }));
      node.append(im);
    }
    // taşı
    node.addEventListener('pointerdown', (e) => {
      if (e.target.getAttribute('contenteditable') === 'true') return;
      e.stopPropagation(); this.select(a.id); this.startDrag(e, a, 'move');
    });
    // seçiliyse tutamak + sil
    if (this.selected === a.id) {
      node.classList.add('selected');
      if (a.type !== 'redact' || true) {
        const handle = el('div', { class: 'handle br' });
        handle.addEventListener('pointerdown', (e) => { e.stopPropagation(); this.startDrag(e, a, 'resize'); });
        node.append(handle);
      }
      const del = el('div', { class: 'del-btn', html: icon('x', 'ic', 12), onpointerdown: (e) => e.stopPropagation(), onclick: (e) => { e.stopPropagation(); this.deleteAnno(a.id); } });
      node.append(del);
    }
    return node;
  }

  nodeFor(id) {
    return this.stack.querySelector(`.anno[data-id="${id}"]`) || this.stack.querySelector(`g[data-id="${id}"]`);
  }

  // -------- Seçim & sürükleme --------
  select(id) {
    this.selected = id;
    this.redrawAnnotations();
    this.renderProps();
  }

  startDrag(e, a, mode) {
    e.preventDefault();
    const p = this.ptFromEvent(e, a.page);
    this.dragOp = { a, mode, startPt: p, orig: JSON.parse(JSON.stringify(a)), histBefore: this.serializeState() };
  }

  handleDrag(e) {
    const { a, mode, startPt, orig } = this.dragOp;
    const p = this.ptFromEvent(e, a.page);
    const dx = p.x - startPt.x, dy = p.y - startPt.y;
    if (a.type === 'line' || a.type === 'arrow') {
      a.x1 = orig.x1 + dx; a.y1 = orig.y1 + dy; a.x2 = orig.x2 + dx; a.y2 = orig.y2 + dy;
    } else if (a.type === 'freehand') {
      a.points = orig.points.map(([x, y]) => [x + dx, y + dy]);
    } else if (mode === 'move') {
      a.x = orig.x + dx; a.y = orig.y + dy;
    } else if (mode === 'resize') {
      a.w = Math.max(10, orig.w + dx); a.h = Math.max(8, orig.h + dy);
    }
    this.redrawAnnotations();
  }

  deleteAnno(id) {
    this.pushUndo();
    this.annotations = this.annotations.filter(a => a.id !== id);
    if (this.selected === id) this.selected = null;
    this.redrawAnnotations();
    this.renderProps();
  }

  // -------- Görsel / imza ekleme --------
  async addImageFlow(isSignature) {
    const input = el('input', { type: 'file', class: 'hidden', accept: 'image/*' });
    input.addEventListener('change', async () => {
      if (!input.files.length) return;
      const f = input.files[0];
      const dataUrl = await fileToDataUrl(f);
      await this.placeImage(dataUrl, isSignature);
    }, { once: true });
    input.click();
  }

  async placeImage(dataUrl, isSignature) {
    showOverlay('Görsel ekleniyor…');
    let ref;
    try {
      const blob = dataUrlToBlob(dataUrl);
      const file = new File([blob], (isSignature ? 'imza' : 'gorsel') + '.png', { type: blob.type || 'image/png' });
      const res = await api.upload([file]);
      ref = res.files[0].file_id;
    } catch (e) { hideOverlay(); toast(e.message, 'error'); return; }
    hideOverlay();
    // boyutu görselin oranından hesapla
    const dim = await imgDim(dataUrl);
    const pageIndex = this.currentVisiblePage();
    const pg = this.pages[pageIndex];
    let w = Math.min(pg.width * 0.4, 220);
    let h = w * (dim.h / dim.w);
    const a = { id: nextId(), page: pageIndex, type: isSignature ? 'signature' : 'image', x: (pg.width - w) / 2, y: (pg.height - h) / 2, w, h, data_url: dataUrl, image_ref: ref };
    this.imageRefs[ref] = ref;
    a.image_ref = ref;
    this.dataUrls[a.id] = dataUrl;
    this.pushUndo();
    this.annotations.push(a);
    this.activeTool = 'select'; this.buildRail();
    this.redrawAnnotations(); this.select(a.id);
    toast('Görsel eklendi — konumlandırıp boyutlandırabilirsiniz.', 'success');
  }

  currentVisiblePage() {
    const scrollTop = this.canvas.scrollTop;
    let best = 0, bestDist = Infinity;
    this.pageEls.forEach((pe, i) => {
      const top = pe.wrap.offsetTop;
      const d = Math.abs(top - scrollTop - 60);
      if (d < bestDist) { bestDist = d; best = i; }
    });
    return best;
  }

  signatureFlow() {
    const body = el('div');

    // Kayıtlı imza galerisi: daha önce "hatırla" ile saklanan imzalar tek tıkla eklenir
    const saved = loadSavedSignatures();
    if (saved.length) {
      const gal = el('div', { class: 'sig-gallery' });
      gal.append(el('div', { class: 'sig-gallery-title', text: 'Kayıtlı imzalarınız' }));
      const rowEl = el('div', { class: 'sig-gallery-row' });
      saved.forEach((du, idx) => {
        const item = el('div', { class: 'sig-gallery-item', title: 'Bu imzayı ekle' });
        item.append(el('img', { src: du, alt: `Kayıtlı imza ${idx + 1}` }));
        item.addEventListener('click', async () => { m.close(); await this.placeImage(du, true); });
        item.append(el('button', { class: 'sig-gallery-del', title: 'Kayıtlı imzayı sil', html: icon('x', 'ic', 12), onclick: (e) => {
          e.stopPropagation();
          saveSignatures(loadSavedSignatures().filter((_, i) => i !== idx));
          item.remove();
          if (!rowEl.children.length) gal.remove();
        } }));
        rowEl.append(item);
      });
      gal.append(rowEl);
      body.append(gal);
    }

    const tabs = el('div', { class: 'sig-tabs' });
    const drawTab = el('button', { class: 'active', text: 'Çiz' });
    const typeTab = el('button', { text: 'Yaz' });
    const upTab = el('button', { text: 'Yükle' });
    tabs.append(drawTab, typeTab, upTab);
    const holder = el('div');
    body.append(tabs, holder);

    let getImage = null;
    const showDraw = () => {
      setActive(drawTab); holder.innerHTML = '';
      const canvas = el('canvas', { class: 'sig-canvas', width: 900, height: 300 });
      holder.append(canvas, el('p', { class: 'hint', style: 'margin-top:8px', text: 'Fare veya parmağınızla imzanızı çizin.' }));
      const ctx = canvas.getContext('2d');
      ctx.lineWidth = 3.2; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = '#111';
      let drawing = false, empty = true;
      const pos = (e) => { const r = canvas.getBoundingClientRect(); const cx = (e.touches ? e.touches[0].clientX : e.clientX) - r.left; const cy = (e.touches ? e.touches[0].clientY : e.clientY) - r.top; return [cx * canvas.width / r.width, cy * canvas.height / r.height]; };
      const down = (e) => { e.preventDefault(); drawing = true; empty = false; const [x, y] = pos(e); ctx.beginPath(); ctx.moveTo(x, y); };
      const move = (e) => { if (!drawing) return; e.preventDefault(); const [x, y] = pos(e); ctx.lineTo(x, y); ctx.stroke(); };
      const up = () => drawing = false;
      canvas.addEventListener('pointerdown', down); canvas.addEventListener('pointermove', move); document.addEventListener('pointerup', up);
      getImage = () => empty ? null : canvas.toDataURL('image/png');
    };
    const showType = () => {
      setActive(typeTab); holder.innerHTML = '';
      const inp = el('input', { class: 'sig-type-input', placeholder: 'Adınız', value: '' });
      holder.append(inp);
      getImage = () => { const v = inp.value.trim(); if (!v) return null; return typedSignatureDataUrl(v); };
    };
    const showUpload = () => {
      setActive(upTab); holder.innerHTML = '';
      const prev = el('div', { style: 'text-align:center' });
      const fi = el('input', { type: 'file', class: 'hidden', accept: 'image/*' });
      let du = null;
      fi.addEventListener('change', async () => { if (fi.files[0]) { du = await fileToDataUrl(fi.files[0]); prev.innerHTML = `<img src="${du}" style="max-height:160px;max-width:100%">`; } });
      holder.append(el('button', { class: 'btn btn-ghost', html: icon('upload', 'ic', 16) + 'Görsel Seç', onclick: () => fi.click() }), fi, el('div', { style: 'margin-top:12px' }, [prev]));
      getImage = () => du;
    };
    const setActive = (b) => { [drawTab, typeTab, upTab].forEach(x => x.classList.remove('active')); b.classList.add('active'); };
    drawTab.onclick = showDraw; typeTab.onclick = showType; upTab.onclick = showUpload;
    showDraw();

    const foot = el('div');
    const rememberCb = el('input', { type: 'checkbox' });
    const m = modal({
      title: 'İmza Ekle', bodyNode: body, wide: true,
      footNode: (() => {
        foot.append(el('label', { class: 'check', style: 'margin-right:auto' }, [
          rememberCb, el('span', { class: 'box' }), el('span', { class: 'lbl', text: 'İmzayı hatırla' }),
        ]));
        const cancel = el('button', { class: 'btn btn-ghost', text: 'İptal', onclick: () => m.close() });
        const ok = el('button', { class: 'btn btn-primary', html: icon('check', 'ic', 16) + 'İmzayı Ekle', onclick: async () => {
          const du = getImage && getImage();
          if (!du) { toast('Lütfen bir imza oluşturun.', 'warn'); return; }
          if (rememberCb.checked) rememberSignature(du);
          m.close();
          await this.placeImage(du, true);
        } });
        foot.append(cancel, ok); return foot;
      })(),
    });
  }

  // -------- Özellik paneli --------
  renderProps() {
    const p = this.props;
    p.innerHTML = '';
    const sel = this.selected ? this.annotations.find(a => a.id === this.selected) : null;

    if (sel) {
      p.append(el('h4', { html: icon('edit', 'ic', 16) + 'Seçili Öğe' }));
      p.append(this.selEditor(sel));
      p.append(el('button', { class: 'btn btn-danger btn-block btn-sm', style: 'margin-top:12px', html: icon('trash', 'ic', 15) + 'Öğeyi Sil', onclick: () => this.deleteAnno(sel.id) }));
    } else {
      p.append(el('h4', { html: icon('edit', 'ic', 16) + 'Araç Ayarları' }));
      p.append(this.toolSettings());
    }

    // Sayfa küçük resimleri
    p.append(el('h4', { style: 'margin-top:22px', html: icon('pages', 'ic', 16) + 'Sayfalar' }));
    const mini = el('div', { class: 'mini-thumbs' });
    this.pages.forEach((_, i) => {
      const mt = el('div', { class: 'mini-thumb', onclick: () => this.pageEls[i].wrap.scrollIntoView({ behavior: 'smooth', block: 'start' }) }, [
        el('img', { src: api.renderUrl(this.file.file_id, i, 'thumb'), alt: '' }),
        el('span', { class: 'n', text: i + 1 }),
      ]);
      mini.append(mt);
    });
    p.append(mini);
  }

  colorSwatches(current, onPick) {
    const row = el('div', { class: 'swatch-row' });
    for (const c of SWATCHES) {
      const s = el('div', { class: 'swatch' + (current === c ? ' active' : ''), style: `background:${c};${c === '#ffffff' ? 'border:1px solid var(--border-strong)' : ''}`, onclick: () => onPick(c) });
      row.append(s);
    }
    const ci = el('input', { type: 'color', value: current || '#000000', style: 'width:26px;height:26px;border:none;border-radius:7px;background:none;cursor:pointer' });
    ci.addEventListener('input', () => onPick(ci.value));
    row.append(ci);
    return row;
  }

  toolSettings() {
    const wrap = el('div');
    const t = this.activeTool;
    const hint = {
      select: 'Bir öğeyi seçmek için üzerine tıklayın. Taşımak için sürükleyin.',
      text: 'Metin eklemek için sayfaya tıklayın.',
      freehand: 'Serbest çizim için basılı tutup sürükleyin.',
      highlight: 'Vurgulamak için bir alan çizin.',
      rect: 'Kutu çizmek için sürükleyin.', ellipse: 'Daire çizmek için sürükleyin.',
      line: 'Çizgi için sürükleyin.', arrow: 'Ok için sürükleyin.',
      redact: 'Karartmak için alan çizin (içerik kalıcı silinir).',
    }[t] || '';
    wrap.append(el('p', { style: 'font-size:13px;color:var(--text-soft);margin:0 0 14px', text: hint }));

    if (['text', 'freehand', 'rect', 'ellipse', 'line', 'arrow', 'highlight'].includes(t)) {
      wrap.append(el('label', { style: 'font-size:12px;font-weight:650;color:var(--text-soft)', text: t === 'highlight' ? 'Vurgu rengi' : 'Renk' }));
      wrap.append(this.colorSwatches(t === 'highlight' ? this.color : this.color, (c) => { this.color = c; this.renderProps(); }));
    }
    if (['text'].includes(t)) {
      wrap.append(sliderField('Yazı boyutu', this.fontSize, 8, 72, 'pt', (v) => this.fontSize = v));
    }
    if (['freehand', 'rect', 'ellipse', 'line', 'arrow'].includes(t)) {
      wrap.append(sliderField('Çizgi kalınlığı', this.strokeWidth, 1, 12, 'px', (v) => this.strokeWidth = v));
    }
    if (['rect', 'ellipse'].includes(t)) {
      wrap.append(el('label', { style: 'font-size:12px;font-weight:650;color:var(--text-soft);margin-top:12px;display:block', text: 'Dolgu' }));
      const noFill = el('button', { class: 'btn btn-sm' + (!this.fillColor ? ' btn-primary' : ' btn-ghost'), text: 'Yok', onclick: () => { this.fillColor = null; this.renderProps(); } });
      const row = el('div', { style: 'display:flex;gap:8px;align-items:center;margin-top:6px' }, [noFill]);
      row.append(this.colorSwatches(this.fillColor, (c) => { this.fillColor = c; this.renderProps(); }));
      wrap.append(row);
    }
    return wrap;
  }

  selEditor(a) {
    const wrap = el('div');
    const mutate = (fn) => { this.pushUndo(); fn(); this.redrawAnnotations(); this.renderProps(); };
    const history = { capture: () => this.serializeState(), commit: (snap) => this.pushUndo(snap) };
    if (a.type === 'text') {
      wrap.append(el('label', { style: 'font-size:12px;font-weight:650', text: 'Renk' }));
      wrap.append(this.colorSwatches(a.color, (c) => mutate(() => a.color = c)));
      wrap.append(sliderField('Yazı boyutu', a.fontsize, 8, 72, 'pt', (v) => { a.fontsize = v; a.h = v * 1.6; this.redrawAnnotations(); }, history));
      const style = el('div', { style: 'display:flex;gap:8px;margin-top:8px' }, [
        el('button', { class: 'btn btn-sm' + (a.bold ? ' btn-primary' : ' btn-ghost'), style: 'font-weight:800;flex:1', text: 'B', onclick: () => mutate(() => a.bold = !a.bold) }),
        el('button', { class: 'btn btn-sm' + (a.italic ? ' btn-primary' : ' btn-ghost'), style: 'font-style:italic;flex:1', text: 'I', onclick: () => mutate(() => a.italic = !a.italic) }),
      ]);
      wrap.append(style);
    } else if (a.type === 'rect' || a.type === 'ellipse') {
      wrap.append(el('label', { style: 'font-size:12px;font-weight:650', text: 'Çizgi rengi' }));
      wrap.append(this.colorSwatches(a.color, (c) => mutate(() => a.color = c)));
      wrap.append(sliderField('Kalınlık', a.width, 1, 12, 'px', (v) => { a.width = v; this.redrawAnnotations(); }, history));
      wrap.append(el('label', { style: 'font-size:12px;font-weight:650;margin-top:10px;display:block', text: 'Dolgu' }));
      const noFill = el('button', { class: 'btn btn-sm' + (!a.fill ? ' btn-primary' : ' btn-ghost'), text: 'Yok', onclick: () => mutate(() => a.fill = null) });
      const row = el('div', { style: 'display:flex;gap:8px;align-items:center;margin-top:6px' }, [noFill]);
      row.append(this.colorSwatches(a.fill, (c) => mutate(() => a.fill = c)));
      wrap.append(row);
    } else if (a.type === 'line' || a.type === 'arrow' || a.type === 'freehand') {
      wrap.append(el('label', { style: 'font-size:12px;font-weight:650', text: 'Renk' }));
      wrap.append(this.colorSwatches(a.color, (c) => mutate(() => a.color = c)));
      wrap.append(sliderField('Kalınlık', a.width, 1, 12, 'px', (v) => { a.width = v; this.redrawAnnotations(); }, history));
    } else if (a.type === 'highlight') {
      wrap.append(el('label', { style: 'font-size:12px;font-weight:650', text: 'Renk' }));
      wrap.append(this.colorSwatches(a.color, (c) => mutate(() => a.color = c)));
    } else if (a.type === 'image' || a.type === 'signature') {
      wrap.append(el('p', { style: 'font-size:13px;color:var(--text-soft)', text: 'Köşedeki tutamaktan boyutlandırın, sürükleyerek taşıyın.' }));
    } else if (a.type === 'redact') {
      wrap.append(el('p', { style: 'font-size:13px;color:var(--text-soft)', text: 'Bu alan kaydederken kalıcı olarak karartılacak.' }));
    }
    return wrap;
  }

  // -------- Kaydet --------
  async save() {
    if (this.annotations.length === 0) { toast('Kaydedilecek bir değişiklik yok.', 'warn'); return; }
    // metin düzenlemesi bitmemişse yakala
    this.stack.querySelectorAll('.anno-text[contenteditable="true"]').forEach(n => n.blur());

    const redactions = this.annotations.filter(a => a.type === 'redact');
    const others = this.annotations.filter(a => a.type !== 'redact');

    showOverlay('Değişiklikler uygulanıyor…');
    try {
      let fileId = this.file.file_id;
      if (redactions.length) {
        const boxes = redactions.map(a => ({ page: a.page, x0: a.x, y0: a.y, x1: a.x + a.w, y1: a.y + a.h, color: '#000000' }));
        const r = await api.post('/api/edit/redact', { file_id: fileId, boxes });
        fileId = r.outputs[0].file_id;
      }
      let finalOut;
      if (others.length) {
        const image_refs = {};
        for (const a of others) if (a.image_ref) image_refs[a.image_ref] = a.image_ref;
        const annos = others.map(a => this.serializeAnno(a));
        const r = await api.post('/api/edit/annotate', { file_id: fileId, annotations: annos, image_refs });
        finalOut = r.outputs[0];
      } else if (redactions.length) {
        // yalnızca redaksiyon: son çıktı redaksiyon sonucudur — tekrar indirilebilir bilgi al
        const r = await api.post('/api/edit/annotate', { file_id: fileId, annotations: [], image_refs: {} });
        finalOut = r.outputs[0];
      }
      hideOverlay();
      toast('Kaydedildi! İndiriliyor…', 'success');
      download(finalOut.download_url, finalOut.name);
    } catch (e) { hideOverlay(); toast(e.message, 'error', 5000); }
  }

  serializeAnno(a) {
    const base = { page: a.page, type: a.type };
    if (a.type === 'text') return { ...base, x: a.x, y: a.y, w: a.w, h: a.h, text: a.text, fontsize: a.fontsize, color: a.color, bold: a.bold, italic: a.italic };
    if (a.type === 'rect' || a.type === 'ellipse') return { ...base, x: a.x, y: a.y, w: a.w, h: a.h, color: a.color, fill: a.fill || null, width: a.width };
    if (a.type === 'highlight') return { ...base, x: a.x, y: a.y, w: a.w, h: a.h, color: a.color, opacity: a.opacity };
    if (a.type === 'line' || a.type === 'arrow') return { ...base, x1: a.x1, y1: a.y1, x2: a.x2, y2: a.y2, color: a.color, width: a.width };
    if (a.type === 'freehand') return { ...base, points: a.points, color: a.color, width: a.width };
    if (a.type === 'image' || a.type === 'signature') return { ...base, x: a.x, y: a.y, w: a.w, h: a.h, image_ref: a.image_ref };
    return base;
  }
}

// -------- Kayıtlı imzalar (localStorage) --------
const SIG_STORE_KEY = 'pdfstudio_signatures';
const SIG_STORE_MAX = 5;

function loadSavedSignatures() {
  try {
    const arr = JSON.parse(localStorage.getItem(SIG_STORE_KEY) || '[]');
    return Array.isArray(arr) ? arr.filter(s => typeof s === 'string' && s.startsWith('data:image/')) : [];
  } catch { return []; }
}

function saveSignatures(list) {
  try { localStorage.setItem(SIG_STORE_KEY, JSON.stringify(list.slice(0, SIG_STORE_MAX))); }
  catch { toast('İmza kaydedilemedi (tarayıcı depolama sınırı).', 'warn'); }
}

function rememberSignature(dataUrl) {
  const list = loadSavedSignatures().filter(s => s !== dataUrl);
  list.unshift(dataUrl);
  saveSignatures(list);
}

// -------- Yardımcılar --------
// history verilirse slider hareketi TEK undo adımı olur: jest başında anlık
// görüntü alınır, bırakışta ('change') geçmişe itilir.
function sliderField(label, value, min, max, unit, onChange, history) {
  const wrap = el('div', { class: 'field', style: 'margin-top:10px' });
  const val = el('span', { class: 'range-val', text: value + (unit || '') });
  wrap.append(el('label', { style: 'font-size:12px;font-weight:650;color:var(--text-soft)' , text: label }));
  const rg = el('input', { type: 'range', min, max, value, step: 1, style: 'width:100%' });
  let snap = null;
  const capture = () => { if (history && snap === null) snap = history.capture(); };
  rg.addEventListener('pointerdown', capture);
  rg.addEventListener('keydown', capture);
  rg.addEventListener('input', () => { val.textContent = rg.value + (unit || ''); onChange(+rg.value); });
  rg.addEventListener('change', () => { if (history && snap !== null) { history.commit(snap); snap = null; } });
  wrap.append(el('div', { class: 'range-row' }, [rg, val]));
  return wrap;
}

function fileToDataUrl(file) {
  return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(file); });
}
function dataUrlToBlob(dataUrl) {
  const [head, b64] = dataUrl.split(',');
  const mime = (head.match(/:(.*?);/) || [])[1] || 'image/png';
  const bin = atob(b64); const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  return new Blob([arr], { type: mime });
}
function imgDim(dataUrl) {
  return new Promise((res) => { const im = new Image(); im.onload = () => res({ w: im.naturalWidth, h: im.naturalHeight }); im.onerror = () => res({ w: 1, h: 1 }); im.src = dataUrl; });
}
function typedSignatureDataUrl(text) {
  const canvas = document.createElement('canvas');
  canvas.width = 900; canvas.height = 300;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#111';
  ctx.font = 'italic 120px "Segoe Script","Snell Roundhand",cursive';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(text, canvas.width / 2, canvas.height / 2);
  return canvas.toDataURL('image/png');
}
