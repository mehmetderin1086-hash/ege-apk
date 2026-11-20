// Sayfa düzenleyici — sürükle-bırak sıralama, döndürme, silme.
import { icon } from './icons.js';
import { el, toast, showOverlay, hideOverlay, updateOverlayProgress, download, registerWindowDrop } from './ui.js';
import * as api from './api.js';

export async function openOrganizer(tool) {
  const content = document.getElementById('content');
  content.innerHTML = '';
  const container = el('div', { class: 'container' });
  container.append(el('div', { class: 'tool-header' }, [
    el('button', { class: 'icon-btn back', onclick: () => import('./app.js').then(m => m.init()), html: icon('back', 'ic', 20) }),
    el('div', { class: `tool-ic ${tool.color}`, html: icon(tool.icon, 'ic', 26) }),
    el('div', {}, [el('h1', { text: tool.title }), el('p', { text: tool.desc })]),
  ]));

  // Yükleme aşaması
  const stage = el('div');
  container.append(stage);
  content.append(container);

  const input = el('input', { type: 'file', class: 'hidden', accept: 'application/pdf' });
  const dz = el('div', { class: 'dropzone', onclick: () => input.click() }, [
    el('div', { class: 'dz-ic', html: icon('uploadcloud', 'ic', 62) }),
    el('h3', { text: 'Düzenlenecek PDF’i sürükleyin' }),
    el('p', { text: 'veya bilgisayardan seçin · PDF' }),
    el('button', { class: 'btn btn-primary', html: icon('upload', 'ic', 18) + 'Dosya Seç' }),
    input,
  ]);
  ;['dragover', 'dragenter'].forEach(ev => dz.addEventListener(ev, e => { e.preventDefault(); dz.classList.add('drag'); }));
  ;['dragleave', 'drop'].forEach(ev => dz.addEventListener(ev, e => { e.preventDefault(); dz.classList.remove('drag'); }));
  dz.addEventListener('drop', e => { const f = e.dataTransfer.files[0]; if (f) load(f); });
  input.addEventListener('change', () => { if (input.files[0]) load(input.files[0]); });
  registerWindowDrop(dz, (files) => { if (files[0]) load(files[0]); });
  stage.append(dz);

  async function load(file) {
    showOverlay('Yükleniyor…', file.name, { progress: true });
    try {
      const res = await api.upload([file], updateOverlayProgress);
      const info = res.files[0];
      if (info.kind !== 'pdf') { toast('Lütfen bir PDF dosyası seçin.', 'error'); hideOverlay(); return; }
      hideOverlay();
      renderGrid(info);
    } catch (e) { hideOverlay(); toast(e.message, 'error'); }
  }

  function renderGrid(fileInfo) {
    const pageCount = fileInfo.pages || 0;
    // durum: her sayfa {orig, rotation, deleted}
    let pages = Array.from({ length: pageCount }, (_, i) => ({ orig: i, rotation: 0, deleted: false }));

    stage.innerHTML = '';
    const bar = el('div', { style: 'display:flex;align-items:center;gap:12px;margin-bottom:18px;flex-wrap:wrap' }, [
      el('div', { style: 'font-weight:650;color:var(--text-soft)', html: icon('info', 'ic', 16) + ` <span id="pgcount">${pageCount}</span> sayfa · sürükleyerek sıralayın` }),
      el('div', { style: 'flex:1' }),
      el('button', { class: 'btn btn-ghost btn-sm', html: icon('rotate', 'ic', 16) + 'Tümünü döndür', onclick: () => { pages.forEach(p => { if (!p.deleted) p.rotation = (p.rotation + 90) % 360; }); draw(); } }),
      el('button', { class: 'btn btn-primary', id: 'applyBtn', html: icon('check', 'ic', 18) + 'Uygula ve İndir' }),
    ]);
    const grid = el('div', { class: 'organizer-grid' });
    stage.append(bar, grid);

    let dragIdx = null;

    function draw() {
      grid.innerHTML = '';
      const visible = pages.filter(p => !p.deleted);
      document.getElementById('pgcount').textContent = visible.length;
      pages.forEach((p, idx) => {
        const cell = el('div', { class: 'org-page' + (p.deleted ? ' deleted' : ''), draggable: p.deleted ? null : 'true', 'data-idx': idx });
        const num = p.deleted ? '✕' : (visible.indexOf(p) + 1);
        cell.append(el('span', { class: 'org-num', text: num }));
        const img = el('img', { src: api.renderUrl(fileInfo.file_id, p.orig, 'thumb'), alt: `Sayfa ${p.orig + 1}` });
        img.style.transform = `rotate(${p.rotation}deg)`;
        cell.append(img);
        const tools = el('div', { class: 'org-tools' }, [
          el('button', { title: 'Sola döndür', onclick: (e) => { e.stopPropagation(); p.rotation = (p.rotation + 270) % 360; draw(); }, html: icon('undo', 'ic', 15) }),
          el('button', { title: 'Sağa döndür', onclick: (e) => { e.stopPropagation(); p.rotation = (p.rotation + 90) % 360; draw(); }, html: icon('rotate', 'ic', 15) }),
          el('button', { class: 'danger', title: p.deleted ? 'Geri al' : 'Sil', onclick: (e) => { e.stopPropagation(); p.deleted = !p.deleted; draw(); }, html: icon(p.deleted ? 'plus' : 'trash', 'ic', 15) }),
        ]);
        cell.append(tools);
        grid.append(cell);
      });
      attachReorder();
    }

    // Sürükle-bırak yeniden sıralama (dizi indeksleriyle çalışır)
    function attachReorder() {
      grid.querySelectorAll('.org-page').forEach(cell => {
        cell.ondragstart = () => { dragIdx = +cell.dataset.idx; cell.classList.add('dragging'); };
        cell.ondragend = () => { cell.classList.remove('dragging'); grid.querySelectorAll('.drop-target').forEach(n => n.classList.remove('drop-target')); };
        cell.ondragover = (e) => { e.preventDefault(); cell.classList.add('drop-target'); };
        cell.ondragleave = () => cell.classList.remove('drop-target');
        cell.ondrop = (e) => {
          e.preventDefault();
          const to = +cell.dataset.idx;
          if (dragIdx === null || dragIdx === to) return;
          const [moved] = pages.splice(dragIdx, 1);
          pages.splice(to, 0, moved);
          dragIdx = null;
          draw();
        };
      });
    }

    document.getElementById('applyBtn').addEventListener('click', async () => {
      const kept = pages.filter(p => !p.deleted).map(p => ({ index: p.orig, rotation: p.rotation }));
      if (kept.length === 0) { toast('En az bir sayfa kalmalı.', 'warn'); return; }
      showOverlay('Uygulanıyor…');
      try {
        const res = await api.post('/api/organize/compose', { file_id: fileInfo.file_id, pages: kept });
        hideOverlay();
        const o = res.outputs[0];
        toast(res.message, 'success');
        download(o.download_url, o.name);
      } catch (e) { hideOverlay(); toast(e.message, 'error'); }
    });

    draw();
  }
}
