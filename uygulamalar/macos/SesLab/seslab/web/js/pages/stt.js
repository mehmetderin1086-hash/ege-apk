// Deşifre (STT) — kelime zaman damgalı çözümleme + exportlar
import { apiForm, api, watchJob } from "/js/api.js";
import { createRecorder } from "/js/components/recorder.js";
import { createPlayer } from "/js/components/player.js";
import { toast } from "/js/components/toast.js";

export async function renderSTT(page) {
  page.innerHTML = `
    <div class="page-header">
      <h1>Deşifre</h1>
      <p>Ses kayıtlarını kelime zaman damgalı Türkçe metne dönüştürün (Whisper large-v3-turbo).</p>
    </div>
    <div class="card">
      <div class="dropzone" id="stt-drop">
        Ses / video dosyası seçin veya sürükleyin (wav, mp3, m4a, mp4, webm...)
        <input type="file" accept="audio/*,video/*" style="display:none">
      </div>
      <div style="margin:14px 0 4px">
        <label class="field-label" style="display:block;margin-bottom:8px">veya mikrofonla kaydedin</label>
        <div id="stt-rec"></div>
      </div>
      <div class="row" style="margin-top:12px">
        <div class="col">
          <label class="field-label">Dil</label>
          <select id="stt-lang">
            <option value="tr" selected>Türkçe</option>
            <option value="">Otomatik algıla</option>
            <option value="en">İngilizce</option>
            <option value="de">Almanca</option>
            <option value="fr">Fransızca</option>
            <option value="ar">Arapça</option>
          </select>
        </div>
      </div>
    </div>
    <div id="stt-progress" style="display:none">
      <div class="progress"><div class="fill"></div></div>
      <div class="progress-label">Çözümleniyor...</div>
    </div>
    <div id="stt-result"></div>
  `;

  const drop = page.querySelector("#stt-drop");
  const fileInput = drop.querySelector("input");
  drop.addEventListener("click", () => fileInput.click());
  drop.addEventListener("dragover", (e) => { e.preventDefault(); drop.classList.add("drag"); });
  drop.addEventListener("dragleave", () => drop.classList.remove("drag"));
  drop.addEventListener("drop", (e) => {
    e.preventDefault();
    drop.classList.remove("drag");
    if (e.dataTransfer.files[0]) transcribe(e.dataTransfer.files[0]);
  });
  fileInput.addEventListener("change", () => {
    if (fileInput.files[0]) transcribe(fileInput.files[0]);
  });

  page.querySelector("#stt-rec").appendChild(
    createRecorder({ maxSeconds: 600, onComplete: (blob) => transcribe(blob) })
  );

  const progressEl = page.querySelector("#stt-progress");
  const resultEl = page.querySelector("#stt-result");

  async function transcribe(fileOrBlob) {
    progressEl.style.display = "block";
    resultEl.innerHTML = "";
    const fd = new FormData();
    fd.append("file", fileOrBlob, fileOrBlob.name || "kayit.webm");
    fd.append("language", page.querySelector("#stt-lang").value);
    fd.append("word_timestamps", "true");
    try {
      const { job_id } = await apiForm("/api/stt", fd);
      const fill = progressEl.querySelector(".fill");
      const label = progressEl.querySelector(".progress-label");
      const final = await watchJob(job_id, (j) => {
        fill.style.width = `${Math.max(8, j.progress * 100)}%`;
        label.textContent = j.message || "Çözümleniyor... (ilk kullanımda model yüklenir)";
      });
      showResult(final.result, job_id, fileOrBlob);
    } catch (e) {
      toast(e.message || "Deşifre başarısız", "error");
    } finally {
      progressEl.style.display = "none";
    }
  }

  function showResult(result, jobId, fileOrBlob) {
    const card = document.createElement("div");
    card.className = "card";
    const words = [];
    for (const seg of result.segments) for (const w of seg.words || []) words.push(w);

    card.innerHTML = `
      <div class="row between" style="margin-bottom:12px">
        <h2>Transkript</h2>
        <div class="row" style="gap:8px">
          <a class="btn small" href="/api/stt/${jobId}/export?format=txt">TXT</a>
          <a class="btn small" href="/api/stt/${jobId}/export?format=srt">SRT</a>
          <a class="btn small" href="/api/stt/${jobId}/export?format=vtt">VTT</a>
          <a class="btn small" href="/api/stt/${jobId}/export?format=json">JSON</a>
        </div>
      </div>
      <div id="player-slot" style="margin-bottom:14px"></div>
      <div class="transcript" id="transcript"></div>`;

    // Oynatıcı (yerel blob'dan)
    const url = URL.createObjectURL(fileOrBlob);
    const player = createPlayer(url, { downloadName: "kayit.wav" });
    card.querySelector("#player-slot").appendChild(player);

    // Tıklanabilir kelimeler
    const tEl = card.querySelector("#transcript");
    if (words.length) {
      for (const w of words) {
        const span = document.createElement("span");
        span.className = "word";
        span.textContent = w.word;
        span.title = `${w.start.toFixed(2)} sn`;
        span.addEventListener("click", () => player.seekTo(w.start));
        tEl.appendChild(span);
      }
      // Oynatma sırasında aktif kelimeyi vurgula
      player.audio.addEventListener("timeupdate", () => {
        const t = player.audio.currentTime;
        tEl.querySelectorAll(".word").forEach((el, i) => {
          const w = words[i];
          el.classList.toggle("active", w && t >= w.start && t <= w.end);
        });
      });
    } else {
      tEl.textContent = result.text;
    }
    resultEl.innerHTML = "";
    resultEl.appendChild(card);
  }
}
