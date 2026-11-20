// Projeler — uzun metin seslendirme (kitap bölümü, makale...)
import { api, watchJob, fmtDate } from "/js/api.js";
import { createVoicePicker } from "/js/components/voicepicker.js";
import { openModal } from "/js/components/modal.js";
import { toast } from "/js/components/toast.js";

export async function renderProjects(page) {
  page.innerHTML = `
    <div class="page-header row between">
      <div>
        <h1>Projeler</h1>
        <p>Uzun metinleri bölüm bölüm seslendirin; tek dosya olarak dışa aktarın.</p>
      </div>
      <button class="btn primary" id="new-project">+ Yeni Proje</button>
    </div>
    <div id="project-list"></div>
    <div id="project-detail"></div>
  `;

  page.querySelector("#new-project").addEventListener("click", () => newProjectModal(refresh));
  const listEl = page.querySelector("#project-list");
  const detailEl = page.querySelector("#project-detail");

  async function refresh() {
    const { projects } = await api("/api/projects");
    listEl.innerHTML = "";
    if (!projects.length) {
      listEl.innerHTML = `<div class="card" style="text-align:center;color:var(--muted)">
        Henüz proje yok. Uzun bir metni (500 bin karaktere kadar) seslendirmek için
        "+ Yeni Proje" ile başlayın.</div>`;
      return;
    }
    for (const p of projects) {
      const item = document.createElement("div");
      item.className = "list-item";
      const statusTr = { draft: "taslak", running: "çalışıyor", done: "tamam", error: "hata" }[p.status] || p.status;
      const badgeCls = { done: "done", running: "running", error: "error" }[p.status] || "";
      item.innerHTML = `
        <div class="item-text">
          <div class="item-title">${escapeHtml(p.title)}</div>
          <div class="item-sub">${p.done_chunks}/${p.chunk_count} bölüm · ${fmtDate(p.created_at)}</div>
        </div>
        <span class="badge ${badgeCls}">${statusTr}</span>
        <button class="btn small" data-act="open">Aç</button>
        <button class="btn small danger" data-act="del">🗑</button>`;
      item.querySelector('[data-act="open"]').addEventListener("click", () => showDetail(p.id));
      item.querySelector('[data-act="del"]').addEventListener("click", async () => {
        if (confirm(`"${p.title}" projesi silinsin mi?`)) {
          await api(`/api/projects/${p.id}`, { method: "DELETE" });
          detailEl.innerHTML = "";
          refresh();
        }
      });
      listEl.appendChild(item);
    }
  }

  async function showDetail(projectId) {
    const p = await api(`/api/projects/${projectId}`);
    detailEl.innerHTML = "";
    const card = document.createElement("div");
    card.className = "card";
    const allDone = p.done_chunks === p.chunk_count;
    card.innerHTML = `
      <div class="row between" style="margin-bottom:12px">
        <h2>${escapeHtml(p.title)}</h2>
        <div class="row" style="gap:8px">
          <button class="btn primary small" id="p-start"
            ${p.status === "running" ? "disabled" : ""}>
            ${allDone ? "↻ Yeniden sentezle" : "▶ Sentezle"}
          </button>
          <a class="btn success small ${allDone ? "" : "disabled"}"
             href="/api/projects/${p.id}/export?format=wav" ${allDone ? "" : 'style="pointer-events:none;opacity:.4"'}>WAV indir</a>
          <a class="btn success small"
             href="/api/projects/${p.id}/export?format=mp3" ${allDone ? "" : 'style="pointer-events:none;opacity:.4"'}>MP3 indir</a>
        </div>
      </div>
      <div id="p-progress" style="display:none;margin-bottom:12px">
        <div class="progress"><div class="fill"></div></div>
        <div class="progress-label"></div>
      </div>
      <div class="card" style="padding:6px 4px;margin:0" id="chunk-list"></div>`;

    const chunkList = card.querySelector("#chunk-list");
    // Kitap boyu projelerde binlerce bölüm olabilir → listeyi sınırla
    const MAX_ROWS = 300;
    const shown = p.chunks.slice(0, MAX_ROWS);
    if (p.chunks.length > MAX_ROWS) {
      const note = document.createElement("div");
      note.className = "chunk-row";
      note.style.color = "var(--muted)";
      note.textContent =
        `İlk ${MAX_ROWS} bölüm gösteriliyor (toplam ${p.chunks.length}); ` +
        `ilerleme çubuğu tümünü kapsar.`;
      chunkList.appendChild(note);
    }
    for (const c of shown) {
      const row = document.createElement("div");
      row.className = "chunk-row";
      row.innerHTML = `
        <div class="chunk-dot ${c.status}"></div>
        <div class="grow" style="min-width:0">
          <div class="chunk-text"
               style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis"></div>
        </div>
        <button class="btn small ghost" title="Bu bölümü yeniden üret">↻</button>`;
      // Kullanıcı metni DOM özellikleriyle atanır (öznitelik XSS'ine kapalı)
      const textDiv = row.querySelector(".chunk-text");
      textDiv.textContent = `${c.idx + 1}. ${c.text}`;
      textDiv.title = c.text;
      row.querySelector("button").addEventListener("click", async () => {
        const { job_id } = await api(`/api/projects/${p.id}/chunks/${c.idx}/regenerate`, { method: "POST" });
        toast(`Bölüm ${c.idx + 1} kuyruğa alındı`);
        try { await watchJob(job_id); } catch { /* hata bildirimi watchJob'da */ }
        showDetail(p.id);
      });
      chunkList.appendChild(row);
    }

    card.querySelector("#p-start").addEventListener("click", async () => {
      const { job_id } = await api(`/api/projects/${p.id}/start`, { method: "POST" });
      const prog = card.querySelector("#p-progress");
      const fill = prog.querySelector(".fill");
      const label = prog.querySelector(".progress-label");
      prog.style.display = "block";
      card.querySelector("#p-start").disabled = true;
      try {
        await watchJob(job_id, (j) => {
          fill.style.width = `${j.progress * 100}%`;
          label.textContent = j.message || "";
        });
        toast("Proje sentezlendi 🎉");
      } catch (e) {
        toast(e.message || "Sentez hatası", "error");
      }
      showDetail(p.id);
      refresh();
    });

    detailEl.appendChild(card);
  }

  await refresh();
}

