#!/usr/bin/env bats
# Tests du filtre de devcontainer.yml : une PR doit-elle construire l'image ?
# Lancer : bats tests/image-concernee.bats

bats_require_minimum_version 1.5.0

setup() {
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.org
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.org
  SCRIPT="$BATS_TEST_DIRNAME/../.github/scripts/image-concernee.sh"
  TMP="$(mktemp -d)"
  DEPOT="$TMP/depot"
  mkdir -p "$DEPOT/.devcontainer/source/amorcage" "$DEPOT/exemples" \
           "$DEPOT/.github/workflows" "$DEPOT/.github/scripts" "$DEPOT/docs" "$DEPOT/tests"
  echo 'FROM debian' > "$DEPOT/.devcontainer/source/Dockerfile"
  echo '[env:steami]' > "$DEPOT/.devcontainer/source/amorcage/platformio.ini"
  echo '{}' > "$DEPOT/.devcontainer/devcontainer.json"
  echo '{}' > "$DEPOT/exemples/devcontainer.json"
  echo 'echo ok' > "$DEPOT/.devcontainer/smoke-test.sh"
  echo 'name: devcontainer' > "$DEPOT/.github/workflows/devcontainer.yml"
  echo 'name: publier-image' > "$DEPOT/.github/workflows/publier-image.yml"
  echo 'echo décide' > "$DEPOT/.github/scripts/image-concernee.sh"
  echo 'echo publie' > "$DEPOT/.github/scripts/publier-image.sh"
  echo '# Dépôt de test' > "$DEPOT/README.md"
  echo '# Contribuer' > "$DEPOT/CONTRIBUTING.md"
  echo '# Doc' > "$DEPOT/docs/guide.md"
  echo '@test "x" { true; }' > "$DEPOT/tests/x.bats"
  git -C "$DEPOT" init -q -b main
  cd "$DEPOT"
  git add -A
  git commit -q -m "init"
  BASE=$(git rev-parse HEAD)
  git switch -q -c pr
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Committe l'état courant de la branche de la PR.
commit() {
  git add -A
  git commit -q --allow-empty -m "${1:-change}"
}

# Lance le filtre entre la base et la tête de la PR ($1 : branche de tête, facultative).
decider() {
  if [ $# -ge 1 ]; then
    run --separate-stderr "$SCRIPT" "$BASE" "$(git rev-parse HEAD)" "$1"
  else
    run --separate-stderr "$SCRIPT" "$BASE" "$(git rev-parse HEAD)"
  fi
}

# Ce que fait la PR « chore: image » du robot publier-image.
changer_version() {
  echo '{"image": "x:2026.11.13"}' > .devcontainer/devcontainer.json
  echo '{"image": "x:2026.11.13"}' > exemples/devcontainer.json
  commit "chore: image 2026.11.13"
}

@test "README seul → pas de construction" {
  echo 'une ligne' >> README.md
  commit
  decider
  [ "$status" -eq 0 ]
  [ "$output" = false ]
}

@test "PR « chore: image » (les deux devcontainer.json) → pas de construction" {
  echo '{"image": "x:2026.11.13"}' > .devcontainer/devcontainer.json
  echo '{"image": "x:2026.11.13"}' > exemples/devcontainer.json
  commit "chore: image 2026.11.13"
  decider
  [ "$status" -eq 0 ]
  [ "$output" = false ]
}

@test "PR du robot (branche chore/image-*) → construction, même sans entrée de l'image" {
  changer_version
  decider chore/image-2026.11.13
  [ "$status" -eq 0 ]
  [ "$output" = true ]
  [[ "$stderr" == *"chore/image-2026.11.13"* ]]
}

@test "mêmes fichiers depuis une autre branche → pas de construction" {
  changer_version
  decider docs/version-image
  [ "$status" -eq 0 ]
  [ "$output" = false ]
}

@test "branche de tête vide → règle des chemins seule" {
  changer_version
  decider ""
  [ "$status" -eq 0 ]
  [ "$output" = false ]
}

@test "branche du robot et commits introuvables → construction" {
  run --separate-stderr "$SCRIPT" "" "" chore/image-2026.11.13
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "le préfixe chore/image- est bien celui des branches de publier-image.yml" {
  workflow="$BATS_TEST_DIRNAME/../.github/workflows/publier-image.yml"
  grep -qF 'branche="chore/image-$VERSION"' "$workflow"
  grep -qF 'PREFIXE_ROBOT=chore/image-' "$SCRIPT"
}

@test "docs, CONTRIBUTING, tests et autres workflows → pas de construction" {
  echo 'x' >> docs/guide.md
  echo 'x' >> CONTRIBUTING.md
  echo 'x' >> tests/x.bats
  echo 'x' >> .github/workflows/publier-image.yml
  echo 'x' >> .github/scripts/publier-image.sh
  echo 'name: suivre-daplink' > .github/workflows/suivre-daplink.yml
  commit
  decider
  [ "$status" -eq 0 ]
  [ "$output" = false ]
}

@test "aucun changement → pas de construction" {
  commit "vide"
  decider
  [ "$status" -eq 0 ]
  [ "$output" = false ]
}

@test "Dockerfile modifié → construction" {
  echo 'RUN true' >> .devcontainer/source/Dockerfile
  commit
  decider
  [ "$status" -eq 0 ]
  [ "$output" = true ]
  [[ "$stderr" == *".devcontainer/source/Dockerfile"* ]]
}

@test "fichier ajouté dans .devcontainer/source/ → construction" {
  echo 'x' > .devcontainer/source/nouveau
  commit
  decider
  [ "$output" = true ]
}

@test "fichier supprimé de .devcontainer/source/ → construction" {
  git rm -q .devcontainer/source/amorcage/platformio.ini
  commit
  decider
  [ "$output" = true ]
}

@test "renommage hors de .devcontainer/source/ → construction (suppression comptée)" {
  git mv .devcontainer/source/amorcage/platformio.ini docs/platformio.ini
  commit
  decider
  [ "$output" = true ]
}

@test "renommage vers .devcontainer/source/ → construction" {
  git mv docs/guide.md .devcontainer/source/guide.md
  commit
  decider
  [ "$output" = true ]
}

@test "smoke-test.sh modifié → construction" {
  echo 'x' >> .devcontainer/smoke-test.sh
  commit
  decider
  [ "$output" = true ]
}

@test "autre fichier de .devcontainer/ que devcontainer.json → construction" {
  echo 'x' > .devcontainer/autre.sh
  commit
  decider
  [ "$output" = true ]
}

@test "devcontainer.yml modifié → construction" {
  echo 'x' >> .github/workflows/devcontainer.yml
  commit
  decider
  [ "$output" = true ]
}

@test "le filtre lui-même modifié → construction" {
  echo 'x' >> .github/scripts/image-concernee.sh
  commit
  decider
  [ "$output" = true ]
}

@test ".github/actions/ ou .gitattributes → construction" {
  mkdir -p .github/actions/x
  echo 'name: x' > .github/actions/x/action.yml
  commit
  decider
  [ "$output" = true ]
  git reset -q --hard "$BASE"
  echo '* text=auto' > .gitattributes
  commit
  decider
  [ "$output" = true ]
}

@test "nom de fichier accentué dans .devcontainer/source/ → construction" {
  echo 'x' > .devcontainer/source/modèle.txt
  commit
  decider
  [ "$output" = true ]
}

@test "nom de fichier avec un retour à la ligne dans .devcontainer/source/ → construction" {
  echo 'x' > ".devcontainer/source/a
b"
  commit
  decider
  [ "$output" = true ]
}

@test "main a avancé avec un changement de l'image : seule la PR compte (base...tête)" {
  echo 'x' >> README.md
  commit
  tete=$(git rev-parse HEAD)
  git switch -q main
  echo 'RUN true' >> .devcontainer/source/Dockerfile
  commit "fix: image"
  base=$(git rev-parse HEAD)
  run --separate-stderr "$SCRIPT" "$base" "$tete"
  [ "$status" -eq 0 ]
  [ "$output" = false ]
}

@test "commit de base introuvable → construction (dans le doute)" {
  echo 'x' >> README.md
  commit
  run --separate-stderr "$SCRIPT" 0123456789abcdef0123456789abcdef01234567 "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
  [[ "$stderr" == *"construction"* ]]
}

@test "base vide → construction (dans le doute)" {
  run --separate-stderr "$SCRIPT" "" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "hors d'un dépôt git → construction (dans le doute)" {
  cd "$TMP"
  run --separate-stderr "$SCRIPT" "$BASE" "$BASE"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "mauvais nombre d'arguments → sortie 2" {
  run --separate-stderr "$SCRIPT" "$BASE"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr "$SCRIPT" "$BASE" "$BASE" chore/image-1 en-trop
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}
