# arduino-steami-devcontainer

Image du Codespace pour programmer la carte [STeaMi](https://github.com/steamicc) en Arduino, sans rien installer : PlatformIO, la toolchain STM32 et les drivers sont dans l'image : le paquet Arduino [STeaMi](https://github.com/steamicc/arduino-steami), la même bibliothèque que celle de l'Arduino IDE. Compiler ne demande aucun accès réseau.

L'image est publiée sur `ghcr.io/steamicc/arduino-steami-devcontainer`, avec un tag `AAAA.MM.N` (jamais de `latest`). Elle est conçue pour le dépôt modèle `steamicc/arduino-steami-starter`.

## Pour les élèves et les enseignants

Dans le dépôt modèle, choisissez **« Use this template »**, puis **« Create a new repository »** (et non « Open in a codespace ») : vous obtenez votre propre dépôt, où votre travail est sauvegardé. Ouvrez ensuite un Codespace sur ce dépôt.

Les commandes disponibles dans le terminal :

| Commande | Rôle |
| --- | --- |
| `steami-exemples [filtre]` | liste les exemples de la bibliothèque, sous la forme `COMPOSANT/Exemple` (les noms du menu Exemples de l'Arduino IDE) |
| `steami-compiler [COMPOSANT/Exemple]` | compile votre programme (`src/`), ou un exemple tel quel |
| `steami-copier COMPOSANT/Exemple` | copie un exemple dans `src/` pour le modifier |
| `steami-televerser` | prépare l'envoi sur la carte : page « Téléverser » (Chrome ou Edge, avec console série) ou glisser-déposer de `.steami/firmware.bin` sur le lecteur STEAMI |
| `steami-sauver ["message"]` | sauvegarde le travail sur GitHub |
| `steami-serveur start\|stop\|status` | gère le serveur de la page « Téléverser » (port 8080) |

Exemples de référence : `LIS2MDL/BasicReader` et `BLE/BleBeacon` (ce dernier demande une V1a ou une V1b). Les noms s'écrivent comme dans le menu Exemples de l'Arduino IDE, mais la casse n'a pas d'importance : `lis2mdl/basicreader` fonctionne aussi.

En fin de séance, arrêtez le Codespace (indicateur « Codespaces » en bas à gauche, puis « Stop Current Codespace » ; sans activité, il s'arrête seul au bout de 30 minutes par défaut) : un Codespace allumé consomme le quota.

Le terminal est **zsh avec oh-my-zsh**. L'historique des commandes est conservé, même après l'arrêt du Codespace, dans `/workspaces/.zsh_history` (et `/workspaces/.bash_history` pour bash) : ce dossier est hors du dépôt, rien n'est commité. Le serveur SSH est présent : `gh codespace ssh` et `gh codespace logs` fonctionnent.

L'image installe aussi **Copilot Chat sans complétion automatique** : l'élève écrit son code lui-même et Copilot ne répond que dans le chat, où il joue le rôle de tuteur cadré par les instructions du dépôt (`AGENTS.md`, `.github/copilot-instructions.md`).

## Contenu du dépôt

| Chemin | Rôle |
| --- | --- |
| `.devcontainer/source/` | tout ce qui fabrique l'image : `Dockerfile`, commandes `steami-*`, historique du shell (`steami-historique.sh`), serveur et page « Téléverser » (`flasher/`), projet d'amorçage, `devcontainer.json` de construction sur place |
| `.devcontainer/devcontainer.json` | configuration distribuée de ce dépôt : elle télécharge l'image publiée |
| `.devcontainer/smoke-test.sh` | test de fumée lancé dans l'image avant toute publication |
| `exemples/devcontainer.json` | modèle de configuration pour le dépôt `arduino-steami-starter` |
| `tests/` | tests des commandes (bats), du serveur (Python) et de la page (Node) |
| `.github/workflows/` | `devcontainer.yml` (tests et build), `devcontainer-publish.yml` (publication) et `suivre-paquet.yml` (PR automatique quand le paquet STeaMi publie une release) |

## Contribuer

Les tests, la construction locale, la publication d'une nouvelle image et la mise à jour du paquet des drivers sont décrits dans [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

Voir [LICENSE](LICENSE). DAP.js 2.3.0 est embarqué dans `flasher/vendor` avec sa licence.
