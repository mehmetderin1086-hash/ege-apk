const API_BASE = "/api/v1";
const JOBS_PAGE_SIZE = 100;
document.documentElement.dataset.uiVersion = "0.1.0-ui3";

const state = {
  jobs: [],
  jobsPage: 0,
  jobsTotal: 0,
  jobsLoading: false,
  selectedJobs: new Set(),
  inspection: null,
  filter: "active",
  search: "",
  view: localStorage.getItem("downloadhub:view") || "rows",
  settings: null,
  translations: {},
  eventSource: null,
  lastEventId: sessionStorage.getItem("downloadhub:last-event") || "",
  reloadTimer: null,
  pairingTimer: null,
  cancelTargets: [],
  sidebarReturnFocus: null,
  playlist: {
    items: [],
    filtered: [],
    selected: new Set(),
    rowHeight: 56,
    overscan: 6,
  },
};

const STATUS_LABELS = {
  inspecting: "İnceleniyor",
  queued: "Kuyrukta",
  scheduled: "Zamanlandı",
  downloading: "İndiriliyor",
  postprocessing: "İşleniyor",
  paused: "Duraklatıldı",
  retry_wait: "Yeniden denenecek",
  completed: "Tamamlandı",
  failed: "Hata",
  cancelled: "İptal edildi",
  interrupted: "Kesintiye uğradı",
};

const FILTER_LABELS = {
  active: "Aktif indirmeler",
  queued: "Kuyruktaki indirmeler",
  scheduled: "Zamanlanmış indirmeler",
  completed: "Tamamlanan indirmeler",
  failed: "Hatalı indirmeler",
  all: "Tüm indirmeler",
};

const ACTIVE_STATUSES = new Set(["inspecting", "downloading", "postprocessing", "paused", "retry_wait", "interrupted"]);
const QUEUE_STATUSES = new Set(["queued", "retry_wait", "interrupted"]);

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

function csrfToken() {
  const fromMeta = $('meta[name="csrf-token"]')?.content?.trim();
  if (fromMeta) return fromMeta;
  const match = document.cookie.match(/(?:^|;\s*)(?:dh_csrf|csrf_token|downloadhub_csrf)=([^;]+)/);
  return match ? decodeURIComponent(match[1]) : "";
}

async function apiFetch(path, options = {}) {
  const headers = new Headers(options.headers || {});
  headers.set("Accept", "application/json");
  if (options.body && !(options.body instanceof FormData)) {
    headers.set("Content-Type", "application/json");
  }
  const token = csrfToken();
  if (token && !headers.has("X-CSRF-Token")) headers.set("X-CSRF-Token", token);

  const response = await fetch(`${API_BASE}${path}`, {
    credentials: "same-origin",
    ...options,
    headers,
  });

  if (response.status === 204) return null;
  const contentType = response.headers.get("content-type") || "";
  const body = contentType.includes("application/json")
    ? await response.json().catch(() => null)
    : await response.text().catch(() => "");

  if (!response.ok) {
    const message = body?.detail?.message || body?.detail || body?.message || body || `İstek başarısız (${response.status})`;
    const error = new Error(typeof message === "string" ? message : JSON.stringify(message));
    error.status = response.status;
    error.payload = body;
    throw error;
  }
  return body;
}

function setBusy(button, busy) {
  if (!button) return;
  button.classList.toggle("is-loading", busy);
  button.disabled = busy;
  button.setAttribute("aria-busy", String(busy));
}

function showMessage(node, message = "", kind = "error") {
  if (!node) return;
  node.textContent = message;
  node.classList.toggle("is-success", kind === "success");
  node.hidden = !message;
}

function translate(key, fallback = key) {
  return state.translations[key] ?? fallback;
}

async function loadTranslations() {
  const locale = localStorage.getItem("downloadhub:locale") || document.documentElement.lang || "tr";
  try {
    const response = await fetch(`/static/i18n/${encodeURIComponent(locale)}.json`, { credentials: "same-origin" });
    if (response.ok) state.translations = await response.json();
  } catch {
    state.translations = {};
  }
  $$('[data-i18n]').forEach((node) => {
    const value = translate(node.dataset.i18n, "");
    if (value) node.textContent = value;
  });
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, Number(value) || 0));
}

function formatBytes(value, decimals = 1) {
  const bytes = Number(value);
  if (!Number.isFinite(bytes) || bytes < 0) return "—";
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const amount = bytes / 1024 ** index;
  const digits = index === 0 || amount >= 100 ? 0 : decimals;
  return `${amount.toLocaleString("tr-TR", { maximumFractionDigits: digits })} ${units[index]}`;
}

function formatSpeed(value) {
  const bytes = Number(value);
  return bytes > 0 ? `${formatBytes(bytes)}/sn` : "0 B/sn";
}

