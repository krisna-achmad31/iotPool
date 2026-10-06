// Firestore → RTDB: config terkompilasi untuk hub, dan ACL anggota site.
// Di mode Spark app melakukan hal yang sama; keduanya idempoten.

import { logger } from 'firebase-functions';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { db, rtdb } from './admin';
import { buildHubConfig } from '../../shared/src/hub-config';
import { rtdb as paths } from '../../shared/src/paths';
import type { AutomationDoc, HubDoc, SiteDoc, ZoneDoc } from '../../shared/src/types';

export async function publishHubConfig(hubId: string): Promise<void> {
  const hubSnap = await db.doc(`hubs/${hubId}`).get();
  const hub = hubSnap.data() as HubDoc | undefined;
  if (!hub?.siteId) return;

  const [siteSnap, zonesSnap, rulesSnap] = await Promise.all([
    db.doc(`sites/${hub.siteId}`).get(),
    db.collection(`sites/${hub.siteId}/zones`).get(),
    db.collection(`sites/${hub.siteId}/automations`).where('hubId', '==', hubId).get(),
  ]);
  const site = siteSnap.data() as SiteDoc | undefined;
  if (!site) return;

  const cfg = buildHubConfig({
    hub,
    hubId,
    timezone: site.timezone,
    zones: Object.fromEntries(zonesSnap.docs.map((d) => [d.id, d.data() as ZoneDoc])),
    automations: Object.fromEntries(rulesSnap.docs.map((d) => [d.id, d.data() as AutomationDoc])),
  });

  const ref = rtdb.ref(paths.config(hubId));
  const current = (await ref.get()).val();
  if (JSON.stringify(current) === JSON.stringify(cfg)) return;
  await ref.set(cfg);
  logger.info('config dipublish', { hubId, v: cfg.v, rules: cfg.rules.length });
}

export const syncConfigOnAutomation = onDocumentWritten('sites/{siteId}/automations/{ruleId}', async (e) => {
  const hubIds = new Set<string>();
  for (const s of [e.data?.before, e.data?.after]) {
    const h = s?.get('hubId');
    if (typeof h === 'string') hubIds.add(h);
  }
  await Promise.all([...hubIds].map(publishHubConfig));
});

export const syncConfigOnZone = onDocumentWritten('sites/{siteId}/zones/{zoneId}', async (e) => {
  const site = (await db.doc(`sites/${e.params.siteId}`).get()).data() as SiteDoc | undefined;
  await Promise.all((site?.hubIds ?? []).map(publishHubConfig));
});

export const syncConfigOnHub = onDocumentWritten('hubs/{hubId}', async (e) => {
  const before = e.data?.before.data() as HubDoc | undefined;
  const after = e.data?.after.data() as HubDoc | undefined;
  if (!after?.siteId) return;
  const relevant = (h?: HubDoc) =>
    JSON.stringify([h?.siteId, h?.ports, h?.relays, h?.configVersion]);
  if (relevant(before) === relevant(after)) return; // abaikan tulisan status dari hub (fw, detected, claim)
  await publishHubConfig(e.params.hubId);
});

export const syncSiteAcl = onDocumentWritten('sites/{siteId}', async (e) => {
  const { siteId } = e.params;
  const before = e.data?.before.data() as SiteDoc | undefined;
  const after = e.data?.after.data() as SiteDoc | undefined;

  const updates: Record<string, unknown> = {};
  for (const hubId of after?.hubIds ?? []) {
    updates[`${paths.acl(hubId)}`] = after!.roles;
    updates[`${paths.meta(hubId)}/siteId`] = siteId;
  }

  const removed = (before?.hubIds ?? []).filter((h) => !after?.hubIds.includes(h));
  for (const hubId of removed) {
    const metaSite = (await rtdb.ref(`${paths.meta(hubId)}/siteId`).get()).val();
    if (metaSite === siteId) updates[paths.acl(hubId)] = null;
  }

  if (Object.keys(updates).length) await rtdb.ref().update(updates);
});
