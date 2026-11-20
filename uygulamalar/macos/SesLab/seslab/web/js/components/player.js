// Dalga formlu ses çalar — <audio> + canvas tepe çizimi
const audioCtx = new (window.AudioContext || window.webkitAudioContext)();

// Aktif çalarlar — sayfa geçişinde hepsini durdurmak için (app.js çağırır)
const activePlayers = new Set();
export function stopAllPlayers() {
  for (const audio of activePlayers) {
    try { audio.pause(); } catch { /* yoksay */ }
  }
  activePlayers.clear();
}

function drawPeaks(canvas, peaks, progress = 0) {
  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);

  const barW = 2, gap = 1;
  const n = Math.floor(w / (barW + gap));
  const playedBars = Math.floor(n * progress);
  for (let i = 0; i < n; i++) {
    const p = peaks[Math.floor((i / n) * peaks.length)] || 0.02;
    const bh = Math.max(2, p * h * 0.92);
    ctx.fillStyle = i <= playedBars && progress > 0 ? "#7c5cff" : "#3a4150";
    ctx.fillRect(i * (barW + gap), (h - bh) / 2, barW, bh);
  }
}

async function computePeaks(url) {
  const res = await fetch(url);
  const buf = await res.arrayBuffer();
  const audio = await audioCtx.decodeAudioData(buf);
  const data = audio.getChannelData(0);
  const bins = 400;
  const step = Math.floor(data.length / bins) || 1;
  const peaks = new Float32Array(bins);
  for (let i = 0; i < bins; i++) {
    let max = 0;
    for (let j = i * step; j < (i + 1) * step && j < data.length; j++) {
      const v = Math.abs(data[j]);
      if (v > max) max = v;
    }
    peaks[i] = max;
  }
  return peaks;
}

const PLAY_ICON = `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>`;
const PAUSE_ICON = `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>`;

function fmt(t) {
  if (!isFinite(t)) return "0:00";
  const m = Math.floor(t / 60), s = Math.floor(t % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

/**
 * createPlayer(url, {downloadName}) → çalar DOM öğesi.
 * el.seekTo(saniye) dışarıdan çağrılabilir (STT kelime tıklaması).
 */
export function createPlayer(url, { downloadName = "ses.wav", mp3Url = null } = {}) {
  const el = document.createElement("div");
  el.className = "player";
  el.innerHTML = `
    <canvas></canvas>
    <div class="controls">
      <button class="play-btn" title="Çal / Duraklat">${PLAY_ICON}</button>
      <span class="time">0:00 / 0:00</span>
      <div class="grow"></div>
      <select class="speed btn small" title="Oynatma hızı">
        <option value="0.75">0.75×</option>
        <option value="1" selected>1×</option>
        <option value="1.25">1.25×</option>
        <option value="1.5">1.5×</option>
        <option value="2">2×</option>
      </select>
      <a class="btn small icon dl" href="${url}" download="${downloadName}" title="WAV indir">WAV</a>
      ${mp3Url ? `<a class="btn small icon" href="${mp3Url}" download title="MP3 indir">MP3</a>` : ""}
    </div>`;

  const canvas = el.querySelector("canvas");
  const playBtn = el.querySelector(".play-btn");
  const timeEl = el.querySelector(".time");
  const speedEl = el.querySelector(".speed");
  const audio = new Audio(url);
  let peaks = new Float32Array(400).fill(0.05);

  computePeaks(url).then((p) => { peaks = p; drawPeaks(canvas, peaks); }).catch(() => {});

  function refresh() {
    const progress = audio.duration ? audio.currentTime / audio.duration : 0;
    drawPeaks(canvas, peaks, progress);
    timeEl.textContent = `${fmt(audio.currentTime)} / ${fmt(audio.duration)}`;
  }

  playBtn.addEventListener("click", () => {
    if (audio.paused) audio.play();
    else audio.pause();
  });
  audio.addEventListener("play", () => { playBtn.innerHTML = PAUSE_ICON; });
  audio.addEventListener("pause", () => { playBtn.innerHTML = PLAY_ICON; });
  audio.addEventListener("timeupdate", refresh);
  audio.addEventListener("loadedmetadata", refresh);
  audio.addEventListener("ended", () => { playBtn.innerHTML = PLAY_ICON; });
  speedEl.addEventListener("change", () => { audio.playbackRate = +speedEl.value; });

  canvas.addEventListener("click", (e) => {
    if (!audio.duration) return;
    const rect = canvas.getBoundingClientRect();
    audio.currentTime = ((e.clientX - rect.left) / rect.width) * audio.duration;
  });

  activePlayers.add(audio);
  el.seekTo = (t) => { audio.currentTime = t; audio.play(); };
  el.audio = audio;
  el.destroy = () => {
    audio.pause();
    audio.removeAttribute("src");
    activePlayers.delete(audio);
    el.remove();
  };
  return el;
}
