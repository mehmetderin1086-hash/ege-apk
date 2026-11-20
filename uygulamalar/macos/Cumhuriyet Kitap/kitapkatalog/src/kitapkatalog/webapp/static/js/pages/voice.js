// Sesli Kayıt: MediaRecorder canlı kayıt + analiz + kayıt onayı + toplu ses işleri.

import { api, pollJob } from "../api.js";
import { confirmBox, esc, fillForm, readForm, show, toast } from "../ui.js";
import { refreshDatalists } from "../main.js";

const $ = (id) => document.getElementById(id);
let bound = false;
let pollTimer = null;
let pollBusy = false;

let mediaRecorder = null;
let audioContext = null;
let levelRaf = null;
let chunks = [];
let recordStart = 0;
let timerInterval = null;
let pendingId = null;
let mergeInto = null;
let currentSuggestions = [];

let refieldField = null;
let refieldRecorder = null;

const err = (error) => toast(error.message || String(error), "error");

const FIELD_LABELS_TR = { title: "Başlık", author: "Yazar", publisher: "Yayınevi" };
const ORIGIN_LABELS_TR = {
  second_pass: "ikinci geçiş", alias: "sözlük", catalog: "katalog", refield: "yeniden söylendi",
};

// ── Kayıt ────────────────────────────────────────────

function pickMime() {
  const candidates = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"];
  return candidates.find((type) => MediaRecorder.isTypeSupported(type)) || "";
}

async function startRecording() {
  if (pendingId) {
    if (!(await confirmBox("Onaylanmamış önceki ses kaydı silinsin mi?"))) return;
    await discardPending(true);
  }
  let stream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch {
    toast("Mikrofona erişilemedi. Tarayıcıya mikrofon izni verin (macOS: Sistem Ayarları → Gizlilik).", "error", 6000);
    return;
  }
  chunks = [];
  const mime = pickMime();
  mediaRecorder = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
  mediaRecorder.addEventListener("dataavailable", (event) => chunks.push(event.data));
  mediaRecorder.addEventListener("stop", () => {
    stream.getTracks().forEach((track) => track.stop());
    stopLevelMeter();
    const blob = new Blob(chunks, { type: mediaRecorder.mimeType || "audio/webm" });
    analyzeBlob(blob).catch(err);
  });
  mediaRecorder.start();
  startLevelMeter(stream);
  recordStart = Date.now();
  timerInterval = setInterval(() => {
    const seconds = Math.floor((Date.now() - recordStart) / 1000);
    $("kayit-sure").textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
  }, 250);
  $("kayit-btn").classList.add("recording");
  $("kayit-btn").setAttribute("aria-label", "Kaydı durdur");
  $("ses-durum").textContent = "Kaydediliyor… bitince düğmeye tekrar basın.";
}

function stopRecording() {
  clearInterval(timerInterval);
  $("kayit-btn").classList.remove("recording");
  $("kayit-btn").setAttribute("aria-label", "Kaydı başlat");
  if (mediaRecorder && mediaRecorder.state !== "inactive") mediaRecorder.stop();
}

function startLevelMeter(stream) {
  audioContext = new AudioContext();
  const source = audioContext.createMediaStreamSource(stream);
  const analyser = audioContext.createAnalyser();
  analyser.fftSize = 512;
  source.connect(analyser);
  const data = new Uint8Array(analyser.frequencyBinCount);
  const tick = () => {
    analyser.getByteTimeDomainData(data);
    let sum = 0;
    for (const value of data) { const deviation = (value - 128) / 128; sum += deviation * deviation; }
    const rms = Math.sqrt(sum / data.length);
    $("seviye").style.width = `${Math.min(100, rms * 260)}%`;
    levelRaf = requestAnimationFrame(tick);
  };
  tick();
}

function stopLevelMeter() {
  cancelAnimationFrame(levelRaf);
  if (audioContext) { audioContext.close(); audioContext = null; }
  $("seviye").style.width = "0";
}

// ── Analiz ve kayıt ──────────────────────────────────