function newProjectModal(refresh) {
  const content = document.createElement("div");
  content.innerHTML = `
    <div class="col" style="gap:6px;margin-bottom:12px">
      <label class="field-label">Proje adı</label>
      <input type="text" id="p-title" placeholder="Örn: Kitap 1. Bölüm">
    </div>
    <div class="dropzone" id="p-file" style="margin-bottom:12px;padding:18px">
      📄 PDF / Word / TXT dosyası yükleyin (kitap boyu desteklenir)
      <input type="file" accept=".pdf,.docx,.txt,.md" style="display:none">
    </div>
    <div id="p-file-info" style="font-size:12.5px;color:var(--accent-2);margin-bottom:10px"></div>
    <div class="col" style="gap:6px;margin-bottom:12px">
      <label class="field-label">Metin <span id="p-chars" style="text-transform:none;font-weight:400"></span></label>
      <textarea id="p-text" rows="10" placeholder="...veya uzun metni buraya yapıştırın. Paragraf araları doğal duraklamalara dönüşür."></textarea>
    </div>
    <div class="row" style="margin-bottom:14px">
      <div class="col grow">
        <label class="field-label">Ses</label>
        <div id="p-voice"></div>
      </div>
      <div class="col">
        <label class="field-label">Motor</label>
        <select id="p-engine"></select>
      </div>
      <div class="col">
        <label class="field-label">Normalizasyon</label>
        <select id="p-norm"><option value="1" selected>Açık</option><option value="0">Kapalı</option></select>
      </div>
      <div class="col">
        <label class="field-label" title="Titiz mod her bölümü Whisper'la denetler ve belirgin biçimde daha yavaştır">Üretim modu</label>
        <select id="p-verify">
          <option value="0" selected>Hızlı (önerilen)</option>
          <option value="1">Titiz (çok yavaş)</option>
        </select>
      </div>
    </div>
    <div class="row" style="justify-content:flex-end">
      <button class="btn primary" id="p-create">Projeyi Oluştur</button>
    </div>`;

  const { close } = openModal(content, { title: "Yeni Proje" });

  // Dosya yükleme: PDF/DOCX/TXT → metin çıkar, alana doldur
  const fileDrop = content.querySelector("#p-file");
  const fileInput = fileDrop.querySelector("input");
  const fileInfo = content.querySelector("#p-file-info");
  const textArea = content.querySelector("#p-text");
  const charsEl = content.querySelector("#p-chars");

  function updateChars() {
    const n = textArea.value.length;
    charsEl.textContent = n ? `— ${n.toLocaleString("tr-TR")} karakter` : "";
  }
  textArea.addEventListener("input", updateChars);

  async function handleFile(f) {
    fileInfo.textContent = `"${f.name}" işleniyor...`;
    try {
      const fd = new FormData();
      fd.append("file", f);
      const res = await apiForm("/api/projects/extract", fd);
      textArea.value = res.text;
      updateChars();
      fileInfo.textContent =
        `✓ ${res.filename} — ${res.chars.toLocaleString("tr-TR")} karakter çıkarıldı (düzenleyebilirsiniz)`;
      const titleEl = content.querySelector("#p-title");
      if (!titleEl.value.trim())
        titleEl.value = f.name.replace(/\.[^.]+$/, "");
    } catch {
      fileInfo.textContent = "";
    }
  }
  fileDrop.addEventListener("click", () => fileInput.click());
  fileDrop.addEventListener("dragover", (e) => { e.preventDefault(); fileDrop.classList.add("drag"); });
  fileDrop.addEventListener("dragleave", () => fileDrop.classList.remove("drag"));
  fileDrop.addEventListener("drop", (e) => {
    e.preventDefault();
    fileDrop.classList.remove("drag");
    if (e.dataTransfer.files[0]) handleFile(e.dataTransfer.files[0]);
  });
  fileInput.addEventListener("change", () => {
    if (fileInput.files[0]) handleFile(fileInput.files[0]);
  });

  // Motor menüsü: sunucu varsayılanıyla doldur
  api("/api/engines").then((info) => {
    const sel = content.querySelector("#p-engine");
    for (const [key, e] of Object.entries(info.engines)) {
      if (!e.available) continue;
      const opt = document.createElement("option");
      opt.value = key;
      opt.textContent = e.label;
      sel.appendChild(opt);
    }
    sel.value = info.default;
  });

  createVoicePicker().then((picker) => {
    picker.style.width = "100%";
    content.querySelector("#p-voice").appendChild(picker);
    const createBtn = content.querySelector("#p-create");
    createBtn.addEventListener("click", async () => {
      const text = content.querySelector("#p-text").value.trim();
      if (!text) { toast("Metin girin", "error"); return; }
      createBtn.disabled = true;  // çift tıklama = çift proje olmasın
      try {
        const project = await api("/api/projects", {
          json: {
            title: content.querySelector("#p-title").value,
            text,
            voice_id: picker.value || null,
            engine: content.querySelector("#p-engine").value || null,
            normalize: content.querySelector("#p-norm").value === "1",
            verify: content.querySelector("#p-verify").value === "1",
          },
        });
        toast(`Proje oluşturuldu: ${project.chunk_count} bölüm`);
        close();
        refresh();
      } catch {
        createBtn.disabled = false;
      }
    });
  });
}

function escapeHtml(s) {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}
