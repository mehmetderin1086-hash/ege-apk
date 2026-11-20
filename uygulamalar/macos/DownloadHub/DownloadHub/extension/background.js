"use strict";

const BASE_URL = "http://127.0.0.1:8765";
const CLIENT_NAME = "DownloadHub Chromium";
const STORAGE_KEYS = {
  token: "downloadHubToken",
  clientId: "downloadHubClientId",
  pairedAt: "downloadHubPairedAt"
};
const MAX_BATCH_SIZE = 200;
const ENQUEUE_CONCURRENCY = 3;
const IDEMPOTENCY_WINDOW_MS = 30000;
const idempotencyKeys = new Map();

const MENU_IDS = {
  inspectPage: "downloadhub-inspect-page",
  downloadLink: "downloadhub-download-link",
  downloadImage: "downloadhub-download-image",
  inspectVideo: "downloadhub-inspect-video",
  inspectAudio: "downloadhub-inspect-audio"
};

class DownloadHubError extends Error {
  constructor(message, code = "unknown", status = null) {
    super(message);
    this.name = "DownloadHubError";
    this.code = code;
    this.status = status;
  }
}

function createContextMenus() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_IDS.inspectPage,
      title: "Bu sayfayı DownloadHub ile incele",
      contexts: ["page"]
    });
    chrome.contextMenus.create({
      id: MENU_IDS.downloadLink,
      title: "Bağlantıyı DownloadHub ile indir",
      contexts: ["link"]
    });
    chrome.contextMenus.create({
      id: MENU_IDS.downloadImage,
      title: "Resmi DownloadHub ile indir",
      contexts: ["image"]
    });
    chrome.contextMenus.create({
      id: MENU_IDS.inspectVideo,
      title: "Video öğesini DownloadHub ile incele",
      contexts: ["video"]
    });
    chrome.contextMenus.create({
      id: MENU_IDS.inspectAudio,
      title: "Ses öğesini DownloadHub ile incele",
      contexts: ["audio"]
    });
  });
}

chrome.runtime.onInstalled.addListener(createContextMenus);
chrome.runtime.onStartup.addListener(createContextMenus);

async function getStoredAuth() {
  const values = await chrome.storage.local.get(Object.values(STORAGE_KEYS));
  return {
    token: values[STORAGE_KEYS.token] || null,
    clientId: values[STORAGE_KEYS.clientId] || null,
    pairedAt: values[STORAGE_KEYS.pairedAt] || null
  };
}

async function storeAuth(payload) {
  const token = payload.access_token || payload.token || payload.bearer_token;
  if (!token || typeof token !== "string") {
    throw new DownloadHubError(
      "Eşleştirme yanıtında erişim belirteci bulunamadı.",
      "missing_token"
    );
  }

  const clientId = payload.client_id || payload.clientId || null;
  const pairedAt = new Date().toISOString();
  await chrome.storage.local.set({
    [STORAGE_KEYS.token]: token,
    [STORAGE_KEYS.clientId]: clientId,
    [STORAGE_KEYS.pairedAt]: pairedAt
  });

  return { clientId, pairedAt };
}

async function clearAuth() {
  await chrome.storage.local.remove(Object.values(STORAGE_KEYS));
}

function withTimeout(timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  return { controller, clear: () => clearTimeout(timer) };
}

function errorFromStatus(status, payload) {
  const serverMessage = readableServerMessage(payload);

  if (status === 401) {
    return new DownloadHubError(
      "Eşleştirme geçersiz veya süresi dolmuş. Eklentiyi yeniden eşleştirin.",
      "unauthorized",
      status
    );
  }
  if (status === 403) {
    return new DownloadHubError(
      "DownloadHub bu işleme izin vermedi. Eşleştirme ve güvenlik ayarlarını kontrol edin.",
      "forbidden",
      status
    );
  }
  if (status === 404) {
    return new DownloadHubError(
      "DownloadHub API uç noktası bulunamadı. Uygulamanın güncel sürümünü başlatın.",
      "not_found",
      status
    );
  }
  if (status === 409) {
    return new DownloadHubError(
      serverMessage || "Bu indirme zaten kuyrukta veya tamamlanmış.",
      "conflict",
      status
    );
  }
  if (status === 422) {
    return new DownloadHubError(
      serverMessage || "DownloadHub gönderilen bağlantıyı kabul etmedi.",
      "validation",
      status
    );
  }
  if (status === 429) {
    return new DownloadHubError(
      "Çok fazla istek gönderildi. Bir süre bekleyip yeniden deneyin.",
      "rate_limited",
      status
    );
  }

  return new DownloadHubError(
    serverMessage || `DownloadHub isteği başarısız oldu (HTTP ${status}).`,
    "http_error",
    status
  );
}

