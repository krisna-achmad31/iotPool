// Path & kunci yang dipakai bersama oleh app, functions, dan (secara manual) firmware.

export const fs = {
  user: (uid: string) => `users/${uid}`,
  fcmToken: (uid: string, token: string) => `users/${uid}/fcmTokens/${token}`,
  site: (siteId: string) => `sites/${siteId}`,
  zones: (siteId: string) => `sites/${siteId}/zones`,
  automations: (siteId: string) => `sites/${siteId}/automations`,
  events: (siteId: string) => `sites/${siteId}/events`,
  hub: (hubId: string) => `hubs/${hubId}`,
  day: (hubId: string, yyyymmdd: string) => `hubs/${hubId}/days/${yyyymmdd}`,
  month: (hubId: string, yyyymm: string) => `hubs/${hubId}/months/${yyyymm}`,
} as const;

export const rtdb = {
  hub: (hubId: string) => `hubs/${hubId}`,
  meta: (hubId: string) => `hubs/${hubId}/meta`,
  acl: (hubId: string) => `hubs/${hubId}/acl`,
  live: (hubId: string) => `hubs/${hubId}/live`,
  config: (hubId: string) => `hubs/${hubId}/down/config`,
  cmds: (hubId: string) => `hubs/${hubId}/down/cmd`,
  ack: (hubId: string, cmdId: string) => `hubs/${hubId}/ack/${cmdId}`,
  firmware: (model: string) => `firmware/${model}`,
} as const;

/** Hub dianggap offline bila `live.ts` lebih tua dari ini. */
export const ONLINE_WINDOW_MS = 90_000;

const pad = (n: number) => String(n).padStart(2, '0');

/** Waktu lokal hub (dari epoch ms + offset menit) → id dokumen & kunci slot. */
export function telemetryKeys(epochMs: number, tzOffsetMin: number) {
  const d = new Date(epochMs + tzOffsetMin * 60_000);
  const y = d.getUTCFullYear(), mo = pad(d.getUTCMonth() + 1), da = pad(d.getUTCDate());
  const h = pad(d.getUTCHours()), m5 = pad(Math.floor(d.getUTCMinutes() / 5) * 5);
  return {
    dayId: `${y}${mo}${da}`,
    date: `${y}-${mo}-${da}`,
    slot: `t${h}${m5}`,
    monthId: `${y}${mo}`,
    month: `${y}-${mo}`,
    hourKey: `d${da}h${h}`,
  };
}
