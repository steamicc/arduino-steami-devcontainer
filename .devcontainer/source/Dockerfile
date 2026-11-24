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
      org.opencontainers.image.description="Environnement Arduino STeaMi : PlatformIO, toolchain STM32 et drivers arduino-steami-lib"

# Refuse tout de suite une autre architecture plutôt que d'échouer au milieu.
RUN [ "$(dpkg --print-architecture)" = amd64 ] \
    || { echo "Image amd64 seulement" >&2; exit 1; }

# PlatformIO Core 6.1.19, dans son propre environnement virtuel, avec un lien
# dans /usr/local/bin (le /etc/profile de Debian remet PATH à zéro dans les
# shells de connexion). Pas de télémétrie, pas de vérification de version.
ENV PLATFORMIO_CORE_DIR=/opt/platformio \
    PLATFORMIO_SETTING_ENABLE_TELEMETRY=No \
    PLATFORMIO_SETTING_CHECK_PLATFORMIO_INTERVAL=36500
RUN set -eu; \
    mkdir -p /opt/steami /opt/platformio; \
    python -m venv /opt/steami/venv; \
    /opt/steami/venv/bin/pip install --no-cache-dir platformio==6.1.19; \
    ln -s /opt/steami/venv/bin/pio /usr/local/bin/pio; \
    [ "$(pio --version)" = "PlatformIO Core, version 6.1.19" ]

# Drivers : arduino-steami-lib au tag v0.24.0 (carte, bibliothèques, exemples).
RUN git clone --depth 1 --branch v0.24.0 \
      https://github.com/steamicc/arduino-steami-lib.git /opt/steami/arduino-steami-lib \
    && [ "$(git -C /opt/steami/arduino-steami-lib describe --tags)" = v0.24.0 ]

# Bibliothèque tierce : STM32duinoBLE 1.5.0, pour les exemples ble/.
RUN mkdir -p /opt/steami/libs && pio pkg install --storage-dir /opt/steami/libs -l stm32duino/STM32duinoBLE@1.5.0

# Compilation d'amorçage : télécharge la plateforme, le framework et la
# toolchain dans /opt/platformio ; le résultat de la compilation est jeté.
COPY amorcage /tmp/amorcage
RUN set -eu; \
    cd /tmp/amorcage; \
    pio run -e steami; \
    cd /; \
    rm -rf /tmp/amorcage

# /opt/steami et /opt/platformio appartiennent à vscode : PlatformIO écrit
# <croquis>.ino.cpp dans le dossier de l'exemple, et git refuse un dépôt qui
# appartient à un autre utilisateur.
RUN chown -R vscode:vscode /opt/steami /opt/platformio
