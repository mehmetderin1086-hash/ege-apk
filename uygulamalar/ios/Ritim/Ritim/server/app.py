#!/usr/bin/env python3
"""Ritim's authenticated, bounded-parallel YouTube media preparation service."""
from __future__ import annotations

import argparse
import collections
import hmac
import json
import mimetypes
import math
import os
from pathlib import Path
import queue
import re
import secrets
import selectors
import shutil
import signal
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
import uuid

from ai_service import AIError, AIService
from media_quality import QUALITIES, conversion_options, download_options, first_stream, frame_rate, media_info

ACTIVE = {"queued", "preparing", "downloading"}
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
JOB_PATH = re.compile(r"^/v1/jobs/([a-f0-9-]{36})(/file|/ack)?$")
PLAYLIST_PATH = re.compile(r"^/v1/playlists/([a-f0-9-]{36})$")
PLAYLIST_ACTIVE = {"queued", "resolving"}
PLAYLIST_LIMIT = 1000


class APIError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message
        super().__init__(message)


class Cancelled(Exception):
    pass


def youtube_url(value):
    if not isinstance(value, str) or len(value) > 2048:
        raise APIError(400, "Geçerli bir YouTube video bağlantısı girin.")
    try:
        parsed = urlsplit(value.strip())
        if parsed.scheme != "https" or parsed.username or parsed.password or parsed.port not in (None, 443):
            raise ValueError()
        host = (parsed.hostname or "").lower()
        video = None
        if host == "youtu.be":
            video = parsed.path.strip("/")
        elif host in {"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"}:
            if parsed.path == "/watch":
                values = parse_qs(parsed.query).get("v", [])
                video = values[0] if len(values) == 1 else None
            elif re.fullmatch(r"/(shorts|embed|live)/[A-Za-z0-9_-]{11}/?", parsed.path):
                video = parsed.path.split("/")[2]
        if not video or not VIDEO_ID.fullmatch(video):
            raise ValueError()
        return "https://www.youtube.com/watch?v=" + video
    except (ValueError, TypeError):
        raise APIError(400, "Yalnızca HTTPS YouTube video bağlantıları desteklenir; oynatma listesi eklenemez.")


def youtube_playlist_url(value):
    """Accept playlist links, including bounded snapshots of public Mix lists."""
    if not isinstance(value, str) or len(value) > 2048:
        raise APIError(400, "Geçerli bir YouTube oynatma listesi bağlantısı girin.")
    try:
        parsed = urlsplit(value.strip())
        if (parsed.scheme != "https" or parsed.username or parsed.password or
                parsed.port not in (None, 443) or parsed.hostname not in
                {"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"} or
                parsed.path not in {"/playlist", "/watch"}):
            raise ValueError()
        query = parse_qs(parsed.query)
        values = query.get("list", [])
        if len(values) != 1 or not re.fullmatch(r"(?:PL|OLAK5uy_|RD)[A-Za-z0-9_-]{8,90}", values[0]):
            raise ValueError()
        if parsed.path == "/watch" and (len(query.get("v", [])) != 1 or
                                        not VIDEO_ID.fullmatch(query["v"][0])):
            raise ValueError()
        # Mix lists use YouTube's public playback redirect. Without playnext=1
        # RDEM lists can report "unviewable" despite being publicly playable.
        return "https://www.youtube.com/playlist?list=" + values[0] + ("&playnext=1" if values[0].startswith("RD") else "")
    except (ValueError, TypeError):
        raise APIError(400, "Herkese açık bir YouTube oynatma listesi veya Mix bağlantısı kullanın. Kanal, Beğenilenler ve Daha sonra izle desteklenmez.")


