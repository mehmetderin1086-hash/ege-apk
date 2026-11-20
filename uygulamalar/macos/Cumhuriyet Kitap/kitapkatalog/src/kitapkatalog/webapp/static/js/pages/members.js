// Üyeler: öğrenci/personel listesi, e-Okul içe aktarımı, yıl sonu sihirbazı.

import { api } from "../api.js";
import {
  confirmBox, debounce, esc, fillForm, fmtCount, formSnapshot, progressBar, readForm, show, toast,
} from "../ui.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");
const PAGE_SIZE = 50;

let bound = false;
let offset = 0;
let editingId = null;
let memberFormBaseline = "";
let stagedId = null;
let listController = null;
let currentSummaryId = null;

const TYPE_LABELS = { student: "Öğrenci", staff: "Personel" };

async function refreshList() {
  listController?.abort();
  const controller = new AbortController();
  listController = controller;
  const params = new URLSearchParams({
    q: $("uye-ara").value.trim(),
    class_name: $("uye-sinif").value,
    member_type: $("uye-tip").value,
    limit: PAGE_SIZE,
    offset,
  });
  const durum = $("uye-durum").value;
  if (durum !== "") params.set("active", durum);
  else params.set("active", "");
  let data;
  try {
    data = await api.get(`/api/members?${params}`, { signal: controller.signal });
  } catch (error) {
    if (error.name === "AbortError") return;
    throw error;
  }
  const rows = data.items
    .map(
      (member) => `
      <tr data-id="${member.id}" class="${member.is_active ? "" : "pasif"}"
          tabindex="0" role="button" data-key-activate aria-label="${esc(member.full_name)} üye özetini aç">
        <td>${esc(member.school_number || "—")}</td>
        <td>${esc(member.full_name)}</td>
        <td>${esc(member.class_name || "—")}</td>
        <td>${TYPE_LABELS[member.member_type] || member.member_type}</td>
        <td>${member.is_active ? "Aktif" : "Pasif"}</td>
        <td class="col-islem">
          <button class="btn" data-edit="${member.id}">Düzenle</button>
          <button class="btn" data-toggle="${member.id}" data-durum="${member.is_active ? 1 : 0}">${member.is_active ? "Pasifleştir" : "Aktifleştir"}</button>
          <button class="btn-icon" data-del="${member.id}" title="Sil"
                  aria-label="${esc(member.full_name)} üyesini sil">🗑️</button>
        </td>
      </tr>`
    )
    .join("");
  $("uye-tablo").innerHTML = rows;
  show($("uye-tablo-sarici"), data.total > 0);
  show($("uye-bos"), data.total === 0);
  $("uye-sayfa-bilgi").textContent =
    data.total === 0
      ? "0 üye"
      : `${offset + 1}–${Math.min(offset + PAGE_SIZE, data.total)} / ${fmtCount(data.total)}`;
  $("uye-sayfa-geri").disabled = offset === 0;
  $("uye-sayfa-ileri").disabled = offset + PAGE_SIZE >= data.total;
}

async function refreshClassFilter() {
  try {
    const classes = await api.get("/api/meta/classes");
    const current = $("uye-sinif").value;
    $("uye-sinif").innerHTML =
      '<option value="">Tüm sınıflar</option>' +
      classes.map((name) => `<option value="${esc(name)}">${esc(name)}</option>`).join("");
    $("uye-sinif").value = current;
  } catch { /* boş katalog */ }
}

function fmtDate(value) {
  if (!value) return "—";
  return value.slice(0, 10).split("-").reverse().join(".");
}

async function renderBlockHistory(memberId) {
  const blocks = await api.get(`/api/members/${memberId}/blocks`);
  $("ud-yasak-liste").innerHTML = blocks
    .map((block) => {
      const kind = block.kind === "manual" ? "Elle yasak" : "Otomatik af (gecikme cezası söndürüldü)";
      const durum = block.lifted_at
        ? `kaldırıldı ${fmtDate(block.lifted_at)}`
        : block.end_date
          ? `bitiş ${fmtDate(block.end_date)}`
          : "süresiz";
      return `<li>${esc(kind)} — ${esc(block.reason || "gerekçe belirtilmedi")} · ${durum}
        ${!block.lifted_at
          ? `<button class="btn-icon" type="button" data-yasak-kaldir="${block.id}" aria-label="Yasağı kaldır">✕</button>`
          : ""}</li>`;
    })
    .join("");
  show($("ud-yasak-bos"), blocks.length === 0);
}

