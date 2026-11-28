#!/usr/bin/env bats
# Tests des décisions du robot suivre-paquet (PR dépassées, PR en conflit).
# Lancer : bats tests/suivre-paquet.bats

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../.github/scripts/suivre-paquet.sh"
}

liste() {
  cat <<'EOT'
[
 {"number":10,"headRefName":"chore/paquet-v0.47.0","isCrossRepository":false,"author":{"login":"app/robot"}},
 {"number":11,"headRefName":"chore/paquet-v0.48.0","isCrossRepository":false,"author":{"login":"app/robot"}},
 {"number":12,"headRefName":"chore/paquet-v0.46.0","isCrossRepository":true,"author":{"login":"app/robot"}},
 {"number":13,"headRefName":"chore/paquet-v0.45.0","isCrossRepository":false,"author":{"login":"alice"}},
 {"number":14,"headRefName":"chore/image-2026.11.1","isCrossRepository":false,"author":{"login":"app/robot"}},
 {"number":15,"headRefName":"chore/paquet-v0.44.0","isCrossRepository":false,"author":{"login":"robot[bot]"}}
]
EOT
}

@test "anciennes : seules les PR du robot, de ce dépôt, chore/paquet-*, autres que la courante" {
  run bash -c "'$SCRIPT' anciennes chore/paquet-v0.48.0 robot <<< \"\$(cat <<'EOT'
$(liste)
EOT
)\""
  [ "$status" -eq 0 ]
  [ "$output" = $'10\n15' ]
}

@test "anciennes : rien à fermer s'il n'y a que la PR courante" {
  run bash -c "echo '[{\"number\":11,\"headRefName\":\"chore/paquet-v0.48.0\",\"isCrossRepository\":false,\"author\":{\"login\":\"app/robot\"}}]' | '$SCRIPT' anciennes chore/paquet-v0.48.0 robot"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

pr() { # état, logins des auteurs des commits
  local m=$1; shift
  local c="" l
  for l in "$@"; do c="$c{\"authors\":[{\"login\":\"$l\"}]},"; done
  printf '{"mergeable":"%s","commits":[%s]}' "$m" "${c%,}"
}

@test "conflit : PR mergeable, ok" {
  run bash -c "$(declare -f pr); pr MERGEABLE 'robot[bot]' | '$SCRIPT' conflit robot"
  [ "$output" = ok ]
}

@test "conflit : état inconnu, ok (on réessaiera)" {
  run bash -c "$(declare -f pr); pr UNKNOWN 'robot[bot]' | '$SCRIPT' conflit robot"
  [ "$output" = ok ]
}

@test "conflit : en conflit, commits du robot seulement, recreer" {
  run bash -c "$(declare -f pr); pr CONFLICTING 'robot[bot]' robot | '$SCRIPT' conflit robot"
  [ "$output" = recreer ]
}

@test "conflit : en conflit avec un commit d'une personne, humain" {
  run bash -c "$(declare -f pr); pr CONFLICTING 'robot[bot]' alice | '$SCRIPT' conflit robot"
  [ "$output" = humain ]
}

@test "usage : commande inconnue refusée" {
  run "$SCRIPT" bidule
  [ "$status" -eq 2 ]
}
