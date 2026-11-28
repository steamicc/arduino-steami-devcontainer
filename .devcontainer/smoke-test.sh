#!/usr/bin/env bash
# Test de fumée de l'image : outils en place, compilation sans réseau.
# Lancé depuis la racine du dépôt, dans l'image (voir CONTRIBUTING.md).
set -u

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB=/opt/steami/libs/STeaMi
# Le tag du paquet : la ligne « ARG STEAMI_PAQUET= » du Dockerfile, seule source.
PAQUET=$(sed -n 's/^ARG STEAMI_PAQUET=//p' "$(dirname "${BASH_SOURCE[0]}")/source/Dockerfile")
DAPLINK=$(sed -n 's/^ARG STEAMI_DAPLINK_RELEASE=//p' "$(dirname "${BASH_SOURCE[0]}")/source/Dockerfile")
DAPLINK_SHA=$(sed -n 's/^ARG STEAMI_DAPLINK_SHA256=//p' "$(dirname "${BASH_SOURCE[0]}")/source/Dockerfile")
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echec() { echo "✗ $*" >&2; exit 1; }
ok() { echo "✅ $*"; }

# Boucle des exemples du paquet :
#   - `representatif` (par défaut) : le premier exemple de chaque composant
#     (dossier de examples/), plus un exemple BLE s'il n'y en a pas déjà un. La
#     publication du paquet (steamicc/arduino-steami-lib) compile déjà tous ses
#     exemples avec le même core : ici, il suffit de prouver que la chaîne hors
#     ligne de l'image marche et trouve chaque bibliothèque ;
#   - `tous` : chaque exemple listé par steami-exemples (vérification à la main) ;
#   - `aucun` : boucle sautée.
# La CI des PR ne la lance qu'une fois par run (devcontainer.yml) ; la
# publication la lance toujours (devcontainer-publish.yml).
EXEMPLES=${STEAMI_SMOKE_EXEMPLES:-representatif}
case "$EXEMPLES" in
  representatif | tous | aucun) ;;
  *) echec "STEAMI_SMOKE_EXEMPLES vaut representatif, tous ou aucun (obtenu : « $EXEMPLES »)" ;;
esac

command -v pio >/dev/null 2>&1 || echec "pio est introuvable"
[ "$(pio --version)" = "PlatformIO Core, version 6.1.19" ] \
  || echec "pio --version devrait afficher 6.1.19, obtenu : $(pio --version)"
ok "PlatformIO 6.1.19"

[ -n "$PAQUET" ] || echec "ARG STEAMI_PAQUET introuvable dans le Dockerfile"
[ "$(git -C "$LIB" describe --tags 2>/dev/null)" = "$PAQUET" ] \
  || echec "le paquet STeaMi devrait être au tag $PAQUET"
grep -qx "version=${PAQUET#v}" "$LIB/library.properties" \
  || echec "library.properties devrait déclarer version=${PAQUET#v}"
ok "paquet STeaMi $PAQUET"

FW=/opt/steami/flasher/daplink
[ -n "$DAPLINK" ] && [ -n "$DAPLINK_SHA" ] || echec "ARG STEAMI_DAPLINK_* introuvables dans le Dockerfile"
[ -s "$FW/firmware.bin" ] || echec "firmware DAPLink absent ou vide : $FW/firmware.bin"
[ -s "$FW/firmware.json" ] || echec "firmware DAPLink absent ou vide : $FW/firmware.json"
[ "$(sha256sum "$FW/firmware.bin" | cut -d' ' -f1)" = "$DAPLINK_SHA" ] \
  || echec "le firmware DAPLink devrait avoir le SHA256 $DAPLINK_SHA"
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$FW/firmware.json")" = "$DAPLINK_SHA" ] \
  || echec "firmware.json devrait déclarer le SHA256 $DAPLINK_SHA"
[ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["release"], d["numero"], type(d["numero"]).__name__)' "$FW/firmware.json")" = "$DAPLINK ${DAPLINK##*.} int" ] \
  || echec "firmware.json devrait déclarer la release $DAPLINK et le numéro entier ${DAPLINK##*.}"
