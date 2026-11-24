#!/usr/bin/env bats
# Tests des commandes steami-exemples, steami-compiler et steami-copier.
# Lancer : bats tests/commandes.bats

setup() {
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.org
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.org
  SRC="$BATS_TEST_DIRNAME/../.devcontainer/source"
  export PATH="$BATS_TEST_DIRNAME/stubs:$SRC:$PATH"
  TMP="$(mktemp -d)"
  export STEAMI_LIB="$TMP/STeaMi"
  export PIO_STUB_LOG="$TMP/pio.log"
  mkdir -p "$STEAMI_LIB/examples/LIS2MDL/BasicReader" "$STEAMI_LIB/examples/WSEN-HIDS/dew_point"
  echo '// basic' > "$STEAMI_LIB/examples/LIS2MDL/BasicReader/BasicReader.ino"
  echo '// dew' > "$STEAMI_LIB/examples/WSEN-HIDS/dew_point/dew_point.ino"
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
  [ "$output" = $'LIS2MDL/BasicReader\nWSEN-HIDS/dew_point' ]
}

@test "exemples_filtre_inconnu" {
  run steami-exemples zzz
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aucun exemple pour « zzz »"* ]]
}

@test "exemples_filtre_insensible_a_la_casse" {
  run steami-exemples lis2mdl
  [ "$status" -eq 0 ]
  [ "$output" = "LIS2MDL/BasicReader" ]
  run steami-exemples Wsen
  [ "$status" -eq 0 ]
  [ "$output" = "WSEN-HIDS/dew_point" ]
}

@test "exemples_liste_tout_sans_masque" {
  mkdir -p "$STEAMI_LIB/examples/LIS2MDL/DigitalCompass"
  echo '// ok' > "$STEAMI_LIB/examples/LIS2MDL/DigitalCompass/DigitalCompass.ino"
  run steami-exemples lis2mdl
  [ "$status" -eq 0 ]
  [ "$output" = $'LIS2MDL/BasicReader\nLIS2MDL/DigitalCompass' ]
}

@test "nom_insensible_a_la_casse_compiler" {
  run steami-compiler lis2mdl/basicreader
  [ "$status" -eq 0 ]
  grep -qx "PLATFORMIO_SRC_DIR=$STEAMI_LIB/examples/LIS2MDL/BasicReader" "$PIO_STUB_LOG"
  grep -q '"programme": "LIS2MDL/BasicReader"' .steami/firmware.json
}

@test "nom_insensible_a_la_casse_copier" {
  run steami-copier lis2mdl/basicreader
  [ "$status" -eq 0 ]
  [ "$(ls src)" = BasicReader.ino ]
}

@test "nom_ambigu_refuse" {
  mkdir -p "$STEAMI_LIB/examples/LIS2MDL/basicreader"
  echo '// autre' > "$STEAMI_LIB/examples/LIS2MDL/basicreader/basicreader.ino"
  run steami-compiler lis2mdl/BASICREADER
  [ "$status" -eq 1 ]
  [[ "$output" == *"ambigu"* ]]
  [[ "$output" == *"steami-exemples"* ]]
  run steami-compiler LIS2MDL/BasicReader
  [ "$status" -eq 0 ]
}

@test "nom_inconnu_renvoie_a_steami_exemples" {
  run steami-compiler lis2mdl/Inconnu
  [ "$status" -eq 1 ]
  [[ "$output" == *"Exemple inconnu"* ]]
  [[ "$output" == *"steami-exemples"* ]]
}

@test "exemple_sans_nom_refuse" {
  run steami-compiler LIS2MDL/
  [ "$status" -eq 1 ]
  [[ "$output" == *"Exemple inconnu"* ]]
  run steami-copier --remplacer LIS2MDL/
  [ "$status" -eq 1 ]
  [[ "$output" == *"Exemple inconnu"* ]]
  [ -f src/main.cpp ]
}

@test "compiler_avec_son_message_en_francais" {
  PIO_STUB_ECHEC=1 run steami-compiler
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗ La compilation a échoué"* ]]
}

@test "message_d_accueil_exact" {
  n="$BATS_TEST_DIRNAME/../.devcontainer/source/first-run-notice.txt"
  ! grep -q "envoie le programme" "$n"
  grep -q "prépare l'envoi" "$n"
  ! grep -q "n'en montre qu'un" "$n"
  grep -q "Stop Current Codespace" "$n"
  ! grep -q "Stop codespace" "$n"
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
  run steami-compiler LIS2MDL/BasicReader
  [ "$status" -eq 0 ]
  grep -qx "PLATFORMIO_SRC_DIR=$STEAMI_LIB/examples/LIS2MDL/BasicReader" "$PIO_STUB_LOG"
  grep -q '"programme": "LIS2MDL/BasicReader"' .steami/firmware.json
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
  run steami-copier LIS2MDL/BasicReader
  [ "$status" -eq 0 ]
  [ "$(ls src)" = BasicReader.ino ]
}

@test "copier_ignore_ino_cpp_genere" {
  echo '// généré par PlatformIO' > "$STEAMI_LIB/examples/LIS2MDL/BasicReader/BasicReader.ino.cpp"
  run steami-copier LIS2MDL/BasicReader
  [ "$status" -eq 0 ]
  [ "$(ls src)" = BasicReader.ino ]
}

@test "copier_refuse_src_modifie" {
  echo '// modifié' >> src/main.cpp
  run steami-copier LIS2MDL/BasicReader
  [ "$status" -eq 1 ]
  [[ "$output" == *"steami-sauver"* ]]
  [[ "$output" == *"--remplacer"* ]]
  grep -q '// modifié' src/main.cpp
}

@test "copier_remplacer_force" {
  echo '// modifié' >> src/main.cpp
  run steami-copier --remplacer LIS2MDL/BasicReader
  [ "$status" -eq 0 ]
  [ "$(ls src)" = BasicReader.ino ]
}

@test "aide" {
  run steami-compiler -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage : steami-compiler"* ]]
}
