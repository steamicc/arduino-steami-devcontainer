# Fonctions communes aux commandes steami-* (à charger avec « source »).

STEAMI_LIB="${STEAMI_LIB:-/opt/steami/arduino-steami-lib}"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# Affiche la commande (avec des guillemets autour des arguments qui contiennent
# une espace), puis la lance.
run() {
    local a ligne="→"
    for a in "$@"; do
        case "$a" in *" "*) ligne="$ligne \"$a\"" ;; *) ligne="$ligne $a" ;; esac
    done
    printf '%s\n' "$ligne"
    "$@"
}

# Remonte depuis $PWD jusqu'au premier dossier qui contient platformio.ini
# (sans git) et affiche son chemin.
racine_depot() {
    local d="$PWD"
    while [ "$d" != / ]; do
        if [ -f "$d/platformio.ini" ]; then printf '%s\n' "$d"; return 0; fi
        d=$(dirname "$d")
    done
    [ -f /platformio.ini ] && { echo /; return 0; }
    return 1
}

# Affiche le dossier d'un exemple « driver/Exemple », ou sort en erreur.
dossier_exemple() {
    local ex="$1" d
    case "$ex" in */*/*|/*|*..*) die "Exemple inconnu : « $ex ». Voir la liste avec steami-exemples." ;; esac
    d="$STEAMI_LIB/lib/${ex%%/*}/examples/${ex#*/}"
    [ "${ex#*/}" != "$ex" ] && [ -d "$d" ] || die "Exemple inconnu : « $ex ». Voir la liste avec steami-exemples."
    printf '%s\n' "$d"
}