function formatDuration(value) {
  const seconds = Math.max(0, Math.round(Number(value) || 0));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const rest = seconds % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(rest).padStart(2, "0")}`
    : `${minutes}:${String(rest).padStart(2, "0")}`;
}

function formatEta(value) {
  if (value === null || value === undefined || value === "") return "Kalan —";
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds < 0) return "Kalan —";
  if (seconds < 60) return `Kalan ${Math.ceil(seconds)} sn`;
  if (seconds < 3600) return `Kalan ${Math.ceil(seconds / 60)} dk`;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.ceil((seconds % 3600) / 60);
  return `Kalan ${hours} sa ${minutes} dk`;
}

function formatDate(value, includeTime = true) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("tr-TR", {
    dateStyle: "medium",
    ...(includeTime ? { timeStyle: "short" } : {}),
  }).format(date);
}

function sourceHost(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "Bağlantı";
  }
}

function todayMatches(value) {
  if (!value) return false;
  const date = new Date(value);
  const today = new Date();
  return date.getFullYear() === today.getFullYear()
    && date.getMonth() === today.getMonth()
    && date.getDate() === today.getDate();
}

function normalizeError(error) {
  if (!navigator.onLine) return "İnternet bağlantısı görünmüyor. Bağlantıyı kontrol edip yeniden deneyin.";
  if (error?.status === 401 || error?.status === 403) return "Bu işlem için yetki alınamadı. Tarayıcı oturumu ayarlarını kontrol edin.";
  if (error?.status === 404) return "İstenen kaynak bulunamadı veya artık kullanılamıyor.";
  if (error?.status === 429) return "Kaynak çok fazla istek aldı. Bir süre bekleyip yeniden deneyin.";
  if (error?.status >= 500) return "Yerel servis isteği tamamlayamadı. Sistem kontrolünü inceleyin.";
  if (error instanceof TypeError) return "DownloadHub yerel servisine ulaşılamadı.";
  return error?.message || "Beklenmeyen bir hata oluştu.";
}

function showToast(title, detail = "", kind = "success", timeout = 4500) {
  const template = $("#toast-template");
  const region = $("[data-toast-region]");
  if (!template || !region) return;
  const toast = template.content.firstElementChild.cloneNode(true);
  toast.classList.toggle("is-error", kind === "error");
  $(".toast-icon", toast).textContent = kind === "error" ? "!" : "✓";
  $("strong", toast).textContent = title;
  $("p", toast).textContent = detail;
  const dismiss = () => {
    toast.classList.add("is-leaving");
    window.setTimeout(() => toast.remove(), 200);
  };
  $("button", toast).addEventListener("click", dismiss);
  region.append(toast);
  window.setTimeout(dismiss, timeout);
}

function setTheme(theme, persist = true) {
  const valid = ["system", "light", "dark"].includes(theme) ? theme : "system";
  document.documentElement.dataset.theme = valid;
  if (persist) localStorage.setItem("downloadhub:theme", valid);
  const themeSelect = $('[name="theme"]', $("[data-settings-form]"));
  if (themeSelect) themeSelect.value = valid;
  const metaColor = $('meta[name="theme-color"]');
  if (metaColor) {
    const dark = valid === "dark" || (valid === "system" && matchMedia("(prefers-color-scheme: dark)").matches);
    metaColor.content = dark ? "#08121b" : "#0b1927";
  }
}

function cycleTheme() {
  const current = document.documentElement.dataset.theme || "system";
  const next = current === "system" ? "light" : current === "light" ? "dark" : "system";
  setTheme(next);
  const labels = { system: "Sistem teması", light: "Açık tema", dark: "Koyu tema" };
  showToast(labels[next], "Görünüm tercihiniz bu cihazda saklandı.");
}

function setSidebar(open) {
  const sidebar = $("#sidebar");
  const compact = matchMedia("(max-width: 960px)").matches;
  const wasOpen = document.body.classList.contains("sidebar-open");
  const shouldOpen = compact && Boolean(open);

  if (shouldOpen && !wasOpen) state.sidebarReturnFocus = document.activeElement;
  document.body.classList.toggle("sidebar-open", shouldOpen);
  $("[data-sidebar-open]")?.setAttribute("aria-expanded", String(shouldOpen));
  if (sidebar) {
    sidebar.toggleAttribute("inert", compact && !shouldOpen);
    if (compact && !shouldOpen) sidebar.setAttribute("aria-hidden", "true");
    else sidebar.removeAttribute("aria-hidden");
  }

  [$(".workspace"), $(".skip-link")].filter(Boolean).forEach((node) => {
    node.toggleAttribute("inert", shouldOpen);
  });

  if (shouldOpen && !wasOpen) {
    window.requestAnimationFrame(() => {
      $(".sidebar [data-filter], .sidebar button, .sidebar a")?.focus();
    });
  } else if (!shouldOpen && wasOpen) {
    const returnFocus = state.sidebarReturnFocus;
    state.sidebarReturnFocus = null;
    if (compact && returnFocus?.isConnected) window.requestAnimationFrame(() => returnFocus.focus());
  }
}

function syncSidebarAccessibility() {
  setSidebar(document.body.classList.contains("sidebar-open") && matchMedia("(max-width: 960px)").matches);
}

function openDialog(dialog) {
  if (!dialog || dialog.open) return;
  dialog.showModal();
}

function closeDialog(dialog) {
  if (dialog?.open) dialog.close();
}

function setFilter(filter) {
  if (!FILTER_LABELS[filter]) return;
  state.filter = filter;
  $$('[data-filter]').forEach((button) => {
    const active = button.dataset.filter === filter;
    button.classList.toggle("is-active", active);
    if (active) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  });
  const heading = translate(`filter.${filter}`, FILTER_LABELS[filter]);
  $("[data-page-title]").textContent = heading;
  $("#jobs-title").textContent = heading;
  renderJobs();
  setSidebar(false);
}

function filteredJobs() {
  const query = state.search.trim().toLocaleLowerCase("tr-TR");
  return state.jobs.filter((job) => {
    const filterMatch = state.filter === "all"
      || (state.filter === "active" && ACTIVE_STATUSES.has(job.status))
      || (state.filter === "queued" && QUEUE_STATUSES.has(job.status))
      || job.status === state.filter;
    if (!filterMatch) return false;
    if (!query) return true;
    return `${job.title || ""} ${job.source_url || ""} ${job.category || ""}`.toLocaleLowerCase("tr-TR").includes(query);
  });
}

function updateCounts() {
  const counts = {
    active: state.jobs.filter((job) => ACTIVE_STATUSES.has(job.status)).length,
    queued: state.jobs.filter((job) => QUEUE_STATUSES.has(job.status)).length,
    scheduled: state.jobs.filter((job) => job.status === "scheduled").length,
    completed: state.jobs.filter((job) => job.status === "completed").length,
    failed: state.jobs.filter((job) => job.status === "failed").length,
    all: state.jobs.length,
  };
  Object.entries(counts).forEach(([name, count]) => {
    $$(`[data-count="${name}"]`).forEach((node) => { node.textContent = String(count); });
  });

  const activeJobs = state.jobs.filter((job) => ["downloading", "postprocessing"].includes(job.status));
  $("[data-metric-speed]").textContent = formatSpeed(activeJobs.reduce((total, job) => total + (Number(job.speed_bytes) || 0), 0));
  $("[data-metric-active]").textContent = String(activeJobs.length);
  $("[data-metric-queued]").textContent = String(counts.queued + counts.scheduled);
  $("[data-metric-completed]").textContent = String(state.jobs.filter((job) => job.status === "completed" && todayMatches(job.updated_at)).length);
  const limit = state.settings?.max_concurrent_jobs || 3;
  $(".metric-card:nth-child(2) .metric-caption").textContent = `${limit} sınır`;
}

function actionButton(label, action, title = label, className = "") {
  const button = document.createElement("button");
  button.type = "button";
  button.className = `job-action ${className}`.trim();
  button.dataset.action = action;
  button.title = title;
  button.setAttribute("aria-label", title);
  button.textContent = label;
  return button;
}

function actionsForJob(job) {
  const fragment = document.createDocumentFragment();
  if (["downloading", "queued", "scheduled", "retry_wait"].includes(job.status)) {
    fragment.append(actionButton("Ⅱ", "pause", translate("action.pause", "İndirmeyi duraklat"), "primary-action"));
  }
  if (job.status === "paused") {
    fragment.append(actionButton("▶", "resume", translate("action.resume", "İndirmeyi sürdür"), "primary-action"));
  }
  if (["failed", "cancelled", "interrupted"].includes(job.status)) {
    fragment.append(actionButton("↻", "retry", translate("action.retry", "Yeniden dene"), "primary-action"));
  }
  if (["queued", "scheduled", "paused", "retry_wait", "interrupted"].includes(job.status)) {
    fragment.append(actionButton("↑", "priority", "Önceliği artır"));
  }
  if (job.status === "completed" && job.output_path) {
    fragment.append(actionButton("Bul", "reveal", translate("action.reveal", "Finder'da göster")));
    fragment.append(actionButton("Aç", "open", translate("action.open", "Dosyayı aç")));
    fragment.append(actionButton("Kopyala", "copy", "Dosya yolunu kopyala"));
  }
  if (!["completed", "failed", "cancelled"].includes(job.status)) {
    fragment.append(actionButton("×", "cancel", translate("action.cancel", "İndirmeyi iptal et"), "danger-action"));
  }
  fragment.append(actionButton("•••", "detail", translate("action.detail", "Görev ayrıntıları")));
  return fragment;
}

function renderJob(job) {
  const template = $("#job-row-template");
  const row = template.content.firstElementChild.cloneNode(true);
  const progress = clamp(job.progress, 0, 100);
  row.dataset.jobId = job.id;
  row.dataset.engine = job.engine || "direct";
  row.classList.add(`is-${job.status || "queued"}`);
  row.classList.toggle("is-selected", state.selectedJobs.has(job.id));

  const checkbox = $("[data-job-select]", row);
  checkbox.checked = state.selectedJobs.has(job.id);
  checkbox.setAttribute("aria-label", `${job.title || "İndirme"} görevini seç`);

  const title = $(".job-title", row);
  title.textContent = job.title || "Adsız indirme";
  title.title = job.title || "Adsız indirme";

  $(".status-pill", row).textContent = translate(`status.${job.status}`, STATUS_LABELS[job.status] || job.status || "Kuyrukta");
  $(".job-source", row).textContent = `${sourceHost(job.source_url)} · ${job.category || (job.engine === "media" ? "Videolar" : "Diğer")}`;

  const track = $(".progress-track", row);
  track.setAttribute("aria-valuenow", String(progress));
  track.setAttribute("aria-label", `${job.title || "İndirme"}: yüzde ${Math.round(progress)}`);
  $("span", track).style.width = `${progress}%`;
  $(".progress-percent", row).textContent = `%${Math.round(progress)}`;

  const size = job.total_bytes
    ? `${formatBytes(job.downloaded_bytes)} / ${formatBytes(job.total_bytes)}`
    : formatBytes(job.downloaded_bytes || 0);
  $(".job-size", row).textContent = size;
  $(".job-speed", row).textContent = ["downloading", "postprocessing"].includes(job.status) ? formatSpeed(job.speed_bytes) : STATUS_LABELS[job.status] || "Bekliyor";
  $(".job-eta", row).textContent = job.status === "scheduled" ? formatDate(job.scheduled_at) : formatEta(job.eta_seconds);
  $(".job-actions", row).append(actionsForJob(job));
  return row;
}

function updateBulkActions() {
  for (const id of [...state.selectedJobs]) {
    if (!state.jobs.some((job) => job.id === id)) state.selectedJobs.delete(id);
  }
  const count = state.selectedJobs.size;
  $("[data-bulk-actions]").hidden = count === 0;
  $("[data-selected-count]").textContent = String(count);
}

function renderJobs() {
  const list = $("[data-jobs-list]");
  const empty = $("[data-empty-state]");
  const jobs = filteredJobs();
  const fragment = document.createDocumentFragment();
  jobs.forEach((job) => fragment.append(renderJob(job)));
  list.replaceChildren(fragment);
  list.dataset.view = state.view;
  list.setAttribute("aria-busy", "false");
  empty.hidden = jobs.length > 0;
  list.hidden = jobs.length === 0;
  updateCounts();
  updateBulkActions();
  updateJobsPagination();
}

function mergeJobPages(primary, secondary) {
  const merged = [...primary];
  const positions = new Map(merged.map((job, index) => [job.id, index]));
  secondary.forEach((job) => {
    const index = positions.get(job.id);
    if (index === undefined) {
      positions.set(job.id, merged.length);
      merged.push(job);
    } else {
      merged[index] = { ...merged[index], ...job };
    }
  });
  return merged;
}

function updateJobsPagination() {
  const root = $("[data-jobs-pagination]");
  if (!root) return;
  const total = Math.max(state.jobsTotal, state.jobs.length);
  $("[data-jobs-loaded]", root).textContent = String(state.jobs.length);
  $("[data-jobs-total]", root).textContent = String(total);
  root.hidden = total === 0 || state.jobs.length >= total;
}

async function loadJobs({ quiet = false, append = false } = {}) {
  if (state.jobsLoading) return;
  state.jobsLoading = true;
  const refreshButton = $("[data-refresh-jobs]");
  const moreButton = $("[data-load-more]");
  const targetPage = append ? Math.max(1, state.jobsPage + 1) : 1;
  if (!quiet) refreshButton?.classList.add("is-loading");
  if (append) setBusy(moreButton, true);
  try {
    const page = await apiFetch(`/jobs?page=${targetPage}&page_size=${JOBS_PAGE_SIZE}`);
    const items = Array.isArray(page) ? page : page?.items || [];
    if (append) {
      state.jobs = mergeJobPages(state.jobs, items);
      state.jobsPage = targetPage;
    } else if (state.jobsPage > 1) {
      state.jobs = mergeJobPages(items, state.jobs);
    } else {
      state.jobs = items;
      state.jobsPage = 1;
    }
    const reportedTotal = Number(page?.total);
    state.jobsTotal = Number.isFinite(reportedTotal) ? reportedTotal : state.jobs.length;
    renderJobs();
  } catch (error) {
    $("[data-jobs-list]")?.setAttribute("aria-busy", "false");
    if (!quiet || append) showToast("Görevler yüklenemedi", normalizeError(error), "error");
  } finally {
    state.jobsLoading = false;
    refreshButton?.classList.remove("is-loading");
    if (append) setBusy(moreButton, false);
  }
}

function scheduleJobsReload(delay = 300) {
  window.clearTimeout(state.reloadTimer);
  state.reloadTimer = window.setTimeout(() => loadJobs({ quiet: true }), delay);
}

function consumeEvent(event) {
  if (event.lastEventId && Number(event.lastEventId) > 0) {
    state.lastEventId = event.lastEventId;
    sessionStorage.setItem("downloadhub:last-event", event.lastEventId);
  }
  let payload;
  try {
    payload = JSON.parse(event.data);
  } catch {
    scheduleJobsReload();
    return;
  }
  if (Array.isArray(payload?.jobs) || Array.isArray(payload?.items)) {
    const snapshot = payload.jobs || payload.items;
    state.jobs = mergeJobPages(snapshot, state.jobs);
    state.jobsPage = Math.max(state.jobsPage, Math.ceil(snapshot.length / JOBS_PAGE_SIZE), 1);
    state.jobsTotal = Math.max(state.jobsTotal, state.jobs.length);
    renderJobs();
    return;
  }
  const incomingJob = payload?.job || (payload?.id && payload?.status ? payload : null);
  if (incomingJob) {
    const index = state.jobs.findIndex((job) => job.id === incomingJob.id);
    if (index >= 0) state.jobs[index] = { ...state.jobs[index], ...incomingJob };
    else {
      state.jobs.unshift(incomingJob);
      state.jobsTotal = Math.max(state.jobs.length, state.jobsTotal + 1);
    }
    renderJobs();
    return;
  }
  if (payload?.job_id) {
    const index = state.jobs.findIndex((job) => job.id === payload.job_id);
    if (index < 0) {
      scheduleJobsReload();
      return;
    }
    const eventStatus = {
      "job.completed": "completed",
      "job.failed": "failed",
      "job.retry_wait": "retry_wait",
    }[event.type];
    const patch = { ...payload };
    delete patch.job_id;
    if (eventStatus) patch.status = eventStatus;
    if (patch.code) {
      patch.error_code = patch.code;
      delete patch.code;
    }
    if (patch.message) {
      patch.error_message = patch.message;
      delete patch.message;
    }
    if (patch.error && !patch.error_message) {
      patch.error_message = patch.error;
      delete patch.error;
    }
    state.jobs[index] = { ...state.jobs[index], ...patch };
    renderJobs();
    return;
  }
  scheduleJobsReload();
}

function connectEvents() {
  if (state.eventSource) state.eventSource.close();
  const query = state.lastEventId ? `?after=${encodeURIComponent(state.lastEventId)}` : "";
  const source = new EventSource(`${API_BASE}/events${query}`, { withCredentials: true });
  state.eventSource = source;
  const serviceCard = $(".service-card");
  source.onopen = () => {
    serviceCard?.classList.add("is-online");
    serviceCard?.classList.remove("is-error");
    $("[data-service-label]").textContent = "Servis bağlı";
    $("[data-service-detail]").textContent = "Canlı güncellemeler açık";
  };
  source.onerror = () => {
    serviceCard?.classList.remove("is-online");
    serviceCard?.classList.add("is-error");
    $("[data-service-label]").textContent = "Bağlantı yenileniyor";
    $("[data-service-detail]").textContent = "Yerel servis bekleniyor";
  };
  source.onmessage = consumeEvent;
  [
    "snapshot",
    "job",
    "progress",
    "status",
    "job.updated",
    "job.created",
    "job.state",
    "job.progress",
    "job.completed",
    "job.retry_wait",
    "job.failed",
    "job.items_failed",
    "job.priority",
    "job.partials_discarded",
  ].forEach((name) => {
    source.addEventListener(name, consumeEvent);
  });
}

function hideInspection() {
  $("[data-inspection-panel]").hidden = true;
  state.inspection = null;
  state.playlist.items = [];
  state.playlist.filtered = [];
  state.playlist.selected.clear();
}

function setImage(thumbnail) {
  const image = $("[data-inspection-thumb]");
  const placeholder = $("[data-thumb-placeholder]");
  image.hidden = true;
  placeholder.hidden = false;
  image.removeAttribute("src");
  if (!thumbnail || !/^https?:\/\//i.test(thumbnail)) return;
  image.referrerPolicy = "no-referrer";
  image.onload = () => {
    image.hidden = false;
    placeholder.hidden = true;
  };
  image.onerror = () => {
    image.hidden = true;
    placeholder.hidden = false;
  };
  image.src = thumbnail;
}

function renderFormats(formats = []) {
  const select = $("[data-format-select]");
  select.replaceChildren(new Option("Profil otomatik seçsin", ""));
  formats.forEach((format) => {
    const details = [format.label || format.format_id, format.extension?.toUpperCase(), format.resolution, format.filesize ? formatBytes(format.filesize) : null].filter(Boolean);
    select.append(new Option(details.join(" · "), format.format_id));
  });
}

function renderSubtitles(subtitles = []) {
  const section = $("[data-subtitle-section]");
  const list = $("[data-subtitle-list]");
  list.replaceChildren();
  section.hidden = subtitles.length === 0;
  subtitles.forEach((language) => {
    const label = document.createElement("label");
    label.className = "chip-check";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.name = "subtitle_languages";
    input.value = language;
    const text = document.createElement("span");
    text.textContent = language;
    label.append(input, text);
    list.append(label);
  });
}

function resetPlaylist(items = []) {
  state.playlist.items = items.map((item, index) => ({ ...item, _index: index }));
  state.playlist.filtered = [...state.playlist.items];
  state.playlist.selected = new Set(items.filter((item) => item.selected !== false).map((item) => item.id));
  const section = $("[data-playlist-section]");
  section.hidden = items.length === 0;
  $("[data-playlist-search]").value = "";
  $("[data-playlist-viewport]").scrollTop = 0;
  renderPlaylistVirtual();
  updatePlaylistSelection();
}

function filterPlaylist() {
  const query = $("[data-playlist-search]").value.trim().toLocaleLowerCase("tr-TR");
  state.playlist.filtered = query
    ? state.playlist.items.filter((item) => `${item.title || ""} ${item.id || ""}`.toLocaleLowerCase("tr-TR").includes(query))
    : [...state.playlist.items];
  $("[data-playlist-viewport]").scrollTop = 0;
  renderPlaylistVirtual();
}

function renderPlaylistVirtual() {
  const viewport = $("[data-playlist-viewport]");
  const spacer = $("[data-playlist-spacer]");
  const windowNode = $("[data-playlist-window]");
  if (!viewport || !spacer || !windowNode) return;

  const { rowHeight, overscan, filtered, selected } = state.playlist;
  spacer.style.height = `${filtered.length * rowHeight}px`;
  const start = Math.max(0, Math.floor(viewport.scrollTop / rowHeight) - overscan);
  const visibleCount = Math.ceil(viewport.clientHeight / rowHeight) + overscan * 2;
  const end = Math.min(filtered.length, start + visibleCount);
  const fragment = document.createDocumentFragment();

  for (let index = start; index < end; index += 1) {
    const item = filtered[index];
    const row = document.createElement("div");
    row.className = "playlist-item";
    row.setAttribute("role", "row");
    row.style.transform = `translateY(${index * rowHeight}px)`;

    const checkLabel = document.createElement("label");
    checkLabel.className = "playlist-item-check";
    const sr = document.createElement("span");
    sr.className = "sr-only";
    sr.textContent = `${item.title || "Öğe"} seç`;
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = selected.has(item.id);
    checkbox.dataset.playlistId = item.id;
    checkLabel.append(sr, checkbox);

    const title = document.createElement("span");
    title.className = "playlist-title";
    title.setAttribute("role", "cell");
    const strong = document.createElement("strong");
    strong.textContent = item.title || `Öğe ${index + 1}`;
    strong.title = item.title || "";
    const small = document.createElement("small");
    small.textContent = `#${item._index + 1} · ${item.id || "Kimlik yok"}`;
    title.append(strong, small);

    const duration = document.createElement("span");
    duration.className = "playlist-duration";
    duration.setAttribute("role", "cell");
    duration.textContent = item.duration ? formatDuration(item.duration) : "—";
    row.append(checkLabel, title, duration);
    fragment.append(row);
  }
  windowNode.replaceChildren(fragment);
}

