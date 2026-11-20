(function scanDownloadHubResources() {
  "use strict";

  const EXTENSIONS = {
    video: new Set(["3gp", "avi", "flv", "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "ogv", "ts", "webm"]),
    audio: new Set(["aac", "aiff", "alac", "flac", "m4a", "mp3", "oga", "ogg", "opus", "wav", "wma"]),
    image: new Set(["apng", "avif", "bmp", "gif", "heic", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]),
    document: new Set([
      "7z", "csv", "doc", "docx", "epub", "gz", "json", "key", "numbers", "odp", "ods", "odt", "pages", "pdf",
      "ppt", "pptx", "rar", "rtf", "tar", "tgz", "txt", "xls", "xlsx", "xml", "xz", "zip"
    ])
  };

  function isHttpUrl(value) {
    try {
      const parsed = new URL(value, document.baseURI);
      return parsed.protocol === "http:" || parsed.protocol === "https:";
    } catch (_error) {
      return false;
    }
  }

  function absoluteUrl(value) {
    if (!value) {
      return "";
    }
    try {
      return new URL(value, document.baseURI).href;
    } catch (_error) {
      return "";
    }
  }

  function canonicalizeYouTubeUrl(value) {
    if (!isHttpUrl(value)) {
      return value;
    }
    const parsed = new URL(value, document.baseURI);
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
    return value;
  }

  const declaredCanonical = document.querySelector('link[rel="canonical"]');
  const canonicalCandidate = declaredCanonical ? absoluteUrl(declaredCanonical.href) : location.href;
  const pageUrl = canonicalizeYouTubeUrl(
    isHttpUrl(canonicalCandidate) ? canonicalCandidate : location.href
  );
  const pageHost = (() => {
    try {
      return new URL(pageUrl).hostname.toLowerCase().replace(/^www\./, "");
    } catch (_error) {
      return "";
    }
  })();
  const isYouTubePage = pageHost === "youtu.be" || pageHost === "youtube.com" || pageHost.endsWith(".youtube.com");
  const resources = [];
  const seen = new Set();

  function cleanTitle(value, fallback) {
    const normalized = String(value || "").replace(/\s+/g, " ").trim();
    return (normalized || fallback || "Adsız kaynak").slice(0, 240);
  }

  function extensionFromUrl(value) {
    try {
      const pathname = new URL(value, document.baseURI).pathname.toLowerCase();
      const fileName = pathname.split("/").pop() || "";
      if (fileName.endsWith(".tar.gz")) {
        return "gz";
      }
      const dot = fileName.lastIndexOf(".");
      return dot >= 0 ? fileName.slice(dot + 1) : "";
    } catch (_error) {
      return "";
    }
  }

  function classifyUrl(value) {
    const extension = extensionFromUrl(value);
    for (const [kind, extensions] of Object.entries(EXTENSIONS)) {
      if (extensions.has(extension)) {
        return kind;
      }
    }
    return "other";
  }

  function normalizeResourceUrl(value, kind) {
    const raw = absoluteUrl(value) || String(value || "");
    if ((kind === "video" || kind === "audio") && isYouTubePage) {
      return { url: pageUrl, fallback: raw !== pageUrl };
    }
    if (raw.startsWith("blob:") || raw.startsWith("data:")) {
      return { url: pageUrl, fallback: true };
    }
    if (!isHttpUrl(raw)) {
      return { url: "", fallback: false };
    }
    return { url: canonicalizeYouTubeUrl(raw), fallback: false };
  }

  function addResource(kind, value, title, source, forcedFallback = false) {
    const normalized = normalizeResourceUrl(value, kind);
    if (!normalized.url) {
      return;
    }
    const dedupeKey = `${kind}\n${normalized.url}`;
    if (seen.has(dedupeKey)) {
      return;
    }
    seen.add(dedupeKey);
    resources.push({
      kind,
      url: normalized.url,
      title: cleanTitle(title, normalized.url),
      source,
      pageUrl,
      usedPageFallback: Boolean(forcedFallback || normalized.fallback)
    });
  }

  function elementLabel(element, fallback) {
    return cleanTitle(
      element.getAttribute("aria-label") ||
      element.getAttribute("title") ||
      element.getAttribute("alt") ||
      element.textContent,
      fallback
    );
  }

  for (const video of document.querySelectorAll("video")) {
    const label = elementLabel(video, document.title || "Sayfadaki video");
    const values = [video.currentSrc, video.src];
    for (const source of video.querySelectorAll("source[src]")) {
      values.push(source.src);
    }
    if (values.every((value) => !value)) {
      addResource("video", pageUrl, label, "video", true);
    } else {
      for (const value of values) {
        if (value) {
          addResource("video", value, label, "video");
        }
      }
    }
  }

  for (const audio of document.querySelectorAll("audio")) {
    const label = elementLabel(audio, document.title || "Sayfadaki ses");
    const values = [audio.currentSrc, audio.src];
    for (const source of audio.querySelectorAll("source[src]")) {
      values.push(source.src);
    }
    if (values.every((value) => !value)) {
      addResource("audio", pageUrl, label, "audio", true);
    } else {
      for (const value of values) {
        if (value) {
          addResource("audio", value, label, "audio");
        }
      }
    }
  }

  for (const image of document.querySelectorAll("img")) {
    const value = image.currentSrc || image.src;
    if (value) {
      addResource("image", value, elementLabel(image, "Sayfadaki resim"), "img");
    }
  }

  for (const pictureSource of document.querySelectorAll("picture source[srcset]")) {
    const candidates = pictureSource.srcset
      .split(",")
      .map((entry) => entry.trim().split(/\s+/)[0])
      .filter(Boolean);
    const value = candidates[candidates.length - 1];
    if (value) {
      addResource("image", value, "Duyarlı sayfa resmi", "picture");
    }
  }

  for (const anchor of document.querySelectorAll("a[href]")) {
    const raw = anchor.getAttribute("href");
    const url = absoluteUrl(raw);
    if (!url || !isHttpUrl(url)) {
      continue;
    }
    const kind = classifyUrl(url);
    addResource(kind, url, elementLabel(anchor, url), "link");
  }

  const order = { video: 0, audio: 1, image: 2, document: 3, other: 4 };
  resources.sort((left, right) => {
    const kindOrder = order[left.kind] - order[right.kind];
    return kindOrder || left.title.localeCompare(right.title, "tr");
  });

  const counts = { video: 0, audio: 0, image: 0, document: 0, other: 0 };
  for (const resource of resources) {
    counts[resource.kind] += 1;
  }

  return {
    page: {
      url: location.href,
      canonicalUrl: pageUrl,
      title: cleanTitle(document.title, pageUrl)
    },
    counts,
    resources
  };
})();
