"""Tests de .github/scripts/regles_image.py (numéro de l'image et filtres de chemins)."""

import importlib.util
import pathlib
import subprocess
import sys
import unittest

CHEMIN = (
    pathlib.Path(__file__).resolve().parent.parent
    / ".github"
    / "scripts"
    / "regles_image.py"
)
spec = importlib.util.spec_from_file_location("regles_image", CHEMIN)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


def T(*versions):
    return [f"devcontainer-{v}" for v in versions]


def commande(*args, entree=""):
    return subprocess.run(
        [sys.executable, str(CHEMIN), *args],
        check=False,
        input=entree,
        capture_output=True,
        text=True,
    )


class DerniereVersionTest(unittest.TestCase):
    def test_comparaison_numerique(self):
        self.assertEqual(
            r.derniere_version(T("2026.11.9", "2026.11.11", "2026.11.10")), "2026.11.11"
        )

    def test_aucun_tag_de_l_image(self):
        self.assertIsNone(r.derniere_version(["v9.9.9", "devcontainer-latest"]))
        self.assertIsNone(r.derniere_version([]))


class ProchaineVersionTest(unittest.TestCase):
    def test_meme_mois(self):
        self.assertEqual(
            r.prochaine_version(T("2026.11.9", "2026.11.11", "2026.11.10"), "2026.11"),
            "2026.11.12",
        )

    def test_nouveau_mois(self):
        self.assertEqual(r.prochaine_version(T("2026.11.11"), "2026.12"), "2026.12.1")

    def test_changement_d_annee(self):
        self.assertEqual(r.prochaine_version(T("2026.12.4"), "2027.01"), "2027.01.1")

    def test_aucun_tag(self):
        self.assertEqual(r.prochaine_version([], "2026.11"), "2026.11.1")

    def test_tag_pele_et_autres_tags_ignores(self):
        lignes = [
            "devcontainer-2026.11.4^{}",
            "v9.9.9",
            "devcontainer-latest",
            "devcontainer-2026.11.4",
        ]
        self.assertEqual(r.prochaine_version(lignes, "2026.11"), "2026.11.5")

    def test_jamais_en_arriere(self):
        self.assertRaises(ValueError, r.prochaine_version, T("2026.12.1"), "2026.11")

    def test_mois_sur_deux_chiffres(self):
        self.assertRaises(ValueError, r.prochaine_version, [], "2026.1")


class ChangeLImageTest(unittest.TestCase):
    def test_entrees_de_l_image(self):
        self.assertTrue(r.change_l_image([".devcontainer/source/Dockerfile"]))
        self.assertTrue(r.change_l_image(["README.md", ".devcontainer/smoke-test.sh"]))

    def test_pr_des_configurations_sans_nouvelle_image(self):
        # Anti-boucle : la PR qui recopie la version publiée ne relance pas d'image.
        self.assertFalse(
            r.change_l_image(
                [".devcontainer/devcontainer.json", "exemples/devcontainer.json"]
            )
        )

    def test_aucun_chemin(self):
        self.assertFalse(r.change_l_image([]))


class ConstruireEnPrTest(unittest.TestCase):
    def test_documentation_seule(self):
        self.assertFalse(
            r.construire_en_pr(
                ["README.md", "docs/superpowers/plans/x.md", "CONTRIBUTING.md"]
            )
        )

    def test_configurations_seules(self):
        self.assertFalse(
            r.construire_en_pr(
                [".devcontainer/devcontainer.json", "exemples/devcontainer.json"]
            )
        )

    def test_tests_scripts_et_robots(self):
        self.assertFalse(
            r.construire_en_pr(
                [
                    "tests/commandes.bats",
                    ".github/scripts/regles_image.py",
                    ".github/workflows/tag-image.yml",
                    ".github/workflows/suivre-paquet.yml",
                ]
            )
        )

    def test_workflow_de_construction(self):
        self.assertTrue(r.construire_en_pr([".github/workflows/devcontainer.yml"]))

    def test_une_entree_suffit(self):
        self.assertTrue(
            r.construire_en_pr(["README.md", ".devcontainer/source/steami-compiler"])
        )

    def test_entree_l_emporte_sur_les_motifs_sans_effet(self):
        self.assertTrue(r.construire_en_pr([".devcontainer/source/x.md"]))
        self.assertTrue(r.change_l_image([".devcontainer/source/x.md"]))

    def test_dans_le_doute_on_construit(self):
        self.assertTrue(r.construire_en_pr(["inconnu/fichier"]))
        self.assertTrue(r.construire_en_pr([]))


class CommandeTest(unittest.TestCase):
    def test_prochaine(self):
        res = subprocess.run(
            [sys.executable, CHEMIN, "prochaine", "2026.11"],
            input="devcontainer-2026.11.11\n",
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual((res.returncode, res.stdout), (0, "2026.11.12\n"))

    def test_derniere(self):
        res = commande(
            "derniere",
            entree="devcontainer-2026.11.9\ndevcontainer-2026.11.12\nv1.0.0\n",
        )
        self.assertEqual((res.returncode, res.stdout), (0, "2026.11.12\n"))

    def test_derniere_sans_tag_n_affiche_rien(self):
        res = commande("derniere", entree="v1.0.0\n")
        self.assertEqual((res.returncode, res.stdout), (0, ""))

    def test_pr(self):
        res = commande("pr", entree="README.md\n.devcontainer/source/Dockerfile\n")
        self.assertEqual((res.returncode, res.stdout), (0, "true\n"))
        res = commande("pr", entree="README.md\ntests/commandes.bats\n")
        self.assertEqual((res.returncode, res.stdout), (0, "false\n"))
        res = commande("pr", entree="")
        self.assertEqual((res.returncode, res.stdout), (0, "true\n"))

    def test_tag(self):
        res = commande("tag", entree=".devcontainer/smoke-test.sh\n")
        self.assertEqual((res.returncode, res.stdout), (0, "true\n"))
        res = commande(
            "tag",
            entree=".devcontainer/devcontainer.json\nexemples/devcontainer.json\n",
        )
        self.assertEqual((res.returncode, res.stdout), (0, "false\n"))

    def test_valueerror_code_1(self):
        res = commande("prochaine", "2026.11", entree="devcontainer-2026.12.1\n")
        self.assertEqual((res.returncode, res.stdout), (1, ""))
        self.assertTrue(res.stderr.startswith("✗ "), res.stderr)
        res = commande("prochaine", "2026.1", entree="")
        self.assertEqual(res.returncode, 1)
        self.assertTrue(res.stderr.startswith("✗ "), res.stderr)

    def test_usage_invalide_code_2(self):
        for args in (
            [],
            ["inconnue"],
            ["prochaine"],
            ["prochaine", "2026.11", "en-trop"],
            ["pr", "en-trop"],
        ):
            with self.subTest(args=args):
                res = commande(*args)
                self.assertEqual((res.returncode, res.stdout), (2, ""))
                self.assertIn("usage", res.stderr)


if __name__ == "__main__":
    unittest.main()