function readableServerMessage(payload) {
  if (!payload) {
    return null;
  }
  if (typeof payload === "string") {
    return payload.slice(0, 500);
  }

  const detail = payload.detail || payload.message || payload.error;
  if (typeof detail === "string") {
    return detail.slice(0, 500);
  }
  if (Array.isArray(detail)) {
    const messages = detail
      .map((entry) => entry && (entry.msg || entry.message))
      .filter((entry) => typeof entry === "string");
    return messages.length ? messages.join("; ").slice(0, 500) : null;
  }
  if (detail && typeof detail === "object") {
    const message = detail.message || detail.msg;
    return typeof message === "string" ? message.slice(0, 500) : null;
  }
  return null;
}

async function parseResponse(response) {
  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    try {
      return await response.json();
    } catch (_error) {
      return null;
    }
  }

  const text = await response.text();
  return text ? { message: text.slice(0, 500) } : {};
}

async function apiRequest(path, options = {}) {
  const {
    method = "GET",
    body,
    auth = true,
    timeoutMs = 15000,
    headers: extraHeaders = {}
  } = options;
  const headers = { Accept: "application/json", ...extraHeaders };

  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
  }

  if (auth) {
    const { token } = await getStoredAuth();
    if (!token) {
      throw new DownloadHubError(
        "Bu işlem için eklentiyi önce DownloadHub ile eşleştirin.",
        "not_paired"
      );
    }
    headers.Authorization = `Bearer ${token}`;
  }

  const timeout = withTimeout(timeoutMs);
  try {
    const response = await fetch(`${BASE_URL}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: timeout.controller.signal,
      cache: "no-store"
    });
    const payload = await parseResponse(response);
    if (!response.ok) {
      if (response.status === 401 && auth) {
        await clearAuth();
      }
      throw errorFromStatus(response.status, payload);
    }
    return payload;
  } catch (error) {
    if (error instanceof DownloadHubError) {
      throw error;
    }
    if (error && error.name === "AbortError") {
      throw new DownloadHubError(
        "DownloadHub zamanında yanıt vermedi. Uygulamanın çalıştığını kontrol edin.",
        "timeout"
      );
    }
    throw new DownloadHubError(
      "DownloadHub'a bağlanılamadı. Uygulamayı açıp 127.0.0.1:8765 adresini kontrol edin.",
      "offline"
    );
  } finally {
    timeout.clear();
  }
}

async function checkService() {
  const healthPaths = ["/health", "/readyz", "/api/v1/health"];
  let lastError = null;

  for (const path of healthPaths) {
    try {
      const payload = await apiRequest(path, {
        auth: false,
        timeoutMs: 2500
      });
      const auth = await getStoredAuth();
      return {
        online: true,
        paired: Boolean(auth.token),
        pairedAt: auth.pairedAt,
        service: payload
      };
    } catch (error) {
      lastError = error;
      if (error.status && error.status !== 404) {
        break;
      }
    }
  }

  const auth = await getStoredAuth();
  return {
    online: false,
    paired: Boolean(auth.token),
    pairedAt: auth.pairedAt,
    error: serializeError(lastError)
  };
}

function isHttpUrl(value) {
  try {
    const parsed = new URL(value);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch (_error) {
    return false;
  }
}

function canonicalizeYouTubeUrl(value) {
  if (!isHttpUrl(value)) {
    return value;
  }

  const parsed = new URL(value);
  const host = parsed.hostname.toLowerCase().replace(/^www\./, "");
  let videoId = null;

  if (host === "youtu.be") {
    videoId = parsed.pathname.split("/").filter(Boolean)[0] || null;
  } else if (host === "youtube.com" || host.endsWith(".youtube.com")) {
    if (parsed.pathname === "/watch") {
      videoId = parsed.searchParams.get("v");
    } else {
      const match = parsed.pathname.match(/^\/(?:shorts|embed|live)\/([^/?#]+)/);
      videoId = match ? match[1] : null;
    }

    if (!videoId && parsed.pathname === "/playlist") {
      const listId = parsed.searchParams.get("list");
      return listId
        ? `https://www.youtube.com/playlist?list=${encodeURIComponent(listId)}`
        : "https://www.youtube.com/playlist";
    }
  }

  if (videoId) {
    const canonical = new URL("https://www.youtube.com/watch");
    canonical.searchParams.set("v", videoId);
    const listId = parsed.searchParams.get("list");
    if (listId) {
      canonical.searchParams.set("list", listId);
    }
    return canonical.toString();
  }

  if (host === "youtube.com" || host.endsWith(".youtube.com")) {
    parsed.protocol = "https:";
    parsed.hostname = "www.youtube.com";
    parsed.hash = "";
    for (const key of [...parsed.searchParams.keys()]) {
      if (key.startsWith("utm_") || ["feature", "si", "pp"].includes(key)) {
        parsed.searchParams.delete(key);
      }
    }
    return parsed.toString();
  }

  return value;
}

