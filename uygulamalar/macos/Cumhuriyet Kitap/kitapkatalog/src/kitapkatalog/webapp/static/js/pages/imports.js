// İçe Aktarma: toplu/tek yükleme, dolap seçimi, kuyruk tablosu, OCR işleme kontrolü.

import { api } from "../api.js";
import { confirmBox, esc, show, toast } from "../ui.js";

const $ = (id) => document.getElementById(id);
let bound = false;
let pollTimer = null;
let bulkFiles = [];
let openJobId = null;
let pollBusy = false;

const err = (error) => toast(error.message || String(error), "error");

// Tarayıcı klasör seçiminde göreli yolu verir; çok parçalı gönderimde dosya
// adı olarak taşınır, sunucu klasör yapısını böyle görür.
const relativeName = (file) => file.webkitRelativePath || file.name;

// ── Dolap listesi ────────────────────────────────────

async function refreshShelfOptions() {
  try {
    const shelves = await api.get("/api/shelves");
    $("dolap-listesi").innerHTML = shelves
      .map((shelf) => `<option value="${esc(shelf.name)}"></option>`)
      .join("");
  } catch { /* dolap listesi olmadan da yükleme yapılabilir */ }
}

// ── Yüklemeler ───────────────────────────────────────

function updateBulkSelection() {
  const info = $("toplu-secim");
  if (bulkFiles.length === 0) { show(info, false); $("toplu-yukle").disabled = true; return; }
  const folders = new Set(
    bulkFiles.map((file) => relativeName(file).split("/").slice(0, -1).join("/")).filter(Boolean)
  );
  const books = Math.floor(bulkFiles.length / 4);
  const folderNote = folders.size ? ` — ${folders.size} klasör` : "";
  info.textContent = `${bulkFiles.length} dosya seçildi (~${books} kitap)${folderNote}.`;
  show(info, true);
  $("toplu-yukle").disabled = false;
}

function reportRow(title, items) {
  if (!items.length) return "";
  return `<p><strong>${esc(title)}</strong></p><ul class="rapor-liste">${items
    .map((text) => `<li>${esc(text)}</li>`)
    .join("")}</ul>`;
}

function renderReport(result) {
  const badges = result.preflight
    ? [`<span class="rapor-rozet uyari">Ön kontrol: yükleme yapılmadı</span>`]
    : [`<span class="rapor-rozet iyi">${result.books} kitap kuyruğa eklendi</span>`];
  if (result.shelf) badges.push(`<span class="rapor-rozet">Dolap: ${esc(result.shelf)}</span>`);
  for (const name of result.folder_shelves || []) {
    badges.push(`<span class="rapor-rozet">Klasör dolabı: ${esc(name)}</span>`);
  }
  if (result.books_without_shelf) {
    badges.push(
      `<span class="rapor-rozet uyari">${result.books_without_shelf} kitap dolapsız</span>`
    );
  }
  const problems = (result.unpaired?.length || 0) + (result.rejected?.length || 0);
  if (problems) badges.push(`<span class="rapor-rozet uyari">${problems} dosya alınamadı</span>`);
  if (result.quality_warnings?.length) {
    badges.push(
      `<span class="rapor-rozet uyari">${result.quality_warnings.length} fotoğrafta kalite uyarısı</span>`
    );
  }

  $("rapor-govde").innerHTML =
    `<div class="rapor-ozet">${badges.join("")}</div>` +
    reportRow(
      "Yeniden çekilmesi önerilen fotoğraflar",
      (result.quality_warnings || []).map((row) => `${row.file}: ${row.warnings.join(", ")}`)
    ) +
    reportRow(
      "Açılan ZIP arşivleri",
      (result.zip_expanded || []).map(
        (row) =>
          `${row.file}: ${row.files} dosya` +
          (row.rejected.length ? `, ${row.rejected.length} reddedildi` : "")
      )
    ) +
    reportRow(
      "Bölünen çok kitaplı belgeler",
      (result.split_documents || []).map((row) => `${row.file} → ${row.books} kitap`)
    ) +
    reportRow(
      "Yeni oluşturulan dolaplar",
      (result.shelves_created || []).map((name) => name)
    ) +
    reportRow("Eşleşmeyen dosyalar", result.unpaired || []) +
    reportRow(
      "Reddedilen dosyalar",
      (result.rejected || []).map((row) => `${row.file}: ${row.reason}`)
    ) +
    reportRow(
      "Kararsız eşleşmeler",
      (result.ambiguous || []).map((row) => `${row.reason}: ${row.files.join(", ")}`)
    );
  show($("aktarim-rapor"), true);
}

