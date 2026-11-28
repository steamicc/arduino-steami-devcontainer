# Robot publier-image — plan de réalisation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** qu'un changement de `.devcontainer/source/` fusionné sur `main` soit publié sans geste manuel : PR « chore: image AAAA.MM.N » en fusion automatique, puis tag `devcontainer-AAAA.MM.N` poussé par l'App.

**Architecture:** un script bash pur (`.github/scripts/publier-image.sh`) décide quoi faire à partir de l'état git (tag, PR ou rien) et sait réécrire la version des deux `devcontainer.json` ; il est testé par bats. Un workflow `publier-image.yml` (push sur `main`, `workflow_dispatch`) l'appelle puis agit avec le jeton de l'App, sur le modèle de `suivre-paquet.yml`.

**Tech Stack:** bash, git, bats, GitHub Actions, `gh`, `actions/create-github-app-token`.

**Spec:** `docs/superpowers/specs/2026-11-28-publier-image-design.md` (issue [#33](https://github.com/steamicc/arduino-steami-devcontainer/issues/33)).

## Global Constraints

- Version au format `AAAA.MM.N` (regex `^[0-9]{4}\.[0-9]{2}\.[0-9]+$`), tag `devcontainer-AAAA.MM.N`, image `ghcr.io/steamicc/arduino-steami-devcontainer`.
- Fichiers qui citent la version : `.devcontainer/devcontainer.json` et `exemples/devcontainer.json` (ligne `"image": "ghcr.io/steamicc/arduino-steami-devcontainer:<V>",`).
- Seul chemin qui change l'image : `.devcontainer/source/`.
- `AAAA.MM` = mois courant UTC ; `N` = 1 + plus grand `N` des tags du mois, sinon 1 ; jamais une version inférieure ou égale au dernier tag (si le mois courant est antérieur au mois du dernier tag, garder le mois du dernier tag).
- Écritures (push de branche, tag, PR, fusion auto) avec le jeton de l'App (`secrets.RELEASE_APP_ID` / `RELEASE_APP_SECRET`, Contents et Pull requests en écriture, ce dépôt seulement) ; `GITHUB_TOKEN` en lecture seule.
- Comme les autres workflows : `if: github.repository == 'steamicc/arduino-steami-devcontainer'`, actions épinglées par SHA (reprendre les SHA de `suivre-paquet.yml`), commentaires et messages en français.
- Commits : Conventional Commits en français, sans ligne d'attribution, sans marqueur de saut de CI, sans `!` ni BREAKING.
- Tests du dépôt : `bats tests/`, `python3 -m unittest discover -s tests -p 'test_*.py'`, `node --test tests/*.test.mjs` (tous doivent rester verts).

## Review Focus

1. Horloge ou mois en arrière (date `2026.11` alors que le dernier tag est `devcontainer-2026.12.3`) : la version proposée doit être `2026.12.4`, jamais `2026.11.x` (le robot du modèle prend le plus grand tag par `sort -V`). Test en tâche 1.
2. Tags `devcontainer-*` hors format (`devcontainer-test`, `devcontainer-2026.11`) : ignorés pour le dernier tag et pour `N`. Test en tâche 1.
3. Tri numérique : `2026.11.10` est après `2026.11.9`. Test en tâche 1.
4. Une PR d'image du robot déjà ouverte quand un autre changement de l'image est fusionné : pas de seconde PR, seulement vérifier sa fusion automatique (sa version reste valable). Revue de la tâche 2.
5. Version citée sans tag mais déjà présente sur ghcr.io : ne pas taguer, erreur explicite. Revue de la tâche 2.

---

### Task 1: script de décision et de réécriture, avec ses tests

**Files:**
- Create: `.github/scripts/publier-image.sh` (exécutable, `set -euo pipefail`)
- Test: `tests/publier-image.bats`

**Interfaces:**
- Produces :
  - `publier-image.sh decider <commit> <AAAA.MM>` lancé à la racine d'un dépôt git ; écrit une seule ligne sur stdout et sort avec 0 :
    - `tag <V>` : les deux fichiers citent la même `<V>` au commit, et le tag `devcontainer-<V>` n'existe pas ;
    - `pr <V>` : le tag de la version citée existe, `.devcontainer/source/` diffère entre le dernier tag valide et `<commit>` ; `<V>` = version suivante ;
    - `rien <raison en français>` sinon.
    - Sortie 2 avec un message sur stderr si les deux fichiers citent des versions différentes, si une version citée ou `<AAAA.MM>` est hors format, ou si un fichier ne cite aucune version.
  - `publier-image.sh remplacer <V>` : remplace la version dans les deux fichiers du répertoire courant (et rien d'autre) ; sortie 2 si `<V>` est hors format ou si un fichier ne contient pas la ligne attendue.
- Le script ne fait ni push, ni réseau, ni commit.

- [ ] **Step 1: Écrire les tests** dans `tests/publier-image.bats`, dans le style de `tests/sauver.bats` (dépôt temporaire dans `setup`, identités git exportées, `teardown` qui supprime). Une fonction d'aide crée les deux fichiers avec une version donnée et un fichier `.devcontainer/source/Dockerfile`. Tests (nom → assertion) :
  - `decider : version citée sans tag → tag` : fichiers en `2026.11.12`, tag `devcontainer-2026.11.11` sur un commit antérieur → sortie `tag 2026.11.12`.
  - `decider : source modifiée depuis le dernier tag → pr` : tag `devcontainer-2026.11.12` sur le commit qui cite `2026.11.12`, puis commit qui modifie `.devcontainer/source/Dockerfile` ; `decider HEAD 2026.11` → `pr 2026.11.13`.
  - `decider : nouveau mois → N repart à 1` : même état, `decider HEAD 2026.12` → `pr 2026.12.1`.
  - `decider : mois en arrière → garde le mois du dernier tag` : dernier tag `devcontainer-2026.12.3` cité et tagué, changement de source, `decider HEAD 2026.11` → `pr 2026.12.4`.
  - `decider : tri numérique des tags` : tags `devcontainer-2026.11.9` et `devcontainer-2026.11.10` (ce dernier cité), changement de source → `pr 2026.11.11`.
  - `decider : tags hors format ignorés` : en plus de l'état du test « pr », tags `devcontainer-test` et `devcontainer-2026.11` sur HEAD → toujours `pr 2026.11.13`.
  - `decider : changement hors de .devcontainer/source → rien` : changement de `README.md` après le tag → sortie qui commence par `rien `.
  - `decider : aucun changement → rien` : HEAD = commit tagué → sortie qui commence par `rien `.
  - `decider : versions différentes → erreur` : `.devcontainer/devcontainer.json` en `2026.11.12`, `exemples/devcontainer.json` en `2026.11.11` → statut 2, stderr cite les deux versions.
  - `decider : date hors format → erreur` : `decider HEAD 2026-11` → statut 2.
  - `remplacer : met la version dans les deux fichiers` : `remplacer 2026.11.13` → les deux fichiers contiennent `arduino-steami-devcontainer:2026.11.13"`, plus `2026.11.12`, et `git diff --stat` ne touche que ces deux fichiers.
  - `remplacer : version hors format → erreur` : `remplacer 2026.11` → statut 2, fichiers inchangés.

- [ ] **Step 2: Vérifier que les tests échouent** — `bats tests/publier-image.bats` : échecs (script absent).

- [ ] **Step 3: Écrire `.github/scripts/publier-image.sh`** selon les interfaces. Versions lues avec `git show <commit>:<fichier>` ; tags listés avec `git tag -l 'devcontainer-*'`, filtrés par la regex, triés par `sort -V` ; changement détecté avec `git diff --quiet <dernier tag> <commit> -- .devcontainer/source`. En-tête de commentaire : rôle, usage, et renvoi vers `publier-image.yml`.

- [ ] **Step 4: Vérifier** — `bats tests/publier-image.bats` : tout passe ; `bats tests/` : tout passe ; `shellcheck .github/scripts/publier-image.sh` s'il est installé : aucun avertissement.

- [ ] **Step 5: Commit** — `ci(publier-image): script de décision et de version de l'image` (corps : `Refs #33`).

### Task 2: workflow `publier-image.yml`

**Files:**
- Create: `.github/workflows/publier-image.yml`

**Interfaces:**
- Consumes : `publier-image.sh decider <sha> <AAAA.MM>` et `publier-image.sh remplacer <V>` (tâche 1).

- [ ] **Step 1: Écrire le workflow**, sur le modèle de `suivre-paquet.yml` (en-tête de commentaire, vérification des secrets, jeton d'App, explication de l'échec du jeton, identité git du bot, garde-fous de fusion automatique : brouillon, étiquette `garder-ouverte`, ruleset sans les checks « tests des commandes » et « build & smoke-test ») :
  - `on: push: branches: [main]` et `workflow_dispatch` ; `permissions: contents: read, pull-requests: read` ; `concurrency: { group: publier-image, cancel-in-progress: false }`.
  - `actions/checkout` (jeton de l'App, `fetch-depth: 0`, `fetch-tags: true`).
  - Étape « Décide » : `decision=$(.github/scripts/publier-image.sh decider "$GITHUB_SHA" "$(date -u +%Y.%m)")`, sorties `action` (`tag`, `pr` ou vide) et `version`.
  - `tag` : vérifier avec `docker manifest inspect` que `ghcr.io/steamicc/arduino-steami-devcontainer:<V>` n'existe pas (même règle à trois issues que `devcontainer-publish.yml` : existe → erreur ; « manifest unknown|name unknown » → continuer ; autre → erreur) ; puis `git tag "devcontainer-<V>" "$GITHUB_SHA"` et `git push origin "devcontainer-<V>"` ; résumé dans `$GITHUB_STEP_SUMMARY` avec le lien vers le run de `devcontainer-publish`.
  - `pr` : chercher une PR ouverte dont la branche commence par `chore/image-`, de ce dépôt, ouverte par `app/<slug>` ; si elle existe, seulement vérifier sa fusion automatique. Sinon, si la branche `chore/image-<V>` ou une PR de ce nom (même fermée) existe, ne rien faire. Sinon : créer `chore/image-<V>` depuis `$GITHUB_SHA`, `publier-image.sh remplacer <V>`, commit `chore: image <V>` (auteur : bot de l'App), push, PR « chore: image <V> » (corps : ce que publie la PR = `git log --oneline <dernier tag>..$GITHUB_SHA -- .devcontainer/source`, et la suite automatique : tag par ce robot à la fusion, publication par `devcontainer-publish`, PR du modèle par son robot `suivre-image`), puis fusion automatique squash.

- [ ] **Step 2: Vérifier** — `actionlint .github/workflows/publier-image.yml` s'il est installé (sinon `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/publier-image.yml`) ; `shellcheck` sur les blocs `run` si actionlint n'est pas disponible n'est pas exigé ; `bats tests/` reste vert.

- [ ] **Step 3: Commit** — `ci(publier-image): ouvrir la PR d'image puis poser le tag avec l'App` (corps : `Refs #33`).

### Task 3: documentation et robot du paquet

**Files:**
- Modify: `CONTRIBUTING.md` (« Publier une nouvelle image », « Mettre à jour le paquet des drivers » : liste « Il reste à faire, une fois la PR fusionnée »)
- Modify: `.github/workflows/devcontainer-publish.yml` (en-tête : « Déclencheurs, tous deux manuels »)
- Modify: `.github/workflows/suivre-paquet.yml` (en-tête lignes 12-14 et corps de la PR, « La suite, à la main… »)

- [ ] **Step 1: Mettre à jour les textes** : la publication est automatique (PR « chore: image » par `publier-image`, fusion automatique, tag par le robot, publication, puis PR du modèle par son robot) ; garder la procédure manuelle comme secours (PR de version à la main : le robot pose le tag à sa fusion ; ou tag à la main) ; prérequis identiques à `suivre-paquet` (secrets, App, ruleset). Le corps de PR de `suivre-paquet` annonce la suite automatique au lieu des deux étapes manuelles.

- [ ] **Step 2: Vérifier** — `bats tests/` vert ; `git grep -n "à la main" -- CONTRIBUTING.md .github/workflows` ne décrit plus le tag comme seule voie.

- [ ] **Step 3: Commit** — `docs: publication automatique de l'image` (corps : `Closes #33`).