async function analyzeBlob(blob) {
  // Analiz sürerken yeni kayıt alınmasın: iş yuvası tekli, ikinci yükleme
  // 409 alır ve kayıt geri dönüşsüz kaybolur.
  $("kayit-btn").disabled = true;
  $("ses-durum").innerHTML = '<span class="spinner"></span> Analiz ediliyor…';
  const form = new FormData();
  const extension = blob.type.includes("mp4") ? "mp4" : "webm";
  form.append("file", blob, `kayit.${extension}`);
  try {
    await api.upload("/api/voice/analyze", form);
    const job = await pollJob("/api/voice/analyze/status", {
      onTick: (state) => { if (state?.message) $("ses-durum").innerHTML = `<span class="spinner"></span> ${esc(state.message)}`; },
    });
    if (job.status !== "succeeded") {
      $("ses-durum").textContent = "";
      toast(job.error || "Analiz başarısız", "error", 6000);
      return;
    }
    applyAnalysis(job.result);
  } catch (error) {
    $("ses-durum").textContent = "";
    err(error);
  } finally {
    $("kayit-btn").disabled = false;
  }
}

// ── Öneri çipleri (ikinci geçiş / sözlük / katalog / yeniden söyle) ──

function renderSuggestions(suggestions) {
  currentSuggestions = suggestions || [];
  const box = $("ses-oneriler");
  if (!currentSuggestions.length) {
    box.innerHTML = "";
    show(box, false);
    return;
  }
  box.innerHTML = currentSuggestions
    .map((item, index) => {
      const field = esc(FIELD_LABELS_TR[item.field_path] ?? item.field_path);
      const origin = esc(ORIGIN_LABELS_TR[item.origin] ?? item.origin);
      return `<button type="button" class="chip" data-oneri="${index}">` +
        `${field}: ${esc(item.value)} <small>${origin}</small></button>`;
    })
    .join("");
  show(box, true);
}

function addSuggestion(item) {
  renderSuggestions([...currentSuggestions, item]);
}

function applyAnalysis(result) {
  pendingId = result.pending_id;
  mergeInto = null;
  $("ses-durum").textContent = "Analiz tamam. Alanları kontrol edip kaydedin.";
  const transcript = $("ses-transkript");
  transcript.textContent = result.transcript;
  show(transcript, Boolean(result.transcript));

  fillForm($("ses-form"), { ...result.values, copy_count: result.copy_count });
  renderSuggestions(result.suggestions);
  $("ses-kaydet").disabled = false;
  show($("ses-vazgec"), true);

  const warn = $("ses-uyari");
  if (result.review_reasons.length) {
    warn.textContent = "Dikkat: " + result.review_reasons.join(" · ");
    show(warn, true);
  } else show(warn, false);

  const similarBox = $("ses-benzer");
  if (result.similar.length) {
    const top = result.similar[0];
    similarBox.innerHTML =
      `Benzer kayıt var: <strong>${esc(top.title)}</strong> (${esc(top.authors)}) ` +
      `<button class="btn" id="benzer-birlestir">Adet olarak ekle</button>`;
    show(similarBox, true);
    $("benzer-birlestir").addEventListener("click", () => {
      mergeInto = top.edition_id;
      toast(`Kayıt "${top.title}" üzerine adet olarak eklenecek`, "info");
    }, { once: true });
  } else show(similarBox, false);

  // Hızlı mod: uygunsa sormadan kaydet, ardından kaydı otomatik yeniden başlat.
  if ($("hizli-mod").checked && result.auto_save_allowed) {
    saveVoice().then(() => startRecording()).catch(err);
  }
}

async function offerLearnable(learnable) {
  for (const item of learnable || []) {
    const label = FIELD_LABELS_TR[item.field] ?? item.field;
    const ok = await confirmBox(
      `"${item.heard}" duyulduğunda "${item.canonical}" yazılsın mı? ` +
        `(${label} sözlüğüne eklenir)`
    );
    if (!ok) continue;
    try {
      await api.post("/api/voice/aliases", {
        heard: item.heard, canonical: item.canonical, field_scope: item.field,
      });
      toast("Sözlüğe eklendi ✓", "success");
    } catch (error) { err(error); }
  }
}

