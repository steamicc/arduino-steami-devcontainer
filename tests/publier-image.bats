#!/usr/bin/env bats
# Tests du script de décision du robot publier-image.
# Lancer : bats tests/publier-image.bats

bats_require_minimum_version 1.5.0

setup() {
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.org
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.org
  SCRIPT="$BATS_TEST_DIRNAME/../.github/scripts/publier-image.sh"
  CONCERNEE="$BATS_TEST_DIRNAME/../.github/scripts/image-concernee.sh"
  TMP="$(mktemp -d)"
  DEPOT="$TMP/depot"
  mkdir -p "$DEPOT/.devcontainer/source" "$DEPOT/exemples"
  echo 'FROM debian' > "$DEPOT/.devcontainer/source/Dockerfile"
  echo 'echo smoke' > "$DEPOT/.devcontainer/smoke-test.sh"
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

# Modifie le smoke-test (hors de .devcontainer/source) et committe.
changer_smoke() {
  echo 'echo encore' >> .devcontainer/smoke-test.sh
  git commit -q -am "fix: smoke-test"
}

# Modifie .devcontainer/devcontainer.json sans changer la version citée.
changer_devcontainer_json() {
  sed -i 's/"cpus": 2/"cpus": 4/' .devcontainer/devcontainer.json
  grep -q '"cpus": 4' .devcontainer/devcontainer.json
  git commit -q -am "chore: devcontainer.json"
}

@test "decider : version citée sans tag → tag" {
  citer 2026.11.11
  git tag devcontainer-2026.11.11
  citer 2026.11.12
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "tag 2026.11.12" ]
}

@test "decider : version citée sans tag mais pas après le dernier tag → erreur" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  citer 2026.11.5
  run --separate-stderr "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"2026.11.5"* ]]
  [[ "$stderr" == *"devcontainer-2026.11.12"* ]]
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

@test "decider : N avec un zéro en tête lu en base 10" {
  citer 2026.11.08
  git tag devcontainer-2026.11.08
  changer_source
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "pr 2026.11.9" ]
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

@test "decider : changement de .devcontainer/smoke-test.sh après le tag → pr" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_smoke
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "pr 2026.11.13" ]
}

@test "decider : changement de .devcontainer/devcontainer.json seul → rien" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_devcontainer_json
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [[ "$output" == "rien "* ]]
}

@test "decider : changement hors de .devcontainer/ → rien" {
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

@test "decider : lit le commit donné, pas l'arbre de travail" {
  citer 2026.11.11
  git tag devcontainer-2026.11.11
  changer_source
  citer 2026.11.12
  # HEAD~1 change la source et cite encore 2026.11.11 ; HEAD cite 2026.11.12.
  run "$SCRIPT" decider HEAD~1 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "pr 2026.11.12" ]
  run "$SCRIPT" decider HEAD 2026.11
  [ "$status" -eq 0 ]
  [ "$output" = "tag 2026.11.12" ]
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

@test "remplacer : un fichier sans la ligne de l'image → erreur, aucun fichier modifié" {
  citer 2026.11.12
  # Le second fichier ne cite plus l'image : le premier ne doit pas être réécrit.
  echo '{ "name": "test" }' > exemples/devcontainer.json
  git commit -q -am "test: exemples sans image"
  run --separate-stderr "$SCRIPT" remplacer 2026.11.13
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"exemples/devcontainer.json"* ]]
  git diff --quiet
}

@test "remplacer : version hors format → erreur" {
  citer 2026.11.12
  run "$SCRIPT" remplacer 2026.11
  [ "$status" -eq 2 ]
  git diff --quiet
}

# Crée la branche de la PR d'image depuis HEAD, y change la version, et
# revient sur main.
branche_pr() {
  git switch -q -c chore/image-2026.11.13
  citer 2026.11.13
  git switch -q main
}

@test "retard : changement de .devcontainer/source sur main → oui" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  branche_pr
  changer_source
  run "$SCRIPT" retard chore/image-2026.11.13 main
  [ "$status" -eq 0 ]
  [ "$output" = "oui" ]
}

@test "retard : changement de .devcontainer/smoke-test.sh sur main → oui" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  branche_pr
  changer_smoke
  run "$SCRIPT" retard chore/image-2026.11.13 main
  [ "$status" -eq 0 ]
  [ "$output" = "oui" ]
}

@test "retard : changement de .devcontainer/devcontainer.json seul sur main → non" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  branche_pr
  changer_devcontainer_json
  run "$SCRIPT" retard chore/image-2026.11.13 main
  [ "$status" -eq 0 ]
  [ "$output" = "non" ]
}

