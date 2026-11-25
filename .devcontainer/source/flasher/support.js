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
  if (
    /transfer error|controlTransfer(In|Out)|transfer(In|Out)|device unavailable|disconnected/i.test(message)
  ) {
    return 'La carte a été débranchée ou elle est utilisée par un autre onglet : rebranchez-la, puis réessayez.';
  }
  return message;
}

// Résultat du bouton « Redémarrer la carte » : ok est la valeur de dap.reset().
// Un DAPLink sans le correctif de steamicc/DAPLink#10 (avant la release
// 2026-11-25) répond que le redémarrage n'a pas eu lieu.
export function messageRedemarrage(ok) {
  if (ok) return 'Carte redémarrée : le programme repart du début.';
  return (
    'Cette carte ne sait pas redémarrer depuis la page : son DAPLink est trop ancien. ' +
    'Débranchez-la puis rebranchez-la, ou mettez à jour son DAPLink.'
  );
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

// Mise à jour du DAPLink : décisions pures, sans accès à la carte.

// Les numéros de série des cartes STeaMi commencent par 0839.
export function estSteami(numeroSerie) {
  return typeof numeroSerie === 'string' && numeroSerie.startsWith('0839');
}

// Réponse (DataView) à la commande vendeur 0x9F : octet 0 = commande répétée,
// octets 1-4 = « STM1 », 5-8 = numéro, 9-12 = date (entiers 32 bits little-endian).
export function lireVersionSteami(reponse) {
  if (!reponse || reponse.byteLength < 13) return null;
  const marque = String.fromCharCode(
    reponse.getUint8(1),
    reponse.getUint8(2),
    reponse.getUint8(3),
    reponse.getUint8(4),
  );
  if (marque !== 'STM1') return null;
  return { numero: reponse.getUint32(5, true), date: reponse.getUint32(9, true) };
}

export function lireFirmwareEpingle(json) {
  if (!json || typeof json.release !== 'string') return null;
  if (!Number.isInteger(json.numero) || json.numero <= 0) return null;
  if (!Number.isInteger(json.date) || json.date < 19700101 || json.date > 99991231) return null;
  return { release: json.release, numero: json.numero, date: json.date };
}

export function decisionMiseAJour(version, epingle) {
  if (!version) return 'ancien';
  if (version.numero === 0) return 'dev';
  // Ordre par (date, numéro) : un redémarrage du run_number GitHub ne doit pas
  // transformer une régression en « mise à jour ».
  if (version.date !== epingle.date) return version.date < epingle.date ? 'ancien' : 'a-jour';
  return version.numero < epingle.numero ? 'ancien' : 'a-jour';
}

// La déconnexion (reset de la carte pendant la mise à jour) ne masque jamais l'encart.
export function etatEncartApresDeconnexion(etat) {
  return etat;
}

export function texteMiseAJour(release) {
  return `Une mise à jour du DAPLink de cette carte est disponible (release ${release}).`;
}
