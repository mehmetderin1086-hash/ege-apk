// USB barkod okuyucu bileşeni.
//
// Okuyucular klavye gibi davranır: kodu hızla yazıp Enter basar. Bu modül
// bir input'u "okuyucu girişi" hâline getirir: Enter'da kodu işler, odağı
// input'ta tutar, işlem sürerken gelen okumaları kuyruklar (input asla
// disabled yapılmaz; okuyucu hızına dayanıklılık için).

const REPEAT_WINDOW_MS = 2000;

export function normalizeCode(raw) {
  const code = String(raw || "").trim();
  const compact = code.replace(/[^0-9Xx]/g, "").toUpperCase();
  if (compact.length === 10 || compact.length === 13) {
    return { code, isbn: compact };
  }
  return { code, isbn: null };
}

export function attachScanner(input, onCode, { refocus = true } = {}) {
  let lastCode = null;
  let lastAt = 0;
  let busy = false;
  const queue = [];

  async function process(value) {
    const { code, isbn } = normalizeCode(value);
    if (!code) return;
    const now = Date.now();
    const repeat = code === lastCode && now - lastAt < REPEAT_WINDOW_MS;
    lastCode = code;
    lastAt = now;
    await onCode(code, { isbn, repeat });
  }

  async function drain() {
    if (busy) return;
    busy = true;
    try {
      while (queue.length > 0) {
        await process(queue.shift());
      }
    } finally {
      busy = false;
    }
  }

  input.addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    const value = input.value;
    input.value = "";
    queue.push(value);
    drain();
  });

  if (refocus) {
    input.addEventListener("blur", () => {
      setTimeout(() => {
        // Sayfa görünür, modal/diyalog açık değil ve kullanıcı başka bir
        // form alanına geçmediyse odağı okuyucu inputuna geri ver.
        const section = input.closest("section.page");
        if (section && section.hidden) return;
        const active = document.activeElement;
        const formFocus =
          active &&
          active !== document.body &&
          (active.matches("input, textarea, select, button, [contenteditable]") ||
            active.closest("dialog"));
        if (!formFocus && !document.querySelector("dialog[open], .lightbox")) {
          input.focus();
        }
      }, 150);
    });
  }

  return { focus: () => input.focus() };
}
