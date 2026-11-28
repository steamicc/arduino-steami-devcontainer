#!/usr/bin/env python3
"""Règles de l'image : numéro AAAA.MM.N et filtres de chemins.

Bibliothèque standard seulement. Utilisé par :
  - tag-image.yml : `derniere`, `tag` et `prochaine AAAA.MM`, à chaque push sur main ;
  - devcontainer.yml : `pr`, pour sauter la construction quand une PR ne touche pas l'image.

Commande : regles_image.py {derniere | prochaine AAAA.MM | pr | tag}
L'entrée standard donne les tags (sortie de `git tag --list 'devcontainer-*'`)
ou les chemins (sortie de `git diff --name-only`), un par ligne. La commande
affiche la version, ou `true`/`false`. `derniere` n'affiche rien s'il n'y a
aucun tag de l'image.
Code de sortie : 0 si tout va bien, 1 sur une erreur de valeur (message
`✗ …` sur stderr), 2 sur un usage invalide.
"""

import fnmatch
import re
import sys

TAG = re.compile(r"devcontainer-(\d{4})\.(\d{2})\.(\d+)")
MOIS = re.compile(r"(\d{4})\.(\d{2})")

# Chemins sans effet sur l'image ni sur sa construction (fnmatch : `*` traverse
# aussi les `/`). Les entrées de l'image sont testées avant : `.devcontainer/source/x.md`
# reste une entrée.
SANS_IMAGE = (
    "*.md",
    "docs/*",
    "LICENSE",
    ".gitignore",
    "tests/*",
    "exemples/*",
    ".devcontainer/devcontainer.json",
    ".github/scripts/*",
    ".github/workflows/suivre-*.yml",
    ".github/workflows/tag-image.yml",
)

USAGE = "usage : regles_image.py {derniere | prochaine AAAA.MM | pr | tag} < lignes"


def _versions(lignes):
    """(AAAA, MM, N, texte) de chaque tag `devcontainer-AAAA.MM.N` ; le reste est ignoré."""
    for ligne in lignes:
        m = TAG.fullmatch(ligne.strip())
        if m:
            yield int(m[1]), int(m[2]), int(m[3]), ligne.strip()[len("devcontainer-") :]


def derniere_version(lignes):
    """Plus grande version AAAA.MM.N (comparaison numérique), ou None."""
    versions = list(_versions(lignes))
    if not versions:
        return None
    return max(versions)[3]


def prochaine_version(lignes, mois):
    """Version suivante dans le mois AAAA.MM : N+1 si le mois a déjà des tags, sinon 1."""
    m = MOIS.fullmatch(mois)
    if not m or not 1 <= int(m[2]) <= 12:
        raise ValueError(f"mois « {mois} » invalide : le format attendu est AAAA.MM")
    courant = (int(m[1]), int(m[2]))
    versions = list(_versions(lignes))
    if versions:
        plus_recent = max(versions)
        if plus_recent[:2] > courant:
            raise ValueError(
                f"le tag devcontainer-{plus_recent[3]} est postérieur au mois {mois} : "
                "le numéro de l'image ne revient jamais en arrière"
            )
    numeros = [v[2] for v in versions if v[:2] == courant]
    return f"{mois}.{max(numeros) + 1 if numeros else 1}"


def entree_image(chemin):
    """Le Dockerfile et tout `.devcontainer/source/`, plus le smoke-test."""
    return chemin == ".devcontainer/smoke-test.sh" or chemin.startswith(
        ".devcontainer/source/"
    )


def sans_effet(chemin):
    return any(fnmatch.fnmatchcase(chemin, motif) for motif in SANS_IMAGE)


def construire_en_pr(chemins):
    """Filtre des PR, prudent : on construit sauf si chaque chemin est connu pour être sans effet."""
    return not chemins or any(entree_image(c) or not sans_effet(c) for c in chemins)


def change_l_image(chemins):
    """Une entrée de l'image a changé : la fusion produit une nouvelle image (tag)."""
    return any(entree_image(c) for c in chemins)


def main(argv, entree, sortie):
    if (
        not argv
        or argv[0] not in ("derniere", "prochaine", "pr", "tag")
        or len(argv) != (2 if argv[0] == "prochaine" else 1)
    ):
        print(USAGE, file=sys.stderr)
        return 2
    lignes = [ligne.strip() for ligne in entree.read().splitlines() if ligne.strip()]
    try:
        if argv[0] == "derniere":
            version = derniere_version(lignes)
            if version is not None:
                print(version, file=sortie)
        elif argv[0] == "prochaine":
            print(prochaine_version(lignes, argv[1]), file=sortie)
        else:
            regle = construire_en_pr if argv[0] == "pr" else change_l_image
            print("true" if regle(lignes) else "false", file=sortie)
    except ValueError as e:
        print(f"✗ {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], sys.stdin, sys.stdout))
