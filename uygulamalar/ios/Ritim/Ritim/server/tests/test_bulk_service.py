"""Bulk playlist and durable acknowledgement tests; no external network."""
import json
from pathlib import Path
import sys
import time
import unittest
import uuid
from unittest.mock import patch

import test_service as fixtures

URL = fixtures.URL
from app import APIError, PlaylistManager, youtube_playlist_url

PLAYLIST = "https://www.youtube.com/playlist?list=PL1234567890abcdefghij"
PLAYLIST_SCRIPT = r'''
import json, pathlib, sys, time
root = pathlib.Path(__file__).parent
args = sys.argv[1:]
mode = (root / "mode").read_text().strip()
(root / "arguments.json").write_text(json.dumps(args))
if mode == "slow": time.sleep(10)
if mode == "huge":
    print("x" * 30000)
    sys.exit(0)
if mode == "private":
    print("ERROR: private playlist https://secret.invalid/path", file=sys.stderr)
    sys.exit(1)
print("unavailable entry skipped", file=sys.stderr)
data = json.loads((root / "playlist.json").read_text())
end = int(args[args.index("--playlist-end") + 1])
data["entries"] = data["entries"][:end]
print(json.dumps(data))
'''


class BulkServiceTests(unittest.TestCase):
    setUp = fixtures.ServiceTests.setUp
    tearDown = fixtures.ServiceTests.tearDown
    executable = fixtures.ServiceTests.executable
    manager = fixtures.ServiceTests.manager
    server = fixtures.ServiceTests.server
    request = fixtures.ServiceTests.request
    wait = fixtures.ServiceTests.wait

    def playlist_manager(self, count=600, **kwargs):
        self.downloader = self.executable("playlist-ytdlp", PLAYLIST_SCRIPT)
        self.fixture = {"title": "600 eser", "playlist_count": count,
                        "entries": [dict(id=f"{index:011d}", title=f"Eser {index}", uploader="Ritim", duration=5,
                                         playlist_index=index + 1) for index in range(count)]}
        self.write_fixture()
        return self.manager(**kwargs)

    def write_fixture(self):
        (self.base / "playlist.json").write_text(json.dumps(self.fixture))

    def wait_playlist(self, manager, item, status=None):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            value = manager.playlists.get(item["id"])
            if value["status"] == status if status else value["status"] not in {"queued", "resolving"}:
                return value
            time.sleep(0.02)
        self.fail("Playlist never reached state: " + str(value))

    def test_playlist_url_validation_and_canonicalization(self):
        for url in [PLAYLIST, "https://music.youtube.com/watch?v=BaW_jenozKc&list=PL1234567890abcdefghij&index=3",
                    "https://m.youtube.com/playlist?list=PL1234567890abcdefghij&si=ignored"]:
            self.assertEqual(youtube_playlist_url(url), PLAYLIST)
        album = "https://www.youtube.com/playlist?list=OLAK5uy_1234567890abcdef"
        self.assertEqual(youtube_playlist_url(album), album)
        mix = "https://youtube.com/playlist?list=RDEMTPfPURSbYpb0YHCKyIG37Q&playnext=1&si=ignored"
        self.assertEqual(youtube_playlist_url(mix), "https://www.youtube.com/playlist?list=RDEMTPfPURSbYpb0YHCKyIG37Q&playnext=1")
        for url in ["http://youtube.com/playlist?list=PL1234567890abcdef", "https://youtube.com@evil.test/playlist?list=PL1234567890abcdef",
                    "https://youtube.com:8765/playlist?list=PL1234567890abcdef", "https://youtube.com/channel/PL1234567890abcdef",
                    "https://youtube.com/playlist?list=WL",
                    "https://youtube.com/playlist?list=LL", "https://youtube.com/playlist?list=UU1234567890abcdef",
                    PLAYLIST + "&list=PL1234567890abcdef", "https://youtu.be/BaW_jenozKc?list=PL1234567890abcdef",
                    PLAYLIST.replace("playlist?", "watch?"), {}, None, "--exec bad"]:
            with self.subTest(url=url), self.assertRaises(APIError):
                youtube_playlist_url(url)

    def test_600_metadata_entries_dedupe_partial_unavailable_and_source_order(self):
        manager = self.playlist_manager()
        self.fixture["entries"][5] = dict(self.fixture["entries"][1])
        self.fixture["entries"][10]["title"] = "[Private video]"
        self.fixture["entries"][11]["title"] = "[Deleted video]"
        self.fixture["entries"][12]["availability"] = "needs_auth"
        self.fixture["entries"][13] = None
        self.fixture["entries"][14]["id"] = "https://localhost/"
        self.fixture["entries"][15]["live_status"] = "is_upcoming"
        self.fixture["entries"][16]["duration"] = float("nan")
        self.write_fixture()
        item = manager.playlists.create(PLAYLIST)
        result = self.wait_playlist(manager, item)
        self.assertEqual(result["status"], "completed", result)
        self.assertEqual(len(result["items"]), 593)
        self.assertEqual(result["skipped"], 7)
        self.assertFalse(result["truncated"])
        indexes = [entry["index"] for entry in result["items"]]
        self.assertEqual(indexes, sorted(indexes))
        self.assertEqual(result["items"][-1]["index"], 600)
        self.assertEqual(len(set(entry["id"] for entry in result["items"])), 593)
        self.assertTrue(all(entry["url"].startswith("https://www.youtube.com/watch?v=") for entry in result["items"]))
        self.assertIsNone(next(entry for entry in result["items"] if entry["index"] == 17)["duration"])
        arguments = json.loads((self.base / "arguments.json").read_text())
        for arg in ["--flat-playlist", "--skip-download", "--no-cookies", "--no-cookies-from-browser", "--ignore-config"]:
            self.assertIn(arg, arguments)
        self.assertEqual(arguments[arguments.index("--playlist-end") + 1], "1001")
        self.assertEqual(list(manager.media.iterdir()), [])

    def test_mix_resolution_uses_bounded_public_redirect(self):
        manager = self.playlist_manager(count=30)
        mix = "https://youtube.com/playlist?list=RDEMTPfPURSbYpb0YHCKyIG37Q&si=tracking"
        result = self.wait_playlist(manager, manager.playlists.create(mix, limit=25))
        self.assertEqual(result["status"], "completed")
        self.assertEqual(len(result["items"]), 25)
        self.assertTrue(result["truncated"])
        arguments = json.loads((self.base / "arguments.json").read_text())
        self.assertEqual(arguments[-1], "https://www.youtube.com/playlist?list=RDEMTPfPURSbYpb0YHCKyIG37Q&playnext=1")
        self.assertEqual(arguments[arguments.index("--playlist-end") + 1], "26")

    def test_1000_limit_and_truncation(self):
        manager = self.playlist_manager(count=1100)
        result = self.wait_playlist(manager, manager.playlists.create(PLAYLIST))
        self.assertEqual(len(result["items"]), 1000)
        self.assertTrue(result["truncated"])
        self.assertEqual(result["items"][-1]["index"], 1000)
        smaller = self.wait_playlist(manager, manager.playlists.create(PLAYLIST, limit=25))
        self.assertEqual(len(smaller["items"]), 25)
        self.assertTrue(smaller["truncated"])

    def test_auth_limits_poll_delete_and_capabilities(self):
        manager = self.playlist_manager(autostart=False)
        base = self.server(manager)
        for path, method in [("/v1/playlists/resolve", "POST"), ("/v1/playlists/" + str(uuid.uuid4()), "GET"),
                             ("/v1/playlists/" + str(uuid.uuid4()), "DELETE"), ("/v1/jobs/" + str(uuid.uuid4()) + "/ack", "POST")]:
            self.assertEqual(self.request(base, path, method, {"url": PLAYLIST}, auth=False)[0], 401)
        for limit in [0, 1001, -1, 2.5, "1000", None, True]:
            self.assertEqual(self.request(base, "/v1/playlists/resolve", "POST", {"url": PLAYLIST, "limit": limit})[0], 400)
        status, raw, _ = self.request(base, "/v1/playlists/resolve", "POST", {"url": PLAYLIST, "limit": 1000})
        self.assertEqual(status, 202)
        item = json.loads(raw)
        self.assertEqual(item["items"], [])
        self.assertEqual(set(item), {"id", "status", "title", "items", "skipped", "truncated", "error"})
        path = "/v1/playlists/" + item["id"]
        self.assertEqual(self.request(base, path)[0], 200)
        self.assertEqual(json.loads(self.request(base, path, "DELETE")[1])["status"], "cancelled")
        for endpoint in ["/health", "/v1/status"]:
            health = json.loads(self.request(base, endpoint)[1])
            self.assertEqual(health["playlist_limit"], 1000)
            self.assertEqual(health["queue_limit"], 12)
            self.assertIn("job_ack", health["capabilities"])

    def test_resolver_dedup_bound_and_single_worker_cancel(self):
        manager = self.playlist_manager()
        self.mode.write_text("slow")
        first = manager.playlists.create(PLAYLIST)
        self.wait_playlist(manager, first, "resolving")
        self.assertEqual(manager.playlists.create(PLAYLIST)["id"], first["id"])
        second = manager.playlists.create(PLAYLIST, limit=20)
        manager.playlists.create(PLAYLIST, limit=30)
        manager.playlists.create(PLAYLIST, limit=40)
        with self.assertRaises(APIError) as error:
            manager.playlists.create(PLAYLIST, limit=50)
        self.assertEqual(error.exception.status, 429)
        self.assertEqual(manager.playlists.get(second["id"])["status"], "queued")
        manager.playlists.cancel(first["id"])
        self.mode.write_text("normal")
        self.assertEqual(self.wait_playlist(manager, second)["status"], "completed")
        self.assertEqual(manager.playlists.get(first["id"])["status"], "cancelled")

    def test_timeout_output_cap_and_sanitized_errors(self):
        manager = self.playlist_manager(playlist_runtime=0.2, playlist_capture_limit=20000)
        for mode, expected in [("slow", "süresi"), ("huge", "boyut"), ("private", "herkese açık")]:
            with self.subTest(mode=mode):
                self.mode.write_text(mode)
                result = self.wait_playlist(manager, manager.playlists.create(PLAYLIST))
                self.assertEqual(result["status"], "failed", result)
                self.assertIn(expected, result["error"])
                self.assertNotIn("secret.invalid", result["error"])
                self.assertEqual(result["items"], [])

    def test_playlist_restart_persistence_and_cancel_survives(self):
        manager = self.playlist_manager(autostart=False)
        interrupted = manager.playlists.create(PLAYLIST)
        manager.playlists._update(interrupted["id"], status="resolving")
        cancelled = manager.playlists.create(PLAYLIST, limit=10)
        manager.playlists.cancel(cancelled["id"])
        manager.close()
        restarted = self.manager(autostart=False)
        self.assertEqual(restarted.playlists.get(interrupted["id"])["status"], "queued")
        self.assertEqual(restarted.playlists.get(cancelled["id"])["status"], "cancelled")
        restarted.start()
        complete = self.wait_playlist(restarted, interrupted)
        restarted.close()
        again = self.manager(autostart=False)
        self.assertEqual(again.playlists.get(interrupted["id"]), complete)

    def test_ack_only_completed_is_idempotent_and_restart_safe(self):
        manager = self.manager(autostart=False)
        base = self.server(manager)
        first = manager.create(URL, "mp3")
        self.assertEqual(self.request(base, "/v1/jobs/" + first["id"] + "/ack", "POST")[0], 409)
        manager.start()
        self.assertEqual(self.wait(manager, first)["status"], "completed")
        second = manager.create(URL, "mp4")
        self.assertEqual(self.wait(manager, second)["status"], "completed")
        second_path = manager.file(second["id"])
        for _ in range(2):
            status, body, _ = self.request(base, "/v1/jobs/" + first["id"] + "/ack", "POST")
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body), {"status": "acknowledged"})
        self.assertEqual(self.request(base, "/v1/jobs/" + first["id"] + "/file")[0], 410)
        self.assertTrue(second_path.exists())
        self.assertEqual(manager._stored_bytes, second_path.stat().st_size)
        manager.close()
        restarted = self.manager(autostart=False)
        self.assertEqual(restarted.get(first["id"])["status"], "completed")
        self.assertTrue(restarted.get(first["id"])["acknowledged"])
        self.assertEqual(restarted.get(second["id"])["status"], "completed")
        self.assertTrue(restarted.file(second["id"]).exists())
        self.assertEqual(restarted.acknowledge(first["id"]), {"status": "acknowledged"})

    def test_ack_crash_between_durable_marker_and_deletion(self):
        manager = self.manager()
        job = manager.create(URL, "mp3")
        self.assertEqual(self.wait(manager, job)["status"], "completed")
        path = manager.file(job["id"])
        with patch.object(manager, "_remove_media", side_effect=OSError("crash")):
            with self.assertRaises(OSError):
                manager.acknowledge(job["id"])
        self.assertTrue(path.exists())
        self.assertTrue(json.loads(manager.state_file.read_text())[0]["acknowledged"])
        manager.close()
        restarted = self.manager(autostart=False)
        self.assertFalse(path.exists())
        self.assertEqual(restarted.get(job["id"])["status"], "completed")
        self.assertEqual(restarted._stored_bytes, 0)

    def test_ack_state_write_failure_preserves_file_and_allows_safe_retry(self):
        manager = self.manager()
        job = manager.create(URL, "mp3")
        self.assertEqual(self.wait(manager, job)["status"], "completed")
        path = manager.file(job["id"])
        with patch.object(manager, "_save", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                manager.acknowledge(job["id"])
        self.assertTrue(path.exists())
        self.assertFalse(manager.get(job["id"])["acknowledged"])
        self.assertFalse(json.loads(manager.state_file.read_text())[0].get("acknowledged", False))
        self.assertEqual(manager.acknowledge(job["id"]), {"status": "acknowledged"})
        self.assertFalse(path.exists())

    def test_terminal_history_and_storage_checks_do_not_scan_entire_tree(self):
        manager = self.manager(autostart=False)
        for index in range(2510):
            identifier = str(uuid.uuid4())
            manager.jobs[identifier] = dict(id=identifier, url=URL, format="mp3", status="completed", acknowledged=True,
                                            updated_at=time.time(), progress=1, title="Ritim", artist="", error=None)
        manager._save()
        manager.close()
        manager = self.manager(autostart=False)
        self.assertEqual(len(manager.jobs), 2500)
        original = manager._usage
        with patch.object(manager, "_usage", wraps=original) as usage:
            job = manager.create(URL, "mp3")
            manager._check(job["id"], time.monotonic())
            self.assertTrue(all(call.args and call.args[0] is not None for call in usage.call_args_list))


if __name__ == "__main__":
    unittest.main(verbosity=2)
