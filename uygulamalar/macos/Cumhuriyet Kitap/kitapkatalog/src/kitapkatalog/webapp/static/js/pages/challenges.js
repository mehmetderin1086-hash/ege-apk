// Okuma yarışması: yarışma yönetimi, sınıf ligi, sıralama, sertifika sicili.

import { api } from "../api.js";
import { confirmBox, esc, show, toast } from "../ui.js";
import { barChart } from "../charts.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");

let bound = false;
let challenges = [];
let selectedId = null;

function daysRemaining(endDate) {
  const end = new Date(`${endDate}T23:59:59`);
  const diffMs = end.getTime() - Date.now();
  return Math.max(0, Math.ceil(diffMs / (24 * 60 * 60 * 1000)));
}

function fmtDate(value) {
  if (!value) return "—";
  return value.slice(0, 10).split("-").reverse().join(".");
}

async function refreshChallenges() {
  const data = await api.get("/api/challenges");
  challenges = data.items;
  const previous = selectedId;
  $("yrs-secim").innerHTML = challenges
    .map(
      (challenge) =>
        `<option value="${challenge.id}">${esc(challenge.name)}${challenge.status === "archived" ? " (arşiv)" : ""}</option>`
    )
    .join("");
  show($("yrs-bos"), challenges.length === 0);
  show($("yrs-pano"), challenges.length > 0);
  if (challenges.length === 0) { selectedId = null; return; }
  const stillExists = challenges.some((challenge) => challenge.id === previous);
  selectedId = stillExists
    ? previous
    : (challenges.find((challenge) => challenge.status === "active") || challenges[0]).id;
  $("yrs-secim").value = String(selectedId);
  await loadDashboard(selectedId);
}

async function loadDashboard(challengeId) {
  const data = await api.get(`/api/challenges/${challengeId}/standings`);
  const { challenge, standings, class_league: classLeague } = data;
  $("yrs-ad").textContent = challenge.name;
  $("yrs-bilgi").textContent =
    `${fmtDate(challenge.start_date)} – ${fmtDate(challenge.end_date)} · ` +
    (challenge.scope === "class" ? `Sınıf: ${challenge.class_name}` : "Tüm okul") +
    (challenge.status === "archived" ? " · Arşivlendi" : "");
  $("yrs-hedef").textContent = challenge.target_books;
  $("yrs-kalan-gun").textContent = daysRemaining(challenge.end_date);
  $("yrs-katilimci").textContent = standings.length;
  show($("yrs-arsivle"), challenge.status === "active");

  barChart(
    $("yrs-lig-grafik"),
    classLeague.map((row) => ({ label: row.class_name, value: row.total_books })),
    { ariaLabel: "Sınıf ligi — toplam okunan kitap" }
  );

  const top = standings.slice(0, 10);
  $("yrs-siralama").innerHTML = top
    .map(
      (row, index) => `
      <tr data-member="${row.member_id}">
        <td>${index + 1}</td>
        <td>${esc(row.member_name)}</td>
        <td>${esc(row.class_name || "—")}</td>
        <td>${esc(row.school_number || "—")}</td>
        <td>${row.book_count}</td>
        <td>${row.reached_target ? "🏆" : ""}</td>
        <td><button type="button" class="btn" data-sertifika="${row.member_id}" data-rank="${index + 1}">Sertifika</button></td>
      </tr>`
    )
    .join("") || '<tr><td colspan="7" class="hint">Henüz katılımcı yok.</td></tr>';
}

async function recordAndPrintCertificate(memberId, rank) {
  if (selectedId === null) return;
  try {
    await api.post(`/api/challenges/${selectedId}/certificates`, { member_id: memberId, rank });
    toast("Sertifika sicile kaydedildi ✓", "success");
    window.open(`/print/certificate?challenge_id=${selectedId}&member_id=${memberId}`, "_blank", "noopener");
  } catch (error) { err(error); }
}

// ── Yeni yarışma formu ────────────────────────────────

async function fillClassDatalist() {
  try {
    const classes = await api.get("/api/meta/classes");
    $("dl-yrs-sinif").innerHTML = classes.map((name) => `<option value="${esc(name)}">`).join("");
  } catch { /* boş katalog */ }
}

function toggleScopeField() {
  const isClass = $("yrs-kapsam").value === "class";
  $("yrs-sinif").disabled = !isClass;
  $("yrs-sinif").required = isClass;
  if (!isClass) $("yrs-sinif").value = "";
}

async function submitCreateForm(event) {
  event.preventDefault();
  const form = $("yrs-form");
  const values = Object.fromEntries(new FormData(form).entries());
  const payload = {
    name: values.name,
    start_date: values.start_date,
    end_date: values.end_date,
    target_books: Number(values.target_books),
    scope: values.scope,
    class_name: values.scope === "class" ? values.class_name : null,
  };
  try {
    const created = await api.post("/api/challenges", payload);
    toast("Yarışma oluşturuldu ✓", "success");
    form.reset();
    toggleScopeField();
    show($("yrs-form-kart"), false);
    selectedId = created.id;
    await refreshChallenges();
  } catch (error) { err(error); }
}

// ── Olay bağlama ───────────────────────────────────────

function bind() {
  if (bound) return;
  bound = true;

  $("yrs-yeni").addEventListener("click", () => show($("yrs-form-kart"), true));
  $("yrs-form-vazgec").addEventListener("click", () => {
    $("yrs-form").reset();
    toggleScopeField();
    show($("yrs-form-kart"), false);
  });
  $("yrs-form").addEventListener("submit", (event) => submitCreateForm(event));
  $("yrs-kapsam").addEventListener("change", toggleScopeField);

  $("yrs-secim").addEventListener("change", (event) => {
    selectedId = Number(event.target.value);
    loadDashboard(selectedId).catch(err);
  });

  $("yrs-arsivle").addEventListener("click", async () => {
    if (selectedId === null) return;
    if (!(await confirmBox("Bu yarışma arşivlenecek. Emin misiniz?"))) return;
    try {
      await api.patch(`/api/challenges/${selectedId}`, { status: "archived" });
      toast("Yarışma arşivlendi", "success");
      await refreshChallenges();
    } catch (error) { err(error); }
  });

  $("yrs-siralama").addEventListener("click", (event) => {
    const memberId = event.target.dataset.sertifika;
    if (!memberId) return;
    recordAndPrintCertificate(Number(memberId), Number(event.target.dataset.rank)).catch(err);
  });
}

export function enter() {
  bind();
  toggleScopeField();
  fillClassDatalist();
  refreshChallenges().catch(err);
}

export function leave() {
  show($("yrs-form-kart"), false);
}