function updatePlaylistSelection() {
  $("[data-playlist-selected]").textContent = String(state.playlist.selected.size);
}

function updateOutputEstimate() {
  if (!state.inspection) return;
  const preset = $("[data-preset-select]").value;
  const formatId = $("[data-format-select]").value;
  const format = state.inspection.formats?.find((item) => item.format_id === formatId);
  const labels = {
    best: "En iyi kalite · Otomatik kapsayıcı",
    mp4: "En uyumlu MP4 seçimi",
    "1080p": "Full HD · 1080p'ye kadar",
    "720p": "HD · 720p'ye kadar",
    m4a: "Yalnız ses · M4A",
    mp3: "Yalnız ses · MP3 192 kbps",
    archive: "Kaynak kalite · Arşiv",
  };
  $("[data-output-summary]").textContent = format ? format.label : labels[preset] || "Otomatik format";
  const size = format?.filesize || state.inspection.filesize;
  $("[data-output-size]").textContent = size ? `Yaklaşık ${formatBytes(size)}` : "Boyut kaynak tarafından bildirilmedi";

  const category = $("[data-category-select]");
  if (["m4a", "mp3"].includes(preset) && category.dataset.userChanged !== "true") category.value = "Müzik";
  else if (state.inspection.engine === "media" && category.dataset.userChanged !== "true") category.value = "Videolar";
}

