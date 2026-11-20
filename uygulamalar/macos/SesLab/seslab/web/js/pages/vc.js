// Ses Değiştirici (speech-to-speech)
import { apiForm, api, fmtDuration } from "/js/api.js";
import { createRecorder } from "/js/components/recorder.js";
import { createPlayer } from "/js/components/player.js";
import { createVoicePicker } from "/js/components/voicepicker.js";
import { toast } from "/js/components/toast.js";

export async function renderVC(page) {
  page.innerHTML = `
    <div class="page-header">
      <h1>Ses Değiştirici</h1>
      <p>Bir kaydın içeriğini koruyup sesini kütüphanedeki bir sese dönüştürün.</p>
    </div>
    <div class="card">
      <label class="field-label" style="display:block;margin-bottom:8px">1. Kaynak kayıt</label>
      <div class="dropzone" id="vc-drop">
        Ses dosyası seçin veya sürükleyin
        <input type="file" accept="audio/*,video/mp4,video/webm" style="display:none">
      </div>
      <div style="margin-top:12px">
        <label class="field-label" style="display:block;margin-bottom:8px">veya kaydedin</label>
        <div id="vc-rec"></div>
      </div>
      <div id="vc-selected" style="font-size:13px;color:var(--accent-2);margin-top:8px"></div>
    </div>
    <div class="card">
      <label class="field-label">2. Hedef ses (kütüphaneden)</label>
      <div id="vc-voice" style="margin-top:6px"></div>
      <p style="font-size:12.5px;color:var(--muted);margin-top:8px">
        Henüz klon ses yoksa önce <a href="#/sesler">Sesler</a> bölümünden ekleyin.
      </p>
    </div>
    <div class="row between">
      <span id="vc-status" style="font-size:13px;color:var(--muted)"></span>
      <button class="btn primary" id="vc-go" disabled style="padding:12px 28px">🔄 Dönüştür</button>
    </div>
    <div id="vc-result" style="margin-top:18px"></div>
  `;

  const picker = await createVoicePicker();
  picker.style.width = "100%";
  page.querySelector("#vc-voice").appendChild(picker);

  let blob = null;
  const goBtn = page.querySelector("#vc-go");
  const selected = page.querySelector("#vc-selected");

  function setSource(b, name) {
    blob = b;
    selected.textContent = `Kaynak hazır: ${name} (${(b.size / 1024).toFixed(0)} KB)`;
    goBtn.disabled = false;
  }

  const drop = page.querySelector("#vc-drop");
  const fileInput = drop.querySelector("input");
  drop.addEventListener("click", () => fileInput.click());
  drop.addEventListener("dragover", (e) => { e.preventDefault(); drop.classList.add("drag"); });
  drop.addEventListener("dragleave", () => drop.classList.remove("drag"));
  drop.addEventListener("drop", (e) => {
    e.preventDefault();
    drop.classList.remove("drag");
    if (e.dataTransfer.files[0]) setSource(e.dataTransfer.files[0], e.dataTransfer.files[0].name);
  });
  fileInput.addEventListener("change", () => {
    if (fileInput.files[0]) setSource(fileInput.files[0], fileInput.files[0].name);
  });
  page.querySelector("#vc-rec").appendChild(
    createRecorder({ maxSeconds: 120, onComplete: (b) => setSource(b, "mikrofon kaydı") })
  );

  const statusEl = page.querySelector("#vc-status");
  const resultEl = page.querySelector("#vc-result");

  goBtn.addEventListener("click", async () => {
    if (!blob) return;
    if (!picker.value) { toast("Hedef ses seçin (varsayılan ses değiştirici için kullanılamaz)", "error"); return; }
    goBtn.disabled = true;
    statusEl.textContent = "Dönüştürülüyor... (ilk kullanımda model yüklenir)";
    try {
      const fd = new FormData();
      fd.append("file", blob, "kaynak.webm");
      fd.append("voice_id", picker.value);
      const res = await apiForm("/api/vc", fd);
      resultEl.innerHTML = "";
      const player = createPlayer(res.url, {
        downloadName: "donusturulmus.wav",
        mp3Url: `${res.url}?format=mp3`,
      });
      resultEl.appendChild(player);
      statusEl.textContent = `Tamamlandı — ${fmtDuration(res.duration_s)}`;
      player.audio.play().catch(() => {});
    } catch {
      statusEl.textContent = "";
    } finally {
      goBtn.disabled = false;
    }
  });
}