@test "retard : changement hors de .devcontainer/ sur main → non" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  branche_pr
  echo 'Une ligne de plus.' >> README.md
  git commit -q -am "docs: README"
  run "$SCRIPT" retard chore/image-2026.11.13 main
  [ "$status" -eq 0 ]
  [ "$output" = "non" ]
}

@test "retard : main déjà fusionné dans la branche → non" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  branche_pr
  changer_source
  # Ce que fait « gh pr update-branch » : fusion de main dans la branche.
  git switch -q chore/image-2026.11.13
  git merge -q --no-edit main
  git switch -q main
  run "$SCRIPT" retard chore/image-2026.11.13 main
  [ "$status" -eq 0 ]
  [ "$output" = "non" ]
}

# Part bien du merge-base : un correctif de .devcontainer/source propre à
# la branche de la PR ne compte pas comme un retard sur main.
@test "retard : changement de .devcontainer/source sur la branche seulement → non" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  branche_pr
  git switch -q chore/image-2026.11.13
  changer_source
  git switch -q main
  echo 'Une ligne de plus.' >> README.md
  git commit -q -am "docs: README"
  run "$SCRIPT" retard chore/image-2026.11.13 main
  [ "$status" -eq 0 ]
  [ "$output" = "non" ]
}

@test "retard : commit introuvable → erreur" {
  citer 2026.11.12
  run --separate-stderr "$SCRIPT" retard chore/image-inconnue main
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"chore/image-inconnue"* ]]
  run --separate-stderr "$SCRIPT" retard main 0123456789abcdef0123456789abcdef01234567
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "changements : commits de l'image seulement, depuis le tag" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  changer_source
  echo 'Une ligne de plus.' >> README.md
  git commit -q -am "docs: README"
  changer_devcontainer_json
  changer_smoke
  run --separate-stderr "$SCRIPT" changements devcontainer-2026.11.12 HEAD
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed 's/^[0-9a-f]* //')" = "$(printf '%s\n' "fix: smoke-test" "fix: change l'image")" ]
}

@test "changements : commit introuvable → erreur" {
  citer 2026.11.12
  run --separate-stderr "$SCRIPT" changements devcontainer-inconnu HEAD
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"devcontainer-inconnu"* ]]
}

# Les deux robots doivent compter les mêmes chemins de .devcontainer/ comme
# image : image-concernee.sh (construire sur une PR) et publier-image.sh
# (publier une nouvelle version). Les fichiers de CI que image-concernee.sh
# compte en plus sont hors de .devcontainer/ et restent hors de la publication.
@test "accord avec image-concernee.sh sur les chemins de .devcontainer/" {
  citer 2026.11.12
  git tag devcontainer-2026.11.12
  vus=""
  for chemin in .devcontainer/source/Dockerfile .devcontainer/smoke-test.sh \
                .devcontainer/devcontainer.json .devcontainer/x.sh \
                .devcontainer/source/devcontainer.json .devcontainer/nouveau/y.txt; do
    git switch -q -c essai devcontainer-2026.11.12
    if [ "$chemin" = .devcontainer/devcontainer.json ]; then
      sed -i 's/"cpus": 2/"cpus": 4/' "$chemin"
    else
      mkdir -p "$(dirname "$chemin")"
      echo 'une ligne' >> "$chemin"
    fi
    git add -A
    git commit -q -m "test: $chemin"
    [ "$(git diff --name-only devcontainer-2026.11.12 HEAD)" = "$chemin" ]

    run --separate-stderr "$CONCERNEE" devcontainer-2026.11.12 HEAD
    [ "$status" -eq 0 ]
    concernee=$output
    run "$SCRIPT" decider HEAD 2026.11
    [ "$status" -eq 0 ]
    decision=${output%% *}
    run "$SCRIPT" retard devcontainer-2026.11.12 HEAD
    [ "$status" -eq 0 ]
    retard=$output
    echo "$chemin : image-concernee=$concernee decider=$decision retard=$retard"
    vus="$vus $concernee"

    case "$concernee" in
      true) attendu="pr oui" ;;
      false) attendu="rien non" ;;
      *) attendu="réponse inattendue de image-concernee.sh" ;;
    esac
    [ "$decision $retard" = "$attendu" ]
    git switch -q main
    git branch -q -D essai
  done
  # Sans quoi l'accord ne vérifierait rien : des chemins des deux sortes.
  [[ "$vus" == *true* ]]
  [[ "$vus" == *false* ]]
}

# PR d'une liste `gh pr list --json number,state,author,isCrossRepository`.
pr_json() { # <numéro> <état> <auteur> [<fork : true|false>]
  printf '{"number": %s, "state": "%s", "author": {"login": "%s"}, "isCrossRepository": %s}' "$1" "$2" "$3" "${4:-false}"
}

