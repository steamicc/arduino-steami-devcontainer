# Publier l'image automatiquement — conception

Issue : [#33](https://github.com/steamicc/arduino-steami-devcontainer/issues/33). Date : 2026-11-28. Approche validée par l'utilisateur le 2026-11-28 (« Allons-y ») ; conception courte.

## Intention

Après la fusion d'un changement de l'image, il faut aujourd'hui trois gestes manuels : une PR « chore: image AAAA.MM.N » qui change les deux `devcontainer.json`, sa fusion, puis le push du tag `devcontainer-AAAA.MM.N` (CONTRIBUTING.md, « Publier une nouvelle image »). Le modèle `arduino-steami-starter` suit déjà seul (robot `suivre-image`, PR #14 du modèle). Le but : qu'un changement fusionné arrive jusqu'aux élèves sans geste manuel, toujours à travers la CI.

## Objectifs

- Un robot `publier-image` (workflow `.github/workflows/publier-image.yml`) qui, à chaque push sur `main` :
  1. **pose le tag** `devcontainer-V` sur le commit poussé quand les deux `devcontainer.json` y citent une version `V` qui n'a pas encore de tag (cas de la PR « chore: image V » qui vient d'être fusionnée, par le robot ou à la main) ;
  2. sinon, **ouvre la PR** « chore: image V » quand l'image a changé depuis le dernier tag `devcontainer-*` (tout `.devcontainer/` sauf `.devcontainer/devcontainer.json`, voir Contraintes), avec la fusion automatique (squash), comme `suivre-paquet.yml`.
- Le tag est poussé avec le jeton de l'App : `devcontainer-publish.yml` se déclenche alors (un tag poussé avec `GITHUB_TOKEN` ne déclenche aucun workflow).
- Version `AAAA.MM.N` : `AAAA.MM` = mois courant (UTC) ; `N` = 1 + le plus grand `N` des tags `devcontainer-AAAA.MM.*`, ou 1 s'il n'y en a aucun ce mois-ci.
- Documentation à jour : CONTRIBUTING.md (« Publier une nouvelle image », « Mettre à jour le paquet des drivers »), en-têtes de `devcontainer-publish.yml` et `suivre-paquet.yml`, et le corps de la PR de `suivre-paquet` (« La suite, à la main… »).

## Non-objectifs

- semantic-release : il ne produit pas `AAAA.MM.N`, et pousser un commit de version sur `main` demanderait une exception au ruleset « CI verte avant fusion ».
- Déclencher depuis ici le robot du modèle : il tourne chaque jour (06:47) et à la demande ; le lancer depuis ce dépôt demanderait un jeton de l'App sur un autre dépôt avec le droit Actions.
- CHANGELOG ou notes de release générées.
- Republier une version dont la publication a échoué : le tag reste, la correction suivante prend la version suivante.

## Anti-objectifs

