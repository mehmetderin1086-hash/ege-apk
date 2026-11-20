// Mikrofon kaydedici — MediaRecorder + canlı seviye göstergesi
// Chrome: audio/webm;codecs=opus — Safari: audio/mp4 (aac)

const MIC_ICON = `<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M12 14a3 3 0 0 0 3-3V5a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2z"/></svg>`;
const STOP_ICON = `<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>`;

// Aktif kaydediciler — sayfa geçişi/modal kapanışında mikrofonu serbest bırak
const activeRecorders = new Set();
export function disposeAllRecorders() {
  for (const dispose of [...activeRecorders]) dispose();
}

function pickMime() {
  const candidates = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"];
  for (const m of candidates) {
    if (window.MediaRecorder && MediaRecorder.isTypeSupported(m)) return m;
  }
  return "";
}

/**
 * createRecorder({ onComplete(blob), maxSeconds }) → DOM öğesi.
 * Kayıt bitince onComplete(blob) çağrılır.
 */
export function createRecorder({ onComplete, maxSeconds = 30 } = {}) {
  const el = document.createElement("div");
  el.className = "recorder";
  el.innerHTML = `
    <div class="row">
      <button class="rec-btn" title="Kaydı başlat">${MIC_ICON}</button>
      <div class="col grow">
        <div class="level-meter"><div class="bar"></div></div>
        <span class="rec-status" style="font-size:12.5px;color:var(--muted)">
          Kayda başlamak için mikrofona tıklayın
        </span>
      </div>
      <span class="rec-timer" style="font-family:var(--mono);font-size:14px;color:var(--muted)">0:00</span>
    </div>`;

  const btn = el.querySelector(".rec-btn");
  const bar = el.querySelector(".level-meter .bar");
  const status = el.querySelector(".rec-status");
  const timer = el.querySelector(".rec-timer");

  let recorder = null, stream = null, chunks = [], raf = 0, t0 = 0, tick = 0;
  let starting = false;

  async function start() {
    if (starting || (recorder && recorder.state === "recording")) return;
    starting = true;  // izin istemi açıkken ikinci tıklama ikinci stream açmasın
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      status.textContent = "Mikrofon izni reddedildi";
      starting = false;
      return;
    }
    starting = false;
    const mime = pickMime();
    recorder = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
    chunks = [];
    recorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
    recorder.onstop = () => {
      const blob = new Blob(chunks, { type: recorder.mimeType || "audio/webm" });
      cleanup();
      if (onComplete) onComplete(blob);
    };

    // Seviye göstergesi
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const src = ctx.createMediaStreamSource(stream);
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 512;
    src.connect(analyser);
    const buf = new Uint8Array(analyser.frequencyBinCount);
    const loop = () => {
      analyser.getByteTimeDomainData(buf);
      let peak = 0;
      for (const v of buf) peak = Math.max(peak, Math.abs(v - 128) / 128);
      bar.style.width = `${Math.min(100, peak * 160)}%`;
      raf = requestAnimationFrame(loop);
    };
    loop();

    recorder.start();
    t0 = Date.now();
    btn.classList.add("recording");
    btn.innerHTML = STOP_ICON;
    status.textContent = "Kaydediliyor... durdurmak için tıklayın";
    tick = setInterval(() => {
      const s = Math.floor((Date.now() - t0) / 1000);
      timer.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
      if (s >= maxSeconds) stop();
    }, 250);
  }

  function stop() {
    if (recorder && recorder.state !== "inactive") recorder.stop();
  }

  function cleanup() {
    cancelAnimationFrame(raf);
    clearInterval(tick);
    if (stream) stream.getTracks().forEach((t) => t.stop());
    btn.classList.remove("recording");
    btn.innerHTML = MIC_ICON;
    status.textContent = "Kayıt tamamlandı";
    bar.style.width = "0%";
  }

  btn.addEventListener("click", () => {
    if (recorder && recorder.state === "recording") stop();
    else start();
  });

  // Bileşen ortadan kalkarken (modal kapanışı / sayfa geçişi) mikrofonu bırak
  const dispose = () => {
    if (recorder && recorder.state === "recording") {
      recorder.onstop = null;  // onComplete tetiklenmesin
    }
    cleanup();
    activeRecorders.delete(dispose);
  };
  activeRecorders.add(dispose);
  el.dispose = dispose;

  return el;
}