async function openSummary(memberId) {
  const data = await api.get(`/api/members/${memberId}/summary`);
  currentSummaryId = memberId;
  const member = data.member;
  $("ud-ad").textContent = member.full_name;
  $("ud-kimlik").textContent = [
    member.school_number ? `No ${member.school_number}` : null,
    member.class_name || (member.member_type === "staff" ? "Personel" : null),
    member.is_active ? "Aktif" : "Pasif",
  ].filter(Boolean).join(" · ");
  const ceza = $("ud-ceza");
  if (data.penalty_end) {
    ceza.textContent = `⛔ Geç iade cezası: ${fmtDate(data.penalty_end)} tarihine kadar ödünç alamaz.`;
    show(ceza, true);
  } else show(ceza, false);
  show($("ud-af-buton"), Boolean(data.penalty_end));
  const yasak = $("ud-yasak");
  if (data.active_block) {
    yasak.textContent = `🚫 Elle yasaklı: ${data.active_block.reason || "gerekçe belirtilmedi"}`;
    show(yasak, true);
  } else show(yasak, false);
  await renderBlockHistory(memberId);
  $("ud-toplam").textContent = data.totals.total;
  $("ud-iade").textContent = data.totals.returned;
  $("ud-gec").textContent = data.totals.late;
  $("ud-aktif-sayi").textContent = data.overdue_count;
  show($("ud-aktif-sayi"), data.overdue_count > 0);
  $("ud-aktif").innerHTML = data.active
    .map(
      (loan) =>
        `<li>${esc(loan.title)} · son gün ${fmtDate(loan.due_at)}${
          loan.overdue ? ` <span class="geciken">${loan.days_overdue} gün gecikti</span>` : ""
        }</li>`
    )
    .join("");
  show($("ud-aktif-bos"), data.active.length === 0);
  $("ud-gecmis").innerHTML = data.history
    .filter((loan) => loan.returned_at)
    .map((loan) => `<li>${esc(loan.title)} · ${fmtDate(loan.loaned_at)} → ${fmtDate(loan.returned_at)}</li>`)
    .join("");
  show($("ud-gecmis-bos"), data.history.filter((loan) => loan.returned_at).length === 0);
  await renderReadingLists(memberId);
  show($("uye-detay"), true);
}

async function renderReadingLists(memberId) {
  const data = await api.get(`/api/members/${memberId}/reading-lists`);
  $("ud-listeler").innerHTML = data.items
    .map(
      (entry) => `<li>${esc(entry.list_name)} — ${entry.completed}/${entry.total}
        ${progressBar(entry.fraction)}</li>`
    )
    .join("");
  show($("ud-listeler-bos"), data.items.length === 0);
}

export function isDirty() {
  return Boolean(
    !$("uye-form-kart").hidden && memberFormBaseline &&
    memberFormBaseline !== formSnapshot($("uye-form"))
  );
}

export function canLeave() {
  if (!isDirty()) return Promise.resolve(true);
  return confirmBox("Üye formunda kaydedilmemiş değişiklikler var. Vazgeçilsin mi?");
}

async function openForm(member = null) {
  if (isDirty() && !(await canLeave())) return false;
  editingId = member ? member.id : null;
  $("uye-form-baslik").textContent = member ? `Üyeyi Düzenle: ${member.full_name}` : "Yeni Üye";
  $("uye-form").reset();
  if (member) fillForm($("uye-form"), member);
  memberFormBaseline = formSnapshot($("uye-form"));
  show($("uye-form-kart"), true);
  $("uye-form").querySelector("[name=first_name]").focus();
  return true;
}

async function grantAmnesty() {
  if (!currentSummaryId) return;
  const reason = window.prompt("Af gerekçesi (zorunlu):");
  if (reason === null) return;
  if (!reason.trim()) { toast("Af gerekçesi zorunludur", "error"); return; }
  if (!(await confirmBox("Bu üyenin süren geç iade cezası kaldırılacak. Emin misiniz?"))) return;
  try {
    await api.post(`/api/members/${currentSummaryId}/amnesty`, { reason: reason.trim() });
    toast("Af uygulandı ✓", "success");
    await openSummary(currentSummaryId);
  } catch (error) { err(error); }
}

async function submitBlockForm(event) {
  event.preventDefault();
  if (!currentSummaryId) return;
  const values = readForm($("ud-yasak-form"));
  if (!values.reason.trim()) { toast("Yasak gerekçesi zorunludur", "error"); return; }
  if (!(await confirmBox("Bu üye elle yasaklanacak; iade edilene/kaldırılana kadar ödünç alamaz. Emin misiniz?"))) {
    return;
  }
  try {
    await api.post(`/api/members/${currentSummaryId}/blocks`, {
      reason: values.reason.trim(),
      end_date: values.end_date || null,
    });
    toast("Üye yasaklandı", "success");
    $("ud-yasak-form").reset();
    await openSummary(currentSummaryId);
  } catch (error) { err(error); }
}

