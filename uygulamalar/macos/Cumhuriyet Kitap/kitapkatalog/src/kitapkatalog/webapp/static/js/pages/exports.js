// Dışa Aktarım: katalog dosyası + taşınabilir yedek; iş bitince otomatik indirme.

import { api, pollJob } from "../api.js";
import { esc, show, toast } from "../ui.js";

const $ = (id) => document.getElementById(id);
let bound = false;

const err = (error) => toast(error.message || String(error), "error");

function download(name) {
  const link = document.createElement("a");
  link.href = `/api/exports/download/${encodeURIComponent(name)}`;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  link.remove();
}

async function runExport() {
  const format = document.querySelector('input[name="format"]:checked').value;
  const statusBox = $("disari-durum");
  $("disari-baslat").disabled = true;
  statusBox.innerHTML = '<span class="spinner"></span> Hazırlanıyor…';
  try {
    await api.post("/api/exports", {
      format,
      completed_only: $("disari-tamam").checked,
    });
    const job = await pollJob("/api/exports/status", {
      field: "export",
      onTick: (state) => { if (state?.message) statusBox.innerHTML = `<span class="spinner"></span> ${esc(state.message)}`; },
    });
    if (job.status === "succeeded") {
      statusBox.textContent = `${job.result.records} kayıt dışa aktarıldı ✓`;
      download(job.result.download);
    } else {
      statusBox.textContent = "";
      toast(job.error || "Dışa aktarım başarısız", "error", 6000);
    }
  } catch (error) { statusBox.textContent = ""; err(error); }
  finally { $("disari-baslat").disabled = false; }
}

async function runArchive() {
  const statusBox = $("arsiv-durum");
  $("arsiv-baslat").disabled = true;
  statusBox.innerHTML = '<span class="spinner"></span> Yedek oluşturuluyor…';
  try {
    await api.post("/api/archive", { include_covers: $("arsiv-kapak").checked });
    const job = await pollJob("/api/exports/status", { field: "archive" });
    if (job.status === "succeeded") {
      statusBox.textContent = `Yedek hazır ✓ (${job.result.cover_count} kapak)`;
      download(job.result.download);
    } else {
      statusBox.textContent = "";
      toast(job.error || "Yedekleme başarısız", "error", 6000);
    }
  } catch (error) { statusBox.textContent = ""; err(error); }
  finally { $("arsiv-baslat").disabled = false; }
}

// ── Yedekten geri yükleme ────────────────────────────

let stagingId = null;

function summaryText(result) {
  const counts = result.counts || {};
  const parts = [
    `${counts.edition ?? 0} kitap`,
    `${counts.copy ?? 0} nüsha`,
    `${counts.member ?? 0} üye`,
    `${counts.loan ?? 0} ödünç kaydı`,
    `${result.cover_count ?? 0} kapak`,
  ];
  const school = result.school_name ? ` · Okul: ${result.school_name}` : "";
  const created = result.archive_created_at
    ? ` · Yedek tarihi: ${String(result.archive_created_at).slice(0, 10)}`
    : "";
  return `Doğrulandı ✓ ${parts.join(" · ")}${school}${created}`;
}

async function refreshRestoreState() {
  try {
    const status = await api.get("/api/restore/status");
    show($("geri-bekleyen"), Boolean(status.pending));
    if (!status.pending && status.last_result) {
      const last = status.last_result;
      $("geri-durum").textContent =
        last.status === "applied"
          ? `Son geri yükleme uygulandı ✓ (${String(last.at || "").slice(0, 10)})`
          : last.status === "failed"
            ? `Son geri yükleme başarısız: ${last.reason || ""}`
            : "";
    }
  } catch { /* durum bilgisi kritik değil */ }
}

async function uploadRestore() {
  const input = $("geri-dosya");
  if (!input.files.length) { toast("Önce .kitaparsiv dosyası seçin", "error"); return; }
  const form = new FormData();
  form.append("file", input.files[0]);
  $("geri-yukle").disabled = true;
  show($("geri-ozet"), false);
  $("geri-durum").innerHTML = '<span class="spinner"></span> Yükleniyor ve doğrulanıyor…';
  try {
    await api.upload("/api/restore/upload", form);
    const job = await pollJob("/api/restore/status", { field: "job" });
    if (job.status === "succeeded") {
      stagingId = job.result.staging_id;
      $("geri-durum").textContent = "";
      $("geri-ozet-metin").textContent = summaryText(job.result);
      show($("geri-ozet"), true);
    } else {
      $("geri-durum").textContent = "";
      toast(job.error || "Yedek doğrulanamadı", "error", 6000);
    }
  } catch (error) { $("geri-durum").textContent = ""; err(error); }
  finally { $("geri-yukle").disabled = false; }
}

async function confirmRestore() {
  if (!stagingId) return;
  try {
    await api.post("/api/restore/confirm", { staging_id: stagingId });
    stagingId = null;
    $("geri-dosya").value = "";
    show($("geri-ozet"), false);
    show($("geri-bekleyen"), true);
    toast("Geri yükleme onaylandı; uygulamayı yeniden başlatın ✓", "success", 6000);
  } catch (error) { err(error); }
}

async function cancelRestore() {
  try {
    await api.del("/api/restore/pending");
    show($("geri-bekleyen"), false);
    toast("Geri yükleme iptal edildi", "success");
  } catch (error) { err(error); }
}

function bind() {
  if (bound) return;
  bound = true;
  $("disari-baslat").addEventListener("click", runExport);
  $("arsiv-baslat").addEventListener("click", runArchive);
  $("geri-yukle").addEventListener("click", () => uploadRestore().catch(err));
  $("geri-onayla").addEventListener("click", () => confirmRestore().catch(err));
  $("geri-vazgec").addEventListener("click", () => cancelRestore().catch(err));
}

export function enter() {
  bind();
  refreshRestoreState();
}
export function leave() {}
