import { logger } from 'firebase-functions';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { Timestamp } from 'firebase-admin/firestore';
import { db, rtdb } from './admin';
import { PORT_IDS, type MetricId } from '../../shared/src/catalog';
import { ONLINE_WINDOW_MS } from '../../shared/src/paths';
import type { EventDoc, HubDoc } from '../../shared/src/types';

const OFFLINE_AFTER_MS = 3 * 60_000;      // > ONLINE_WINDOW_MS agar tidak berkedip
const LOOKBACK_MS = 7 * 24 * 3600_000;    // hub mati > 7 hari sudah ditandai sebelumnya

async function siteOf(hubId: string): Promise<string | null> {
  return (await rtdb.ref(`hubs/${hubId}/meta/siteId`).get()).val();
}

function writeEvent(siteId: string, id: string, ev: Omit<EventDoc<Timestamp>, 'source'>) {
  return db.doc(`sites/${siteId}/events/${id}`).set({ ...ev, source: 'server' });
}

/** Tiap 5 menit: tandai hub yang berhenti mengirim `live`, dan yang kembali online. */
export const hubWatchdog = onSchedule({ schedule: 'every 5 minutes', timeZone: 'Asia/Jakarta' }, async () => {
  const now = Date.now();
  const hubs = rtdb.ref('hubs');

  const [stale, flagged] = await Promise.all([
    hubs.orderByChild('live/ts').startAt(now - LOOKBACK_MS).endAt(now - OFFLINE_AFTER_MS).get(),
    hubs.orderByChild('status/offlineSince').startAt(1).get(),
  ]);

  const jobs: Promise<unknown>[] = [];

  stale.forEach((h) => {
    if (h.child('status/offlineSince').exists()) return;
    const hubId = h.key!;
    const lastTs = h.child('live/ts').val() as number;
    jobs.push((async () => {
      await rtdb.ref(`hubs/${hubId}/status`).set({ offlineSince: lastTs });
      const siteId = await siteOf(hubId);
      if (siteId) {
        await writeEvent(siteId, `srv-off-${hubId}-${lastTs}`, {
          ts: Timestamp.fromMillis(lastTs), type: 'hub_offline', severity: 'warning', hubId,
        });
      }
    })());
  });

  flagged.forEach((h) => {
    const ts = h.child('live/ts').val() as number | null;
    if (!ts || now - ts > ONLINE_WINDOW_MS) return;
    const hubId = h.key!;
    jobs.push((async () => {
      await rtdb.ref(`hubs/${hubId}/status`).remove();
      const siteId = await siteOf(hubId);
      if (siteId) {
        await writeEvent(siteId, `srv-on-${hubId}-${ts}`, {
          ts: Timestamp.fromMillis(ts), type: 'hub_online', severity: 'info', hubId,
        });
      }
    })());
  });

  await Promise.all(jobs);
  if (jobs.length) logger.info('watchdog', { changes: jobs.length });
});

const NEEDS_CALIBRATION: MetricId[] = ['do', 'ph', 'nh3_water', 'tds', 'salinity', 'soil_ec'];
const CALIBRATE_EVERY_DAYS = 28;

/** Tiap pagi: ingatkan sensor yang terakhir dikalibrasi > 28 hari lalu (maks sekali seminggu per port). */
export const calibrationReminder = onSchedule({ schedule: '0 8 * * *', timeZone: 'Asia/Jakarta' }, async () => {
  const cutoff = Date.now() - CALIBRATE_EVERY_DAYS * 86_400_000;
  const week = Math.floor(Date.now() / (7 * 86_400_000));
  const snap = await db.collection('hubs').where('siteId', '!=', null).get();

  const jobs: Promise<unknown>[] = [];
  for (const d of snap.docs) {
    const hub = d.data() as HubDoc<Timestamp>;
    for (const p of PORT_IDS) {
      const port = hub.ports?.[p];
      if (!port || !NEEDS_CALIBRATION.includes(port.metric)) continue;
      const at = port.calibratedAt?.toMillis() ?? 0;
      if (at > cutoff) continue;
      jobs.push(writeEvent(hub.siteId!, `srv-cal-${d.id}-${p}-w${week}`, {
        ts: Timestamp.now(), type: 'calibration_due', severity: 'info',
        hubId: d.id, ch: p, metric: port.metric, zoneId: port.zoneId,
      }));
    }
  }
  await Promise.all(jobs);
  logger.info('pengingat kalibrasi', { count: jobs.length });
});
