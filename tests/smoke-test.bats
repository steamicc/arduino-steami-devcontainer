#!/usr/bin/env bats
# Tests du smoke-test hors de l'image : seulement ce qui se vérifie avant
# les outils (la valeur de STEAMI_SMOKE_EXEMPLES) et la boucle des exemples, avec
# de faux outils. Le reste tourne dans
# l'image, en CI (devcontainer.yml).
# Lancer : bats tests/smoke-test.bats

bats_require_minimum_version 1.5.0

setup() {
  SMOKE="$BATS_TEST_DIRNAME/../.devcontainer/smoke-test.sh"
  SOURCE="$BATS_TEST_DIRNAME/../.devcontainer/source"
  BIN="$BATS_TEST_TMPDIR/bin"
  export FAUX_LIB="$BATS_TEST_TMPDIR/lib"
  mkdir -p "$BIN"
}

# Faux paquet : un dossier par exemple, COMPOSANT/Exemple/Exemple.ino. Les
# arguments sont des COMPOSANT/Exemple ; suffixe « :ble » pour un exemple qui
# inclut STM32duinoBLE.h.
faux_paquet() {
  local e ex
  for e in "$@"; do
    ex=${e%:ble}
    mkdir -p "$FAUX_LIB/examples/$ex"
    if [ "$ex" != "$e" ]; then
      printf '#include <STM32duinoBLE.h>\nvoid setup() {}\nvoid loop() {}\n' > "$FAUX_LIB/examples/$ex/${ex#*/}.ino"
    else
      printf '#include <Arduino.h>\nvoid setup() {}\nvoid loop() {}\n' > "$FAUX_LIB/examples/$ex/${ex#*/}.ino"
    fi
  done
}

# 50 exemples (le smoke-test en exige au moins 50) : AAA/Ex01..Ex20,
# MMM/Ex21..Ex40, ZZZ/Ex41..Ex50, plus ceux passés en arguments.
faux_paquet_50() {
  local i comp
  local exs=()
  for i in $(seq -w 1 50); do
    if [ "$i" -le 20 ]; then comp=AAA; elif [ "$i" -le 40 ]; then comp=MMM; else comp=ZZZ; fi
    exs+=("$comp/Ex$i")
  done
  faux_paquet "${exs[@]}" "$@"
}

# Faux pio : note l'exemple compilé, exige un dossier de travail
# (PLATFORMIO_WORKSPACE_DIR) propre à chaque compilation (mkdir échoue si une
# autre l'a déjà pris), compte les compilations simultanées. Ex07 dure 2 s ;
# l'exemple nommé par $PIO_ECHEC échoue.
faux_pio() {
  cat > "$BIN/pio" <<'PIO'
#!/bin/bash
ex=${PLATFORMIO_SRC_DIR#"$FAUX_LIB"/examples/}
[ -n "${PLATFORMIO_WORKSPACE_DIR:-}" ] || { echo "pas de PLATFORMIO_WORKSPACE_DIR" >&2; exit 3; }
mkdir -p "$(dirname "$PLATFORMIO_WORKSPACE_DIR")"
mkdir "$PLATFORMIO_WORKSPACE_DIR" || { echo "dossier de travail partagé : $PLATFORMIO_WORKSPACE_DIR" >&2; exit 4; }
echo "$ex" >> "$JOURNAL/compiles"
mkdir -p "$JOURNAL/actifs"
: > "$JOURNAL/actifs/$$"
ls "$JOURNAL/actifs" | wc -l >> "$JOURNAL/simultanes"
case "$ex" in */Ex07) sleep 2 ;; *) sleep 0.3 ;; esac
rm -f "$JOURNAL/actifs/$$"
if [ "$ex" = "${PIO_ECHEC:-}" ]; then
  echo "Compiling .pio/build/steami/src/$ex.o"
  echo "erreur bidon dans $ex" >&2
  exit 1
fi
echo "compilation de $ex terminée"
PIO
  chmod +x "$BIN/pio"
}

