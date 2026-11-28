#!/usr/bin/env bats
# Tests du smoke-test hors de l'image : seulement ce qui se vérifie avant
# les outils (la valeur de STEAMI_SMOKE_EXEMPLES) et la boucle des exemples, avec
# de faux outils. Le reste tourne dans
# l'image, en CI (devcontainer.yml).
# Lancer : bats tests/smoke-test.bats

bats_require_minimum_version 1.5.0

setup() {
  SMOKE="$BATS_TEST_DIRNAME/../.devcontainer/smoke-test.sh"
}

@test "STEAMI_SMOKE_EXEMPLES invalide → échec immédiat, avant les outils" {
  STEAMI_SMOKE_EXEMPLES=quelques run --separate-stderr "$SMOKE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"STEAMI_SMOKE_EXEMPLES vaut tous ou aucun"* ]]
  [[ "$stderr" != *"pio"* ]]
  [ -z "$output" ]
}

@test "STEAMI_SMOKE_EXEMPLES absent, vide, tous ou aucun → accepté (suite du test)" {
  # Faux pio à la mauvaise version : le script s'arrête juste après la
  # vérification de la variable, sans dépendre des outils de la machine.
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho "PlatformIO Core, version 0.0.0"\n' > "$bin/pio"
  chmod +x "$bin/pio"
  for valeur in absent "" tous aucun; do
    if [ "$valeur" = absent ]; then
      PATH="$bin:$PATH" run --separate-stderr env -u STEAMI_SMOKE_EXEMPLES "$SMOKE"
    else
      PATH="$bin:$PATH" STEAMI_SMOKE_EXEMPLES="$valeur" run --separate-stderr "$SMOKE"
    fi
    [ "$status" -eq 1 ]
    [[ "$stderr" != *"STEAMI_SMOKE_EXEMPLES"* ]]
    [[ "$stderr" == *"pio --version devrait afficher 6.1.19"* ]]
  done
}

@test "boucle des exemples : durée de chaque exemple, puis les 10 plus lents, résumé inchangé" {
  # Extrait la boucle (entre les repères) et la lance avec de faux outils.
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\nfor i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52; do echo "LIB/Ex$i"; done\n' > "$bin/steami-exemples"
  # Faux pio : l'exemple Ex07 dure 2 s, les autres rien.
  printf '#!/bin/sh\ncase "$PLATFORMIO_SRC_DIR" in *Ex07) sleep 2;; esac\n' > "$bin/pio"
  chmod +x "$bin/steami-exemples" "$bin/pio"
  sed -n '/^# DEBUT boucle des exemples$/,/^# FIN boucle des exemples$/p' "$SMOKE" > "$BATS_TEST_TMPDIR/boucle.sh"
  [ -s "$BATS_TEST_TMPDIR/boucle.sh" ]
  cat > "$BATS_TEST_TMPDIR/appel.sh" <<APPEL
set -u
TMP="$BATS_TEST_TMPDIR"; LIB=/lib; EXEMPLES=tous
echec() { echo "✗ \$*" >&2; exit 1; }
ok() { echo "✅ \$*"; }
. "$BATS_TEST_TMPDIR/boucle.sh"
APPEL
  PATH="$bin:$PATH" run --separate-stderr bash "$BATS_TEST_TMPDIR/appel.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIB/Ex07 2s"* ]]
  [[ "$output" == *"LIB/Ex01 0s"* ]]
  [[ "$output" == *"Les 10 exemples les plus lents :"* ]]
  # Le plus lent est en tête de la liste, qui compte 10 lignes.
  [ "$(printf '%s\n' "$output" | sed -n '/plus lents/,$p' | sed -n 2p)" = "  2s LIB/Ex07" ]
  [ "$(printf '%s\n' "$output" | sed -n '/plus lents/,/compilés/p' | grep -c '^  [0-9]*s ')" -eq 10 ]
  [ "${lines[-1]}" = "✅ 52 exemples compilés" ]
}
