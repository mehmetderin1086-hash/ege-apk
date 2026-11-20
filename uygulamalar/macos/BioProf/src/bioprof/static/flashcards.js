/* Flashcard çalışma modu: deste listesi, kart çevirme, SM-2 düğmeleri
   (bilemedim/zor/bildim → 2/3/5) ve Anki/CSV dışa aktarma. */
(function () {
  "use strict";

  let dialog = null;
  let kuyruk = [];
  let aktifKart = null;
  let cevrik = false;
  let deckId = null;
  let sayaclar = { bakilan: 0 };

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  async function loadDecks(notebookId) {
    const container = document.querySelector("#deck-list");
    if (!container || !notebookId) return;
    container.replaceChildren();
    let decks = [];
    try { decks = await window.BioProf.api(`/notebooks/${encodeURIComponent(notebookId)}/flashcard-decks`); }
    catch (error) { container.append(el("p", "muted", `Desteler yüklenemedi: ${error.message}`)); return; }
    if (!Array.isArray(decks) || !decks.length) {
      container.append(el("p", "muted", "Henüz deste yok. Studio'da bir flashcard çıktısı üretip 'Desteye çevir' deyin."));
      return;
    }
    decks.forEach(deck => {
      const row = el("div", "deste-satiri");
      const body = el("div", "");
      body.append(el("strong", "", deck.title));
      body.append(el("small", "muted", ` ${deck.card_count} kart`));
      const vade = el("span", "deste-vade", deck.due_count ? `${deck.due_count} kart vadede` : "hepsi tamam");
      const calis = el("button", "button primary", "Çalış");
      calis.type = "button";
      calis.disabled = !deck.due_count;
      calis.addEventListener("click", () => study(deck.id));
      const disari = el("button", "text-button", "Anki");
      disari.type = "button";
      disari.title = "Anki paketi indir (.apkg; olmadıysa CSV deneyin)";
      disari.addEventListener("click", () => window.open(`/api/v1/flashcard-decks/${encodeURIComponent(deck.id)}/export?format=apkg`, "_blank"));
      const csv = el("button", "text-button", "CSV");
      csv.type = "button";
      csv.addEventListener("click", () => window.open(`/api/v1/flashcard-decks/${encodeURIComponent(deck.id)}/export?format=csv`, "_blank"));
      const sil = el("button", "text-button danger", "Sil");
      sil.type = "button";
      sil.addEventListener("click", async () => {
        if (!window.confirm(`"${deck.title}" destesi silinsin mi?`)) return;
        try { await window.BioProf.api(`/flashcard-decks/${encodeURIComponent(deck.id)}`, { method: "DELETE" }); loadDecks(notebookId); }
        catch (error) { window.BioProf.toast(`Silinemedi: ${error.message}`, "error"); }
      });
      row.append(body, vade, calis, disari, csv, sil);
      container.append(row);
    });
  }

  function ensureDialog() {
    if (dialog) return dialog;
    dialog = el("dialog", "calisma-gorunum");
    const bar = el("div", "slide-viewer-bar");
    const baslik = el("strong", "", "Kart çalışması");
    const kapat = el("button", "icon-button", "×");
    kapat.type = "button";
    kapat.setAttribute("aria-label", "Kapat");
    kapat.addEventListener("click", () => dialog.close());
    bar.append(baslik, el("span", "slide-viewer-counter calisma-sayac", ""), kapat);
    const alan = el("div", "calisma-kart");
    const ic = el("div", "calisma-kart-ic");
    const on = el("div", "calisma-yuz on", "");
    const arka = el("div", "calisma-yuz arka", "");
    ic.append(on, arka);
    ic.addEventListener("click", () => { cevrik = !cevrik; ic.classList.toggle("cevrik", cevrik); guncelleDugmeler(); });
    alan.append(ic);
    const durum = el("p", "calisma-durum", "Karta tıklayınca cevap görünür.");
    const dugmeler = el("div", "calisma-dugmeler");
    [["bilemedim", "Bilemedim", 2, "bilemedim"], ["zor", "Zor hatırladım", 3, "zor"], ["bildim", "Bildim", 5, ""]].forEach(([anahtar, ad, not_, sinif]) => {
      const dugme = el("button", `button primary ${sinif}`.trim(), ad);
      dugme.type = "button";
      dugme.dataset.grade = String(not_);
      dugme.addEventListener("click", () => answer(not_));
      dugmeler.append(dugme);
    });
    dialog.append(bar, alan, durum, dugmeler);
    dialog.addEventListener("close", () => loadDecks(localStorage.getItem("bioprof.notebook")));
    document.body.append(dialog);
    return dialog;
  }

  function guncelleDugmeler() {
    dialog.querySelectorAll(".calisma-dugmeler .button").forEach(dugme => { dugme.disabled = !cevrik; });
    dialog.querySelector(".calisma-durum").textContent = cevrik
      ? "Ne kadar iyi hatırladınız?"
      : "Karta tıklayınca cevap görünür.";
  }

  function goster() {
    aktifKart = kuyruk[0] || null;
    cevrik = false;
    const ic = dialog.querySelector(".calisma-kart-ic");
    ic.classList.remove("cevrik");
    if (!aktifKart) {
      dialog.querySelector(".calisma-yuz.on").textContent = "Bu oturumda vadesi gelen kart kalmadı 🎉";
      dialog.querySelector(".calisma-yuz.arka").textContent = "";
      dialog.querySelector(".calisma-sayac").textContent = `${sayaclar.bakilan} kart çalışıldı`;
      dialog.querySelectorAll(".calisma-dugmeler .button").forEach(dugme => { dugme.disabled = true; });
      dialog.querySelector(".calisma-durum").textContent = "Kapatabilirsiniz.";
      return;
    }
    dialog.querySelector(".calisma-yuz.on").textContent = aktifKart.front;
    dialog.querySelector(".calisma-yuz.arka").textContent = aktifKart.back;
    dialog.querySelector(".calisma-sayac").textContent = `${kuyruk.length} kart kaldı`;
    guncelleDugmeler();
  }

  async function answer(grade) {
    if (!aktifKart) return;
    try {
      await window.BioProf.api(`/flashcards/${encodeURIComponent(aktifKart.id)}/review`, {
        method: "POST", body: JSON.stringify({ grade }),
      });
      sayaclar.bakilan += 1;
      kuyruk.shift();
      // Bilemediyse aynı oturumda kuyruk sonuna geri gelir (due_at bugün kaldı).
      if (grade < 3) kuyruk.push({ ...aktifKart });
      goster();
    } catch (error) { window.BioProf.toast(`Kaydedilemedi: ${error.message}`, "error"); }
  }

  async function study(id) {
    deckId = id;
    sayaclar = { bakilan: 0 };
    try { kuyruk = await window.BioProf.api(`/flashcard-decks/${encodeURIComponent(id)}/due`); }
    catch (error) { window.BioProf.toast(`Kartlar alınamadı: ${error.message}`, "error"); return; }
    ensureDialog();
    goster();
    if (!dialog.open) dialog.showModal();
  }

  window.BioProfFlashcards = { loadDecks, study };
})();