DAPLINK_DATE=$(printf '%s' "${DAPLINK%.*}" | tr -d '-')
[ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["date"], type(d["date"]).__name__)' "$FW/firmware.json")" = "$DAPLINK_DATE int" ] \
  || echec "firmware.json devrait déclarer la date entière $DAPLINK_DATE"
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["taille"])' "$FW/firmware.json")" = "$(stat -c %s "$FW/firmware.bin")" ] \
  || echec "firmware.json devrait déclarer la taille réelle de firmware.bin"
ok "firmware DAPLink $DAPLINK"

[ -d "$LIB/examples/LIS2MDL/BasicReader" ] \
  || echec "exemple LIS2MDL/BasicReader introuvable"
ok "exemple LIS2MDL/BasicReader présent"

cp -r "$RACINE/.devcontainer/source/amorcage" "$TMP/projet"
cd "$TMP/projet" || exit 1

pio run -e steami >"$TMP/base.log" 2>&1 || { tail -30 "$TMP/base.log" >&2; echec "compilation du projet d'amorçage"; }
ok "projet d'amorçage compilé"

steami-exemples lis2mdl | grep -qx LIS2MDL/BasicReader \
  || echec "steami-exemples lis2mdl devrait lister LIS2MDL/BasicReader"
ok "steami-exemples"

steami-compiler lis2mdl/basicreader >"$TMP/cmd.log" 2>&1 \
  || { tail -30 "$TMP/cmd.log" >&2; echec "steami-compiler lis2mdl/basicreader"; }
{ [ -s .steami/firmware.bin ] && grep -q '"programme": "LIS2MDL/BasicReader"' .steami/firmware.json; } \
  || echec "steami-compiler n'a pas écrit .steami/firmware.bin et firmware.json"
ok "steami-compiler lis2mdl/basicreader (nom réel : LIS2MDL/BasicReader)"

# Les exemples choisis (voir STEAMI_SMOKE_EXEMPLES), tels que steami-exemples
# les liste, compilés l'un après l'autre dans le même dossier de travail
# PlatformIO : les objets des bibliothèques sont compilés une fois et réutilisés
# (~11 s par exemple, contre ~83 s dans un dossier vide, et chaque compilation
# utilise déjà tous les cœurs : le parallèle n'a pas aidé). La fin du journal
# d'un exemple en échec est affichée. Chaque compilation affiche sa durée, puis
# les 10 plus lentes
# (tests/smoke-test.bats extrait ce bloc entre les deux repères : les garder).
# DEBUT boucle des exemples
# Une ligne par exemple : le premier de chaque composant, plus le premier
# exemple BLE (qui inclut STM32duinoBLE.h, installée à part dans l'image) si
# aucun de ceux-là n'en est un. Ordre de steami-exemples : déterministe.
selection_representative() {
  local ex ble=""
  awk -F/ '!vu[$1]++' "$1" >"$TMP/selection"
  while read -r ex; do
    if grep -rqsE '#include[[:space:]]*[<"]STM32duinoBLE\.h' "$LIB/examples/$ex"; then
      ble=$ex
      break
    fi
  done < <(cat "$TMP/selection" "$1")
  [ -n "$ble" ] \
    || echec "aucun exemple n'inclut STM32duinoBLE.h : l'image installe STM32duinoBLE pour les exemples BLE (voir le Dockerfile)"
  grep -qxF "$ble" "$TMP/selection" || echo "$ble" >>"$TMP/selection"
  LC_ALL=C sort -o "$TMP/selection" "$TMP/selection"
}

