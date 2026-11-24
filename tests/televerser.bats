#!/usr/bin/env bats
# Tests de la commande steami-televerser.
# Lancer : bats tests/televerser.bats

setup() {
  SRC="$BATS_TEST_DIRNAME/../.devcontainer/source"
  # Le faux steami-serveur passe avant le vrai.
  export PATH="$BATS_TEST_DIRNAME/stubs:$SRC:$PATH"
  TMP="$(mktemp -d)"
  export STEAMI_STUB_LOG="$TMP/serveur.log"
  DEPOT="$TMP/depot"
  mkdir -p "$DEPOT/src"
  echo '[env:steami]' > "$DEPOT/platformio.ini"
  unset CODESPACE_NAME GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN STEAMI_PORT
  cd "$DEPOT"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

compile() {
  mkdir -p "$DEPOT/.steami"
  echo x > "$DEPOT/.steami/firmware.bin"
  echo '{"programme":"src","date":"2026-01-01T00:00:00Z","taille":1}' > "$DEPOT/.steami/firmware.json"
}

@test "adresse_codespace" {
  compile
  export CODESPACE_NAME=abc GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev
  run steami-televerser
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://abc-8080.app.github.dev/"* ]]
  [[ "$output" == *"Chrome"* ]]
  [[ "$output" == *"Download"* ]]
  [ "$(cat "$STEAMI_STUB_LOG")" = start ]
}

@test "adresse_locale" {
  compile
  run steami-televerser
  [ "$status" -eq 0 ]
  [[ "$output" == *"http://localhost:8080/"* ]]
}

@test "sans_binaire" {
  run steami-televerser
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ Aucun programme compilé : lancez steami-compiler"* ]]
  [ ! -e "$STEAMI_STUB_LOG" ]
}

@test "depuis_src" {
  compile
  cd "$DEPOT/src"
  run steami-televerser
  [ "$status" -eq 0 ]
  [ "$(cat "$STEAMI_STUB_LOG")" = start ]
}
