import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import {
  assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { get, push, ref, remove, serverTimestamp, set, update } from 'firebase/database';

const HUB = 'SYN-0A41';
const HUB_AUTH = 'hubauth-0a41';
const NONCE = 'n0nce-from-ble-0123456789';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sysnergi',
    database: { rules: readFileSync('database.rules.json', 'utf8'), host: '127.0.0.1', port: 9000 },
  });
});
afterAll(() => env.cleanup());

const as = (uid: string) => env.authenticatedContext(uid).database();
const pushCmd = (uid: string, body: object) => Promise.resolve(push(ref(as(uid), `hubs/${HUB}/down/cmd`), body));

beforeEach(async () => {
  await env.clearDatabase();
  await env.withSecurityRulesDisabled((ctx) => set(ref(ctx.database(), `hubs/${HUB}`), {
    meta: { authUid: HUB_AUTH },
    claim: { nonce: NONCE, exp: Date.now() + 600_000 },
  }));
});

async function seedClaimed() {
  await env.withSecurityRulesDisabled((ctx) => update(ref(ctx.database(), `hubs/${HUB}`), {
    claim: null,
    meta: { authUid: HUB_AUTH, ownerUid: 'darto', claimNonce: NONCE, siteId: 'siteDarto' },
    acl: { darto: 'owner', joko: 'operator', sari: 'viewer' },
  }));
}

const claimUpdate = (uid: string, nonce = NONCE) => ({
  [`hubs/${HUB}/meta/ownerUid`]: uid,
  [`hubs/${HUB}/meta/claimNonce`]: nonce,
  [`hubs/${HUB}/meta/siteId`]: 'siteDarto',
  [`hubs/${HUB}/acl`]: { [uid]: 'owner' },
});

describe('klaim (RTDB)', () => {
  it('berhasil dengan nonce benar', async () => {
    await assertSucceeds(update(ref(as('darto')), claimUpdate('darto')));
  });
  it('gagal dengan nonce salah', async () => {
    await assertFails(update(ref(as('darto')), claimUpdate('darto', 'tebak-tebakan-nonce-xxxx')));
  });
  it('gagal bila sudah dimiliki orang lain', async () => {
    await seedClaimed();
    await assertFails(update(ref(as('penyusup')), claimUpdate('penyusup')));
  });
  it('user tidak bisa membaca nonce klaim', async () => {
    await assertFails(get(ref(as('darto'), `hubs/${HUB}/claim`)));
  });
});

describe('live & perintah', () => {
  beforeEach(seedClaimed);

  it('hub menulis live; anggota membaca; orang luar tidak', async () => {
    await assertSucceeds(set(ref(as(HUB_AUTH), `hubs/${HUB}/live`), {
      ts: serverTimestamp(), rssi: -58, ch: { P1: { v: 4.1 } }, relays: { R1: { on: true, mode: 'auto' } },
    }));
    await assertSucceeds(get(ref(as('sari'), `hubs/${HUB}/live`)));
    await assertFails(get(ref(as('asing'), `hubs/${HUB}/live`)));
  });
  it('user tidak bisa memalsukan live', async () => {
    await assertFails(set(ref(as('darto'), `hubs/${HUB}/live`), { ts: serverTimestamp() }));
  });

  const cmd = (by: string) => ({ type: 'relay', args: { relay: 'R1', on: true }, by, ts: serverTimestamp(), expSec: 60 });

  it('operator mengirim perintah; viewer tidak', async () => {
    await assertSucceeds(pushCmd('joko', cmd('joko')));
    await assertFails(pushCmd('sari', cmd('sari')));
  });
  it('perintah harus atas nama pengirim & bertanggal server', async () => {
    await assertFails(pushCmd('joko', cmd('darto')));
    await assertFails(pushCmd('joko', { ...cmd('joko'), ts: 1 }));
  });
  it('hub membaca, meng-ack, lalu menghapus perintah', async () => {
    const r = await pushCmd('darto', cmd('darto'));
    await assertSucceeds(get(ref(as(HUB_AUTH), `hubs/${HUB}/down`)));
    await assertSucceeds(set(ref(as(HUB_AUTH), `hubs/${HUB}/ack/${r.key}`), { ok: true, ts: serverTimestamp() }));
    await assertSucceeds(remove(ref(as(HUB_AUTH), `hubs/${HUB}/down/cmd/${r.key}`)));
    await assertFails(remove(ref(as('sari'), `hubs/${HUB}/ack/${r.key}`)));
    await assertSucceeds(remove(ref(as('darto'), `hubs/${HUB}/ack/${r.key}`)));
  });
  it('config harus untuk siteId hub ini', async () => {
    const cfg = { v: 1, tzOffsetMin: 420, ports: {}, relays: {}, alarms: [], rules: [] };
    await assertSucceeds(set(ref(as('joko'), `hubs/${HUB}/down/config`), { ...cfg, siteId: 'siteDarto' }));
    await assertFails(set(ref(as('joko'), `hubs/${HUB}/down/config`), { ...cfg, siteId: 'lain' }));
    await assertFails(set(ref(as('sari'), `hubs/${HUB}/down/config`), { ...cfg, siteId: 'siteDarto' }));
  });
  it('owner menambah anggota; operator tidak', async () => {
    await assertSucceeds(set(ref(as('darto'), `hubs/${HUB}/acl`), { darto: 'owner', joko: 'operator', sari: 'viewer', budi: 'viewer' }));
    await assertFails(set(ref(as('joko'), `hubs/${HUB}/acl/teman`), 'operator'));
  });
  it('owner melepas hub', async () => {
    await assertSucceeds(update(ref(as('darto')), {
      [`hubs/${HUB}/meta/ownerUid`]: null,
      [`hubs/${HUB}/meta/claimNonce`]: null,
      [`hubs/${HUB}/meta/siteId`]: null,
      [`hubs/${HUB}/acl`]: null,
    }));
  });
  it('hub reset pabrik', async () => {
    await assertSucceeds(update(ref(as(HUB_AUTH)), {
      [`hubs/${HUB}/meta/ownerUid`]: null,
      [`hubs/${HUB}/meta/claimNonce`]: null,
      [`hubs/${HUB}/meta/siteId`]: null,
      [`hubs/${HUB}/acl`]: null,
    }));
  });
});
