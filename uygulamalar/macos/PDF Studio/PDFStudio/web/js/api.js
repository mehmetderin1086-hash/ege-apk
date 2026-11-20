// Backend ile iletişim katmanı.
const SESSION_KEY = 'pdfstudio_session';

export function getSessionId() {
  return localStorage.getItem(SESSION_KEY) || null;
}
export function setSessionId(id) {
  if (id) localStorage.setItem(SESSION_KEY, id);
}
export function clearSessionId() {
  localStorage.removeItem(SESSION_KEY);
}

async function handle(res) {
  if (!res.ok) {
    let detail = 'Bir hata oluştu.';
    try { const j = await res.json(); detail = j.detail || detail; } catch {}
    const error = new Error(detail);
    error.status = res.status;
    throw error;
  }
  return res.json();
}

// Dosya yükleme (çoklu). onProgress: yüzde (0-100)
export function upload(files, onProgress) {
  return new Promise((resolve, reject) => {
    const fd = new FormData();
    for (const f of files) fd.append('files', f);
    const sid = getSessionId();
    if (sid) fd.append('session_id', sid);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/upload');
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress(Math.round((e.loaded / e.total) * 100));
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        const data = JSON.parse(xhr.responseText);
        setSessionId(data.session_id);
        resolve(data);
      } else {
        let detail = 'Yükleme başarısız.';
        try { detail = JSON.parse(xhr.responseText).detail || detail; } catch {}
        reject(new Error(detail));
      }
    };
    xhr.onerror = () => reject(new Error('Ağ hatası: sunucuya ulaşılamadı.'));
    xhr.send(fd);
  });
}

export async function post(path, body) {
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session: getSessionId(), ...body }),
  });
  return handle(res);
}

export async function get(path, params = {}) {
  const q = new URLSearchParams({ session: getSessionId(), ...params });
  const res = await fetch(`${path}?${q}`);
  return handle(res);
}

export async function del(path, params = {}) {
  const sid = getSessionId();
  if (!sid) throw new Error('Aktif oturum bulunamadı.');
  const q = new URLSearchParams({ session: sid, ...params });
  const res = await fetch(`${path}?${q}`, { method: 'DELETE' });
  return handle(res);
}

export async function sessionFiles() {
  if (!getSessionId()) return { files: [], total_size: 0 };
  return get('/api/session/files');
}

export async function deleteSessionFile(fileId) {
  return del(`/api/session/files/${encodeURIComponent(fileId)}`);
}

export async function clearSession() {
  const result = await del('/api/session');
  clearSessionId();
  return result;
}

export function renderUrl(fileId, page, dpi) {
  const q = new URLSearchParams({ session: getSessionId(), page });
  const base = dpi === 'thumb' ? '/api/thumb/' : '/api/render/';
  return `${base}${fileId}?${q}`;
}

export function downloadUrl(fileId) {
  return `/api/download/${getSessionId()}/${fileId}`;
}

export async function info(fileId) {
  return get(`/api/info/${fileId}`);
}
