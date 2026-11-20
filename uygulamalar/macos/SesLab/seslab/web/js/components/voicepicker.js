// Ses seçici — kütüphanedeki sesler + varsayılan yerleşik ses
import { api } from "/js/api.js";

/**
 * createVoicePicker({ value }) → <select> öğesi.
 * el.value → seçili voice_id (kütüphane boşsa "" = yerleşik ses)
 */
export async function createVoicePicker({ value = "" } = {}) {
  const select = document.createElement("select");
  select.className = "voice-picker";
  const { voices } = await api("/api/voices");

  if (!voices.length) {
    const def = document.createElement("option");
    def.value = "";
    def.textContent = "🎙️ Varsayılan ses (yerleşik)";
    select.appendChild(def);
  }

  for (const v of voices) {
    const opt = document.createElement("option");
    opt.value = v.id;
    opt.textContent = `👤 ${v.name}`;
    select.appendChild(opt);
  }
  // Kütüphane varsa en yeni sesi açık kimliğiyle seç. Böylece geçmiş kaydı
  // "varsayılan" yerine gerçekten kullanılan Murat/Emel modelini gösterir ve
  // menüde aynı ses iki kez görünmez.
  select.value = value && [...select.options].some((o) => o.value === value)
    ? value
    : (voices[0]?.id || "");
  return select;
}
