#!/usr/bin/env bash
# Test de fumée de l'image : outils en place, compilation sans réseau.
# Lancé depuis la racine du dépôt, dans l'image (voir CONTRIBUTING.md).
set -u

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB=/opt/steami/arduino-steami-lib
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echec() { echo "✗ $*" >&2; exit 1; }
ok() { echo "✅ $*"; }

command -v pio >/dev/null 2>&1 || echec "pio est introuvable"
[ "$(pio --version)" = "PlatformIO Core, version 6.1.19" ] \
  || echec "pio --version devrait afficher 6.1.19, obtenu : $(pio --version)"
ok "PlatformIO 6.1.19"

[ "$(git -C "$LIB" describe --tags 2>/dev/null)" = v0.24.0 ] \
  || echec "arduino-steami-lib devrait être au tag v0.24.0"
ok "arduino-steami-lib v0.24.0"

[ -d "$LIB/lib/lis2mdl/examples/BasicReader" ] \
  || echec "exemple lis2mdl/BasicReader introuvable"
ok "exemple lis2mdl/BasicReader présent"

cp -r "$RACINE/.devcontainer/source/amorcage" "$TMP/projet"
cd "$TMP/projet" || exit 1

pio run -e steami >"$TMP/base.log" 2>&1 || { tail -30 "$TMP/base.log" >&2; echec "compilation du projet d'amorçage"; }
ok "projet d'amorçage compilé"

steami-exemples lis2mdl | grep -qx lis2mdl/BasicReader \
  || echec "steami-exemples lis2mdl devrait lister lis2mdl/BasicReader"
ok "steami-exemples"

steami-compiler lis2mdl/BasicReader >"$TMP/cmd.log" 2>&1 \
  || { tail -30 "$TMP/cmd.log" >&2; echec "steami-compiler lis2mdl/BasicReader"; }
[ -s .steami/firmware.bin ] && grep -q '"programme": "lis2mdl/BasicReader"' .steami/firmware.json \
  || echec "steami-compiler n'a pas écrit .steami/firmware.bin et firmware.json"
ok "steami-compiler lis2mdl/BasicReader"

for ex in lis2mdl/BasicReader ble/BleBeacon; do
  dossier="$LIB/lib/${ex%%/*}/examples/${ex##*/}"
  PLATFORMIO_SRC_DIR="$dossier" pio run -e steami >"$TMP/ex.log" 2>&1 \
    || { tail -30 "$TMP/ex.log" >&2; echec "compilation de $ex"; }
  ok "$ex compilé"
done

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