def atomic_json(path, value):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def load_token(root):
    supplied = os.environ.get("RITIM_API_TOKEN", "").strip()
    if supplied:
        if len(supplied) < 24:
            raise RuntimeError("RITIM_API_TOKEN must have at least 24 characters.")
        return supplied
    token_path = root / "api-token"
    if token_path.exists():
        token = token_path.read_text().strip()
        if len(token) < 24:
            raise RuntimeError("Invalid api-token file. Replace it with a new secure token.")
        os.chmod(token_path, 0o600)
        return token
    token = secrets.token_urlsafe(32)
    descriptor = os.open(str(token_path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(token + "\n")
    return token


class JobManager:
    def __init__(self, root, yt_dlp="yt-dlp", ffmpeg="ffmpeg", max_queue=12,
                 max_bytes=512 * 1024 * 1024, max_duration=7200, max_runtime=1800,
                 max_storage=4 * 1024**3, retention_days=7, autostart=True,
                 playlist_runtime=180, playlist_capture_limit=16 * 1024**2, workers=4, ffprobe=None):
        if type(workers) is not int or not 1 <= workers <= 6:
            raise ValueError("workers must be an integer from 1 to 6")
        self.root = Path(root).resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)
        self.media = self.root / "media"
        self.media.mkdir(mode=0o700, exist_ok=True)
        self.state_file = self.root / "jobs.json"
        self.yt_dlp, self.ffmpeg = yt_dlp, ffmpeg
        self.ffprobe = ffprobe
        self.max_queue, self.max_bytes = max_queue, max_bytes
        self.max_duration, self.max_runtime = max_duration, max_runtime
        self.max_storage, self.retention = max_storage, retention_days * 86400
        self.lock = threading.RLock()
        self.work = queue.Queue()
        self.stopping = threading.Event()
        self.jobs = {}
        self.worker_limit = workers
        self.threads = []
        self._stored_bytes = 0
        self._active_ids = set()
        self._restore()
        # Account old/unacknowledged files once. Runtime checks scan only the
        # bounded set of active directories, never the terminal history tree.
        self._stored_bytes = self._usage()
        self.playlists = PlaylistManager(self.root, yt_dlp, max_runtime=playlist_runtime,
                                        capture_limit=playlist_capture_limit, autostart=False)
        if autostart:
            self.start()

    def _restore(self):
        if self.state_file.exists():
            try:
                records = json.loads(self.state_file.read_text())
                if not isinstance(records, list):
                    raise ValueError("Expected an array")
                for job in records:
                    if not isinstance(job, dict) or not JOB_PATH.fullmatch("/v1/jobs/" + str(job.get("id", ""))):
                        continue
                    uuid.UUID(job["id"])
                    if job.get("format") not in {"mp3", "mp4"}:
                        continue
                    if job.get("quality", "standard") not in QUALITIES:
                        continue
                    job.setdefault("quality", "standard")
                    if job.get("status") in ACTIVE:
                        job.update(status="queued", progress=0, error=None)
                        shutil.rmtree(self.media / job["id"], ignore_errors=True)
                    elif job.get("status") == "completed":
                        if job.get("acknowledged"):
                            # The durable ack precedes deletion, so a crash between
                            # those operations can safely finish cleanup here.
                            shutil.rmtree(self.media / job["id"], ignore_errors=True)
                        elif not self._file(job).is_file():
                            job.update(status="failed", error="Sunucudaki medya dosyası bulunamadı.", progress=0)
                    self.jobs[job["id"]] = job
            except (ValueError, TypeError, KeyError, OSError) as error:
                # Never silently overwrite a damaged history or delete the associated files.
                raise RuntimeError("Cannot read jobs.json; restore or move the damaged file before restarting.") from error
        self._prune()
        for job in self.jobs.values():
            if job["status"] == "queued":
                self.work.put(job["id"])
        self._save()

    def _save(self):
        atomic_json(self.state_file, list(self.jobs.values()))

    def _prune(self):
        now = time.time()
        terminal = sorted((j for j in self.jobs.values() if j["status"] not in ACTIVE and j["id"] not in self._active_ids),
                          key=lambda j: j.get("updated_at", 0))
        for index, job in enumerate(terminal):
            if now - job.get("updated_at", 0) > self.retention or index < len(terminal) - 2500:
                self._remove_media(job)
                del self.jobs[job["id"]]

    def start(self):
        self.playlists.start()
        with self.lock:
            if not self.threads:
                for index in range(self.worker_limit):
                    thread = threading.Thread(target=self._worker, name="media-worker-%d" % (index + 1), daemon=True)
                    self.threads.append(thread)
                    thread.start()

    def close(self):
        self.stopping.set()
        self.playlists.close()
        deadline = time.monotonic() + 8
        for thread in self.threads:
            thread.join(timeout=max(0, deadline - time.monotonic()))

    def _usage(self, root=None):
        total = 0
        for path in (root or self.media).rglob("*"):
            try:
                if path.is_file():
                    total += path.stat().st_size
            except FileNotFoundError:
                pass
        return total

    def _remove_media(self, job, strict=False):
        with self.lock:
            directory = self.media / job["id"]
            before = self._usage(directory)
            try:
                if directory.exists():
                    shutil.rmtree(directory, ignore_errors=not strict)
            finally:
                # Active output is counted from disk, not in the stored cache.
                if job["id"] not in self._active_ids:
                    self._stored_bytes = max(0, self._stored_bytes - before + self._usage(directory))

    def _release_active(self, job_id):
        """Move one job's remaining bytes into the terminal cache exactly once."""
        with self.lock:
            if job_id in self._active_ids:
                self._stored_bytes += self._usage(self.media / job_id)
                self._active_ids.remove(job_id)

    def _total_usage(self):
        with self.lock:
            return self._stored_bytes + sum(self._usage(self.media / job_id) for job_id in self._active_ids)

    def create(self, url, format, quality="standard"):
        url = youtube_url(url)
        if not isinstance(format, str) or format not in {"mp3", "mp4"}:
            raise APIError(400, "Biçim mp3 veya mp4 olmalıdır.")
        if not isinstance(quality, str) or quality not in QUALITIES:
            raise APIError(400, "Kalite standard veya highest olmalıdır.")
        if quality == "highest" and not self.ffprobe:
            raise APIError(503, "En yüksek kalite için indirme servisine FFprobe kurulmalı.")
        with self.lock:
            self._prune()
            for job in self.jobs.values():
                if (job["url"] == url and job["format"] == format and
                        job.get("quality", "standard") == quality and job["status"] in ACTIVE):
                    return self.public(job)
            if sum(j["status"] in ACTIVE for j in self.jobs.values()) >= self.max_queue:
                raise APIError(429, "İndirme kuyruğu dolu. Bir indirme tamamlandığında yeniden deneyin.")
            if self._total_usage() >= self.max_storage or shutil.disk_usage(self.root).free < self.max_bytes * 2:
                raise APIError(507, "Sunucuda yeterli boş alan yok.")
            job = dict(id=str(uuid.uuid4()), status="queued", progress=0, title="YouTube", artist="",
                       url=url, format=format, quality=quality, error=None, created_at=time.time(), updated_at=time.time())
            self.jobs[job["id"]] = job
            self._save()
            self.work.put(job["id"])
            return self.public(job)

    def public(self, job):
        result = {key: job.get(key) for key in ("id", "status", "progress", "title", "artist", "error", "quality")}
        if job.get("media_info"):
            result["media_info"] = job["media_info"]
        if job["status"] == "completed":
            result["download_path"] = "/v1/jobs/" + job["id"] + "/file"
            result["acknowledged"] = bool(job.get("acknowledged"))
        return result

    def get(self, job_id):
        with self.lock:
            if job_id not in self.jobs:
                raise APIError(404, "İndirme bulunamadı veya sunucu saklama süresi doldu.")
            return self.public(self.jobs[job_id])

    def cancel(self, job_id):
        with self.lock:
            job = self.jobs.get(job_id)
            if not job:
                raise APIError(404, "İndirme bulunamadı.")
            if job["status"] in ACTIVE:
                job.update(status="cancelled", error=None, updated_at=time.time())
                self._save()
            return self.public(job)

    def _file(self, job):
        return self.media / job["id"] / ("media." + job["format"])

    def file(self, job_id):
        with self.lock:
            self.get(job_id)
            job = self.jobs[job_id]
            path = self._file(job)
            if job.get("acknowledged"):
                raise APIError(410, "Dosya telefona aktarıldığı onaylandı ve sunucudan temizlendi.")
            if job["status"] != "completed" or not path.is_file():
                raise APIError(409, "Dosya henüz hazır değil.")
            return path

    def acknowledge(self, job_id):
        with self.lock:
            self.get(job_id)
            job = self.jobs[job_id]
            if job["status"] != "completed":
                raise APIError(409, "Yalnızca tamamlanmış bir dosyanın aktarımı onaylanabilir.")
            if not job.get("acknowledged"):
                previous = dict(job)
                job.update(acknowledged=True, updated_at=time.time())
                try:
                    self._save()
                except Exception:
                    # A failed state write must never authorize deletion on a
                    # later retry merely because the in-memory flag was set.
                    job.clear()
                    job.update(previous)
                    raise
            self._remove_media(job, strict=True)
            return {"status": "acknowledged"}

    def _update(self, job_id, **values):
        with self.lock:
            job = self.jobs[job_id]
            if job["status"] == "cancelled":
                raise Cancelled()
            job.update(values, updated_at=time.time())
            self._save()

    def _check(self, job_id, started):
        with self.lock:
            if self.stopping.is_set() or self.jobs[job_id]["status"] == "cancelled":
                raise Cancelled()
            current_bytes = self._usage(self.media / job_id)
            # Include every concurrently downloading/converting job. Also allow
            # direct checks of a queued job's directory during recovery/tests.
            total_bytes = self._total_usage() + (current_bytes if job_id not in self._active_ids else 0)
            if current_bytes > self.max_bytes * 2 or total_bytes > self.max_storage:
                raise RuntimeError("İndirme depolama sınırını aştı.")
        if time.monotonic() - started > self.max_runtime:
            raise RuntimeError("İşlem süresi sınırı aşıldı. Daha kısa bir video deneyin.")
        if shutil.disk_usage(self.root).free < 64 * 1024 * 1024:
            raise RuntimeError("Sunucunun boş disk alanı tükendi.")

    def _run(self, args, job_id, started, callback=None, capture_limit=8 * 1024 * 1024):
        # No shell, no credentials, no user-supplied yt-dlp options, and no inherited stdin.
        process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        captured = bytearray()
        pending = bytearray()
        try:
            while selector.get_map():
                self._check(job_id, started)
                for key, _ in selector.select(timeout=0.2):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        break
                    captured.extend(chunk)
                    if len(captured) > capture_limit:
                        del captured[:-capture_limit]
                    if callback:
                        pending.extend(chunk)
                        while b"\n" in pending:
                            line, _, rest = pending.partition(b"\n")
                            pending = bytearray(rest)
                            callback(line.decode("utf-8", "replace"))
                        if len(pending) > 65536:
                            pending.clear()
            code = process.wait(timeout=5)
            self._check(job_id, started)
            output = captured.decode("utf-8", "replace")
            if code:
                self._process_error(output)
            return output
        finally:
            selector.close()
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=2)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=3)
            process.stdout.close()

    @staticmethod
    def _process_error(output):
        lowered = output.lower()
        if any(value in lowered for value in ("sign in", "login required", "private video", "members-only", "cookies")):
            raise RuntimeError("YouTube bu video için giriş veya doğrulama istiyor. Yalnızca herkese açık, giriş gerektirmeyen videolar desteklenir.")
        if "not available" in lowered or "unavailable" in lowered:
            raise RuntimeError("Video kullanılamıyor, kaldırılmış veya bu bölgede erişilemiyor.")
        if any(value in lowered for value in ("http error 403", "http error 429", "forbidden", "too many requests")):
            raise RuntimeError("YouTube erişimi geçici olarak kısıtladı. Daha sonra yeniden deneyin.")
        if "larger than max-filesize" in lowered:
            raise RuntimeError("Video izin verilen dosya boyutunu aşıyor.")
        lines = [re.sub(r"https?://\S+", "[bağlantı]", line) for line in output.splitlines() if "error" in line.lower()]
        detail = (lines[-1] if lines else "Medya hazırlama işlemi başarısız oldu.")[:400]
        raise RuntimeError(detail)

    def _worker(self):
        while not self.stopping.is_set():
            try:
                job_id = self.work.get(timeout=0.2)
            except queue.Empty:
                continue
            try:
                with self.lock:
                    value = self.jobs.get(job_id)
                    if not value:
                        continue
                    job = dict(value)
                    if job["status"] != "queued" or self.stopping.is_set():
                        continue
                    self._active_ids.add(job_id)
                self._execute(job)
            except Cancelled:
                # A graceful service stop preserves active status, so startup requeues it.
                if not self.stopping.is_set():
                    self._remove_media(job)
            except Exception as error:
                try:
                    self._update(job_id, status="failed", error=str(error)[:500])
                except Cancelled:
                    pass
                self._remove_media(job)
            finally:
                self._release_active(job_id)
                self.work.task_done()

    def _execute(self, job):
        job_id, started = job["id"], time.monotonic()
        directory = self.media / job_id
        directory.mkdir(mode=0o700, exist_ok=True)
        common = [self.yt_dlp, "--ignore-config", "--no-plugin-dirs", "--no-cookies", "--no-cookies-from-browser",
                  "--no-playlist", "--no-colors", "--no-warnings", "--no-cache-dir", "--socket-timeout", "20",
                  "--retries", "2", "--extractor-retries", "2", "--ffmpeg-location", self.ffmpeg]
        node = shutil.which("node")
        if node:
            common += ["--js-runtimes", "node:" + node]
        self._update(job_id, status="preparing", progress=0.01)
        raw = self._run(common + ["--dump-single-json", "--skip-download", "--", job["url"]], job_id, started)
        try:
            metadata = json.loads(raw)
        except ValueError:
            raise RuntimeError("YouTube video bilgisi okunamadı.")
        duration = metadata.get("duration")
        if not isinstance(duration, (int, float)) or not 0 < duration <= self.max_duration:
            raise RuntimeError("Video süresi bilinmiyor veya en fazla %d dakika sınırını aşıyor." % (self.max_duration // 60))
        if metadata.get("is_live") or metadata.get("live_status") in {"is_live", "is_upcoming", "post_live"}:
            raise RuntimeError("Canlı yayınlar desteklenmiyor; tamamlanmış bir video seçin.")
        if metadata.get("availability") in {"private", "premium_only", "subscriber_only", "needs_auth"}:
            raise RuntimeError("Bu video herkese açık değil.")
        self._update(job_id, status="downloading", progress=0.05,
                     title=str(metadata.get("title") or "YouTube")[:500],
                     artist=str(metadata.get("artist") or metadata.get("uploader") or "YouTube")[:300])
        last_progress = [0.05]

        def download_progress(line):
            if line.startswith("RT_PROGRESS:"):
                match = re.search(r"([0-9.]+)%", line)
                if match:
                    value = min(0.74, 0.05 + float(match.group(1)) / 100 * 0.69)
                    if value >= last_progress[0] + 0.005:
                        self._update(job_id, progress=value)
                        last_progress[0] = value

        quality = job.get("quality", "standard")
        selection, sort_order = download_options(job["format"], quality)
        args = common + ["--format", selection, "--format-sort", sort_order, "--merge-output-format", "mkv",
                         "--max-filesize", str(self.max_bytes), "--concurrent-fragments", "1",
                         "--newline", "--progress", "--progress-delta", "0.5", "--progress-template", "download:RT_PROGRESS:%(progress._percent_str)s",
                         "--output", str(directory / "source.%(ext)s"), "--", job["url"]]
        self._run(args, job_id, started, download_progress)
        sources = [p for p in directory.glob("source.*") if p.suffix not in {".part", ".ytdl", ".temp"} and p.is_file()]
        if len(sources) != 1 or sources[0].stat().st_size == 0:
            raise RuntimeError("Video indirilemedi veya boyut sınırını aştı.")
        if sources[0].stat().st_size > self.max_bytes:
            raise RuntimeError("İndirilen video boyut sınırını aşıyor.")
        probe = self._probe(sources[0], job_id, started) if quality == "highest" else None
        self._update(job_id, progress=0.75)
        destination = self._file(job)
        convert = [self.ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-threads", "2",
                   "-filter_threads", "1", "-protocol_whitelist", "file,pipe",
                   "-i", str(sources[0]), "-map_metadata", "-1", "-threads", "2"]
        convert += conversion_options(job["format"], quality, probe)
        convert += ["-metadata", "title=" + str(metadata.get("title") or "YouTube")[:500],
                    "-metadata", "artist=" + str(metadata.get("artist") or metadata.get("uploader") or "YouTube")[:300],
                    "-progress", "pipe:1", str(destination)]

        def conversion_progress(line):
            if line.startswith("out_time_us="):
                try:
                    value = 0.75 + min(1, max(0, int(line.split("=", 1)[1]) / 1000000 / duration)) * 0.24
                except ValueError:
                    return
                if value >= last_progress[0] + 0.005:
                    self._update(job_id, progress=value)
                    last_progress[0] = value

        self._run(convert, job_id, started, conversion_progress)
        if not destination.is_file() or not 0 < destination.stat().st_size <= self.max_bytes:
            raise RuntimeError("Hazırlanan dosya boş veya boyut sınırını aşıyor.")
        if quality == "highest":
            output_probe = self._probe(destination, job_id, started)
            info = media_info(output_probe)
            if job["format"] == "mp3":
                if info.get("audio_codec") != "mp3" or info.get("audio_bitrate") != 320000:
                    raise RuntimeError("320 kbps MP3 çıktısı doğrulanamadı.")
            else:
                video = first_stream(output_probe, "video") or {}
                width, height = info.get("width", 0), info.get("height", 0)
                fps = frame_rate(video)
                if (info.get("video_codec") != "h264" or not width or not height or
                        max(width, height) > 3840 or min(width, height) > 2160 or
                        fps is None or fps > 60.01 or video.get("pix_fmt") not in {"yuv420p", "yuvj420p"} or
                        info.get("audio_codec") not in {None, "aac"}):
                    raise RuntimeError("iPhone uyumlu yüksek kaliteli MP4 çıktısı doğrulanamadı.")
            self._update(job_id, media_info=info)
        self._check(job_id, started)
        for path in directory.iterdir():
            if path != destination and path.is_file():
                path.unlink()
        with self.lock:
            self._update(job_id, status="completed", progress=1, error=None)
            self._release_active(job_id)

    def _probe(self, path, job_id, started):
        if not self.ffprobe:
            raise RuntimeError("En yüksek kalite için FFprobe kurulmalı.")
        raw = self._run([self.ffprobe, "-v", "error", "-protocol_whitelist", "file,pipe",
                         "-show_streams", "-of", "json", str(path)], job_id, started, capture_limit=256 * 1024)
        try:
            value = json.loads(raw)
            if not isinstance(value, dict) or not isinstance(value.get("streams"), list):
                raise ValueError()
            return value
        except ValueError:
            raise RuntimeError("Medyanın gerçek ses/video bilgisi doğrulanamadı.")


class PlaylistManager:
    """One bounded metadata-only worker, independent of the media converter."""
    def __init__(self, root, yt_dlp, max_runtime=180, capture_limit=16 * 1024**2, autostart=True):
        self.root, self.yt_dlp = Path(root), yt_dlp
        self.state_file = self.root / "playlists.json"
        self.max_runtime, self.capture_limit = max_runtime, capture_limit
        self.lock = threading.RLock()
        self.stopping = threading.Event()
        self.work = queue.Queue()
        self.records = {}
        self.thread = None
        self._restore()
        if autostart:
            self.start()

    def _restore(self):
        if self.state_file.exists():
            try:
                records = json.loads(self.state_file.read_text())
                if not isinstance(records, list):
                    raise ValueError()
                for item in records:
                    if not isinstance(item, dict) or not PLAYLIST_PATH.fullmatch("/v1/playlists/" + str(item.get("id", ""))):
                        continue
                    uuid.UUID(item["id"])
                    if item.get("status") in PLAYLIST_ACTIVE:
                        item.update(status="queued", items=[], error=None)
                    self.records[item["id"]] = item
            except (ValueError, TypeError, KeyError, OSError) as error:
                raise RuntimeError("Cannot read playlists.json; restore or move the damaged file before restarting.") from error
        self._prune()
        for item in self.records.values():
            if item["status"] == "queued":
                self.work.put(item["id"])
        self._save()

    def _save(self):
        atomic_json(self.state_file, list(self.records.values()))

    def _prune(self):
        terminal = sorted((item for item in self.records.values() if item["status"] not in PLAYLIST_ACTIVE),
                          key=lambda item: item.get("updated_at", 0))
        for index, item in enumerate(terminal):
            if time.time() - item.get("updated_at", 0) > 86400 or index < len(terminal) - 40:
                del self.records[item["id"]]

    def start(self):
        if not self.thread:
            self.thread = threading.Thread(target=self._worker, name="playlist-worker", daemon=True)
            self.thread.start()

    def close(self):
        self.stopping.set()
        if self.thread:
            self.thread.join(timeout=8)

    @staticmethod
    def public(item):
        value = {key: item.get(key) for key in ("id", "status", "title", "items", "skipped", "truncated", "error")}
        if item["status"] in PLAYLIST_ACTIVE:
            value["items"] = []
        return value

    def create(self, url, limit=PLAYLIST_LIMIT):
        url = youtube_playlist_url(url)
        if type(limit) is not int or not 1 <= limit <= PLAYLIST_LIMIT:
            raise APIError(400, "Liste sınırı 1 ile 1000 arasında bir tam sayı olmalıdır.")
        with self.lock:
            self._prune()
            for item in self.records.values():
                if item["url"] == url and item["limit"] == limit and item["status"] in PLAYLIST_ACTIVE:
                    return self.public(item)
            if sum(item["status"] in PLAYLIST_ACTIVE for item in self.records.values()) >= 4:
                raise APIError(429, "Liste çözümleme kuyruğu dolu. Bir liste tamamlandığında yeniden deneyin.")
            item = dict(id=str(uuid.uuid4()), url=url, limit=limit, status="queued", title="YouTube oynatma listesi",
                        items=[], skipped=0, truncated=False, error=None, updated_at=time.time())
            self.records[item["id"]] = item
            self._save()
            self.work.put(item["id"])
            return self.public(item)

    def get(self, identifier):
        with self.lock:
            if identifier not in self.records:
                raise APIError(404, "Liste önizlemesi bulunamadı veya saklama süresi doldu.")
            return self.public(self.records[identifier])

    def cancel(self, identifier):
        with self.lock:
            self.get(identifier)
            item = self.records[identifier]
            if item["status"] in PLAYLIST_ACTIVE:
                item.update(status="cancelled", items=[], error=None, updated_at=time.time())
                self._save()
            return self.public(item)

    def _update(self, identifier, **values):
        with self.lock:
            item = self.records[identifier]
            if item["status"] == "cancelled":
                raise Cancelled()
            item.update(values, updated_at=time.time())
            self._save()

    def _check(self, identifier, started):
        with self.lock:
            if self.stopping.is_set() or self.records[identifier]["status"] == "cancelled":
                raise Cancelled()
        if time.monotonic() - started > self.max_runtime:
            raise RuntimeError("Liste çözümleme süresi aşıldı. Daha sonra tekrar deneyin.")

    def _extract(self, item):
        args = [self.yt_dlp, "--ignore-config", "--no-plugin-dirs", "--no-cookies", "--no-cookies-from-browser",
                "--flat-playlist", "--skip-download", "--dump-single-json", "--ignore-errors", "--no-colors",
                "--no-warnings", "--no-cache-dir", "--socket-timeout", "15", "--retries", "1",
                "--extractor-retries", "1", "--playlist-end", str(item["limit"] + 1), "--", item["url"]]
        process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
        selector = selectors.DefaultSelector()
        output, errors = bytearray(), bytearray()
        selector.register(process.stdout, selectors.EVENT_READ, output)
        selector.register(process.stderr, selectors.EVENT_READ, errors)
        started, total = time.monotonic(), 0
        try:
            while selector.get_map():
                self._check(item["id"], started)
                for key, _ in selector.select(timeout=0.2):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    total += len(chunk)
                    if total > self.capture_limit:
                        raise RuntimeError("Liste bilgisi boyut sınırını aştı. Daha küçük bir liste deneyin.")
                    key.data.extend(chunk)
                    if key.data is errors and len(errors) > 65536:
                        del errors[:-65536]
            code = process.wait(timeout=5)
            self._check(item["id"], started)
            if code:
                # No upstream URLs, local paths or request details reach the UI.
                self._playlist_error(errors.decode("utf-8", "replace"))
            try:
                data = json.loads(output)
            except (ValueError, UnicodeError):
                self._playlist_error(errors.decode("utf-8", "replace"))
            if not isinstance(data, dict) or not isinstance(data.get("entries"), list):
                self._playlist_error(errors.decode("utf-8", "replace"))
            return data
        finally:
            selector.close()
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=2)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=3)
            process.stdout.close()
            process.stderr.close()

    @staticmethod
    def _playlist_error(detail):
        lowered = detail.lower()
        if "unviewable" in lowered:
            raise RuntimeError("YouTube bu Mix listesini paylaşılabilir liste olarak açamadı. Videoları herkese açık yeni bir oynatma listesine kaydedip bağlantısını kullanın.")
        if any(text in lowered for text in ("private", "sign in", "login", "cookies", "not exist", "unavailable")):
            raise RuntimeError("Liste herkese açık değil, kaldırılmış veya YouTube giriş istiyor. Herkese açık bir liste seçin.")
        if "429" in lowered or "403" in lowered:
            raise RuntimeError("YouTube liste erişimini geçici olarak kısıtladı. Daha sonra yeniden deneyin.")
        raise RuntimeError("YouTube oynatma listesi okunamadı. Bağlantıyı kontrol edip yeniden deneyin.")

    @staticmethod
    def normalize(data, limit):
        entries, items, seen, skipped = data["entries"], [], set(), 0
        for position, entry in enumerate(entries[:limit], start=1):
            if not isinstance(entry, dict):
                skipped += 1
                continue
            video_id = entry.get("id")
            title = str(entry.get("title") or "YouTube").strip()[:500]
            blocked = title.casefold().strip("[] ") in {"private video", "deleted video", "unavailable video", "video unavailable"}
            if (not isinstance(video_id, str) or not VIDEO_ID.fullmatch(video_id) or video_id in seen or blocked or
                    entry.get("availability") in {"private", "premium_only", "subscriber_only", "needs_auth", "unavailable"} or
                    entry.get("is_live") or entry.get("live_status") in {"is_live", "is_upcoming", "post_live"}):
                skipped += 1
                continue
            seen.add(video_id)
            duration = entry.get("duration")
            if not isinstance(duration, (int, float)) or isinstance(duration, bool) or not math.isfinite(duration) or duration <= 0:
                duration = None
            source_index = entry.get("playlist_index")
            if type(source_index) is not int or source_index < 1:
                source_index = position
            items.append(dict(id=video_id, url="https://www.youtube.com/watch?v=" + video_id, title=title,
                              artist=str(entry.get("artist") or entry.get("uploader") or entry.get("channel") or "YouTube")[:300],
                              duration=duration, index=source_index))
        count = data.get("playlist_count")
        truncated = len(entries) > limit or (isinstance(count, int) and count > limit)
        return dict(title=str(data.get("title") or "YouTube oynatma listesi")[:500], items=items,
                    skipped=skipped, truncated=truncated)

    def _worker(self):
        while not self.stopping.is_set():
            try:
                identifier = self.work.get(timeout=0.2)
            except queue.Empty:
                continue
            try:
                with self.lock:
                    item = dict(self.records[identifier])
                if item["status"] != "queued":
                    continue
                self._update(identifier, status="resolving")
                result = self.normalize(self._extract(item), item["limit"])
                self._update(identifier, status="completed", error=None, **result)
            except Cancelled:
                pass
            except Exception as error:
                # Known failures use fixed messages; never expose command paths.
                message = str(error) if isinstance(error, RuntimeError) else "Liste çözümleme işlemi tamamlanamadı."
                try:
                    self._update(identifier, status="failed", items=[], error=message[:400])
                except Cancelled:
                    pass
            finally:
                self.work.task_done()


class RitimServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, manager, token):
        self.manager, self.token = manager, token
        self.ai = AIService(manager.root, manager.yt_dlp, PlaylistManager.normalize)
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    server_version = "Ritim/1.3"
    protocol_version = "HTTP/1.1"

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def log_message(self, format, *args):
        # Do not log tokens, request bodies, or user URLs.
        pass

    def _json(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if status == 401:
            self.send_header("WWW-Authenticate", "Bearer")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _dispatch(self):
        path = urlsplit(self.path).path
        capabilities = ["playlist_resolve", "job_ack", "parallel_jobs", "ai_chat", "ai_search"]
        quality_profiles = ["standard"]
        if self.server.manager.ffprobe:
            capabilities.append("download_quality")
            quality_profiles.append("highest")
        if self.command in {"GET", "HEAD"} and path == "/health":
            self._json(200, dict(status="ok", service="ritim", version=1,
                                 api_version="1.4", capabilities=capabilities, quality_profiles=quality_profiles,
                                 playlist_limit=PLAYLIST_LIMIT, queue_limit=self.server.manager.max_queue,
                                 worker_limit=self.server.manager.worker_limit,
                                 max_duration_seconds=self.server.manager.max_duration,
                                 max_file_bytes=self.server.manager.max_bytes, authentication="bearer"))
            return
        expected = "Bearer " + self.server.token
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), expected.encode()):
            self.close_connection = True
            raise APIError(401, "Sunucu anahtarı eksik veya geçersiz.")
        if path == "/v1/status" and self.command in {"GET", "HEAD"}:
            self._json(200, dict(status="ok", api_version="1.4", playlist_limit=PLAYLIST_LIMIT,
                                 queue_limit=self.server.manager.max_queue,
                                 worker_limit=self.server.manager.worker_limit,
                                 capabilities=capabilities, quality_profiles=quality_profiles,
                                 max_file_bytes=self.server.manager.max_bytes))
            return
        if path == "/v1/ai/models" and self.command in {"GET", "HEAD"}:
            self._json(200, self.server.ai.models())
            return
        if path in {"/v1/ai/chat", "/v1/ai/search"} and self.command == "POST":
            body = self._body(limit=512 * 1024 if path == "/v1/ai/chat" else 4096)
            result = self.server.ai.chat(body) if path == "/v1/ai/chat" else self.server.ai.search(body)
            self._json(200, result)
            return
        if path in {"/v1/jobs", "/v1/playlists/resolve"} and self.command == "POST":
            body = self._body()
            if path == "/v1/jobs":
                result = self.server.manager.create(body.get("url"), body.get("format"), body.get("quality", "standard"))
            else:
                result = self.server.manager.playlists.create(body.get("url"), body.get("limit", PLAYLIST_LIMIT))
            self._json(202, result)
            return
        playlist_match = PLAYLIST_PATH.fullmatch(path)
        if playlist_match:
            identifier = playlist_match.group(1)
            if self.command in {"GET", "HEAD"}:
                self._json(200, self.server.manager.playlists.get(identifier))
                return
            if self.command == "DELETE":
                self._json(200, self.server.manager.playlists.cancel(identifier))
                return
        match = JOB_PATH.fullmatch(path)
        if match:
            job_id, suffix = match.groups()
            if self.command == "POST" and suffix == "/ack":
                # This endpoint requires no body; closing avoids an unread body
                # being mistaken for another request on a persistent connection.
                self.close_connection = True
                self._json(200, self.server.manager.acknowledge(job_id))
                return
            if self.command in {"GET", "HEAD"} and suffix != "/ack":
                if suffix == "/file":
                    self._serve_file(self.server.manager.file(job_id))
                else:
                    self._json(200, self.server.manager.get(job_id))
                return
            if self.command == "DELETE" and not suffix:
                self._json(200, self.server.manager.cancel(job_id))
                return
        raise APIError(404, "Uç nokta bulunamadı.")

    def _body(self, limit=4096):
        if self.headers.get("Transfer-Encoding"):
            self.close_connection = True
            raise APIError(400, "Chunked request bodies are not supported.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if not 0 < length <= limit:
            self.close_connection = True
            raise APIError(413, "İstek gövdesi eksik veya çok büyük.")
        try:
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError()
            return body
        except (ValueError, UnicodeError):
            raise APIError(400, "Geçersiz JSON isteği.")

    def _serve_file(self, path):
        with path.open("rb") as handle:
            size = os.fstat(handle.fileno()).st_size
            start, end, status = 0, size - 1, 200
            range_value = self.headers.get("Range")
            if range_value:
                match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_value)
                if not match or not any(match.groups()):
                    raise APIError(416, "Geçersiz dosya aralığı.")
                left, right = match.groups()
                if left:
                    start = int(left)
                    end = min(int(right), end) if right else end
                else:
                    start = max(0, size - int(right))
                if start > end or start >= size:
                    raise APIError(416, "Dosya aralığı sınır dışında.")
                status = 206
            self.send_response(status)
            self.send_header("Content-Type", mimetypes.guess_type(str(path))[0] or "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="' + path.name + '"')
            self.send_header("Content-Length", str(end - start + 1))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Cache-Control", "private, no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            if status == 206:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
            self.end_headers()
            if self.command == "HEAD":
                return
            handle.seek(start)
            remaining = end - start + 1
            while remaining:
                data = handle.read(min(65536, remaining))
                if not data:
                    break
                self.wfile.write(data)
                remaining -= len(data)

    def _handle(self):
        try:
            self._dispatch()
        except (APIError, AIError) as error:
            self._json(error.status, {"error": error.message})
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            self.close_connection = True
        except Exception:
            self.close_connection = True
            self._json(500, {"error": "Sunucu işlemi tamamlayamadı."})

    do_GET = do_POST = do_DELETE = do_HEAD = _handle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=os.environ.get("RITIM_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("RITIM_PORT", "8765")))
    parser.add_argument("--data-dir", default=os.environ.get("RITIM_DATA_DIR", str(Path(__file__).parent / ".runtime")))
    parser.add_argument("--workers", type=int, choices=range(1, 7), default=os.environ.get("RITIM_WORKERS", "4"),
                        help="Concurrent media preparation workers (1–6, default: 4)")
    args = parser.parse_args()
    if not 1 <= args.workers <= 6:
        parser.error("RITIM_WORKERS must be from 1 to 6.")
    yt_dlp = shutil.which(os.environ.get("RITIM_YTDLP", "yt-dlp"))
    ffmpeg = shutil.which(os.environ.get("RITIM_FFMPEG", "ffmpeg"))
    if not yt_dlp or not ffmpeg:
        parser.error("Install yt-dlp and FFmpeg, or set RITIM_YTDLP and RITIM_FFMPEG.")
    root = Path(args.data_dir).resolve()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    token = load_token(root)
    ffprobe = shutil.which(os.environ.get("RITIM_FFPROBE", "ffprobe"))
    if not ffprobe:
        ffprobe = next((str(path) for path in (Path(ffmpeg).parent / "ffprobe", root / "tools" / "ffprobe")
                        if path.is_file() and os.access(path, os.X_OK)), None)
    manager = JobManager(root, yt_dlp=yt_dlp, ffmpeg=ffmpeg, ffprobe=ffprobe,
                         workers=args.workers,
                         max_bytes=int(os.environ.get("RITIM_MAX_BYTES", str(512 * 1024**2))),
                         max_duration=int(os.environ.get("RITIM_MAX_DURATION", "7200")),
                         max_runtime=int(os.environ.get("RITIM_MAX_RUNTIME", "1800")),
                         max_storage=int(os.environ.get("RITIM_MAX_STORAGE", str(4 * 1024**3))))
    server = RitimServer((args.host, args.port), manager, token)

    def stop(signum, frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print("Ritim server ready: http://%s:%s (token stays in private runtime storage)" % (args.host, args.port), flush=True)
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()
        manager.close()


if __name__ == "__main__":
    main()
