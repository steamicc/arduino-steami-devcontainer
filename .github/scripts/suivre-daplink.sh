#!/usr/bin/env bash
# =====================================================================
# suivre-daplink.sh : règle de version et édition du Dockerfile pour le
# robot .github/workflows/suivre-daplink.yml.
#
#   suivre-daplink.sh lire
#       Écrit la release épinglée (ARG STEAMI_DAPLINK_RELEASE).
#   suivre-daplink.sh comparer <actuelle> <derniere>
#       Écrit « nouvelle » si <derniere> est différente et plus récente
#       (date, puis numéro, en nombre), « a_jour » sinon : jamais de
#       retour en arrière.
#   suivre-daplink.sh branche <release>
#       Écrit chore/daplink-<release à tirets> (pas de point après chore/).
#   suivre-daplink.sh epingler <release> <sha256>
#       Remplace les deux ARG dans .devcontainer/source/Dockerfile du
#       répertoire courant, et rien d'autre.
#
# Format de release exigé par le Dockerfile : AAAA-MM-JJ.N (le numéro est
# ce qui suit le dernier point). Pas de réseau, pas de git.
# Sortie 2, avec un message sur stderr, si une entrée est hors format.
# =====================================================================
set -euo pipefail

DOCKERFILE=.devcontainer/source/Dockerfile
FORMAT_RELEASE='^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$'
FORMAT_SHA='^[0-9a-f]{64}$'

erreur() {
    echo "suivre-daplink : $*" >&2
    exit 2
}

release_valide() {
    [[ "$1" =~ $FORMAT_RELEASE ]] || erreur "release « $1 » invalide : le format attendu est AAAA-MM-JJ.N"
}

case "${1:-}" in
lire)
    [ -f "$DOCKERFILE" ] || erreur "$DOCKERFILE introuvable."
    actuelle=$(sed -n 's/^ARG STEAMI_DAPLINK_RELEASE=//p' "$DOCKERFILE")
    [ "$(printf '%s\n' "$actuelle" | wc -l)" -eq 1 ] || erreur "ARG STEAMI_DAPLINK_RELEASE absent ou répété."
    release_valide "$actuelle"
    printf '%s\n' "$actuelle"
    ;;
comparer)
    [ $# -eq 3 ] || erreur "usage : comparer <actuelle> <derniere>"
    release_valide "$2"
    release_valide "$3"
    plus_recente=$(printf '%s\n%s\n' "$2" "$3" | sort -V | tail -n1)
    if [ "$2" = "$3" ] || [ "$plus_recente" != "$3" ]; then
        echo a_jour
    else
        echo nouvelle
    fi
    ;;
branche)
    [ $# -eq 2 ] || erreur "usage : branche <release>"
    release_valide "$2"
    printf 'chore/daplink-%s\n' "${2//./-}"
    ;;
epingler)
    [ $# -eq 3 ] || erreur "usage : epingler <release> <sha256>"
    release_valide "$2"
    [[ "$3" =~ $FORMAT_SHA ]] || erreur "sha256 « $3 » invalide : 64 caractères hexadécimaux en minuscules attendus."
    [ -f "$DOCKERFILE" ] || erreur "$DOCKERFILE introuvable."
    for arg in STEAMI_DAPLINK_RELEASE STEAMI_DAPLINK_SHA256; do
        [ "$(grep -c "^ARG $arg=" "$DOCKERFILE")" -eq 1 ] || erreur "ARG $arg absent ou répété dans $DOCKERFILE."
    done
    sed -i \
        -e "s/^ARG STEAMI_DAPLINK_RELEASE=.*/ARG STEAMI_DAPLINK_RELEASE=$2/" \
        -e "s/^ARG STEAMI_DAPLINK_SHA256=.*/ARG STEAMI_DAPLINK_SHA256=$3/" "$DOCKERFILE"
    grep -qx "ARG STEAMI_DAPLINK_RELEASE=$2" "$DOCKERFILE" || erreur "ARG STEAMI_DAPLINK_RELEASE non mis à jour."
    grep -qx "ARG STEAMI_DAPLINK_SHA256=$3" "$DOCKERFILE" || erreur "ARG STEAMI_DAPLINK_SHA256 non mis à jour."
    ;;
*)
    erreur "usage : suivre-daplink.sh lire | comparer <a> <d> | branche <r> | epingler <r> <sha256>"
    ;;
esac