async function liftBlock(blockId) {
  if (!currentSummaryId) return;
  if (!(await confirmBox("Bu yasak kaldırılacak. Emin misiniz?"))) return;
  try {
    await api.post(`/api/members/${currentSummaryId}/blocks/${blockId}/lift`, {});
    toast("Yasak kaldırıldı ✓", "success");
    await openSummary(currentSummaryId);
  } catch (error) { err(error); }
}

async function saveForm() {
  const values = readForm($("uye-form"));
  if (editingId) {
    await api.patch(`/api/members/${editingId}`, values);
    toast("Üye güncellendi ✓", "success");
  } else {
    await api.post("/api/members", values);
    toast("Üye eklendi ✓", "success");
  }
  memberFormBaseline = "";
  show($("uye-form-kart"), false);
  await Promise.all([refreshList(), refreshClassFilter()]);
}

function reportText(report) {
  const parts = [
    `${report.imported} yeni`,
    `${report.updated} güncellendi`,
  ];
  if (report.deactivated) parts.push(`${report.deactivated} pasife alındı`);
  if (report.skipped) parts.push(`${report.skipped} atlandı`);
  if (report.needs_resolution?.length) {
    parts.push(`${report.needs_resolution.length} açık ödünçli öğrenci işlem bekliyor`);
  }
  let text = parts.join(", ") + ".";
  if (report.errors?.length) {
    text += ` Uyarılar: ${report.errors.slice(0, 5).join(" · ")}`;
    if (report.errors.length > 5) text += ` (+${report.errors.length - 5})`;
  }
  return text;
}

function renderPromoteResolutions(items = []) {
  const resolutions = Array.isArray(items) ? items : [];
  $("uye-promote-cozum-liste").innerHTML = resolutions
    .map((item) =>
      `<li><strong>${esc(item.full_name)}</strong> ` +
      `(${esc(item.school_number || "numarasız")}, ${esc(item.class_name || "sınıfsız")}) — ` +
      `${Number(item.active_loan_count || 0)} kitap üzerinde</li>`
    )
    .join("");
  show($("uye-promote-cozum"), resolutions.length > 0);
}

async function importEokul() {
  const input = $("uye-eokul-dosya");
  if (!input.files.length) { toast("Önce .xlsx dosyası seçin", "error"); return; }
  const form = new FormData();
  form.append("file", input.files[0]);
  $("uye-eokul-sonuc").textContent = "Yükleniyor…";
  try {
    const report = await api.upload("/api/members/import", form);
    $("uye-eokul-sonuc").textContent = reportText(report);
    toast("Liste içe aktarıldı ✓", "success");
    input.value = "";
    await Promise.all([refreshList(), refreshClassFilter()]);
  } catch (error) {
    $("uye-eokul-sonuc").textContent = "";
    err(error);
  }
}

async function promotePreview() {
  const input = $("uye-promote-dosya");
  if (!input.files.length) { toast("Önce .xlsx dosyası seçin", "error"); return; }
  if (stagedId) {
    try { await api.del(`/api/members/promote/staged/${stagedId}`); }
    catch { /* süre aşımı temizliği zaten sunucuda çalışır */ }
    stagedId = null;
  }
  const form = new FormData();
  form.append("file", input.files[0]);
  try {
    const plan = await api.upload("/api/members/promote/preview", form);
    stagedId = plan.staged_id;
    $("uye-promote-ozet").textContent =
      `${plan.update.length} sınıf güncellenecek · ${plan.add.length} yeni öğrenci eklenecek · ` +
      `${plan.deactivate.length} öğrenci pasife alınacak (mezun/nakil) · ` +
      `${plan.needs_resolution?.length || 0} açık ödünçli öğrenci aktif tutulacak.`;
    const detail = [];
    for (const item of plan.deactivate.slice(0, 10)) {
      detail.push(`<li>Pasif: ${esc(item.full_name)} (${esc(item.school_number)}, ${esc(item.class_name || "—")})</li>`);
    }
    if (plan.deactivate.length > 10) detail.push(`<li>… ve ${plan.deactivate.length - 10} öğrenci daha</li>`);
    for (const error of plan.errors.slice(0, 5)) detail.push(`<li>⚠️ ${esc(error)}</li>`);
    $("uye-promote-detay").innerHTML = detail.join("");
    renderPromoteResolutions(plan.needs_resolution);
    show($("uye-promote-uygula"), true);
    show($("uye-promote-vazgec"), true);
    show($("uye-promote-onizleme"), true);
  } catch (error) { err(error); }
}

