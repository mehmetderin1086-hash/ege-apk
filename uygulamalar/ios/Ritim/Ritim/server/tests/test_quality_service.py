"""Highest-quality contract, copy preservation and real codec verification."""
import json
from pathlib import Path
import shutil
import subprocess
import time
import unittest

import test_service
from test_service import URL
from app import APIError, JobManager
from media_quality import conversion_options, download_options


VIDEO = dict(codec_type="video", codec_name="h264", profile="High", pix_fmt="yuv420p",
             width=3840, height=2160, level=51, avg_frame_rate="30/1")
AUDIO = dict(codec_type="audio", codec_name="aac", profile="LC", channels=2, sample_rate="48000")


class QualityServiceTests(unittest.TestCase):
    setUp = test_service.ServiceTests.setUp
    tearDown = test_service.ServiceTests.tearDown
    executable = test_service.ServiceTests.executable
    manager = test_service.ServiceTests.manager
    server = test_service.ServiceTests.server
    request = test_service.ServiceTests.request
    wait = test_service.ServiceTests.wait

    def test_explicit_quality_contract_dedupe_and_legacy_restore(self):
        manager = self.manager(autostart=False, ffprobe="unused")
        standard = manager.create(URL, "mp3")
        highest = manager.create(URL, "mp3", "highest")
        self.assertEqual(standard["quality"], "standard")
        self.assertNotEqual(standard["id"], highest["id"])
        self.assertEqual(manager.create(URL, "mp3", "highest")["id"], highest["id"])
        manager.jobs[standard["id"]].pop("quality")
        manager._save()
        restored = JobManager(manager.root, yt_dlp=self.downloader, ffmpeg=self.encoder, ffprobe="unused", autostart=False)
        self.managers.append(restored)
        self.assertEqual(restored.get(standard["id"])["quality"], "standard")
        self.assertEqual(restored.get(highest["id"])["quality"], "highest")
        for invalid in (None, [], "4k", 320):
            with self.subTest(invalid=invalid), self.assertRaises(APIError):
                manager.create(URL, "mp3", invalid)

    def test_capability_requires_probe_and_rejects_silent_downgrade(self):
        manager = self.manager(autostart=False)
        base = self.server(manager)
        self.assertNotIn("download_quality", json.loads(self.request(base, "/health", auth=False)[1])["capabilities"])
        status, _, _ = self.request(base, "/v1/jobs", "POST", dict(url=URL, format="mp3", quality="highest"))
        self.assertEqual(status, 503)
        manager.ffprobe = "unused"
        status = json.loads(self.request(base, "/v1/status")[1])
        self.assertIn("download_quality", status["capabilities"])
        self.assertEqual(status["quality_profiles"], ["standard", "highest"])
        self.assertEqual(status["api_version"], "1.4")

    def test_copy_decisions_hdr_and_frame_rate(self):
        def options(video, audio=AUDIO):
            return conversion_options("mp4", "highest", {"streams": [video, audio]})
        self.assertEqual(options(VIDEO)[options(VIDEO).index("-c:v") + 1], "copy")
        for changes in ({"codec_name": "vp9"}, {"pix_fmt": "yuv420p10le"}, {"level": 60}, {"width": 3840, "height": 3840}):
            args = options(dict(VIDEO, **changes))
            self.assertEqual(args[args.index("-c:v") + 1], "libx264")
            self.assertIn("18", args)
        args = options(dict(VIDEO, avg_frame_rate="120/1"))
        self.assertIn("fps=60", args[args.index("-vf") + 1])
        self.assertEqual(options(dict(VIDEO, width=2160, height=3840))[5], "copy")
        for changes in ({"color_transfer": "smpte2084"}, {"color_transfer": "arib-std-b67"}, {"color_primaries": "bt2020"}):
            with self.assertRaisesRegex(RuntimeError, "HDR"):
                options(dict(VIDEO, **changes))
        self.assertNotIn("-vf", options(VIDEO))
        aac = options(VIDEO, dict(AUDIO, codec_name="opus"))
        self.assertEqual(aac[aac.index("-c:a") + 1], "aac")
        self.assertIn("320k", aac)

    def tools(self):
        ffmpeg = shutil.which("ffmpeg") or str(Path.home() / ".local/bin/ffmpeg")
        ffprobe = shutil.which("ffprobe") or str(Path(__file__).resolve().parents[1] / ".runtime/tools/ffprobe")
        if not Path(ffmpeg).is_file() or not Path(ffprobe).is_file():
            self.skipTest("FFmpeg and FFprobe are required for real quality validation")
        return ffmpeg, ffprobe

    def fixture(self, ffmpeg, dimensions, codec="libx264"):
        fixture = self.base / "fixture.mp4"
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                        "-f", "lavfi", "-i", "color=c=blue:s=%s:r=1:d=1" % dimensions,
                        "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-c:v", codec,
                        "-threads", "2", "-pix_fmt", "yuv420p", "-c:a", "aac", "-ac", "2",
                        "-shortest", str(fixture)], check=True, timeout=30)
        return fixture

    def frame_hash(self, ffmpeg, path):
        value = subprocess.run([ffmpeg, "-v", "error", "-i", str(path), "-map", "0:v:0",
                                "-f", "framemd5", "-"], check=True, capture_output=True, text=True, timeout=30).stdout
        return [line.split(",")[-1].strip() for line in value.splitlines() if line and not line.startswith("#")]

    def test_real_4k_landscape_portrait_copy_and_mp3_320(self):
        ffmpeg, ffprobe = self.tools()
        for index, dimensions in enumerate(("3840x2160", "2160x3840")):
            with self.subTest(dimensions=dimensions):
                fixture = self.fixture(ffmpeg, dimensions)
                manager = JobManager(self.base / ("real-" + str(index)), yt_dlp=self.downloader,
                                     ffmpeg=ffmpeg, ffprobe=ffprobe, workers=1)
                self.managers.append(manager)
                result = self.wait(manager, manager.create(URL, "mp4", "highest"))
                self.assertEqual(result["status"], "completed", result)
                output = manager.file(result["id"])
                self.assertEqual((result["media_info"]["width"], result["media_info"]["height"]), tuple(map(int, dimensions.split("x"))))
                self.assertEqual(self.frame_hash(ffmpeg, fixture), self.frame_hash(ffmpeg, output))
                content = output.read_bytes()
                self.assertLess(content.index(b"moov"), content.index(b"mdat"))
                subprocess.run([ffmpeg, "-v", "error", "-i", str(output), "-f", "null", "-"], check=True, timeout=30)
                if index == 0:
                    mp3 = self.wait(manager, manager.create(URL, "mp3", "highest"))
                    self.assertEqual(mp3["status"], "completed", mp3)
                    self.assertEqual(mp3["media_info"]["audio_bitrate"], 320000)
                    subprocess.run([ffmpeg, "-v", "error", "-i", str(manager.file(mp3["id"])), "-f", "null", "-"], check=True, timeout=30)

    def test_real_noncompatible_video_transcodes_without_upscale(self):
        ffmpeg, ffprobe = self.tools()
        self.fixture(ffmpeg, "640x360", codec="mpeg4")
        manager = self.manager(ffprobe=ffprobe, workers=1)
        manager.ffmpeg = ffmpeg
        result = self.wait(manager, manager.create(URL, "mp4", "highest"))
        self.assertEqual(result["status"], "completed", result)
        self.assertEqual(result["media_info"]["video_codec"], "h264")
        self.assertEqual((result["media_info"]["width"], result["media_info"]["height"]), (640, 360))
        subprocess.run([ffmpeg, "-v", "error", "-i", str(manager.file(result["id"])), "-f", "null", "-"], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main(verbosity=2)