function normalizeTargetUrl(value, pageUrl, kind = "other") {
  const canonicalPage = canonicalizeYouTubeUrl(pageUrl || "");
  const candidate = typeof value === "string" ? value.trim() : "";
  const pageIsYouTube = /(^|\.)youtube\.com$|^youtu\.be$/i.test((() => {
    try {
      return new URL(canonicalPage).hostname.replace(/^www\./, "");
    } catch (_error) {
      return "";
    }
  })());

  if ((kind === "video" || kind === "audio") && pageIsYouTube) {
    return canonicalPage;
  }
  if (!candidate || candidate.startsWith("blob:") || candidate.startsWith("data:")) {
    return canonicalPage;
  }
  if (!isHttpUrl(candidate)) {
    return canonicalPage;
  }
  return canonicalizeYouTubeUrl(candidate);
}

function validateTargetUrl(value) {
  if (!isHttpUrl(value)) {
    throw new DownloadHubError(
      "Bu sayfa indirilemez. Yalnızca HTTP veya HTTPS bağlantıları desteklenir.",
      "unsupported_url"
    );
  }
  return value;
}

async function inspectUrl(url) {
  return apiRequest("/api/v1/inspect", {
    method: "POST",
    body: { url: validateTargetUrl(url) },
    timeoutMs: 60000
  });
}

function idempotencyKeyForUrl(url) {
  const now = Date.now();
  const cached = idempotencyKeys.get(url);
  if (cached && cached.expiresAt > now) {
    return cached.key;
  }

  for (const [cachedUrl, value] of idempotencyKeys) {
    if (value.expiresAt <= now) {
      idempotencyKeys.delete(cachedUrl);
    }
  }

  const key = crypto.randomUUID();
  idempotencyKeys.set(url, { key, expiresAt: now + IDEMPOTENCY_WINDOW_MS });
  return key;
}

async function enqueueOne(item) {
  const requestedUrl = validateTargetUrl(
    normalizeTargetUrl(item.url, item.pageUrl || item.page_url, item.kind)
  );
  const inspection = await inspectUrl(requestedUrl);
  const url = validateTargetUrl(
    typeof inspection.url === "string" ? inspection.url : requestedUrl
  );
  if (!inspection.inspection_id || !["direct", "media"].includes(inspection.engine)) {
    throw new DownloadHubError(
      "DownloadHub kaynak türünü güvenli biçimde belirleyemedi.",
      "invalid_inspection"
    );
  }

  const body = {
    url,
    engine: inspection.engine,
    inspection_id: inspection.inspection_id,
    source: "extension"
  };
  if (typeof inspection.title === "string" && inspection.title.trim()) {
    body.title = inspection.title.trim();
  }

  return apiRequest("/api/v1/jobs", {
    method: "POST",
    body,
    timeoutMs: 30000,
    headers: { "Idempotency-Key": idempotencyKeyForUrl(url) }
  });
}

