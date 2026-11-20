"""No network required: real HTTP, persistence, subprocess and conversion tests."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import APIError, JobManager, RitimServer, load_token, youtube_url

URL = "https://www.youtube.com/watch?v=BaW_jenozKc"
TOKEN = "unit-test-token-which-is-not-a-production-token"
FAKE_YTDLP = r'''
import json, os, pathlib, shutil, sys, time
args = sys.argv[1:]
mode = pathlib.Path(__file__).with_name("mode").read_text().strip()
if "--dump-single-json" in args:
    if mode == "metadata-timeout":
        time.sleep(10)
    if mode == "failure":
        print("ERROR: Sign in to confirm you're not a bot")
        sys.exit(1)
    data = {"title":"Deneme", "uploader":"Ritim", "duration":1, "availability":"public"}
    if mode == "live": data["is_live"] = True
    if mode == "private": data["availability"] = "private"
    if mode == "long": data["duration"] = 9999999
    print(json.dumps(data))
else:
    target = pathlib.Path(args[args.index("--output") + 1].replace("%(ext)s", "mp4"))
    target.write_bytes(b"source-data")
    print("RT_PROGRESS:50.0%", flush=True)
    if mode == "slow": time.sleep(10)
    if mode == "oversized": target.write_bytes(b"x" * 30000)
    fixture = pathlib.Path(__file__).with_name("fixture.mp4")
    if fixture.exists(): shutil.copyfile(fixture, target)
    print("RT_PROGRESS:100.0%", flush=True)
'''
FAKE_FFMPEG = r'''
import pathlib, sys
pathlib.Path(sys.argv[-1]).write_bytes(b"converted-media-0123456789")
print("out_time_us=1000000", flush=True)
'''


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.mode = self.base / "mode"
        self.mode.write_text("normal")
        self.downloader = self.executable("fake-ytdlp", FAKE_YTDLP)
        self.encoder = self.executable("fake-ffmpeg", FAKE_FFMPEG)
        self.managers = []
        self.servers = []

    def executable(self, name, source):
        path = self.base / name
        path.write_text("#!" + sys.executable + "\n" + source)
        path.chmod(0o700)
        return str(path)

    def manager(self, **kwargs):
        result = JobManager(self.base / "runtime", yt_dlp=self.downloader, ffmpeg=self.encoder, **kwargs)
        self.managers.append(result)
        return result

    def server(self, manager):
        server = RitimServer(("127.0.0.1", 0), manager, TOKEN)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.servers.append((server, thread))
        return "http://127.0.0.1:%d" % server.server_port

    def request(self, base, path, method="GET", body=None, auth=True, extra=None):
        headers = dict(extra or {})
        if auth:
            headers["Authorization"] = "Bearer " + TOKEN
        data = json.dumps(body).encode() if body is not None else None
        if data is not None:
            headers["Content-Type"] = "application/json"
        request = Request(base + path, data=data, method=method, headers=headers)
        try:
            response = urlopen(request, timeout=3)
        except HTTPError as error:
            response = error
        with response:
            return response.status, response.read(), response.headers

    def wait(self, manager, job, condition=None):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            value = manager.get(job["id"])
            if condition(value) if condition else value["status"] not in {"queued", "preparing", "downloading"}:
                return value
            time.sleep(0.025)
        self.fail("Job never reached expected state: " + str(manager.get(job["id"])))

    def tearDown(self):
        for server, thread in self.servers:
            server.shutdown()
            server.server_close()
            thread.join(2)
        for manager in self.managers:
            manager.close()
        self.temp.cleanup()

    def test_url_normalization(self):
        for value in [URL, "https://youtu.be/BaW_jenozKc?t=1", "https://music.youtube.com/watch?v=BaW_jenozKc&list=anything", "https://m.youtube.com/shorts/BaW_jenozKc", "https://youtube.com/embed/BaW_jenozKc/", "https://youtube.com/live/BaW_jenozKc"]:
            with self.subTest(value=value):
                self.assertEqual(youtube_url(value), URL)

    def test_url_rejects_ssrf_commands_and_unsupported_urls(self):
        values = ["http://127.0.0.1/", "https://youtube.com.evil.test/watch?v=BaW_jenozKc", "https://youtube.com@evil.test/watch?v=BaW_jenozKc", "https://u:p@youtube.com/watch?v=BaW_jenozKc", "https://youtube.com:8765/watch?v=BaW_jenozKc", "file:///etc/passwd", "--exec calc", "https://youtube.com/playlist?list=x", "https://youtu.be/BaW_jenozKc;rm", "https://youtube.com/watch?v=BaW_jenozKc&v=BaW_jenozKc", "https://youtu.be/%2Fetc%2Fpasswd", "https://localhost/watch?v=BaW_jenozKc", None, {}, []]
        for value in values:
            with self.subTest(value=value):
                with self.assertRaises(APIError):
                    youtube_url(value)

    def test_auth_health_status_and_file(self):
        base = self.server(self.manager(autostart=False))
        self.assertEqual(self.request(base, "/health", auth=False)[0], 200)
        for path in ["/v1/status", "/v1/jobs", "/v1/jobs/" + str(__import__('uuid').uuid4()) + "/file"]:
            self.assertEqual(self.request(base, path, auth=False)[0], 401)
        self.assertEqual(self.request(base, "/v1/status")[0], 200)
        self.assertEqual(self.request(base, "/v1/status", auth=False, extra={"Authorization":"Bearer wrong"})[0], 401)

    def test_http_validation(self):
        base = self.server(self.manager(autostart=False))
        for body in [{"url":URL, "format":"exe"}, {"url":URL, "format":[]}, {"url":"https://example.com/a", "format":"mp3"}, [], {}]:
            self.assertEqual(self.request(base, "/v1/jobs", "POST", body=body)[0], 400)
        self.assertEqual(self.request(base, "/v1/jobs", "POST", body={"url":"x" * 5000})[0], 413)

    def test_queue_deduplication_limits_and_cancellation(self):
        manager = self.manager(autostart=False, max_queue=1)
        job = manager.create(URL, "mp3")
        self.assertEqual(manager.create(URL, "mp3")["id"], job["id"])
        with self.assertRaises(APIError) as error:
            manager.create(URL, "mp4")
        self.assertEqual(error.exception.status, 429)
        self.assertEqual(manager.cancel(job["id"])["status"], "cancelled")
        self.assertEqual(manager.create(URL, "mp4")["status"], "queued")

    def test_http_end_to_end_download_and_ranges(self):
        manager = self.manager()
        base = self.server(manager)
        status, data, _ = self.request(base, "/v1/jobs", "POST", {"url":URL, "format":"mp3"})
        self.assertEqual(status, 202)
        job = json.loads(data)
        finished = self.wait(manager, job)
        self.assertEqual(finished["status"], "completed", finished)
        self.assertEqual(finished["title"], "Deneme")
        self.assertEqual(finished["progress"], 1)
        status, data, headers = self.request(base, finished["download_path"])
        self.assertEqual(status, 200)
        self.assertEqual(data, b"converted-media-0123456789")
        self.assertIn('filename="media.mp3"', headers["Content-Disposition"])
        self.assertEqual(headers["Content-Type"], "audio/mpeg")
        self.assertEqual(self.request(base, finished["download_path"], extra={"Range":"bytes=0-8"})[:2], (206, b"converted"))
        self.assertEqual(self.request(base, finished["download_path"], extra={"Range":"bytes=-3"})[:2], (206, b"789"))
        self.assertEqual(self.request(base, finished["download_path"], extra={"Range":"bytes=999-1000"})[0], 416)
        self.assertEqual(self.request(base, finished["download_path"], "HEAD")[:2], (200, b""))
        self.assertEqual(len(list((manager.media / job["id"]).iterdir())), 1)

    def test_running_cancel_kills_work_and_cleans_partial_files(self):
        self.mode.write_text("slow")
        manager = self.manager()
        base = self.server(manager)
        job = manager.create(URL, "mp4")
        self.wait(manager, job, lambda item: item["progress"] > 0.2)
        status, body, _ = self.request(base, "/v1/jobs/" + job["id"], "DELETE")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["status"], "cancelled")
        deadline = time.monotonic() + 3
        while manager.work.unfinished_tasks and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertEqual(manager.work.unfinished_tasks, 0)
        self.assertFalse((manager.media / job["id"]).exists())
        self.assertEqual(manager.get(job["id"])["status"], "cancelled")

    def test_restart_recovers_interrupted_jobs(self):
        manager = self.manager(autostart=False)
        job = manager.create(URL, "mp3")
        manager._update(job["id"], status="downloading", progress=0.5)
        partial = manager.media / job["id"]
        partial.mkdir()
        (partial / "source.part").write_bytes(b"partial")
        restarted = self.manager(autostart=False)
        self.assertEqual(restarted.get(job["id"])["status"], "queued")
        self.assertFalse(partial.exists())
        restarted.start()
        self.assertEqual(self.wait(restarted, job)["status"], "completed")

    def test_completed_survives_restart(self):
        manager = self.manager()
        job = manager.create(URL, "mp4")
        self.assertEqual(self.wait(manager, job)["status"], "completed")
        manager.close()
        restarted = self.manager(autostart=False)
        self.assertEqual(restarted.get(job["id"])["status"], "completed")
        self.assertTrue(restarted.file(job["id"]).is_file())

    def test_access_and_duration_restrictions(self):
        manager = self.manager()
        for mode in ["live", "private", "long", "failure"]:
            with self.subTest(mode=mode):
                self.mode.write_text(mode)
                job = manager.create(URL, "mp3")
                result = self.wait(manager, job)
                self.assertEqual(result["status"], "failed", result)
                self.assertTrue(result["error"])
                self.assertFalse((manager.media / job["id"]).exists())

    def test_runtime_limit(self):
        self.mode.write_text("metadata-timeout")
        manager = self.manager(max_runtime=0.4)
        result = self.wait(manager, manager.create(URL, "mp3"))
        self.assertEqual(result["status"], "failed")
        self.assertIn("süresi", result["error"])

    def test_file_size_limit(self):
        self.mode.write_text("oversized")
        manager = self.manager(max_bytes=10000)
        result = self.wait(manager, manager.create(URL, "mp4"))
        self.assertEqual(result["status"], "failed")
        self.assertFalse((manager.media / result["id"]).exists())

    def test_token_is_persistent_and_private(self):
        root = self.base / "secrets"
        root.mkdir()
        from unittest.mock import patch
        with patch.dict(os.environ, {}, clear=True):
            first = load_token(root)
            self.assertGreaterEqual(len(first), 32)
            self.assertEqual(first, load_token(root))
            self.assertEqual((root / "api-token").stat().st_mode & 0o777, 0o600)

    def test_corrupted_history_preserved(self):
        root = self.base / "runtime"
        root.mkdir()
        (root / "jobs.json").write_text("not json")
        with self.assertRaises(RuntimeError):
            self.manager()
        self.assertEqual((root / "jobs.json").read_text(), "not json")

    def test_real_ffmpeg_both_formats(self):
        ffmpeg = shutil.which("ffmpeg") or str(Path.home() / ".local/bin/ffmpeg")
        if not Path(ffmpeg).is_file():
            self.skipTest("FFmpeg not installed")
        fixture = self.base / "fixture.mp4"
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-f", "lavfi", "-i", "color=c=blue:s=320x240:r=15:d=1", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(fixture)], check=True, timeout=15)
        manager = self.manager()
        manager.ffmpeg = ffmpeg
        for format in ["mp3", "mp4"]:
            with self.subTest(format=format):
                result = self.wait(manager, manager.create(URL, format))
                self.assertEqual(result["status"], "completed", result)
                path = manager.file(result["id"])
                self.assertGreater(path.stat().st_size, 1000)
                # Fully decode the output: catches corrupt or non-playable conversion output.
                subprocess.run([ffmpeg, "-v", "error", "-i", str(path), "-f", "null", "-"], check=True, timeout=15)
                if format == "mp4":
                    content = path.read_bytes()
                    self.assertLess(content.index(b"moov"), content.index(b"mdat"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
