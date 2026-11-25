// Tests de la logique pure de la page « Téléverser » (console.js, support.js).
// Lancer : node --test tests/flasher.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';

import { TamponLignes } from '../.devcontainer/source/flasher/console.js';
import {
  etatWebUSB,
  messageErreur,
  messageRedemarrage,
  resumeProgramme,
  texteEncart,
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