# Extrait la boucle (entre les repères) et la lance avec le vrai
# steami-exemples (sur le faux paquet) et le faux pio. $1 : le mode.
lancer_boucle() {
  faux_pio
  mkdir -p "$BATS_TEST_TMPDIR/journal" "$BATS_TEST_TMPDIR/tmp"
  sed -n '/^# DEBUT boucle des exemples$/,/^# FIN boucle des exemples$/p' "$SMOKE" > "$BATS_TEST_TMPDIR/boucle.sh"
  [ -s "$BATS_TEST_TMPDIR/boucle.sh" ]
  cat > "$BATS_TEST_TMPDIR/appel.sh" <<APPEL
set -u
TMP="$BATS_TEST_TMPDIR/tmp"; LIB="$FAUX_LIB"; EXEMPLES=$1; PARALLELE=4
echec() { echo "✗ \$*" >&2; exit 1; }
ok() { echo "✅ \$*"; }
. "$BATS_TEST_TMPDIR/boucle.sh"
APPEL
  PATH="$BIN:$SOURCE:$PATH" STEAMI_LIB="$FAUX_LIB" \
    JOURNAL="$BATS_TEST_TMPDIR/journal" PIO_ECHEC="${PIO_ECHEC:-}" \
    run --separate-stderr bash "$BATS_TEST_TMPDIR/appel.sh"
}

@test "STEAMI_SMOKE_EXEMPLES invalide → échec immédiat, avant les outils" {
  STEAMI_SMOKE_EXEMPLES=quelques run --separate-stderr "$SMOKE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"STEAMI_SMOKE_EXEMPLES vaut representatif, tous ou aucun"* ]]
  [[ "$stderr" != *"pio"* ]]
  [ -z "$output" ]
}

@test "STEAMI_SMOKE_EXEMPLES absent, vide, representatif, tous ou aucun → accepté (suite du test)" {
  # Faux pio à la mauvaise version : le script s'arrête juste après la
  # vérification de la variable, sans dépendre des outils de la machine.
  printf '#!/bin/sh\necho "PlatformIO Core, version 0.0.0"\n' > "$BIN/pio"
  chmod +x "$BIN/pio"
  for valeur in absent "" representatif tous aucun; do
    if [ "$valeur" = absent ]; then
      PATH="$BIN:$PATH" run --separate-stderr env -u STEAMI_SMOKE_EXEMPLES "$SMOKE"
    else
      PATH="$BIN:$PATH" STEAMI_SMOKE_EXEMPLES="$valeur" run --separate-stderr "$SMOKE"
    fi
    [ "$status" -eq 1 ]
    [[ "$stderr" != *"STEAMI_SMOKE_EXEMPLES"* ]]
    [[ "$stderr" == *"pio --version devrait afficher 6.1.19"* ]]
  done
}

@test "par défaut, le mode est representatif" {
  # shellcheck disable=SC2016 # la ligne exacte, sans expansion
  grep -qx 'EXEMPLES=${STEAMI_SMOKE_EXEMPLES:-representatif}' "$SMOKE"
}

@test "representatif : le premier exemple de chaque composant, dans l'ordre de steami-exemples" {
  faux_paquet_50 BLE/BleZ:ble BLE/BleA:ble
  lancer_boucle representatif
  [ "$status" -eq 0 ]
  [ "$(LC_ALL=C sort "$BATS_TEST_TMPDIR/journal/compiles" | paste -sd' ')" = "AAA/Ex01 BLE/BleA MMM/Ex21 ZZZ/Ex41" ]
  [[ "$output" == *"4 exemples sur 52"* ]]
  [ "${lines[-1]}" = "✅ 4 exemples compilés" ]
}

@test "representatif : un exemple BLE ajouté s'il n'y en a pas déjà un (le premier, dans l'ordre)" {
  # Aucun premier exemple de composant n'inclut STM32duinoBLE.h : le premier
  # exemple BLE de la liste est ajouté, un seul.
  faux_paquet_50 MMM/Ex33:ble ZZZ/Ex45:ble
  lancer_boucle representatif
  [ "$status" -eq 0 ]
  [ "$(LC_ALL=C sort "$BATS_TEST_TMPDIR/journal/compiles" | paste -sd' ')" = "AAA/Ex01 MMM/Ex21 MMM/Ex33 ZZZ/Ex41" ]
  [ "${lines[-1]}" = "✅ 4 exemples compilés" ]
}

