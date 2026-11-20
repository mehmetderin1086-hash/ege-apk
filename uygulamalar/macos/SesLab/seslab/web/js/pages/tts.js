// Konuşturucu (TTS stüdyosu)
import { api, fmtDuration } from "/js/api.js";
import { createPlayer } from "/js/components/player.js";
import { createVoicePicker } from "/js/components/voicepicker.js";
import { openModal } from "/js/components/modal.js";
import { toast } from "/js/components/toast.js";

const SLIDERS = [
  { key: "exaggeration", label: "Abartı (duygu)", min: 0, max: 1.5, step: 0.05, def: 0.5,
    hint: "Yüksek değer daha duygusal, coşkulu okuma" },
  { key: "cfg_weight", label: "CFG / sadakat", min: 0, max: 1, step: 0.05, def: 0.5,
    hint: "Düşük değer klon sesin aksanını azaltır" },
  { key: "temperature", label: "Çeşitlilik", min: 0.05, max: 1.5, step: 0.05, def: 0.8,
    hint: "Yüksek değer her üretimde daha farklı tonlama" },
  { key: "speed", label: "Hız", min: 0.5, max: 2, step: 0.05, def: 1.0,
    hint: "1.0 = doğal ve canlı tempo (varsayılan) · düşük değerler daha ağır okur" },
];

