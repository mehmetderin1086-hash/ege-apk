// Yazdır: etiket/kart/gecikme sayfalarını yeni sekmede açar; kodsuz nüshalara kod verir.

import { api } from "../api.js";
import { esc, show, toast } from "../ui.js";

const $ = (id) => document.getElementById(id);
const err = (error) => toast(error.message || String(error), "error");

let bound = false;

function labelScope() {
  const scope = $("yz-etiket-kapsam").value;
  const location = $("yz-etiket-dolap").value;
  return { scope, location };
}

async function refreshMeta() {
  try {
    const [locations, classes] = await Promise.all([
      api.get("/api/meta/distinct/location"),
      api.get("/api/meta/classes"),
    ]);
    $("yz-etiket-dolap").innerHTML = locations
      .map((value) => `<option value="${esc(value)}">${esc(value)}</option>`)
      .join("");
    $("yz-kart-sinif").innerHTML =
      '<option value="">Tüm sınıflar</option>' +
      classes.map((value) => `<option value="${esc(value)}">${esc(value)}</option>`).join("");
  } catch { /* boş katalog */ }
  refreshMissingInfo().catch(() => {});
}

async function refreshMissingInfo() {
  // Kodsuz nüsha sayısı: eksik-ISBN süzgeci değil, envanter kodu — API'de
  // doğrudan sayaç yok; etiket sayfası uyarısıyla yetinmeyip burada da
  // gösterelim diye books araması yerine hafif bir yaklaşım: kod ver düğmesi
  // sonucu zaten sayı döndürür. Başlangıçta genel ipucu göster.
  $("yz-kodsuz-bilgi").textContent =
    'Etikette yalnız demirbaş numarası olan nüshalar basılır; "Kod ver" eksikleri tamamlar.';
}

function bind() {
  if (bound) return;
  bound = true;

  $("yz-etiket-kapsam").addEventListener("change", () => {
    show($("yz-etiket-dolap-kutu"), $("yz-etiket-kapsam").value === "location");
  });

  $("yz-kod-ver").addEventListener("click", async () => {
    try {
      const result = await api.post("/api/copies/assign-codes", labelScope());
      toast(
        result.assigned > 0
          ? `${result.assigned} nüshaya demirbaş numarası verildi ✓`
          : "Kapsamdaki tüm nüshaların numarası zaten var ✓",
        "success"
      );
    } catch (error) { err(error); }
  });

  $("yz-etiket-bas").addEventListener("click", () => {
    const { scope, location } = labelScope();
    const params = new URLSearchParams({ scope });
    if (scope === "location") params.set("location", location);
    window.open(`/print/labels?${params}`, "_blank");
  });

  $("yz-kart-bas").addEventListener("click", () => {
    const params = new URLSearchParams();
    const className = $("yz-kart-sinif").value;
    if (className) params.set("class_name", className);
    window.open(`/print/member-cards?${params}`, "_blank");
  });

  $("yz-gecikme-bas").addEventListener("click", () => {
    window.open("/print/overdue", "_blank");
  });
}

export function enter() {
  bind();
  refreshMeta();
}

export function leave() {}
