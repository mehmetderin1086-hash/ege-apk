// Düşüm defteri: liste, geri alma, tutanak indirme.

import { api, pollJob } from "../api.js";
import { confirmBox, esc, fmtCount, show, toast } from "../ui.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");
const PAGE_SIZE = 50;

let bound = false;
let offset = 0;

function fmtDate(value) {
  return value ? value.slice(0, 10).split("-").reverse().join(".") : "—";
}

async function refreshList() {
  const data = await api.get(`/api/discards?limit=${PAGE_SIZE}&offset=${offset}`);
  $("du-tablo").innerHTML = data.items
    .map(
      (record) => `
      <tr>
        <td>${fmtDate(record.discarded_at)}</td>
        <td>${esc(record.inventory_code || "—")}</td>
        <td>${esc(record.title)}</td>
        <td>${esc(record.reason_label)}</td>
        <td>${esc(record.note || "—")}</td>
        <td>${record.copy_id ? `<button class="btn" data-restore="${record.id}">Geri Al</button>` : ""}</td>
      </tr>`
    )
    .join("");
  show($("du-bos"), data.total === 0);
  $("du-sayfa-bilgi").textContent =
    data.total === 0
      ? "0 kayıt"
      : `${offset + 1}–${Math.min(offset + PAGE_SIZE, data.total)} / ${fmtCount(data.total)}`;
  $("du-sayfa-geri").disabled = offset === 0;
  $("du-sayfa-ileri").disabled = offset + PAGE_SIZE >= data.total;
}

function bind() {
  if (bound) return;
  bound = true;

  $("du-tablo").addEventListener("click", async (event) => {
    const restoreId = event.target.dataset.restore;
    if (!restoreId) return;
    if (!(await confirmBox("Düşüm geri alınacak; nüsha yeniden envantere girecek. Emin misiniz?"))) return;
    try {
      await api.post(`/api/discards/${restoreId}/restore`);
      toast("Düşüm geri alındı ✓", "success");
      refreshList().catch(err);
    } catch (error) { err(error); }
  });

  $("du-sayfa-geri").addEventListener("click", () => { offset = Math.max(0, offset - PAGE_SIZE); refreshList().catch(err); });
  $("du-sayfa-ileri").addEventListener("click", () => { offset += PAGE_SIZE; refreshList().catch(err); });

  $("du-tutanak").addEventListener("click", async () => {
    try {
      await api.post("/api/discards/export");
      toast("Tutanak hazırlanıyor…");
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
  refreshList().catch(err);
}

export function leave() {}
