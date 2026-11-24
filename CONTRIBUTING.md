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

Le smoke-test vérifie PlatformIO 6.1.19, les drivers au tag `v0.24.0`, la compilation du projet d'amorçage et des exemples de référence (`lis2mdl/BasicReader`, `ble/BleBeacon`), le tout **sans réseau**. La première construction télécharge la plateforme, le framework et la toolchain, donc elle est longue. Les tests bats existent aussi dans l'image (`bats` y est installé).

Le workflow `devcontainer.yml` fait la même chose à chaque PR et à chaque push sur `main`. Il est désactivé dans les forks.

## Versions figées

Toutes les versions sont exactes, jamais une plage : PlatformIO `6.1.19`, plateforme `ststm32@19.7.1`, framework `platformio/framework-arduinoststm32@4.21200.0`, STM32duinoBLE `1.5.0`, `arduino-steami-lib` au tag `v0.24.0`, DAP.js `2.3.0` (copie embarquée, sans CDN). Changer l'une d'elles, c'est publier une nouvelle image.

## Publier une nouvelle image

Une version publiée n'est jamais écrasée ni remplacée : les dépôts d'élèves déjà créés pointent dessus. Jamais de tag `latest`.

1. Fusionner les changements sur `main`, `devcontainer.yml` au vert.
2. Choisir la version `AAAA.MM.N` (par exemple `2026.11.2`) et la mettre dans `.devcontainer/devcontainer.json` et `exemples/devcontainer.json`.
3. Pousser le tag : `git tag devcontainer-2026.11.2 && git push origin devcontainer-2026.11.2`. Le workflow `devcontainer-publish` peut aussi être lancé à la main (Actions, « Run workflow ») une fois présent sur la branche par défaut.
4. Vérifier que le job est vert, **y compris l'étape « Post Build, smoke-test & publish »** : c'est elle qui pousse l'image sur ghcr.io, seulement si le smoke-test a réussi.
5. À la première publication seulement, rendre le paquet **public** (Packages, Package settings, Change visibility), faute de quoi les élèves ne peuvent pas le télécharger. Vérifier sans être connecté : `docker pull ghcr.io/steamicc/arduino-steami-devcontainer:2026.11.2`.
6. Dans le dépôt modèle `steamicc/arduino-steami-starter`, mettre la nouvelle version dans `.devcontainer/devcontainer.json`. Les dépôts d'élèves déjà créés gardent l'ancienne.

Le résumé du job rappelle ces étapes et signale les configurations qui ne pointent pas encore sur la nouvelle version.

## Mettre à jour les drivers

1. Dans `.devcontainer/source/Dockerfile`, changer le tag de `arduino-steami-lib` (`--branch vX.Y.Z` et la vérification `describe --tags`), et la même valeur dans `.devcontainer/smoke-test.sh`.
2. Si la plateforme, le framework ou STM32duinoBLE changent, les mettre à jour dans `.devcontainer/source/amorcage/platformio.ini` et le Dockerfile, à l'exacte.
3. Lancer les tests et le smoke-test en local, puis publier une nouvelle image (section précédente).

**À rétablir quand un tag corrige les deux exemples.** `lis2mdl/DigitalCompass` et `ble/BleHotCold` ne compilent pas avec `v0.24.0` : le README, la documentation du wiki et le dépôt modèle ne doivent pas les citer tant que l'image utilise ce tag. Quand le tag des drivers les corrige :

- vérifier que les deux se compilent avec `steami-compiler lis2mdl/DigitalCompass` et `steami-compiler ble/BleHotCold`, dans l'image construite ;
- les ajouter au smoke-test ;
- les rétablir dans la documentation (README, wiki, dépôt modèle).
