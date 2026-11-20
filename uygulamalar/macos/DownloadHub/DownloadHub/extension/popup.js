"use strict";

const state = {
  online: false,
  paired: false,
  resources: [],
  inspectedUrl: null,
  selected: new Set()
};

const GROUPS = [
  ["video", "Videolar"],
  ["audio", "Sesler"],
  ["image", "Resimler"],
  ["document", "Belgeler ve dosyalar"],
  ["other", "Diğer bağlantılar"]
];

const elements = {};

document.addEventListener("DOMContentLoaded", () => {
  for (const id of [
    "serviceStatus", "statusDot", "statusText", "refreshStatus", "pairingPanel",
    "pairedPanel", "pairCode", "completePairing", "startPairing", "revokePairing",
    "inspectPage", "scanPage", "messageBox", "inspectionPanel", "inspectionTitle",
    "inspectionDetails", "enqueueInspected", "resourcesPanel", "pageSummary",
    "resourceGroups", "selectAll", "selectionCount", "enqueueSelected", "openApp"
  ]) {
    elements[id] = document.getElementById(id);
  }

  elements.refreshStatus.addEventListener("click", refreshStatus);
  elements.completePairing.addEventListener("click", completePairing);
  elements.startPairing.addEventListener("click", startPairing);
  elements.revokePairing.addEventListener("click", revokePairing);
  elements.inspectPage.addEventListener("click", inspectActivePage);
  elements.scanPage.addEventListener("click", scanActivePage);
  elements.enqueueInspected.addEventListener("click", enqueueInspected);
  elements.selectAll.addEventListener("click", toggleSelectAll);
  elements.enqueueSelected.addEventListener("click", enqueueSelected);
  elements.openApp.addEventListener("click", openApp);
  elements.pairCode.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      completePairing();
    }
  });

  refreshStatus();
});

function sendMessage(type, payload = {}) {
  return new Promise((resolve, reject) => {
    if (!globalThis.chrome || !chrome.runtime || !chrome.runtime.sendMessage) {
      reject(new Error("Eklenti arka plan hizmetine ulaşılamadı. Eklentiyi yeniden yükleyin."));
      return;
    }
    chrome.runtime.sendMessage({ type, ...payload }, (response) => {
      if (chrome.runtime.lastError) {
        reject(new Error("Eklenti arka plan hizmetine ulaşılamadı. Eklentiyi yeniden yükleyin."));
        return;
      }
      if (!response || !response.ok) {
        const error = new Error(
          response && response.error && response.error.message
            ? response.error.message
            : "Beklenmeyen bir eklenti hatası oluştu."
        );
        error.code = response && response.error ? response.error.code : "unknown";
        reject(error);
        return;
      }
      resolve(response.data);
    });
  });
}

function setBusy(element, busy, busyText) {
  if (!element) {
    return;
  }
  if (busy) {
    element.dataset.originalText = element.textContent;
    if (busyText) {
      element.textContent = busyText;
    }
    element.disabled = true;
    element.classList.add("busy");
  } else {
    if (element.dataset.originalText) {
      element.textContent = element.dataset.originalText;
      delete element.dataset.originalText;
    }
    element.disabled = false;
    element.classList.remove("busy");
  }
}

function showMessage(message, tone = "info") {
  elements.messageBox.textContent = message;
  elements.messageBox.className = `message-box ${tone}`;
  elements.messageBox.hidden = false;
}

function hideMessage() {
  elements.messageBox.hidden = true;
  elements.messageBox.textContent = "";
}

function friendlyError(error) {
  return error && error.message
    ? error.message
    : "Beklenmeyen bir hata oluştu. DownloadHub'ı yeniden başlatıp tekrar deneyin.";
}

function updateAvailability() {
  const enabled = state.online && state.paired;
  elements.inspectPage.disabled = !enabled;
  elements.scanPage.disabled = !enabled;
  elements.pairingPanel.hidden = state.paired;
  elements.pairedPanel.hidden = !state.paired;
}

