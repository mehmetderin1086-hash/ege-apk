// İlk kurulum — model indirme
import { api, watchJob } from "/js/api.js";
import { toast } from "/js/components/toast.js";

export async function renderSetup(page, onDone) {
  page.innerHTML = `
    <div class="page-header" style="text-align:center;padding-top:40px">
      <h1>SesLab'e Hoş Geldiniz 🎙️</h1>
      <p>Başlamadan önce yapay zekâ modellerinin indirilmesi gerekiyor (~7 GB, tek seferlik).</p>
    </div>
    <div class="card" style="max-width:560px;margin:0 auto">
      <div id="model-status" style="margin-bottom:16px"></div>
      <div id="dl-progress" style="display:none;margin-bottom:16px">
        <div class="progress"><div class="fill"></div></div>
        <div class="progress-label">İndiriliyor...</div>
      </div>
      <button class="btn primary" id="dl-btn" style="width:100%;padding:13px">
        📥 Modelleri İndir (~7 GB)
      </button>
      <p style="font-size:12px;color:var(--muted);margin-top:12px;text-align:center">
        Chatterbox Multilingual (TTS + klonlama, ~5.5 GB) ·
        Whisper large-v3-turbo (deşifre, ~1.6 GB)<br>
        İndirme yarıda kalırsa kaldığı yerden devam eder.
      </p>
    </div>
  `;

  const statusEl = page.querySelector("#model-status");
  const btn = page.querySelector("#dl-btn");
  const prog = page.querySelector("#dl-progress");

  async function checkStatus() {
    const s = await api("/api/system/status");
    statusEl.innerHTML = Object.entries(s.models)
      .map(([repo, size]) =>
        `<div class="row between" style="font-size:13px;padding:6px 0">
          <span style="font-family:var(--mono)">${repo}</span>
          <span class="badge ${size ? "done" : ""}">${size ? size + " GB ✓" : "eksik"}</span>
        </div>`)
      .join("");
    return s.models_present;
  }

  // Dinleyici İLK önce bağlanır: ilk durum sorgusu başarısız olsa bile
  // "Modelleri İndir" düğmesi işlevsel kalır.
  btn.addEventListener("click", async () => {
    btn.disabled = true;
    prog.style.display = "block";
    const fill = prog.querySelector(".fill");
    const label = prog.querySelector(".progress-label");
    try {
      const { job_id } = await api("/api/setup/download", { method: "POST" });
      await watchJob(job_id, (j) => {
        fill.style.width = `${Math.max(4, j.progress * 100)}%`;
        label.textContent = j.message || "İndiriliyor... (hız bağlantınıza bağlı)";
      });
      toast("Modeller hazır! 🎉");
      await checkStatus();
      onDone();
    } catch (e) {
      toast(e.message || "İndirme hatası", "error");
      btn.disabled = false;
    }
  });

  try {
    if (await checkStatus()) { onDone(); return; }
  } catch {
    statusEl.innerHTML =
      '<span style="color:var(--danger)">Sunucu durumu alınamadı — indirme yine de denenebilir.</span>';
  }
}
