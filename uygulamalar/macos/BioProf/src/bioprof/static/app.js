(function () {
  "use strict";

  const shell = document.querySelector(".app-shell");
  if (!shell) return;
  const API = shell.dataset.apiPrefix || "/api/v1";
  const state = {
    notebooks: [], notebookId: "", sources: [], artifacts: [], selectedSources: new Set(),
    selectedArtifacts: new Set(), answerMode: "strict", citations: new Map(),
    jobs: new Map(), jobContexts: new Map(), recorder: null, audioChunks: [],
    conversationId: null,
  };
  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];

  function apiPath(path) {
    const normalized = path.startsWith("/") ? path : `/${path}`;
    if (
      normalized === API
      || normalized.startsWith(`${API}/`)
      || normalized.startsWith("/v1/")
    ) return normalized;
    return `${API}${normalized}`;
  }

  async function api(path, options = {}) {
    const response = await fetch(apiPath(path), {
      headers: options.body instanceof FormData ? options.headers : { "Content-Type": "application/json", ...(options.headers || {}) },
      ...options,
    });
    if (!response.ok) {
      let message = `HTTP ${response.status}`;
      try {
        const body = await response.json();
        const detail = body.detail || body.error;
        message = typeof detail === "string" ? detail : detail?.message || detail?.code || message;
      } catch (_) { /* body is not JSON */ }
      throw new Error(message);
    }
    if (response.status === 204) return null;
    const type = response.headers.get("content-type") || "";
    return type.includes("json") ? response.json() : response;
  }

  function items(value, keys = ["items", "data", "notebooks", "sources", "artifacts", "providers", "models"]) {
    if (Array.isArray(value)) return value;
    for (const key of keys) if (Array.isArray(value?.[key])) return value[key];
    return [];
  }

  function systemCatalog(providerPayload, modelPayload) {
    const body = modelPayload && !Array.isArray(modelPayload) ? modelPayload : {};
    const providerMap = new Map();
    [...items(providerPayload, ["items", "providers"]), ...items(body.providers)].forEach(provider => {
      const normalized = typeof provider === "string" ? { name: provider, available: true, models: [] } : provider;
      const name = normalized?.name || normalized?.id;
      if (!name) return;
      const previous = providerMap.get(name) || {};
      providerMap.set(name, { ...previous, ...normalized, name, models: normalized.models || previous.models || [] });
    });

    const models = [];
    const seen = new Set();
    function addModel(value, label, provider = "", disabled = false, origin = "") {
      if (!value) return;
      const key = `${provider}\u0000${value}`;
      if (seen.has(key)) return;
      seen.add(key);
      models.push({ value, label: label || value, provider, disabled, origin });
    }

    [...providerMap.values()].forEach(provider => {
      (Array.isArray(provider.models) ? provider.models : []).forEach(model => {
        const id = typeof model === "string" ? model : model?.id || model?.name;
        addModel(id, `${id} · ${provider.name}`, provider.name, provider.available === false, "provider");
      });
    });
    items(body.local_profiles, ["local_profiles"]).forEach(profile => {
      const value = typeof profile === "string" ? profile : profile.repo_id || profile.id;
      const title = typeof profile === "string" ? profile : profile.title || profile.repo_id || profile.id;
      const stateLabel = profile.active ? "aktif" : profile.downloaded ? "yerel" : "indirilmemiş";
      addModel(
        value,
        `${title} · ${stateLabel}`,
        profile.active ? "local_model" : "",
        profile.downloaded === false || profile.engine_available === false,
        "local_profile",
      );
    });
    items(body.registry, ["registry"]).forEach(entry => {
      const value = typeof entry === "string" ? entry : entry.name || entry.id;
      const status = typeof entry === "string" ? "registry" : entry.status || "candidate";
      addModel(value, `${value} · ${status}`, "local_model", status !== "champion", "registry");
    });
    return { providers: [...providerMap.values()], models };
  }

  function toast(message, kind = "") {
    const node = document.createElement("div");
    node.className = `toast ${kind}`;
    node.textContent = message;
    $("#toast-region").append(node);
    window.setTimeout(() => node.remove(), 4500);
  }

  function openDialog(id) { const dialog = $(id); if (dialog && !dialog.open) dialog.showModal(); }
  function closeDialogs() { $$('dialog[open]').forEach(dialog => dialog.close()); }

  async function loadNotebooks(selectNewest = false) {
    state.notebooks = items(await api("/notebooks"));
    const select = $("#notebook-select");
    select.replaceChildren(new Option("Notebook seçin", ""));
    state.notebooks.forEach(notebook => select.add(new Option(notebook.name || notebook.title || "Adsız notebook", notebook.id)));
    const stored = localStorage.getItem("bioprof.notebook");
    const candidate = selectNewest ? state.notebooks[0]?.id : (stored && state.notebooks.some(n => n.id === stored) ? stored : state.notebooks[0]?.id);
    if (candidate) await selectNotebook(candidate);
  }

  async function selectNotebook(notebookId) {
    state.notebookId = notebookId;
    localStorage.setItem("bioprof.notebook", notebookId);
    $("#notebook-select").value = notebookId;
    const notebook = state.notebooks.find(item => item.id === notebookId);
    const privacy = notebook?.privacy_mode || "local_first";
    $("#privacy-pill").lastChild.textContent = ` ${privacy === "local_only" ? "Yalnız yerel" : privacy === "cloud_allowed" ? "Buluta izinli" : "Yerel öncelikli"}`;
    state.selectedArtifacts = new Set();
    state.conversationId = null;
    // Not editörü hemen sıfırlanır: loadNotes tamamlanana kadar eski
    // notebook'un noteId'siyle Kaydet/Sil basılması başka notebook'un notunu
    // değiştirebilirdi (Codex bulgusu).
    state.notes = [];
    selectNote("");
    renderNoteSelect();
    await Promise.all([loadSources(), loadArtifacts(), loadNotes(), loadConversations()]);
    window.BioProfFlashcards?.loadDecks?.(notebookId);
  }

  // --- Notlar: DB'de yaşar; eski localStorage notu bir kez içeri taşınır. ---
  async function loadNotes() {
    const istekNotebook = state.notebookId;
    if (!istekNotebook) return;
    let notes = [];
    try { notes = await api(`/notebooks/${encodeURIComponent(istekNotebook)}/notes`); }
    catch (_) { notes = []; }
    if (state.notebookId !== istekNotebook) return; // bayat yanıt
    state.notes = notes;
    await migrateLocalNotes(istekNotebook);
    if (state.notebookId !== istekNotebook) return;
    renderNoteSelect();
    selectNote(state.notes[0]?.id || "");
  }

  async function migrateLocalNotes(notebookId) {
    const anahtar = `bioprof.notes.${notebookId}`;
    const eski = localStorage.getItem(anahtar);
    if (!eski || !eski.trim() || localStorage.getItem(`${anahtar}.migrated`)) return;
    if (state.notes.some(note => note.content === eski)) { localStorage.setItem(`${anahtar}.migrated`, "1"); return; }
    // İşaret POST'tan ÖNCE konur: eşzamanlı iki yükleme aynı notu iki kez
    // taşıyamaz. POST başarısızsa işaret geri alınır, veri localStorage'da kalır.
    localStorage.setItem(`${anahtar}.migrated`, "1");
    try {
      const yeni = await api(`/notebooks/${encodeURIComponent(notebookId)}/notes`, {
        method: "POST", body: JSON.stringify({ title: "Yerel notlar (aktarıldı)", content: eski }),
      });
      if (state.notebookId === notebookId) state.notes.unshift(yeni);
      localStorage.removeItem(anahtar);
      toast("Bu Mac'teki eski notlar notebook'a taşındı.", "success");
    } catch (_) { localStorage.removeItem(`${anahtar}.migrated`); }
  }

  function renderNoteSelect() {
    const select = $("#note-select");
    select.replaceChildren(new Option("Yeni not…", ""));
    (state.notes || []).forEach(note => select.add(new Option(`${note.pinned ? "📌 " : ""}${note.title || "Adsız not"}`, note.id)));
  }

  function selectNote(noteId) {
    state.noteId = noteId || "";
    $("#note-select").value = state.noteId;
    const note = (state.notes || []).find(item => item.id === state.noteId);
    $("#note-title").value = note?.title || "";
    $("#notes-input").value = note?.content || "";
    $("#delete-note").hidden = !state.noteId;
  }

  async function saveNote() {
    if (!state.notebookId) return;
    const body = { title: $("#note-title").value.trim(), content: $("#notes-input").value };
    try {
      if (state.noteId) await api(`/notes/${encodeURIComponent(state.noteId)}`, { method: "PATCH", body: JSON.stringify(body) });
      else {
        const yeni = await api(`/notebooks/${encodeURIComponent(state.notebookId)}/notes`, { method: "POST", body: JSON.stringify(body) });
        state.noteId = yeni.id;
      }
      state.notes = await api(`/notebooks/${encodeURIComponent(state.notebookId)}/notes`);
      renderNoteSelect(); $("#note-select").value = state.noteId; $("#delete-note").hidden = false;
      toast("Not kaydedildi.", "success");
    } catch (error) { toast(`Not kaydedilemedi: ${error.message}`, "error"); }
  }

  // --- Sohbet geçmişi ---
  async function loadConversations() {
    const istekNotebook = state.notebookId;
    if (!istekNotebook) return;
    let conversations = [];
    try { conversations = await api(`/notebooks/${encodeURIComponent(istekNotebook)}/conversations`); }
    catch (_) { conversations = []; }
    if (state.notebookId !== istekNotebook) return; // bayat yanıt
    state.conversations = conversations;
    const select = $("#conversation-select");
    select.replaceChildren(new Option("Yeni sohbet", ""));
    (state.conversations || []).forEach(conversation =>
      select.add(new Option(`${conversation.title || "Sohbet"} · ${formatDate(conversation.created_at)}`, conversation.id)));
    select.value = state.conversationId || "";
    $("#delete-conversation").hidden = !state.conversationId;
  }

  async function openConversation(conversationId) {
    state.conversationId = conversationId || null;
    $("#delete-conversation").hidden = !state.conversationId;
    const container = $("#messages");
    container.replaceChildren();
    if (!state.conversationId) return;
    try {
      const messages = await api(`/conversations/${encodeURIComponent(state.conversationId)}/messages`);
      messages.forEach(message => appendMessage(
        message.role === "user" ? "user" : "assistant",
        message.content,
        { citations: message.citations || [], provider: message.provider, model: message.model },
      ));
    } catch (error) { toast(`Sohbet yüklenemedi: ${error.message}`, "error"); }
  }

  async function loadSources() {
    // İsteğin başladığı notebook yakalanır; yanıt geldiğinde kullanıcı başka
    // notebook'a geçtiyse bayat liste state'e yazılmaz — aksi hâlde "Sil"
    // düğmesi başka notebook'un gerçek verisini silebilirdi (Codex bulgusu).
    const istekNotebook = state.notebookId;
    if (!istekNotebook) return;
    const sources = items(await api(`/notebooks/${encodeURIComponent(istekNotebook)}/sources`), ["items", "sources"]);
    if (state.notebookId !== istekNotebook) return;
    state.sources = sources;
    const old = state.selectedSources;
    state.selectedSources = new Set(state.sources.filter(source => old.size === 0 || old.has(source.id)).map(source => source.id));
    renderSources();
  }

  function renderSources() {
    const list = $("#source-list");
    const query = $("#source-filter").value.trim().toLocaleLowerCase("tr");
    const shown = state.sources.filter(source => (source.title || source.original_name || "").toLocaleLowerCase("tr").includes(query));
    list.replaceChildren();
    if (!shown.length) {
      const empty = document.createElement("div"); empty.className = "empty-state compact"; empty.textContent = state.sources.length ? "Filtreyle eşleşen kaynak yok." : "Kaynaklar burada görünecek."; list.append(empty);
    }
    shown.forEach(source => {
      const row = document.createElement("label"); row.className = "source-item";
      const checkbox = document.createElement("input"); checkbox.type = "checkbox"; checkbox.checked = state.selectedSources.has(source.id);
      checkbox.addEventListener("change", () => { checkbox.checked ? state.selectedSources.add(source.id) : state.selectedSources.delete(source.id); updateSelection(); });
      const content = document.createElement("div"); const title = document.createElement("strong"); title.textContent = source.title || source.original_name || source.id;
      const doclingStatus = source.metadata?.docling_status;
      const doclingLabel = doclingStatus ? (doclingStatus.startsWith("Docling kapalı") ? "Docling kapalı" : "Docling fallback") : "";
      const meta = document.createElement("small"); meta.textContent = [source.mime_type?.split("/").pop(), source.language, source.license, doclingLabel].filter(Boolean).join(" · ");
      if (doclingStatus) meta.title = doclingStatus;
      content.append(title, meta);
      const statusDot = document.createElement("span"); statusDot.className = `source-state ${source.status || "queued"}`; statusDot.title = source.status || "queued";
      const remove = document.createElement("button"); remove.className = "text-button danger source-remove"; remove.textContent = "×"; remove.title = "Kaynağı sil";
      remove.addEventListener("click", async event => {
        event.preventDefault(); event.stopPropagation();
        if (!window.confirm(`"${source.title || source.original_name}" kaynağı ve indeksi silinsin mi?`)) return;
        try { await api(`/sources/${encodeURIComponent(source.id)}`, { method: "DELETE" }); state.selectedSources.delete(source.id); await loadSources(); toast("Kaynak silindi.", "success"); }
        catch (error) { toast(`Kaynak silinemedi: ${error.message}`, "error"); }
      });
      row.dataset.sourceId = source.id;
      row.append(checkbox, content, statusDot, remove); list.append(row);
    });
    $("#source-count").textContent = `${state.sources.length} kaynak`;
    updateSelection();
  }

  function updateSelection() {
    $("#evidence-selection").textContent = `${state.selectedSources.size} seçili kaynak`;
    $("#source-select-all").checked = state.sources.length > 0 && state.selectedSources.size === state.sources.length;
    $("#source-select-all").indeterminate = state.selectedSources.size > 0 && state.selectedSources.size < state.sources.length;
  }

  async function loadArtifacts() {
    const istekNotebook = state.notebookId;
    if (!istekNotebook) return;
    let artifacts = [];
    try { artifacts = items(await api(`/notebooks/${encodeURIComponent(istekNotebook)}/artifacts`), ["items", "artifacts"]); }
    catch (_) { artifacts = []; }
    if (state.notebookId !== istekNotebook) return; // bayat yanıt
    state.artifacts = artifacts;
    renderArtifacts();
  }

  async function fetchArtifact(id) {
    return api(`/artifacts/${encodeURIComponent(id)}`);
  }

  function renderArtifacts() {
    const list = $("#artifact-list"); list.replaceChildren();
    if (!state.artifacts.length) { const empty = document.createElement("div"); empty.className = "empty-state compact"; empty.textContent = "Henüz çıktı yok."; list.append(empty); return; }
    state.artifacts.slice(0, 12).forEach(artifact => {
      const row = document.createElement("div"); row.className = "artifact-row";
      const check = document.createElement("input"); check.type = "checkbox"; check.className = "artifact-check"; check.title = "Öğrenci paketine ekle";
      check.checked = state.selectedArtifacts.has(artifact.id);
      check.addEventListener("change", () => { check.checked ? state.selectedArtifacts.add(artifact.id) : state.selectedArtifacts.delete(artifact.id); updatePaketButton(); });
      const body = document.createElement("div"); const title = document.createElement("strong"); title.textContent = artifact.title || artifact.kind;
      const meta = document.createElement("small");
      const sure = artifact.metadata?.structured_data?.estimated_seconds;
      meta.textContent = [`${artifact.kind || "studio"}`, formatDate(artifact.created_at), sure ? `≈ ${Math.round(sure / 60)} dk` : ""].filter(Boolean).join(" · ");
      body.append(title, meta);
      const actions = document.createElement("div"); actions.className = "artifact-actions";
      function addAction(label, handler, danger = false) {
        const button = document.createElement("button"); button.className = `text-button${danger ? " danger" : ""}`; button.textContent = label;
        button.addEventListener("click", handler); actions.append(button);
      }
      // Tür-duyarlı görüntüleyiciler: yapı dosyayı indirmeden API'den okunur.
      if (artifact.kind === "slides") addAction("Sun", async () => { try { window.BioProfSlides.open(await fetchArtifact(artifact.id)); } catch (error) { toast(`Sunum açılamadı: ${error.message}`, "error"); } });
      if (artifact.kind === "mind_map" || artifact.kind === "infographic") addAction("Harita", async () => { try { window.BioProfMindMap.open(await fetchArtifact(artifact.id)); } catch (error) { toast(`Harita açılamadı: ${error.message}`, "error"); } });
      if (artifact.kind === "flashcards") addAction("Desteye çevir", () => createDeckFromArtifact(artifact));
      if (artifact.download_url || artifact.url) addAction("İndir", () => window.open(artifact.download_url || artifact.url, "_blank", "noopener"));
      addAction("Sil", async () => {
        if (!window.confirm(`"${artifact.title || artifact.kind}" çıktısı ve dosyaları silinsin mi?`)) return;
        try { await api(`/artifacts/${encodeURIComponent(artifact.id)}`, { method: "DELETE" }); state.selectedArtifacts.delete(artifact.id); await loadArtifacts(); toast("Çıktı silindi.", "success"); }
        catch (error) { toast(`Silinemedi: ${error.message}`, "error"); }
      }, true);
      row.append(check, body, actions); list.append(row);
    });
    updatePaketButton();
  }

  async function createDeckFromArtifact(artifact) {
    try {
      const result = await api(`/notebooks/${encodeURIComponent(state.notebookId)}/flashcard-decks`, {
        method: "POST", body: JSON.stringify({ artifact_id: artifact.id, title: artifact.title }),
      });
      toast(`"${result.title}" destesi oluşturuldu (${result.card_count} kart).`, "success");
      window.BioProfFlashcards?.loadDecks?.(state.notebookId);
      $(".tab[data-tab='study']")?.click();
    } catch (error) { toast(`Deste oluşturulamadı: ${error.message}`, "error"); }
  }

  function updatePaketButton() {
    const button = $("#paket-button");
    if (!button) return;
    button.disabled = state.selectedArtifacts.size === 0;
    button.textContent = state.selectedArtifacts.size ? `Öğrenci paketi indir (${state.selectedArtifacts.size})` : "Öğrenci paketi indir";
  }

  async function loadSystem() {
    const [providersValue, modelsValue] = await Promise.allSettled([api("/providers"), api("/models")]);
    const catalog = systemCatalog(
      providersValue.status === "fulfilled" ? providersValue.value : [],
      modelsValue.status === "fulfilled" ? modelsValue.value : {},
    );
    const providerSelect = $("#provider-select"); providerSelect.replaceChildren(new Option("Otomatik sağlayıcı", ""));
    const system = $("#provider-status"); system.replaceChildren();
    catalog.providers.forEach(provider => {
      const name = typeof provider === "string" ? provider : provider.name || provider.id;
      const option = new Option(name, name); option.disabled = provider.available === false; providerSelect.add(option);
      const row = document.createElement("div"); row.className = "system-item";
      const label = document.createElement("span"); label.textContent = name;
      const status = document.createElement("span"); status.textContent = provider.available === false ? "kapalı" : "hazır"; status.style.color = provider.available === false ? "var(--amber)" : "var(--accent)";
      row.append(label, status); system.append(row);
    });
    const modelSelect = $("#model-select"); modelSelect.replaceChildren(new Option("Otomatik model", ""));
    catalog.models.forEach(model => {
      const option = new Option(model.label, model.value); option.disabled = model.disabled;
      option.dataset.provider = model.provider; option.dataset.origin = model.origin; modelSelect.add(option);
    });
    modelSelect.onchange = () => {
      const provider = modelSelect.selectedOptions[0]?.dataset.provider;
      const matching = [...providerSelect.options].find(option => option.value === provider && !option.disabled);
      if (matching) providerSelect.value = provider;
    };
  }

  function appendMessage(role, content, envelope = {}) {
    const welcome = $(".welcome-card"); if (welcome) welcome.remove();
    const article = document.createElement("article"); article.className = `message ${role}`;
    const bubble = document.createElement("div"); bubble.className = "message-bubble";
    if (content instanceof Node) bubble.append(content); else renderGroundedText(bubble, String(content), envelope.citations || []);
    article.append(bubble);
    if (role === "assistant") {
      const meta = document.createElement("div"); meta.className = "message-meta";
      meta.textContent = [envelope.provider, envelope.model, envelope.evidence_status, envelope.degraded && "⚠ yerel model kullanılamadı — kanıt özeti", envelope.trace_id && `iz ${String(envelope.trace_id).slice(0, 8)}`].filter(Boolean).join(" · ");
      article.append(meta);
    }
    $("#messages").append(article); $("#messages").scrollTop = $("#messages").scrollHeight;
    return article;
  }

  function citationLabel(citation, index) {
    const explicit = citation?.label || citation?.citation_label;
    if (explicit) return String(explicit).replace(/^\[|\]$/g, "");
    return `S${index + 1}`;
  }

  function renderGroundedText(container, text, citations) {
    const citationsByLabel = new Map();
    citations.forEach((citation, index) => {
      const label = citationLabel(citation, index);
      citationsByLabel.set(label, citation);
      state.citations.set(citation.id || citation.citation_id || label, citation);
      state.citations.set(label, citation);
    });
    const chunks = text.split(/(\[(?:S|K)\d+\])/g);
    chunks.forEach(chunk => {
      if (/^\[(?:S|K)\d+\]$/.test(chunk)) {
        const label = chunk.slice(1, -1); const citation = citationsByLabel.get(label);
        const button = document.createElement("button"); button.className = "citation-button"; button.textContent = chunk;
        button.addEventListener("click", () => showCitation(citation?.id || citation?.citation_id || label, citation)); container.append(button);
      } else {
        chunk.split(/\n{2,}/).forEach((paragraph, index) => {
          if (!paragraph) return; if (index) container.append(document.createElement("br"));
          const span = document.createElement("span"); span.className = "message-line"; span.textContent = paragraph.replace(/^#+\s*/gm, "").replace(/\*\*/g, ""); container.append(span);
        });
      }
    });
  }

  async function showCitation(id, known) {
    try {
      const citation = known || state.citations.get(id) || await api(`/citations/${encodeURIComponent(id)}`);
      const detail = $("#citation-detail"); detail.replaceChildren();
      const heading = document.createElement("div"); heading.className = "modal-heading";
      const wrap = document.createElement("div"); const eyebrow = document.createElement("span"); eyebrow.className = "eyebrow"; eyebrow.textContent = "Kanıt alıntısı";
      const title = document.createElement("h2"); title.textContent = citation.source_title || citation.title || citation.label || "Kaynak"; wrap.append(eyebrow, title); heading.append(wrap);
      const quote = document.createElement("blockquote"); quote.className = "citation-quote"; quote.textContent = citation.quote || citation.text || "Alıntı metni yok.";
      const meta = document.createElement("div"); meta.className = "citation-meta";
      meta.textContent = [citation.section, citation.page && `Sayfa ${citation.page}`, citation.timestamp_start != null && `${citation.timestamp_start}–${citation.timestamp_end || ""} sn`].filter(Boolean).join(" · ");
      detail.append(heading, quote, meta); openDialog("#citation-dialog");
      highlightSource(citation.source_id);
    } catch (error) { toast(`Alıntı açılamadı: ${error.message}`, "error"); }
  }

  function highlightSource(sourceId) {
    if (!sourceId) return;
    const row = $(`#source-list .source-item[data-source-id="${CSS.escape(sourceId)}"]`);
    if (!row) return;
    document.querySelectorAll("#source-list .source-item.cited").forEach(item => item.classList.remove("cited"));
    row.classList.add("cited");
    row.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }

  async function* sseEvents(path, body) {
    const response = await fetch(`${API}${path}`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });
    if (!response.ok || !response.body) throw new Error(`Akış başlatılamadı (${response.status})`);
    const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = "";
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let boundary;
      while ((boundary = buffer.indexOf("\n\n")) >= 0) {
        const raw = buffer.slice(0, boundary); buffer = buffer.slice(boundary + 2);
        let name = "message"; const dataLines = [];
        raw.split("\n").forEach(line => {
          if (line.startsWith("event:")) name = line.slice(6).trim();
          else if (line.startsWith("data:")) dataLines.push(line.slice(5).trim());
        });
        if (!dataLines.length) continue;
        try { yield { name, data: JSON.parse(dataLines.join("\n")) }; } catch { /* retry satırı */ }
      }
    }
  }

  async function ask(question) {
    if (!state.notebookId) { toast("Önce bir notebook oluşturun veya seçin.", "error"); return; }
    // Akış sürerken notebook değişirse sonuç NE görüntülenir NE de sohbet
    // kimliği yeni notebook'un state'ine yazılır (Codex bulgusu: eski kimlik
    // sonraki soruda 409 üretiyordu).
    const istekNotebook = state.notebookId;
    question = question.trim(); if (!question) return;
    appendMessage("user", question); $("#question-input").value = ""; $("#send-button").disabled = true;
    const dots = document.createElement("span"); dots.className = "typing"; dots.innerHTML = "<i></i><i></i><i></i>"; const pending = appendMessage("assistant", dots);
    const request = {
      question, mode: state.answerMode, source_ids: [...state.selectedSources], provider: $("#provider-select").value || null,
      model: $("#model-select").value || null, speak: $("#speak-answer").checked,
      // Alan API'de baştan beri vardı ama istemci hiç göndermiyordu: her soru
      // yeni bir sohbet açıyordu. Artık seçili sohbete eklenir.
      conversation_id: state.conversationId || null,
    };
    const path = `/notebooks/${encodeURIComponent(state.notebookId)}/ask`;
    try {
      let draft = ""; let bubble = null; let result = null; let failure = null;
      for await (const event of sseEvents(`${path}/stream`, request)) {
        if (event.name === "draft_delta") {
          draft += event.data.text || "";
          // Taslak DOĞRULANMAMIŞTIR; kanıt kapısından geçen final metin
          // birazdan yerini alacak. Bu yüzden ayrı bir sınıfla işaretlenir.
          if (!bubble) { pending.replaceChildren(); bubble = document.createElement("div"); bubble.className = "message-bubble draft"; pending.append(bubble); }
          bubble.textContent = draft;
          $("#messages").scrollTop = $("#messages").scrollHeight;
        } else if (event.name === "validating") {
          if (bubble) bubble.dataset.state = "Kaynaklara karşı doğrulanıyor…";
        } else if (event.name === "final") {
          result = event.data.answer;
        } else if (event.name === "error") {
          failure = event.data.message || "Akış hatası";
        }
      }
      pending.remove();
      if (failure) throw new Error(failure);
      if (!result) throw new Error("Yanıt tamamlanmadı");
      if (state.notebookId !== istekNotebook) return; // bayat yanıt: sessizce düş
      appendMessage("assistant", result.answer_markdown || result.answer || "Yanıt üretilmedi.", result);
      if (result.conversation_id && result.conversation_id !== state.conversationId) {
        state.conversationId = result.conversation_id;
        loadConversations();
      }
      if (result.audio_job_id) registerJob({ id: result.audio_job_id, kind: "speech", status: "queued" });
    } catch (error) { pending.remove(); appendMessage("assistant", `İstek tamamlanamadı: ${error.message}`); toast(error.message, "error"); }
    finally { $("#send-button").disabled = false; $("#question-input").focus(); }
  }

  async function createStudio(kind) {
    if (!state.notebookId || state.selectedSources.size === 0) { toast("Studio için notebook ve en az bir kaynak seçin.", "error"); return; }
    const names = { podcast: "Podcast", audio_lesson: "Murat sesli ders", video_overview: "Video genel bakış", summary: "Kaynak özeti", study_guide: "Çalışma kılavuzu", quiz: "Quiz", flashcards: "Flashcard destesi", mind_map: "Zihin haritası", slides: "Ders slaytları", glossary: "Terim sözlüğü", ders_plani: "Ders planı", table: "Kaynak tablosu", faq: "Sık sorulan sorular", timeline: "Zaman çizgisi" };
    const payload = { notebook_id: state.notebookId, kind, title: names[kind] || kind, source_ids: [...state.selectedSources] };
    if (kind === "podcast") {
      const secim = $("#podcast-length")?.value || "orta";
      // Dakika değerleri hedef süreyi belirler; adlandırılmış presetler
      // eski davranışı korur.
      if (/^\d+$/.test(secim)) payload.target_minutes = Number(secim);
      else payload.length = secim;
      payload.style = $("#podcast-style")?.value || "sohbet";
      // Uzun bölümler bölüm bölüm yazılır; her bölüm kendi kanıtını çeker.
      payload.max_evidence = payload.target_minutes ? 24 : 20;
    }
    try {
      const result = await api("/studio", { method: "POST", body: JSON.stringify(payload) });
      if (result.job_id || (result.id && ["queued", "running"].includes(result.status))) registerJob({ id: result.job_id || result.id, kind: `studio:${kind}`, status: result.status || "queued" });
      else { state.artifacts.unshift(result); renderArtifacts(); }
      toast(`${names[kind] || kind} oluşturma işi başlatıldı.`, "success");
    } catch (error) { toast(`Studio işi başlatılamadı: ${error.message}`, "error"); }
  }

  function registerJob(job, context = null) {
    if (context) state.jobContexts.set(job.id, context);
    state.jobs.set(job.id, job); renderJobs(); pollJob(job.id);
  }
  async function pollJob(id) {
    for (let attempt = 0; attempt < 600 && state.jobs.has(id); attempt++) {
      await new Promise(resolve => setTimeout(resolve, attempt ? 1500 : 300));
      try {
        const job = await api(`/jobs/${encodeURIComponent(id)}`); state.jobs.set(id, job); renderJobs();
        if (["completed", "failed", "cancelled"].includes(job.status)) {
          const context = state.jobContexts.get(id);
          if (job.status === "completed") {
            toast(`${job.kind || "İş"} tamamlandı.`, "success");
            if (job.kind === "research" && context?.phase === "search") showResearchResults(job.result || {}, context);
            if (job.kind === "research" && context?.phase === "import") { closeDialogs(); resetResearchForm(); }
            await Promise.all([loadSources(), loadArtifacts()]);
          }
          else toast(`${job.kind || "İş"}: ${job.error || job.status}`, "error");
          window.setTimeout(() => { state.jobs.delete(id); state.jobContexts.delete(id); renderJobs(); }, 5000); return;
        }
      } catch (_) { return; }
    }
  }
  function renderJobs() {
    const list = $("#job-list"); list.replaceChildren();
    if (!state.jobs.size) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "Etkin iş yok."; list.append(empty); return; }
    state.jobs.forEach(job => {
      const row = document.createElement("div"); row.className = "job-row"; const text = document.createElement("span"); text.textContent = job.kind || "iş";
      const progress = document.createElement("span"); progress.textContent = job.status === "running" ? `%${Math.round((job.progress || 0) * 100)}` : job.status; row.append(text, progress); list.append(row);
    });
  }

  async function beginRecording() {
    if (state.recorder?.state === "recording") { state.recorder.stop(); return; }
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) { toast("Bu tarayıcı mikrofon kaydını desteklemiyor.", "error"); return; }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true }); state.audioChunks = [];
      state.recorder = new MediaRecorder(stream); state.recorder.ondataavailable = event => event.data.size && state.audioChunks.push(event.data);
      state.recorder.onstop = async () => { stream.getTracks().forEach(track => track.stop()); $("#mic-button").classList.remove("recording"); await transcribeRecording(); };
      state.recorder.start(); $("#mic-button").classList.add("recording"); toast("Dinliyorum; bitirmek için mikrofona yeniden basın.");
    } catch (error) { toast(`Mikrofon açılamadı: ${error.message}`, "error"); }
  }
  async function transcribeRecording() {
    const blob = new Blob(state.audioChunks, { type: state.audioChunks[0]?.type || "audio/webm" }); const form = new FormData();
    form.append("file", blob, "soru.webm"); form.append("model", "mlx-whisper"); form.append("language", "tr"); form.append("response_format", "json");
    try { const result = await api("/v1/audio/transcriptions", { method: "POST", body: form }); $("#question-input").value = result.text || result.transcript || ""; $("#question-input").focus(); }
    catch (error) { toast(`Whisper transkripsiyonu başarısız: ${error.message}`, "error"); }
  }

  async function uploadSource(form) {
    if (!state.notebookId) throw new Error("Önce notebook seçin");
    const body = new FormData(form); const result = await api(`/notebooks/${encodeURIComponent(state.notebookId)}/sources`, { method: "POST", body });
    if (result.job_id || result.id) registerJob({ id: result.job_id || result.id, kind: "ingest", status: result.status || "queued" });
    closeDialogs(); form.reset(); toast("Kaynak güvenli indeksleme kuyruğuna alındı.", "success");
  }

  async function research(form) {
    if (!state.notebookId) throw new Error("Önce notebook seçin"); const data = new FormData(form);
    const phase = form.dataset.phase || "search";
    const importIds = phase === "import" ? [...form.querySelectorAll('input[name="record_id"]:checked')].map(input => input.value) : [];
    if (phase === "import" && importIds.length === 0) throw new Error("İçe aktarmak için en az bir kayıt seçin");
    if (phase === "search") await api(`/notebooks/${encodeURIComponent(state.notebookId)}`, { method: "PATCH", body: JSON.stringify({ remote_egress_approved: true }) });
    const context = { phase, query: form.elements.query.value, provider: form.elements.provider.value };
    const result = await api("/research", { method: "POST", body: JSON.stringify({ notebook_id: state.notebookId, query: context.query, provider: context.provider, limit: 20, import_record_ids: importIds }) });
    if (result.job_id || (result.id && result.status)) registerJob({ id: result.job_id || result.id, kind: "research", status: result.status || "queued" }, context);
    toast(phase === "search" ? "Resmî kaynak araştırması başlatıldı." : "Seçili snapshot'lar içe aktarılıyor.", "success");
  }

  function showResearchResults(result, context) {
    const form = $("#research-form"); const region = $("#research-results"); region.replaceChildren();
    const records = Array.isArray(result.records) ? result.records : [];
    if (!records.length) { const empty = document.createElement("p"); empty.className = "form-note"; empty.textContent = "Bu sorgu için kayıt bulunamadı."; region.append(empty); }
    records.forEach(record => {
      const row = document.createElement("label"); row.className = "research-result";
      const checkbox = document.createElement("input"); checkbox.type = "checkbox"; checkbox.name = "record_id"; checkbox.value = record.id;
      const body = document.createElement("span"); const title = document.createElement("strong"); title.textContent = record.title || record.id;
      const note = document.createElement("small"); note.textContent = [record.record_type, record.published_at, record.provenance?.rights_status].filter(Boolean).join(" · ");
      body.append(title, note); row.append(checkbox, body); region.append(row);
    });
    form.dataset.phase = "import"; form.elements.query.value = context.query; form.elements.provider.value = context.provider;
    form.elements.query.readOnly = true; form.elements.provider.disabled = true; form.elements.approve_egress.closest("label").hidden = true;
    form.querySelector('button[type="submit"]').textContent = "Seçilenleri snapshot olarak içe aktar"; region.hidden = false; openDialog("#research-dialog");
  }

  function resetResearchForm() {
    const form = $("#research-form"); form.reset(); form.dataset.phase = "search"; form.elements.query.readOnly = false; form.elements.provider.disabled = false;
    form.elements.approve_egress.closest("label").hidden = false; form.querySelector('button[type="submit"]').textContent = "Araştır"; $("#research-results").hidden = true; $("#research-results").replaceChildren();
  }

  function formatDate(value) { if (!value) return "şimdi"; try { return new Intl.DateTimeFormat("tr", { dateStyle: "short", timeStyle: "short" }).format(new Date(value)); } catch (_) { return value; } }

  $("#notebook-select").addEventListener("change", event => event.target.value && selectNotebook(event.target.value));
  $("#new-notebook-button").addEventListener("click", () => openDialog("#notebook-dialog"));
  $("#upload-button").addEventListener("click", () => openDialog("#source-dialog"));
  $("#research-button").addEventListener("click", () => { resetResearchForm(); openDialog("#research-dialog"); });
  $("#settings-button").addEventListener("click", () => { $(".studio-pane").classList.add("open"); $(".tab[data-tab='system']").click(); });
  $$('[data-close-dialog]').forEach(button => button.addEventListener("click", closeDialogs));
  $("#notebook-form").addEventListener("submit", async event => { event.preventDefault(); const data = new FormData(event.currentTarget); const payload = Object.fromEntries(data); payload.remote_egress_approved = data.has("remote_egress_approved"); try { await api("/notebooks", { method: "POST", body: JSON.stringify(payload) }); closeDialogs(); event.currentTarget.reset(); await loadNotebooks(true); toast("Notebook oluşturuldu.", "success"); } catch (error) { toast(error.message, "error"); } });
  $("#source-form").addEventListener("submit", async event => { event.preventDefault(); try { await uploadSource(event.currentTarget); } catch (error) { toast(error.message, "error"); } });
  $("#research-form").addEventListener("submit", async event => { event.preventDefault(); try { await research(event.currentTarget); } catch (error) { toast(error.message, "error"); } });
  $("#ask-form").addEventListener("submit", event => { event.preventDefault(); ask($("#question-input").value); });
  $("#question-input").addEventListener("keydown", event => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); $("#ask-form").requestSubmit(); } });
  $("#mic-button").addEventListener("click", beginRecording);
  $("#source-filter").addEventListener("input", renderSources);
  $("#source-select-all").addEventListener("change", event => { state.selectedSources = event.target.checked ? new Set(state.sources.map(source => source.id)) : new Set(); renderSources(); });
  $$(".mode-button").forEach(button => button.addEventListener("click", () => { $$(".mode-button").forEach(item => { item.classList.toggle("active", item === button); item.setAttribute("aria-pressed", String(item === button)); }); state.answerMode = button.dataset.mode; }));
  $$(".starter[data-question]").forEach(button => button.addEventListener("click", () => { $("#question-input").value = button.dataset.question; $("#question-input").focus(); }));
  $$("[data-studio]").forEach(button => button.addEventListener("click", () => createStudio(button.dataset.studio)));
  $$(".studio-card").forEach(button => button.addEventListener("click", () => createStudio(button.dataset.kind)));
  $$(".tab").forEach(button => button.addEventListener("click", () => { $$(".tab").forEach(item => { item.classList.toggle("active", item === button); item.setAttribute("aria-selected", String(item === button)); }); $$(".tab-panel").forEach(panel => panel.classList.toggle("active", panel.id === `${button.dataset.tab}-tab`)); }));
  $("#save-notes").addEventListener("click", saveNote);
  $("#new-note").addEventListener("click", () => selectNote(""));
  $("#note-select").addEventListener("change", event => selectNote(event.target.value));
  $("#delete-note").addEventListener("click", async () => {
    if (!state.noteId || !window.confirm("Bu not silinsin mi?")) return;
    try {
      await api(`/notes/${encodeURIComponent(state.noteId)}`, { method: "DELETE" });
      state.notes = state.notes.filter(note => note.id !== state.noteId);
      renderNoteSelect(); selectNote(state.notes[0]?.id || ""); toast("Not silindi.", "success");
    } catch (error) { toast(`Not silinemedi: ${error.message}`, "error"); }
  });
  $("#conversation-select").addEventListener("change", event => openConversation(event.target.value));
  $("#delete-conversation").addEventListener("click", async () => {
    if (!state.conversationId || !window.confirm("Bu sohbet ve mesajları silinsin mi?")) return;
    try {
      await api(`/conversations/${encodeURIComponent(state.conversationId)}`, { method: "DELETE" });
      state.conversationId = null; $("#messages").replaceChildren(); await loadConversations();
      toast("Sohbet silindi.", "success");
    } catch (error) { toast(`Sohbet silinemedi: ${error.message}`, "error"); }
  });
  // Üretim süresi tahmini: ölçülmüş katsayı (~1.35 × hedef süre; sunucudaki
  // podcast_uretim_katsayisi ile aynı varsayılan). Preset'lerde sabit metin kalır.
  $("#podcast-length")?.addEventListener("change", event => {
    const secim = event.target.value;
    const not = $("#podcast-note");
    if (!not) return;
    if (/^\d+$/.test(secim)) {
      const dakika = Number(secim);
      not.textContent = `${dakika} dakikalık bölüm yaklaşık ${Math.round(dakika * 1.35)} dakikada üretilir; iş arka planda sürer, uygulamayı kapatabilirsiniz.`;
    } else {
      not.textContent = "Kısa bölümler birkaç dakikada üretilir; iş arka planda sürer.";
    }
  });
  $("#paket-button")?.addEventListener("click", async () => {
    if (!state.selectedArtifacts.size) return;
    try {
      const response = await fetch(apiPath(`/notebooks/${encodeURIComponent(state.notebookId)}/paket`), {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ artifact_ids: [...state.selectedArtifacts] }),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const blob = await response.blob();
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = (response.headers.get("content-disposition") || "").match(/filename="?([^";]+)"?/)?.[1] || "ogrenci-paketi.zip";
      link.click();
      window.setTimeout(() => URL.revokeObjectURL(link.href), 5000);
      toast("Öğrenci paketi indirildi.", "success");
    } catch (error) { toast(`Paket oluşturulamadı: ${error.message}`, "error"); }
  });
  $("#drop-zone").addEventListener("dragover", event => { event.preventDefault(); event.currentTarget.style.borderColor = "var(--accent)"; });
  $("#drop-zone").addEventListener("dragleave", event => event.currentTarget.style.borderColor = "");
  $("#drop-zone").addEventListener("drop", event => { event.preventDefault(); event.currentTarget.style.borderColor = ""; if (event.dataTransfer.files.length) $("#source-file").files = event.dataTransfer.files; });

  $("#local-port").textContent = window.location.port || (window.location.protocol === "https:" ? "443" : "80");
  // Görüntüleyici dosyaları (slides.js, mindmap.js, flashcards.js) ana modülün
  // kanıt paneline ve API katmanına bu köprüden erişir.
  window.BioProf = { showCitation, toast, api, askFromViewer: question => { $("#question-input").value = question; $(".studio-pane").classList.remove("open"); ask(question); } };
  Promise.all([loadNotebooks(), loadSystem()]).catch(error => toast(`Başlangıç verileri alınamadı: ${error.message}`, "error"));
})();
