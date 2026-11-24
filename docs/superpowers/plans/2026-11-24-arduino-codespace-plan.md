# Codespace Arduino STeaMi — plan de réalisation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** compiler et téléverser des programmes Arduino STeaMi depuis un GitHub Codespace, sans rien installer, et documenter la démarche dans le wiki.

**Architecture :** un dépôt d'image `steamicc/arduino-steami-devcontainer` publie sur ghcr.io une image versionnée. Elle contient PlatformIO, la toolchain STM32, les drivers STeaMi, des commandes `steami-*` et une page « Téléverser » (WebUSB + DAP.js). Un dépôt template `steamicc/arduino-steami-starter` ne contient que la configuration distribuée qui télécharge cette image, un programme d'exemple et un `platformio.ini`. Le wiki explique le parcours. Le modèle est `IUTInfoAix-R510/devcontainer`.

**Tech Stack :** Dev Containers / Codespaces, Docker, PlatformIO 6.1.19, Bash (+ bats-core pour les tests), Python 3 (serveur, `unittest`), HTML/JS sans framework + DAP.js 2.3.0 (tests `node --test`), GitHub Actions, Docusaurus (wiki).

**Spec :** `2026-11-24-arduino-codespace-design.md` (même dossier ; copié dans `docs/superpowers/specs/` du dépôt d'image à la tâche 1).

## Global Constraints

- Versions exactes, jamais de plage :
  - PlatformIO `6.1.19` ;
  - plateforme `ststm32@19.7.1` ;
  - `platformio/framework-arduinoststm32@4.21200.0` ;
  - STM32duinoBLE `1.5.0` ;
  - `arduino-steami-lib` au tag `v0.24.0` ;
  - DAP.js `2.3.0`, en copie embarquée, sans CDN.
- **Exemples de référence** pour les tests et la recette : `lis2mdl/BasicReader` et `ble/BleBeacon`. `lis2mdl/DigitalCompass` et `ble/BleHotCold` ne compilent pas en `v0.24.0` : il ne faut pas les citer dans le README ni dans le wiki tant que l'image n'utilise pas un tag qui les corrige.
- Image `ghcr.io/steamicc/arduino-steami-devcontainer:AAAA.MM.N` :
  - jamais de tag `latest`, jamais d'écrasement d'une version publiée ;
  - smoke-test obligatoire avant la publication ;
  - publication désactivée hors de `steamicc/arduino-steami-devcontainer` ;
  - plateforme amd64.
- **Contexte de construction de l'image : `.devcontainer/source/`, partout** (en local, en CI et à la publication). Tout ce que le Dockerfile copie se trouve dans ce dossier.
- Emplacements dans l'image :

  | Contenu                  | Emplacement                       |
  | ------------------------ | --------------------------------- |
  | drivers                  | `/opt/steami/arduino-steami-lib`  |
  | bibliothèques tierces    | `/opt/steami/libs`                |
  | page « Téléverser »      | `/opt/steami/flasher`             |
  | serveur                  | `/usr/local/lib/steami/`          |
  | commandes                | `/usr/local/bin/steami-*`         |
  | PlatformIO               | `PLATFORMIO_CORE_DIR=/opt/platformio` |

  `/opt/steami` et `/opt/platformio` appartiennent à `vscode`. PlatformIO écrit `<croquis>.ino.cpp` dans le dossier de l'exemple, et git refuse un dépôt qui appartient à un autre utilisateur.
- Variables d'environnement de l'image : `PLATFORMIO_SETTING_ENABLE_TELEMETRY=No` et `PLATFORMIO_SETTING_CHECK_PLATFORMIO_INTERVAL=36500`.
- **Compiler ne demande aucun accès réseau** : la plateforme, le framework, la toolchain et les bibliothèques sont dans l'image. Le `platformio.ini` du template n'a pas de `lib_deps`.
- Binaire servi à la page : `<racine>/.steami/firmware.bin` et `<racine>/.steami/firmware.json`, au format `{"programme": "src" | "<driver>/<Exemple>", "date": "<ISO 8601 UTC>", "taille": <octets>}`.
  - Les deux fichiers sont écrits de façon atomique (`.tmp` puis `mv`), le `.bin` en premier.
  - `.steami/` et `.pio/` sont dans le `.gitignore` du template.
- **`racine_depot`** : on remonte depuis `$PWD` jusqu'au premier dossier qui contient `platformio.ini`, sans utiliser git. Seuls `steami-sauver` et la vérification de `src/` dans `steami-copier` utilisent git.
- Page sur le port `8080` (surchargeable par `STEAMI_PORT`), libellé « Téléverser ». Fichier pid `/tmp/steami-serveur.pid` (surchargeable par `STEAMI_PID`).
- Commandes :
  - messages en français ;
  - `-h`/`--help` affiche l'aide ;
  - chaque commande affiche `→ <commande>` avant de lancer une commande git ou pio ;
  - erreurs préfixées `✗`, succès `✅`, comme `r510-sauver` ;
  - on écrit « Codespace » avec une majuscule.
- WebUSB : filtre `vendorId: 0x0D28` ; série à 115200 bauds.
- Le template ouvre une machine 2 cœurs (`hostRequirements.cpus = 2`). Le README et le wiki disent de choisir **« Create a new repository »**, pas « Open in a codespace ».
- Wiki : issue, puis branche dédiée, puis PR qui référence l'issue ; mots nouveaux dans `.cspell/steami.txt`.
- Tests bats : l'identité git (`GIT_AUTHOR_*`, `GIT_COMMITTER_*`) est exportée dans `setup`.
- Exécution des outils strictement séquentielle (règle de l'utilisateur).

## Review Focus

1. **Compilation qui échoue après une compilation réussie :** `.steami/` reste inchangé, et la page continue d'afficher le nom et la date de l'ancien programme. Testé à la tâche 2 (`echec_ne_touche_pas_au_binaire`).
2. **`steami-copier` alors que `src/` a des modifications non sauvegardées :** la commande refuse sans `--remplacer`. Testé à la tâche 2.
3. **Codespace sans dépôt lié (« Open in a codespace ») ou sans droit de push (ouvert sur `steamicc/arduino-steami-starter`) :** `steami-sauver` enregistre le travail en local et donne la bonne marche à suivre dans chacun des deux cas. Testé à la tâche 3.
4. **Page ouverte avant toute compilation, ou commande lancée depuis `src/` :** `/firmware.json` répond 404, la page affiche « Aucun programme compilé » et le bouton Téléverser reste désactivé. Le serveur sert toujours la racine. Testé aux tâches 4 et 5.
5. **Carte débranchée, carte déjà utilisée par un autre onglet, sélection annulée, accès refusé, page dans une iframe :** chaque cas a son propre message, et la page revient à l'état « non connectée ». Testé à la tâche 5 (`messageErreur`).

---

### Task 0 : essai WebUSB sur une vraie carte (point de décision)

Jetable, aucun dépôt. Il faut une STeaMi branchée en USB sur la machine de l'utilisateur, et Chrome ou Edge.

**Files :** dossier temporaire `essai-webusb/` : `index.html`, `dap.umd.js` (DAP.js 2.3.0, `dist/dap.umd.js`), `firmware.bin`.

- [ ] **Step 1 : compiler un binaire de test.** Dans `/home/nedjar/sandbox/arduino-steami-lib`, écrire un croquis qui fait clignoter `LED_GREEN` et écrit `Serial.println(millis())` toutes les 500 ms. Le compiler avec `PLATFORMIO_SRC_DIR=<dossier du croquis> .venv/bin/pio run -e steami`, puis copier `.pio/build/steami/firmware.bin`.
- [ ] **Step 2 : écrire une page minimale.**
  1. `navigator.usb.requestDevice({filters:[{vendorId:0x0D28}]})`, puis `dap = new DAPjs.DAPLink(new DAPjs.WebUSB(device))` et `await dap.connect()`.
  2. `await dap.flash(await (await fetch('firmware.bin')).arrayBuffer())`, en affichant `EVENT_PROGRESS`.
  3. `await dap.setSerialBaudrate(115200)`, puis brancher un écouteur sur `EVENT_SERIAL_DATA`.
  4. Lancer la lecture série **sans attendre la fin de la boucle** : `boucle = dap.startSerialRead(10).catch(afficherErreur)`.

  Servir la page avec `python3 -m http.server 8080` (`localhost` est un contexte sécurisé).
- [ ] **Step 3 : faire l'essai avec l'utilisateur**, sur chacune des releases dont il dispose (la V1c d'abord). Résultat attendu : la LED clignote après le téléversement et les nombres défilent dans la page.
- [ ] **Step 4 : décider de la suite.**
  - Tout fonctionne : on continue.
  - `flash()` refuse le `.bin` : refaire l'essai avec un `.hex` (`arm-none-eabi-objcopy -O ihex firmware.elf firmware.hex`). Dans ce cas, la tâche 2 publie `.steami/firmware.hex`, et le plan entier remplace `firmware.bin` par `firmware.hex`.
  - Rien ne fonctionne : **s'arrêter et revenir vers l'utilisateur.** La copie sur le lecteur reste alors la seule méthode, et la tâche 5 est abandonnée.
- [ ] **Step 5 : noter le résultat dans la spec.** Ajouter à la section « Contraintes » la release testée, la version DAPLink lue dans `DETAILS.TXT` sur le lecteur, et le format retenu (.bin ou .hex).

### Task 1 : image de base (PlatformIO, toolchain, drivers), compilation hors ligne

**Files :**
- Create (dépôt neuf `/home/nedjar/sandbox/arduino-steami-devcontainer`) :
  - `.devcontainer/source/Dockerfile` et `.devcontainer/source/devcontainer.json` ;
  - le projet d'amorçage `.devcontainer/source/amorcage/platformio.ini` et `.devcontainer/source/amorcage/src/main.cpp` ;
  - `.devcontainer/smoke-test.sh` ;
  - `docs/superpowers/specs/2026-11-24-arduino-codespace-design.md` et `docs/superpowers/plans/2026-11-24-arduino-codespace-plan.md` ;
  - `LICENSE` (même licence que `arduino-steami-lib`) et `.gitignore`.

**Interfaces :**
- Produces :
  - l'image locale `steami-devcontainer:dev` ;
  - `.devcontainer/source/amorcage/platformio.ini`, le `platformio.ini` de référence que la tâche 7 recopie :

```ini
[platformio]
boards_dir = /opt/steami/arduino-steami-lib/boards

[env:steami]
platform = ststm32@19.7.1
platform_packages = platformio/framework-arduinoststm32@4.21200.0
board = steami
framework = arduino
monitor_speed = 115200
lib_extra_dirs =
  /opt/steami/arduino-steami-lib/lib
  /opt/steami/libs
```

- [ ] **Step 1 : écrire `smoke-test.sh` (le test).** Il copie `.devcontainer/source/amorcage` dans un dossier temporaire, puis vérifie :
  - `pio --version` affiche `6.1.19` ;
  - `git -C /opt/steami/arduino-steami-lib describe --tags` affiche `v0.24.0` ;
  - `/opt/steami/arduino-steami-lib/lib/lis2mdl/examples/BasicReader` existe ;
  - la copie compile avec `pio run -e steami` ;
  - elle compile aussi `lis2mdl/BasicReader` et `ble/BleBeacon` via `PLATFORMIO_SRC_DIR`.

  Le script s'arrête au premier échec avec un message `✗`. Si `ble/BleBeacon` ne compile pas en `v0.24.0`, prendre un autre exemple `ble/` qui compile et mettre à jour Global Constraints.
- [ ] **Step 2 : vérifier que le test échoue.** `docker run --rm -v "$PWD":/w -w /w mcr.microsoft.com/devcontainers/python:3.12-bookworm .devcontainer/smoke-test.sh` doit sortir en `✗` (`pio` introuvable).
- [ ] **Step 3 : écrire le `Dockerfile`** (contexte `.devcontainer/source/`, tous les `COPY` en chemin relatif comme dans R510).
  - Base : `mcr.microsoft.com/devcontainers/python:3.12-bookworm`, épinglée par digest, avec `LABEL org.opencontainers.image.source`.
  - PlatformIO installé dans `/opt/steami/venv`, avec un lien `/usr/local/bin/pio`, plus les variables d'environnement listées dans Global Constraints.
  - Drivers : `git clone --depth 1 --branch v0.24.0`.
  - STM32duinoBLE : `pio pkg install --storage-dir /opt/steami/libs -l stm32duino/STM32duinoBLE@1.5.0`.
  - Une compilation d'amorçage de `amorcage/`, pour télécharger la plateforme, le framework et la toolchain ; supprimer ensuite son `.pio`.
  - Pour finir, `chown -R vscode:vscode /opt/steami /opt/platformio`.

  Le `devcontainer.json` source contient `build: {dockerfile: "Dockerfile", context: "."}`, `remoteUser: vscode` et `hostRequirements: {cpus: 2}`.
- [ ] **Step 4 : construire l'image et lancer le test hors ligne.** `docker build -t steami-devcontainer:dev .devcontainer/source`, puis `docker run --rm --network none -u vscode -v "$PWD":/w -w /w steami-devcontainer:dev .devcontainer/smoke-test.sh`. Attendu : code de sortie 0, sans aucun téléchargement.
- [ ] **Step 5 : commit.** `git init -b main`, `git add -A`, puis `git commit -m "feat: image de base avec PlatformIO, toolchain STM32 et drivers STeaMi"`.

### Task 2 : commandes `steami-exemples`, `steami-compiler`, `steami-copier`

**Files :**
- Create :
  - `.devcontainer/source/steami-exemples`, `.devcontainer/source/steami-compiler`, `.devcontainer/source/steami-copier` ;
  - `.devcontainer/source/steami-commun.sh` (fonctions `die`, `run`, `racine_depot`) ;
  - les tests `tests/commandes.bats` et le faux `pio` `tests/stubs/pio`.
- Modify : `.devcontainer/source/Dockerfile` (commandes copiées dans `/usr/local/bin`, `steami-commun.sh` dans `/usr/local/lib/steami/`, installation de `bats`).

**Interfaces :**
- Produces :
  - **`steami-exemples [filtre]`** : affiche `driver/Exemple`, trié, un par ligne. Le filtre est une sous-chaîne du nom du driver. Si rien ne correspond, sort en 1 avec `✗ Aucun exemple pour « <filtre> »`.
  - **`steami-compiler [driver/Exemple]`** : se place dans `racine_depot`.
    - Sans argument, compile `src/`.
    - Avec un argument, compile l'exemple tel quel, via `PLATFORMIO_SRC_DIR=$STEAMI_LIB/lib/<driver>/examples/<Exemple>`.
    - **Seulement en cas de réussite**, écrit `.steami/firmware.bin` puis `.steami/firmware.json`, chacun de façon atomique. Il affiche alors `✅ <programme> compilé : firmware.bin prêt (steami-televerser pour l'envoyer sur la carte)`.
    - N'appelle jamais git.
  - **`steami-copier [--remplacer] driver/Exemple`** : remplace le contenu de `src/` par les fichiers du dossier de l'exemple.
  - **`STEAMI_LIB`** : vaut `/opt/steami/arduino-steami-lib` par défaut ; les tests le pointent ailleurs.

- [ ] **Step 1 : écrire les tests bats.** Le décor de test comprend :
  - un dépôt git temporaire qui contient `platformio.ini` et `src/main.cpp` ;
  - un faux `$STEAMI_LIB/lib/lis2mdl/examples/BasicReader/BasicReader.ino` et un faux `$STEAMI_LIB/lib/hts221/examples/dew_point/dew_point.ino` ;
  - un faux `pio` qui note son environnement et écrit `.pio/build/steami/firmware.bin`, ou qui échoue quand `PIO_STUB_ECHEC=1`.

  Tests :
  - `exemples_liste_tout` : la sortie vaut exactement `hts221/dew_point\nlis2mdl/BasicReader` ;
  - `exemples_filtre_inconnu` : `status -eq 1`, et la sortie contient `Aucun exemple pour « zzz »` ;
  - `compiler_src` : `.steami/firmware.json` contient `"programme": "src"`, et `.steami/firmware.bin` existe ;
  - `compiler_depuis_src` : lancé depuis `src/`, `.steami/` est créé à la racine ;
  - `compiler_hors_depot_git` : la compilation réussit dans une copie du décor sans `.git` ;
  - `compiler_exemple` : `pio` a reçu `PLATFORMIO_SRC_DIR=$STEAMI_LIB/lib/lis2mdl/examples/BasicReader`, et le json contient `"programme": "lis2mdl/BasicReader"` ;
  - `compiler_exemple_inconnu` : `status -eq 1`, et la sortie contient `steami-exemples` ;
  - `echec_ne_touche_pas_au_binaire` : après une compilation réussie, `PIO_STUB_ECHEC=1 steami-compiler` donne `status -ne 0`, et `.steami/firmware.json` comme `.steami/firmware.bin` gardent le même contenu ;
  - `copier_remplace_src` : avec un `src/` commité, `src/` ne contient ensuite que `BasicReader.ino` ;
  - `copier_refuse_src_modifie` : avec `src/main.cpp` modifié et non commité, `status -eq 1`, la sortie contient `steami-sauver` et `--remplacer`, et `src/main.cpp` est inchangé ;
  - `copier_remplacer_force` : même situation avec `--remplacer`, la copie réussit ;
  - `aide` : `steami-compiler -h` sort en 0 et affiche `Usage : steami-compiler`.
- [ ] **Step 2 : vérifier que les tests échouent.** `bats tests/commandes.bats` est rouge.
- [ ] **Step 3 : écrire les trois commandes et `steami-commun.sh`.**
- [ ] **Step 4 : vérifier que les tests passent.** `bats tests/commandes.bats` est vert.
- [ ] **Step 5 : compléter le smoke-test.** Ajouter `steami-exemples lis2mdl | grep -qx lis2mdl/BasicReader` et un vrai `steami-compiler lis2mdl/BasicReader` dans la copie d'`amorcage`. Reconstruire l'image et relancer le Step 4 de la tâche 1, hors ligne : code de sortie 0.
- [ ] **Step 6 : commit.** `feat: commandes steami-exemples, steami-compiler et steami-copier`

### Task 3 : `steami-sauver`

**Files :**
- Create : `.devcontainer/source/steami-sauver`, `tests/sauver.bats`
- Modify : `.devcontainer/source/Dockerfile`

**Interfaces :**
- Consumes : `steami-commun.sh` (tâche 2).
- Produces : `steami-sauver ["message"]`. La commande enchaîne `git add -A`, `git commit -m "<message|sauvegarde>"` et `git push`. Si la branche n'a pas d'amont, elle fait `git push -u origin <branche>` à la place. C'est une version de `IUTInfoAix-R510/devcontainer/.devcontainer/source/r510-sauver` **sans** intégration, sans rendu et sans verrou.

- [ ] **Step 1 : écrire les tests bats.** Un dépôt nu local sert d'`origin`.
  - `sauver_commit_et_push` : `origin/main` contient le commit `sauvegarde`.
  - `sauver_message` : après `steami-sauver "LED rouge"`, le dernier commit a pour message `LED rouge`.
  - `sauver_rien_de_neuf` : la sortie contient `rien de nouveau à enregistrer`, et le push est tout de même tenté.
  - `sauver_branche_sans_amont` : sur la branche `essai`, la sortie contient `git push -u origin essai`.
  - `sauver_sans_origin` (dépôt sans remote) : `status -eq 1`, le commit local existe, et la sortie contient `Publish Branch`.
  - `sauver_push_refuse` (`hooks/pre-receive` du dépôt nu qui affiche `Permission denied` et sort en 1) : `status -eq 1`, la sortie contient `Use this template` et `enregistré dans le Codespace`, et le commit local existe.
  - `sauver_head_detachee` : `status -eq 1`, et le message contient `git switch main`.
- [ ] **Step 2 : vérifier que les tests échouent.** `bats tests/sauver.bats` est rouge.
- [ ] **Step 3 : écrire `steami-sauver`.**
  - **Sans `origin`** (vérifié avec `git remote get-url origin`) : faire le commit en local, puis expliquer que le Codespace n'est lié à aucun dépôt GitHub. Pour le publier : Contrôle de code source → « Publish Branch », ou « Publish to a new repository » depuis github.com/codespaces.
  - **Push refusé** : dire que le travail est enregistré dans le Codespace et non sur GitHub. Ajouter : si ce Codespace est ouvert sur steamicc/arduino-steami-starter, créer d'abord son dépôt avec « Use this template » → « Create a new repository » (voir le wiki).
- [ ] **Step 4 : vérifier que les tests passent.** `bats tests/sauver.bats` est vert.
- [ ] **Step 5 : commit.** `feat: commande steami-sauver`

### Task 4 : serveur de la page et `steami-televerser`

**Files :**
- Create :
  - `.devcontainer/source/steami_serveur.py`, copié dans `/usr/local/lib/steami/` ;
  - `.devcontainer/source/steami-serveur` (enveloppe `start|stop|status`) et `.devcontainer/source/steami-televerser` ;
  - les tests `tests/test_serveur.py`, `tests/serveur.bats` et `tests/televerser.bats` ;
  - le faux serveur `tests/stubs/steami-serveur`.
- Modify : `.devcontainer/source/Dockerfile`

**Interfaces :**
- Consumes : `.steami/firmware.bin` et `.steami/firmware.json` (tâche 2), `racine_depot` (tâche 2).
- Produces :
  - **`steami_serveur.py`** : écoute sur `0.0.0.0:$STEAMI_PORT`.
    - Il sert `/` et les fichiers statiques depuis `STEAMI_FLASHER` (par défaut `/opt/steami/flasher`).
    - Les chemins **exactement** `/firmware.bin` et `/firmware.json` (comparés sur `urlsplit(self.path).path`) sont servis depuis `$STEAMI_DEPOT/.steami/`.
    - Toutes les réponses ont l'en-tête `Cache-Control: no-store`, et un fichier absent donne 404.
  - **`steami-serveur start`** :
    - se place dans `racine_depot` et exporte `STEAMI_DEPOT` ;
    - ne fait rien si le serveur tourne déjà, c'est-à-dire si `/proc/$pid/cmdline` contient `steami_serveur` ;
    - sinon, supprime un fichier pid périmé, puis lance `setsid nohup python3 /usr/local/lib/steami/steami_serveur.py >/tmp/steami-serveur.log 2>&1 </dev/null &` et écrit `$STEAMI_PID`.
  - **`steami-serveur status`** : sort en 0 si le serveur tourne, en 1 sinon. **`steami-serveur stop`** l'arrête.
  - **`steami-televerser`** :
    - se place dans `racine_depot` ;
    - sans `.steami/firmware.json`, affiche `✗ Aucun programme compilé : lancez steami-compiler` et sort en 1 ;
    - sinon, lance `steami-serveur start` puis affiche l'adresse `https://${CODESPACE_NAME}-${STEAMI_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}/` (ou `http://localhost:${STEAMI_PORT}/` hors Codespace) ;
    - rappelle d'ouvrir la page dans un onglet de Chrome ou d'Edge ;
    - présente **à égalité** l'autre méthode : clic droit sur `.steami/firmware.bin` → Download, puis glisser le fichier sur le lecteur STEAMI.

- [ ] **Step 1 : écrire les tests.**
  - `tests/test_serveur.py` (`unittest`) : il ajoute lui-même le chemin absolu de `.devcontainer/source` à `sys.path`, et lance le serveur dans un thread, sur un port libre, avec des dossiers temporaires.
    - `test_firmware_absent_404`
    - `test_firmware_servi` : mêmes octets, et en-tête `Cache-Control: no-store`
    - `test_json_servi`
    - `test_json_avec_requete` : `/firmware.json?t=1` répond 200
    - `test_index_servi`
    - `test_pas_de_sortie_du_dossier` : `/../../etc/passwd`, `/firmware.bin/../../etc/passwd` et `/firmware.bin.tmp` répondent tous 404
  - `tests/serveur.bats` (`STEAMI_PID` temporaire, port libre, `stop` dans le teardown) :
    - `start_rend_la_main` : `timeout 5 steami-serveur start | cat` se termine, et aucun `nohup.out` n'est créé ;
    - `start_pid_perime` : avec un fichier pid qui contient le pid d'un `sleep 60 &`, `start` lance bien le serveur et `status` sort en 0 ;
    - `start_depuis_src` : lancé depuis `src/`, le serveur sert le `.steami/firmware.json` de la racine.
  - `tests/televerser.bats` (le faux `steami-serveur` est placé dans le PATH et note ses arguments) :
    - `adresse_codespace` : avec `CODESPACE_NAME=abc` et `GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev`, la sortie contient `https://abc-8080.app.github.dev/` et le faux serveur a reçu `start` ;
    - `sans_binaire` : `status -eq 1` ;
    - `depuis_src` : réussit si `.steami/firmware.json` existe à la racine.
- [ ] **Step 2 : vérifier que les tests échouent.** `python3 -m unittest discover -s tests -p 'test_*.py'`, `bats tests/serveur.bats tests/televerser.bats`.
- [ ] **Step 3 : implémenter.** `ThreadingHTTPServer`, et un `SimpleHTTPRequestHandler` avec `directory=STEAMI_FLASHER` qui intercepte les deux chemins exacts.
- [ ] **Step 4 : vérifier que les tests passent** (mêmes commandes).
- [ ] **Step 5 : commit.** `feat: serveur de la page Téléverser et commande steami-televerser`

### Task 5 : page « Téléverser » (WebUSB + console série)

**Files :**
- Create :
  - `.devcontainer/source/flasher/index.html` ;
  - `flasher/app.js` (lien entre le DOM et DAP.js), `flasher/console.js`, `flasher/support.js` ;
  - `flasher/vendor/dap.umd.js` et `flasher/vendor/LICENSE-dapjs` (DAP.js 2.3.0, licence MIT) ;
  - les tests `tests/flasher.test.mjs`.
- Modify : `.devcontainer/source/Dockerfile` (copie dans `/opt/steami/flasher`)

**Interfaces :**
- Consumes : `/firmware.bin` et `/firmware.json` (tâche 4) ; la séquence DAP.js validée à la tâche 0.
- Produces :
  - `console.js` : `class TamponLignes { constructor(maxLignes = 2000); ajouter(texte: string): string[] /* lignes complètes */; vider(): void; get lignes(): string[] }`.
  - `support.js` :
    - `etatWebUSB(nav, estFenetrePrincipale: boolean): 'ok' | 'absent' | 'iframe'` ;
    - `messageErreur(err: {name?: string, message?: string}): string` ;
    - `resumeProgramme(json: {programme, date, taille} | null): string`.

- [ ] **Step 1 : écrire `tests/flasher.test.mjs`** (`node:test`). Les messages d'erreur sont les vrais messages de Chrome.
  - **`TamponLignes`** :
    - `ajouter("a\nb")` renvoie `["a"]`, puis `ajouter("c\n")` renvoie `["bc"]` ;
    - au-delà de 2000 lignes, les plus anciennes sont retirées ;
    - `vider()` remet le tampon à zéro.
  - **`etatWebUSB`** :
    - `etatWebUSB({}, true)` → `'absent'` ;
    - `etatWebUSB({usb:{}}, false)` → `'iframe'` ;
    - `etatWebUSB({usb:{}}, true)` → `'ok'`.
  - **`messageErreur`** :
    - `{name:'NotFoundError', message:'No device selected.'}` → contient `Aucune carte choisie` ;
    - `{name:'NotFoundError', message:'The device was disconnected.'}` → contient `débranchée` ;
    - `{name:'SecurityError', message:'Access denied.'}` → contient `accès à la carte refusé` ;
    - `{name:'SecurityError', message:'... permissions policy ...'}` → contient `ouvrir la page dans un onglet` ;
    - `{name:'NetworkError', message:'Unable to claim interface.'}` → contient `utilisée par un autre onglet` ;
    - une erreur inconnue → contient son propre message.
  - **`resumeProgramme`** :
    - `resumeProgramme(null)` → `Aucun programme compilé : lancez steami-compiler` ;
    - `resumeProgramme({programme:"src", date:"2026-11-24T10:00:00Z", taille:20480})` → contient `src` et `20 Ko`.
- [ ] **Step 2 : vérifier que les tests échouent.** `node --test tests/flasher.test.mjs`.
- [ ] **Step 3 : implémenter `console.js` et `support.js`.** Ce sont des modules ES sans dépendance.
- [ ] **Step 4 : vérifier que les tests passent.** `node --test tests/flasher.test.mjs`.
- [ ] **Step 5 : écrire `index.html` et `app.js`** (textes en français).
  - Le bandeau affiche `resumeProgramme`, rafraîchi toutes les 3 s.
  - Boutons « Connecter la carte », « Téléverser » et « Effacer la console ». Téléverser est désactivé tant qu'il n'y a pas de carte ou pas de programme.
  - Une barre de progression et la console série.
  - **Lecture série** : `boucle = dap.startSerialRead(10).catch(err => { afficher(messageErreur(err)); etatNonConnectee(); })`. Ne jamais attendre cette promesse au démarrage.
  - **Téléversement** : `dap.stopSerialRead(); await boucle;`, puis récupérer `/firmware.bin`. Si sa `byteLength` diffère de la `taille` affichée, rafraîchir le bandeau et demander de cliquer à nouveau. Sinon `await dap.flash(...)`, attendre 1 s, `await dap.reset()` (sans ce reset, la carte ne redémarre pas : constaté à la tâche 0), puis relancer la boucle.
  - Sur un `disconnect` USB, revenir à l'état « non connectée ».
  - Si `etatWebUSB` ne vaut pas `'ok'`, afficher un encart qui explique la copie sur le lecteur.
- [ ] **Step 6 : vérifier sur la carte, avec l'utilisateur.** Lancer l'image locale avec `docker run -p 8080:8080 ...`, puis `steami-compiler` et `steami-serveur start`, et ouvrir la page dans Chrome.
  - Téléverser deux programmes différents : la console affiche la sortie du second.
  - Débrancher la carte : un message s'affiche, puis l'état « non connectée ».
  - Ouvrir la page dans Firefox : l'encart de copie sur le lecteur s'affiche.
- [ ] **Step 7 : commit.** `feat: page Téléverser en WebUSB avec console série`

### Task 6 : accueil, CI, publication de l'image

**Files :**
- Create :
  - `.devcontainer/source/first-run-notice.txt` ;
  - `.devcontainer/devcontainer.json`, la configuration distribuée de ce dépôt ;
  - `exemples/devcontainer.json`, le modèle pour le template ;
  - `.github/workflows/devcontainer.yml`. Il se déclenche sur les PR et les push, et est désactivé dans les forks. Il lance `bats tests/`, `python3 -m unittest discover -s tests -p 'test_*.py'` et `node --test tests/`, puis `docker build -t steami-devcontainer:dev .devcontainer/source` et le smoke-test en `docker run --network none -u vscode`.
  - `.github/workflows/devcontainer-publish.yml`, adapté de R510 :
    - `IMAGE: ghcr.io/steamicc/arduino-steami-devcontainer` ;
    - condition `github.repository == 'steamicc/arduino-steami-devcontainer'` ;
    - tag `devcontainer-AAAA.MM.N`, `configFile: .devcontainer/source/devcontainer.json` ;
    - la boucle du résumé porte sur `.devcontainer/devcontainer.json exemples/devcontainer.json`, et la suite à donner ne cite que `.devcontainer/devcontainer.json` de `steamicc/arduino-steami-starter`.
  - `README.md` et `CONTRIBUTING.md`, avec les sections « Publier une nouvelle image » et « Mettre à jour les drivers » (changer le tag, rétablir `DigitalCompass` et `BleHotCold` dans la documentation une fois corrigés).
- Modify : `.devcontainer/source/Dockerfile` (le message d'accueil va dans `/usr/local/etc/vscode-dev-containers/first-run-notice.txt`)

**Interfaces :**
- Produces : `exemples/devcontainer.json`, que la tâche 7 recopie :

```jsonc
{
  "name": "STeaMi Arduino",
  "image": "ghcr.io/steamicc/arduino-steami-devcontainer:2026.11.1",
  "hostRequirements": { "cpus": 2 },
  "forwardPorts": [8080],
  "portsAttributes": { "8080": { "label": "Téléverser", "onAutoForward": "notify" } },
  "postStartCommand": "steami-serveur start"
}
```

- [ ] **Step 1 : écrire `first-run-notice.txt`** sur le modèle de R510. Il présente :
  - `steami-exemples` ;
  - `steami-compiler` ;
  - `steami-copier` ;
  - `steami-televerser` et la copie sur le lecteur, **à égalité** ;
  - `steami-sauver` ;
  - l'arrêt du Codespace en fin de séance, à cause du quota.
- [ ] **Step 2 : écrire les deux workflows, `README.md` et `CONTRIBUTING.md`.**
- [ ] **Step 3 : vérifier en local.** `actionlint` ne signale rien sur les deux workflows, et les commandes de test du workflow `devcontainer.yml` passent toutes au vert.
- [ ] **Step 4 : commit.** `ci: construction, smoke-test et publication de l'image`
- [ ] **Step 5 : publier, avec l'accord de l'utilisateur.**
  1. Lui demander l'accord explicite pour créer le dépôt public `steamicc/arduino-steami-devcontainer`, puis lancer `gh repo create steamicc/arduino-steami-devcontainer --public --source . --push`.
  2. Ouvrir une issue de suivi qui renvoie vers la spec.
  3. Pousser le tag `devcontainer-2026.11.1`. Attendu : `devcontainer-publish` est vert, y compris son étape « Post Build ».
  4. Faire rendre le paquet **public** par l'utilisateur ou un administrateur de `steamicc`.
  5. Vérifier qu'il est bien accessible : `docker pull ghcr.io/steamicc/arduino-steami-devcontainer:2026.11.1` sans être connecté.

### Task 7 : dépôt template `arduino-steami-starter`

**Files :**
- Create (dépôt neuf `/home/nedjar/sandbox/arduino-steami-starter`) :
  - `.devcontainer/devcontainer.json`, identique à `exemples/devcontainer.json` (tâche 6) ;
  - `platformio.ini`, identique à `.devcontainer/source/amorcage/platformio.ini` (tâche 1) ;
  - `src/main.cpp` ;
  - `.vscode/tasks.json` ;
  - `.gitignore` (`.pio/`, `.steami/`) ;
  - `.github/workflows/compiler.yml` ;
  - `README.md` et `LICENSE`.

**Interfaces :**
- Consumes : l'image `2026.11.1` publiée (tâche 6) et les commandes des tâches 2 à 4.

- [ ] **Step 1 : écrire la CI (le test).** `compiler.yml` contient un job `container: ghcr.io/steamicc/arduino-steami-devcontainer:2026.11.1` qui lance `steami-compiler`, puis `test -s .steami/firmware.bin`. Il porte `if: github.repository == 'steamicc/arduino-steami-starter'`, avec un commentaire : sans cette condition, chaque dépôt d'élève recevrait un courriel d'échec à chaque sauvegarde d'un programme en cours.
- [ ] **Step 2 : écrire `src/main.cpp`.** Il fait clignoter `LED_GREEN` et affiche `Bonjour STeaMi !`, puis un compteur, toutes les secondes, avec `Serial.println`.
- [ ] **Step 3 : écrire `.vscode/tasks.json`.** Tâches :
  - « STeaMi : compiler » → `steami-compiler`, tâche de compilation par défaut ;
  - « STeaMi : compiler un exemple » et « STeaMi : copier un exemple » → l'argument vient d'un `promptString` qui rappelle `steami-exemples` ;
  - « STeaMi : téléverser » → `steami-televerser` ;
  - « STeaMi : sauvegarder » → `steami-sauver`.
- [ ] **Step 4 : écrire `README.md`.** Dans l'ordre :
  1. « Use this template » → **« Create a new repository »**, et non « Open in a codespace » ;
  2. ouvrir un Codespace sur **son** dépôt ;
  3. les commandes ;
  4. les deux façons d'envoyer le programme, à égalité ;
  5. le lien vers `https://wiki.steami.cc/docs/software/arduino/codespace`.
- [ ] **Step 5 : vérifier en local.** `docker run --rm -u vscode -v "$PWD":/w -w /w ghcr.io/steamicc/arduino-steami-devcontainer:2026.11.1 steami-compiler` doit afficher `✅ src compilé`.
- [ ] **Step 6 : commit et publication** (création du dépôt accordée par l'utilisateur).
  1. `git init -b main`, puis commit `feat: dépôt template Arduino STeaMi pour Codespaces`.
  2. `gh repo create steamicc/arduino-steami-starter --public --source . --push`.
  3. `gh repo edit steamicc/arduino-steami-starter --template`.

  Attendu : le workflow `compiler` est vert.

### Task 8 : essai complet dans un vrai Codespace

- [ ] **Step 1 : dérouler la recette avec l'utilisateur.** Partir de « Use this template » → « Create a new repository », sur un compte de test.
  1. Le Codespace est utilisable en moins de 2 minutes, et le message d'accueil s'affiche.
  2. `steami-compiler` et `steami-compiler lis2mdl/BasicReader` réussissent.
  3. La notification « Téléverser » ouvre la page dans un onglet. Le téléversement en un clic fonctionne et la sortie série s'affiche.
  4. La copie sur le lecteur fonctionne : Download, puis glisser le fichier sur STEAMI.
  5. `steami-copier` puis `steami-sauver "essai"` : le commit apparaît sur GitHub.
  6. Après un arrêt puis une reprise du Codespace, la page répond toujours.
- [ ] **Step 2 : corriger dans le dépôt concerné.** Si besoin, publier une nouvelle version de l'image et mettre à jour son tag dans le template. Noter les durées mesurées pour le wiki.
- [ ] **Step 3 : faire des captures d'écran pour le wiki.** L'accueil du Codespace, la page Téléverser, et l'explorateur avec Download.

### Task 9 : page wiki

**Files** (dépôt `/home/nedjar/sandbox/wiki_steami`) :
- Create :
  - `docs/software/arduino/codespace.md` ;
  - `static/img/software/arduino/codespace-*.png` (captures de la tâche 8).
- Modify :
  - `docs/software/arduino/index.md`, section « Par où commencer » : ajouter « Programmer sans installation » ;
  - `docs/software/arduino/arduino-ide.md` : encart vers l'alternative sans installation ;
  - les `sidebar_position` des pages suivantes de `docs/software/arduino/`, décalées de 1 ;
  - `.cspell/steami.txt`.

- [ ] **Step 1 : préparer l'issue et la branche.** Créer l'issue avec `gh issue create` dans `steamicc/wiki_steami`. Créer la branche `docs/arduino-codespace` à partir de `main` si `feat/software-arduino` est fusionnée, sinon à partir de `feat/software-arduino`, et l'indiquer dans la PR.
- [ ] **Step 2 : écrire `codespace.md`.** En-tête : `title: Programmer sans installation (Codespace)`, `sidebar_position: 2`. Sections, dans l'ordre :
  1. Pour qui.
  2. Prérequis : compte GitHub, 13 ans minimum, quota de 120 h-cœur par mois (60 h sur 2 cœurs).
  3. Créer son dépôt (« Create a new repository ») et ouvrir le Codespace.
  4. Compiler un exemple.
  5. Écrire et sauvegarder son programme.
  6. Envoyer le programme sur la carte : un tableau « quelle méthode choisir » selon le navigateur et le poste (Chrome/Edge ou autre, WebUSB désactivé, Linux sans règle udev), puis les deux méthodes à égalité.
  7. Lire la sortie série.
  8. Limites : pas de débogage, quota, Codespaces inactifs supprimés.
  9. Conseils pour la classe : préparer avant la séance, vérifier l'accès à `*.github.dev` sur le réseau de l'établissement, arrêter le Codespace.

  Ne citer que des exemples qui compilent à la version de l'image.
- [ ] **Step 3 : ajouter les liens et le vocabulaire.** Liens depuis `index.md` et `arduino-ide.md`, mots nouveaux dans `.cspell/steami.txt`.
- [ ] **Step 4 : vérifier.** `npm run build` réussit sans lien cassé, et les contrôles du pre-commit (cspell, markdownlint, prettier) passent.
- [ ] **Step 5 : commit et PR.** Commit `docs: programmer la STeaMi en Arduino sans installation (Codespace)`, puis une PR qui référence l'issue.
