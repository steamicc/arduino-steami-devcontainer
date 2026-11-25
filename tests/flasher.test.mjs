// Tests de la logique pure de la page « Téléverser » (console.js, support.js).
// Lancer : node --test tests/flasher.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';

import { TamponLignes } from '../.devcontainer/source/flasher/console.js';
import {
  decisionMiseAJour,
  estSteami,
  etatEncartApresDeconnexion,
  etatWebUSB,
  lireFirmwareEpingle,
  lireVersionSteami,
  messageErreur,
  messageRedemarrage,
  resumeProgramme,
  texteEncart,
  texteMiseAJour,
} from '../.devcontainer/source/flasher/support.js';

test('TamponLignes : ne renvoie que les lignes complètes', () => {
  const t = new TamponLignes();
  assert.deepEqual(t.ajouter('a\nb'), ['a']);
  assert.deepEqual(t.ajouter('c\n'), ['bc']);
  assert.deepEqual(t.lignes, ['a', 'bc']);
});

test('TamponLignes : retire les lignes les plus anciennes au-delà de 2000', () => {
  const t = new TamponLignes();
  for (let i = 0; i < 2005; i++) t.ajouter(`ligne ${i}\n`);
  assert.equal(t.lignes.length, 2000);
  assert.equal(t.lignes[0], 'ligne 5');
  assert.equal(t.lignes[1999], 'ligne 2004');
});

test('TamponLignes : vider remet le tampon à zéro', () => {
  const t = new TamponLignes();
  t.ajouter('a\nb');
  t.vider();
  assert.deepEqual(t.lignes, []);
  assert.deepEqual(t.ajouter('c\n'), ['c']);
});

test('etatWebUSB', () => {
  assert.equal(etatWebUSB({}, true), 'absent');
  assert.equal(etatWebUSB({ usb: {} }, false), 'iframe');
  assert.equal(etatWebUSB({ usb: {} }, true), 'ok');
});

test('messageErreur : messages de Chrome', () => {
  assert.match(
    messageErreur({ name: 'NotFoundError', message: 'No device selected.' }),
    /Aucune carte choisie/,
  );
  assert.match(
    messageErreur({ name: 'NotFoundError', message: 'The device was disconnected.' }),
    /débranchée/,
  );
  assert.match(
    messageErreur({ name: 'SecurityError', message: 'Access denied.' }),
    /accès à la carte refusé/,
  );
  assert.match(
    messageErreur({ name: 'SecurityError', message: 'Failed ... permissions policy ... usb' }),
    /ouvrir la page dans un onglet/,
  );
  assert.match(
    messageErreur({ name: 'NetworkError', message: 'Unable to claim interface.' }),
    /utilisée par un autre onglet/,
  );
});

test('messageErreur : carte débranchée pendant un transfert', () => {
  const message = "Failed to execute 'controlTransferOut' on 'USBDevice': A transfer error has occurred.";
  for (const name of ['Error', 'NetworkError']) {
    const texte = messageErreur({ name, message });
    assert.ok(texte.includes('débranchée'), texte);
    assert.ok(!texte.includes('Failed to execute'), texte);
  }
});

test('messageRedemarrage : reset() réussi ou DAPLink trop ancien', () => {
  assert.match(messageRedemarrage(true), /Carte redémarrée/);
  const ancien = messageRedemarrage(false);
  assert.match(ancien, /DAPLink est trop ancien/);
  assert.match(ancien, /Débranchez-la puis rebranchez-la/);
});

test('messageErreur : erreur inconnue', () => {
  assert.match(messageErreur({ name: 'Autre', message: 'quelque chose' }), /quelque chose/);
});

test('resumeProgramme', () => {
  assert.equal(resumeProgramme(null), 'Aucun programme compilé : lancez steami-compiler');
  const r = resumeProgramme({ programme: 'src', date: '2026-11-24T10:00:00Z', taille: 20480 });
  assert.match(r, /src/);
  assert.match(r, /20 Ko/);
});

test('texteEncart : le plan B passe par firmware.bin, jamais par steami-copier', () => {
  for (const etat of ['iframe', 'absent']) {
    const texte = texteEncart(etat);
    assert.match(texte, /firmware\.bin/);
    assert.match(texte, /lecteur STEAMI/);
    assert.doesNotMatch(texte, /steami-copier/);
  }
  assert.match(texteEncart('iframe'), /Ports/);
  assert.match(texteEncart('iframe'), /steami-televerser/);
});

