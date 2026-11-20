// Okuma raporları: en çok okuyanlar, sınıf bazlı, popüler kitaplar, aylık seri.

import { api, pollJob } from "../api.js";
import { esc, fmtCount, show, toast } from "../ui.js";
import { lineChart } from "../charts.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");

let bound = false;

function range() {
  return { start: $("rp-baslangic").value, end: $("rp-bitis").value };
}

function params() {
  const { start, end } = range();
  const search = new URLSearchParams();
  if (start) search.set("start", start);
  if (end) search.set("end", end);
  return search.toString() ? `?${search}` : "";
}

async function refresh() {
  const [readers, classes, books, monthly, quality] = await Promise.all([
    api.get(`/api/reports/top-readers${params()}`),
    api.get(`/api/reports/by-class${params()}`),
    api.get(`/api/reports/popular-books${params()}`),
    api.get("/api/reports/monthly"),
    api.get(`/api/reports/snapshot-quality${params()}`),
  ]);
  if (quality.estimated > 0) {
    $("rp-veri-kalitesi").textContent =
      `Veri kalitesi uyarısı: Bu aralıktaki ${fmtCount(quality.estimated)} kayıt ` +
      "v0.8 öncesinden taşındı. Üye ve sınıf bilgisi geçiş anındaki güncel " +
      "üye kaydından tahmin edilmiştir; tarihsel sınıf sonuçları kesin değildir.";
    show($("rp-veri-kalitesi"), true);
  } else {
    $("rp-veri-kalitesi").textContent = "";
    show($("rp-veri-kalitesi"), false);
  }
  $("rp-okuyanlar").innerHTML = readers
    .map(
      (row, index) => `
      <tr><td>${index + 1}</td><td>${esc(row.member_name)}</td>
      <td>${esc(row.class_name || (row.member_type === "staff" ? "Personel" : "—"))}</td>
      <td>${row.loan_count}</td></tr>`
    )
    .join("") || '<tr><td colspan="4" class="hint">Henüz ödünç kaydı yok.</td></tr>';
  $("rp-siniflar").innerHTML = classes
    .map(
      (row) => `<tr><td>${esc(row.class_name)}</td><td>${row.loan_count}</td><td>${row.reader_count}</td></tr>`
    )
    .join("") || '<tr><td colspan="3" class="hint">Henüz veri yok.</td></tr>';
  $("rp-kitaplar").innerHTML = books
    .map(
      (row, index) => `
      <tr><td>${index + 1}</td><td>${esc(row.title)}</td><td>${row.loan_count}</td><td>${row.reader_count}</td></tr>`
    )
    .join("") || '<tr><td colspan="4" class="hint">Henüz veri yok.</td></tr>';

  // Aylık seri artık SVG çizgi grafiği (charts.js yeniden kullanımı).
  lineChart(
    $("rp-aylik"),
    monthly.map((row) => ({ label: row.month.slice(2), value: row.loans }))
  );
}

function bind() {
  if (bound) return;
  bound = true;
  $("rp-uygula").addEventListener("click", () => refresh().catch(err));
  $("rp-excel").addEventListener("click", async () => {
    try {
      await api.post("/api/reports/export", range());
      toast("Rapor hazırlanıyor…");
      const done = await pollJob("/api/exports/status", { field: "export" });
      if (done?.status === "succeeded" && done.result?.download) {
        window.location.href = `/api/exports/download/${done.result.download}`;
      } else if (done?.error) {
        toast(done.error, "error", 6000);
      }
    } catch (error) { err(error); }
  });
}

export function enter() {
  bind();
  refresh().catch(err);
}

export function leave() {}
