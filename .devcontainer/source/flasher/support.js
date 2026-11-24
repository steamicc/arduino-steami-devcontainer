// Fonctions pures de la page « Téléverser » (sans DOM, testables avec node).

// 'absent' : le navigateur n'a pas WebUSB (Firefox, Safari) ;
// 'iframe' : WebUSB existe mais la page est dans un cadre (aperçu de
// Codespaces), où l'accès USB est interdit.
export function etatWebUSB(nav, estFenetrePrincipale) {
  if (!nav?.usb) return 'absent';
  if (!estFenetrePrincipale) return 'iframe';
  return 'ok';
}

// Traduit les erreurs de Chrome (WebUSB et DAP.js) en français.
export function messageErreur(err) {
  const nom = err?.name || '';
  const message = err?.message || String(err);

  if (nom === 'NotFoundError' && /No device selected/i.test(message)) {
    return 'Aucune carte choisie.';
  }
  if (nom === 'NotFoundError' && /disconnected/i.test(message)) {
    return 'La carte a été débranchée.';
  }
  if (nom === 'SecurityError' && /permissions policy/i.test(message)) {
    return "Le navigateur interdit l'USB dans cet aperçu : ouvrir la page dans un onglet du navigateur.";
  }
  if (nom === 'SecurityError') {
    return "Le navigateur indique : accès à la carte refusé. Autorisez l'USB pour ce site, puis réessayez.";
  }
  if (nom === 'NetworkError' && /claim interface/i.test(message)) {
    return 'La carte est déjà utilisée par un autre onglet ou un autre programme : fermez-le puis réessayez.';
  }
  return message;
}

// Phrase du bandeau : quel programme est prêt à être téléversé.
export function resumeProgramme(json) {
  if (!json) return 'Aucun programme compilé : lancez steami-compiler';
  const ko = Math.round(json.taille / 1024);
  const date = new Date(json.date);
  const quand = Number.isNaN(date.getTime())
    ? json.date
    : date.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'medium' });
  return `Programme prêt : ${json.programme}, ${ko} Ko, compilé le ${quand}`;
}

// Texte de l'encart quand la page ne peut pas parler USB : etat vient de
// etatWebUSB ('iframe' ou 'absent'). Le plan B est le glisser-déposer de
// firmware.bin sur le lecteur STEAMI ; steami-copier ne touche jamais à la carte.
const GLISSER =
  "Clic droit sur .steami/firmware.bin dans l'explorateur du Codespace → Download, puis glissez le fichier sur le lecteur STEAMI (le disque qui apparaît quand la carte est branchée).";

export function texteEncart(etat) {
  if (etat === 'iframe') {
    return (
      "Cette page est affichée dans un aperçu, où l'USB est interdit. " +
      "Ouvrez-la dans un onglet de Chrome ou Edge : onglet Ports, globe de la ligne « Téléverser » (ou l'adresse affichée par steami-televerser). " +
      'Sinon : ' +
      GLISSER
    );
  }
  return 'Ce navigateur ne sait pas parler à la carte en USB. Utilisez Chrome ou Edge. Sinon : ' + GLISSER;
}
