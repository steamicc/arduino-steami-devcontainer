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

Le smoke-test vérifie PlatformIO 6.1.19, le paquet STeaMi au tag de l'`ARG STEAMI_PAQUET` du Dockerfile (tag et `version=` de `library.properties`), la compilation du projet d'amorçage et des exemples `LIS2MDL/BasicReader`, `LIS2MDL/DigitalCompass` et `BLE/BleHotCold`, et `steami-compiler lis2mdl/basicreader`, le tout **sans réseau**, puis zsh comme shell de connexion et l'historique conservé dans `/workspaces` (simulé avec `STEAMI_WORKSPACES`). Le serveur SSH est une feature de `source/devcontainer.json` : seul l'outillage devcontainer (CI) l'applique, `docker build` et le smoke-test ne la voient pas. La première construction télécharge la plateforme, le framework et la toolchain, donc elle est longue. Les tests bats existent aussi dans l'image (`bats` y est installé).

Le workflow `devcontainer.yml` fait la même chose à chaque PR et à chaque push sur `main`. Il est désactivé dans les forks.

## Versions figées

Toutes les versions sont exactes, jamais une plage : PlatformIO `6.1.19`, plateforme `ststm32@20.0.0`, framework `platformio/framework-arduinoststm32@4.30100.0` (STM32duino 3.1.0, comme l'Arduino IDE), STM32duinoBLE `1.5.0`, le paquet Arduino STeaMi (`steamicc/arduino-steami`) au tag `ARG STEAMI_PAQUET` du Dockerfile, le firmware DAPLink de la carte (`steamicc/DAPLink`, release `AAAA-MM-JJ.N`, embarqué dans l'image) à la release `ARG STEAMI_DAPLINK_RELEASE` du Dockerfile, avec son SHA256 `ARG STEAMI_DAPLINK_SHA256`, DAP.js `2.3.0` (copie embarquée, sans CDN). Changer l'une d'elles, c'est publier une nouvelle image.

## Publier une nouvelle image

Une version publiée n'est jamais écrasée ni remplacée : les dépôts d'élèves déjà créés pointent dessus. Jamais de tag `latest`.

1. Fusionner les changements sur `main`, `devcontainer.yml` au vert.
2. Choisir la version `AAAA.MM.N` (une version publiée ne change plus et ne se réutilise jamais : prendre la suivante) et la mettre dans `.devcontainer/devcontainer.json` et `exemples/devcontainer.json`.
3. Pousser le tag : `git tag devcontainer-AAAA.MM.N && git push origin devcontainer-AAAA.MM.N`. Le workflow `devcontainer-publish` peut aussi être lancé à la main (Actions, « Run workflow ») une fois présent sur la branche par défaut.
4. Vérifier que le job est vert, **y compris l'étape « Post Build, smoke-test & publish »** : c'est elle qui pousse l'image sur ghcr.io, seulement si le smoke-test a réussi.
5. À la première publication seulement, rendre le paquet **public** (Packages, Package settings, Change visibility), faute de quoi les élèves ne peuvent pas le télécharger. Vérifier sans être connecté : `docker pull ghcr.io/steamicc/arduino-steami-devcontainer:AAAA.MM.N`.
6. Dans le dépôt modèle `steamicc/arduino-steami-starter`, mettre la nouvelle version dans `.devcontainer/devcontainer.json`. Les dépôts d'élèves déjà créés gardent l'ancienne.

Le résumé du job rappelle ces étapes et signale les configurations qui ne pointent pas encore sur la nouvelle version.

## Mettre à jour le firmware DAPLink

Le firmware DAPLink proposé par la page « Téléverser » est téléchargé à la construction de l'image (`stm32f103xb_steami32_if_crc.bin` de la release `steamicc/DAPLink`), vérifié par SHA256 et copié dans `/opt/steami/flasher/daplink/` avec un `firmware.json` (release, numéro, taille, SHA256). Il est fixé par `ARG STEAMI_DAPLINK_RELEASE` et `ARG STEAMI_DAPLINK_SHA256` dans `.devcontainer/source/Dockerfile` (seule source : le smoke-test les lit). Pour le changer, mettre dans les deux `ARG` une release plus récente `AAAA-MM-JJ.N` et le SHA256 de son fichier (`curl -fsSL <url> | sha256sum`), puis construire l'image, lancer le smoke-test, choisir la version d'image suivante et la publier comme ci-dessus.

## Mettre à jour le paquet des drivers

Les drivers viennent du paquet Arduino « STeaMi » (`steamicc/arduino-steami`), le même que celui de l'Arduino IDE, cloné au tag fixé par `ARG STEAMI_PAQUET` dans `.devcontainer/source/Dockerfile` (seule source du tag : le smoke-test et le workflow le lisent). La définition de la carte n'est pas dans le paquet : elle est copiée dans `.devcontainer/source/boards/steami.json` (copiée depuis `boards/steami.json` d'`arduino-steami-lib` v0.30.0 ; la mise à jour automatique ne change que l'`ARG`, donc elle n'est pas rafraîchie toute seule).

**Mise à jour automatique.** Le workflow `suivre-paquet.yml` tourne une fois par jour (et à la demande, Actions, « Run workflow »). Quand `steamicc/arduino-steami` publie une release plus récente que l'`ARG`, il ouvre la PR « chore: paquet arduino-steami vX.Y.Z » sur la branche `chore/paquet-vX.Y.Z` (une seule fois par release : s'il existe déjà une branche ou une PR de ce nom, même fermée, il ne fait rien) et lance `devcontainer.yml` sur cette branche, car une PR créée avec `GITHUB_TOKEN` ne déclenche pas les workflows `pull_request`. Il reste à faire :

1. attendre que `devcontainer.yml` soit au vert sur la branche, puis comparer `.devcontainer/source/boards/steami.json` avec celui d'`arduino-steami-lib` au nouveau tag (`gh api repos/steamicc/arduino-steami-lib/contents/boards/steami.json?ref=vX.Y.Z --jq .content | base64 -d | diff - .devcontainer/source/boards/steami.json`) et reporter les différences ; enfin fusionner la PR ;
2. choisir la version `AAAA.MM.N` suivante, la mettre dans `.devcontainer/devcontainer.json` et `exemples/devcontainer.json`, puis publier l'image (section précédente) ;
3. mettre à jour le modèle `steamicc/arduino-steami-starter` avec la nouvelle version de l'image.

**Prérequis, à régler une fois.** L'organisation (ou le dépôt) doit autoriser « Allow GitHub Actions to create and approve pull requests » (Settings, Actions, General, Workflow permissions), sinon l'étape qui ouvre la PR échoue.

**À la main.** Changer `ARG STEAMI_PAQUET=vX.Y.Z` dans le Dockerfile, puis, si le paquet change de plateforme, de framework ou de dépendance, mettre à jour `.devcontainer/source/amorcage/platformio.ini` et le Dockerfile, à l'exacte. Compiler chaque exemple listé par `steami-exemples` dans l'image construite, puis lancer les tests et le smoke-test en local avant de publier.
