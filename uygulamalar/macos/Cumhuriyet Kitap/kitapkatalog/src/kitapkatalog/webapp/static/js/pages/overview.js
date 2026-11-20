// Genel Bakış: stat kartları + donut/bar/line grafik + mini listeler.

import { api } from "../api.js";
import { esc, fmtCount, show } from "../ui.js";
import { lineChart, barChart, donutChart } from "../charts.js";

function fmtDate(value) {
  if (!value) return "—";
  return value.slice(0, 10).split("-").reverse().join(".");
}

async function loadDashboard() {
  const data = await api.get("/api/dashboard");
  document.getElementById("st-eser").textContent = fmtCount(data.totals.works);
  document.getElementById("st-nusha").textContent = fmtCount(data.totals.copies);
  document.getElementById("st-odunc").textContent = fmtCount(data.active_loans);
  document.getElementById("st-geciken").textContent = fmtCount(data.overdue);
  document.getElementById("st-bugun-islem").textContent = fmtCount(data.today_events);
  document.getElementById("st-bildirim").textContent = fmtCount(data.unread_notifications);
  document.getElementById("st-rezervasyon").textContent = fmtCount(data.pending_holds);
  document.getElementById("st-okuyan").textContent = fmtCount(data.readers_this_month);

  donutChart(document.getElementById("grafik-koleksiyon"), [
    { label: "Rafta", value: data.collection_status.on_shelf },
    { label: "Ödünçte", value: data.collection_status.on_loan },
  ], { ariaLabel: "Koleksiyon durumu" });

  barChart(
    document.getElementById("grafik-kategori"),
    (data.category_distribution || []).map((row) => ({ label: row.value, value: row.count })),
    { ariaLabel: "Kategoriye göre dağılım" }
  );

  lineChart(
    document.getElementById("grafik-buyume"),
    (data.monthly_loans || []).map((point) => ({ label: point.month.slice(2), value: point.total }))
  );

  const yarismaKart = document.getElementById("oz-yarisma-kart");
  show(yarismaKart, Boolean(data.active_challenge));
  if (data.active_challenge) {
    document.getElementById("oz-yarisma-ad").textContent = data.active_challenge.name;
    document.getElementById("oz-yarisma-liste").innerHTML = data.active_challenge.top
      .map(
        (entry, index) => `
        <li class="yarisma-mini-sira">
          <span class="sira-no">${index + 1}</span>
          <span>${esc(entry.member_name)}</span>
          <strong style="margin-left:auto">${fmtCount(entry.value)}</strong>
        </li>`
      )
      .join("");
  }
}

async function loadOverdue() {
  const data = await api.get("/api/loans?status=overdue&limit=5");
  const list = document.getElementById("oz-geciken");
  const top = data.items.slice(0, 5);
  list.innerHTML = top
    .map(
      (loan) => `
      <li>
        <span>${esc(loan.title)}<span class="mini-liste-alt"> — ${esc(loan.member_name)}</span></span>
        <span class="geciken">${fmtDate(loan.due_at)}</span>
      </li>`
    )
    .join("");
  show(document.getElementById("oz-geciken-bos"), data.total === 0);
  show(document.getElementById("oz-geciken-daha"), data.total > 0);
}

export async function enter() {
  try {
    await loadDashboard();
  } catch { /* toast'a gerek yok; kartlar tire kalır */ }
  try {
    await loadOverdue();
  } catch { /* ödünç modülü boşken sessiz */ }
  try {
    const stats = await api.get("/api/stats");
    document.getElementById("oz-dusum").textContent = fmtCount(stats.discards ?? 0);
    if (stats.last_stocktake) {
      const st = stats.last_stocktake;
      document.getElementById("oz-sayim").innerHTML =
        `${esc(st.name)} (${(st.closed_at || "").slice(0, 10)}) — ` +
        `<strong>${st.missing} eksik</strong>, ${st.surplus} fazla`;
    }
  } catch { /* toast'a gerek yok; kartlar tire kalır */ }
  try {
    const loanStats = await api.get("/api/loans/stats");
    document.getElementById("oz-bugun-verilen").textContent = fmtCount(loanStats.today_out ?? 0);
    document.getElementById("oz-bugun-iade").textContent = fmtCount(loanStats.today_in ?? 0);
    document.getElementById("oz-bu-ay").textContent = fmtCount(loanStats.this_month ?? 0);
  } catch { /* ödünç modülü boşken sessiz */ }
  try {
    const start = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);
    const popular = await api.get(`/api/reports/popular-books?start=${start}&limit=5`);
    const top = popular.slice(0, 5);
    document.getElementById("oz-populer").innerHTML = top
      .map((row) => `<li>${esc(row.title)} — <strong>${fmtCount(row.loan_count)}</strong> ödünç</li>`)
      .join("");
    document.getElementById("oz-populer-bos").hidden = top.length > 0;
  } catch { /* rapor yoksa boş kalır */ }
}

export function leave() {}
