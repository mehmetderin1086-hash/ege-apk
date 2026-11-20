// Motor Durumu: 5 OCR + Qwen3 alan çıkarıcı paket doğrulaması.

import { api, pollJob } from "../api.js";
import { esc, show, toast } from "../ui.js";

const $ = (id) => document.getElementById(id);
let bound = false;

const ENGINE_NAMES = {
  rapidocr_ppocrv6: "RapidOCR + PP-OCRv6",
  tesseract: "Tesseract 5",
  easyocr: "EasyOCR",
  paddleocr_vl: "PaddleOCR-VL",
  surya: "Surya OCR 2",
  qwen3: "Qwen3 alan çıkarıcı",
};

function render(statuses) {
  $("motor-govde").innerHTML = (statuses || [])
    .map(
      (engine) => `
      <tr>
        <td><strong>${esc(ENGINE_NAMES[engine.engine_id] || engine.engine_id)}</strong></td>
        <td>${esc(engine.version ?? "")}</td>
        <td>${esc(engine.family ?? "")}</td>
        <td><span class="status-pill ${engine.available ? "ok" : "err"}">${engine.available ? "Hazır" : "Eksik"}</span></td>
        <td>${esc(engine.reasons.join("; "))}</td>
      </tr>`
    )
    .join("");
}

async function verify() {
  const statusBox = $("motor-durum");
  $("motor-dogrula").disabled = true;
  statusBox.innerHTML = '<span class="spinner"></span> Model paketleri doğrulanıyor…';
  try {
    await api.post("/api/engines/verify");
    const job = await pollJob("/api/engines", { field: "job", intervalMs: 2000 });
    if (job.status === "succeeded") {
      render(job.result);
      const ready = job.result.filter((engine) => engine.available).length;
      statusBox.textContent = `${ready}/${job.result.length} motor hazır.`;
    } else {
      statusBox.textContent = "";
      toast(job.error || "Doğrulama başarısız", "error", 6000);
    }
  } catch (error) {
    statusBox.textContent = "";
    if (error.status === 409) toast("Doğrulama zaten sürüyor");
    else toast(error.message, "error");
  } finally { $("motor-dogrula").disabled = false; }
}

function bind() {
  if (bound) return;
  bound = true;
  $("motor-dogrula").addEventListener("click", verify);
}

export async function enter() {
  bind();
  try {
    const data = await api.get("/api/engines");
    if (data.statuses) render(data.statuses);
    else verify(); // İlk ziyarette otomatik doğrula.
  } catch (error) { toast(error.message, "error"); }
}

export function leave() {}