async function uploadBulk() {
  const form = new FormData();
  for (const file of bulkFiles) form.append("files", file, relativeName(file));
  const shelf = $("toplu-dolap").value.trim();
  if (shelf) form.append("shelf", shelf);
  if ($("toplu-klasor-dolap").checked) form.append("folder_shelf", "1");
  $("toplu-yukle").disabled = true;
  $("toplu-yukle").textContent = "Yükleniyor…";
  try {
    const result = await api.upload("/api/imports/bulk", form);
    let message = `${result.books} kitap işe eklendi ✓`;
    if (result.shelf) message += ` — ${result.shelf}`;
    if (result.unpaired.length) message += ` — ${result.unpaired.length} dosya eşleşmedi`;
    toast(message, result.unpaired.length ? "info" : "success", 5000);
    renderReport(result);
    bulkFiles = [];
    $("toplu-dosyalar").value = "";
    $("toplu-klasor-secim").value = "";
    updateBulkSelection();
    refreshShelfOptions();
    refreshQueue();
  } catch (error) { err(error); } finally {
    $("toplu-yukle").textContent = "Yükle ve İşe Ekle";
    updateBulkSelection();
  }
}

function singleMode() {
  const checked = document.querySelector('input[name="tek-mod"]:checked');
  return checked ? checked.value : "belge";
}

function singleFaces() {
  const faces = {};
  document.querySelectorAll("#tek-yuz-alani .face-pick input").forEach((input) => {
    if (input.files[0]) faces[input.dataset.face] = input.files[0];
  });
  return faces;
}

function singleReady() {
  return singleMode() === "belge"
    ? Boolean($("tek-belge").files[0])
    : Object.keys(singleFaces()).length === 4;
}

function syncSingleMode() {
  const document4 = singleMode() === "belge";
  show($("tek-belge-alani"), document4);
  show($("tek-yuz-alani"), !document4);
  $("tek-yukle").disabled = !singleReady();
}

async function uploadSingle() {
  const form = new FormData();
  if (singleMode() === "belge") {
    form.append("document", $("tek-belge").files[0]);
  } else {
    for (const [face, file] of Object.entries(singleFaces())) form.append(face, file);
  }
  const shelf = $("tek-dolap").value.trim();
  if (shelf) form.append("shelf", shelf);
  $("tek-yukle").disabled = true;
  try {
    if ($("tek-on-kontrol").checked) {
      const preflightForm = new FormData();
      for (const [key, value] of form.entries()) preflightForm.append(key, value);
      preflightForm.append("preflight", "1");
      const check = await api.upload("/api/imports/single", preflightForm);
      if (check.quality_warnings.length) {
        renderReport(check);
        const devamEt = await confirmBox(
          `${check.quality_warnings.length} fotoğrafta kalite uyarısı var. Yine de yüklensin mi?`
        );
        if (!devamEt) return;
      }
    }
    const result = await api.upload("/api/imports/single", form);
    toast(result.shelf ? `Kitap işe eklendi ✓ — ${result.shelf}` : "Kitap işe eklendi ✓", "success");
    $("tek-belge").value = "";
    document.querySelectorAll("#tek-yuz-alani .face-pick input").forEach((input) => {
      input.value = "";
    });
    refreshShelfOptions();
    refreshQueue();
  } catch (error) { err(error); } finally {
    $("tek-yukle").disabled = !singleReady();
  }
}

// ── Kuyruk ───────────────────────────────────────────

function jobActions(job) {
  const buttons = [];
  if (job.status === "paused") {
    buttons.push(`<button class="btn" data-act="resume" data-job="${job.id}">Devam</button>`);
  } else if (job.status === "running" || job.status === "queued") {
    buttons.push(`<button class="btn" data-act="pause" data-job="${job.id}">Duraklat</button>`);
  }
  const running = ["queued", "running", "paused"].includes(job.status);
  if (running) {
    buttons.push(`<button class="btn" data-act="cancel" data-job="${job.id}">İptal</button>`);
  }
  // Silme yalnız durmuş ve kataloğa kitap yazmamış iş için; sunucu da aynı
  // kapıyı uygular, buradaki kural düğmeyi boşuna göstermemek içindir.
  if (!running && !job.successful_items) {
    buttons.push(`<button class="btn btn-danger" data-act="delete" data-job="${job.id}">Sil</button>`);
  }
  return buttons.join(" ");
}