async function refreshStatus() {
  elements.statusDot.className = "status-dot checking";
  elements.statusText.textContent = "Bağlantı kontrol ediliyor…";
  setBusy(elements.refreshStatus, true);
  try {
    const status = await sendMessage("STATUS");
    state.online = Boolean(status.online);
    state.paired = Boolean(status.paired);
    elements.statusDot.className = `status-dot ${state.online ? "online" : "offline"}`;
    elements.statusText.textContent = state.online
      ? (state.paired ? "Uygulama açık · eşleştirildi" : "Uygulama açık · eşleştirme gerekli")
      : "Uygulama çevrimdışı";
    if (!state.online) {
      elements.messageBox.dataset.statusError = "true";
      showMessage(
        "DownloadHub'a bağlanılamadı. Masaüstü uygulamasını başlatıp yeniden kontrol edin.",
        "error"
      );
    } else {
      if (elements.messageBox.dataset.statusError === "true") {
        hideMessage();
      }
      delete elements.messageBox.dataset.statusError;
    }
    updateAvailability();
  } catch (error) {
    state.online = false;
    elements.statusDot.className = "status-dot offline";
    elements.statusText.textContent = "Bağlantı denetlenemedi";
    elements.messageBox.dataset.statusError = "true";
    showMessage(friendlyError(error), "error");
    updateAvailability();
  } finally {
    setBusy(elements.refreshStatus, false);
  }
}

async function openApp() {
  try {
    await sendMessage("OPEN_APP");
  } catch (error) {
    showMessage(friendlyError(error), "error");
  }
}

async function startPairing() {
  hideMessage();
  setBusy(elements.startPairing, true, "Kod oluşturuluyor…");
  try {
    const result = await sendMessage("PAIR_START");
    if (result.code) {
      elements.pairCode.value = result.code;
      elements.pairCode.focus();
      elements.pairCode.select();
      showMessage(
        result.expiresAt
          ? `Kod oluşturuldu. ${formatExpiry(result.expiresAt)} tarihine kadar geçerli.`
          : "Kod oluşturuldu. Eşleştirmek için Eşleştir düğmesine basın.",
        "success"
      );
    } else {
      showMessage(
        "Eşleştirme isteği açıldı. Web panelinde gösterilen kodu yukarıdaki alana girin.",
        "info"
      );
    }
  } catch (error) {
    showMessage(friendlyError(error), "error");
  } finally {
    setBusy(elements.startPairing, false);
  }
}

function formatExpiry(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "Kısa süre"
    : new Intl.DateTimeFormat("tr-TR", { hour: "2-digit", minute: "2-digit" }).format(date);
}

async function completePairing() {
  const code = elements.pairCode.value.trim();
  if (!code) {
    showMessage("Web panelindeki eşleştirme kodunu girin.", "error");
    elements.pairCode.focus();
    return;
  }
  hideMessage();
  setBusy(elements.completePairing, true, "Bağlanıyor…");
  try {
    await sendMessage("PAIR_COMPLETE", { code });
    elements.pairCode.value = "";
    state.paired = true;
    showMessage("Eklenti DownloadHub ile güvenle eşleştirildi.", "success");
    await refreshStatus();
  } catch (error) {
    showMessage(friendlyError(error), "error");
  } finally {
    setBusy(elements.completePairing, false);
  }
}

async function revokePairing() {
  hideMessage();
  setBusy(elements.revokePairing, true, "Kaldırılıyor…");
  try {
    await sendMessage("PAIR_REVOKE");
    state.paired = false;
    state.resources = [];
    state.selected.clear();
    elements.resourcesPanel.hidden = true;
    elements.inspectionPanel.hidden = true;
    showMessage("Eşleştirme kaldırıldı. Bu eklenti artık indirme gönderemez.", "success");
    updateAvailability();
  } catch (error) {
    state.paired = false;
    updateAvailability();
    showMessage(friendlyError(error), "error");
  } finally {
    setBusy(elements.revokePairing, false);
  }
}

async function inspectActivePage() {
  hideMessage();
  elements.inspectionPanel.hidden = true;
  setBusy(elements.inspectPage, true, "Sayfa inceleniyor…");
  try {
    const data = await sendMessage("INSPECT_ACTIVE_PAGE");
    state.inspectedUrl = data.url;
    renderInspection(data.result, data.url);
    elements.inspectionPanel.hidden = false;
    showMessage("İnceleme tamamlandı. Seçenekleri web panelinde ayrıntılandırabilirsiniz.", "success");
  } catch (error) {
    showMessage(friendlyError(error), "error");
  } finally {
    setBusy(elements.inspectPage, false);
  }
}

