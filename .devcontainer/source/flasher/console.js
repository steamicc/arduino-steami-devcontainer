// Tampon de lignes pour la console série : le flux arrive par morceaux
// arbitraires, on ne rend que des lignes complètes.
export class TamponLignes {
  #maxLignes;
  #lignes = [];
  #reste = '';

  constructor(maxLignes = 2000) {
    this.#maxLignes = maxLignes;
  }

  // Ajoute un morceau de texte et renvoie les lignes qu'il vient de compléter.
  ajouter(texte) {
    const morceaux = (this.#reste + texte).split('\n');
    this.#reste = morceaux.pop();
    this.#lignes.push(...morceaux);
    if (this.#lignes.length > this.#maxLignes) {
      this.#lignes.splice(0, this.#lignes.length - this.#maxLignes);
    }
    return morceaux;
  }

  vider() {
    this.#lignes = [];
    this.#reste = '';
  }

  get lignes() {
    return [...this.#lignes];
  }
}