async function refreshQueue() {
  const [jobs, processState] = await Promise.all([
    api.get("/api/imports"),
    api.get("/api/process/status"),
  ]);
  const body = $("kuyruk-govde");
  body.innerHTML = jobs
    .map((job) => {
      const percent = job.total_items ? Math.round((job.terminal_items / job.total_items) * 100) : 0;
      return `
      <tr data-job="${job.id}" tabindex="0" role="button" data-key-activate
          aria-label="${esc(job.name)} iş ayrıntısını aç">
        <td><strong>${esc(job.name)}</strong></td>
        <td>${esc(job.location || "—")}</td>
        <td>${esc(job.status_label)}</td>
        <td><div class="mini-progress" title="%${percent}"><div style="width:${percent}%"></div></div></td>
        <td>${job.successful_items}/${job.total_items}</td>
        <td>${job.review_items}</td>
        <td>${job.failed_items}</td>
        <td>${jobActions(job)}</td>
      </tr>`;
    })
    .join("");
  show($("kuyruk-bos"), jobs.length === 0);

  const running = processState.status === "running";
  show($("islem-durum"), running);
  if (running) {
    $("islem-durum").innerHTML =
      `<span class="spinner"></span> ${esc(processState.message || "İşleniyor…")}`;
  } else if (processState.status === "failed") {
    show($("islem-durum"), true);
    $("islem-durum").textContent = `İşlem hatası: ${processState.error}`;
  }
  show($("islem-baslat"), !running);
  show($("islem-durdur"), running);

  if (openJobId && jobs.some((job) => job.id === openJobId)) {
    renderJobDetail(openJobId).catch(() => {});
  } else if (openJobId) {
    openJobId = null;
    show($("is-detay"), false);
  }
}

async function renderJobDetail(jobId) {
  const detail = await api.get(`/api/imports/${jobId}`);
  const box = $("is-detay");
  const failedRows = detail.failed_items
    .map(
      (item) => `
      <tr>
        <td>${esc(item.pair_key)}</td>
        <td>${esc(item.stage_label)}</td>
        <td>${esc(item.location ?? detail.job.location ?? "—")}</td>
        <td>${esc(item.last_error ?? "")}</td>
        <td><button class="btn" data-retry="${item.id}">Yeniden dene</button></td>
      </tr>`
    )
    .join("");
  const shelfBadges = (detail.shelves || [])
    .map(
      (row) =>
        `<span class="rapor-rozet">${esc(row.name || "Dolapsız")}: ${row.count} kitap</span>`
    )
    .join("");
  const splitBadge = detail.split_books
    ? `<span class="rapor-rozet">${detail.split_books} kitap çok kitaplı PDF'ten bölündü</span>`
    : "";
  box.innerHTML = `
    <h3>${esc(detail.job.name)} — ayrıntı</h3>
    <div class="rapor-ozet">${shelfBadges}${splitBadge}</div>
    <div class="dolap-alani">
      <label for="is-dolap">Dolap</label>
      <input type="text" id="is-dolap" list="dolap-listesi" maxlength="120"
             value="${esc(detail.job.location ?? "")}" placeholder="ör. Dolap 3">
      <button class="btn" id="is-dolap-kaydet" data-job="${detail.job.id}">Dolabı güncelle</button>
    </div>
    <p class="hint">Dolap değişikliği yalnız işlenmeye başlamamış kitaplara uygulanır;
    kataloğa girmiş kitaplar eski dolaplarında kalır.</p>
    ${detail.failed_items.length
      ? `<p><button class="btn" data-retry-all="${detail.job.id}">Bütün hatalıları yeniden dene</button></p>
         <div class="table-wrap"><table class="data-table">
           <thead><tr><th>Kitap</th><th>Aşama</th><th>Dolap</th><th>Hata</th><th></th></tr></thead>
           <tbody>${failedRows}</tbody></table></div>`
      : '<p class="hint">Hatalı öğe yok.</p>'}`;
  show(box, true);
}

// ── İşleme kontrolü ──────────────────────────────────

async function startProcessing() {
  try {
    await api.post("/api/process/start", {});
    toast("5 OCR işleme başlatıldı", "success");
    refreshQueue();
  } catch (error) { err(error); }
}

