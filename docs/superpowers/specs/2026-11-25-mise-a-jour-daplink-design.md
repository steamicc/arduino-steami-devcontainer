# Mise à jour du DAPLink depuis la page Téléverser — conception

Date : 2026-11-25. Dépôts touchés : `steamicc/DAPLink` (branche `release_letssteam`), `steamicc/arduino-steami-devcontainer` (page Téléverser, image), `steamicc/wiki_steami` (tutoriel du Codespace).

## Intention

Les élèves et les enseignants utilisent la page Téléverser du Codespace pour programmer leur STeaMi. On veut profiter de ce passage pour faire évoluer le DAPLink des cartes « de manière quasi transparente » (mots de l'utilisateur) : quand une carte connectée a un DAPLink plus ancien que celui que connaît l'image, la page le signale et aide à le mettre à jour, sans que personne n'ait à aller chercher la procédure dans le wiki.

Déclencheur : le correctif de steamicc/DAPLink#10 (release DAPLink 2026-11-25) n'apporte le bouton « Redémarrer la carte » qu'aux cartes mises à jour ; toutes les cartes distribuées ont un DAPLink plus ancien.

## Objectifs

- À la connexion de la carte, savoir si son DAPLink est plus ancien que la release connue de l'image, sans action de l'utilisateur et sans effet sur la carte.
- Si c'est le cas, l'annoncer dans la page et guider la mise à jour (étape B), puis, si l'essai C réussit, la faire presque toute seule depuis la page (étape C).
- Fonctionner dès aujourd'hui pour les cartes déjà distribuées : elles doivent être reconnues comme anciennes.

## Non-objectifs

- Mise à jour en un clic par WebUSB (option A écartée : demanderait de modifier le bootloader, risque de briquer une carte, et les cartes existantes auraient de toute façon l'ancien bootloader).
- Mise à jour du bootloader, de la stack radio du STM32WB55 ou du programme de l'élève.
- Suivi automatique des releases DAPLink par un workflow (le numéro est épinglé à la main dans l'image pour l'instant).
- Firefox/Safari : sans WebUSB, la page ne voit pas la carte ; le wiki reste la référence.

## Anti-objectifs (échec même si « ça marche »)

- Mettre à jour sans clic explicite de l'utilisateur.
- Bloquer ou retarder le téléversement d'un programme : l'encart est une proposition, jamais un préalable.
- Proposer de « mettre à jour » vers une version plus ancienne (carte de développement ou plus récente que l'image).
- Gêner les autres outils qui lisent le DAPLink (pyOCD, Mbed, etc.).

## Contraintes constatées

- `DAP_Info` « Product Firmware Version » renvoie `info_get_version()` = `DAPLINK_VERSION` sur 4 chiffres : `0259` dans l'ancien firmware comme dans le nouveau. Le descripteur USB `bcdDevice` vaut 1.00. Seul `DETAILS.TXT` (Git SHA, Build ID) distingue les builds, et la page ne peut pas le lire sans accès au lecteur.
- Le firmware d'interface ne peut pas se remplacer lui-même ; la mise à jour passe par le bootloader (lecteur MAINTENANCE), qui n'a que l'USB MSC (`module_bl` : usb-core + usb-msc) : WebUSB ne le voit pas. On y entre en créant `START_BL.ACT` sur le lecteur de la carte.
- Une commande vendeur que le DAPLink ne connaît pas (`ID_DAP_Vendor5` à `31`, `default`) répond un seul octet : son code de commande. Le reste du paquet (64 octets) contient ce qui traînait dans le tampon : il ne faut pas s'y fier.
- DAP.js 2.3.0 expose `send(commande, données)` : la page peut envoyer une commande vendeur.
- La release DAPLink est faite par `.github/workflows/generate_release.yml` à chaque push sur `release_letssteam`, nommée par la date (`AAAA-MM-JJ`), avec `stm32f103xb_steami32_if_crc.bin` parmi les fichiers.
- Ne pas changer la chaîne `0259` : des outils hôtes la lisent comme un nombre.
- Un seul firmware pour toutes les révisions (V1a, V1b, V1c) : confirmé par l'utilisateur. Le redémarrage par nRESET (#10) n'a été vérifié que sur une V1c (V1a : tampon 74LVC1G07 ; V1b/V1c : MOSFET).
- Le numéro de série USB d'un DAPLink commence par l'identifiant de carte : `0839` pour la STeaMi (ex. `08390001066f…`). La page demande à Chrome tout périphérique de vendor ID `0x0d28` : une micro:bit ou une autre carte DAPLink peut être connectée.
- `START_BL.ACT` n'agit que si le réglage « automation allowed » du DAPLink est actif (`vfs_user.c`) ; il l'est par défaut (`settings_rom.c`). La procédure a fonctionné sur la V1c de l'utilisateur.
- Les chemins `/firmware.bin` et `/firmware.json` servent déjà le programme de l'élève ; l'élément `#encart` de la page est déjà pris (WebUSB indisponible).

## Approches considérées

- **A — un clic par WebUSB** : commande « passer en bootloader » + WebUSB dans le bootloader. Écartée (voir non-objectifs).
- **B — détection + mise à jour guidée** : petite commande vendeur côté DAPLink pour annoncer la date de release ; la page compare et affiche les étapes avec un bouton de téléchargement. Choisie par l'utilisateur, en premier.
- **C — B + accès aux dossiers de Chrome** (`showDirectoryPicker`) : la page écrit elle-même `START_BL.ACT` sur le lecteur de la carte puis le firmware sur MAINTENANCE ; deux choix de dossier. Choisie par l'utilisateur, après B, sous réserve d'un essai jetable (Chrome peut refuser d'écrire à la racine d'un lecteur, surtout sous Windows).

## Conception

### 1. DAPLink : commande « version STeaMi »

- Nouvelle commande vendeur, `ID_DAP_Vendor31` (`0x9F`), choisie loin des commandes que DAPLink amont pourrait utiliser. *(Mon choix.)*
- Réponse : `0x9F`, puis la marque ASCII `STM1`, puis le **numéro de release** (`uint32` petit-boutiste) et la **date** de release (`uint32` `AAAAMMJJ`, ex. `20261126`). La marque évite de prendre un reste de tampon d'un ancien DAPLink pour une réponse. *(Mon choix ; le format exact est laissé au constructeur tant que la marque, le numéro et la date y sont.)*
- **Nommage des releases (décidé par l'utilisateur) :** la date suivie du numéro d'exécution de la CI, `AAAA-MM-JJ.N` (ex. `2026-11-26.37`, `N` = `github.run_number` de `generate_release.yml`). Deux releases du même jour ont ainsi des noms et des numéros différents, et une release existante n'est jamais réécrite. La release `2026-11-25` déjà publiée garde son nom.
- Le numéro et la date viennent de définitions de compilation (ex. `STEAMI_RELEASE_NUMBER`, `STEAMI_RELEASE_DATE`) que `generate_release.yml` fixe avant les étapes de compilation, avec les mêmes valeurs que le nom de la release. Un build local sans ces définitions répond le numéro `0` (« build de développement »).
- Pas de changement de `DAPLINK_VERSION`, de `DETAILS.TXT`, du bootloader.
- Travail confié à la session wiki-steami-71, qui a l'environnement de build et a fait #10 ; issue + PR dans `steamicc/DAPLink`, fusion par l'utilisateur. *(Mon choix, à confirmer avec elle.)*

### 2. Page Téléverser (image)

- **Identité d'abord** *(mon choix)* : si le numéro de série USB (`device.serialNumber`) ne commence pas par `0839`, ce n'est pas une STeaMi : aucune détection, aucun encart.
- Après `connect()` et le réglage de la console, la page envoie `0x9F`, avant de lancer la lecture série (pas d'échange concurrent, comme pour `reset()`).
  - Réponse trop courte ou marque absente → DAPLink « ancien » (toutes les cartes distribuées aujourd'hui, y compris celles qui ont déjà la release `2026-11-25`). Une réponse d'un seul octet n'est pas une erreur.
  - Numéro `0` → build de développement : aucun encart.
  - Numéro < numéro épinglé dans l'image → « ancien ».
  - Numéro ≥ numéro épinglé → rien.
  - Erreur pendant l'échange → rien (la page continue comme avant) ; l'erreur n'est pas affichée à l'élève.
- La logique de décision est une fonction pure dans `support.js`, testée avec `node --test`.
- Encart non bloquant, distinct de l'encart WebUSB existant, sous l'état de la carte : « Une mise à jour du DAPLink de cette carte est disponible (release AAAA-MM-JJ.N). » avec **Mettre à jour…** et **Plus tard**. « Plus tard » masque l'encart jusqu'au rechargement de la page. *(Texte et emplacement : mon choix ; le texte ne promet pas « Redémarrer la carte », que certaines cartes ont déjà.)*
- **B** : « Mettre à jour… » déplie les étapes : 1) bouton **Télécharger le firmware** (fichier servi par la page) ; 2) créer un fichier vide `START_BL.ACT` sur le lecteur de la carte : il devient MAINTENANCE ; 3) copier le fichier sur MAINTENANCE et attendre le retour du lecteur ; 4) reconnecter la carte. Si MAINTENANCE n'apparaît pas, un lien renvoie au dépannage du wiki. La page perd la carte à l'étape 2 (événement `disconnect` déjà géré) ; à la reconnexion, la détection tourne de nouveau et l'encart disparaît si la mise à jour a réussi.
- Le firmware est **embarqué dans l'image**, épinglé : `ARG` avec le nom de la release (`AAAA-MM-JJ.N`) et le SHA256 du `stm32f103xb_steami32_if_crc.bin`, téléchargé depuis la release GitHub au build et vérifié ; servi par `steami_serveur.py` sous un préfixe propre (ex. `/daplink/firmware.bin`, `/daplink/firmware.json`), sans collision avec `/firmware.bin` et `/firmware.json` du programme de l'élève. Le JSON (nom et numéro de release, taille, SHA256) donne à la page le numéro épinglé. Même origine que la page, ce qui sert aussi à C. *(Mon choix : les releases GitHub n'envoient pas d'en-têtes CORS, et une image publiée ne change plus.)*
- Le smoke-test de l'image vérifie la présence du fichier, sa taille et son SHA256.
- Nouvelle image `2026.11.8` (ou suivante), puis PR `chore/image-…` dans le template.

### 3. Essai C (jetable, après B)

- Page de test minimale qui, sur clic : `showDirectoryPicker({ mode: 'readwrite' })` sur le lecteur de la carte, lit `DETAILS.TXT`, écrit `START_BL.ACT` ; puis, sur second clic, choix du lecteur MAINTENANCE et écriture du firmware.
- À vérifier sous Linux (ici, avec l'accord de la session qui a la carte) et sous Windows (par l'utilisateur) : Chrome accepte-t-il la racine du lecteur, l'écriture aboutit-elle à un firmware valide, combien de fenêtres de permission voit-on ?
- Si l'essai réussit, C devient une évolution de la page conçue à partir de ce qu'il a appris, et repasse par une validation ; sinon B reste la solution.

### 4. Wiki

- `docs/software/arduino/codespace.md` : l'encart de mise à jour dans les étapes du téléversement ; la section de dépannage « Le bouton Redémarrer la carte ne fonctionne pas » renvoie à l'encart.
- Pas de modification de `docs/software/daplink.md` (procédure différente : bouton Reset + `.hex`) sans accord de l'utilisateur ; le signaler.

## Essais sur carte réelle

- La carte (V1c de l'utilisateur) est partagée avec la session wiki-steami-71 : ne la prendre qu'après son accord, la lui rendre ensuite.
- Pour voir l'encart, remettre temporairement un ancien DAPLink (la release `2026-11-25`, sans la commande `0x9F`) par MAINTENANCE, puis vérifier : encart affiché, mise à jour guidée, encart disparu après reconnexion. Remettre ensuite la dernière release. *(Mon choix, réversible ; l'utilisateur peut s'y opposer.)*
- Contrôles négatifs : build de développement (numéro 0) sans encart ; dernière release sans encart.

## Laissé au constructeur

- Format binaire exact de la réponse `0x9F` au-delà de la marque et de la date.
- Noms des fonctions, des chemins servis, de l'ARG de l'image.
- Mise en page de l'encart, dans le style actuel de la page.
- Contenu exact des tests, au minimum : identité (`0839` ou non), décision (réponse d'un octet, marque absente, numéro 0, plus ancien, égal, plus récent, erreur), présence et SHA256 du firmware dans l'image.

## Ordre

1. DAPLink : commande `0x9F`, numéro et date de release dans le build, nommage `AAAA-MM-JJ.N` (wiki-steami-71), fusion, release.
2. Image : détection + B, firmware épinglé de la nouvelle release ; publication ; template.
3. Wiki.
4. Essai C, puis décision.
