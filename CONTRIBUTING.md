# Contribuer

Tout ce qui fabrique l'image est dans `.devcontainer/source/`, qui est aussi le contexte de construction, en local, en CI et à la publication.

## Lancer les tests

Les tests des commandes n'ont pas besoin de l'image : ils utilisent des faux `pio` et `steami-serveur` (`tests/stubs/`). Il faut `bats` (par exemple `sudo apt-get install bats`), Python 3 et Node.

```sh
bats tests/
python3 -m unittest discover -s tests -p 'test_*.py'
node --test tests/*.test.mjs
```

## Construire l'image et lancer le smoke-test

Depuis la racine du dépôt :

```sh
docker build -t steami-devcontainer:dev .devcontainer/source
docker run --rm --network none -u vscode -v "$PWD":/work:ro -w /work \
  steami-devcontainer:dev .devcontainer/smoke-test.sh
```

Le smoke-test vérifie PlatformIO 6.1.19, le paquet STeaMi au tag de l'`ARG STEAMI_PAQUET` du Dockerfile (tag et `version=` de `library.properties`), la compilation du projet d'amorçage et des exemples `LIS2MDL/BasicReader`, `LIS2MDL/DigitalCompass` et `BLE/BleHotCold`, et `steami-compiler lis2mdl/basicreader`, le firmware DAPLink embarqué (présence, SHA256, `firmware.json`), le tout **sans réseau**, puis zsh comme shell de connexion et l'historique conservé dans `/workspaces` (simulé avec `STEAMI_WORKSPACES`). Le serveur SSH est une feature de `source/devcontainer.json` : seul l'outillage devcontainer (CI) l'applique, `docker build` et le smoke-test ne la voient pas. La première construction télécharge la plateforme, le framework et la toolchain, donc elle est longue. Les tests bats existent aussi dans l'image (`bats` y est installé).

Le workflow `devcontainer.yml` fait la même chose à chaque PR et à chaque push sur `main`. Il est désactivé dans les forks.

## Versions figées

Toutes les versions sont exactes, jamais une plage : PlatformIO `6.1.19`, plateforme `ststm32@20.0.0`, framework `platformio/framework-arduinoststm32@4.30100.0` (STM32duino 3.1.0, comme l'Arduino IDE), STM32duinoBLE `1.5.0`, le paquet Arduino STeaMi (`steamicc/arduino-steami`) au tag `ARG STEAMI_PAQUET` du Dockerfile, le firmware DAPLink de la carte (`steamicc/DAPLink`, release `AAAA-MM-JJ.N`, embarqué dans l'image) à la release `ARG STEAMI_DAPLINK_RELEASE` du Dockerfile, avec son SHA256 `ARG STEAMI_DAPLINK_SHA256`, DAP.js `2.3.0` (copie embarquée, sans CDN). Changer l'une d'elles, c'est publier une nouvelle image.

## Publier une nouvelle image

Une version publiée n'est jamais écrasée ni remplacée : les dépôts d'élèves déjà créés pointent dessus. Jamais de tag `latest`.

1. Fusionner les changements sur `main`, `devcontainer.yml` au vert.
2. Le tag est posé tout seul. À chaque push sur `main`, le workflow `tag-image.yml` regarde si les entrées de l'image (tout `.devcontainer/source/`, dont le Dockerfile, et `.devcontainer/smoke-test.sh`) ont changé depuis le dernier tag `devcontainer-*`. Si oui, il calcule la version `AAAA.MM.N` suivante à partir des tags existants (`N+1` dans le mois courant, sinon `1` : une version publiée ne change plus et ne se réutilise jamais) et pousse le tag `devcontainer-AAAA.MM.N` avec le jeton de l'App, ce qui lance `devcontainer-publish`. Une fusion qui ne touche que la documentation, les tests, les robots ou les `devcontainer.json` ne pose pas de tag. La version posée apparaît dans la notice du run `tag-image`.
3. En réparation seulement (tag non posé, publication ratée) : lancer `devcontainer-publish` à la main (Actions, « Run workflow ») avec la version, ou pousser soi-même le tag suivant (`git tag devcontainer-AAAA.MM.N && git push origin devcontainer-AAAA.MM.N`), jamais un tag existant.
4. Vérifier que le job est vert, **y compris l'étape « Post Build, smoke-test & publish »** : c'est elle qui pousse l'image sur ghcr.io, seulement si le smoke-test a réussi.
5. À la première publication seulement, rendre le paquet **public** (Packages, Package settings, Change visibility), faute de quoi les élèves ne peuvent pas le télécharger. Vérifier sans être connecté : `docker pull ghcr.io/steamicc/arduino-steami-devcontainer:AAAA.MM.N`.
6. Une fois l'image publiée, mettre sa version dans `.devcontainer/devcontainer.json` et `exemples/devcontainer.json` (cette PR ne touche aucune entrée de l'image : elle ne pose pas de nouveau tag), puis, dans le dépôt modèle `steamicc/arduino-steami-starter`, dans `.devcontainer/devcontainer.json`. Les dépôts d'élèves déjà créés gardent l'ancienne.

