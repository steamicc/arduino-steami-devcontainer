# Image du Codespace Arduino STeaMi : PlatformIO, toolchain STM32 et drivers
# sont installés ici, à la construction, pour que compiler ne demande aucun
# accès réseau. Contexte de construction : .devcontainer/source/ (en local,
# en CI et à la publication) ; tous les COPY sont relatifs à ce dossier.
#
# Chaque version est figée à l'exacte : changer une version, c'est publier une
# nouvelle image.
#
# amd64 seulement (architecture de Codespaces).

# Image de base des devcontainers Python 3.12 (Debian bookworm), épinglée sur
# le digest de l'index multi-architecture. Elle fournit l'utilisateur vscode
# (uid 1000), git, curl et sudo. Digest seul, sans le tag devant : la CLI
# devcontainer ne sait pas lire la forme `tag@sha256:...`.
FROM mcr.microsoft.com/devcontainers/python@sha256:589b65db720b03c96d721706005f176ff467ee879f92c2d137c04a537feffa56

# Rattache le paquet publié sur ghcr.io au dépôt de l'image.
LABEL org.opencontainers.image.source="https://github.com/steamicc/arduino-steami-devcontainer" \
      org.opencontainers.image.description="Environnement Arduino STeaMi : PlatformIO, toolchain STM32 et paquet Arduino STeaMi"

# Refuse tout de suite une autre architecture plutôt que d'échouer au milieu.
RUN [ "$(dpkg --print-architecture)" = amd64 ] \
    || { echo "Image amd64 seulement" >&2; exit 1; }

# PlatformIO Core 6.1.19, dans son propre environnement virtuel, avec un lien
# dans /usr/local/bin (le /etc/profile de Debian remet PATH à zéro dans les
# shells de connexion). Pas de télémétrie, pas de vérification de version.
ENV PLATFORMIO_CORE_DIR=/opt/platformio \
    PLATFORMIO_SETTING_ENABLE_TELEMETRY=No \
    PLATFORMIO_SETTING_CHECK_PLATFORMIO_INTERVAL=36500

# /opt/steami et /opt/platformio appartiennent à vscode dès leur création, et
# tout ce qu'on y écrit l'est par vscode (USER vscode) : un chown -R après coup
# réécrirait dans une couche à part ~2 Go de fichiers, et chaque Codespace
# les télécharge deux fois. PlatformIO écrit <croquis>.ino.cpp dans le dossier
# de l'exemple, et git refuse un dépôt qui appartient à un autre utilisateur.
RUN set -eu; \
    mkdir -p /opt/steami /opt/platformio; \
    chown vscode:vscode /opt/steami /opt/platformio; \
    ln -s /opt/steami/venv/bin/pio /usr/local/bin/pio
USER vscode
RUN set -eu; \
    python -m venv /opt/steami/venv; \
    /opt/steami/venv/bin/pip install --no-cache-dir platformio==6.1.19; \
    [ "$(pio --version)" = "PlatformIO Core, version 6.1.19" ]

# Drivers : le paquet Arduino « STeaMi » (steamicc/arduino-steami), le même que
# celui de l'Arduino IDE, au tag fixé par STEAMI_PAQUET (une seule source de
# vérité : le workflow suivre-paquet.yml lit et met à jour cette ligne).
ARG STEAMI_PAQUET=v0.41.0
RUN git clone --depth 1 --branch "$STEAMI_PAQUET" \
      https://github.com/steamicc/arduino-steami.git /opt/steami/libs/STeaMi \
    && [ "$(git -C /opt/steami/libs/STeaMi describe --tags)" = "$STEAMI_PAQUET" ] \
    && grep -qx "version=${STEAMI_PAQUET#v}" /opt/steami/libs/STeaMi/library.properties

# Définition de la carte : absente du paquet, copiée dans le dépôt de l'image
# (copiée depuis boards/steami.json d'arduino-steami-lib v0.30.0, identique en
# v0.34.0 ; à comparer avec le nouveau tag à chaque mise à jour du paquet, voir
# CONTRIBUTING.md).
COPY --chown=vscode:vscode boards /opt/steami/boards

