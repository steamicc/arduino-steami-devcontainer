// Page « Téléverser » : relie le DOM à DAP.js (global DAPjs, vendor/dap.umd.js).
import { TamponLignes } from './console.js';
import { etatWebUSB, messageErreur, resumeProgramme } from './support.js';

const $ = (id) => document.getElementById(id);
const VENDOR_ID_DAPLINK = 0x0d28;
const BAUDS = 115200;

const tampon = new TamponLignes();
let dap = null;
let boucle = null; // promesse de startSerialRead, jamais attendue au démarrage
let programme = null; // contenu de /firmware.json, ou null
let occupe = false;

function afficher(texte) {
  $('message').textContent = texte;
}

function ajouterConsole(texte) {
  const console_ = $('console');
  const colle = console_.scrollTop + console_.clientHeight >= console_.scrollHeight - 4;
  console_.textContent += texte;
  if (colle) console_.scrollTop = console_.scrollHeight;
}

function majBoutons() {
  $('televerser').disabled = !dap || !programme || occupe;
  $('connecter').disabled = occupe;
}

function etatNonConnectee() {
  dap = null;
  boucle = null;
  $('etat').textContent = 'Carte non connectée';
  $('progression').value = 0;
  majBoutons();
}

function demarrerSerie() {
  boucle = dap.startSerialRead(10).catch((err) => {
    afficher(messageErreur(err));
    etatNonConnectee();
  });
}

async function arreterSerie() {
  if (!boucle) return;
  dap.stopSerialRead();
  await boucle;
  boucle = null;
}

async function rafraichirBandeau() {
  try {
    const rep = await fetch('/firmware.json', { cache: 'no-store' });
    programme = rep.ok ? await rep.json() : null;
  } catch {
    programme = null;
  }
  $('bandeau').textContent = resumeProgramme(programme);
  majBoutons();
}

async function connecter() {
  occupe = true;
  majBoutons();
  try {
    const device = await navigator.usb.requestDevice({ filters: [{ vendorId: VENDOR_ID_DAPLINK }] });
    const nouvelle = new DAPjs.DAPLink(new DAPjs.WebUSB(device));
    nouvelle.on(DAPjs.DAPLink.EVENT_PROGRESS, (p) => {
      $('progression').value = p;
    });
    nouvelle.on(DAPjs.DAPLink.EVENT_SERIAL_DATA, (donnees) => {
      const lignes = tampon.ajouter(donnees);
      if (lignes.length) ajouterConsole(lignes.join('\n') + '\n');
    });
    await nouvelle.connect();
    await nouvelle.setSerialBaudrate(BAUDS);
    dap = nouvelle;
    $('etat').textContent = 'Carte connectée';
    afficher('');
    demarrerSerie();
  } catch (err) {
    afficher(messageErreur(err));
    etatNonConnectee();
  } finally {
    occupe = false;
    majBoutons();
  }
}

async function televerser() {
  occupe = true;
  majBoutons();
  try {
    await arreterSerie();
    $('progression').value = 0;
    afficher('Téléversement en cours…');
    const rep = await fetch('/firmware.bin', { cache: 'no-store' });
    if (!rep.ok) throw new Error('Programme introuvable : lancez steami-compiler.');
    const donnees = await rep.arrayBuffer();
    if (programme && donnees.byteLength !== programme.taille) {
      await rafraichirBandeau();
      afficher('Le programme vient de changer : cliquez à nouveau sur Téléverser.');
      return;
    }
    await dap.flash(donnees);
    // Sans ce reset, la carte ne redémarre pas.
    await new Promise((r) => setTimeout(r, 1000));
    await dap.reset();
    afficher('Programme téléversé.');
  } catch (err) {
    afficher(messageErreur(err));
  } finally {
    // Relance la lecture série si la carte est toujours là.
    if (dap && !boucle) demarrerSerie();
    occupe = false;
    majBoutons();
  }
}

function afficherEncart() {
  const etat = etatWebUSB(navigator, window.top === window.self);
  if (etat === 'ok') return true;
  const encart = $('encart');
  encart.hidden = false;
  encart.textContent =
    etat === 'iframe'
      ? "Cette page est affichée dans un aperçu, où l'USB est interdit. Ouvrez-la dans un onglet du navigateur (Chrome ou Edge), ou copiez le programme sur le lecteur de la carte avec steami-copier."
      : "Ce navigateur ne sait pas parler à la carte en USB. Utilisez Chrome ou Edge, ou copiez le programme sur le lecteur de la carte (le disque qui apparaît quand elle est branchée) avec steami-copier.";
  $('connecter').disabled = true;
  return false;
}

$('connecter').addEventListener('click', connecter);
$('televerser').addEventListener('click', televerser);
$('effacer').addEventListener('click', () => {
  tampon.vider();
  $('console').textContent = '';
});

if (afficherEncart()) {
  navigator.usb.addEventListener('disconnect', () => {
    if (!dap) return;
    afficher('La carte a été débranchée.');
    etatNonConnectee();
  });
}

rafraichirBandeau();
setInterval(rafraichirBandeau, 3000);
