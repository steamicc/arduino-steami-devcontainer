#!/usr/bin/env bats
# Tests de la garde commune de fusion automatique (.github/scripts/garde-fusion-auto.sh)
# et de son appel par les robots suivre-paquet et suivre-daplink.
# Lancer : bats tests/garde-fusion-auto.bats
#
# Le script est une copie à l'identique de la garde commune des dépôts steamicc :
# son comportement est testé avec sa source. Ici, on vérifie que la copie n'a pas
# été modifiée, et que les robots l'appellent avec les deux checks exigés par le
# ruleset « CI verte avant fusion ». Pour mettre la garde à jour : modifier la
# source commune, recopier le fichier, puis changer REFERENCE ci-dessous.

bats_require_minimum_version 1.5.0

REFERENCE=661489204d121fe3a25dbeb533fab7123f77001dda9f138bc6a157506b983324

setup() {
  RACINE="$BATS_TEST_DIRNAME/.."
  SCRIPT="$RACINE/.github/scripts/garde-fusion-auto.sh"
  APPEL='bash .github/scripts/garde-fusion-auto.sh "$GITHUB_REPOSITORY" "$PR" "$APP_SLUG" "tests des commandes" "build & smoke-test"'
}

# etape <workflow> : le bloc de l'étape « Active la fusion automatique ».
etape() {
  awk '/^      - name: Active la fusion automatique$/ { dedans = 1; print; next }
       dedans && /^      - / { exit }
       dedans { print }' "$RACINE/.github/workflows/$1"
}

@test "l'empreinte de la garde est celle de la référence commune (copie non modifiée)" {
  obtenu=$(sha256sum "$SCRIPT" | cut -d' ' -f1)
  [ "$obtenu" = "$REFERENCE" ]
}

@test "la garde est exécutable" {
  [ -x "$SCRIPT" ]
}

@test "la garde refuse un appel incomplet (sortie 2)" {
  run -2 env GH_TOKEN=x bash "$SCRIPT" steamicc/arduino-steami-devcontainer 12 robot
  [[ "$output" == *"Usage"* ]]
}

appel_de_la_garde() {
  run etape "$1"
  [ -n "$output" ]
  grep -qxF "          $APPEL" <<<"$output"
}

plus_de_garde_inline() {
  bloc=$(etape "$1")
  [ -n "$bloc" ]
  # « ! grep » ne fait pas échouer un test bats : test explicite.
  for motif in 'gh pr merge' 'rules/branches' 'current_user_can_bypass' 'isCrossRepository'; do
    if grep -qF "$motif" <<<"$bloc"; then
      echo "L'étape contient encore « $motif »."
      return 1
    fi
  done
}

jeton_de_l_app() {
  run etape "$1"
  grep -qxF '          GH_TOKEN: ${{ steps.app.outputs.token }}' <<<"$output"
  grep -qxF '          APP_SLUG: ${{ steps.app.outputs.app-slug }}' <<<"$output"
  grep -qxF "        if: steps.comparaison.outputs.action != ''" <<<"$output"
}

jeton_actions() {
  grep -qxF '          permission-actions: write' "$RACINE/.github/workflows/$1"
}

@test "suivre-paquet : la fusion automatique passe par la garde commune, avec les deux checks exigés" {
  appel_de_la_garde suivre-paquet.yml
}

@test "suivre-paquet : plus de garde écrite dans le workflow" {
  plus_de_garde_inline suivre-paquet.yml
}

@test "suivre-paquet : la garde reçoit le jeton de l'App et le slug du robot" {
  jeton_de_l_app suivre-paquet.yml
}

@test "suivre-paquet : le jeton de l'App peut relancer un check rouge (actions: write)" {
  jeton_actions suivre-paquet.yml
}

@test "suivre-daplink : la fusion automatique passe par la garde commune, avec les deux checks exigés" {
  appel_de_la_garde suivre-daplink.yml
}

@test "suivre-daplink : plus de garde écrite dans le workflow" {
  plus_de_garde_inline suivre-daplink.yml
}

@test "suivre-daplink : la garde reçoit le jeton de l'App et le slug du robot" {
  jeton_de_l_app suivre-daplink.yml
}

@test "suivre-daplink : le jeton de l'App peut relancer un check rouge (actions: write)" {
  jeton_actions suivre-daplink.yml
}
