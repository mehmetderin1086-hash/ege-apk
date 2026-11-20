// SesLab — hash router + kenar çubuğu
import { api } from "/js/api.js";
import { stopAllPlayers } from "/js/components/player.js";
import { disposeAllRecorders } from "/js/components/recorder.js";
import { renderTTS } from "/js/pages/tts.js?v=20260718-4";
import { renderVoices } from "/js/pages/voices.js?v=20260718-4";
import { renderSTT } from "/js/pages/stt.js";
import { renderVC } from "/js/pages/vc.js";
import { renderProjects } from "/js/pages/projects.js";
import { renderHistory } from "/js/pages/history.js";
import { renderSystem } from "/js/pages/system.js";
import { renderSetup } from "/js/pages/setup.js";

const icon = (d) =>
  `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;

const ROUTES = [
  { hash: "#/tts", label: "Konuşturucu", render: renderTTS,
    icon: icon('<path d="M12 2v20M7 6v12M17 6v12M2 10v4M22 10v4"/>') },
  { hash: "#/sesler", label: "Sesler", render: renderVoices,
    icon: icon('<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>') },
  { hash: "#/desifre", label: "Deşifre", render: renderSTT,
    icon: icon('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/>') },
  { hash: "#/degistirici", label: "Ses Değiştirici", render: renderVC,
    icon: icon('<polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>') },
  { hash: "#/projeler", label: "Projeler", render: renderProjects,
    icon: icon('<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>') },
  { hash: "#/gecmis", label: "Geçmiş", render: renderHistory,
    icon: icon('<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>') },
  { hash: "#/sistem", label: "Sistem", render: renderSystem,
    icon: icon('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>') },
];

const nav = document.getElementById("nav");
const page = document.getElementById("page");
let modelsPresent = null;

function buildNav() {
  nav.innerHTML = "";
  for (const r of ROUTES) {
    const item = document.createElement("div");
    item.className = "nav-item";
    item.dataset.hash = r.hash;
    item.innerHTML = `${r.icon}<span>${r.label}</span>`;
    item.addEventListener("click", () => { location.hash = r.hash; });
    nav.appendChild(item);
  }
}

async function route() {
  let hash = location.hash || "#/tts";

  // İlk kurulum kontrolü: modeller yoksa kurulum sayfasına zorla
  if (modelsPresent === null) {
    try {
      const status = await api("/api/system/status");
      modelsPresent = status.models_present;
    } catch {
      modelsPresent = false;
    }
  }
  if (!modelsPresent && hash !== "#/kurulum") {
    location.hash = "#/kurulum";
    return;
  }

  document.querySelectorAll(".nav-item").forEach((el) =>
    el.classList.toggle("active", el.dataset.hash === hash)
  );

  // Eski sayfanın ses kaynaklarını serbest bırak
  stopAllPlayers();
  disposeAllRecorders();

  // Her render kendi kapsayıcısına çizer: geciken eski bir async render,
  // yeni sayfanın DOM'una karışamaz (detached kapsayıcısında çalışır).
  page.innerHTML = "";
  const container = document.createElement("div");
  page.appendChild(container);

  if (hash === "#/kurulum") {
    await renderSetup(container, () => { modelsPresent = true; location.hash = "#/tts"; });
    return;
  }
  const match = ROUTES.find((r) => r.hash === hash) || ROUTES[0];
  await match.render(container);
}

buildNav();
window.addEventListener("hashchange", route);
route();