async function saveVoice() {
  const values = readForm($("ses-form"));
  const copyCount = Number(values.copy_count || 1);
  delete values.copy_count;
  const result = await api.post("/api/voice/save", {
    pending_id: pendingId,
    values,
    copy_count: copyCount,
    approve: true,
    merge_into_edition: mergeInto,
  });
  toast(`Kaydedildi ✓ (No ${result.edition_id})`, "success");
  pendingId = null;
  mergeInto = null;
  $("ses-form").reset();
  const sticky = values.location; // Dolap yapışkan kalır.
  fillForm($("ses-form"), { location: sticky, copy_count: 1 });
  $("ses-kaydet").disabled = true;
  show($("ses-vazgec"), false);
  show($("ses-transkript"), false);
  show($("ses-benzer"), false);
  show($("ses-uyari"), false);
  renderSuggestions([]);
  $("ses-durum").textContent = "";
  refreshRecent();
  refreshDatalists();
  await offerLearnable(result.learnable);
}

async function discardPending(silent = false) {
  if (pendingId) await api.del(`/api/voice/pending/${pendingId}`);
  pendingId = null;
  mergeInto = null;
  $("ses-form").reset();
  fillForm($("ses-form"), { copy_count: 1 });
  $("ses-kaydet").disabled = true;
  show($("ses-vazgec"), false);
  show($("ses-transkript"), false);
  show($("ses-benzer"), false);
  show($("ses-uyari"), false);
  renderSuggestions([]);
  $("ses-durum").textContent = "";
  if (!silent) toast("Onaylanmamış ses kaydı silindi", "success");
}

// ── Alan bazlı yeniden söyle (refield) ────────────────

async function toggleRefield(field, button) {
  if (refieldRecorder && refieldRecorder.state === "recording") {
    if (refieldField === field) refieldRecorder.stop();
    return; // başka alan zaten kaydediyor; bu tıklama yok sayılır
  }
  if (mediaRecorder && mediaRecorder.state === "recording") {
    toast("Önce ana kaydı durdurun", "error");
    return;
  }
  let stream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch {
    toast("Mikrofona erişilemedi.", "error");
    return;
  }
  const recordedChunks = [];
  const mime = pickMime();
  refieldField = field;
  refieldRecorder = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
  refieldRecorder.addEventListener("dataavailable", (event) => recordedChunks.push(event.data));
  refieldRecorder.addEventListener("stop", () => {
    stream.getTracks().forEach((track) => track.stop());
    button.classList.remove("recording");
    const blob = new Blob(recordedChunks, { type: refieldRecorder.mimeType || "audio/webm" });
    refieldRecorder = null;
    refieldField = null;
    submitRefield(field, blob).catch(err);
  });
  refieldRecorder.start();
  button.classList.add("recording");
}

async function submitRefield(field, blob) {
  const form = new FormData();
  const extension = blob.type.includes("mp4") ? "mp4" : "webm";
  form.append("file", blob, `alan.${extension}`);
  await api.upload(`/api/voice/refield?field=${encodeURIComponent(field)}`, form);
  const finished = await pollJob("/api/voice/analyze/status");
  if (finished?.status !== "succeeded") {
    toast(finished?.error || "Yeniden okuma başarısız", "error");
    return;
  }
  addSuggestion({
    field_path: finished.result.field,
    value: finished.result.value,
    origin: "refield",
    language: "",
    score: 1,
  });
}

async function refreshRecent() {
  try {
    const books = await api.get("/api/voice/recent");
    $("ses-son").innerHTML = books
      .map((book) => `<li><span>${esc(book.title)}</span><small>${esc(book.location ?? "")}</small></li>`)
      .join("") || '<li class="hint">Henüz sesli kayıt yok.</li>';
  } catch { /* önemsiz */ }
}

// ── Toplu ses ────────────────────────────────────────

