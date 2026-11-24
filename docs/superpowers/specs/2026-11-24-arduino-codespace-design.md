# Programmer la STeaMi en Arduino sans rien installer (Codespace) — conception

Date : 2026-11-24

## Intention

Faciliter l'adoption de la STeaMi en Arduino par les **enseignants et élèves** : supprimer l'installation (Arduino IDE + paquet STM32 + bibliothèques, ou PlatformIO) en proposant un **GitHub Codespace** prêt à compiler les exemples STeaMi et les programmes des élèves, depuis le navigateur. La démarche est documentée dans le wiki STeaMi.

## Objectifs

- Ouvrir un Codespace depuis un bouton, et compiler un programme STeaMi sans aucune installation locale.
- Compiler un **exemple des drivers tel quel**, et pouvoir **copier un exemple dans son propre programme** pour le modifier.
- Envoyer le programme compilé sur la carte et **voir la sortie série** (`Serial.println`), indispensable pour les exemples de capteurs.
- Une page wiki qui explique la démarche pas à pas, pour un public enseignant.

## Non-objectifs

- Débogage pas à pas (OpenOCD/GDB) : impossible sans accès USB depuis le Codespace.
- Remplacer le flux PlatformIO des contributeurs (`arduino-steami-lib`, `make setup`) : il reste tel quel.
- Support de navigateurs sans WebUSB pour le téléversement en un clic (Firefox, Safari) : ils passent par la copie sur le lecteur.

## Anti-objectifs (échec même si « ça marche »)

- Un Codespace qui met plusieurs minutes à devenir utilisable à chaque ouverture en classe.
- Un dépôt où l'élève doit taper des commandes `pio`/`make` pour faire l'essentiel.
- Des drivers non figés : un élève qui ouvre le Codespace un autre jour ne doit pas tomber sur une version cassée.

## Contraintes et faits établis

- Le DAPLink STeaMi (`DAPLink/projects.yaml`, cible `stm32f103xb_steami32_if`) inclut `usb-webusb.yaml`, `cmsis-dap.yaml`, `drag-n-drop.yaml` et `usb2uart.yaml` : WebUSB, CMSIS-DAP, lecteur de masse et pont série sont disponibles.
- L'ancien éditeur MicroPython (`micropython-editor-experimental/src/daplink.ts`) flashait et lisait la série en WebUSB via **DAP.js** (`DAPjs.WebUSB` + `DAPjs.DAPLink`), sur une autre cible (STM32L475). Non vérifié sur STM32WB55.
- `arduino-steami-lib` : `platformio.ini` (`platform = ststm32@^19`, `board = steami`, `framework = arduino`, `lib_deps = stm32duino/STM32duinoBLE@^1.5.0`), définition de carte `boards/steami.json`, drivers dans `lib/<driver>/`, exemples dans `lib/<driver>/examples/<Exemple>/<Exemple>.ino`. PlatformIO figé à `platformio==6.1.19` dans `requirements.txt`. Versions publiées par semantic-release (tags `vX.Y.Z`). Les drivers ne sont publiés ni sur le registre PlatformIO ni dans le gestionnaire de bibliothèques Arduino.
- `lib_deps` PlatformIO ne sait pas prendre un sous-dossier d'un dépôt Git.
- Les ports redirigés d'un Codespace sont servis en HTTPS (contexte sécurisé, requis par WebUSB) et privés par défaut (authentification GitHub dans le même navigateur).
- WebUSB est bloqué dans une iframe sans permission explicite : la page de téléversement doit s'ouvrir **dans un onglet du navigateur**, pas dans le « Simple Browser » de VS Code.
- WebUSB : Chrome, Edge et dérivés Chromium uniquement.
- Codespaces demande un compte GitHub (âge minimum 13 ans selon les conditions de GitHub) ; quota gratuit des comptes personnels : 120 h-cœur/mois (soit 60 h sur une machine 2 cœurs). À signaler dans le wiki.
- La première compilation télécharge la toolchain STM32 (plusieurs centaines de Mo). Les **prebuilds** Codespaces ne s'appliquent qu'au dépôt où ils sont activés, donc pas aux dépôts créés depuis le template : la toolchain doit être **intégrée à l'image du conteneur**.
- La variante `STEAM32_WB55RG` est fournie par le framework STM32duino ; `Serial` (PB10/PB11) passe par le pont série du DAPLink ; l'ancien éditeur filtre le VID `0x0D28` et utilise `dapjs ^2.3.0` ; `arduino-steami-lib` compile déjà ses exemples avec `PLATFORMIO_SRC_DIR` (vérifié par la relecture).

