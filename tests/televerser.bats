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

# Secours : en session SSH, les variables Codespaces ne sont que dans un .env
# partagé (qui contient aussi GITHUB_TOKEN : il ne doit jamais s'afficher).
env_codespaces() {
  export STEAMI_CODESPACES_ENV="$TMP/codespaces.env"
  printf '%s\n' "$@" > "$STEAMI_CODESPACES_ENV"
}

@test "secours_env_valeurs_sans_guillemets" {
  compile
  env_codespaces 'GITHUB_TOKEN=ghu_secret123' 'CODESPACE_NAME=abc' 'GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev'
  run steami-televerser
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://abc-8080.app.github.dev/"* ]]
  [[ "$output" != *"ghu_secret123"* ]]
}

@test "secours_env_valeurs_entre_guillemets" {
  compile
  env_codespaces 'GITHUB_TOKEN="ghu_secret123"' "CODESPACE_NAME='abc'" 'GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN="app.github.dev"'
  run steami-televerser
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://abc-8080.app.github.dev/"* ]]
  [[ "$output" != *"ghu_secret123"* ]]
}

@test "secours_env_variables_prioritaires" {
  compile
  export CODESPACE_NAME=env GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=env.dev
  env_codespaces 'CODESPACE_NAME=dufichier' 'GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=dufichier.dev'
  run steami-televerser
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://env-8080.env.dev/"* ]]
  [[ "$output" != *"dufichier"* ]]
}

@test "secours_env_une_variable_manquante_completee" {
  compile
  export CODESPACE_NAME=env
  env_codespaces 'CODESPACE_NAME=dufichier' 'GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=dufichier.dev'
  run steami-televerser
  [[ "$output" == *"https://env-8080.dufichier.dev/"* ]]
}

@test "secours_env_fichier_absent" {
  compile
  export STEAMI_CODESPACES_ENV="$TMP/inexistant.env"
  run steami-televerser
  [ "$status" -eq 0 ]
  [[ "$output" == *"http://localhost:8080/"* ]]
}

@test "secours_env_cles_manquantes_sans_fuite" {
  compile
  env_codespaces 'GITHUB_TOKEN=ghu_secret123' 'AUTRE=x'
  run steami-televerser
  [ "$status" -eq 0 ]
  [[ "$output" == *"http://localhost:8080/"* ]]
  [[ "$output" != *"ghu_secret123"* ]]
}

@test "secours_env_non_execute" {
  compile
  env_codespaces 'CODESPACE_NAME=abc' 'GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev' "touch $TMP/execute"
  run steami-televerser
  [ ! -e "$TMP/execute" ]
}
