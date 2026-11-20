// Sesler — klon kütüphanesi
import { api, apiForm, fmtDate } from "/js/api.js";
import { createRecorder } from "/js/components/recorder.js";
import { openModal } from "/js/components/modal.js";
import { toast } from "/js/components/toast.js";

export async function renderVoices(page) {
  page.innerHTML = `
    <div class="page-header row between">
      <div>
        <h1>Sesler</h1>
        <p>Kısa bir kayıttan (~10 sn) ses klonlayın; tüm dillerde konuşturun.</p>
      </div>
      <button class="btn primary" id="new-voice">+ Yeni Ses</button>
    </div>
    <div class="voice-grid" id="voice-grid"></div>
  `;

  page.querySelector("#new-voice").addEventListener("click", () => newVoiceModal(refresh));
  const grid = page.querySelector("#voice-grid");

  async function refresh() {
    const { voices } = await api("/api/voices");
    grid.innerHTML = "";
    if (!voices.length) {
      grid.innerHTML = `<div class="card" style="grid-column:1/-1;text-align:center;color:var(--muted)">
        Henüz klonlanmış ses yok. "+ Yeni Ses" ile başlayın:<br>
        mikrofonla ~10 saniyelik temiz bir kayıt yeterli.</div>`;
      return;
    }
    for (const v of voices) grid.appendChild(voiceCard(v, refresh));
  }
  await refresh();
}

function voiceCard(v, refresh) {
  const card = document.createElement("div");
  card.className = "voice-card";
  card.innerHTML = `
    <div class="row">
      <div class="voice-avatar">${v.name.charAt(0).toUpperCase()}</div>
      <div class="grow">
        <div class="voice-name">${escapeHtml(v.name)}</div>
        <div class="voice-meta">${v.duration_s.toFixed(1)} sn örnek · ${fmtDate(v.created_at)}</div>
      </div>
    </div>
    <div class="row">
      <button class="btn small" data-act="preview">▶ Yeni önizleme</button>
      <button class="btn small ghost" data-act="ref">Kaynak kayıt</button>
      <div class="grow"></div>
      <button class="btn small ghost" data-act="rename" title="Yeniden adlandır">✏️</button>
      <button class="btn small danger" data-act="delete" title="Sil">🗑</button>
    </div>
    <audio style="display:none"></audio>`;

  const audio = card.querySelector("audio");

  card.querySelector('[data-act="preview"]').addEventListener("click", async (e) => {
    const btn = e.target;
    btn.disabled = true;
    btn.textContent = "Üretiliyor...";
    try {
      const { url } = await api(`/api/voices/${v.id}/preview`, { method: "POST" });
      audio.src = url;
      audio.play();
    } finally {
      btn.disabled = false;
      btn.textContent = "▶ Yeni önizleme";
    }
  });

  card.querySelector('[data-act="ref"]').addEventListener("click", () => {
    audio.src = `/api/voices/${v.id}/audio`;
    audio.play();
  });

  card.querySelector('[data-act="rename"]').addEventListener("click", async () => {
    const name = prompt("Yeni ad:", v.name);
    if (name && name.trim()) {
      await api(`/api/voices/${v.id}`, { method: "PATCH", json: { name } });
      refresh();
    }
  });

  card.querySelector('[data-act="delete"]').addEventListener("click", async () => {
    if (confirm(`"${v.name}" sesi silinsin mi?`)) {
      await api(`/api/voices/${v.id}`, { method: "DELETE" });
      toast("Ses silindi");
      refresh();
    }
  });

  return card;
}

function newVoiceModal(refresh) {
  const content = document.createElement("div");
  content.innerHTML = `
    <p style="font-size:13.5px;color:var(--muted);margin-bottom:14px">
      En iyi sonuç için: sessiz bir ortamda, doğal tonda, <b>en az 5 – ideali 10 saniye</b>
      konuşun. Örnek cümle: <i>"Merhaba, ben ___. Bugün hava çok güzel; biraz yürüyüş
      yapmayı ve kitap okumayı düşünüyorum. Bu kayıt, sesimin bir kopyasını çıkarmak için."</i>
    </p>
    <div class="col" style="gap:6px;margin-bottom:14px">
      <label class="field-label">Ses adı</label>
      <input type="text" id="v-name" placeholder="Örn: Benim Sesim">
    </div>
    <div class="card" style="margin-bottom:12px">
      <label class="field-label" style="display:block;margin-bottom:8px">Mikrofonla kaydet</label>
      <div id="rec-slot"></div>
    </div>
    <div class="dropzone" id="v-drop">
      veya ses dosyası seçin / sürükleyin (wav, mp3, m4a, webm...)
      <input type="file" accept="audio/*,video/mp4,video/webm" style="display:none">
    </div>
    <div id="v-selected" style="font-size:13px;color:var(--accent-2);margin-top:8px"></div>
    <div class="row" style="justify-content:flex-end;margin-top:16px">
      <button class="btn primary" id="v-save" disabled>Sesi Oluştur</button>
    </div>`;

  let blob = null;
  const saveBtn = content.querySelector("#v-save");
  const selected = content.querySelector("#v-selected");

  const recorder = createRecorder({
    maxSeconds: 30,
    onComplete(b) {
      blob = b;
      selected.textContent = `Kayıt hazır (${(b.size / 1024).toFixed(0)} KB)`;
      saveBtn.disabled = false;
    },
  });
  content.querySelector("#rec-slot").appendChild(recorder);

  // Modal hangi yoldan kapanırsa kapansın mikrofonu serbest bırak
  const { close } = openModal(content, {
    title: "Yeni Ses Klonla",
    onClose: () => recorder.dispose(),
  });

  const drop = content.querySelector("#v-drop");
  const fileInput = drop.querySelector("input");
  drop.addEventListener("click", () => fileInput.click());
  drop.addEventListener("dragover", (e) => { e.preventDefault(); drop.classList.add("drag"); });
  drop.addEventListener("dragleave", () => drop.classList.remove("drag"));
  drop.addEventListener("drop", (e) => {
    e.preventDefault();
    drop.classList.remove("drag");
    if (e.dataTransfer.files[0]) setFile(e.dataTransfer.files[0]);
  });
  fileInput.addEventListener("change", () => {
    if (fileInput.files[0]) setFile(fileInput.files[0]);
  });

  function setFile(f) {
    blob = f;
    selected.textContent = `Dosya: ${f.name} (${(f.size / 1024).toFixed(0)} KB)`;
    saveBtn.disabled = false;
  }

  saveBtn.addEventListener("click", async () => {
    const name = content.querySelector("#v-name").value.trim();
    if (!name) { toast("Ses adı girin", "error"); return; }
    if (!blob) return;
    saveBtn.disabled = true;
    saveBtn.textContent = "Oluşturuluyor...";
    try {
      const fd = new FormData();
      fd.append("name", name);
      fd.append("file", blob, "ornek.webm");
      await apiForm("/api/voices", fd);
      toast(`"${name}" sesi kütüphaneye eklendi`);
      close();
      refresh();
    } catch {
      saveBtn.disabled = false;
      saveBtn.textContent = "Sesi Oluştur";
    }
  });
}

function escapeHtml(s) {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}
