#!/usr/bin/env bats
# Tests du script du robot suivre-daplink (règle de version, édition du Dockerfile).
# Lancer : bats tests/suivre-daplink.bats

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../.github/scripts/suivre-daplink.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/.devcontainer/source"
  cat > "$TMP/.devcontainer/source/Dockerfile" <<'EOT'
FROM debian
ARG STEAMI_PAQUET=v0.41.0
ARG STEAMI_DAPLINK_RELEASE=2026-11-25.3
ARG STEAMI_DAPLINK_SHA256=73b67af70d7c42ef66589698caca95a89e8bd90b7001bfce0e570c70691287ea
RUN echo "${STEAMI_DAPLINK_RELEASE}"
EOT
  SHA=$(printf 'a%.0s' $(seq 64))
  cd "$TMP"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

@test "lire : la release épinglée dans le Dockerfile" {
  run "$SCRIPT" lire
  [ "$status" -eq 0 ]
  [ "$output" = "2026-11-25.3" ]
}

@test "comparer : même release, à jour" {
  run "$SCRIPT" comparer 2026-11-25.3 2026-11-25.3
  [ "$status" -eq 0 ]
  [ "$output" = "a_jour" ]
}

@test "comparer : numéro plus grand, nouvelle" {
  run "$SCRIPT" comparer 2026-11-25.3 2026-11-28.4
  [ "$status" -eq 0 ]
  [ "$output" = "nouvelle" ]
}

@test "comparer : le numéro se compare en nombre, pas en texte (9 puis 10)" {
  run "$SCRIPT" comparer 2026-11-28.9 2026-11-28.10
  [ "$output" = "nouvelle" ]
}

@test "comparer : numéro plus petit mais date postérieure, nouvelle" {
  run "$SCRIPT" comparer 2026-11-25.30 2026-11-28.4
  [ "$output" = "nouvelle" ]
}

@test "comparer : release plus ancienne, jamais de retour en arrière" {
  run "$SCRIPT" comparer 2026-11-28.4 2026-11-25.3
  [ "$status" -eq 0 ]
  [ "$output" = "a_jour" ]
}

@test "comparer : format invalide refusé (sortie 2)" {
  run "$SCRIPT" comparer 2026-11-25.3 v1.0
  [ "$status" -eq 2 ]
  run "$SCRIPT" comparer 2026-11-25 2026-11-28.4
  [ "$status" -eq 2 ]
  run "$SCRIPT" comparer 2026-11-25.3 "2026-11-28.4 "
  [ "$status" -eq 2 ]
}

@test "branche : points remplacés par des tirets" {
  run "$SCRIPT" branche 2026-11-28.4
  [ "$status" -eq 0 ]
  [ "$output" = "chore/daplink-2026-11-28-4" ]
}

@test "epingler : change les deux ARG et rien d'autre" {
  cp .devcontainer/source/Dockerfile avant
  run "$SCRIPT" epingler 2026-11-28.4 "$SHA"
  [ "$status" -eq 0 ]
  grep -qx "ARG STEAMI_DAPLINK_RELEASE=2026-11-28.4" .devcontainer/source/Dockerfile
  grep -qx "ARG STEAMI_DAPLINK_SHA256=$SHA" .devcontainer/source/Dockerfile
  run diff avant .devcontainer/source/Dockerfile
  [ "$(printf '%s\n' "$output" | grep -c '^[<>]')" -eq 4 ]
}

@test "epingler : sha256 invalide refusé, Dockerfile intact" {
  cp .devcontainer/source/Dockerfile avant
  run "$SCRIPT" epingler 2026-11-28.4 abc
  [ "$status" -eq 2 ]
  run diff avant .devcontainer/source/Dockerfile
  [ "$status" -eq 0 ]
}

@test "epingler : release invalide refusée" {
  run "$SCRIPT" epingler 28-11-2026 "$SHA"
  [ "$status" -eq 2 ]
}

@test "epingler : ARG absent, échec (sortie 2)" {
  sed -i '/STEAMI_DAPLINK_SHA256/d' .devcontainer/source/Dockerfile
  run "$SCRIPT" epingler 2026-11-28.4 "$SHA"
  [ "$status" -eq 2 ]
}