- Publier sans CI verte : la PR « chore: image » passe par le ruleset (checks « tests des commandes » et « build & smoke-test ») ; `devcontainer-publish` refait le smoke-test avant de pousser.
- Réutiliser ou écraser une version : jamais de tag sur une version déjà taguée ni déjà présente sur ghcr.io.
- Ouvrir deux PR d'image à la fois, ou une PR d'image pour un changement qui ne touche pas l'image (docs, CI, tests).
- Affaiblir un ruleset ou donner au robot plus que Contents, Pull requests, Workflows (`gh pr update-branch`) et Actions (relance d'un check exigé rouge par la garde, issue [#54](https://github.com/steamicc/arduino-steami-devcontainer/issues/54)) en écriture sur ce dépôt.

## Contraintes

- Rulesets de `main` : `Default_Ruleset` (organisation : PR obligatoire, squash ou rebase, historique linéaire ; l'App `semantic-release-updater`, id 1055123, a une exception) et « CI verte avant fusion » (dépôt : checks obligatoires, sans exception). Les tags ne sont soumis à aucun ruleset.
- Secrets `RELEASE_APP_ID` / `RELEASE_APP_SECRET` au niveau de l'organisation ; l'App est installée sur tous les dépôts.
- Le contexte de construction de l'image est `.devcontainer/source/` (`.devcontainer/source/devcontainer.json`). Ce qui change l'image publiée est plus large : tout `.devcontainer/` sauf `.devcontainer/devcontainer.json`, qui ne fait que citer l'image, donc aussi `.devcontainer/smoke-test.sh`, qui décide de la publication (issue [#51](https://github.com/steamicc/arduino-steami-devcontainer/issues/51) : au départ, seul `.devcontainer/source/` comptait, et une correction du smoke-test seul ne donnait pas de nouvelle image). C'est la partie `.devcontainer/` de `entree_image` dans `.github/scripts/image-concernee.sh` ; le pathspec est défini une fois, `IMAGE_CHEMINS` dans `publier-image.sh`, et un test bats vérifie l'accord des deux scripts. Les autres entrées d'`image-concernee.sh` ne donnent pas de nouvelle image : les fichiers de CI (`devcontainer.yml`, `.github/actions/`, `image-concernee.sh`), qui ne la changent pas, et `.gitattributes` et `.gitmodules` hors de `.devcontainer/`, qui peuvent la changer au checkout (fins de ligne, filtres) ; ce cas rare se publie par « En secours, à la main » (choix : la publication automatique s'en tient à `.devcontainer/`).
- Les tests du dépôt tournent avec `bats tests/`, `python3 -m unittest`, `node --test` (CONTRIBUTING.md, job « tests des commandes »).
- Conventions : messages et commentaires en français, Conventional Commits, actions épinglées par SHA, neutralisé dans les forks (`if: github.repository == …`).

## Approches

1. **Robot en deux temps, PR puis tag** (choisie) : chaque étape passe par la CI et les rulesets sans exception ; garde `AAAA.MM.N`.
2. **semantic-release** : notes de release en plus, mais versions semver (un `feat` donnerait 2026.12.0) et commit de version poussé sur `main` à travers « CI verte avant fusion » (exception à ajouter). Écartée.
3. **Tag direct à chaque fusion, sans PR** : le tag pointerait sur un commit dont les `devcontainer.json` citent l'ancienne version. Écartée.

## Conception

- **Script** `.github/scripts/publier-image.sh` (bash), testé par `tests/publier-image.bats` sur des dépôts git temporaires. Il lit l'état du dépôt (tags, contenu des deux `devcontainer.json` au commit donné, `git diff` de l'image, `IMAGE_CHEMINS`) et une date `AAAA.MM` passée en argument, et écrit sur la sortie la décision : `tag V`, `pr V`, ou `rien <raison>`. Il ne touche à rien (ni push, ni réseau).
  - `tag V` : les deux fichiers citent la même `V` au format `AAAA.MM.N`, et `devcontainer-V` n'existe pas.
  - Les deux fichiers citent des versions différentes : erreur (code non nul), à corriger à la main.
  - `pr V` : `devcontainer-V` existe déjà pour la version citée, `git diff --quiet <dernier tag> <commit> -- .devcontainer/ ':(exclude).devcontainer/devcontainer.json'` signale un changement, et `V` = version suivante calculée.
  - `rien` sinon (aucun changement de l'image).
  - Dernier tag : le plus grand `devcontainer-*` au format `AAAA.MM.N`, trié par `sort -V`.
- **Workflow** `publier-image.yml` : `on: push: branches: [main]` et `workflow_dispatch` ; `concurrency: publier-image` ; permissions en lecture ; même vérification des secrets et même jeton d'App que `suivre-paquet.yml` (Contents, Pull requests et Actions en écriture, plus Workflows, ce dépôt seulement) ; `actions/checkout` avec `fetch-depth: 0` et les tags.
  - `tag V` : vérifier que `ghcr.io/…:V` n'existe pas (`docker manifest inspect`, même règle que `devcontainer-publish`), puis `git tag devcontainer-V <sha du push>` et `git push origin devcontainer-V` avec le jeton de l'App.
  - `pr V` : si une PR ouverte du robot `chore/image-*` existe déjà, mettre sa branche à jour avec `main` (`gh pr update-branch`, jeton de l'App) quand `publier-image.sh retard <tête> <sha>` vaut `oui` (l'image a changé entre leur `merge-base` et le sha), avertir si cette mise à jour échoue (sans faire échouer le job), puis passer la PR à la garde commune de fusion automatique, sauf si la mise à jour vient de réussir dans ce run et que la fusion automatique est déjà activée (ajouté après coup, issue #43 : une PR d'image rouge bloquait sans bruit toutes les publications suivantes ; d'abord un avertissement sur les checks rouges, remplacé par la garde, issue [#54](https://github.com/steamicc/arduino-steami-devcontainer/issues/54)) ; si la dernière PR `chore/image-V` de ce dépôt est une PR du robot fermée sans fusion, sans PR ouverte ni fusionnée pour V (`publier-image.sh fermee <slug>`, sur le JSON de `gh pr list --state all --head chore/image-V`), la remplacer quand `publier-image.sh retard <tête de la PR fermée> <sha>` vaut `oui` (tête lue par `refs/pull/<N>/head`, même si la branche a été supprimée) : supprimer sa branche si elle existe encore et que `publier-image.sh auteur <sha> <branche> <courriel du bot>` vaut `oui` (tous les commits propres à la branche ont pour auteur le bot de l'App ; sinon avertissement et rien), avec `--force-with-lease` sur la tête vérifiée, puis suivre le chemin d'une nouvelle PR, dont le corps cite la PR fermée ; si `retard` vaut `non`, notice « PR #N fermée par un mainteneur, aucun nouveau changement de l'image depuis : rien à faire » (ajouté après coup, issue [#50](https://github.com/steamicc/arduino-steami-devcontainer/issues/50) : fermer une PR d'image encore valable bloquait le robot jusqu'au mois suivant) ; sinon, si la branche `chore/image-V` ou une PR de ce nom existe (ouverte, fusionnée, ou d'une personne), ne rien faire ; sinon créer la branche, remplacer la version dans les deux fichiers, committer (auteur : le bot de l'App) « chore: image V », ouvrir la PR (corps : `publier-image.sh changements <dernier tag> <sha>`, la liste `git log --oneline` des commits de l'image depuis le dernier tag) et activer la fusion automatique par la garde commune, comme `suivre-paquet`.
- **Fusion automatique** : la garde commune `.github/scripts/garde-fusion-auto.sh` (copie à l'identique dans les dépôts steamicc, empreinte vérifiée par `tests/garde-fusion-auto.bats`, qui vérifie aussi l'appel par `publier-image.yml`), appelée avec le jeton de l'App et les checks « tests des commandes » et « build & smoke-test », pour une PR qui vient d'être ouverte comme pour une PR déjà ouverte (issue [#54](https://github.com/steamicc/arduino-steami-devcontainer/issues/54)). Elle refuse un fork ou un autre auteur que le robot, exige ces checks sur la branche par défaut sans contournement possible, respecte brouillon et « garder-ouverte » ; si la fusion automatique est déjà activée et qu'un check exigé est rouge (un check en cours ne compte pas), elle le relance une fois, puis fait échouer le run du robot s'il reste rouge. Elle n'est pas appelée juste après un `gh pr update-branch` réussi dans le même run : la CI vient de repartir, et l'API peut encore donner l'ancien SHA de tête, dont le build vient d'être annulé par la concurrence de `devcontainer.yml` ; la garde le relancerait pour rien (log explicite, le passage suivant vérifie la PR).
- Le `sha` tagué est celui de l'événement (`github.sha`), pas `main` au moment de l'exécution.

## Laissé au constructeur

- Le découpage exact du script (fonctions, options) et la forme des messages, dans le style de `suivre-paquet.yml`.
- La factorisation éventuelle des garde-fous de fusion automatique avec `suivre-paquet.yml` (copie acceptable si la factorisation complique). Faite depuis : la garde commune (PR [#49](https://github.com/steamicc/arduino-steami-devcontainer/pull/49)), branchée ici par l'issue [#54](https://github.com/steamicc/arduino-steami-devcontainer/issues/54).
