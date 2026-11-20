/* BioProf local hypermedia helper.
 * A deliberately small, clean-room subset for hx-get/post/delete,
 * hx-trigger, hx-target, hx-swap and hx-indicator. No external CDN request.
 */
(function () {
  "use strict";
  const htmx = window.htmx = window.htmx || {};
  function targetOf(el) {
    const selector = el.getAttribute("hx-target");
    if (!selector || selector === "this") return el;
    return document.querySelector(selector);
  }
  function swap(target, text, mode) {
    if (!target) return;
    if (mode === "outerHTML") target.outerHTML = text;
    else if (mode === "beforeend") target.insertAdjacentHTML("beforeend", text);
    else target.innerHTML = text;
  }
  async function issue(el, event) {
    const method = ["get", "post", "put", "patch", "delete"].find(m => el.hasAttribute("hx-" + m));
    if (!method) return;
    event && event.preventDefault();
    const indicator = document.querySelector(el.getAttribute("hx-indicator") || "");
    indicator && indicator.classList.add("htmx-request");
    const detail = { elt: el, target: targetOf(el) };
    el.dispatchEvent(new CustomEvent("htmx:beforeRequest", { bubbles: true, detail }));
    try {
      let url = el.getAttribute("hx-" + method);
      const options = { method: method.toUpperCase(), headers: { "HX-Request": "true" } };
      if (el instanceof HTMLFormElement) {
        const data = new FormData(el);
        if (method === "get") url += (url.includes("?") ? "&" : "?") + new URLSearchParams(data);
        else options.body = data;
      }
      const response = await fetch(url, options);
      if (!response.ok) throw new Error("HTTP " + response.status);
      swap(detail.target, await response.text(), el.getAttribute("hx-swap") || "innerHTML");
      el.dispatchEvent(new CustomEvent("htmx:afterSwap", { bubbles: true, detail }));
    } catch (error) {
      el.dispatchEvent(new CustomEvent("htmx:responseError", { bubbles: true, detail: { ...detail, error } }));
    } finally {
      indicator && indicator.classList.remove("htmx-request");
      el.dispatchEvent(new CustomEvent("htmx:afterRequest", { bubbles: true, detail }));
    }
  }
  htmx.process = function (root) {
    (root || document).querySelectorAll("[hx-get],[hx-post],[hx-put],[hx-patch],[hx-delete]").forEach(el => {
      if (el.dataset.hxBound) return;
      el.dataset.hxBound = "true";
      const trigger = el.getAttribute("hx-trigger") || (el instanceof HTMLFormElement ? "submit" : "click");
      el.addEventListener(trigger.split(/\s+/)[0], event => issue(el, event));
    });
  };
  document.addEventListener("DOMContentLoaded", () => htmx.process(document));
})();