## Approches envisagées

| | Approche | Avantages | Inconvénients |
|---|---|---|---|
| A | Copie du `.bin` sur le lecteur STEAMI uniquement | Tous navigateurs et systèmes, rien à maintenir | Pas de moniteur série : la plupart des exemples de capteurs n'affichent rien ; étape de téléchargement |
| **B (retenue)** | A + page « Téléverser » servie par le Codespace, WebUSB via DAP.js, avec console série | Un clic, sortie série visible, rien à installer | Chrome/Edge seulement ; à valider sur une vraie carte STM32WB55 |
| C | Page WebUSB hébergée sur le wiki, où l'on dépose le `.bin` téléchargé | Réutilisable par les utilisateurs de l'Arduino IDE | Garde l'étape de téléchargement ; ne règle pas le flux Codespace mieux que B |

**Choix : B, avec A documentée comme solution de repli.** Proposé par Claude, accepté par l'utilisateur. C pourra réutiliser plus tard le code de la page de B.

Hébergement : un **nouveau dépôt « starter »** dédié aux enseignants et élèves (choix de l'utilisateur), plutôt qu'un `.devcontainer` dans `arduino-steami-lib` (dont l'outillage contributeur — Node, husky, clang-tidy — est inutile ici).

## Conception

### 1. Dépôt starter

Dépôt `steamicc/arduino-steami-starter`, public, marqué « template » (création par Claude avec `gh`, accord de l'utilisateur).

**Mode d'utilisation (choix de l'utilisateur) : template par défaut.** L'enseignant ou l'élève clique sur « Use this template », obtient son propre dépôt, puis ouvre un Codespace dessus ; son travail se sauvegarde par commit dans son dépôt. Le README et le wiki décrivent ce parcours en premier. Tout ce qui suit doit donc fonctionner **dans une copie du template**, sans réglage d'organisation ni prebuild.

**Révision (modèle R510, demandé par l'utilisateur)** : comme `IUTInfoAix-R510/devcontainer`, l'image vit dans un **dépôt dédié** `steamicc/arduino-steami-devcontainer`, et le template ne contient que la configuration distribuée qui la télécharge. Les **drivers et la toolchain sont intégrés à l'image**, et des **commandes `steami-*`** simplifient l'usage, sur le modèle de `r510-sauver`.

```text
arduino-steami-devcontainer/                 # dépôt de l'image (contributeurs)
├── .devcontainer/devcontainer.json          # configuration distribuée de ce dépôt (télécharge l'image)
├── .devcontainer/source/                    # configuration source : Dockerfile, devcontainer.json, commandes, page
├── .devcontainer/smoke-test.sh              # vérifie l'image avant publication
├── .github/workflows/devcontainer-publish.yml   # tag devcontainer-AAAA.MM.N → ghcr.io, jamais écrasé
└── exemples/devcontainer.json               # modèle de configuration distribuée pour les templates

arduino-steami-starter/                      # template (enseignants et élèves)
├── .devcontainer/devcontainer.json          # image ghcr.io épinglée + démarrage de la page Téléverser
├── .vscode/tasks.json                       # raccourcis vers les commandes steami-*
├── src/main.cpp                             # programme de l'élève (LED + Serial)
├── platformio.ini
└── README.md                                # « Use this template » puis Codespace, renvoi vers le wiki
```

- **Drivers** (choix de Claude) : `arduino-steami-lib` est cloné **au tag `v0.24.0`** dans l'image (`/opt/steami/arduino-steami-lib`), avec la définition de carte ; `platformio.ini` du template y pointe (`boards_dir`, `lib_extra_dirs`). Mise à jour des drivers = nouvelle version de l'image. Le template ne compile donc que dans l'image (non-objectif : PlatformIO local, qui a `arduino-steami-lib`).
- **Commandes** (choix de Claude, sur le modèle R510 : messages en français, chaque commande affiche les commandes qu'elle lance, `-h` pour l'aide) : `steami-exemples` (liste), `steami-compiler [driver/Exemple]` (compile `src/` ou un exemple tel quel), `steami-copier driver/Exemple` (copie un exemple dans `src/`), `steami-televerser` (adresse de la page et emplacement du binaire), `steami-sauver ["message"]` (add, commit, push). Message d'accueil `first-run-notice.txt` qui les présente.
- **`platformio.ini`** : un environnement `steami` repris de `arduino-steami-lib` (même carte, `monitor_speed = 115200`), sans la configuration de tests ni `lib_deps`. Les versions de la plateforme et du framework sont **exactes**. STM32duinoBLE `1.5.0` vient de l'image (`/opt/steami/libs`, via `lib_extra_dirs`), ce qui permet de compiler sans réseau. Ce sont des choix de Claude, liés à l'anti-objectif « non figé ».
- **Exemples de référence** : `lis2mdl/BasicReader` et `ble/BleBeacon`. `lis2mdl/DigitalCompass` et `ble/BleHotCold` ne compilent pas au tag `v0.24.0` : on ne les cite pas tant que l'image ne passe pas à un tag qui les corrige.
- **Compiler un exemple tel quel** : une tâche VS Code qui demande le chemin d'un exemple (liste générée à la création du conteneur, ou saisie) et compile avec `PLATFORMIO_SRC_DIR` pointé sur le dossier de l'exemple, sans le copier. Une seconde tâche copie l'exemple dans `src/` pour le modifier. Le mécanisme exact (liste de choix, script) est laissé au constructeur, avec la contrainte : aucune commande à taper pour l'élève.
- Le binaire compilé est toujours exposé au même endroit pour la page de téléversement (par exemple `.pio/build/steami/firmware.bin`, ou un lien stable vers le dernier exemple compilé).

### 2. Conteneur (`.devcontainer`)

- **Image `ghcr.io/steamicc/arduino-steami-devcontainer:AAAA.MM.N`** (à la place des prebuilds, qui ne s'appliquent pas aux dépôts créés depuis le template) : PlatformIO `6.1.19`, plateforme `ststm32@19.7.1` (framework-arduinoststm32 `4.21200.0`), STM32duinoBLE `1.5.0`, `arduino-steami-lib` `v0.24.0`, tous **déjà téléchargés** dans l'image par une compilation d'amorçage. Paquet public. Publication sur tag `devcontainer-AAAA.MM.N`, refus d'écraser une version, smoke-test avant push, rien dans les forks — comme R510.
- Pas d'extension PlatformIO IDE : les commandes et les tâches suffisent, et l'extension télécharge son propre PlatformIO au premier lancement.
- Aucune commande de cycle de vie qui installe quoi que ce soit ; seul `postStartCommand` démarre le serveur de la page « Téléverser ».
- `postStartCommand` : lancer le petit serveur HTTP de la page de téléversement sur un port fixe ; `forwardPorts` + `portsAttributes` avec une étiquette « Téléverser » et `onAutoForward: notify` (ou `openBrowser`).
- Machine 2 cœurs par défaut (économise le quota des élèves).

### 3. Page « Téléverser » (`flasher/`)

- Page statique en français, sans framework, avec DAP.js embarqué dans le dépôt (pas de CDN, version figée).
- Bouton **Connecter la carte** (sélecteur WebUSB filtré sur le VID/PID du DAPLink STeaMi), bouton **Téléverser** qui récupère le dernier `firmware.bin` depuis le serveur du Codespace et l'envoie via `DAPLink.flash()`, avec barre de progression.
- **Console série** sous les boutons, à 115200 bauds via `DAPLink` (`setSerialBaudrate`, lecture série), arrêtée pendant le téléversement puis relancée ; bouton pour effacer.
- Messages clairs si WebUSB n'est pas disponible (navigateur non Chromium, page ouverte dans une iframe) : renvoyer vers la copie sur le lecteur.
- Afficher la date du binaire servi, pour éviter de téléverser une ancienne compilation.
- **Première étape de réalisation : un essai sur une vraie carte STeaMi** (flash d'un `.bin` STM32WB55 et lecture série via DAP.js). Si `flash()` ne fonctionne pas avec un `.bin`, essayer un `.hex` ; si rien ne fonctionne, revenir vers l'utilisateur avant de continuer (l'option A seule reste viable).

Toutes les STeaMi en circulation ont un DAPLink (réponse de l'utilisateur). La présence de WebUSB et des commandes de flash dans chaque version de firmware sera confirmée par l'essai sur carte ; si certaines versions ne l'ont pas, le wiki renvoie vers la mise à jour du DAPLink ou vers la copie sur le lecteur.

### 4. Copie sur le lecteur (à égalité avec la page « Téléverser »)

**Les deux méthodes sont présentées à égalité** dans le README et le wiki (choix de l'utilisateur), pour s'adapter aux postes et réseaux de chaque établissement (navigateur non Chromium, WebUSB désactivé par une politique, filtrage réseau…). Pas de hiérarchie « principale / repli » dans le texte : un tableau « quelle méthode choisir » selon le navigateur et le poste.

Copie : clic droit sur `firmware.bin` dans l'explorateur du Codespace → **Download**, puis glisser le fichier sur le lecteur **STEAMI**. Une tâche ou un lien stable rend le dernier binaire facile à trouver. La sortie série demande alors un terminal série local ; le wiki indique aussi que la page « Téléverser » peut servir de console seule.

### 5. Page wiki

- Nouvelle page `docs/software/arduino/codespace.md`, titre « Programmer sans installation (Codespace) », placée juste après « Installer l'Arduino IDE » dans l'ordre de la barre latérale.
- Contenu : à qui elle s'adresse ; prérequis (compte GitHub, âge minimum, quota) ; créer son dépôt avec « Use this template » et ouvrir le Codespace ; compiler un exemple ; écrire son programme et le sauvegarder (commit) ; **envoyer le programme sur la carte : les deux méthodes à égalité** (page « Téléverser » en WebUSB, copie sur le lecteur) avec un tableau pour choisir ; lire la sortie série ; limites (pas de débogage, quota, Codespaces inactifs supprimés) ; conseils pour la classe (créer les dépôts et Codespaces avant la séance, vérifier l'accès à `*.github.dev` depuis le réseau de l'établissement).
- Liens depuis `docs/software/arduino/index.md` (« Par où commencer ») et depuis `arduino-ide.md` (alternative sans installation). Mots nouveaux ajoutés à `.cspell/steami.txt`.
- Suivre le flux habituel du wiki : issue, branche dédiée, PR qui référence l'issue.
- Captures d'écran : à demander à l'utilisateur ou à réaliser une fois le Codespace en ligne.

## Laissé au constructeur

- Mécanisme exact des tâches VS Code et du choix d'exemple.
- Serveur HTTP de la page (Python `http.server` ou équivalent) et façon d'exposer le dernier binaire.
- Mise en page de la page « Téléverser ».
- Version de DAP.js (la plus récente stable compatible avec le DAPLink).
