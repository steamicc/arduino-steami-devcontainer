# Historique des shells conservé dans un Codespace. Lu par /etc/zsh/zshenv (avant
# oh-my-zsh, qui ne définit HISTFILE que s'il est vide) et par /etc/bash.bashrc.
#
# /workspaces est le volume persistant d'un Codespace : il survit à l'arrêt et à
# la reconstruction du conteneur, et il est hors du dépôt (rien à commiter).
# Hors Codespace, il est absent ou non inscriptible : les réglages par défaut
# restent en place. STEAMI_WORKSPACES remplace /workspaces (tests).
_steami_ws="${STEAMI_WORKSPACES:-/workspaces}"
if [ -d "$_steami_ws" ] && [ -w "$_steami_ws" ]; then
  if [ -n "${ZSH_VERSION-}" ]; then
    # zsh (avec oh-my-zsh : share_history) écrit chaque commande tout de suite.
    HISTFILE="$_steami_ws/.zsh_history"
  elif [ -n "${BASH_VERSION-}" ]; then
    # bash n'écrit qu'à la fermeture du shell, que VS Code ne laisse pas se
    # faire : on ajoute à l'historique après chaque commande.
    HISTFILE="$_steami_ws/.bash_history"
    shopt -s histappend
    case ";${PROMPT_COMMAND-};" in
      *";history -a;"*) ;;
      *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
  fi
fi
unset _steami_ws
