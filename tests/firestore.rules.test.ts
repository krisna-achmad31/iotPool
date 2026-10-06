import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import {
  assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion, collection, doc, getDoc, getDocs, query, setDoc, Timestamp, updateDoc, where, writeBatch,
  type Firestore,
} from 'firebase/firestore';

const HUB = 'SYN-0A41';
const HUB2 = 'SYN-0C88';
const HUB_AUTH = 'hubauth-0a41';
const HUB2_AUTH = 'hubauth-0c88';
const NONCE = 'n0nce-from-ble-0123456789';
const SITE = 'siteDarto';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sysnergi',
    firestore: { rules: readFileSync('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
afterAll(() => env.cleanup());

const now = () => Timestamp.now();
const inMin = (m: number) => Timestamp.fromMillis(Date.now() + m * 60_000);

/** Kondisi awal: Darto punya site; dua hub sudah diprovisioning dan sedang mode pairing. */
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/darto'), { ownedHubIds: [], createdAt: now() });
    await setDoc(doc(db, `sites/${SITE}`), {
      name: 'Kolam Sukamaju', kind: 'aquaculture', ownerUid: 'darto',
      roles: { darto: 'owner', joko: 'operator', sari: 'viewer' },
      memberUids: ['darto', 'joko', 'sari'], hubIds: [], timezone: 'Asia/Jakarta',
      createdAt: now(), updatedAt: now(),
    });
    for (const [id, authUid] of [[HUB, HUB_AUTH], [HUB2, HUB2_AUTH]]) {
      await setDoc(doc(db, `hubs/${id}`), {
        authUid, model: 'SYN-HUB-1', ownerUid: null, siteId: null, ports: {}, relays: {},
        claim: { nonce: NONCE, expiresAt: inMin(10) }, createdAt: now(),
      });
    }
  });
});

const as = (uid: string) => env.authenticatedContext(uid).firestore() as unknown as Firestore;

function claimBatch(db: Firestore, hubId: string, uid: string, nonce = NONCE, siteId = SITE) {
  const b = writeBatch(db);
  b.update(doc(db, `hubs/${hubId}`), { ownerUid: uid, siteId, claimNonce: nonce, claim: null, name: 'Hub Kolam 2' });
  b.update(doc(db, `sites/${siteId}`), { hubIds: arrayUnion(hubId), updatedAt: now() });
  b.update(doc(db, `users/${uid}`), { ownedHubIds: arrayUnion(hubId) });
  return b.commit();
}

async function seedClaimed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await updateDoc(doc(db, `hubs/${HUB}`), { ownerUid: 'darto', siteId: SITE, claim: null, claimNonce: NONCE });
    await updateDoc(doc(db, `sites/${SITE}`), { hubIds: [HUB] });
    await updateDoc(doc(db, 'users/darto'), { ownedHubIds: [HUB] });
  });
}

describe('users', () => {
  it('membuat profil sendiri tanpa field plan', async () => {
    await assertSucceeds(setDoc(doc(as('baru'), 'users/baru'), { ownedHubIds: [], createdAt: now() }));
  });
  it('tidak bisa memberi diri sendiri paket Pro', async () => {
    await assertFails(setDoc(doc(as('baru'), 'users/baru'),
      { ownedHubIds: [], createdAt: now(), plan: { tier: 'pro', hubLimit: 99, aiMonthlyLimit: 999 } }));
    await assertFails(updateDoc(doc(as('darto'), 'users/darto'), { plan: { tier: 'pro', hubLimit: 99 } }));
  });
  it('tidak bisa mengosongkan ownedHubIds selagi masih memiliki hub', async () => {
    await seedClaimed();
    await assertFails(updateDoc(doc(as('darto'), 'users/darto'), { ownedHubIds: [] }));
  });
  it('tidak bisa membaca profil orang lain', async () => {
    await assertFails(getDoc(doc(as('joko'), 'users/darto')));
  });
});