function firstValue(object, keys) {
  for (const key of keys) {
    const path = key.split(".");
    let value = object;
    for (const segment of path) {
      value = value && typeof value === "object" ? value[segment] : undefined;
    }
    if (value !== undefined && value !== null && value !== "") {
      return value;
    }
  }
  return null;
}

function renderInspection(result, url) {
  const payload = result && result.data ? result.data : (result || {});
  const title = firstValue(payload, ["title", "name", "metadata.title"]) || "Kaynak hazır";
  const type = firstValue(payload, ["source_type", "kind", "engine", "type"]) || "Otomatik algılandı";
  const duration = firstValue(payload, ["duration_string", "durationText"]);
  const size = firstValue(payload, ["filesize_approx", "content_length", "size"]);
  const entries = firstValue(payload, ["entries", "items"]);

  elements.inspectionTitle.textContent = String(title).slice(0, 100);
  elements.inspectionDetails.replaceChildren();
  addDetail("Tür", formatType(type));
  if (duration) {
    addDetail("Süre", String(duration));
  }
  if (size && Number.isFinite(Number(size))) {
    addDetail("Yaklaşık boyut", formatBytes(Number(size)));
  }
  if (Array.isArray(entries)) {
    addDetail("Öğe", `${entries.length} içerik`);
  }
  addDetail("Adres", displayUrl(url));
}

function addDetail(label, value) {
  const term = document.createElement("dt");
  term.textContent = label;
  const description = document.createElement("dd");
  description.textContent = value;
  description.title = value;
  elements.inspectionDetails.append(term, description);
}