async function stopProcessing() {
  try {
    await api.post("/api/process/stop");
    toast("Durdurma istendi; mevcut kitap bitince duracak");
  } catch (error) { err(error); }
}

// ── Bağlama ──────────────────────────────────────────

function bind() {
  if (bound) return;
  bound = true;

  const zone = $("toplu-birak");
  const input = $("toplu-dosyalar");
  const folderInput = $("toplu-klasor-secim");
  zone.addEventListener("click", () => input.click());
  zone.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      input.click();
    }
  });
  input.addEventListener("change", () => {
    bulkFiles = [...input.files];
    updateBulkSelection();
  });
  $("toplu-klasor-ac").addEventListener("click", () => folderInput.click());
  folderInput.addEventListener("change", () => {
    bulkFiles = [...folderInput.files];
    updateBulkSelection();
  });
  for (const eventName of ["dragover", "dragenter"]) {
    zone.addEventListener(eventName, (event) => { event.preventDefault(); zone.classList.add("hover"); });
  }
  for (const eventName of ["dragleave", "drop"]) {
    zone.addEventListener(eventName, (event) => { event.preventDefault(); zone.classList.remove("hover"); });
  }
  zone.addEventListener("drop", (event) => {
    bulkFiles = [...event.dataTransfer.files];
    updateBulkSelection();
  });
  $("toplu-yukle").addEventListener("click", uploadBulk);
  $("rapor-kapat").addEventListener("click", () => show($("aktarim-rapor"), false));

  document.querySelectorAll('input[name="tek-mod"]').forEach((radio) => {
    radio.addEventListener("change", syncSingleMode);
  });
  $("tek-belge").addEventListener("change", syncSingleMode);
  document.querySelectorAll("#tek-yuz-alani .face-pick input").forEach((faceInput) => {
    faceInput.addEventListener("change", syncSingleMode);
  });
  $("tek-yukle").addEventListener("click", uploadSingle);

  $("islem-baslat").addEventListener("click", startProcessing);
  $("islem-durdur").addEventListener("click", stopProcessing);

  $("kuyruk-govde").addEventListener("click", async (event) => {
    const act = event.target.dataset.act;
    if (act) {
      event.stopPropagation();
      const jobId = event.target.dataset.job;
      try {
        if (act === "delete") {
          if (!(await confirmBox("Bu iş ve kuyruk kayıtları silinsin mi?"))) return;
          await api.del(`/api/imports/${jobId}`);
          if (openJobId === jobId) { openJobId = null; show($("is-detay"), false); }
          toast("İş silindi", "success");
        } else {
          await api.post(`/api/imports/${jobId}/${act}`);
        }
        refreshQueue();
      } catch (error) { err(error); }
      return;
    }
    const row = event.target.closest("tr[data-job]");
    if (row) {
      openJobId = row.dataset.job;
      renderJobDetail(openJobId).catch(err);
    }
  });
  $("is-detay").addEventListener("click", async (event) => {
    const { retry, retryAll } = event.target.dataset;
    if (retry) {
      try {
        await api.post(`/api/imports/items/${retry}/retry`);
        toast("Öğe yeniden kuyruğa alındı", "success");
        refreshQueue();
      } catch (error) { err(error); }
      return;
    }
    if (retryAll) {
      try {
        const result = await api.post(`/api/imports/${retryAll}/retry-failed`);
        const kalan = result.remaining
          ? ` — ${result.remaining} öğe hâlâ hatalı, yeniden çalıştırın`
          : "";
        toast(`${result.requeued} öğe yeniden kuyruğa alındı${kalan}`, kalan ? "info" : "success", 5000);
        refreshQueue();
      } catch (error) { err(error); }
      return;
    }
    if (event.target.id === "is-dolap-kaydet") {
      try {
        await api.patch(`/api/imports/${event.target.dataset.job}`, {
          shelf: $("is-dolap").value.trim(),
        });
        toast("İşin dolabı güncellendi", "success");
        refreshShelfOptions();
        refreshQueue();
      } catch (error) { err(error); }
    }
  });
}

export function enter() {
  bind();
  syncSingleMode();
  refreshShelfOptions();
  refreshQueue().catch(err);
  pollTimer = setInterval(async () => {
    if (document.hidden || pollBusy) return;
    pollBusy = true;
    try { await refreshQueue(); }
    catch { /* sonraki turda yeniden dene */ }
    finally { pollBusy = false; }
  }, 2000);
}

export function leave() {
  clearInterval(pollTimer);
  pollTimer = null;
}
