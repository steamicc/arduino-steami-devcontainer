#!/usr/bin/env bats
# Tests du script de décision du robot publier-image.
# Lancer : bats tests/publier-image.bats

bats_require_minimum_version 1.5.0

setup() {
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.org
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.org
  SCRIPT="$BATS_TEST_DIRNAME/../.github/scripts/publier-image.sh"
  TMP="$(mktemp -d)"
  DEPOT="$TMP/depot"
  mkdir -p "$DEPOT/.devcontainer/source" "$DEPOT/exemples"
  echo 'FROM debian' > "$DEPOT/.devcontainer/source/Dockerfile"
  echo '# Dépôt de test' > "$DEPOT/README.md"
  git -C "$DEPOT" init -q -b main
  cd "$DEPOT"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Écrit un devcontainer.json qui cite la version donnée.
devcontainer() {
  cat > "$1" <<EOT
{
  "name": "test",
  "image": "ghcr.io/steamicc/arduino-steami-devcontainer:$2",
  "hostRequirements": { "cpus": 2 }
}
EOT
}

# Cite la version $1 dans .devcontainer/devcontainer.json et la version $2
# (par défaut la même) dans exemples/devcontainer.json, puis committe.
citer() {
  devcontainer .devcontainer/devcontainer.json "$1"
  devcontainer exemples/devcontainer.json "${2:-$1}"
  git add -A
  git commit -q -m "chore: image $1"
}

# Modifie le contexte de construction de l'image et committe.
changer_source() {
  echo 'RUN true' >> .devcontainer/source/Dockerfile
  git commit -q -am "fix: change l'image"
}

@test "decider : version citée sans tag → tag" {
  citer 2026.11.11
  git tag devcontainer-2026.11.11
  citer 2026.11.12
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "tag 2026.11.12" ]
}

@test "decider : source modifiée depuis le dernier tag → pr" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "pr 2026.11.13" ]
}

@test "decider : nouveau mois → N repart à 1" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  run "$SCRIPT" decider HEAD 2026.12
  [ "$status" -eq 0 ]
  [ "$output" = "pr 2026.12.1" ]
}

@test "decider : mois en arrière → garde le mois du dernier tag" {
  citer 2026.12.3
  git tag devcontainer-2026.12.3
  changer_source
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "pr 2026.12.4" ]
}

@test "decider : tri numérique des tags" {
  citer 2026.11.9
  git tag devcontainer-2026.11.9
  citer 2026.11.10
  git tag devcontainer-2026.11.10
  changer_source
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "pr 2026.11.11" ]
}

@test "decider : tags hors format ignorés" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  git tag devcontainer-test
  git tag devcontainer-2026.11
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "pr 2026.11.13" ]
}

@test "decider : changement hors de .devcontainer/source → rien" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  echo 'Une ligne de plus.' >> README.md
  git commit -q -am "docs: README"
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [[ "$output" == "rien "* ]]
}

@test "decider : aucun changement → rien" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [[ "$output" == "rien "* ]]
}

@test "decider : versions différentes → erreur" {
  citer 2026.11.12 2026.11.11
  run --separate-stderr "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"2026.11.12"* ]]
  [[ "$stderr" == *"2026.11.11"* ]]
}

@test "decider : date hors format → erreur" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  run "$SCRIPT" decider HEAD 2026-11
  [ "$status" -eq 2 ]
}

@test "remplacer : met la version dans les deux fichiers" {
  # Un autre fichier qui cite la version : il ne doit pas changer.
  echo 'ghcr.io/steamicc/arduino-steami-devcontainer:2026.11.12' >> README.md
  citer 2026.11.12
  run "$SCRIPT" remplacer 2026.11.13
  [ "$status" -eq 0 ]
  for f in .devcontainer/devcontainer.json exemples/devcontainer.json; do
    grep -q 'arduino-steami-devcontainer:2026.11.13"' "$f"
    [ "$(grep -c '2026.11.12' "$f")" -eq 0 ]
  done
  [ "$(git diff --name-only | sort)" = "$(printf '%s\n' .devcontainer/devcontainer.json exemples/devcontainer.json)" ]
  [ "$(git diff --stat | tail -1)" = " 2 files changed, 2 insertions(+), 2 deletions(-)" ]
}

@test "remplacer : version hors format → erreur" {
  citer 2026.11.12
  run "$SCRIPT" remplacer 2026.11
  [ "$status" -eq 2 ]
  git diff --quiet
}
