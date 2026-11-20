// API istemcisi — fetch sarmalayıcı + SSE yardımcıları
import { toast } from "/js/components/toast.js";

export async function api(path, options = {}) {
  const opts = { ...options };
  if (opts.json !== undefined) {
    opts.method = opts.method || "POST";
    opts.headers = { "Content-Type": "application/json", ...(opts.headers || {}) };
    opts.body = JSON.stringify(opts.json);
    delete opts.json;
  }
  let res;
  try {
    res = await fetch(path, opts);
  } catch {
    toast("Sunucuya ulaşılamıyor", "error");
    throw new Error("network");
  }
  if (!res.ok) {
    let detail = `Hata ${res.status}`;
    try {
      const data = await res.json();
      // FastAPI 422'de detail bir nesne dizisidir — stringe indir
      if (typeof data.detail === "string") detail = data.detail;
      else if (Array.isArray(data.detail))
        detail = data.detail.map((d) => d.msg || JSON.stringify(d)).join(", ");
    } catch { /* gövde JSON değil */ }
    toast(detail, "error");
    throw new Error(detail);
  }
  const type = res.headers.get("content-type") || "";
  return type.includes("application/json") ? res.json() : res;
}

export async function apiForm(path, formData, method = "POST") {
  return api(path, { method, body: formData });
}

/**
 * İş SSE akışını dinler. Her olayda onEvent(data) çağrılır;
 * iş bittiğinde son durumla çözülen bir Promise döndürür.
 */
export function watchJob(jobId, onEvent) {
  return new Promise((resolve, reject) => {
    const es = new EventSource(`/api/jobs/${jobId}/events`);
    es.onmessage = (e) => {
      const data = JSON.parse(e.data);
      if (data.error) {
        es.close();
        reject(new Error(data.error));
        return;
      }
      if (onEvent) onEvent(data);
      if (["done", "error", "cancelled"].includes(data.status)) {
        es.close();
        if (data.status === "done") resolve(data);
        else reject(new Error(data.message || "İş başarısız oldu"));
      }
    };
    let retries = 0;
    es.onerror = () => {
      // EventSource geçici kopmada kendini onarır (CONNECTING) ve sunucu her
      // bağlantıda güncel durumu yeniden yayınlar — hemen pes etme.
      if (es.readyState === EventSource.CONNECTING && retries < 5) {
        retries += 1;
        return;
      }
      es.close();
      reject(new Error("SSE bağlantısı koptu"));
    };
  });
}

export function fmtDuration(s) {
  if (s == null) return "—";
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return m > 0 ? `${m} dk ${sec} sn` : `${s.toFixed(1)} sn`;
}

export function fmtDate(ts) {
  return new Date(ts * 1000).toLocaleString("tr-TR", {
    day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit",
  });
}
