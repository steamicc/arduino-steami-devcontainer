# Mise à jour du DAPLink depuis la page Téléverser — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** à la connexion d'une STeaMi dont le DAPLink est plus ancien que celui embarqué dans l'image, la page Téléverser l'annonce et guide sa mise à jour (option B), puis un essai jetable évalue l'écriture directe sur les lecteurs (option C).

**Architecture:** le DAPLink STeaMi répond à une commande vendeur `0x9F` (marque `STM1`, numéro et date de release, fixés par la CI de release). L'image embarque le firmware de la dernière release, épinglé par SHA256, dans `/opt/steami/flasher/daplink/` (servi tel quel par `steami_serveur.py`). La page interroge la carte après `connect()`, décide avec des fonctions pures de `support.js`, et affiche un encart non bloquant avec les étapes.

**Tech Stack:** C (DAPLink, progen + make_gcc_arm), GitHub Actions, DAP.js 2.3.0 (WebUSB), JavaScript ES modules + `node --test`, Dockerfile, bash (smoke-test), Docusaurus (wiki).

**Spec:** `docs/superpowers/specs/2026-11-25-mise-a-jour-daplink-design.md` (dépôt image, branche `feat/maj-daplink`).

## Global Constraints

- Outils : un appel d'outil à la fois, jamais en parallèle (règle de l'utilisateur).
- Chaque changement : issue + branche + PR dans le dépôt concerné ; jamais de push sur `main`/`release_letssteam` ; **l'utilisateur fusionne** (*Rebase and merge*) ; pas de `--admin`. Pas de ligne d'attribution dans les commits ni les PR. Commits conventionnels en français (DAPLink : en anglais, comme son historique).
- Tag d'image posé par le contrôleur seulement après avoir vérifié que la PR est MERGED et que le tag = `origin/main`.
- La carte (V1c de l'utilisateur) est partagée avec la session wiki-steami-71 : ne la toucher qu'après son accord, la lui rendre ensuite.
- Ne pas modifier `docs/software/daplink.md` ni `docs/software/arduino/bibliotheques.md` (wiki).
- Ne pas changer `DAPLINK_VERSION` (`0259`), `DETAILS.TXT` ni le bootloader.
- Identifiant de carte STeaMi : préfixe `0839` du numéro de série USB. Commande vendeur : `ID_DAP_Vendor31` = `0x9F`. Marque : ASCII `STM1`.
- Nommage des releases DAPLink : `AAAA-MM-JJ.N`, `N` = `github.run_number` de `generate_release.yml`. La release `2026-11-25` existante garde son nom.
- Textes de la page en français, ton neutre ; la page ne bloque jamais le téléversement.

## Review Focus

- **La carte part en MAINTENANCE pendant la mise à jour** : l'événement `disconnect` ne doit pas masquer l'encart ni ses étapes (l'utilisateur en a besoin aux étapes 3 et 4). Testé par `etatEncartApresDeconnexion` (Task 3).
- **Réponse d'un ancien DAPLink avec des restes de tampon** : 64 octets dont le premier vaut `0x9F` et la suite est aléatoire → « ancien », jamais un numéro lu dans les restes. Testé dans `lireVersionSteami` (Task 3).
- **Carte DAPLink qui n'est pas une STeaMi** (micro:bit, `9904…`) ou numéro de série absent → aucune détection ni encart. Testé par `estSteami` (Task 3).
- **`/daplink/firmware.json` absent ou illisible** (page servie hors de l'image, image ancienne) → aucune détection, aucune erreur visible. Testé par `lireFirmwareEpingle` (Task 3).
- **Reconnexion d'une carte à jour après la mise à jour** → l'encart disparaît ; reconnexion d'une carte encore ancienne → il reste. Vérifié à la recette (Task 5).

---

### Task 1: DAPLink — commande `0x9F` « version STeaMi » (dépôt `steamicc/DAPLink`)

Confiée à la session wiki-steami-71 (environnement de build `/home/nedjar/sandbox/DAPLink-wt-build`, carte). Issue + branche `feat/steami-version-command` depuis `release_letssteam` + PR.

**Files:**
- Create: `source/board/steami/steami_release.h` — `#define STEAMI_RELEASE_NUMBER 0u` et `#define STEAMI_RELEASE_DATE 0u` (valeurs de développement ; la CI les réécrit, Task 2).
- Modify: `source/daplink/cmsis-dap/DAP_vendor.c` — `case ID_DAP_Vendor31:` appelle `board_vendor_version(response)` et ajoute sa longueur à `num`.
- Modify: `source/hic_hal/stm32/stm32f103xb/gpio.c` (ou le fichier commun où le constructeur juge le défaut faible le plus naturel) — `__WEAK uint8_t board_vendor_version(uint8_t *response)` qui renvoie `0` (comportement inchangé pour les autres cartes).
- Modify: `source/board/steami/steami32.c` — redéfinition qui écrit la réponse.

**Interfaces:**
- Produces: réponse `0x9F` sur STeaMi = `9F 53 54 4D 31 <numéro uint32 LE> <date uint32 LE>` (13 octets ; `53 54 4D 31` = `STM1`). Build local : numéro `0`, date `0`. Autres cartes / anciens builds : 1 octet `9F` (+ restes de tampon).

- [ ] **Step 1:** Écrire un script hôte `tools/steami_version.py` (hidapi ou `/dev/hidrawN`, rapport `00 9F` + zéros) qui affiche la réponse décodée ; l'exécuter sur le firmware actuel (release `2026-11-25`) : attendu « marque absente ».
- [ ] **Step 2:** Implémenter le défaut faible, le `case`, l'en-tête et la redéfinition STeaMi. Le `case` n'ajoute rien à `num` quand la fonction renvoie `0`.
- [ ] **Step 3:** `python tools/progen_compile.py -t make_gcc_arm --clean --parallel stm32f103xb_steami32_if` puis `stm32f103xb_stm32wb55rg_if` et `stm32f103xb_stm32l475vg_if` : les trois compilent ; noter la taille du binaire STeaMi avant/après.
- [ ] **Step 4:** Flasher le build sur la V1c (après accord), relancer le script : attendu `STM1`, numéro `0`, date `0` ; `DAP_ResetTarget` (`0a 00 01`) et le flash DAP.js fonctionnent toujours.
- [ ] **Step 5:** Commit (`steami: add vendor command 0x9F reporting the release number`), push, PR liée à l'issue.

### Task 2: DAPLink — releases `AAAA-MM-JJ.N` et numéro dans le build

Même session, même PR que Task 1 ou PR suivante.

**Files:**
- Modify: `.github/workflows/generate_release.yml`

**Interfaces:**
- Consumes: `source/board/steami/steami_release.h` (Task 1).
- Produces: release GitHub `AAAA-MM-JJ.N` dont `stm32f103xb_steami32_if_crc.bin` répond numéro `N` et date `AAAAMMJJ`.

- [ ] **Step 1:** Déplacer le calcul du nom avant les compilations : `RELEASE_NAME=$(date +'%Y-%m-%d').${{ github.run_number }}`, `RELEASE_NUMBER=${{ github.run_number }}`, `RELEASE_DATE=$(date +'%Y%m%d')` dans `$GITHUB_ENV`.
- [ ] **Step 2:** Étape avant les compilations qui réécrit les deux `#define` de `steami_release.h` avec `RELEASE_NUMBER` et `RELEASE_DATE` (sed), puis `grep` qui échoue si la réécriture n'a pas eu lieu.
- [ ] **Step 3:** Vérifier le YAML (`actionlint` si disponible) ; commit (`ci: name releases DATE.RUN and stamp the STeaMi build`), push.
- [ ] **Step 4:** Après fusion par l'utilisateur : vérifier que la release `AAAA-MM-JJ.N` existe, que la release `2026-11-25` n'a pas changé (même commit, mêmes fichiers), télécharger `stm32f103xb_steami32_if_crc.bin`, noter son SHA256, le flasher sur la V1c et vérifier `0x9F` → numéro `N`, date du jour. Transmettre au contrôleur : nom de release, `N`, date, SHA256, taille.

### Task 3: Page Téléverser — fonctions de décision (dépôt image)

Peut démarrer pendant Tasks 1–2. Branche `feat/maj-daplink`.

**Files:**
- Modify: `.devcontainer/source/flasher/support.js`
- Test: `tests/flasher.test.mjs`

**Interfaces:**
- Produces (exportées par `support.js`) :
  - `estSteami(numeroSerie: string | undefined): boolean` — vrai si la chaîne commence par `0839`.
  - `lireVersionSteami(reponse: DataView): { numero: number, date: number } | null` — `null` si moins de 13 octets ou si les octets 1–4 ne sont pas `STM1` ; sinon numéro (octets 5–8, LE) et date (9–12, LE).
  - `lireFirmwareEpingle(json: unknown): { release: string, numero: number } | null` — `null` sauf si `json.release` est une chaîne et `json.numero` un entier > 0.
  - `decisionMiseAJour(version: {numero, date} | null, epingle: {release, numero}): 'ancien' | 'a-jour' | 'dev'` — `null` → `'ancien'` ; numéro `0` → `'dev'` ; `< epingle.numero` → `'ancien'` ; sinon `'a-jour'`.
  - `etatEncartApresDeconnexion(etat: 'masque' | 'propose' | 'etapes'): same` — renvoie l'état inchangé (la déconnexion ne masque jamais l'encart).
  - `texteMiseAJour(release: string): string` — « Une mise à jour du DAPLink de cette carte est disponible (release ${release}). »

- [ ] **Step 1: Tests** (dans `tests/flasher.test.mjs`) :
  - `estSteami('08390001066fff56')` vrai ; `estSteami('9904360258994e45')`, `estSteami('')`, `estSteami(undefined)` faux.
  - `lireVersionSteami` : vue de 13 octets `9F 'S' 'T' 'M' '1' 25 00 00 00 06 29 35 01` → `{numero: 37, date: 20261126}` ; vue d'un octet `9F` → `null` ; 64 octets `9F` + octets aléatoires (graine fixe, sans `STM1`) → `null` ; vue de 12 octets avec la marque → `null`.
  - `lireFirmwareEpingle({release: '2026-11-26.37', numero: 37})` → objet ; `null`, `{}`, `{release: 'x', numero: 0}`, `{release: 'x', numero: '37'}` → `null`.
  - `decisionMiseAJour` : `null` → `'ancien'` ; numéro 0 → `'dev'` ; 36 vs 37 → `'ancien'` ; 37 → `'a-jour'` ; 38 → `'a-jour'`.
  - `etatEncartApresDeconnexion('etapes')` → `'etapes'` ; `'propose'` → `'propose'`.
  - `texteMiseAJour('2026-11-26.37')` contient `2026-11-26.37`.
- [ ] **Step 2:** `node --test tests/*.test.mjs` → échecs « not exported ».
- [ ] **Step 3:** Implémenter les six fonctions dans `support.js`.
- [ ] **Step 4:** `node --test tests/*.test.mjs` → tout passe.
- [ ] **Step 5:** Commit `feat(televerser): décision de mise à jour du DAPLink`.

### Task 4: Page Téléverser — encart et étapes, firmware embarqué dans l'image

**Files:**
- Modify: `.devcontainer/source/flasher/index.html` — bloc `<div id="maj-daplink" hidden>` (texte `#maj-texte`, boutons `#maj-ouvrir` « Mettre à jour… » et `#maj-plus-tard` « Plus tard », liste `<ol id="maj-etapes" hidden>`) sous `#etat`, style proche de `#encart` sans le réutiliser.
- Modify: `.devcontainer/source/flasher/app.js`
- Modify: `.devcontainer/source/Dockerfile`
- Modify: `.devcontainer/smoke-test.sh`
- Modify: `.devcontainer/devcontainer.json`, `exemples/devcontainer.json` (tag d'image suivant, ex. `2026.11.8`)

**Interfaces:**
- Consumes: fonctions de Task 3 ; valeurs de Task 2 (release, `N`, SHA256).
- Produces: `/opt/steami/flasher/daplink/firmware.bin` et `/opt/steami/flasher/daplink/firmware.json` (`{"release": "AAAA-MM-JJ.N", "numero": N, "taille": octets, "sha256": "…"}`), servis en `/daplink/firmware.bin` et `/daplink/firmware.json`.

- [ ] **Step 1 (Dockerfile):** `ARG STEAMI_DAPLINK_RELEASE=<release Task 2>` et `ARG STEAMI_DAPLINK_SHA256=<sha Task 2>` ; après `COPY … flasher`, `RUN` qui télécharge `https://github.com/steamicc/DAPLink/releases/download/${STEAMI_DAPLINK_RELEASE}/stm32f103xb_steami32_if_crc.bin` (`curl -fsSL`) vers `/opt/steami/flasher/daplink/firmware.bin`, vérifie `sha256sum -c`, écrit `firmware.json` (numéro = partie après le dernier `.` du nom), propriétaire `vscode`.
- [ ] **Step 2 (smoke-test):** contrôles qui échouent avec `echec` : fichier présent et non vide ; `sha256sum` = `sha256` du JSON = ARG du Dockerfile (lu comme `STEAMI_PAQUET`) ; `numero` du JSON = suffixe de l'ARG ; `taille` = taille du fichier. Ligne `ok "firmware DAPLink <release>"`.
- [ ] **Step 3 (app.js):** au chargement, `fetch('/daplink/firmware.json')` → `lireFirmwareEpingle` (échec → `null`, jamais d'erreur affichée). Dans `connecter()`, après `setSerialBaudrate` et avant `demarrerSerie()` : si `epingle` et `estSteami(device.serialNumber)`, `dap.send(0x9F)` dans un `try` (erreur → pas d'encart), `decisionMiseAJour(lireVersionSteami(réponse), epingle)` ; `'ancien'` → encart proposé (`texteMiseAJour`), sauf si « Plus tard » a été cliqué depuis le chargement ; `'a-jour'` → encart masqué. Le gestionnaire `disconnect` passe par `etatEncartApresDeconnexion`. Le lien de l'étape 1 : `href="/daplink/firmware.bin"`, `download="stm32f103xb_steami32_if_crc.bin"`. Étapes 2–4 : texte de la spec ; si MAINTENANCE n'apparaît pas, lien vers `https://wiki.steami.cc/docs/software/arduino/codespace#le-bouton-redémarrer-la-carte-ne-fonctionne-pas`.
- [ ] **Step 4:** `node --test tests/*.test.mjs`, `bats tests/`, `python3 -m unittest discover -s tests -p 'test_*.py'`, `node --input-type=module --check < .devcontainer/source/flasher/app.js` : tout passe.
- [ ] **Step 5:** Construire l'image localement (procédure de `CONTRIBUTING.md`) et lancer `.devcontainer/smoke-test.sh` dedans : tout passe, dont la ligne du firmware DAPLink.
- [ ] **Step 6:** Commit `feat(televerser): proposer la mise à jour du DAPLink (image 2026.11.8)`, puis issue + PR (fusion après la recette de Task 5).

### Task 5: Recette sur carte réelle

**Files:** aucun dans les dépôts (scripts de recette dans le scratchpad).

- [ ] **Step 1:** Accord de wiki-steami-71 pour prendre la carte. Remettre la release `2026-11-25` (sans `0x9F`) par `START_BL.ACT` + MAINTENANCE.
- [ ] **Step 2 (Node + DAP.js 2.3.0, comme la recette de #10):** `send(0x9F)` → réponse décodée `null` par `lireVersionSteami` (importée de `support.js`).
- [ ] **Step 3 (Chrome, page servie en local depuis la branche):** l'utilisateur ouvre la page dans son Chrome, connecte la carte : l'encart apparaît ; suit les étapes ; pendant MAINTENANCE l'encart et les étapes restent ; après reconnexion, l'encart disparaît. « Plus tard » masque l'encart jusqu'au rechargement. Téléverser reste possible avec l'encart affiché.
- [ ] **Step 4:** `send(0x9F)` sur la carte à jour → numéro `N`. Rendre la carte à wiki-steami-71 avec la dernière release.

### Task 6: Publication, template, wiki

- [ ] **Step 1:** Après fusion de la PR de Task 4 : vérifier MERGED et `origin/main`, tag `devcontainer-2026.11.8`, suivre la publication, vérifier le manifeste public.
- [ ] **Step 2:** Template `steamicc/arduino-steami-starter` : branche `chore/image-2026.11.8`, tag d'image dans `.devcontainer/devcontainer.json`, PR, CI verte.
- [ ] **Step 3:** Wiki (issue + branche `docs/codespace-maj-daplink` + PR) : dans `docs/software/arduino/codespace.md`, l'encart de mise à jour dans les étapes du téléversement ; la section « Le bouton Redémarrer la carte ne fonctionne pas » renvoie à l'encart et à la release la plus récente (lien `releases/latest`) ; prettier, markdownlint, cspell, `npm run build` sans lien cassé. Capture de l'encart si la recette (Task 5) en fournit une.

### Task 7: Essai C (jetable)

**Files:** page de test dans le scratchpad uniquement, rien dans les dépôts.

- [ ] **Step 1:** Page minimale servie sur `http://localhost` : bouton 1 → `showDirectoryPicker({ mode: 'readwrite' })`, lit `DETAILS.TXT`, écrit un `START_BL.ACT` vide ; bouton 2 → second `showDirectoryPicker`, écrit le firmware (récupéré par `fetch('/daplink/firmware.bin')`) en `stm32f103xb_steami32_if_crc.bin`.
- [ ] **Step 2:** Essai Linux (carte, après accord de wiki-steami-71) ; demander à l'utilisateur l'essai Windows (et macOS s'il en a un). Noter pour chacun : racine du lecteur acceptée ou refusée, nombre de fenêtres de permission, firmware valide (`0x9F` → numéro `N`).
- [ ] **Step 3:** Rapport à l'utilisateur ; si l'essai réussit, C repasse par une conception et une validation avant tout code dans la page.
