// Kompilasi data Firestore (hub + zona + otomasi) menjadi `down/config` yang dieksekusi hub.
// Dipakai oleh app (mode Spark) dan Cloud Function `syncHubConfig` (mode Blaze) — hasil harus identik.

import { METRICS, PORT_IDS, RELAY_IDS } from './catalog';
import type { AutomationDoc, HubConfig, HubDoc, Threshold, ZoneDoc } from './types';

const TZ_OFFSET_MIN: Record<string, number> = {
  'Asia/Jakarta': 420,
  'Asia/Pontianak': 420,
  'Asia/Makassar': 480,
  'Asia/Jayapura': 540,
};

export function tzOffsetMin(timezone: string): number {
  return TZ_OFFSET_MIN[timezone] ?? 420;
}

export function buildHubConfig(input: {
  hub: Pick<HubDoc, 'ports' | 'relays' | 'configVersion' | 'siteId'>;
  hubId: string;
  timezone: string;
  zones: Record<string, Pick<ZoneDoc, 'thresholds'>>;
  automations: Record<string, Pick<AutomationDoc, 'enabled' | 'hubId' | 'trigger' | 'action' | 'safety'>>;
}): HubConfig {
  const { hub, hubId, timezone, zones, automations } = input;
  if (!hub.siteId) throw new Error(`hub ${hubId} belum diklaim`);

  const cfg: HubConfig = {
    v: hub.configVersion ?? 0,
    siteId: hub.siteId,
    tzOffsetMin: tzOffsetMin(timezone),
    ports: {},
    relays: {},
    alarms: [],
    rules: [],
  };

  for (const p of PORT_IDS) {
    const a = hub.ports?.[p];
    if (!a) continue;
    cfg.ports[p] = { m: a.metric, z: a.zoneId };

    const def = METRICS[a.metric] as { thresholds?: Threshold } | undefined;
    const t: Threshold | undefined = zones[a.zoneId]?.thresholds?.[a.metric] ?? def?.thresholds;
    if (t && (t.warn || t.danger)) {
      cfg.alarms.push({ ch: p, ...(t.warn && { warn: t.warn }), ...(t.danger && { danger: t.danger }) });
    }
  }

  for (const r of RELAY_IDS) {
    const a = hub.relays?.[r];
    if (!a) continue;
    cfg.relays[r] = { k: a.kind, z: a.zoneId, ...(a.levels && { lv: a.levels }) };
  }

  for (const [id, rule] of Object.entries(automations).sort(([a], [b]) => a.localeCompare(b))) {
    if (!rule.enabled || rule.hubId !== hubId) continue;
    if (!referencesExist(rule, cfg)) continue;
    cfg.rules.push({ id, trigger: rule.trigger, action: rule.action, ...(rule.safety && { safety: rule.safety }) });
  }

  return cfg;
}

/** Aturan yang menunjuk port/relay kosong dilewati agar hub tidak menjalankan aturan setengah. */
function referencesExist(rule: Pick<AutomationDoc, 'trigger' | 'action'>, cfg: HubConfig): boolean {
  const chs: string[] = [];
  if (rule.trigger.type === 'threshold') chs.push(rule.trigger.ch);
  if (rule.action.type === 'relay') {
    if (!cfg.relays[rule.action.relay]) return false;
    if (rule.action.until?.type === 'threshold') chs.push(rule.action.until.ch);
  }
  return chs.every((c) => c in cfg.ports);
}
