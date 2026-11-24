# Fonctions communes aux commandes steami-* (à charger avec « source »).

STEAMI_LIB="${STEAMI_LIB:-/opt/steami/arduino-steami-lib}"

# Exemples de la bibliothèque qui ne compilent pas avec le tag des drivers de
# l'image (v0.24.0) : steami-exemples ne les liste pas. À vider quand un tag
# les corrige (CONTRIBUTING.md, « Mettre à jour les drivers »).
EXEMPLES_EXCLUS="${EXEMPLES_EXCLUS-lis2mdl/DigitalCompass ble/BleHotCold}"

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
    case "$ex" in */*/*|/*|*/|*..*) die "Exemple inconnu : « $ex ». Voir la liste avec steami-exemples." ;; esac
    d="$STEAMI_LIB/lib/${ex%%/*}/examples/${ex#*/}"
    [ "${ex#*/}" != "$ex" ] && [ -d "$d" ] || die "Exemple inconnu : « $ex ». Voir la liste avec steami-exemples."
    case " $EXEMPLES_EXCLUS " in
        *" $ex "*) echo "⚠ $ex ne compile pas avec les drivers de cette image : le résultat risque d'être une erreur de compilation." >&2 ;;
    esac
    printf '%s\n' "$d"
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
