# Fonctions communes aux commandes steami-* (à charger avec « source »).

STEAMI_LIB="${STEAMI_LIB:-/opt/steami/libs/STeaMi}"

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

# Affiche le dossier d'un exemple « COMPOSANT/Exemple » (les noms du menu
# Exemples de l'Arduino IDE : LIS2MDL/BasicReader), ou sort en erreur. La casse
# ne compte pas (lis2mdl/basicreader est accepté, pour l'ancienne documentation) ;
# si plusieurs dossiers conviennent, la correspondance exacte gagne, sinon la
# demande est ambiguë.
dossier_exemple() {
    local ex="$1" comp nom d
    local inconnu="Exemple inconnu : « $ex ». Voir la liste avec steami-exemples."
    case "$ex" in */*/*|/*|*/|*..*) die "$inconnu" ;; esac
    [ "${ex#*/}" != "$ex" ] || die "$inconnu"
    comp=$(trouver_nom "$STEAMI_LIB/examples" "${ex%%/*}" "$ex") || exit 1
    nom=$(trouver_nom "$STEAMI_LIB/examples/$comp" "${ex#*/}" "$ex") || exit 1
    d="$STEAMI_LIB/examples/$comp/$nom"
    printf '%s\n' "$d"
}

# Affiche le nom réel du sous-dossier de $1 qui correspond à $2 (exact, sinon
# sans tenir compte de la casse). Sort en erreur s'il n'y en a aucun ou
# plusieurs ($3 : la demande complète, pour les messages).
trouver_nom() {
    local parent="$1" voulu="$2" demande="$3" e n trouves=()
    [ -d "$parent/$voulu" ] && { printf '%s\n' "$voulu"; return 0; }
    for e in "$parent"/*/; do
        [ -d "$e" ] || continue
        n=$(basename "$e")
        [ "${n,,}" = "${voulu,,}" ] && trouves+=("$n")
    done
    case "${#trouves[@]}" in
        1) printf '%s\n' "${trouves[0]}" ;;
        0) die "Exemple inconnu : « $demande ». Voir la liste avec steami-exemples." ;;
        *) die "Nom ambigu : « $demande » correspond à plusieurs exemples (${trouves[*]}). Voir la liste avec steami-exemples." ;;
    esac
}

# Complète CODESPACE_NAME et GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN depuis le
# fichier .env de Codespaces quand elles sont absentes (session SSH). Le
# fichier contient aussi GITHUB_TOKEN : il n'est jamais sourcé, seules ces deux
# clés sont lues, et les variables déjà présentes gardent la priorité.
secours_env_codespaces() {
    local f="${STEAMI_CODESPACES_ENV:-/workspaces/.codespaces/shared/.env}" cle val
    { [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; } && return 0
    [ -r "$f" ] || return 0
    while IFS='=' read -r cle val || [ -n "$cle" ]; do
        case "$cle" in CODESPACE_NAME|GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN) ;; *) continue ;; esac
        val=${val%$'\r'}
        case "$val" in
            \"*\"|\'*\') val=${val:1:${#val}-2} ;;
        esac
        [ -n "$val" ] && [ -z "${!cle:-}" ] && printf -v "$cle" '%s' "$val"
    done < "$f"
    return 0
}
