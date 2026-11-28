# Publier l'image automatiquement — conception

Issue : [#33](https://github.com/steamicc/arduino-steami-devcontainer/issues/33). Date : 2026-11-28. Approche validée par l'utilisateur le 2026-11-28 (« Allons-y ») ; conception courte.

## Intention

Après la fusion d'un changement de l'image, il faut aujourd'hui trois gestes manuels : une PR « chore: image AAAA.MM.N » qui change les deux `devcontainer.json`, sa fusion, puis le push du tag `devcontainer-AAAA.MM.N` (CONTRIBUTING.md, « Publier une nouvelle image »). Le modèle `arduino-steami-starter` suit déjà seul (robot `suivre-image`, PR #14 du modèle). Le but : qu'un changement fusionné arrive jusqu'aux élèves sans geste manuel, toujours à travers la CI.

## Objectifs

- Un robot `publier-image` (workflow `.github/workflows/publier-image.yml`) qui, à chaque push sur `main` :
  1. **pose le tag** `devcontainer-V` sur le commit poussé quand les deux `devcontainer.json` y citent une version `V` qui n'a pas encore de tag (cas de la PR « chore: image V » qui vient d'être fusionnée, par le robot ou à la main) ;
  2. sinon, **ouvre la PR** « chore: image V » quand `.devcontainer/source/` a changé depuis le dernier tag `devcontainer-*`, avec la fusion automatique (squash), comme `suivre-paquet.yml`.
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
- Affaiblir un ruleset ou donner au robot plus que Contents et Pull requests en écriture sur ce dépôt.

## Contraintes

- Rulesets de `main` : `Default_Ruleset` (organisation : PR obligatoire, squash ou rebase, historique linéaire ; l'App `semantic-release-updater`, id 1055123, a une exception) et « CI verte avant fusion » (dépôt : checks obligatoires, sans exception). Les tags ne sont soumis à aucun ruleset.
- Secrets `RELEASE_APP_ID` / `RELEASE_APP_SECRET` au niveau de l'organisation ; l'App est installée sur tous les dépôts.
- Le contexte de construction de l'image est `.devcontainer/source/` (`.devcontainer/source/devcontainer.json`) : c'est le seul chemin qui change le contenu de l'image.
- Les tests du dépôt tournent avec `bats tests/`, `python3 -m unittest`, `node --test` (CONTRIBUTING.md, job « tests des commandes »).
- Conventions : messages et commentaires en français, Conventional Commits, actions épinglées par SHA, neutralisé dans les forks (`if: github.repository == …`).

## Approches

1. **Robot en deux temps, PR puis tag** (choisie) : chaque étape passe par la CI et les rulesets sans exception ; garde `AAAA.MM.N`.
2. **semantic-release** : notes de release en plus, mais versions semver (un `feat` donnerait 2026.12.0) et commit de version poussé sur `main` à travers « CI verte avant fusion » (exception à ajouter). Écartée.
3. **Tag direct à chaque fusion, sans PR** : le tag pointerait sur un commit dont les `devcontainer.json` citent l'ancienne version. Écartée.

## Conception

- **Script** `.github/scripts/publier-image.sh` (bash), testé par `tests/publier-image.bats` sur des dépôts git temporaires. Il lit l'état du dépôt (tags, contenu des deux `devcontainer.json` au commit donné, `git diff` de `.devcontainer/source/`) et une date `AAAA.MM` passée en argument, et écrit sur la sortie la décision : `tag V`, `pr V`, ou `rien <raison>`. Il ne touche à rien (ni push, ni réseau).
  - `tag V` : les deux fichiers citent la même `V` au format `AAAA.MM.N`, et `devcontainer-V` n'existe pas.
  - Les deux fichiers citent des versions différentes : erreur (code non nul), à corriger à la main.
  - `pr V` : `devcontainer-V` existe déjà pour la version citée, `git diff --quiet <dernier tag> <commit> -- .devcontainer/source` signale un changement, et `V` = version suivante calculée.
  - `rien` sinon (aucun changement de l'image).
  - Dernier tag : le plus grand `devcontainer-*` au format `AAAA.MM.N`, trié par `sort -V`.
- **Workflow** `publier-image.yml` : `on: push: branches: [main]` et `workflow_dispatch` ; `concurrency: publier-image` ; permissions en lecture ; même vérification des secrets et même jeton d'App que `suivre-paquet.yml` (Contents et Pull requests en écriture, ce dépôt seulement) ; `actions/checkout` avec `fetch-depth: 0` et les tags.
  - `tag V` : vérifier que `ghcr.io/…:V` n'existe pas (`docker manifest inspect`, même règle que `devcontainer-publish`), puis `git tag devcontainer-V <sha du push>` et `git push origin devcontainer-V` avec le jeton de l'App.
  - `pr V` : si une PR ouverte du robot `chore/image-*` existe déjà, seulement vérifier sa fusion automatique ; si la branche `chore/image-V` ou une PR de ce nom existe (même fermée), ne rien faire ; sinon créer la branche, remplacer la version dans les deux fichiers, committer (auteur : le bot de l'App) « chore: image V », ouvrir la PR (corps : la liste `git log --oneline` des commits de `.devcontainer/source/` depuis le dernier tag) et activer la fusion automatique avec les mêmes garde-fous que `suivre-paquet` (brouillon, étiquette « garder-ouverte », ruleset absent).
- Le `sha` tagué est celui de l'événement (`github.sha`), pas `main` au moment de l'exécution.

## Laissé au constructeur

- Le découpage exact du script (fonctions, options) et la forme des messages, dans le style de `suivre-paquet.yml`.
- La factorisation éventuelle des garde-fous de fusion automatique avec `suivre-paquet.yml` (copie acceptable si la factorisation complique).