function renderInspection(result) {
  state.inspection = result;
  const panel = $("[data-inspection-panel]");
  panel.hidden = false;
  setImage(result.thumbnail);

  $("[data-source-type]").textContent = result.engine === "media" ? (result.source_type === "playlist" ? "OYNATMA LİSTESİ" : "MEDYA") : "DOSYA";
  $("[data-inspection-title]").textContent = result.title || "İndirilecek içerik";
  const details = [result.uploader, result.duration ? formatDuration(result.duration) : null, result.filesize ? formatBytes(result.filesize) : null, result.mime_type].filter(Boolean);
  $("[data-inspection-meta]").textContent = details.join(" · ") || sourceHost(result.url);

  const duration = $("[data-inspection-duration]");
  duration.hidden = !result.duration;
  duration.textContent = result.duration ? formatDuration(result.duration) : "";

  const warnings = $("[data-warning-list]");
  warnings.replaceChildren();
  (result.warnings || []).forEach((warning) => {
    const item = document.createElement("span");
    item.textContent = `Dikkat: ${warning}`;
    warnings.append(item);
  });
  warnings.hidden = !result.warnings?.length;

  const media = result.engine === "media";
  $("[data-format-field]").hidden = !media;
  $("[data-preset-select]").closest(".field-group").hidden = !media;
  $("[data-checksum-field]").hidden = media;
  $$('[name="write_thumbnail"], [name="write_metadata"]').forEach((input) => {
    input.closest("label").hidden = !media;
  });
  $("[data-category-select]").dataset.userChanged = "false";
  $("[data-category-select]").value = media ? "Videolar" : inferDirectCategory(result.mime_type, result.title);
  renderFormats(result.formats || []);
  renderSubtitles(media ? result.subtitles || [] : []);
  resetPlaylist(media ? result.items || [] : []);
  updateOutputEstimate();
  showMessage($("[data-create-message]"));
  panel.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "nearest" });
}

