// Sistem — RAM, motorlar, modeller
import { api } from "/js/api.js";
import { toast } from "/js/components/toast.js";

const ENGINE_LABELS = {
  tts: "TTS + Klonlama (Chatterbox)",
  vc: "Ses Değiştirici (ChatterboxVC)",
  stt: "Deşifre (mlx-whisper)",
};

export async function renderSystem(page) {
  page.innerHTML = `
    <div class="page-header">
      <h1>Sistem</h1>
      <p>Bellek durumu, model motorları ve yapılandırma.</p>
    </div>
    <div class="stat-grid" id="stats"></div>
    <div class="card" style="margin-top:16px">
      <h2 style="margin-bottom:12px">Motorlar</h2>
      <div id="engines"></div>
    </div>
    <div class="card">
      <h2 style="margin-bottom:8px">Hakkında</h2>
      <p style="font-size:13.5px;color:var(--muted);line-height:1.7">
        <b>SesLab</b> — tamamen yerel, Türkçe odaklı ses stüdyosu.<br>
        TTS + klonlama: <a href="https://github.com/resemble-ai/chatterbox" target="_blank">Chatterbox Multilingual</a> (MIT, Resemble AI) ·
        Deşifre: <a href="https://github.com/ml-explore/mlx-examples" target="_blank">mlx-whisper large-v3-turbo</a><br>
        Tüm TTS/dönüştürme çıktıları, kötüye kullanımı caydırmak için duyulmayan
        <b>Perth nöral filigranı</b> içerir.<br>
        OpenAI uyumlu API: <code style="font-family:var(--mono)">POST /v1/audio/speech</code> ·
        <code style="font-family:var(--mono)">POST /v1/audio/transcriptions</code>
      </p>
    </div>
  `;

  async function refresh() {
    const s = await api("/api/system/status");
    const stats = page.querySelector("#stats");
    stats.innerHTML = `
      <div class="stat"><div class="stat-value">${s.ram_used_gb} / ${s.ram_total_gb} GB</div>
        <div class="stat-label">Sistem RAM kullanımı</div></div>
      <div class="stat"><div class="stat-value">${s.rss_gb} GB</div>
        <div class="stat-label">SesLab bellek (RSS)</div></div>
      <div class="stat"><div class="stat-value">${s.models_present ? "✓ Hazır" : "Eksik"}</div>
        <div class="stat-label">Model dosyaları</div></div>`;

    const enginesEl = page.querySelector("#engines");
    enginesEl.innerHTML = "";
    for (const [name, e] of Object.entries(s.engines)) {
      const row = document.createElement("div");
      row.className = "row between";
      row.style.padding = "10px 0";
      row.style.borderBottom = "1px solid var(--border)";
      row.innerHTML = `
        <div>
          <div style="font-weight:600;font-size:14px">${ENGINE_LABELS[name] || name}</div>
          <div style="font-size:12px;color:var(--muted)">
            ~${e.est_mem_gb} GB · ${e.gen_count} üretim
            ${e.heavy ? " · ağır motor" : ""}
          </div>
        </div>
        <div class="row" style="gap:10px">
          <span class="badge ${e.loaded ? "done" : ""}">${e.loaded ? "bellekte" : "boşta"}</span>
          <button class="btn small ghost" ${e.loaded ? "" : "disabled"}>Boşalt</button>
        </div>`;
      row.querySelector("button").addEventListener("click", async () => {
        await api(`/api/system/engines/${name}/unload`, { method: "POST" });
        toast(`${name} motoru boşaltıldı`);
        refresh();
      });
      enginesEl.appendChild(row);
    }
  }
  await refresh();
}