async function mapWithConcurrency(values, limit, callback) {
  const results = new Array(values.length);
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await callback(values[index], index);
    }
  }

  const workerCount = Math.min(Math.max(1, limit), values.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
  return results;
}

async function enqueueMany(items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new DownloadHubError(
      "Kuyruğa eklemek için en az bir kaynak seçin.",
      "empty_selection"
    );
  }
  if (items.length > MAX_BATCH_SIZE) {
    throw new DownloadHubError(
      `Tek seferde en fazla ${MAX_BATCH_SIZE} kaynak eklenebilir.`,
      "batch_too_large"
    );
  }

  const unique = [];
  const seen = new Set();
  for (const item of items) {
    const url = normalizeTargetUrl(
      item && item.url,
      item && (item.pageUrl || item.page_url),
      item && item.kind
    );
    if (isHttpUrl(url) && !seen.has(url)) {
      seen.add(url);
      unique.push({ ...item, url });
    }
  }

  if (unique.length === 0) {
    throw new DownloadHubError(
      "Seçilen kaynaklarda indirilebilir bir HTTP veya HTTPS bağlantısı bulunamadı.",
      "no_downloadable_url"
    );
  }

  const results = await mapWithConcurrency(unique, ENQUEUE_CONCURRENCY, async (item) => {
    try {
      const response = await enqueueOne(item);
      return { ok: true, url: item.url, response };
    } catch (error) {
      return { ok: false, url: item.url, error: serializeError(error) };
    }
  });

  return {
    total: unique.length,
    added: results.filter((result) => result.ok).length,
    failed: results.filter((result) => !result.ok).length,
    results
  };
}

async function getActiveTab() {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  const tab = tabs[0];
  if (!tab || !tab.id) {
    throw new DownloadHubError("Etkin sekme bulunamadı.", "no_active_tab");
  }
  if (!isHttpUrl(tab.url || "")) {
    throw new DownloadHubError(
      "Bu tarayıcı sayfasına erişilemiyor. Normal bir HTTP veya HTTPS sekmesi açın.",
      "restricted_tab"
    );
  }
  return tab;
}

async function scanActivePage() {
  const tab = await getActiveTab();
  try {
    const injection = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["content.js"]
    });
    const scan = injection && injection[0] && injection[0].result;
    if (!scan || !Array.isArray(scan.resources)) {
      throw new Error("Tarama sonucu alınamadı");
    }
    return scan;
  } catch (error) {
    if (error instanceof DownloadHubError) {
      throw error;
    }
    throw new DownloadHubError(
      "Sayfa kaynakları taranamadı. Sekmeyi yenileyip eklentiyi yeniden açın.",
      "scan_failed"
    );
  }
}

async function inspectActivePage() {
  const tab = await getActiveTab();
  const url = canonicalizeYouTubeUrl(tab.url);
  const result = await inspectUrl(url);
  return { url, result };
}

async function startPairing() {
  await chrome.tabs.create({ url: `${BASE_URL}/?pair=1` });
  return {
    code: null,
    expiresAt: null
  };
}

async function completePairing(code) {
  const normalized = String(code || "").trim().toUpperCase();
  if (!/^[A-Z0-9-]{4,64}$/.test(normalized)) {
    throw new DownloadHubError(
      "Eşleştirme kodu 4-64 karakter olmalı; yalnız harf, rakam ve kısa çizgi içerebilir.",
      "invalid_pairing_code"
    );
  }
  const response = await apiRequest("/api/v1/pair/complete", {
    method: "POST",
    auth: false,
    body: { code: normalized, client_name: CLIENT_NAME },
    timeoutMs: 10000
  });
  const auth = await storeAuth(response);
  return { paired: true, ...auth };
}

