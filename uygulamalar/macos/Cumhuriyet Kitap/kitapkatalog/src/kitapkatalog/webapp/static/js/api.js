// Fetch sarmalayıcı: JSON gövde, Türkçe hata mesajı, tek noktadan yönetim.

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

async function request(path, options = {}) {
  const response = await fetch(path, options);
  if (response.ok) {
    // 204 No Content: content-type json dese bile gövde boştur; json() patlar.
    if (response.status === 204) return response;
    const type = response.headers.get("content-type") || "";
    return type.includes("json") ? response.json() : response;
  }
  let detail = `İstek başarısız (${response.status})`;
  try {
    const body = await response.json();
    if (body.detail) detail = typeof body.detail === "string" ? body.detail : JSON.stringify(body.detail);
  } catch { /* gövde JSON değil */ }
  throw new ApiError(detail, response.status);
}

export const api = {
  get: (path, options = {}) => request(path, options),
  post: (path, body, options = {}) => request(path, {
    ...options,
    method: "POST",
    headers: { ...options.headers, "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
  }),
  put: (path, body, options = {}) => request(path, {
    ...options,
    method: "PUT",
    headers: { ...options.headers, "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
  }),
  patch: (path, body, options = {}) => request(path, {
    ...options,
    method: "PATCH",
    headers: { ...options.headers, "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
  }),
  del: (path, options = {}) => request(path, { ...options, method: "DELETE" }),
  // FormData yüklemesi; Content-Type'ı tarayıcı belirler.
  upload: (path, formData, options = {}) => request(path, {
    ...options, method: "POST", body: formData,
  }),
};

// Bir iş yuvasını bitene dek yokla; her turda onTick çağrılır.
export async function pollJob(statusPath, { onTick, intervalMs = 1500, field } = {}) {
  for (;;) {
    const data = await api.get(statusPath);
    const job = field ? data[field] : data;
    if (onTick) onTick(job);
    if (!job || job.status !== "running") return job;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}