function vue(octets) {
  return new DataView(Uint8Array.from(octets).buffer);
}

const STM1 = [0x53, 0x54, 0x4d, 0x31];

test('estSteami : reconnaît le préfixe 0839 du numéro de série', () => {
  assert.equal(estSteami('08390001066fff56'), true);
  assert.equal(estSteami('9904360258994e45'), false);
  assert.equal(estSteami(''), false);
  assert.equal(estSteami(undefined), false);
});

test('lireVersionSteami : lit le numéro et la date (little-endian)', () => {
  const r = vue([0x9f, ...STM1, 0x25, 0, 0, 0, 0x06, 0x29, 0x35, 0x01]);
  assert.deepEqual(lireVersionSteami(r), { numero: 37, date: 20261126 });
});

test('lireVersionSteami : null si la réponse est trop courte', () => {
  assert.equal(lireVersionSteami(vue([0x9f])), null);
  assert.equal(lireVersionSteami(vue([0x9f, ...STM1, 0x25, 0, 0, 0, 0x06, 0x29, 0x35])), null);
});

test('lireVersionSteami : null si 64 octets sans la marque STM1', () => {
  let graine = 12345;
  const alea = () => {
    graine = (graine * 1103515245 + 12345) % 2147483648;
    return graine % 256;
  };
  const octets = [0x9f];
  for (let i = 1; i < 64; i++) octets.push(alea());
  assert.notDeepEqual(octets.slice(1, 5), STM1);
  assert.equal(lireVersionSteami(vue(octets)), null);
});

test('lireFirmwareEpingle : accepte une release, un numéro entier positif et une date AAAAMMJJ', () => {
  assert.deepEqual(lireFirmwareEpingle({ release: '2026-11-26.37', numero: 37, date: 20261126 }), {
    release: '2026-11-26.37',
    numero: 37,
    date: 20261126,
  });
  assert.equal(lireFirmwareEpingle(null), null);
  assert.equal(lireFirmwareEpingle({}), null);
  assert.equal(lireFirmwareEpingle({ release: 'x', numero: 0, date: 20261126 }), null);
  assert.equal(lireFirmwareEpingle({ release: 'x', numero: '37', date: 20261126 }), null);
  assert.equal(lireFirmwareEpingle({ release: 'x', numero: 37 }), null);
  assert.equal(lireFirmwareEpingle({ release: 'x', numero: 37, date: '20261126' }), null);
  assert.equal(lireFirmwareEpingle({ release: 'x', numero: 37, date: 1126 }), null);
});

test('decisionMiseAJour : ancien, dev ou à jour', () => {
  const epingle = { release: '2026-11-26.37', numero: 37, date: 20261126 };
  assert.equal(decisionMiseAJour(null, epingle), 'ancien');
  assert.equal(decisionMiseAJour({ numero: 0, date: 0 }, epingle), 'dev');
  assert.equal(decisionMiseAJour({ numero: 36, date: 20261126 }, epingle), 'ancien');
  assert.equal(decisionMiseAJour({ numero: 37, date: 20261126 }, epingle), 'a-jour');
  assert.equal(decisionMiseAJour({ numero: 38, date: 20261126 }, epingle), 'a-jour');
  // date plus ancienne, numéro plus grand : ancien
  assert.equal(decisionMiseAJour({ numero: 90, date: 20261001 }, epingle), 'ancien');
  // date plus récente, numéro plus petit (run_number repart de 1) : à jour
  assert.equal(decisionMiseAJour({ numero: 3, date: 20261201 }, epingle), 'a-jour');
});

test("etatEncartApresDeconnexion : la déconnexion ne masque jamais l'encart", () => {
  assert.equal(etatEncartApresDeconnexion('etapes'), 'etapes');
  assert.equal(etatEncartApresDeconnexion('propose'), 'propose');
  assert.equal(etatEncartApresDeconnexion('masque'), 'masque');
});

test('texteMiseAJour : mentionne la release', () => {
  assert.ok(texteMiseAJour('2026-11-26.37').includes('2026-11-26.37'));
});
