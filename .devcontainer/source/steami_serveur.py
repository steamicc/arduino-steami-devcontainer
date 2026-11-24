#!/usr/bin/env python3
"""Serveur de la page « Téléverser » du Codespace STeaMi (bibliothèque standard seulement).

Sert la page depuis STEAMI_FLASHER et, aux deux chemins exacts /firmware.bin et
/firmware.json, le programme compilé de <STEAMI_DEPOT>/.steami/.
"""
import os
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

FICHIERS_PROGRAMME = ("/firmware.bin", "/firmware.json")


class Gestionnaire(SimpleHTTPRequestHandler):
    def __init__(self, *args, depot, **kwargs):
        self.depot = depot
        super().__init__(*args, **kwargs)

    def translate_path(self, path):
        chemin = urlsplit(path).path
        if chemin in FICHIERS_PROGRAMME:
            return os.path.join(self.depot, ".steami", chemin[1:])
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def make_server(port, flasher, depot, adresse="0.0.0.0"):
    gestionnaire = partial(Gestionnaire, directory=flasher, depot=depot)
    return ThreadingHTTPServer((adresse, port), gestionnaire)


def main():
    port = int(os.environ.get("STEAMI_PORT", "8080"))
    flasher = os.environ.get("STEAMI_FLASHER", "/opt/steami/flasher")
    depot = os.environ.get("STEAMI_DEPOT", os.getcwd())
    httpd = make_server(port, flasher, depot)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