describe('sites', () => {
  it('anggota bisa query site miliknya; orang luar tidak', async () => {
    await assertSucceeds(getDocs(query(collection(as('sari'), 'sites'), where('memberUids', 'array-contains', 'sari'))));
    await assertFails(getDoc(doc(as('asing'), `sites/${SITE}`)));
  });
  it('membuat site baru sebagai owner', async () => {
    await assertSucceeds(setDoc(doc(as('rizal'), 'sites/kandang'), {
      name: 'Kandang Mas Rizal', kind: 'livestock', ownerUid: 'rizal', roles: { rizal: 'owner' },
      memberUids: ['rizal'], hubIds: [], timezone: 'Asia/Jakarta', createdAt: now(), updatedAt: now(),
    }));
  });
  it('operator tidak bisa mengubah anggota', async () => {
    await assertFails(updateDoc(doc(as('joko'), `sites/${SITE}`), {
      roles: { darto: 'owner', joko: 'owner', sari: 'viewer' },
    }));
  });
  it('memberUids harus sama dengan roles', async () => {
    await assertFails(updateDoc(doc(as('darto'), `sites/${SITE}`), { memberUids: ['darto', 'joko', 'sari', 'penyusup'] }));
  });
  it('viewer bisa keluar sendiri', async () => {
    await assertSucceeds(updateDoc(doc(as('sari'), `sites/${SITE}`), {
      roles: { darto: 'owner', joko: 'operator' }, memberUids: ['darto', 'joko'], updatedAt: now(),
    }));
  });
});

describe('klaim hub', () => {
  it('berhasil dengan nonce BLE yang benar', async () => {
    await assertSucceeds(claimBatch(as('darto'), HUB, 'darto'));
  });
  it('gagal dengan nonce salah', async () => {
    await assertFails(claimBatch(as('darto'), HUB, 'darto', 'tebak-tebakan-nonce-xxxx'));
  });
  it('gagal bila token klaim kedaluwarsa', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), `hubs/${HUB}`), { 'claim.expiresAt': inMin(-1) }));
    await assertFails(claimBatch(as('darto'), HUB, 'darto'));
  });
  it('user lain gagal merebut hub yang sudah dimiliki', async () => {
    await seedClaimed();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/rizal'), { ownedHubIds: [], createdAt: now() });
      await setDoc(doc(db, 'sites/kandang'), {
        name: 'Kandang', kind: 'livestock', ownerUid: 'rizal', roles: { rizal: 'owner' },
        memberUids: ['rizal'], hubIds: [], timezone: 'Asia/Jakarta', createdAt: now(), updatedAt: now(),
      });
    });
    await assertFails(claimBatch(as('rizal'), HUB, 'rizal', NONCE, 'kandang'));
  });
  it('gagal tanpa ikut menambah ownedHubIds (mengakali kuota)', async () => {
    const db = as('darto');
    const b = writeBatch(db);
    b.update(doc(db, `hubs/${HUB}`), { ownerUid: 'darto', siteId: SITE, claimNonce: NONCE, claim: null });
    b.update(doc(db, `sites/${SITE}`), { hubIds: arrayUnion(HUB) });
    await assertFails(b.commit());
  });
  it('paket free dibatasi 1 hub', async () => {
    await seedClaimed();
    await assertFails(claimBatch(as('darto'), HUB2, 'darto'));
  });
  it('paket plus boleh 3 hub', async () => {
    await seedClaimed();
    await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'users/darto'),
      { plan: { tier: 'plus', hubLimit: 3, aiMonthlyLimit: 30 } }));
    await assertSucceeds(claimBatch(as('darto'), HUB2, 'darto'));
  });
  it('hub belum diklaim tidak bisa dibaca user mana pun', async () => {
    await assertFails(getDoc(doc(as('darto'), `hubs/${HUB}`)));
  });
});

