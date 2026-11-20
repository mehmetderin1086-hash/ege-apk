/* Tarayıcı içi sunum modu: slides türü artifact'ları tam ekran gösterir.
   Ok tuşları/boşluk ile gezinme, N ile konuşmacı notu, F ile tam ekran.
   Atıf rozetleri app.js'in kanıt paneline bağlanır (window.BioProf.showCitation). */
(function () {
  "use strict";

  let dialog = null;
  let slides = [];
  let index = 0;
  let notesOpen = false;

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function ensureDialog() {
    if (dialog) return dialog;
    dialog = el("dialog", "slide-viewer");
    dialog.innerHTML = "";
    const bar = el("div", "slide-viewer-bar");
    const title = el("strong", "slide-viewer-title", "");
    const counter = el("span", "slide-viewer-counter", "");
    const actions = el("div", "slide-viewer-actions");
    const notesButton = el("button", "text-button", "Not (N)");
    notesButton.type = "button";
    notesButton.addEventListener("click", () => toggleNotes());
    const fullButton = el("button", "text-button", "Tam ekran (F)");
    fullButton.type = "button";
    fullButton.addEventListener("click", () => toggleFullscreen());
    const closeButton = el("button", "icon-button", "×");
    closeButton.type = "button";
    closeButton.setAttribute("aria-label", "Kapat");
    closeButton.addEventListener("click", () => dialog.close());
    actions.append(notesButton, fullButton, closeButton);
    bar.append(title, counter, actions);
    const stage = el("section", "slide-stage");
    const notes = el("aside", "slide-notes");
    notes.hidden = true;
    const hint = el("footer", "slide-viewer-hint", "← → gezin · N not · F tam ekran · Esc kapat");
    dialog.append(bar, stage, notes, hint);
    dialog.addEventListener("keydown", onKey);
    dialog.addEventListener("close", () => { if (document.fullscreenElement) document.exitFullscreen(); });
    document.body.append(dialog);
    return dialog;
  }

  function onKey(event) {
    if (event.key === "ArrowRight" || event.key === " " || event.key === "PageDown") { event.preventDefault(); go(index + 1); }
    else if (event.key === "ArrowLeft" || event.key === "PageUp") { event.preventDefault(); go(index - 1); }
    else if (event.key.toLowerCase() === "n") { event.preventDefault(); toggleNotes(); }
    else if (event.key.toLowerCase() === "f") { event.preventDefault(); toggleFullscreen(); }
  }

  function toggleNotes() {
    notesOpen = !notesOpen;
    render();
  }

  function toggleFullscreen() {
    if (document.fullscreenElement) document.exitFullscreen();
    else dialog.requestFullscreen?.();
  }

  function go(next) {
    if (next < 0 || next >= slides.length) return;
    index = next;
    render();
  }

  function render() {
    const slide = slides[index] || {};
    dialog.querySelector(".slide-viewer-title").textContent = slide.title || "";
    dialog.querySelector(".slide-viewer-counter").textContent = `${index + 1} / ${slides.length}`;
    const stage = dialog.querySelector(".slide-stage");
    stage.replaceChildren();
    stage.append(el("h1", "slide-heading", slide.title || ""));
    const bullets = Array.isArray(slide.bullets) ? slide.bullets : [];
    if (bullets.length) {
      const list = el("ul", "slide-bullets");
      bullets.forEach(bullet => {
        const item = el("li", "", "");
        item.append(document.createTextNode(`${bullet.text || ""} `));
        if (bullet.citation) {
          const badge = el("button", "citation-button", bullet.citation);
          badge.type = "button";
          badge.addEventListener("click", () =>
            window.BioProf?.showCitation?.(bullet.citation_id || bullet.citation));
          item.append(badge);
        }
        list.append(item);
      });
      stage.append(list);
    }
    if (slide.kaynak_dipnotu) stage.append(el("p", "slide-footnote", slide.kaynak_dipnotu));
    const notes = dialog.querySelector(".slide-notes");
    notes.hidden = !notesOpen;
    notes.textContent = notesOpen ? (slide.speaker_notes || "Bu slayt için not yok.") : "";
  }

  function open(artifact) {
    const meta = artifact?.metadata || artifact || {};
    const yapili = meta.structured_data || meta;
    slides = Array.isArray(yapili.slides) ? yapili.slides : [];
    if (!slides.length) {
      window.BioProf?.toast?.("Bu çıktıda gösterilecek slayt yapısı yok.", "error");
      return;
    }
    index = 0;
    notesOpen = false;
    ensureDialog();
    render();
    if (!dialog.open) dialog.showModal();
  }

  window.BioProfSlides = { open };
})();
