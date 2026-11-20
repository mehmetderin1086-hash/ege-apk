// Bağımlılıksız SVG grafikler (çevrimdışı ilke: harici kütüphane yok).

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (ch) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]
  );

// Basit çizgi grafik: points = [{ label, value }]
export function lineChart(container, points, { height = 180 } = {}) {
  if (!points || points.length === 0) {
    container.innerHTML = '<p class="hint">Henüz veri yok.</p>';
    return;
  }
  const width = 560;
  const pad = { top: 12, right: 12, bottom: 26, left: 46 };
  const innerW = width - pad.left - pad.right;
  const innerH = height - pad.top - pad.bottom;
  const max = Math.max(1, ...points.map((p) => p.value));
  const min = 0;
  const stepX = points.length > 1 ? innerW / (points.length - 1) : 0;
  const x = (index) => pad.left + index * stepX;
  const y = (value) => pad.top + innerH - ((value - min) / (max - min)) * innerH;

  const path = points
    .map((point, index) => `${index === 0 ? "M" : "L"}${x(index).toFixed(1)},${y(point.value).toFixed(1)}`)
    .join(" ");
  const area = `${path} L${x(points.length - 1).toFixed(1)},${y(0)} L${x(0)},${y(0)} Z`;

  // En fazla 6 x ekseni etiketi.
  const labelStep = Math.max(1, Math.ceil(points.length / 6));
  const xLabels = points
    .map((point, index) =>
      index % labelStep === 0 || index === points.length - 1
        ? `<text x="${x(index).toFixed(1)}" y="${height - 6}" text-anchor="middle" class="grafik-etiket">${esc(point.label)}</text>`
        : ""
    )
    .join("");
  const gridLines = [0, 0.5, 1]
    .map((ratio) => {
      const value = Math.round(max * ratio);
      const yPos = y(value);
      return `<line x1="${pad.left}" y1="${yPos}" x2="${width - pad.right}" y2="${yPos}" class="grafik-izgara"/>
              <text x="${pad.left - 6}" y="${yPos + 4}" text-anchor="end" class="grafik-etiket">${value}</text>`;
    })
    .join("");
  const dots = points
    .map(
      (point, index) =>
        `<circle cx="${x(index).toFixed(1)}" cy="${y(point.value).toFixed(1)}" r="2.5" class="grafik-nokta">
           <title>${esc(point.label)}: ${point.value}</title>
         </circle>`
    )
    .join("");

  container.innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Çizgi grafik" style="width:100%;height:auto">
      ${gridLines}
      <path d="${area}" class="grafik-alan"/>
      <path d="${path}" class="grafik-cizgi" fill="none"/>
      ${dots}
      ${xLabels}
    </svg>`;
}

// Basit dikey çubuk grafik: bars = [{ label, value }]
export function barChart(container, bars, { height = 180, ariaLabel = "Çubuk grafik" } = {}) {
  if (!bars || bars.length === 0) {
    container.innerHTML = '<p class="hint">Henüz veri yok.</p>';
    return;
  }
  const width = 560;
  const pad = { top: 12, right: 12, bottom: 40, left: 46 };
  const innerW = width - pad.left - pad.right;
  const innerH = height - pad.top - pad.bottom;
  const max = Math.max(1, ...bars.map((b) => b.value));
  const slot = innerW / bars.length;
  const barW = Math.min(48, slot * 0.7);
  const y = (value) => pad.top + innerH - (value / max) * innerH;

  const gridLines = [0, 0.5, 1]
    .map((ratio) => {
      const value = Math.round(max * ratio);
      const yPos = y(value);
      return `<line x1="${pad.left}" y1="${yPos}" x2="${width - pad.right}" y2="${yPos}" class="grafik-izgara"/>
              <text x="${pad.left - 6}" y="${yPos + 4}" text-anchor="end" class="grafik-etiket">${value}</text>`;
    })
    .join("");
  const rects = bars
    .map((bar, index) => {
      const cx = pad.left + slot * index + slot / 2;
      const h = Math.max(1, innerH - (y(bar.value) - pad.top));
      // Uzun etiketler 12 karakterde kısaltılır; tam değer <title> ile okunur kalır.
      const short = bar.label.length > 12 ? `${bar.label.slice(0, 11)}…` : bar.label;
      return `<rect x="${(cx - barW / 2).toFixed(1)}" y="${y(bar.value).toFixed(1)}" width="${barW.toFixed(1)}" height="${h.toFixed(1)}" rx="3" class="grafik-cubuk">
                <title>${esc(bar.label)}: ${bar.value}</title>
              </rect>
              <text x="${cx.toFixed(1)}" y="${height - 22}" text-anchor="middle" class="grafik-etiket">${esc(short)}</text>
              <text x="${cx.toFixed(1)}" y="${(y(bar.value) - 4).toFixed(1)}" text-anchor="middle" class="grafik-deger">${bar.value}</text>`;
    })
    .join("");

  container.innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(ariaLabel)}" style="width:100%;height:auto">
      ${gridLines}
      ${rects}
    </svg>`;
}

// Halka (donut) grafik: parts = [{ label, value }] — merkezde toplam.
export function donutChart(container, parts, { size = 180, ariaLabel = "Halka grafik" } = {}) {
  const cleaned = (parts || []).filter((p) => p.value > 0);
  if (cleaned.length === 0) {
    container.innerHTML = '<p class="hint">Henüz veri yok.</p>';
    return;
  }
  const total = cleaned.reduce((sum, p) => sum + p.value, 0);
  const cx = size / 2;
  const cy = size / 2;
  const radius = size / 2 - 10;
  const stroke = 22;
  const r = radius - stroke / 2;
  const circumference = 2 * Math.PI * r;

  let offset = 0;
  const segments = cleaned
    .map((part, index) => {
      const fraction = part.value / total;
      const length = fraction * circumference;
      const seg = `<circle cx="${cx}" cy="${cy}" r="${r.toFixed(1)}" fill="none"
        class="grafik-dilim grafik-dilim-${index % 6}" stroke-width="${stroke}"
        stroke-dasharray="${length.toFixed(2)} ${(circumference - length).toFixed(2)}"
        stroke-dashoffset="${(-offset).toFixed(2)}" transform="rotate(-90 ${cx} ${cy})">
        <title>${esc(part.label)}: ${part.value} (%${Math.round(fraction * 100)})</title>
      </circle>`;
      offset += length;
      return seg;
    })
    .join("");
  const legend = cleaned
    .map(
      (part, index) =>
        `<li><span class="grafik-lejant-renk grafik-dilim-${index % 6}"></span>${esc(part.label)} <b>${part.value}</b></li>`
    )
    .join("");

  container.innerHTML = `
    <div class="grafik-halka-sarici">
      <svg viewBox="0 0 ${size} ${size}" role="img" aria-label="${esc(ariaLabel)}" style="max-width:${size}px;width:100%;height:auto">
        ${segments}
        <text x="${cx}" y="${cy - 2}" text-anchor="middle" class="grafik-halka-toplam">${total}</text>
        <text x="${cx}" y="${cy + 16}" text-anchor="middle" class="grafik-etiket">toplam</text>
      </svg>
      <ul class="grafik-lejant">${legend}</ul>
    </div>`;
}