Le résumé du job rappelle ces étapes et signale les configurations qui ne pointent pas encore sur la nouvelle version.

## Mettre à jour le firmware DAPLink

Le firmware DAPLink proposé par la page « Téléverser » est téléchargé à la construction de l'image (`stm32f103xb_steami32_if_crc.bin` de la release `steamicc/DAPLink`), vérifié par SHA256 et copié dans `/opt/steami/flasher/daplink/` avec un `firmware.json` (release, numéro, date `AAAAMMJJ`, taille, SHA256). Il est fixé par `ARG STEAMI_DAPLINK_RELEASE` et `ARG STEAMI_DAPLINK_SHA256` dans `.devcontainer/source/Dockerfile` (seule source : le smoke-test les lit). Pour le changer, mettre dans les deux `ARG` une release plus récente `AAAA-MM-JJ.N` et le SHA256 de son fichier (`curl -fsSL <url> | sha256sum`), puis construire l'image, lancer le smoke-test et fusionner : la version d'image suivante est taguée et publiée comme ci-dessus. La page compare les releases par date puis par numéro (le `run_number` de GitHub peut repartir de 1) : la date de la nouvelle release doit donc être postérieure ou égale à celle de la précédente.

## Mettre à jour le paquet des drivers

Les drivers viennent du paquet Arduino « STeaMi » (`steamicc/arduino-steami`), le même que celui de l'Arduino IDE, cloné au tag fixé par `ARG STEAMI_PAQUET` dans `.devcontainer/source/Dockerfile` (seule source du tag : le smoke-test et le workflow le lisent). La définition de la carte n'est pas dans le paquet : elle est copiée dans `.devcontainer/source/boards/steami.json` (copiée depuis `boards/steami.json` d'`arduino-steami-lib` v0.30.0, identique jusqu'en v0.34.0 ; la mise à jour automatique ne change que l'`ARG`, donc elle n'est pas rafraîchie toute seule).

**Mise à jour automatique.** Le workflow `suivre-paquet.yml` tourne une fois par jour (et à la demande, Actions, « Run workflow »). Quand `steamicc/arduino-steami` publie une release plus récente que l'`ARG`, il ouvre la PR « chore: paquet arduino-steami vX.Y.Z » sur la branche `chore/paquet-vX.Y.Z` (une seule fois par release : s'il existe déjà une branche ou une PR de ce nom, même fermée, il ne fait rien, sauf vérifier la fusion automatique de sa propre PR encore ouverte). Il agit avec le jeton de l'App de l'organisation : `devcontainer.yml` se déclenche sur la PR sans approbation manuelle. Il compare aussi `.devcontainer/source/boards/steami.json` avec celui d'`arduino-steami-lib` au nouveau tag ; s'ils sont identiques, il active la fusion automatique (squash) et la PR est fusionnée dès que `devcontainer.yml` est au vert. Sinon, il le signale dans la PR : reporter les différences (`gh api "repos/steamicc/arduino-steami-lib/contents/boards/steami.json?ref=vX.Y.Z" --jq .content | base64 -d | diff - .devcontainer/source/boards/steami.json`) dans la PR : pour une PR déjà ouverte, il compare la copie de sa branche, donc le passage suivant active la fusion automatique (ou fusionner à la main). Pour garder la PR ouverte, la passer en brouillon ou lui mettre l'étiquette « garder-ouverte » : il ne réactive plus sa fusion automatique. À la fusion, `tag-image.yml` pose le tag `devcontainer-AAAA.MM.N` suivant (la PR change le Dockerfile, une entrée de l'image) et `devcontainer-publish` publie l'image (« Publier une nouvelle image »). Il reste à faire, une fois l'image publiée :

1. mettre sa version dans `.devcontainer/devcontainer.json` et `exemples/devcontainer.json` ;
2. mettre à jour le modèle `steamicc/arduino-steami-starter` avec la nouvelle version de l'image.

**Prérequis, à régler une fois.**

- Les secrets `RELEASE_APP_ID` et `RELEASE_APP_SECRET` (ceux d'`arduino-steami-lib`, dans le dépôt ou l'organisation) et l'App correspondante installée sur ce dépôt, avec Contents et Pull requests en écriture (et Workflows en écriture pour `tag-image.yml`). Sans les secrets, le workflow échoue en nommant ceux qui manquent.
- « Allow auto-merge » et « Allow squash merging » activés (Settings, General, Pull Requests).
- Un ruleset « CI verte avant fusion » sur `main` qui exige les checks « tests des commandes » et « build & smoke-test » (Settings, Rules, Rulesets, « Require status checks to pass »). Sans lui, la fusion automatique fusionnerait même une CI rouge : le workflow ne l'active pas, le signale par un avertissement et laisse la PR à fusionner à la main.

**À la main.** Changer `ARG STEAMI_PAQUET=vX.Y.Z` dans le Dockerfile, puis, si le paquet change de plateforme, de framework ou de dépendance, mettre à jour `.devcontainer/source/amorcage/platformio.ini` et le Dockerfile, à l'exacte. Compiler chaque exemple listé par `steami-exemples` dans l'image construite, puis lancer les tests et le smoke-test en local avant de publier.
