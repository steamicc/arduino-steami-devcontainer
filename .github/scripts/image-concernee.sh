#!/usr/bin/env bash
# =====================================================================
# image-concernee.sh : une PR peut-elle changer l'image ? Appelé par le
# job « build & smoke-test » de .github/workflows/devcontainer.yml.
#
#   image-concernee.sh <base> <tête>
#       Liste les fichiers changés par la PR (git diff base...tête, depuis
#       leur ancêtre commun, renommages comptés comme suppression + ajout)
#       et écrit une seule ligne :
#         true   au moins un fichier est une entrée de l'image (ci-dessous),
#                ou la liste n'a pas pu être établie : construire ;
#         false  aucune entrée de l'image : la construction peut être sautée.
#       La raison est écrite sur stderr.
#
# Entrées de l'image (tout ce que la construction ou le smoke-test lit) :
#   - tout `.devcontainer/` sauf `.devcontainer/devcontainer.json` :
#     `source/` (contexte de construction, Dockerfile, amorcage, commandes),
#     `smoke-test.sh` et tout fichier qui y serait ajouté ;
#   - `.github/workflows/devcontainer.yml` (la construction elle-même) ;
#   - ce script (la décision elle-même) et `.github/actions/` ;
#   - `.gitattributes` et `.gitmodules` (ce que contient le checkout).
# `.devcontainer/devcontainer.json` et `exemples/devcontainer.json` ne
# font que citer une image déjà publiée : la PR « chore: image » du robot
# publier-image ne touche qu'eux et ne construit donc rien ici
# (devcontainer-publish reconstruit et teste l'image au tag).
#
# Dans le doute, construire : toute erreur (commit absent, pas d'ancêtre
# commun, git en échec) donne true. Seul un mauvais nombre d'arguments
# donne la sortie 2.
# =====================================================================
set -uo pipefail

[ $# -eq 2 ] || { echo "Usage : image-concernee.sh <base> <tête>" >&2; exit 2; }
base=$1
tete=$2

construire() {
    echo "construction : $*" >&2
    echo true
    exit 0
}

# 0 si le chemin est une entrée de l'image.
entree_image() {
    case "$1" in
        .devcontainer/devcontainer.json) return 1 ;;
        .devcontainer/*) return 0 ;;
        .github/workflows/devcontainer.yml) return 0 ;;
        .github/scripts/image-concernee.sh) return 0 ;;
        .github/actions/*) return 0 ;;
        .gitattributes | */.gitattributes | .gitmodules) return 0 ;;
    esac
    return 1
}

for c in "$base" "$tete"; do
    git rev-parse -q --verify "$c^{commit}" >/dev/null 2>&1 \
        || construire "commit « $c » introuvable, liste des changements impossible"
done

liste=$(mktemp) || construire "fichier temporaire impossible"
trap 'rm -f "$liste"' EXIT
# -z : noms bruts, sans guillemets ni échappement (accents, retours à la ligne).
git diff -z --name-only --no-renames "$base...$tete" -- >"$liste" 2>/dev/null \
    || construire "git diff $base...$tete a échoué"

nb=0
while IFS= read -r -d '' f; do
    nb=$((nb + 1))
    entree_image "$f" && construire "$f est une entrée de l'image"
done <"$liste"

echo "aucune entrée de l'image parmi les $nb fichier(s) changé(s) : construction sautée" >&2
echo false