function inferDirectCategory(mimeType = "", name = "") {
  const mime = mimeType.toLocaleLowerCase("tr-TR");
  const extension = name.split(".").pop()?.toLocaleLowerCase("tr-TR") || "";
  if (mime.startsWith("image/")) return "Resimler";
  if (mime.startsWith("video/")) return "Videolar";
  if (mime.startsWith("audio/")) return "Müzik";
  if (/pdf|document|text|sheet|presentation/.test(mime) || ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt"].includes(extension)) return "Belgeler";
  if (/zip|rar|tar|gzip|7z|archive/.test(mime) || ["zip", "rar", "7z", "tar", "gz"].includes(extension)) return "Arşivler";
  return "Diğer";
}

async function inspectUrl(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const input = $("#download-url");
  const button = $(".inspect-button", form);
  const message = $("[data-inspect-message]");
  showMessage(message);

  if (!form.reportValidity()) return;
  let url;
  try {
    url = new URL(input.value.trim());
    if (!/^https?:$/.test(url.protocol)) throw new Error();
  } catch {
    showMessage(message, "Yalnızca geçerli bir HTTP veya HTTPS bağlantısı girin.");
    input.focus();
    return;
  }

  setBusy(button, true);
  try {
    const result = await apiFetch("/inspect", {
      method: "POST",
      body: JSON.stringify({
        url: url.href,
        use_browser_cookies: $("[data-use-cookies]").checked,
        browser_name: state.settings?.browser_name || "chrome",
        browser_profile: $("[data-use-cookies]").checked ? state.settings?.browser_profile || null : null,
      }),
    });
    renderInspection(result);
  } catch (error) {
    hideInspection();
    showMessage(message, normalizeError(error));
  } finally {
    setBusy(button, false);
  }
}

async function createJob(event) {
  event.preventDefault();
  if (!state.inspection) return;
  const form = event.currentTarget;
  const button = $(".create-button", form);
  const message = $("[data-create-message]");
  showMessage(message);
  if (!form.reportValidity()) return;

  const data = new FormData(form);
  const scheduledValue = data.get("scheduled_at");
  const scheduledAt = scheduledValue ? new Date(String(scheduledValue)) : null;
  if (scheduledAt && Number.isNaN(scheduledAt.getTime())) {
    showMessage(message, "Başlangıç zamanı geçerli değil.");
    return;
  }

  if (state.inspection.items?.length && state.playlist.selected.size === 0) {
    showMessage(message, "Oynatma listesinden en az bir öğe seçin.");
    return;
  }

  const sha256 = String(data.get("sha256") || "").trim();
  const payload = {
    url: state.inspection.url,
    engine: state.inspection.engine,
    inspection_id: state.inspection.inspection_id,
    title: state.inspection.title,
    category: String(data.get("category") || "Diğer"),
    preset: state.inspection.engine === "media" ? String(data.get("preset") || "best") : "best",
    format_id: String(data.get("format_id") || "") || null,
    subtitle_languages: data.getAll("subtitle_languages").map(String),
    write_thumbnail: data.get("write_thumbnail") === "on",
    write_metadata: data.get("write_metadata") === "on",
    selected_item_ids: [...state.playlist.selected],
    scheduled_at: scheduledAt ? scheduledAt.toISOString() : null,
    speed_limit: String(data.get("speed_limit") || "").trim() || null,
    priority: 0,
    sha256: sha256 || null,
    use_browser_cookies: $("[data-use-cookies]").checked,
    browser_name: state.settings?.browser_name || "chrome",
    browser_profile: $("[data-use-cookies]").checked ? state.settings?.browser_profile || null : null,
  };

  setBusy(button, true);
  try {
    const job = await apiFetch("/jobs", {
      method: "POST",
      headers: { "Idempotency-Key": crypto.randomUUID() },
      body: JSON.stringify(payload),
    });
    showMessage(message, "Görev kuyruğa eklendi.", "success");
    showToast("İndirme kuyruğa eklendi", job?.title || state.inspection.title || "Görev hazırlanıyor");
    if (job?.id) {
      const index = state.jobs.findIndex((item) => item.id === job.id);
      if (index >= 0) state.jobs[index] = job;
      else {
        state.jobs.unshift(job);
        state.jobsTotal = Math.max(state.jobs.length, state.jobsTotal + 1);
      }
      renderJobs();
    } else {
      scheduleJobsReload(100);
    }
    window.setTimeout(hideInspection, 700);
  } catch (error) {
    showMessage(message, normalizeError(error));
  } finally {
    setBusy(button, false);
  }
}

async function controlJob(jobId, action, options = {}) {
  const job = state.jobs.find((item) => item.id === jobId);
  if (!job) return false;
  try {
    if (["pause", "resume", "retry"].includes(action)) {
      await apiFetch(`/jobs/${encodeURIComponent(jobId)}/${action}`, { method: "POST" });
      if (!options.silent) {
        showToast(
          action === "pause" ? "İndirme duraklatıldı" : action === "resume" ? "İndirme sürdürülüyor" : "Görev yeniden kuyruğa alındı",
          job.title,
        );
      }
    } else if (action === "cancel") {
      await apiFetch(`/jobs/${encodeURIComponent(jobId)}/cancel`, {
        method: "POST",
        body: JSON.stringify({ keep_partial: options.keepPartial !== false }),
      });
      if (!options.silent) {
        showToast("İndirme iptal edildi", options.keepPartial === false ? "Parçalı dosyalar Çöp'e taşınacak." : "Parçalı dosyalar korundu.");
      }
    } else if (action === "priority") {
      const updated = await apiFetch(`/jobs/${encodeURIComponent(jobId)}/priority`, {
        method: "POST",
        body: JSON.stringify({ priority: Math.min(100, Number(job.priority || 0) + 1) }),
      });
      if (!options.silent) showToast("Görev önceliklendirildi", updated?.title || job.title);
    } else if (["reveal", "open"].includes(action)) {
      await apiFetch(`/jobs/${encodeURIComponent(jobId)}/${action}`, { method: "POST" });
    } else if (action === "copy") {
      await navigator.clipboard.writeText(job.output_path);
      if (!options.silent) showToast("Dosya yolu kopyalandı", job.output_path);
      return true;
    }
    if (options.reload !== false) await loadJobs({ quiet: true });
    return true;
  } catch (error) {
    if (!options.silent) showToast("İşlem tamamlanamadı", normalizeError(error), "error");
    return false;
  }
}

async function handleJobAction(event) {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const row = button.closest("[data-job-id]");
  const jobId = row?.dataset.jobId;
  const action = button.dataset.action;
  if (!jobId) return;
  if (action === "detail") {
    openJobDetail(jobId);
    return;
  }
  if (action === "cancel") {
    state.cancelTargets = [jobId];
    openDialog($("[data-cancel-dialog]"));
    return;
  }
  button.disabled = true;
  await controlJob(jobId, action);
  button.disabled = false;
}

function handleJobSelect(event) {
  const checkbox = event.target.closest("[data-job-select]");
  if (!checkbox) return;
  const row = checkbox.closest("[data-job-id]");
  if (!row) return;
  if (checkbox.checked) state.selectedJobs.add(row.dataset.jobId);
  else state.selectedJobs.delete(row.dataset.jobId);
  row.classList.toggle("is-selected", checkbox.checked);
  updateBulkActions();
}

async function bulkAction(action) {
  const allowedStatuses = {
    pause: new Set(["downloading", "queued", "scheduled", "retry_wait"]),
    resume: new Set(["paused"]),
    cancel: new Set(["inspecting", "queued", "scheduled", "downloading", "postprocessing", "paused", "retry_wait", "interrupted"]),
  };
  const selected = [...state.selectedJobs]
    .map((id) => state.jobs.find((job) => job.id === id))
    .filter(Boolean);
  const jobs = selected.filter((job) => allowedStatuses[action]?.has(job.status));
  if (!selected.length) return;
  if (!jobs.length) {
    showToast("Uygulanabilir görev yok", "Seçili görevlerin durumu bu işleme izin vermiyor.", "error");
    return;
  }
  if (action === "cancel") {
    state.cancelTargets = jobs.map((job) => job.id);
    openDialog($("[data-cancel-dialog]"));
    return;
  }
  const results = await Promise.all(jobs.map((job) => controlJob(job.id, action, { reload: false, silent: true })));
  state.selectedJobs.clear();
  await loadJobs({ quiet: true });
  const completed = results.filter(Boolean).length;
  showToast(
    completed ? "Toplu işlem tamamlandı" : "Toplu işlem tamamlanamadı",
    `${completed} görev güncellendi${jobs.length < selected.length ? `, ${selected.length - jobs.length} görev atlandı` : ""}.`,
    completed ? "success" : "error",
  );
}

function createDetailProperty(label, value) {
  const row = document.createElement("div");
  row.className = "detail-property";
  const dt = document.createElement("dt");
  dt.textContent = label;
  const dd = document.createElement("dd");
  dd.textContent = value || "—";
  row.append(dt, dd);
  return row;
}

function detailCell(label, value) {
  const cell = document.createElement("div");
  cell.className = "detail-cell";
  const span = document.createElement("span");
  span.textContent = label;
  const strong = document.createElement("strong");
  strong.textContent = value;
  cell.append(span, strong);
  return cell;
}

function renderJobDetail(job, extras = {}) {
  const root = $("[data-job-detail]");
  $("[data-detail-title]").textContent = job.title || "İndirme";
  root.replaceChildren();

  const hero = document.createElement("section");
  hero.className = "detail-hero";
  const statusRow = document.createElement("div");
  statusRow.className = "detail-status-row";
  const badge = document.createElement("span");
  badge.className = "status-pill";
  badge.textContent = STATUS_LABELS[job.status] || job.status;
  const source = document.createElement("span");
  source.className = "inspection-meta";
  source.textContent = job.engine === "media" ? "Medya motoru" : "Doğrudan indirme";
  statusRow.append(badge, source);

  const progress = document.createElement("div");
  progress.className = "detail-progress";
  const percent = document.createElement("strong");
  percent.textContent = `%${Math.round(clamp(job.progress, 0, 100))}`;
  const track = document.createElement("div");
  track.className = "progress-track";
  track.setAttribute("role", "progressbar");
  track.setAttribute("aria-valuemin", "0");
  track.setAttribute("aria-valuemax", "100");
  track.setAttribute("aria-valuenow", String(clamp(job.progress, 0, 100)));
  const fill = document.createElement("span");
  fill.style.width = `${clamp(job.progress, 0, 100)}%`;
  track.append(fill);
  progress.append(percent, track);

  const grid = document.createElement("div");
  grid.className = "detail-grid";
  grid.append(
    detailCell("İndirilen", formatBytes(job.downloaded_bytes || 0)),
    detailCell("Toplam", job.total_bytes ? formatBytes(job.total_bytes) : "Bilinmiyor"),
    detailCell("Hız", formatSpeed(job.speed_bytes)),
    detailCell("Tahmini süre", formatEta(job.eta_seconds).replace("Kalan ", "")),
  );
  hero.append(statusRow, progress, grid);
  root.append(hero);

  const section = document.createElement("section");
  section.className = "detail-section";
  const heading = document.createElement("h3");
  heading.textContent = "Görev bilgileri";
  const properties = document.createElement("dl");
  properties.className = "detail-properties";
  properties.append(
    createDetailProperty("Kaynak", job.source_url),
    createDetailProperty("Kategori", job.category),
    createDetailProperty("Oluşturuldu", formatDate(job.created_at)),
    createDetailProperty("Güncellendi", formatDate(job.updated_at)),
    createDetailProperty("Zamanlama", job.scheduled_at ? formatDate(job.scheduled_at) : "Hemen"),
    createDetailProperty("Çıktı", job.output_path || "Henüz oluşmadı"),
    createDetailProperty("Görev kimliği", job.id),
  );
  section.append(heading, properties);
  root.append(section);

  if (job.error_message || job.error_code) {
    const error = document.createElement("div");
    error.className = "detail-error";
    error.textContent = [job.error_code, job.error_message].filter(Boolean).join(" · ");
    root.append(error);
  }

  if (extras.artifacts?.length) {
    const artifactSection = document.createElement("section");
    artifactSection.className = "detail-section";
    const artifactHeading = document.createElement("h3");
    artifactHeading.textContent = "Oluşan dosyalar";
    const artifactProperties = document.createElement("dl");
    artifactProperties.className = "detail-properties";
    extras.artifacts.forEach((artifact) => {
      artifactProperties.append(createDetailProperty(
        artifact.kind || "Dosya",
        `${artifact.path || "—"}${artifact.size_bytes ? ` · ${formatBytes(artifact.size_bytes)}` : ""}`,
      ));
    });
    artifactSection.append(artifactHeading, artifactProperties);
    root.append(artifactSection);
  }

  if (extras.items?.length) {
    const itemSection = document.createElement("section");
    itemSection.className = "detail-section";
    const itemHeading = document.createElement("h3");
    itemHeading.textContent = `Liste öğeleri (${extras.items.length})`;
    const itemProperties = document.createElement("dl");
    itemProperties.className = "detail-properties";
    extras.items.slice(0, 100).forEach((item) => {
      itemProperties.append(createDetailProperty(
        `#${Number(item.position || 0)} · ${STATUS_LABELS[item.status] || item.status || "Bekliyor"}`,
        item.error_message ? `${item.title} · ${item.error_message}` : item.title,
      ));
    });
    itemSection.append(itemHeading, itemProperties);
    root.append(itemSection);
  }

  if (extras.events?.length) {
    const eventSection = document.createElement("section");
    eventSection.className = "detail-section";
    const eventHeading = document.createElement("h3");
    eventHeading.textContent = `Olay geçmişi (${extras.events.length})`;
    const eventProperties = document.createElement("dl");
    eventProperties.className = "detail-properties";
    extras.events.slice(0, 100).forEach((event) => {
      const payload = event.payload || {};
      const summary = payload.message
        || payload.error
        || payload.status
        || payload.code
        || (payload.priority !== undefined ? `Öncelik: ${payload.priority}` : "")
        || (payload.moved !== undefined ? `${payload.moved} parça Çöp'e taşındı` : "")
        || (payload.count !== undefined ? `${payload.count} öğe indirilemedi` : "")
        || payload.output_path
        || (payload.progress !== undefined ? `%${Math.round(Number(payload.progress) || 0)}` : "")
        || payload.job?.title
        || "—";
      eventProperties.append(createDetailProperty(
        `${event.type || "olay"} · ${formatDate(event.created_at)}`,
        String(summary),
      ));
    });
    eventSection.append(eventHeading, eventProperties);
    root.append(eventSection);
  }
}

async function openJobDetail(jobId) {
  const dialog = $("[data-job-dialog]");
  $("[data-job-detail]").innerHTML = '<div class="detail-skeleton"><span></span><span></span><span></span></div>';
  openDialog(dialog);
  try {
    const response = await apiFetch(`/jobs/${encodeURIComponent(jobId)}`);
    const job = response?.job || response;
    renderJobDetail(job, {
      items: response?.items || [],
      artifacts: response?.artifacts || [],
      events: response?.events || [],
    });
  } catch (error) {
    $("[data-job-detail]").replaceChildren();
    const message = document.createElement("div");
    message.className = "detail-error";
    message.textContent = normalizeError(error);
    $("[data-job-detail]").append(message);
  }
}

function fillSettings(settings) {
  const form = $("[data-settings-form]");
  if (!form || !settings) return;
  Object.entries(settings).forEach(([key, value]) => {
    const field = form.elements.namedItem(key);
    if (!field) return;
    if (field.type === "checkbox") field.checked = Boolean(value);
    else field.value = value ?? "";
  });
  setTheme(settings.theme || localStorage.getItem("downloadhub:theme") || "system", false);
}

async function loadSettings({ open = false } = {}) {
  if (open) openDialog($("[data-settings-dialog]"));
  try {
    const settings = await apiFetch("/settings");
    state.settings = settings;
    fillSettings(settings);
    updateCounts();
  } catch (error) {
    if (open) showMessage($("[data-settings-message]"), normalizeError(error));
  }
}

async function saveSettings(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const button = $('button[type="submit"]', form);
  const message = $("[data-settings-message]");
  showMessage(message);
  if (!form.reportValidity()) return;
  const data = new FormData(form);
  const payload = {
    download_dir: String(data.get("download_dir") || ""),
    max_concurrent_jobs: Number(data.get("max_concurrent_jobs")),
    max_total_connections: Number(data.get("max_total_connections")),
    split_count: Number(data.get("split_count")),
    global_speed_limit: String(data.get("global_speed_limit") || "0"),
    timezone: String(data.get("timezone") || "Europe/Istanbul"),
    allow_private_networks: data.get("allow_private_networks") === "on",
    theme: String(data.get("theme") || "system"),
    browser_name: String(data.get("browser_name") || "chrome"),
    browser_profile: String(data.get("browser_profile") || "").trim() || "Default",
    daily_window_start: String(data.get("daily_window_start") || "") || null,
    daily_window_end: String(data.get("daily_window_end") || "") || null,
  };
  setBusy(button, true);
  try {
    state.settings = await apiFetch("/settings", { method: "PUT", body: JSON.stringify(payload) });
    fillSettings(state.settings || payload);
    setTheme(payload.theme);
    showMessage(message, "Ayarlar kaydedildi.", "success");
    showToast("Ayarlar kaydedildi", "Yeni tercihler etkinleştirildi.");
    window.setTimeout(() => closeDialog($("[data-settings-dialog]")), 450);
  } catch (error) {
    showMessage(message, normalizeError(error));
  } finally {
    setBusy(button, false);
  }
}

function renderRuntime(health) {
  const list = $("[data-runtime-list]");
  if (!list) return;
  list.replaceChildren();
  const components = health?.components || [];
  if (!components.length) {
    const message = document.createElement("div");
    message.className = "runtime-placeholder";
    message.textContent = "Bileşen bilgisi alınamadı.";
    list.append(message);
    return;
  }
  components.forEach((component) => {
    const item = document.createElement("div");
    item.className = `runtime-item${component.available ? "" : " is-missing"}`;
    const icon = document.createElement("span");
    icon.className = "runtime-state";
    icon.textContent = component.available ? "✓" : "!";
    const copy = document.createElement("span");
    const title = document.createElement("strong");
    title.textContent = component.name;
    const detail = document.createElement("small");
    detail.textContent = component.available ? component.version || "Hazır" : component.required ? "Gerekli · Bulunamadı" : "İsteğe bağlı · Bulunamadı";
    copy.append(title, detail);
    item.append(icon, copy);
    list.append(item);
  });
}

async function checkHealth() {
  const card = $(".service-card");
  try {
    const response = await fetch("/health", { headers: { Accept: "application/json" }, credentials: "same-origin" });
    if (!response.ok) throw new Error();
    const health = await response.json();
    card?.classList.add("is-online");
    card?.classList.remove("is-error");
    $("[data-service-label]").textContent = ["ok", "healthy", "ready"].includes(health.status) ? "Servis hazır" : "Servis sınırlı";
    $("[data-service-detail]").textContent = "127.0.0.1:8765";
    if (health.version) $("[data-app-version]").textContent = `v${health.version}`;
    renderRuntime(health);
  } catch {
    card?.classList.remove("is-online");
    card?.classList.add("is-error");
    $("[data-service-label]").textContent = "Servise ulaşılamadı";
    $("[data-service-detail]").textContent = "DownloadHub'ı yeniden açın";
    renderRuntime(null);
  }
}

function showPairingCode(code) {
  const root = $("[data-pairing-code]");
  root.replaceChildren();
  const normalized = String(code || "").replace(/\s+/g, "").toUpperCase();
  [...(normalized || "——————")].forEach((character) => {
    const span = document.createElement("span");
    span.textContent = character;
    root.append(span);
  });
}

function startPairingCountdown(expiresAt) {
  window.clearInterval(state.pairingTimer);
  const label = $("[data-pairing-expiry]");
  const update = () => {
    const seconds = Math.max(0, Math.floor((new Date(expiresAt).getTime() - Date.now()) / 1000));
    if (seconds <= 0) {
      label.textContent = "Kodun süresi doldu. Yeni bir kod üretin.";
      window.clearInterval(state.pairingTimer);
      return;
    }
    label.textContent = `Kod ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")} içinde sona erer.`;
  };
  update();
  state.pairingTimer = window.setInterval(update, 1000);
}

async function startPairing() {
  const message = $("[data-pairing-message]");
  showMessage(message);
  showPairingCode("");
  $("[data-pairing-expiry]").textContent = "Kod hazırlanıyor…";
  try {
    const result = await apiFetch("/pair/start", { method: "POST" });
    showPairingCode(result.code);
    startPairingCountdown(result.expires_at);
  } catch (error) {
    $("[data-pairing-expiry]").textContent = "Kod üretilemedi.";
    showMessage(message, normalizeError(error));
  }
}

async function loadPairedClients() {
  const root = $("[data-paired-clients]");
  if (!root) return;
  try {
    const clients = await apiFetch("/pair/clients");
    root.replaceChildren();
    if (!clients.length) {
      const empty = document.createElement("p");
      empty.textContent = "Henüz eşleştirilmiş tarayıcı yok.";
      root.append(empty);
      return;
    }
    clients.forEach((client) => {
      const row = document.createElement("div");
      row.className = "paired-client-row";
      const copy = document.createElement("span");
      const name = document.createElement("strong");
      name.textContent = client.name || "Chromium";
      const detail = document.createElement("small");
      detail.textContent = client.last_seen_at
        ? `Son bağlantı ${formatDate(client.last_seen_at)}`
        : `Eşleştirildi ${formatDate(client.created_at)}`;
      copy.append(name, detail);
      const revoke = document.createElement("button");
      revoke.type = "button";
      revoke.className = "small-button danger-ghost";
      revoke.textContent = "Erişimi iptal et";
      revoke.addEventListener("click", async () => {
        revoke.disabled = true;
        try {
          await apiFetch("/pair/revoke", {
            method: "POST",
            body: JSON.stringify({ client_id: client.id }),
          });
          showToast("Eklenti erişimi iptal edildi", client.name || "Chromium");
          await loadPairedClients();
        } catch (error) {
          revoke.disabled = false;
          showMessage($("[data-pairing-message]"), normalizeError(error));
        }
      });
      row.append(copy, revoke);
      root.append(row);
    });
  } catch (error) {
    root.replaceChildren();
    const message = document.createElement("p");
    message.textContent = normalizeError(error);
    root.append(message);
  }
}

function bindEvents() {
  $("[data-inspect-form]").addEventListener("submit", inspectUrl);
  $("[data-create-job-form]").addEventListener("submit", createJob);
  $("[data-settings-form]").addEventListener("submit", saveSettings);

  $("[data-clear-url]").addEventListener("click", () => {
    const input = $("#download-url");
    input.value = "";
    input.focus();
    hideInspection();
    showMessage($("[data-inspect-message]"));
  });

  $("[data-close-inspection]").addEventListener("click", hideInspection);
  $("[data-preset-select]").addEventListener("change", updateOutputEstimate);
  $("[data-format-select]").addEventListener("change", updateOutputEstimate);
  $("[data-category-select]").addEventListener("change", (event) => { event.currentTarget.dataset.userChanged = "true"; });

  $("[data-playlist-search]").addEventListener("input", filterPlaylist);
  $("[data-playlist-viewport]").addEventListener("scroll", renderPlaylistVirtual, { passive: true });
  $("[data-playlist-window]").addEventListener("change", (event) => {
    const checkbox = event.target.closest("[data-playlist-id]");
    if (!checkbox) return;
    if (checkbox.checked) state.playlist.selected.add(checkbox.dataset.playlistId);
    else state.playlist.selected.delete(checkbox.dataset.playlistId);
    updatePlaylistSelection();
  });
  $("[data-select-all]").addEventListener("click", () => {
    state.playlist.items.forEach((item) => state.playlist.selected.add(item.id));
    renderPlaylistVirtual();
    updatePlaylistSelection();
  });
  $("[data-select-none]").addEventListener("click", () => {
    state.playlist.selected.clear();
    renderPlaylistVirtual();
    updatePlaylistSelection();
  });

  $$('[data-filter]').forEach((button) => button.addEventListener("click", () => setFilter(button.dataset.filter)));
  $("[data-job-search]").addEventListener("input", (event) => {
    state.search = event.target.value;
    renderJobs();
  });

  $("[data-jobs-list]").addEventListener("click", (event) => {
    if (event.target.closest("[data-job-detail-open]")) {
      const row = event.target.closest("[data-job-id]");
      if (row) openJobDetail(row.dataset.jobId);
      return;
    }
    handleJobAction(event);
  });
  $("[data-jobs-list]").addEventListener("change", handleJobSelect);

  $$('[data-bulk-action]').forEach((button) => button.addEventListener("click", () => bulkAction(button.dataset.bulkAction)));
  $("[data-refresh-jobs]").addEventListener("click", () => loadJobs());
  $("[data-load-more]").addEventListener("click", () => loadJobs({ quiet: true, append: true }));

  $$('[data-view]').forEach((button) => button.addEventListener("click", () => {
    state.view = button.dataset.view;
    localStorage.setItem("downloadhub:view", state.view);
    $$('[data-view]').forEach((item) => {
      const active = item.dataset.view === state.view;
      item.classList.toggle("is-active", active);
      item.setAttribute("aria-pressed", String(active));
    });
    renderJobs();
  }));

  $$('[data-focus-url]').forEach((button) => button.addEventListener("click", () => {
    $("#download-url").focus({ preventScroll: true });
    $(".capture-card").scrollIntoView({ behavior: "smooth", block: "center" });
  }));

  $("[data-theme-toggle]").addEventListener("click", cycleTheme);
  $("[data-sidebar-open]").addEventListener("click", () => setSidebar(true));
  $$('[data-sidebar-close]').forEach((button) => button.addEventListener("click", () => setSidebar(false)));

  $$('[data-open-settings]').forEach((button) => button.addEventListener("click", () => loadSettings({ open: true })));
  $$('[data-open-pairing]').forEach((button) => button.addEventListener("click", () => {
    openDialog($("[data-pairing-dialog]"));
    startPairing();
    loadPairedClients();
  }));
  $("[data-refresh-pairing]").addEventListener("click", startPairing);
  $("[data-refresh-clients]").addEventListener("click", loadPairedClients);

  $$('[data-close-dialog]').forEach((button) => button.addEventListener("click", () => closeDialog(button.closest("dialog"))));
  $$('dialog').forEach((dialog) => {
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) closeDialog(dialog);
    });
  });

  $$('[data-cancel-choice]').forEach((button) => button.addEventListener("click", async () => {
    const keepPartial = button.dataset.cancelChoice === "keep";
    const ids = [...state.cancelTargets];
    button.disabled = true;
    const results = await Promise.all(ids.map((id) => controlJob(id, "cancel", {
      keepPartial,
      reload: false,
      silent: true,
    })));
    button.disabled = false;
    state.cancelTargets = [];
    state.selectedJobs.clear();
    closeDialog($("[data-cancel-dialog]"));
    await loadJobs({ quiet: true });
    const completed = results.filter(Boolean).length;
    showToast(
      completed ? "İndirme iptal edildi" : "İptal işlemi tamamlanamadı",
      completed ? `${completed} görev iptal edildi.` : "Görev durumunu yenileyip yeniden deneyin.",
      completed ? "success" : "error",
    );
  }));

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && document.body.classList.contains("sidebar-open")) {
      event.preventDefault();
      setSidebar(false);
      return;
    }
    const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName);
    if ((event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase("tr-TR") === "k") {
      event.preventDefault();
      $("[data-job-search]").focus();
    } else if (!typing && event.key === "/") {
      event.preventDefault();
      $("#download-url").focus();
    }
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) loadJobs({ quiet: true });
  });
  window.addEventListener("online", () => {
    checkHealth();
    loadJobs({ quiet: true });
  });
  window.addEventListener("offline", () => {
    const card = $(".service-card");
    card?.classList.remove("is-online");
    card?.classList.add("is-error");
    $("[data-service-label]").textContent = "Ağ bağlantısı yok";
  });
  window.addEventListener("resize", syncSidebarAccessibility, { passive: true });
  window.addEventListener("beforeunload", () => state.eventSource?.close());
}

