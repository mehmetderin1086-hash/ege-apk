// Geçmiş — üretilen tüm sesler
import { api, fmtDate, fmtDuration } from "/js/api.js";
import { createPlayer } from "/js/components/player.js";

const TYPE_LABELS = { tts: "Konuşturucu", vc: "Ses Değiştirici" };

export async function renderHistory(page) {
  page.innerHTML = `
    <div class="page-header row between">
      <div>
        <h1>Geçmiş</h1>
        <p>Üretilen tüm sesler — yeniden dinleyin, indirin, silin.</p>
      </div>
      <select id="h-filter">
        <option value="">Tümü</option>
        <option value="tts">Konuşturucu</option>
        <option value="vc">Ses Değiştirici</option>
      </select>
    </div>
    <div id="h-list"></div>
  `;

  const listEl = page.querySelector("#h-list");
  const filterEl = page.querySelector("#h-filter");
  filterEl.addEventListener("change", refresh);

  async function refresh() {
    const type = filterEl.value;
    const { items } = await api(`/api/history${type ? `?type=${type}` : ""}`);
    listEl.innerHTML = "";
    if (!items.length) {
      listEl.innerHTML = `<div class="card" style="text-align:center;color:var(--muted)">
        Henüz üretim yok.</div>`;
      return;
    }
    for (const rec of items) {
      const item = document.createElement("div");
      item.className = "list-item";
      item.innerHTML = `
        <div class="item-text">
          <div class="item-title">${escapeHtml(rec.text || "(kayıt)")}</div>
          <div class="item-sub">
            <span class="badge">${TYPE_LABELS[rec.type] || rec.type}</span>
            ${fmtDuration(rec.duration_s)} · ${fmtDate(rec.created_at)}
          </div>
        </div>
        <button class="btn small" data-act="play">▶</button>
        <a class="btn small" href="/api/history/${rec.id}/audio" download="${rec.id}.wav">WAV</a>
        <a class="btn small" href="/api/history/${rec.id}/audio?format=mp3">MP3</a>
        <button class="btn small danger" data-act="del">🗑</button>`;

      let playerEl = null;
      item.querySelector('[data-act="play"]').addEventListener("click", () => {
        if (playerEl) { playerEl.destroy(); playerEl = null; return; }
        playerEl = createPlayer(`/api/history/${rec.id}/audio`, {
          downloadName: `${rec.id}.wav`,
        });
        playerEl.style.marginTop = "10px";
        item.after(playerEl);
        playerEl.audio.play().catch(() => {});
      });
      item.querySelector('[data-act="del"]').addEventListener("click", async () => {
        if (confirm("Bu kayıt silinsin mi?")) {
          await api(`/api/history/${rec.id}`, { method: "DELETE" });
          refresh();
        }
      });
      listEl.appendChild(item);
    }
  }
  await refresh();
}

function escapeHtml(s) {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}