async function promoteCancel() {
  if (stagedId) await api.del(`/api/members/promote/staged/${stagedId}`);
  stagedId = null;
  $("uye-promote-dosya").value = "";
  renderPromoteResolutions([]);
  show($("uye-promote-onizleme"), false);
  toast("Önizleme dosyası silindi", "success");
}

async function promoteApply() {
  if (!stagedId) return;
  const message =
    "Yıl sonu atlatma uygulanacak: " + $("uye-promote-ozet").textContent + " Emin misiniz?";
  if (!(await confirmBox(message))) return;
  try {
    const report = await api.post("/api/members/promote/apply", { staged_id: stagedId });
    toast(`Yıl sonu uygulandı ✓ ${reportText(report)}`, "success");
    stagedId = null;
    $("uye-promote-dosya").value = "";
    const resolutions = report.needs_resolution || [];
    if (resolutions.length > 0) {
      $("uye-promote-ozet").textContent =
        `Güvenli değişiklikler uygulandı. ${resolutions.length} öğrenci, ` +
        "üzerindeki kitaplar iade edilene kadar aktif tutuldu.";
      $("uye-promote-detay").replaceChildren();
      renderPromoteResolutions(resolutions);
      show($("uye-promote-uygula"), false);
      show($("uye-promote-vazgec"), false);
      show($("uye-promote-onizleme"), true);
    } else {
      renderPromoteResolutions([]);
      show($("uye-promote-onizleme"), false);
    }
    await Promise.all([refreshList(), refreshClassFilter()]);
  } catch (error) { err(error); }
}

function bind() {
  if (bound) return;
  bound = true;

  const reload = () => { offset = 0; refreshList().catch(err); };
  $("uye-ara").addEventListener("input", debounce(reload, 250));
  for (const id of ["uye-sinif", "uye-tip", "uye-durum"]) {
    $(id).addEventListener("change", reload);
  }
  $("uye-sayfa-geri").addEventListener("click", () => {
    offset = Math.max(0, offset - PAGE_SIZE);
    refreshList().catch(err);
  });
  $("uye-sayfa-ileri").addEventListener("click", () => {
    offset += PAGE_SIZE;
    refreshList().catch(err);
  });

  $("uye-yeni").addEventListener("click", () => openForm().catch(err));
  $("uye-form-vazgec").addEventListener("click", async () => {
    if (!(await canLeave())) return;
    memberFormBaseline = "";
    editingId = null;
    show($("uye-form-kart"), false);
  });
  $("uye-form").addEventListener("submit", (event) => {
    event.preventDefault();
    saveForm().catch(err);
  });
  $("uye-tablo").addEventListener("click", async (event) => {
    const editId = event.target.dataset.edit;
    const toggleId = event.target.dataset.toggle;
    const delId = event.target.dataset.del;
    try {
      if (editId) {
        await openForm(await api.get(`/api/members/${editId}`));
        return;
      }
      if (toggleId) {
        const active = event.target.dataset.durum === "1";
        await api.patch(`/api/members/${toggleId}`, { is_active: !active });
        toast(active ? "Üye pasifleştirildi" : "Üye aktifleştirildi ✓", "success");
        await refreshList();
        return;
      }
      if (delId) {
        const name = event.target.closest("tr")?.children[1]?.textContent || "Üye";
        if (!(await confirmBox(`"${name}" kalıcı olarak silinecek. Emin misiniz?`))) return;
        await api.del(`/api/members/${delId}`);
        toast("Üye silindi", "success");
        await refreshList();
        return;
      }
      const row = event.target.closest("tr[data-id]");
      if (row) await openSummary(Number(row.dataset.id));
    } catch (error) { err(error); }
  });
  $("uye-detay-kapat").addEventListener("click", () => {
    show($("uye-detay"), false);
    currentSummaryId = null;
  });
  $("ud-af-buton").addEventListener("click", () => grantAmnesty().catch(err));
  $("ud-yasak-form").addEventListener("submit", (event) => submitBlockForm(event).catch(err));
  $("ud-yasak-liste").addEventListener("click", (event) => {
    const liftId = event.target.dataset.yasakKaldir;
    if (liftId) liftBlock(Number(liftId)).catch(err);
  });

  $("uye-eokul-yukle").addEventListener("click", () => importEokul());
  $("uye-promote-onizle").addEventListener("click", () => promotePreview());
  $("uye-promote-uygula").addEventListener("click", () => promoteApply());
  $("uye-promote-vazgec").addEventListener("click", () => promoteCancel().catch(err));
}

export function enter() {
  bind();
  refreshList().catch(err);
  refreshClassFilter();
}

export function leave() {
  listController?.abort();
  memberFormBaseline = "";
  editingId = null;
  currentSummaryId = null;
  show($("uye-form-kart"), false);
  show($("uye-detay"), false);
}
