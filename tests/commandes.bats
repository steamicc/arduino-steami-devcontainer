#!/usr/bin/env bats
# Tests des commandes steami-exemples, steami-compiler et steami-copier.
# Lancer : bats tests/commandes.bats

setup() {
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.org
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.org
  SRC="$BATS_TEST_DIRNAME/../.devcontainer/source"
  export PATH="$BATS_TEST_DIRNAME/stubs:$SRC:$PATH"
  TMP="$(mktemp -d)"
  export STEAMI_LIB="$TMP/lib-steami"
  export PIO_STUB_LOG="$TMP/pio.log"
  mkdir -p "$STEAMI_LIB/lib/lis2mdl/examples/BasicReader" "$STEAMI_LIB/lib/hts221/examples/dew_point"
  echo '// basic' > "$STEAMI_LIB/lib/lis2mdl/examples/BasicReader/BasicReader.ino"
  echo '// dew' > "$STEAMI_LIB/lib/hts221/examples/dew_point/dew_point.ino"
  DEPOT="$TMP/depot"
  mkdir -p "$DEPOT/src"
  echo '[env:steami]' > "$DEPOT/platformio.ini"
  echo 'void setup(){}' > "$DEPOT/src/main.cpp"
  printf '.steami/\n.pio/\n' > "$DEPOT/.gitignore"
  git -C "$DEPOT" init -q
  git -C "$DEPOT" add -A
  git -C "$DEPOT" commit -q -m init
  cd "$DEPOT"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

@test "exemples_liste_tout" {
  run steami-exemples
  [ "$status" -eq 0 ]
  [ "$output" = $'hts221/dew_point\nlis2mdl/BasicReader' ]
}

@test "exemples_filtre_inconnu" {
  run steami-exemples zzz
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aucun exemple pour « zzz »"* ]]
}

@test "compiler_src" {
  run steami-compiler
  [ "$status" -eq 0 ]
  grep -q '"programme": "src"' .steami/firmware.json
  [ -f .steami/firmware.bin ]
}

@test "compiler_depuis_src" {
  cd src
  run steami-compiler
  [ "$status" -eq 0 ]
  [ -f "$DEPOT/.steami/firmware.bin" ]
  [ ! -d "$DEPOT/src/.steami" ]
}

@test "compiler_hors_depot_git" {
  cp -r "$DEPOT" "$TMP/copie"
  rm -rf "$TMP/copie/.git"
  cd "$TMP/copie"
  run steami-compiler
  [ "$status" -eq 0 ]
  [ -f .steami/firmware.bin ]
}

@test "compiler_exemple" {
  run steami-compiler lis2mdl/BasicReader
  [ "$status" -eq 0 ]
  grep -qx "PLATFORMIO_SRC_DIR=$STEAMI_LIB/lib/lis2mdl/examples/BasicReader" "$PIO_STUB_LOG"
  grep -q '"programme": "lis2mdl/BasicReader"' .steami/firmware.json
}

@test "compiler_exemple_inconnu" {
  run steami-compiler nimporte/Quoi
  [ "$status" -eq 1 ]
  [[ "$output" == *"steami-exemples"* ]]
}

@test "echec_ne_touche_pas_au_binaire" {
  steami-compiler
  json_avant="$(cat .steami/firmware.json)"
  bin_avant="$(cat .steami/firmware.bin)"
  PIO_STUB_ECHEC=1 run steami-compiler
  [ "$status" -ne 0 ]
  [ "$(cat .steami/firmware.json)" = "$json_avant" ]
  [ "$(cat .steami/firmware.bin)" = "$bin_avant" ]
}

@test "copier_remplace_src" {
  run steami-copier lis2mdl/BasicReader
  [ "$status" -eq 0 ]
  [ "$(ls src)" = BasicReader.ino ]
}

@test "copier_refuse_src_modifie" {
  echo '// modifié' >> src/main.cpp
  run steami-copier lis2mdl/BasicReader
  [ "$status" -eq 1 ]
  [[ "$output" == *"steami-sauver"* ]]
  [[ "$output" == *"--remplacer"* ]]
  grep -q '// modifié' src/main.cpp
}

@test "copier_remplacer_force" {
  echo '// modifié' >> src/main.cpp
  run steami-copier --remplacer lis2mdl/BasicReader
  [ "$status" -eq 0 ]
  [ "$(ls src)" = BasicReader.ino ]
}

@test "aide" {
  run steami-compiler -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage : steami-compiler"* ]]
}
