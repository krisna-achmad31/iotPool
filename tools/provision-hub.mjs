#!/usr/bin/env node
// Provisioning pabrik: satu kali per unit hub. Jalan di paket Spark (Admin SDK dari laptop).
//
//   set GOOGLE_APPLICATION_CREDENTIALS=path\ke\service-account.json
//   npm run provision -- SYN-0A41 [SYN-0C88 ...]
//
// Hasil: akun Auth hub, hubs/{id} di Firestore, hubs/{id}/meta/authUid di RTDB,
// dan file provisioned/{id}.h berisi kredensial untuk di-flash ke hub.

import { randomBytes } from 'node:crypto';
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'autonomous-pond-system';
const DATABASE_URL = process.env.FIREBASE_DATABASE_URL
  ?? `https://${PROJECT_ID}-default-rtdb.asia-southeast1.firebasedatabase.app`;
const HUB_EMAIL_DOMAIN = process.env.HUB_EMAIL_DOMAIN ?? 'hub.sysnergi.app';
const MODEL = process.env.HUB_MODEL ?? 'SYN-HUB-1';

const ids = process.argv.slice(2);
if (!ids.length || ids.some((id) => !/^SYN-[0-9A-F]{4,6}$/.test(id))) {
  console.error('Pakai: npm run provision -- SYN-0A41 [SYN-xxxx ...]');
  process.exit(1);
}

initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID, databaseURL: DATABASE_URL });
const auth = getAuth();
const fs = getFirestore();
const db = getDatabase();

mkdirSync('provisioned', { recursive: true });

for (const hubId of ids) {
  const out = `provisioned/${hubId}.h`;
  if (existsSync(out)) {
    console.log(`${hubId}: sudah pernah diprovisioning (${out}), dilewati.`);
    continue;
  }

  const email = `${hubId.toLowerCase()}@${HUB_EMAIL_DOMAIN}`;
  const password = randomBytes(18).toString('base64url');

  let user;
  try {
    user = await auth.createUser({ email, password, displayName: hubId, emailVerified: true });
  } catch (e) {
    if (e.code !== 'auth/email-already-exists') throw e;
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, { password });
  }
  await auth.setCustomUserClaims(user.uid, { hub: hubId });

  await fs.doc(`hubs/${hubId}`).set({
    authUid: user.uid, model: MODEL, ownerUid: null, siteId: null,
    ports: {}, relays: {}, createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.ref(`hubs/${hubId}/meta/authUid`).set(user.uid);

  writeFileSync(out, [
    `// ${hubId} — JANGAN di-commit. Dibuat ${new Date().toISOString()}`,
    `#define HUB_ID "${hubId}"`,
    `#define HUB_EMAIL "${email}"`,
    `#define HUB_PASSWORD "${password}"`,
    '',
  ].join('\n'));
  console.log(`${hubId}: ok (uid ${user.uid}) → ${out}`);
}

process.exit(0);
