/* İnteraktif zihin haritası: SVG üstünde radyal yerleşim, pan/zoom, düğüm
   sürükleme; tıklanan düğümün kanıtı yan panelde açılır, "bu kavramdan sohbet
   başlat" sorusu app.js'e gider. Dış kütüphane yok: hiyerarşi + az sayıda
   çapraz kenar için kuvvet simülasyonu gerekmez, deterministik yerleşim yeter. */
(function () {
  "use strict";

  const SVG_NS = "http://www.w3.org/2000/svg";
  let dialog = null;
  let sahne = null; // <g> — pan/zoom bu grubun transform'unda
  let secim = null;
  let gorunum = { x: 0, y: 0, olcek: 1 };
  let dugumler = [];
  let kenarlar = [];

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function svgEl(tag, attrs = {}) {
    const node = document.createElementNS(SVG_NS, tag);
    Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, String(value)));
    return node;
  }

  function yerlesim(nodes) {
    // Kök merkezde; seviye 1 düğümleri çember üstünde, seviye 2 düğümleri
    // ebeveynlerinin açısal komşuluğunda daha geniş bir halkada.
    const merkez = { x: 0, y: 0 };
    const birler = nodes.filter(node => node.level === 1);
    const acilar = new Map();
    birler.forEach((node, sira) => {
      const aci = (2 * Math.PI * sira) / Math.max(1, birler.length) - Math.PI / 2;
      acilar.set(node.id, aci);
      node.x = merkez.x + 260 * Math.cos(aci);
      node.y = merkez.y + 260 * Math.sin(aci);
    });
    nodes.forEach(node => {
      if (node.level === 0) { node.x = merkez.x; node.y = merkez.y; }
      else if (node.level === 2) {
        const ebeveynAci = acilar.get(node.parent) ?? 0;
        const kardesler = nodes.filter(item => item.level === 2 && item.parent === node.parent);
        const sira = kardesler.indexOf(node);
        const yay = 0.55; // ebeveyn açısının iki yanına yayılım (radyan)
        const aci = ebeveynAci + (kardesler.length > 1 ? (sira / (kardesler.length - 1) - 0.5) * yay : 0);
        node.x = merkez.x + 470 * Math.cos(aci);
        node.y = merkez.y + 470 * Math.sin(aci);
      }
    });
  }

  function ciz() {
    sahne.replaceChildren();
    const indeks = new Map(dugumler.map(node => [node.id, node]));
    kenarlar.forEach(kenar => {
      const kaynak = indeks.get(kenar.source); const hedef = indeks.get(kenar.target);
      if (!kaynak || !hedef) return;
      const cizgi = svgEl("line", {
        x1: kaynak.x, y1: kaynak.y, x2: hedef.x, y2: hedef.y,
        class: kenar.kind === "capraz" ? "harita-kenar capraz" : "harita-kenar",
      });
      sahne.append(cizgi);
    });
    dugumler.forEach(node => {
      const grup = svgEl("g", { class: `harita-dugum seviye-${node.level}${secim === node.id ? " secili" : ""}`, transform: `translate(${node.x} ${node.y})` });
      grup.dataset.id = node.id;
      const genislik = Math.max(70, Math.min(240, String(node.label).length * 9 + 26));
      grup.append(svgEl("rect", { x: -genislik / 2, y: -20, width: genislik, height: 40, rx: 12 }));
      const yazi = svgEl("text", { "text-anchor": "middle", dy: 5 });
      yazi.textContent = String(node.label).length > 26 ? `${String(node.label).slice(0, 25)}…` : String(node.label);
      grup.append(yazi);
      sahne.append(grup);
    });
    sahne.setAttribute("transform", `translate(${gorunum.x} ${gorunum.y}) scale(${gorunum.olcek})`);
  }

  function paneliGuncelle(node) {
    const panel = dialog.querySelector(".harita-panel");
    panel.replaceChildren();
    if (!node) { panel.append(el("p", "muted", "Bir kavrama tıklayın: kanıtı burada açılır.")); return; }
    panel.append(el("h3", "", String(node.label)));
    const kanitlar = Array.isArray(node.evidence_chunk_ids) ? node.evidence_chunk_ids : [];
    const kanitSatiri = el("div", "harita-kanitlar");
    const benzersiz = [...new Set([node.citation_id, ...kanitlar].filter(Boolean))];
    benzersiz.slice(0, 6).forEach((kimlik, sira) => {
      const rozet = el("button", "citation-button", node.citation && sira === 0 ? node.citation : `kanıt ${sira + 1}`);
      rozet.type = "button";
      rozet.addEventListener("click", () => window.BioProf?.showCitation?.(kimlik));
      kanitSatiri.append(rozet);
    });
    panel.append(kanitSatiri);
    if (node.level > 0) {
      const sor = el("button", "button primary", "Bu kavramdan sohbet başlat");
      sor.type = "button";
      sor.addEventListener("click", () => {
        dialog.close();
        window.BioProf?.askFromViewer?.(`${node.label} kavramını seçili kaynaklara göre açıkla.`);
      });
      panel.append(sor);
    }
  }

  function etkilesimBagla(svg) {
    let aktif = null; // {tur: "pan"|"dugum", ...}
    svg.addEventListener("pointerdown", event => {
      const grup = event.target.closest(".harita-dugum");
      svg.setPointerCapture(event.pointerId);
      if (grup) {
        const node = dugumler.find(item => item.id === grup.dataset.id);
        aktif = { tur: "dugum", node, sonX: event.clientX, sonY: event.clientY, tasindi: false };
      } else {
        aktif = { tur: "pan", sonX: event.clientX, sonY: event.clientY };
      }
    });
    svg.addEventListener("pointermove", event => {
      if (!aktif) return;
      const dx = event.clientX - aktif.sonX; const dy = event.clientY - aktif.sonY;
      aktif.sonX = event.clientX; aktif.sonY = event.clientY;
      if (aktif.tur === "pan") { gorunum.x += dx; gorunum.y += dy; }
      else { aktif.node.x += dx / gorunum.olcek; aktif.node.y += dy / gorunum.olcek; if (Math.abs(dx) + Math.abs(dy) > 1) aktif.tasindi = true; }
      ciz();
    });
    svg.addEventListener("pointerup", event => {
      if (aktif?.tur === "dugum" && !aktif.tasindi) {
        secim = aktif.node.id;
        paneliGuncelle(aktif.node);
        ciz();
      }
      aktif = null;
      svg.releasePointerCapture?.(event.pointerId);
    });
    svg.addEventListener("wheel", event => {
      event.preventDefault();
      const carpan = event.deltaY < 0 ? 1.1 : 0.9;
      gorunum.olcek = Math.min(3, Math.max(0.3, gorunum.olcek * carpan));
      ciz();
    }, { passive: false });
  }

  function disaAktar(format) {
    const svg = dialog.querySelector("svg");
    const kopya = svg.cloneNode(true);
    kopya.setAttribute("xmlns", SVG_NS);
    const veri = new XMLSerializer().serializeToString(kopya);
    if (format === "svg") {
      indir(new Blob([veri], { type: "image/svg+xml" }), "zihin-haritasi.svg");
      return;
    }
    const resim = new Image();
    const url = URL.createObjectURL(new Blob([veri], { type: "image/svg+xml" }));
    resim.onload = () => {
      const tuval = document.createElement("canvas");
      tuval.width = svg.clientWidth * 2; tuval.height = svg.clientHeight * 2;
      const cizici = tuval.getContext("2d");
      cizici.fillStyle = "#101418"; cizici.fillRect(0, 0, tuval.width, tuval.height);
      cizici.drawImage(resim, 0, 0, tuval.width, tuval.height);
      URL.revokeObjectURL(url);
      tuval.toBlob(blob => blob && indir(blob, "zihin-haritasi.png"), "image/png");
    };
    resim.src = url;
  }

  function indir(blob, ad) {
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = ad;
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(link.href), 5000);
  }

  function ensureDialog() {
    if (dialog) return dialog;
    dialog = el("dialog", "harita-gorunum");
    const bar = el("div", "slide-viewer-bar");
    const baslik = el("strong", "harita-baslik", "Zihin haritası");
    const eylemler = el("div", "slide-viewer-actions");
    [["SVG indir", () => disaAktar("svg")], ["PNG indir", () => disaAktar("png")]].forEach(([ad, isleyici]) => {
      const dugme = el("button", "text-button", ad); dugme.type = "button";
      dugme.addEventListener("click", isleyici); eylemler.append(dugme);
    });
    const kapat = el("button", "icon-button", "×"); kapat.type = "button";
    kapat.setAttribute("aria-label", "Kapat");
    kapat.addEventListener("click", () => dialog.close());
    eylemler.append(kapat);
    bar.append(baslik, eylemler);
    const govde = el("div", "harita-govde");
    const svg = svgEl("svg", { class: "harita-svg", viewBox: "-600 -420 1200 840" });
    sahne = svgEl("g");
    svg.append(sahne);
    const panel = el("aside", "harita-panel");
    govde.append(svg, panel);
    const ipucu = el("footer", "slide-viewer-hint", "Sürükle: taşı · Tekerlek: yakınlaştır · Düğüme tıkla: kanıt · Esc: kapat");
    dialog.append(bar, govde, ipucu);
    etkilesimBagla(svg);
    document.body.append(dialog);
    return dialog;
  }

  function open(artifact) {
    const meta = artifact?.metadata || artifact || {};
    const yapili = meta.structured_data || meta;
    const nodes = Array.isArray(yapili.nodes) ? yapili.nodes.map(node => ({ ...node })) : [];
    if (!nodes.length) { window.BioProf?.toast?.("Bu çıktıda harita yapısı yok.", "error"); return; }
    // Eski (düz liste) kayıtlar da açılabilsin: level yoksa parent'tan türet.
    nodes.forEach(node => { if (node.level == null) node.level = node.parent == null ? 0 : 1; });
    dugumler = nodes;
    kenarlar = Array.isArray(yapili.edges)
      ? yapili.edges
      : nodes.filter(node => node.parent).map(node => ({ source: node.parent, target: node.id, kind: "hiyerarsi" }));
    gorunum = { x: 0, y: 0, olcek: 1 };
    secim = null;
    yerlesim(dugumler);
    ensureDialog();
    dialog.querySelector(".harita-baslik").textContent = meta.title || artifact.title || "Zihin haritası";
    paneliGuncelle(null);
    ciz();
    if (!dialog.open) dialog.showModal();
  }

  window.BioProfMindMap = { open };
})();
