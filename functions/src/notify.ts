// Event baru di sites/{siteId}/events → push notif FCM ke HP anggota site.

import { logger } from 'firebase-functions';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { db, messaging } from './admin';
import { METRICS } from '../../shared/src/catalog';
import type { EventDoc, HubDoc, SiteDoc } from '../../shared/src/types';

const PUSH_TYPES = new Set<EventDoc['type']>([
  'alarm', 'hub_offline', 'automation_start', 'calibration_due', 'report', 'firmware_available',
]);

function fmt(metric: string | undefined, value: number | undefined): string {
  const def = metric ? (METRICS as Record<string, { unit: string; decimals: number }>)[metric] : undefined;
  if (value == null) return '';
  const v = value.toFixed(def?.decimals ?? 1).replace('.', ',');
  return def?.unit ? `${v} ${def.unit}` : v;
}

function render(ev: EventDoc, hub: HubDoc | undefined): { title: string; body: string } {
  const hubName = hub?.name ?? ev.hubId ?? '';
  if (ev.title) return { title: ev.title, body: ev.body ?? '' };
  const label = ev.metric ? (METRICS as Record<string, { label: string }>)[ev.metric]?.label ?? ev.metric : '';
  const relay = ev.relay ? hub?.relays?.[ev.relay]?.label ?? ev.relay : '';
  switch (ev.type) {
    case 'alarm':
      return {
        title: `${ev.severity === 'danger' ? 'BAHAYA' : 'Waspada'} · ${label}`,
        body: `${label} ${hubName ? `di ${hubName} ` : ''}sekarang ${fmt(ev.metric, ev.value)}.`,
      };
    case 'hub_offline':
      return { title: `${hubName} terputus`, body: 'Aturan tetap jalan di hub. Data dikirim saat online lagi.' };
    case 'automation_start':
      return { title: `${relay || 'Alat'} menyala otomatis`, body: hubName };
    case 'calibration_due':
      return { title: `Waktunya kalibrasi ${label}`, body: `${hubName} · port ${ev.ch}` };
    case 'firmware_available':
      return { title: 'Pembaruan hub tersedia', body: hubName };
    default:
      return { title: 'Sysnergi', body: ev.body ?? '' };
  }
}

export const notifyOnEvent = onDocumentCreated('sites/{siteId}/events/{eventId}', async (e) => {
  const ev = e.data?.data() as EventDoc | undefined;
  if (!ev || !PUSH_TYPES.has(ev.type)) return;
  if (ev.type === 'automation_start' && ev.severity === 'info') return; // terlalu sering untuk push

  const { siteId, eventId } = e.params;
  const site = (await db.doc(`sites/${siteId}`).get()).data() as SiteDoc | undefined;
  if (!site) return;
  const hub = ev.hubId ? ((await db.doc(`hubs/${ev.hubId}`).get()).data() as HubDoc | undefined) : undefined;
  const { title, body } = render(ev, hub);

  const tokenRefs: FirebaseFirestore.DocumentReference[] = [];
  for (const uid of site.memberUids) {
    const tokens = await db.collection(`users/${uid}/fcmTokens`).get();
    tokens.docs.forEach((t) => tokenRefs.push(t.ref));
  }
  if (!tokenRefs.length) return;

  const res = await messaging.sendEachForMulticast({
    tokens: tokenRefs.map((r) => r.id),
    notification: { title, body },
    data: { siteId, eventId, type: ev.type, severity: ev.severity, hubId: ev.hubId ?? '' },
    android: {
      priority: ev.severity === 'danger' ? 'high' : 'normal',
      notification: { channelId: ev.severity === 'danger' ? 'alarm' : 'default' },
    },
    apns: { payload: { aps: { sound: ev.severity === 'danger' ? 'alarm.caf' : 'default' } } },
  });

  const stale = res.responses
    .map((r, i) => (!r.success && /registration-token-not-registered|invalid-registration-token/
      .test(r.error?.code ?? '') ? tokenRefs[i] : null))
    .filter((r): r is FirebaseFirestore.DocumentReference => r !== null);
  await Promise.all(stale.map((r) => r.delete()));

  logger.info('push terkirim', { siteId, eventId, ok: res.successCount, fail: res.failureCount, pruned: stale.length });
});