export async function renderTTS(page) {
  page.innerHTML = `
    <section class="tts-hero">
      <div>
        <div class="eyebrow">YAPAY ZEKA SES STÜDYOSU</div>
        <h1>Metninize doğal bir ses verin.</h1>
        <p>Uzunluk sınırı olmadan yazın veya yapıştırın; SesLab metni doğal duraklara ayırıp tek akışta seslendirir.</p>
      </div>
      <div class="hero-badges" aria-label="Konuşturucu özellikleri">
        <span><i class="status-dot"></i>Sınırsız metin</span>
        <span>24 kHz ses</span>
        <span>Akıllı Türkçe</span>
      </div>
    </section>

    <div class="tts-workspace">
      <section class="studio-card editor-card">
        <div class="card-heading">
          <div>
            <span class="section-kicker">01 · METİN</span>
            <h2>Seslendirilecek içerik</h2>
          </div>
          <button class="btn secondary small" id="norm-preview">Normalizasyonu gör</button>
        </div>
        <textarea id="tts-text" rows="11"
          aria-label="Seslendirilecek metin"
          placeholder="Metninizi buraya yazın veya yapıştırın…\n\nÖrnek: Akşamın sessizliğinde yağmur cama usulca vuruyordu. O ise uzun zamandır beklediği haberi nihayet almıştı."></textarea>
        <div class="editor-footer">
          <div class="text-metrics">
            <strong id="char-count">0 karakter</strong>
            <span id="chunk-estimate">Yazmaya başladığınızda tahmini süre burada görünür.</span>
          </div>
          <span class="autosplit-note">Metin otomatik bölünür</span>
        </div>
        <div id="text-ending-warning" class="input-warning" hidden>
          Metnin sonu yarım bir cümle gibi görünüyor. Son sözcüğü ve noktalama işaretini kontrol edin.
        </div>
      </section>

      <section class="studio-card controls-card">
        <div class="card-heading">
          <div>
            <span class="section-kicker">02 · SES TASARIMI</span>
            <h2>Ses ve okuma ayarları</h2>
          </div>
          <span class="ready-pill"><i class="status-dot"></i>Hazır</span>
        </div>

        <div class="settings-grid">
          <div class="setting-field setting-voice">
            <label class="field-label" for="tts-voice">Ses</label>
            <div id="voice-slot"></div>
          </div>
          <div class="setting-field">
            <label class="field-label" for="tts-engine">Motor</label>
            <select id="tts-engine"></select>
          </div>
          <div class="setting-field">
            <label class="field-label" for="tts-lang">Dil</label>
            <select id="tts-lang"></select>
          </div>
          <div class="setting-field">
            <label class="field-label" for="tts-norm">Metin işleme</label>
            <select id="tts-norm">
              <option value="1" selected>Akıllı · Açık</option>
              <option value="0">Ham metin · Kapalı</option>
            </select>
          </div>
          <div class="setting-field">
            <label class="field-label" for="tts-quality">Üretim modu</label>
            <select id="tts-quality">
              <option value="fast" selected>Hızlı · Önerilen</option>
              <option value="strict">Titiz · Çok yavaş</option>
            </select>
          </div>
        </div>

        <div id="engine-notice" class="engine-notice">
          <span class="notice-icon">i</span>
          <div><b id="xtts-model-title">XTTS-v2 · Seçili ses modeli</b><br>
          CPML lisanslıdır ve yalnızca ticari olmayan kişisel kullanım içindir.
          Bu motorda duygu, CFG ve çeşitlilik ayarları model tarafından yönetilir.</div>
        </div>

        <div class="slider-group" id="sliders"></div>

        <div class="generate-bar">
          <div class="generation-state">
            <span id="tts-status">Metin ve sesi seçin, ardından üretimi başlatın.</span>
            <small id="quality-hint">Hızlı mod: XTTS tek geçiş, parça başına Whisper denetimi yok.</small>
          </div>
          <button class="btn primary generate-btn" id="tts-go">
            <span class="mic-mark">●</span>
            <span>Seslendirmeyi başlat</span>
          </button>
        </div>
      </section>
    </div>

    <section id="tts-result" class="tts-result" aria-live="polite"></section>
  `;

  // Ses seçici
  const voicePicker = await createVoicePicker();
  voicePicker.id = "tts-voice";
  voicePicker.style.width = "100%";
  page.querySelector("#voice-slot").appendChild(voicePicker);

  // Bilgi satırı sabit bir ses adı göstermesin; seçili checkpoint'i yansıtsın.
  const xttsModelTitle = page.querySelector("#xtts-model-title");
  function updateXttsModelTitle() {
    const selected = voicePicker.options[voicePicker.selectedIndex];
    const voiceName = selected?.textContent?.replace(/^👤\s*/, "").trim() || "Seçili ses";
    xttsModelTitle.textContent = `XTTS-v2 · ${voiceName} modeli`;
  }
  voicePicker.addEventListener("change", updateXttsModelTitle);
  updateXttsModelTitle();

  // Dil listesi
  const langSelect = page.querySelector("#tts-lang");
  const { languages } = await api("/api/languages");
  for (const [code, name] of Object.entries(languages)) {
    const opt = document.createElement("option");
    opt.value = code;
    opt.textContent = name;
    langSelect.appendChild(opt);
  }
  langSelect.value = "tr";

  // Kaydırıcılar
  const slidersEl = page.querySelector("#sliders");
  const sliderInputs = {};
  for (const s of SLIDERS) {
    const field = document.createElement("div");
    field.className = "slider-field";
    field.innerHTML = `
      <div class="slider-head"><span>${s.label}</span><span class="val">${s.def}</span></div>
      <input type="range" min="${s.min}" max="${s.max}" step="${s.step}" value="${s.def}">
      <div class="hint">${s.hint}</div>`;
    const input = field.querySelector("input");
    const val = field.querySelector(".val");
    input.addEventListener("input", () => { val.textContent = input.value; });
    sliderInputs[s.key] = input;
    slidersEl.appendChild(field);
  }

  const textEl = page.querySelector("#tts-text");
  const charCount = page.querySelector("#char-count");
  const chunkEstimate = page.querySelector("#chunk-estimate");
  const endingWarning = page.querySelector("#text-ending-warning");
  const hasCompleteEnding = (text) => text.length < 120 || /[.!?…:;\)\]"'»”’]$/.test(text.trim());
  textEl.addEventListener("input", () => {
    const length = textEl.value.length;
    const chunks = Math.max(1, Math.ceil(length / 210));
    const minutes = length / 780;
    charCount.textContent = `${length.toLocaleString("tr-TR")} karakter`;
    chunkEstimate.textContent = length
      ? `Yaklaşık ${chunks.toLocaleString("tr-TR")} ses parçası · ${formatEstimate(minutes)}`
      : "Yazmaya başladığınızda tahmini süre burada görünür.";
    endingWarning.hidden = !length || hasCompleteEnding(textEl.value);
  });

  // Motor seçimi: sunucu varsayılanını oku (kullanıcı tercihi: XTTS Türkçesi),
  // XTTS'te lisans uyarısı göster, uygulanmayan ayarları soluklaştır
  const engineSelect = page.querySelector("#tts-engine");
  const engineNotice = page.querySelector("#engine-notice");
  const qualitySelect = page.querySelector("#tts-quality");
  const qualityHint = page.querySelector("#quality-hint");

  qualitySelect.addEventListener("change", () => {
    qualityHint.textContent = qualitySelect.value === "strict"
      ? "Titiz mod her parçayı Whisper ile denetler; süre birkaç kat uzayabilir."
      : "Hızlı mod: XTTS tek geçiş, parça başına Whisper denetimi yok.";
  });

  function applyEngineState() {
    const isXtts = engineSelect.value === "xtts";
    engineNotice.hidden = !isXtts;
    for (const key of ["exaggeration", "cfg_weight", "temperature"]) {
      sliderInputs[key].disabled = isXtts;
      sliderInputs[key].closest(".slider-field").style.opacity = isXtts ? "0.4" : "1";
    }
  }
  engineSelect.addEventListener("change", applyEngineState);

  const engineInfo = await api("/api/engines");
  for (const [key, e] of Object.entries(engineInfo.engines)) {
    if (!e.available) continue;
    const opt = document.createElement("option");
    opt.value = key;
    opt.textContent = e.label;
    engineSelect.appendChild(opt);
  }
  engineSelect.value = engineInfo.default;
  applyEngineState();

  // Hız kaydırıcısı sunucu varsayılanıyla başlar (insan temposu)
  if (engineInfo.default_speed) {
    sliderInputs.speed.value = engineInfo.default_speed;
    sliderInputs.speed.dispatchEvent(new Event("input"));
  }

  // Normalizasyon önizleme
  page.querySelector("#norm-preview").addEventListener("click", async () => {
    const text = textEl.value.trim();
    if (!text) { toast("Önce metin girin", "error"); return; }
    const res = await api("/api/normalize/preview", { json: { text } });
    const content = document.createElement("div");
    content.innerHTML = `
      <label class="field-label">Özgün metin</label>
      <div class="norm-diff" style="margin:6px 0 14px">${escapeHtml(res.original)}</div>
      <label class="field-label">TTS'e gidecek metin (${res.applied_rules.length} kural uygulandı)</label>
      <div class="norm-diff" style="margin:6px 0 14px;border-color:var(--accent-2)">${escapeHtml(res.normalized)}</div>
      <label class="field-label">${res.chunks.length} parçaya bölünecek</label>`;
    openModal(content, { title: "Normalizasyon Önizlemesi" });
  });

  // Seslendir
  const goBtn = page.querySelector("#tts-go");
  const statusEl = page.querySelector("#tts-status");
  const resultEl = page.querySelector("#tts-result");

  goBtn.addEventListener("click", async () => {
    const text = textEl.value.trim();
    if (!text) { toast("Seslendirilecek metin girin", "error"); return; }
    if (!hasCompleteEnding(text)) {
      endingWarning.hidden = false;
      statusEl.textContent = "Metnin sonu eksik görünüyor; seslendirmeden önce son cümleyi tamamlayın.";
      toast("Metnin son cümlesi tamamlanmamış görünüyor", "error");
      textEl.focus();
      return;
    }
    goBtn.disabled = true;
    goBtn.classList.add("is-working");
    statusEl.textContent = "Ses hazırlanıyor… İlk üretimde model yüklenmesi yaklaşık bir dakika sürebilir.";
    try {
      const res = await api("/api/tts", {
        json: {
          text,
          voice_id: voicePicker.value || null,
          language: langSelect.value,
          engine: engineSelect.value,
          normalize: page.querySelector("#tts-norm").value === "1",
          verify: qualitySelect.value === "strict",
          exaggeration: +sliderInputs.exaggeration.value,
          cfg_weight: +sliderInputs.cfg_weight.value,
          temperature: +sliderInputs.temperature.value,
          speed: +sliderInputs.speed.value,
        },
      });
      resultEl.innerHTML = "";
      const player = createPlayer(res.url, {
        downloadName: "seslab.wav",
        mp3Url: `${res.url}?format=mp3`,
      });
      resultEl.appendChild(player);
      resultEl.classList.add("has-result");
      statusEl.textContent = `Tamamlandı — ${fmtDuration(res.duration_s)}`;
      player.audio.play().catch(() => {});
    } catch {
      statusEl.textContent = "";
    } finally {
      goBtn.disabled = false;
      goBtn.classList.remove("is-working");
    }
  });
}

function formatEstimate(minutes) {
  if (minutes < 1) return `tahmini ${Math.max(1, Math.round(minutes * 60))} sn ses`;
  if (minutes < 60) return `tahmini ${Math.round(minutes)} dk ses`;
  const hours = Math.floor(minutes / 60);
  const mins = Math.round(minutes % 60);
  return `tahmini ${hours} sa ${mins} dk ses`;
}

function escapeHtml(s) {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}