async function refreshVoiceQueue() {
  const [jobs, runState] = await Promise.all([
    api.get("/api/voice/jobs"),
    api.get("/api/voice/status"),
  ]);
  $("ses-kuyruk-govde").innerHTML = jobs
    .map(
      (job) => `
      <tr>
        <td><strong>${esc(job.name)}</strong></td>
        <td>${esc(job.status_label)}</td>
        <td>${esc(job.phase_label)}</td>
        <td>${job.total_items}</td>
        <td>${job.successful_items}</td>
        <td>${job.review_items}</td>
        <td>${job.failed_items}</td>
        <td>${
          job.status === "paused"
            ? `<button class="btn" data-vact="resume" data-job="${job.id}">Devam</button>`
            : job.status === "queued" || job.status === "running"
              ? `<button class="btn" data-vact="pause" data-job="${job.id}">Duraklat</button>`
              : ""
        }</td>
      </tr>`
    )
    .join("");
  show($("ses-kuyruk-bos"), jobs.length === 0);
  const running = runState.status === "running";
  show($("ses-kuyruk-baslat"), !running);
  show($("ses-kuyruk-durdur"), running);
}

// ── Bağlama ──────────────────────────────────────────

function bind() {
  if (bound) return;
  bound = true;

  $("kayit-btn").addEventListener("click", () => {
    if (mediaRecorder && mediaRecorder.state === "recording") stopRecording();
    else startRecording().catch(err);
  });
  $("ses-form").addEventListener("submit", (event) => {
    event.preventDefault();
    if (pendingId) saveVoice().catch(err);
  });
  $("ses-vazgec").addEventListener("click", () => discardPending().catch(err));

  $("ses-oneriler").addEventListener("click", (event) => {
    const chip = event.target.closest(".chip");
    if (!chip) return;
    const item = currentSuggestions[Number(chip.dataset.oneri)];
    if (!item) return;
    const input = $("ses-form").querySelector(`[name="${item.field_path}"]`);
    if (input) input.value = item.value;
  });

  for (const button of document.querySelectorAll(".ses-alan-mikrofon")) {
    button.addEventListener("click", () => {
      toggleRefield(button.dataset.refield, button).catch(err);
    });
  }

  $("ses-toplu-sec").addEventListener("click", () => $("ses-toplu-dosyalar").click());
  $("ses-toplu-dosyalar").addEventListener("change", async (event) => {
    const files = [...event.target.files];
    if (!files.length) return;
    const form = new FormData();
    for (const file of files) form.append("files", file);
    const language = $("ses-toplu-dil").value;
    if (language) form.append("language", language);
    try {
      const result = await api.upload("/api/voice/jobs", form);
      toast(`${result.jobs.length} ses işi kuyruğa eklendi ✓`, "success");
      event.target.value = "";
      refreshVoiceQueue();
    } catch (error) { err(error); }
  });
  $("ses-kuyruk-baslat").addEventListener("click", async () => {
    try {
      await api.post("/api/voice/run");
      toast("Ses kuyruğu işleniyor", "success");
      refreshVoiceQueue();
    } catch (error) { err(error); }
  });
  $("ses-kuyruk-durdur").addEventListener("click", async () => {
    try { await api.post("/api/voice/stop"); toast("Durdurma istendi"); } catch (error) { err(error); }
  });
  $("ses-kuyruk-govde").addEventListener("click", async (event) => {
    const act = event.target.dataset.vact;
    if (!act) return;
    try {
      await api.post(`/api/voice/jobs/${event.target.dataset.job}/${act}`);
      refreshVoiceQueue();
    } catch (error) { err(error); }
  });
}

export function enter() {
  bind();
  refreshRecent();
  refreshVoiceQueue().catch(() => {});
  pollTimer = setInterval(async () => {
    if (document.hidden || pollBusy) return;
    pollBusy = true;
    try { await refreshVoiceQueue(); }
    catch { /* sonraki turda yeniden dene */ }
    finally { pollBusy = false; }
  }, 2000);
}

export function leave() {
  clearInterval(pollTimer);
  pollTimer = null;
  if (mediaRecorder && mediaRecorder.state === "recording") stopRecording();
  if (refieldRecorder && refieldRecorder.state === "recording") refieldRecorder.stop();
}