@test "fermee : dernière PR du robot fermée sans fusion → son numéro" {
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 12 CLOSED app/mon-app)]"
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
  # Auteur sous la forme <slug>[bot] aussi accepté.
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 12 CLOSED 'mon-app[bot]')]"
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

@test "fermee : plusieurs PR fermées du robot → la plus récente" {
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 20 CLOSED app/mon-app), $(pr_json 31 CLOSED app/mon-app), $(pr_json 25 CLOSED app/mon-app)]"
  [ "$status" -eq 0 ]
  [ "$output" = "31" ]
}

@test "fermee : une PR fusionnée → rien" {
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 12 MERGED app/mon-app), $(pr_json 15 CLOSED app/mon-app)]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fermee : une PR encore ouverte → rien" {
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 12 CLOSED app/mon-app), $(pr_json 15 OPEN alice)]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fermee : dernière PR fermée d'une personne → rien" {
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 12 CLOSED app/mon-app), $(pr_json 15 CLOSED alice)]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 12 CLOSED app/autre-app)]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fermee : PR depuis un fork ignorées" {
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 12 CLOSED app/mon-app), $(pr_json 15 OPEN alice true), $(pr_json 16 MERGED alice true)]"
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
  run "$SCRIPT" fermee mon-app <<<"[$(pr_json 15 CLOSED app/mon-app true)]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fermee : aucune PR → rien" {
  run "$SCRIPT" fermee mon-app <<<"[]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fermee : entrée illisible ou slug absent → erreur" {
  run --separate-stderr "$SCRIPT" fermee mon-app <<<"pas du JSON"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr "$SCRIPT" fermee <<<"[]"
  [ "$status" -eq 2 ]
}

ROBOT=123+mon-app[bot]@users.noreply.github.com

# Commit sur la branche courante, avec l'auteur donné.
commit_de() { # <courriel> <message> [<fichier>]
  echo "$2" >> "${3:-README.md}"
  git add -A
  GIT_AUTHOR_EMAIL=$1 git commit -q -m "$2"
}

@test "auteur : branche du robot seulement → oui" {
  citer 2026.11.12
  git switch -q -c chore/image-2026.11.13
  commit_de "$ROBOT" "chore: image 2026.11.13"
  commit_de "$ROBOT" "Merge branch 'main'"
  git switch -q main
  run "$SCRIPT" auteur main chore/image-2026.11.13 "$ROBOT"
  [ "$status" -eq 0 ]
  [ "$output" = "oui" ]
}

@test "auteur : un commit d'une personne sur la branche → non" {
  citer 2026.11.12
  git switch -q -c chore/image-2026.11.13
  commit_de "$ROBOT" "chore: image 2026.11.13"
  commit_de alice@example.org "fix: à la main"
  git switch -q main
  run "$SCRIPT" auteur main chore/image-2026.11.13 "$ROBOT"
  [ "$status" -eq 0 ]
  [ "$output" = "non" ]
}

@test "auteur : commits de main (d'une personne) hors de la plage → oui" {
  citer 2026.11.12
  git switch -q -c chore/image-2026.11.13
  commit_de "$ROBOT" "chore: image 2026.11.13"
  git switch -q main
  commit_de alice@example.org "fix: sur main" .devcontainer/source/Dockerfile
  # Ce que fait « gh pr update-branch » : fusion de main par le robot.
  git switch -q chore/image-2026.11.13
  GIT_AUTHOR_EMAIL=$ROBOT git merge -q --no-edit main
  git switch -q main
  run "$SCRIPT" auteur main chore/image-2026.11.13 "$ROBOT"
  [ "$status" -eq 0 ]
  [ "$output" = "oui" ]
}

@test "auteur : rien de propre à la branche → non" {
  citer 2026.11.12
  git branch chore/image-2026.11.13
  run "$SCRIPT" auteur main chore/image-2026.11.13 "$ROBOT"
  [ "$status" -eq 0 ]
  [ "$output" = "non" ]
}

@test "auteur : courriel comparé en entier, pas comme motif" {
  citer 2026.11.12
  git switch -q -c chore/image-2026.11.13
  commit_de "x$ROBOT" "chore: image 2026.11.13"
  git switch -q main
  run "$SCRIPT" auteur main chore/image-2026.11.13 "$ROBOT"
  [ "$status" -eq 0 ]
  [ "$output" = "non" ]
}

@test "auteur : commit introuvable ou courriel absent → erreur" {
  citer 2026.11.12
  run --separate-stderr "$SCRIPT" auteur main chore/image-inconnue "$ROBOT"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"chore/image-inconnue"* ]]
  run --separate-stderr "$SCRIPT" auteur main main ""
  [ "$status" -eq 2 ]
}
