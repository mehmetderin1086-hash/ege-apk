"""Real concurrent child-process tests for bounded preparation and disk accounting."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import time
import unittest

import test_service as fixtures
from app import APIError

CONTROLLED_YTDLP = r'''
import json, os, pathlib, sys, time
args = sys.argv[1:]
root = pathlib.Path(__file__).parent
if "--dump-single-json" in args:
    print(json.dumps({"title":"Parallel fixture", "uploader":"Ritim", "duration":1, "availability":"public"}))
else:
    target = pathlib.Path(args[args.index("--output") + 1].replace("%(ext)s", "mp4"))
    target.write_bytes(b"x" * 1000)
    marker = root / ("started-" + target.parent.name)
    marker.write_text(str(os.getpid()))
    print("RT_PROGRESS:50.0%", flush=True)
    deadline = time.monotonic() + 15
    while not (root / "release-all").exists() and not (root / ("release-" + target.parent.name)).exists():
        if time.monotonic() > deadline:
            sys.exit(1)
        time.sleep(.02)
    print("RT_PROGRESS:100.0%", flush=True)
'''


class ParallelServiceTests(unittest.TestCase):
    setUp = fixtures.ServiceTests.setUp
    tearDown = fixtures.ServiceTests.tearDown
    executable = fixtures.ServiceTests.executable
    manager = fixtures.ServiceTests.manager
    server = fixtures.ServiceTests.server
    request = fixtures.ServiceTests.request
    wait = fixtures.ServiceTests.wait

    def controlled(self, count=4, **kwargs):
        self.downloader = self.executable("controlled-ytdlp", CONTROLLED_YTDLP)
        manager = self.manager(autostart=False, **kwargs)
        jobs = [manager.create("https://www.youtube.com/watch?v=" + f"{index:011d}", "mp3") for index in range(count)]
        manager.start()
        return manager, jobs

    def eventually(self, condition, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.02)
        self.fail("Timed out waiting for concurrent workers")

    def wait_started(self, jobs):
        self.eventually(lambda: all((self.base / ("started-" + job["id"])).exists() for job in jobs))

    def release(self, jobs):
        for job in jobs:
            (self.base / ("release-" + job["id"])).touch()

    def test_four_real_download_processes_bounded_and_cancellation_isolated(self):
        manager, jobs = self.controlled(count=5)
        self.wait_started(jobs[:4])
        self.assertEqual(manager.worker_limit, 4)
        self.assertEqual(len(manager.threads), 4)
        self.assertEqual(manager.get(jobs[4]["id"])["status"], "queued")
        with manager.lock:
            self.assertEqual(manager._active_ids, {job["id"] for job in jobs[:4]})
        pids = [int((self.base / ("started-" + job["id"])).read_text()) for job in jobs[:4]]
        self.assertEqual(len(set(pids)), 4)
        for pid in pids:
            os.kill(pid, 0)  # All four downloader processes are alive at the same time.
        manager.cancel(jobs[0]["id"])
        self.wait_started(jobs[4:])
        self.assertFalse((manager.media / jobs[0]["id"]).exists())
        for job in jobs[1:4]:
            self.assertEqual(manager.get(job["id"])["status"], "downloading")
            self.assertTrue((manager.media / job["id"] / "source.mp4").exists())
        self.release(jobs[1:])
        for job in jobs[1:]:
            self.assertEqual(self.wait(manager, job)["status"], "completed")
        self.assertEqual(manager.get(jobs[0]["id"])["status"], "cancelled")
        self.eventually(lambda: manager.work.unfinished_tasks == 0)
        self.assertEqual(manager._total_usage(), manager._usage())

    def test_completion_and_ack_do_not_double_count_or_remove_other_active_files(self):
        manager, jobs = self.controlled()
        self.wait_started(jobs)
        self.assertEqual(manager._total_usage(), 4000)
        self.assertEqual(manager._stored_bytes, 0)
        self.release(jobs[:1])
        self.assertEqual(self.wait(manager, jobs[0])["status"], "completed")
        completed_size = manager.file(jobs[0]["id"]).stat().st_size
        self.assertEqual(manager._stored_bytes, completed_size)
        self.assertEqual(manager._total_usage(), 3000 + completed_size)
        manager.acknowledge(jobs[0]["id"])
        self.assertEqual(manager._stored_bytes, 0)
        self.assertEqual(manager._total_usage(), 3000)
        for job in jobs[1:]:
            self.assertEqual((manager.media / job["id"] / "source.mp4").stat().st_size, 1000)
        self.release(jobs[1:])
        for job in jobs[1:]:
            self.assertEqual(self.wait(manager, job)["status"], "completed")
        self.eventually(lambda: manager.work.unfinished_tasks == 0)
        self.assertEqual(manager._stored_bytes, completed_size * 3)
        with ThreadPoolExecutor(max_workers=4) as pool:
            responses = list(pool.map(lambda job: manager.acknowledge(job["id"]), jobs))
        self.assertTrue(all(item == {"status": "acknowledged"} for item in responses))
        self.assertEqual(manager._stored_bytes, 0)
        self.assertEqual(manager._total_usage(), 0)
        self.assertEqual(manager._usage(), 0)
        manager.close()
        restarted = self.manager(autostart=False)
        self.assertEqual(restarted._total_usage(), 0)
        self.assertTrue(all(restarted.get(job["id"])["status"] == "completed" for job in jobs))

    def test_storage_limit_checks_aggregate_across_workers(self):
        manager, jobs = self.controlled(max_storage=3500, max_bytes=10000)
        self.wait_started(jobs)
        self.eventually(lambda: any(manager.get(job["id"])["status"] == "failed" for job in jobs))
        failures = [manager.get(job["id"]) for job in jobs if manager.get(job["id"])["status"] == "failed"]
        self.assertTrue(all("depolama" in item["error"] for item in failures))
        (self.base / "release-all").touch()
        for job in jobs:
            self.wait(manager, job)
        self.eventually(lambda: manager.work.unfinished_tasks == 0)
        self.assertLessEqual(manager._total_usage(), 3500)
        self.assertEqual(manager._total_usage(), manager._usage())
        self.assertEqual(len(manager._active_ids), 0)

    def test_graceful_restart_requeues_all_interrupted_workers_and_preserves_queue(self):
        manager, jobs = self.controlled(count=6)
        self.wait_started(jobs[:4])
        manager.close()
        self.assertTrue(all(not thread.is_alive() for thread in manager.threads))
        self.assertEqual(manager._stored_bytes, manager._usage())
        self.assertEqual(len(manager._active_ids), 0)
        self.assertTrue(all(manager.get(job["id"])["status"] in {"queued", "downloading"} for job in jobs))
        restarted = self.manager(autostart=False)
        self.assertEqual(restarted._total_usage(), 0)
        self.assertTrue(all(restarted.get(job["id"])["status"] == "queued" for job in jobs))
        (self.base / "release-all").touch()
        restarted.start()
        for job in jobs:
            self.assertEqual(self.wait(restarted, job)["status"], "completed")
        self.eventually(lambda: restarted.work.unfinished_tasks == 0)
        self.assertEqual(restarted._stored_bytes, restarted._usage())

    def test_worker_configuration_bounds_and_http_capability(self):
        for count in [0, 7, -1, 2.5, "4", True]:
            with self.subTest(count=count), self.assertRaises(ValueError):
                self.manager(workers=count, autostart=False)
        manager = self.manager(workers=6, autostart=False)
        base = self.server(manager)
        for endpoint in ["/health", "/v1/status"]:
            status, body, _ = self.request(base, endpoint)
            self.assertEqual(status, 200)
            data = json.loads(body)
            self.assertEqual(data["worker_limit"], 6)
            self.assertEqual(data["queue_limit"], 12)
            self.assertIn("parallel_jobs", data["capabilities"])

    def test_configured_single_worker_preserves_serial_option(self):
        manager, jobs = self.controlled(count=2, workers=1)
        self.wait_started(jobs[:1])
        self.assertEqual(manager.get(jobs[1]["id"])["status"], "queued")
        self.assertEqual(len(manager._active_ids), 1)
        self.release(jobs)
        for job in jobs:
            self.assertEqual(self.wait(manager, job)["status"], "completed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
