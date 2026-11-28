#!/usr/bin/env bash
# Décisions du robot suivre-paquet, testées dans tests/suivre-paquet.bats.
#
#   suivre-paquet.sh anciennes <branche> <slug-app>   (JSON de `gh pr list` sur l'entrée)
#       Numéros des PR ouvertes à fermer : branche chore/paquet-* de ce dépôt,
#       ouverte par l'App, autre que <branche>. Pas de --author côté gh (index
#       de recherche en retard) : le filtre se fait ici.
#
#   suivre-paquet.sh conflit <slug-app>   (JSON de `gh pr view --json mergeable,commits,isDraft,labels`)
#       ok       : la PR n'est pas en conflit (ou l'état est encore inconnu)
#       recreer  : en conflit, tous les commits sont de l'App : fermer la PR
#                  et en rouvrir une depuis main
#       humain   : en conflit, mais une personne a poussé dessus (ou la liste des
#                  commits / auteurs est vide) : ne rien casser
#       garde    : en conflit, mais en brouillon ou avec l'étiquette
#                  « garder-ouverte » : un mainteneur la gère à la main
set -euo pipefail

cmd=${1:-}
case "$cmd" in
  anciennes)
    branche=${2:?branche}
    slug=${3:?slug}
    jq -r --arg branche "$branche" --arg a1 "app/$slug" --arg a2 "${slug}[bot]" \
      '.[] | select((.isCrossRepository | not)
         and (.headRefName | startswith("chore/paquet-"))
         and .headRefName != $branche
         and (.author.login == $a1 or .author.login == $a2)) | .number'
    ;;
  conflit)
    slug=${2:?slug}
    jq -r --arg a1 "$slug" --arg a2 "${slug}[bot]" --arg a3 "app/$slug" \
      'if .mergeable != "CONFLICTING" then "ok"
       elif (.isDraft == true) or any((.labels // [])[]; .name == "garder-ouverte") then "garde"
       elif ((.commits | length) > 0
             and all(.commits[]; (.authors | length) > 0
                     and all(.authors[]; .login == $a1 or .login == $a2 or .login == $a3))) then "recreer"
       else "humain" end'
    ;;
  *)
    echo "usage: $0 anciennes <branche> <slug> | conflit <slug>" >&2
    exit 2
    ;;
esac
