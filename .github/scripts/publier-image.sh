#!/usr/bin/env bash
# =====================================================================
# publier-image.sh : décide de la suite après un push sur main et réécrit
# la version de l'image. Appelé par .github/workflows/publier-image.yml.
#
#   publier-image.sh decider <commit> <AAAA.MM>
#       Lit l'état du dépôt (tags devcontainer-*, version citée par les
#       deux devcontainer.json au commit, changements de
#       .devcontainer/source) et écrit une seule ligne :
#         tag <V>      les deux fichiers citent <V>, qui n'a pas de tag
#                      et vient après le dernier tag (sinon sortie 2) ;
#         pr <V>       .devcontainer/source a changé depuis le dernier
#                      tag : <V> est la version suivante ;
#         rien <raison>  sinon.
#       <AAAA.MM> est le mois courant (UTC). La version suivante ne
#       recule jamais : si ce mois est antérieur à celui du dernier tag,
#       c'est le mois du dernier tag qui sert.
#
#   publier-image.sh remplacer <V>
#       Remplace la version citée dans les deux devcontainer.json du
#       répertoire courant, et rien d'autre.
#
# Lancer à la racine du dépôt. Le script ne fait ni commit, ni push, ni
# appel réseau : le workflow agit d'après sa sortie.
# Sortie 2, avec un message sur stderr, si les arguments ou les fichiers
# ne sont pas dans le format attendu.
# =====================================================================
set -euo pipefail

IMAGE=ghcr.io/steamicc/arduino-steami-devcontainer
FICHIERS=(.devcontainer/devcontainer.json exemples/devcontainer.json)
SOURCE=.devcontainer/source
FORMAT_VERSION='^[0-9]{4}\.[0-9]{2}\.[0-9]+$'
FORMAT_MOIS='^[0-9]{4}\.[0-9]{2}$'
# Ligne qui cite la version : "image": "ghcr.io/…:<V>",
LIGNE_IMAGE='^[[:space:]]*"image":[[:space:]]*"ghcr\.io/steamicc/arduino-steami-devcontainer:[^"]*",?[[:space:]]*$'

erreur() {
    echo "publier-image : $*" >&2
    exit 2
}

usage() {
    cat >&2 <<'EOT'
Usage : publier-image.sh decider <commit> <AAAA.MM>
        publier-image.sh remplacer <AAAA.MM.N>
EOT
    exit 2
}

# Version citée par un fichier, lue sur l'entrée standard.
version_citee() {
    local nom=$1 lignes
    lignes=$(grep -E "$LIGNE_IMAGE" || true)
    [ -n "$lignes" ] || erreur "$nom ne cite aucune version de $IMAGE."
    [ "$(printf '%s\n' "$lignes" | wc -l)" -eq 1 ] || erreur "$nom cite plusieurs fois $IMAGE."
    local v=${lignes#*"$IMAGE:"}
    v=${v%%\"*}
    [[ "$v" =~ $FORMAT_VERSION ]] || erreur "$nom cite la version « $v », hors du format AAAA.MM.N."
    printf '%s\n' "$v"
}

# Tags devcontainer-AAAA.MM.N, sans le préfixe, du plus petit au plus grand.
versions_taguees() {
    git tag -l 'devcontainer-*' | sed 's/^devcontainer-//' | { grep -E "$FORMAT_VERSION" || true; } | sort -V
}

decider() {
    [ $# -eq 2 ] || usage
    local commit=$1 mois=$2
    [[ "$mois" =~ $FORMAT_MOIS ]] || erreur "mois « $mois » hors du format AAAA.MM."
    git rev-parse -q --verify "$commit^{commit}" >/dev/null || erreur "commit « $commit » introuvable."

    local f contenu v versions=()
    for f in "${FICHIERS[@]}"; do
        contenu=$(git show "$commit:$f" 2>/dev/null) || erreur "$f absent du commit $commit."
        v=$(version_citee "$f" <<<"$contenu")
        versions+=("$v")
    done
    if [ "${versions[0]}" != "${versions[1]}" ]; then
        erreur "versions différentes : ${FICHIERS[0]} cite ${versions[0]}, ${FICHIERS[1]} cite ${versions[1]}."
    fi
    v=${versions[0]}

    local dernier
    dernier=$(versions_taguees | tail -n 1)

    # La version citée n'a pas encore de tag : c'est la PR d'image qui vient d'être fusionnée.
    if ! git rev-parse -q --verify "refs/tags/devcontainer-$v" >/dev/null; then
        # Jamais une version inférieure ou égale au dernier tag : le robot
        # suivre-image du modèle prend le plus grand tag et ne la suivrait pas.
        if [ -n "$dernier" ] && [ "$(printf '%s\n' "$dernier" "$v" | sort -V | tail -n 1)" = "$dernier" ]; then
            erreur "la version citée $v n'est pas après le dernier tag devcontainer-$dernier."
        fi
        echo "tag $v"
        return
    fi

    local rc=0
    git diff --quiet "devcontainer-$dernier" "$commit" -- "$SOURCE" || rc=$?
    case $rc in
        0) echo "rien aucun changement de $SOURCE depuis devcontainer-$dernier"; return ;;
        1) ;;
        *) erreur "git diff a échoué entre devcontainer-$dernier et $commit." ;;
    esac

    # Mois de la version suivante : jamais avant celui du dernier tag.
    local mois_dernier=${dernier%.*}
    if [[ "$mois" < "$mois_dernier" ]]; then
        mois=$mois_dernier
    fi
    local n_max
    n_max=$(versions_taguees | { grep -E "^${mois//./\\.}\\." || true; } | tail -n 1)
    if [ -n "$n_max" ]; then
        # 10# : un N écrit avec un zéro en tête (08) reste lu en base 10.
        echo "pr $mois.$((10#${n_max##*.} + 1))"
    else
        echo "pr $mois.1"
    fi
}

remplacer() {
    [ $# -eq 1 ] || usage
    local v=$1 f contenu
    [[ "$v" =~ $FORMAT_VERSION ]] || erreur "version « $v » hors du format AAAA.MM.N."
    # Tout vérifier avant d'écrire : ne jamais laisser un seul des deux fichiers modifié.
    for f in "${FICHIERS[@]}"; do
        [ -f "$f" ] || erreur "$f introuvable dans $(pwd)."
        contenu=$(<"$f")
        version_citee "$f" <<<"$contenu" >/dev/null
    done
    for f in "${FICHIERS[@]}"; do
        sed -i -E "\\%$LIGNE_IMAGE% s#(arduino-steami-devcontainer:)[^\"]*#\1$v#" "$f"
    done
}

case "${1:-}" in
    decider) shift; decider "$@" ;;
    remplacer) shift; remplacer "$@" ;;
    *) usage ;;
esac
