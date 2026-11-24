#!/usr/bin/env bash
# Test de fumée de l'image : outils en place, compilation sans réseau.
# Lancé depuis la racine du dépôt, dans l'image (voir CONTRIBUTING.md).
set -u

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB=/opt/steami/arduino-steami-lib
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echec() { echo "✗ $*" >&2; exit 1; }
ok() { echo "✅ $*"; }

command -v pio >/dev/null 2>&1 || echec "pio est introuvable"
[ "$(pio --version)" = "PlatformIO Core, version 6.1.19" ] \
  || echec "pio --version devrait afficher 6.1.19, obtenu : $(pio --version)"
ok "PlatformIO 6.1.19"

[ "$(git -C "$LIB" describe --tags 2>/dev/null)" = v0.24.0 ] \
  || echec "arduino-steami-lib devrait être au tag v0.24.0"
ok "arduino-steami-lib v0.24.0"

[ -d "$LIB/lib/lis2mdl/examples/BasicReader" ] \
  || echec "exemple lis2mdl/BasicReader introuvable"
ok "exemple lis2mdl/BasicReader présent"

cp -r "$RACINE/.devcontainer/source/amorcage" "$TMP/projet"
cd "$TMP/projet" || exit 1

pio run -e steami >"$TMP/base.log" 2>&1 || { tail -30 "$TMP/base.log" >&2; echec "compilation du projet d'amorçage"; }
ok "projet d'amorçage compilé"

for ex in lis2mdl/BasicReader ble/BleBeacon; do
  dossier="$LIB/lib/${ex%%/*}/examples/${ex##*/}"
  PLATFORMIO_SRC_DIR="$dossier" pio run -e steami >"$TMP/ex.log" 2>&1 \
    || { tail -30 "$TMP/ex.log" >&2; echec "compilation de $ex"; }
  ok "$ex compilé"
done