describe('hub & telemetri', () => {
  beforeEach(seedClaimed);

  const day = (siteId = SITE) => ({
    hubId: HUB, siteId, date: '2026-10-02', tzOffsetMin: 420, s: { t0935: { P1: 4.1, P2: 28.4 } },
  });

  it('hub menulis slot 5 menit miliknya', async () => {
    await assertSucceeds(setDoc(doc(as(HUB_AUTH), `hubs/${HUB}/days/20261002`), day(), { merge: true }));
  });
  it('hub lain tidak bisa menulis ke hub ini', async () => {
    await assertFails(setDoc(doc(as(HUB2_AUTH), `hubs/${HUB}/days/20261002`), day()));
  });
  it('hub tidak bisa memalsukan siteId', async () => {
    await assertFails(setDoc(doc(as(HUB_AUTH), `hubs/${HUB}/days/20261002`), day('siteOrangLain')));
  });
  it('anggota bisa membaca telemetri; orang luar tidak', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `hubs/${HUB}/days/20261002`), day()));
    await assertSucceeds(getDoc(doc(as('sari'), `hubs/${HUB}/days/20261002`)));
    await assertSucceeds(getDocs(query(collection(as('sari'), `hubs/${HUB}/days`), where('siteId', '==', SITE))));
    await assertFails(getDoc(doc(as('asing'), `hubs/${HUB}/days/20261002`)));
  });
  it('hub tidak bisa mengganti pemiliknya sendiri ke user lain', async () => {
    await assertFails(updateDoc(doc(as(HUB_AUTH), `hubs/${HUB}`), { ownerUid: 'penyusup' }));
  });
  it('hub melaporkan modul terdeteksi & firmware', async () => {
    await assertSucceeds(updateDoc(doc(as(HUB_AUTH), `hubs/${HUB}`), {
      detected: { P1: 'do', P2: 'water_temp' }, fw: { version: '1.4.2' },
    }));
  });
  it('operator mengatur port; viewer tidak', async () => {
    const ports = { P1: { metric: 'do', zoneId: 'kolam2' } };
    await assertSucceeds(updateDoc(doc(as('joko'), `hubs/${HUB}`), { ports, configVersion: 1 }));
    await assertFails(updateDoc(doc(as('sari'), `hubs/${HUB}`), { ports }));
  });
  it('hub membuat event alarm dengan id deterministik', async () => {
    const ev = { ts: now(), type: 'alarm', severity: 'danger', source: 'hub', hubId: HUB, ch: 'P1', metric: 'do', value: 3.8 };
    await assertSucceeds(setDoc(doc(as(HUB_AUTH), `sites/${SITE}/events/${HUB}-1790000000000`), ev));
    await assertFails(setDoc(doc(as(HUB_AUTH), `sites/${SITE}/events/acak`), ev));
    await assertFails(setDoc(doc(as(HUB2_AUTH), `sites/${SITE}/events/${HUB2}-1790000000000`), { ...ev, hubId: HUB2 }));
  });
  it('operator membuat otomasi; viewer tidak', async () => {
    const rule = {
      name: 'Aerator saat oksigen rendah', enabled: true, hubId: HUB, source: 'manual',
      trigger: { type: 'threshold', ch: 'P1', op: 'lt', value: 4 },
      action: { type: 'relay', relay: 'R1', on: true }, createdAt: now(), updatedAt: now(),
    };
    await assertSucceeds(setDoc(doc(as('joko'), `sites/${SITE}/automations/r1`), { ...rule, createdBy: 'joko' }));
    await assertFails(setDoc(doc(as('sari'), `sites/${SITE}/automations/r2`), { ...rule, createdBy: 'sari' }));
  });
  it('owner melepas hub dari akun', async () => {
    const db = as('darto');
    const b = writeBatch(db);
    b.update(doc(db, `hubs/${HUB}`), { ownerUid: null, siteId: null, claimNonce: null, ports: {}, relays: {} });
    b.update(doc(db, `sites/${SITE}`), { hubIds: [] });
    b.update(doc(db, 'users/darto'), { ownedHubIds: [] });
    await assertSucceeds(b.commit());
  });
});
