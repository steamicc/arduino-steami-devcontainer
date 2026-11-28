#!/usr/bin/env bats
# Tests du smoke-test hors de l'image : seulement ce qui se vérifie avant
# les outils (la valeur de STEAMI_SMOKE_EXEMPLES). Le reste tourne dans
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
