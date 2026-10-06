import { describe, expect, it } from 'vitest';
import { buildHubConfig, telemetryKeys } from '../shared/src';

describe('telemetryKeys', () => {
  it('memakai waktu lokal WIB untuk id dokumen & slot 5 menit', () => {
    // 2026-10-01 20:37:12 UTC = 2026-10-02 03:37 WIB
    const k = telemetryKeys(Date.UTC(2026, 9, 1, 20, 37, 12), 420);
    expect(k).toEqual({
      dayId: '20261002', date: '2026-10-02', slot: 't0335',
      monthId: '202610', month: '2026-10', hourKey: 'd02h03',
    });
  });
});

describe('buildHubConfig', () => {
  const hub = {
    siteId: 'siteDarto', configVersion: 3,
    ports: {
      P1: { metric: 'do' as const, zoneId: 'kolam2' },
      P5: { metric: 'water_level' as const, zoneId: 'kolam2' },
      P6: null,
    },
    relays: { R1: { kind: 'aerator' as const, label: 'Aerator', zoneId: 'kolam2' }, R3: null },
  };

  const cfg = buildHubConfig({
    hub, hubId: 'SYN-0A41', timezone: 'Asia/Jakarta',
    zones: { kolam2: { thresholds: { do: { warn: { lt: 4.5 }, danger: { lt: 2.5 } } } } },
    automations: {
      r_do_low: {
        enabled: true, hubId: 'SYN-0A41',
        trigger: { type: 'threshold', ch: 'P1', op: 'lt', value: 4 },
        action: { type: 'relay', relay: 'R1', on: true }, safety: { maxRunSec: 7200 },
      },
      r_disabled: {
        enabled: false, hubId: 'SYN-0A41',
        trigger: { type: 'schedule', start: '00:00', end: '05:00' },
        action: { type: 'relay', relay: 'R1', on: true },
      },
      r_relay_kosong: {
        enabled: true, hubId: 'SYN-0A41',
        trigger: { type: 'threshold', ch: 'P5', op: 'lt', value: 70 },
        action: { type: 'relay', relay: 'R2', on: true },
      },
      r_hub_lain: {
        enabled: true, hubId: 'SYN-0C88',
        trigger: { type: 'threshold', ch: 'P1', op: 'lt', value: 4 },
        action: { type: 'notify', severity: 'warning' },
      },
    },
  });

  it('mengompilasi port & relay terpasang saja', () => {
    expect(cfg.ports).toEqual({ P1: { m: 'do', z: 'kolam2' }, P5: { m: 'water_level', z: 'kolam2' } });
    expect(cfg.relays).toEqual({ R1: { k: 'aerator', z: 'kolam2' } });
    expect(cfg.tzOffsetMin).toBe(420);
    expect(cfg.v).toBe(3);
  });
  it('ambang zona meng-override default katalog', () => {
    expect(cfg.alarms).toEqual([{ ch: 'P1', warn: { lt: 4.5 }, danger: { lt: 2.5 } }]);
  });
  it('melewati aturan nonaktif, hub lain, dan yang menunjuk relay kosong', () => {
    expect(cfg.rules.map((r) => r.id)).toEqual(['r_do_low']);
  });
});