function formatType(value) {
  const labels = {
    media: "Medya",
    video: "Video",
    audio: "Ses",
    direct: "Doğrudan dosya",
    aria2: "Doğrudan dosya",
    "yt-dlp": "Medya"
  };
  return labels[String(value).toLowerCase()] || String(value);
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes < 0) {
    return "Bilinmiyor";
  }
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${new Intl.NumberFormat("tr-TR", { maximumFractionDigits: unit ? 1 : 0 }).format(value)} ${units[unit]}`;
}

async function enqueueInspected() {
  if (!state.inspectedUrl) {
    showMessage("Önce geçerli sayfayı inceleyin.", "error");
    return;
  }
  setBusy(elements.enqueueInspected, true, "Ekleniyor…");
  try {
    const result = await sendMessage("ENQUEUE_MANY", {
      items: [{ url: state.inspectedUrl, pageUrl: state.inspectedUrl, kind: "video" }]
    });
    reportEnqueueResult(result);
  } catch (error) {
    showMessage(friendlyError(error), "error");
  } finally {
    setBusy(elements.enqueueInspected, false);
  }
}

async function scanActivePage() {
  hideMessage();
  elements.resourcesPanel.hidden = true;
  setBusy(elements.scanPage, true, "Kaynaklar taranıyor…");
  try {
    const scan = await sendMessage("SCAN_ACTIVE_PAGE");
    state.resources = scan.resources || [];
    state.selected.clear();
    renderResources(scan);
    elements.resourcesPanel.hidden = false;
    if (state.resources.length === 0) {
      showMessage(
        "Bu sayfada indirilebilir kaynak bulunamadı. Sayfanın kendisini incelemeyi deneyin.",
        "info"
      );
    } else {
      showMessage(`${state.resources.length} indirilebilir kaynak bulundu.`, "success");
    }
  } catch (error) {
    showMessage(friendlyError(error), "error");
  } finally {
    setBusy(elements.scanPage, false);
  }
}

function renderResources(scan) {
  elements.resourceGroups.replaceChildren();
  elements.pageSummary.textContent = scan.page && scan.page.title
    ? scan.page.title
    : "Geçerli sayfa";
  elements.pageSummary.title = scan.page && scan.page.canonicalUrl
    ? scan.page.canonicalUrl
    : "";

  GROUPS.forEach(([kind, label], groupIndex) => {
    const resources = state.resources
      .map((resource, index) => ({ resource, index }))
      .filter((entry) => entry.resource.kind === kind);
    if (resources.length === 0) {
      return;
    }

    const details = document.createElement("details");
    details.className = "resource-group";
    details.open = groupIndex < 2 || resources.length <= 8;
    const summary = document.createElement("summary");
    const summaryLabel = document.createElement("span");
    summaryLabel.textContent = label;
    const count = document.createElement("span");
    count.className = "resource-count";
    count.textContent = String(resources.length);
    summary.append(summaryLabel, count);

    const list = document.createElement("div");
    list.className = "resource-list";
    for (const { resource, index } of resources) {
      list.append(createResourceRow(resource, index));
    }
    details.append(summary, list);
    elements.resourceGroups.append(details);
  });

  updateSelectionUi();
}

function createResourceRow(resource, index) {
  const row = document.createElement("label");
  row.className = "resource-row";

  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.value = String(index);
  checkbox.setAttribute("aria-label", `${resource.title || "Kaynak"} seç`);
  checkbox.addEventListener("change", () => {
    if (checkbox.checked) {
      state.selected.add(index);
    } else {
      state.selected.delete(index);
    }
    updateSelectionUi();
  });

  const copy = document.createElement("span");
  copy.className = "resource-copy";
  const title = document.createElement("span");
  title.className = "resource-title";
  title.textContent = resource.title || "Adsız kaynak";
  title.title = resource.title || "";
  const url = document.createElement("span");
  url.className = "resource-url";
  url.textContent = displayUrl(resource.url);
  url.title = resource.url;
  copy.append(title, url);

  if (resource.usedPageFallback) {
    const fallback = document.createElement("span");
    fallback.className = "fallback-note";
    fallback.textContent = "Sayfa adresi kullanılacak";
    copy.append(fallback);
  }

  row.append(checkbox, copy);
  return row;
}

function displayUrl(value) {
  try {
    const url = new URL(value);
    return `${url.hostname}${url.pathname === "/" ? "" : url.pathname}`.slice(0, 110);
  } catch (_error) {
    return String(value || "").slice(0, 110);
  }
}

function toggleSelectAll() {
  const shouldSelect = state.selected.size !== state.resources.length;
  state.selected.clear();
  if (shouldSelect) {
    state.resources.forEach((_resource, index) => state.selected.add(index));
  }
  for (const checkbox of elements.resourceGroups.querySelectorAll('input[type="checkbox"]')) {
    checkbox.checked = shouldSelect;
  }
  updateSelectionUi();
}

function updateSelectionUi() {
  const count = state.selected.size;
  elements.selectionCount.textContent = `${count} kaynak seçildi`;
  elements.enqueueSelected.disabled = count === 0;
  elements.selectAll.textContent = count === state.resources.length && count > 0
    ? "Seçimi kaldır"
    : "Tümünü seç";
}

async function enqueueSelected() {
  const items = [...state.selected]
    .sort((left, right) => left - right)
    .map((index) => state.resources[index])
    .filter(Boolean);
  if (items.length === 0) {
    showMessage("Kuyruğa eklemek için en az bir kaynak seçin.", "error");
    return;
  }

  setBusy(elements.enqueueSelected, true, "Ekleniyor…");
  try {
    const result = await sendMessage("ENQUEUE_MANY", { items });
    reportEnqueueResult(result);
    if (result.failed === 0) {
      state.selected.clear();
      for (const checkbox of elements.resourceGroups.querySelectorAll('input[type="checkbox"]')) {
        checkbox.checked = false;
      }
      updateSelectionUi();
    }
  } catch (error) {
    showMessage(friendlyError(error), "error");
  } finally {
    setBusy(elements.enqueueSelected, false);
    updateSelectionUi();
  }
}

function reportEnqueueResult(result) {
  if (result.failed === 0) {
    showMessage(`${result.added} kaynak indirme kuyruğuna eklendi.`, "success");
    return;
  }
  const firstFailure = result.results.find((entry) => !entry.ok);
  const reason = firstFailure && firstFailure.error ? ` İlk hata: ${firstFailure.error.message}` : "";
  showMessage(
    `${result.added} kaynak eklendi, ${result.failed} kaynak eklenemedi.${reason}`,
    result.added ? "info" : "error"
  );
}
