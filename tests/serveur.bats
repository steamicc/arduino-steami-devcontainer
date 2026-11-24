#!/usr/bin/env bats
# Tests de la commande steami-serveur.
# Lancer : bats tests/serveur.bats

setup() {
  SRC="$BATS_TEST_DIRNAME/../.devcontainer/source"
  export PATH="$SRC:$PATH"
  TMP="$(mktemp -d)"
  export STEAMI_PID="$TMP/serveur.pid"
  export STEAMI_FLASHER="$TMP/flasher"
  export STEAMI_SERVEUR_PY="$SRC/steami_serveur.py"
  export STEAMI_LOG="$TMP/serveur.log"
  PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  export STEAMI_PORT="$PORT"
  mkdir -p "$STEAMI_FLASHER"
  echo '<h1>ok</h1>' > "$STEAMI_FLASHER/index.html"
  DEPOT="$TMP/depot"
  mkdir -p "$DEPOT/src" "$DEPOT/.steami"
  echo '[env:steami]' > "$DEPOT/platformio.ini"
  echo '{"programme":"src","taille":1}' > "$DEPOT/.steami/firmware.json"
  cd "$DEPOT"
}

teardown() {
  steami-serveur stop >/dev/null 2>&1 || true
  [ -z "${FAUX_PID:-}" ] || kill "$FAUX_PID" 2>/dev/null || true
  cd /
  rm -rf "$TMP"
}

attendre() {
  local i
  for i in $(seq 50); do
    curl -fs "http://127.0.0.1:$PORT/$1" >"$TMP/reponse" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

@test "start_rend_la_main" {
  run timeout 5 bash -c 'steami-serveur start | cat'
  [ "$status" -eq 0 ]
  [ ! -e nohup.out ]
  [ ! -e "$DEPOT/nohup.out" ]
  attendre ""
  run steami-serveur status
  [ "$status" -eq 0 ]
}

@test "start_pid_perime" {
  sleep 60 &
  FAUX_PID=$!
  echo "$FAUX_PID" > "$STEAMI_PID"
  run steami-serveur status
  [ "$status" -eq 1 ]
  run steami-serveur start
  [ "$status" -eq 0 ]
  attendre ""
  run steami-serveur status
  [ "$status" -eq 0 ]
}

@test "start_deux_fois" {
  steami-serveur start
  attendre ""
  pid=$(cat "$STEAMI_PID")
  steami-serveur start
  [ "$(cat "$STEAMI_PID")" = "$pid" ]
}

@test "stop_arrete" {
  steami-serveur start
  attendre ""
  run steami-serveur stop
  [ "$status" -eq 0 ]
  run steami-serveur status
  [ "$status" -eq 1 ]
}

@test "start_depuis_src" {
  cd "$DEPOT/src"
  steami-serveur start
  attendre firmware.json
  grep -q '"programme":"src"' "$TMP/reponse"
}

@test "start_port_pris" {
  python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",'"$PORT"')); s.listen(1); time.sleep(30)' &
  FAUX_PID=$!
  sleep 0.5
  run steami-serveur start
  [ "$status" -ne 0 ]
  [[ "$output" == *"n'a pas démarré"* ]]
  [[ "$output" == *"$STEAMI_LOG"* ]]
  [ ! -e "$STEAMI_PID" ]
}
