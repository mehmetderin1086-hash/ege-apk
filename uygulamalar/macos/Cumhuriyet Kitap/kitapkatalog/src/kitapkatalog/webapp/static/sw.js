// Cumhuriyet Kitap service worker — yalnız uygulama kabuğu (app shell) önbelleği.
// Veri (/api/*) ve yazdırma (/print/*) ASLA önbelleklenmez: bayat katalog riski yok.
// Strateji: stale-while-revalidate — kabuk anında açılır, arka planda tazelenir.

const CACHE_NAME = "kk-shell-v2";
const SHELL_PATHS = [
  "/static/style.css",
  "/static/js/api.js",
  "/static/js/ui.js",
  "/static/js/main.js",
  "/static/js/charts.js",
  "/static/js/scanner.js",
  "/static/icons/icon-192.png",
  "/static/icons/icon-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(SHELL_PATHS))
      .catch(() => undefined) // Kurulum hatası PWA'yı engellemesin; çevrimiçi yol her zaman çalışır.
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== self.location.origin) return;
  // Veri ve dinamik içerik: her zaman ağ (önbellek yok).
  if (url.pathname.startsWith("/api/") || url.pathname.startsWith("/print/")) return;
  // Sayfa gezinmeleri: ağ öncelikli; sunucu kapalıysa kısa Türkçe açıklama.
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(
        () =>
          new Response(
            "<!doctype html><meta charset='utf-8'><title>Cumhuriyet Kitap</title>" +
              "<body style='font-family:system-ui;display:grid;place-items:center;min-height:100vh;margin:0'>" +
              "<div style='text-align:center;max-width:28rem;padding:1rem'><h1>Sunucu çalışmıyor</h1>" +
              "<p>Cumhuriyet Kitap uygulamasını bilgisayarınızdan başlatın, sonra bu sayfayı yenileyin.</p></div>",
            { headers: { "Content-Type": "text/html; charset=utf-8" }, status: 503 }
          )
      )
    );
    return;
  }
  // Statik kabuk: stale-while-revalidate.
  if (url.pathname.startsWith("/static/")) {
    event.respondWith(
      caches.open(CACHE_NAME).then(async (cache) => {
        const cached = await cache.match(event.request);
        const refresh = fetch(event.request)
          .then((response) => {
            if (response.ok) cache.put(event.request, response.clone());
            return response;
          })
          .catch(() => cached);
        return cached || refresh;
      })
    );
  }
});