# Bibliothèque tierce : STM32duinoBLE 1.5.0, que le paquet déclare (depends) et
# dont les exemples BLE ont besoin.
RUN mkdir -p /opt/steami/libs && pio pkg install --storage-dir /opt/steami/libs -l stm32duino/STM32duinoBLE@1.5.0

# Compilation d'amorçage : télécharge la plateforme, le framework et la
# toolchain dans /opt/platformio ; le résultat de la compilation est jeté.
COPY --chown=vscode:vscode amorcage /tmp/amorcage
RUN set -eu; \
    cd /tmp/amorcage; \
    pio run -e steami; \
    cd /; \
    rm -rf /tmp/amorcage
USER root

# bats : lance les tests des commandes (tests/commandes.bats) dans l'image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends bats \
    && rm -rf /var/lib/apt/lists/*

# Commandes pour les élèves : steami-commun.sh (fonctions partagées) dans
# /usr/local/lib/steami/, les commandes dans /usr/local/bin. Placé après les
# couches lourdes pour que modifier une commande ne les reconstruise pas.
COPY steami-commun.sh /usr/local/lib/steami/steami-commun.sh
COPY steami_serveur.py /usr/local/lib/steami/steami_serveur.py
COPY steami-exemples steami-compiler steami-copier steami-sauver steami-serveur steami-televerser /usr/local/bin/

# Page « Téléverser » (WebUSB + console série), servie par steami-serveur.
# DAP.js 2.3.0 est embarqué dans flasher/vendor, sans CDN.
COPY --chown=vscode:vscode flasher /opt/steami/flasher

# Firmware DAPLink de la STeaMi, embarqué pour que la page propose la mise à jour
# sans réseau : release et SHA256 fixés ici (le smoke-test les relit).
ARG STEAMI_DAPLINK_RELEASE=2026-11-25.3
ARG STEAMI_DAPLINK_SHA256=73b67af70d7c42ef66589698caca95a89e8bd90b7001bfce0e570c70691287ea
RUN mkdir -p /opt/steami/flasher/daplink \
    && curl -fsSL -o /opt/steami/flasher/daplink/firmware.bin \
      "https://github.com/steamicc/DAPLink/releases/download/${STEAMI_DAPLINK_RELEASE}/stm32f103xb_steami32_if_crc.bin" \
    && echo "${STEAMI_DAPLINK_SHA256}  /opt/steami/flasher/daplink/firmware.bin" | sha256sum -c - \
    && printf '{"release": "%s", "numero": %s, "date": %s, "taille": %s, "sha256": "%s"}\n' \
      "$STEAMI_DAPLINK_RELEASE" "${STEAMI_DAPLINK_RELEASE##*.}" \
      "$(printf '%s' "${STEAMI_DAPLINK_RELEASE%.*}" | tr -d '-')" \
      "$(stat -c %s /opt/steami/flasher/daplink/firmware.bin)" "$STEAMI_DAPLINK_SHA256" \
      > /opt/steami/flasher/daplink/firmware.json \
    && chown -R vscode:vscode /opt/steami/flasher/daplink

# Message d'accueil du premier terminal : l'image de base le lit à cet endroit.
COPY first-run-notice.txt /usr/local/etc/vscode-dev-containers/first-run-notice.txt

# zsh (avec oh-my-zsh, déjà installé dans l'image de base) est le shell de
# vscode. Historique conservé : steami-historique.sh est lu par zsh (zshenv, donc
# avant oh-my-zsh) et par bash (bash.bashrc, lu aussi par les shells de connexion
# via /etc/profile).
COPY steami-historique.sh /usr/local/lib/steami/steami-historique.sh
RUN set -eu; \
    chsh -s /usr/bin/zsh vscode; \
    printf '%s\n' '[ -r /usr/local/lib/steami/steami-historique.sh ] && . /usr/local/lib/steami/steami-historique.sh' \
      | tee -a /etc/zsh/zshenv /etc/bash.bashrc >/dev/null