@test "representatif : la sélection est la même d'un lancement à l'autre" {
  faux_paquet_50 MMM/Ex33:ble ZZZ/Ex45:ble
  lancer_boucle representatif
  [ "$status" -eq 0 ]
  premiere=$(printf '%s\n' "$output" | sed -n 's/^Exemples compilés : //p')
  [ "$premiere" = "AAA/Ex01 MMM/Ex21 MMM/Ex33 ZZZ/Ex41" ]
  rm -rf "$BATS_TEST_TMPDIR/journal" "$BATS_TEST_TMPDIR/tmp"
  lancer_boucle representatif
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n 's/^Exemples compilés : //p')" = "$premiere" ]
}

@test "representatif : aucun exemple BLE → échec clair" {
  faux_paquet_50
  lancer_boucle representatif
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"STM32duinoBLE"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/journal/compiles" ]
}

@test "tous : chaque exemple, durée de chaque exemple, puis les 10 plus lents, résumé" {
  faux_paquet_50 BLE/BleA:ble BLE/BleB:ble
  lancer_boucle tous
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/journal/compiles")" -eq 52 ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/journal/compiles" | wc -l)" -eq 52 ]
  # Durées en secondes entières (SECONDS) : 2 s pour Ex07, quasi rien sinon.
  [[ "$output" =~ (^|$'\n')"AAA/Ex07 "[23]"s"($'\n'|$) ]]
  [[ "$output" =~ (^|$'\n')"AAA/Ex01 "[01]"s"($'\n'|$) ]]
  [[ "$output" == *"Les 10 exemples les plus lents :"* ]]
  # Le plus lent est en tête de la liste, qui compte 10 lignes.
  [[ "$(printf '%s\n' "$output" | sed -n '/plus lents/,$p' | sed -n 2p)" =~ ^"  "[23]"s AAA/Ex07"$ ]]
  [ "$(printf '%s\n' "$output" | sed -n '/plus lents/,/compilés$/p' | grep -c '^  [0-9]*s ')" -eq 10 ]
  [ "${lines[-1]}" = "✅ 52 exemples compilés" ]
}

@test "tous : moins de 50 exemples listés → échec" {
  faux_paquet AAA/Ex01 BLE/BleA:ble
  lancer_boucle tous
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"steami-exemples ne liste que 2 exemples"* ]]
}

@test "compilations en parallèle, chacune dans son propre dossier de travail" {
  faux_paquet_50 BLE/BleA:ble
  lancer_boucle tous
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"dossier de travail partagé"* ]]
  # Au moins deux compilations ont tourné en même temps.
  [ "$(sort -n "$BATS_TEST_TMPDIR/journal/simultanes" | tail -1)" -ge 2 ]
  # La sortie de pio reste dans le journal de chaque exemple, sans se mêler.
  [[ "$output" != *"terminée"* ]]
}

@test "un exemple en échec dans un job parallèle → script en échec, message et fin du journal" {
  faux_paquet_50 BLE/BleA:ble
  PIO_ECHEC=MMM/Ex25 lancer_boucle tous
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"✗ compilation de MMM/Ex25"* ]]
  [[ "$stderr" == *"erreur bidon dans MMM/Ex25"* ]]
  # Le journal de l'exemple en échec est groupé : ses deux lignes se suivent.
  [[ "$stderr" == *"Compiling .pio/build/steami/src/MMM/Ex25.o"$'\n'"erreur bidon dans MMM/Ex25"* ]]
  [[ "$stderr" != *"compilation de MMM/Ex24"* ]]
  [[ "$output" != *"exemples compilés"* ]]
}

@test "aucun : la boucle est sautée" {
  faux_paquet_50 BLE/BleA:ble
  lancer_boucle aucun
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/journal/compiles" ]
  [ "${lines[-1]}" = "✅ boucle des exemples sautée (STEAMI_SMOKE_EXEMPLES=aucun)" ]
}
