# -*- coding: utf-8 -*-
"""Biyoloji Stüdyosu entegrasyonu: /healthz imza ucu ve /merkez yönlendirmesi."""
import http.client
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

import soru_kes_web as web


class _SahteCozucu(BaseHTTPRequestHandler):
    imza = {"app": "biyo-cozucu", "status": "ready"}

    def do_GET(self):
        if self.path == "/healthz":
            govde = json.dumps(self.imza).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(govde)))
            self.end_headers()
            self.wfile.write(govde)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *a):
        pass


class _YabanciServis(_SahteCozucu):
    imza = {"app": "baska-uygulama", "status": "ready"}


def _sunucu_kur(test, handler):
    sunucu = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=sunucu.serve_forever, daemon=True).start()
    test.addCleanup(sunucu.server_close)
    test.addCleanup(sunucu.shutdown)
    return sunucu


class MerkezAdresiBulTesti(unittest.TestCase):
    def test_imzali_sunucu_bulunur(self):
        sunucu = _sunucu_kur(self, _SahteCozucu)
        port = sunucu.server_address[1]
        self.assertEqual(
            "http://127.0.0.1:%d" % port,
            web.merkez_adresi_bul(portlar=(port,)))

    def test_yabanci_imza_ve_kapali_port_reddedilir(self):
        yabanci = _sunucu_kur(self, _YabanciServis)
        # Kapalı port: geçici sunucu aç, portunu öğren, hemen kapat.
        bosta = ThreadingHTTPServer(("127.0.0.1", 0), _SahteCozucu)
        bos_port = bosta.server_address[1]
        bosta.server_close()
        self.assertIsNone(web.merkez_adresi_bul(
            portlar=(yabanci.server_address[1], bos_port), zaman_asimi=0.2))


class WebUclariTesti(unittest.TestCase):
    def setUp(self):
        self.sunucu = _sunucu_kur(self, web.Handler)
        self.port = self.sunucu.server_address[1]

    def _get(self, yol):
        baglanti = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        self.addCleanup(baglanti.close)
        baglanti.request("GET", yol)
        return baglanti.getresponse()

    def test_healthz_tokensiz_imza_doner(self):
        yanit = self._get("/healthz")
        self.assertEqual(200, yanit.status)
        veri = json.loads(yanit.read())
        self.assertEqual("soru-kesici", veri["app"])
        self.assertEqual("ready", veri["status"])
        self.assertTrue(veri["version"].startswith("v"))

    def test_api_v1_health_token_istemeye_devam_eder(self):
        yanit = self._get("/api/v1/health")
        self.assertEqual(401, yanit.status)

    def test_merkez_bulununca_302_yonlendirir(self):
        with mock.patch.object(
                web, "merkez_adresi_bul",
                return_value="http://127.0.0.1:9"):
            yanit = self._get("/merkez")
        self.assertEqual(302, yanit.status)
        self.assertEqual(
            "http://127.0.0.1:9/merkez", yanit.getheader("Location"))

    def test_merkez_bulunamazsa_503_mesaj_sayfasi(self):
        with mock.patch.object(
                web, "merkez_adresi_bul", return_value=None):
            yanit = self._get("/merkez")
        self.assertEqual(503, yanit.status)
        self.assertIn("Biyoloji Stüdyosu".encode("utf-8"), yanit.read())


if __name__ == "__main__":
    unittest.main()