function consumeLaunchParameters() {
  const current = new URL(window.location.href);
  const sharedUrl = current.searchParams.get("url")?.trim();
  const shouldPair = current.searchParams.get("pair") === "1";
  let parsedUrl = null;

  if (sharedUrl) {
    try {
      const candidate = new URL(sharedUrl);
      if (/^https?:$/.test(candidate.protocol)) parsedUrl = candidate.href;
    } catch {
      parsedUrl = null;
    }
  }

  if (sharedUrl || shouldPair) {
    current.searchParams.delete("url");
    current.searchParams.delete("pair");
    history.replaceState(null, "", `${current.pathname}${current.search}${current.hash}`);
  }

  if (shouldPair) {
    openDialog($("[data-pairing-dialog]"));
    startPairing();
  }

  if (parsedUrl) {
    $("#download-url").value = parsedUrl;
    $("[data-inspect-form]").requestSubmit();
  }
}

async function init() {
  setTheme(localStorage.getItem("downloadhub:theme") || "system", false);
  await loadTranslations();
  bindEvents();
  syncSidebarAccessibility();
  $$('[data-view]').forEach((item) => {
    const active = item.dataset.view === state.view;
    item.classList.toggle("is-active", active);
    item.setAttribute("aria-pressed", String(active));
  });

  await Promise.allSettled([
    loadSettings(),
    loadJobs({ quiet: true }),
    checkHealth(),
  ]);
  connectEvents();
  consumeLaunchParameters();
  document.documentElement.dataset.uiReady = "true";
}

init();
