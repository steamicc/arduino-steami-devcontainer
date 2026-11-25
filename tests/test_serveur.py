"""Tests de steami_serveur.py (serveur de la page Téléverser)."""
import http.client
import os
import sys
import tempfile
import threading
import unittest

SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".devcontainer", "source"))
sys.path.insert(0, SRC)

import steami_serveur  # noqa: E402


class ServeurTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.flasher = os.path.join(self.tmp.name, "flasher")
        self.depot = os.path.join(self.tmp.name, "depot")
        os.makedirs(self.flasher)
        os.makedirs(os.path.join(self.depot, ".steami"))
        with open(os.path.join(self.flasher, "index.html"), "w") as f:
            f.write("<h1>Téléverser</h1>")
        self.httpd = steami_serveur.make_server(0, self.flasher, self.depot)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(5)
        self.tmp.cleanup()

    def get(self, chemin):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            c.request("GET", chemin)
            r = c.getresponse()
            return r.status, dict(r.getheaders()), r.read()
        finally:
            c.close()

    def ecrire(self, nom, octets):
        with open(os.path.join(self.depot, ".steami", nom), "wb") as f:
            f.write(octets)

    def test_firmware_absent_404(self):
        statut, _, _ = self.get("/firmware.bin")
        self.assertEqual(statut, 404)

    def test_firmware_servi(self):
        octets = bytes(range(256)) * 4
        self.ecrire("firmware.bin", octets)
        statut, entetes, corps = self.get("/firmware.bin")
        self.assertEqual(statut, 200)
        self.assertEqual(corps, octets)
        self.assertEqual(entetes.get("Cache-Control"), "no-store")

    def test_json_servi(self):
        self.ecrire("firmware.json", b'{"programme": "src"}')
        statut, entetes, corps = self.get("/firmware.json")
        self.assertEqual(statut, 200)
        self.assertEqual(corps, b'{"programme": "src"}')
        self.assertEqual(entetes.get("Cache-Control"), "no-store")

    def test_json_avec_requete(self):
        self.ecrire("firmware.json", b"{}")
        statut, _, _ = self.get("/firmware.json?t=1")
        self.assertEqual(statut, 200)

    def test_index_servi(self):
        statut, entetes, corps = self.get("/")
        self.assertEqual(statut, 200)
        self.assertIn("Téléverser".encode(), corps)
        self.assertEqual(entetes.get("Cache-Control"), "no-store")

    def test_daplink_firmware_json_servi_depuis_le_dossier_flasher(self):
        os.makedirs(os.path.join(self.flasher, "daplink"))
        with open(os.path.join(self.flasher, "daplink", "firmware.json"), "wb") as f:
            f.write(b'{"release": "flasher"}')
        self.ecrire("firmware.json", b'{"release": "depot"}')
        statut, _, corps = self.get("/daplink/firmware.json")
        self.assertEqual(statut, 200)
        self.assertEqual(corps, b'{"release": "flasher"}')

    def test_pas_de_sortie_du_dossier(self):
        self.ecrire("firmware.bin", b"x")
        self.ecrire("firmware.bin.tmp", b"secret")
        for chemin in ("/../../etc/passwd",
                       "/firmware.bin/../../etc/passwd",
                       "/firmware.bin.tmp"):
            with self.subTest(chemin=chemin):
                statut, _, _ = self.get(chemin)
                self.assertEqual(statut, 404)


if __name__ == "__main__":
    unittest.main()
