// Ayarlar: okul adı, ödünç kuralları, yedekleme, tema, demirbaş serisi, ses.

import { api } from "../api.js";
import { confirmBox, esc, formSnapshot, readForm, show, toast } from "../ui.js";
import { applyTheme, currentTheme, updateSchoolName } from "../main.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");

const FIELD_SCOPE_LABELS = { any: "Her alan", title: "Başlık", author: "Yazar", publisher: "Yayınevi" };

let bound = false;
let settingsBaseline = "";
let settingsLoadGeneration = 0;

async function refresh() {
  const form = $("ay-form");
  const generation = ++settingsLoadGeneration;
  form.inert = true;
  form.setAttribute("aria-busy", "true");
  try {
    const settings = await api.get("/api/settings");
    // A response from an earlier visit must never overwrite a newer visit or
    // a form that has already been left. ``inert`` prevents editing during the
    // only interval in which the baseline is not yet known.
    if (generation !== settingsLoadGeneration) return;
    for (const [key, value] of Object.entries(settings)) {
      const input = form.querySelector(`[name="${key}"]`);
      if (!input) continue;
      if (input.type === "checkbox") input.checked = Boolean(value);
      else input.value = value ?? "";
    }
    $("ay-tema").value = currentTheme();
    settingsBaseline = formSnapshot(form);
    try {
      const code = await api.get("/api/quick/next-code");
      if (generation === settingsLoadGeneration) {
        $("ay-sonraki-kod").textContent = code.next_code;
      }
    } catch { /* önemsiz */ }
  } catch (error) {
    if (generation === settingsLoadGeneration) {
      settingsBaseline = formSnapshot(form);
    }
    throw error;
  } finally {
    if (generation === settingsLoadGeneration) {
      form.inert = false;
      form.removeAttribute("aria-busy");
    }
  }
}

async function save() {
  const form = $("ay-form");
  const values = readForm(form);
  for (const name of ["overdue_block", "voice_second_pass", "voice_prompt_bias"]) {
    values[name] = form.querySelector(`[name=${name}]`).checked;
  }
  const updated = await api.put("/api/settings", values);
  settingsBaseline = formSnapshot(form);
  toast("Ayarlar kaydedildi ✓", "success");
  updateSchoolName(updated.school_name);
}

// ── Sesli düzeltme sözlüğü ───────────────────────────

function renderAliasRow(alias) {
  return `<tr>
    <td>${esc(alias.heard)}</td>
    <td>${esc(alias.canonical)}</td>
    <td>${esc(FIELD_SCOPE_LABELS[alias.field_scope] ?? alias.field_scope)}</td>
    <td><button type="button" class="btn-icon" data-sil="${alias.id}" aria-label="Sözlük kaydını sil">🗑</button></td>
  </tr>`;
}

async function refreshAliases() {
  const aliases = await api.get("/api/voice/aliases");
  $("ay-sozluk-govde").innerHTML = aliases.map(renderAliasRow).join("");
  show($("ay-sozluk-bos"), aliases.length === 0);
}

export function isDirty() {
  return Boolean(settingsBaseline && settingsBaseline !== formSnapshot($("ay-form")));
}

export function canLeave() {
  if (!isDirty()) return Promise.resolve(true);
  return confirmBox("Ayarlarda kaydedilmemiş değişiklikler var. Vazgeçilsin mi?");
}

function bind() {
  if (bound) return;
  bound = true;
  $("ay-form").addEventListener("submit", (event) => {
    event.preventDefault();
    save().catch(err);
  });
  $("ay-tema").addEventListener("change", () => applyTheme($("ay-tema").value));

  $("ay-sozluk-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const values = readForm($("ay-sozluk-form"));
    try {
      await api.post("/api/voice/aliases", values);
      $("ay-sozluk-form").reset();
      toast("Sözlüğe eklendi ✓", "success");
      await refreshAliases();
    } catch (error) { err(error); }
  });
  $("ay-sozluk-govde").addEventListener("click", async (event) => {
    const id = event.target.dataset.sil;
    if (!id) return;
    try {
      await api.del(`/api/voice/aliases/${id}`);
      await refreshAliases();
    } catch (error) { err(error); }
  });
}

export function enter() {
  bind();
  refresh().catch(err);
  refreshAliases().catch(() => {});
}

export function leave() {
  settingsLoadGeneration += 1;
  $("ay-form").inert = false;
  $("ay-form").removeAttribute("aria-busy");
  settingsBaseline = "";
}