async function revokePairing() {
  try {
    await apiRequest("/api/v1/pair/revoke", {
      method: "POST",
      body: {},
      timeoutMs: 10000
    });
  } finally {
    await clearAuth();
  }
  return { paired: false };
}

function serializeError(error) {
  return {
    message: error && error.message
      ? error.message
      : "Beklenmeyen bir eklenti hatası oluştu.",
    code: error && error.code ? error.code : "unknown",
    status: error && error.status ? error.status : null
  };
}

function setActionFeedback(ok, message) {
  chrome.action.setBadgeBackgroundColor({ color: ok ? "#168b5b" : "#d64545" });
  chrome.action.setBadgeText({ text: ok ? "✓" : "!" });
  chrome.action.setTitle({ title: `DownloadHub — ${message}` });
  setTimeout(() => {
    chrome.action.setBadgeText({ text: "" });
    chrome.action.setTitle({ title: "DownloadHub" });
  }, 5000);
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const handlers = {
    STATUS: () => checkService(),
    PAIR_START: () => startPairing(),
    PAIR_COMPLETE: () => completePairing(message.code),
    PAIR_REVOKE: () => revokePairing(),
    INSPECT_ACTIVE_PAGE: () => inspectActivePage(),
    SCAN_ACTIVE_PAGE: () => scanActivePage(),
    ENQUEUE_MANY: () => enqueueMany(message.items),
    OPEN_APP: async () => {
      await chrome.tabs.create({ url: BASE_URL });
      return { opened: true };
    }
  };

  const handler = handlers[message && message.type];
  if (!handler) {
    sendResponse({ ok: false, error: serializeError(new Error("Bilinmeyen istek.")) });
    return false;
  }

  Promise.resolve()
    .then(handler)
    .then((data) => sendResponse({ ok: true, data }))
    .catch((error) => sendResponse({ ok: false, error: serializeError(error) }));
  return true;
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const pageUrl = canonicalizeYouTubeUrl(info.pageUrl || (tab && tab.url) || "");
  try {
    if (info.menuItemId === MENU_IDS.inspectPage) {
      await inspectUrl(validateTargetUrl(pageUrl));
      await chrome.tabs.create({ url: `${BASE_URL}/?url=${encodeURIComponent(pageUrl)}` });
      setActionFeedback(true, "Sayfa incelendi");
      return;
    }

    if (info.menuItemId === MENU_IDS.downloadLink) {
      const result = await enqueueMany([{ url: info.linkUrl, pageUrl, kind: "other" }]);
      throwIfBatchFailed(result);
      setActionFeedback(true, "Bağlantı kuyruğa eklendi");
      return;
    }

    if (info.menuItemId === MENU_IDS.downloadImage) {
      const result = await enqueueMany([{ url: info.srcUrl, pageUrl, kind: "image" }]);
      throwIfBatchFailed(result);
      setActionFeedback(true, "Resim kuyruğa eklendi");
      return;
    }

    if (info.menuItemId === MENU_IDS.inspectVideo || info.menuItemId === MENU_IDS.inspectAudio) {
      const kind = info.menuItemId === MENU_IDS.inspectVideo ? "video" : "audio";
      const url = normalizeTargetUrl(info.srcUrl, pageUrl, kind);
      await inspectUrl(validateTargetUrl(url));
      await chrome.tabs.create({ url: `${BASE_URL}/?url=${encodeURIComponent(url)}` });
      setActionFeedback(true, `${kind === "video" ? "Video" : "Ses"} incelendi`);
    }
  } catch (error) {
    setActionFeedback(false, serializeError(error).message);
  }
});

function throwIfBatchFailed(result) {
  if (result.added > 0) {
    return;
  }
  const failure = result.results.find((entry) => !entry.ok);
  throw new DownloadHubError(
    failure && failure.error && failure.error.message
      ? failure.error.message
      : "Kaynak indirme kuyruğuna eklenemedi.",
    failure && failure.error && failure.error.code
      ? failure.error.code
      : "enqueue_failed",
    failure && failure.error ? failure.error.status : null
  );
}
