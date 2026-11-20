// Basit modal
export function openModal(contentEl, { title = "", onClose = null } = {}) {
  const backdrop = document.createElement("div");
  backdrop.className = "modal-backdrop";
  const modal = document.createElement("div");
  modal.className = "modal";
  if (title) {
    const h = document.createElement("h2");
    h.textContent = title;
    modal.appendChild(h);
  }
  modal.appendChild(contentEl);
  backdrop.appendChild(modal);
  document.body.appendChild(backdrop);

  function esc(e) {
    if (e.key === "Escape") close();
  }

  function close() {
    // Her kapanış yolunda dinleyiciyi kaldır — sızıntı yok
    document.removeEventListener("keydown", esc);
    backdrop.remove();
    if (onClose) onClose();
  }

  backdrop.addEventListener("click", (e) => {
    if (e.target === backdrop) close();
  });
  document.addEventListener("keydown", esc);
  return { close, el: modal };
}