if [ "$EXEMPLES" != aucun ]; then
  steami-exemples >"$TMP/liste" || echec "steami-exemples a échoué"
  total=$(grep -c . "$TMP/liste")
  [ "$total" -ge 50 ] || echec "steami-exemples ne liste que $total exemples"
  if [ "$EXEMPLES" = tous ]; then
    cp "$TMP/liste" "$TMP/selection"
  else
    selection_representative "$TMP/liste"
  fi
  nb=$(grep -c . "$TMP/selection")
  echo "Exemples ($EXEMPLES) : $nb exemples sur $total"
  echo "Exemples compilés : $(paste -sd' ' "$TMP/selection")"
  : >"$TMP/durees"
  while read -r ex; do
    debut=$SECONDS
    PLATFORMIO_SRC_DIR="$LIB/examples/$ex" pio run -e steami >"$TMP/ex.log" 2>&1 \
      || { tail -30 "$TMP/ex.log" >&2; echec "compilation de $ex"; }
    secs=$((SECONDS - debut))
    printf '%s %ss\n' "$ex" "$secs"
    printf '%s %s\n' "$secs" "$ex" >>"$TMP/durees"
  done <"$TMP/selection"
  echo "Les 10 exemples les plus lents :"
  sort -rn "$TMP/durees" | head -10 | while read -r secs ex; do
    printf '  %ss %s\n' "$secs" "$ex"
  done
  ok "$nb exemples compilés"
else
  ok "boucle des exemples sautée (STEAMI_SMOKE_EXEMPLES=aucun)"
fi
# FIN boucle des exemples

# zsh par défaut, historique conservé dans /workspaces (volume persistant d'un
# Codespace). STEAMI_WORKSPACES remplace /workspaces pour pouvoir le simuler.
getent passwd vscode | grep -q ':/usr/bin/zsh$' \
  || echec "le shell de connexion de vscode devrait être /usr/bin/zsh"
ok "shell de connexion : zsh"

[ -d "$HOME/.oh-my-zsh" ] || echec "oh-my-zsh devrait être installé"
ok "oh-my-zsh présent"

mkdir "$TMP/ws"
[ "$(STEAMI_WORKSPACES="$TMP/ws" zsh -ic 'print -r -- $HISTFILE' 2>/dev/null)" = "$TMP/ws/.zsh_history" ] \
  || echec "zsh devrait écrire son historique dans /workspaces/.zsh_history"
[ "$(STEAMI_WORKSPACES="$TMP/ws" bash -ic 'echo "$HISTFILE"' 2>/dev/null)" = "$TMP/ws/.bash_history" ] \
  || echec "bash devrait écrire son historique dans /workspaces/.bash_history"
ok "HISTFILE dans /workspaces (zsh et bash)"

# Une ligne lue par un zsh interactif entre dans l'historique (pas avec -c).
echo 'echo steami-historique-zsh' | STEAMI_WORKSPACES="$TMP/ws" zsh -i >/dev/null 2>&1
STEAMI_WORKSPACES="$TMP/ws" zsh -ic 'fc -R; fc -ln 1' 2>/dev/null | grep -q steami-historique-zsh \
  || echec "une commande zsh devrait être retrouvée dans un nouveau shell"
ok "historique zsh écrit tout de suite"

# Sans history -a explicite : c'est PROMPT_COMMAND qui écrit, avant la fin du shell.
{ printf '%s\n' 'echo steami-historique-bash' 'kill -9 $$' | STEAMI_WORKSPACES="$TMP/ws" bash -i >/dev/null 2>&1; } 2>/dev/null
grep -q steami-historique-bash "$TMP/ws/.bash_history" 2>/dev/null \
  || echec "une commande bash devrait être retrouvée dans .bash_history"
ok "historique bash"

STEAMI_WORKSPACES="$TMP/absent" zsh -ic 'print -r -- $HISTFILE' 2>/dev/null | grep -qx "$HOME/.zsh_history" \
  || echec "sans /workspaces, HISTFILE de zsh devrait rester dans \$HOME"
STEAMI_WORKSPACES="$TMP/absent" bash -ic 'echo "$HISTFILE"' 2>/dev/null | grep -qx "$HOME/.bash_history" \
  || echec "sans /workspaces, HISTFILE de bash devrait rester dans \$HOME"
ok "sans /workspaces : historique inchangé"
