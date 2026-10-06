// Tipe dokumen Firestore & node RTDB. Lihat docs/data-model.md untuk penjelasan tiap field.
// `TS` = tipe Timestamp dari SDK yang dipakai (firebase-admin / firebase web / RN).

import type { ActuatorKind, MetricId, PortId, RelayId } from './catalog';

export type Role = 'owner' | 'operator' | 'viewer';
export type Severity = 'info' | 'warning' | 'danger';
export type Cmp = 'lt' | 'gt';

export interface Threshold {
  ideal?: readonly [number, number];
  warn?: { lt?: number; gt?: number };
  danger?: { lt?: number; gt?: number };
}

// ───────────────────────── Firestore ─────────────────────────

export interface UserDoc<TS = unknown> {
  displayName?: string;
  phone?: string;
  photoURL?: string;
  prefs?: { largeText?: boolean; alarmSound?: boolean; locale?: 'id' | 'en' };
  readAt?: Record<string, TS>;
  ownedHubIds: string[];
  plan?: { tier: 'free' | 'plus' | 'pro'; validUntil?: TS; hubLimit: number; aiMonthlyLimit: number };
  usage?: { aiMonth: string; aiCount: number };
  createdAt: TS;
}

export interface FcmTokenDoc<TS = unknown> {
  platform: 'android' | 'ios' | 'web';
  updatedAt: TS;
}

export interface SiteDoc<TS = unknown> {
  name: string;
  kind: string;
  ownerUid: string;
  roles: Record<string, Role>;
  memberUids: string[];
  hubIds: string[];
  timezone: string;
  createdAt: TS;
  updatedAt: TS;
}

export interface ZoneDoc {
  name: string;
  kind: string;
  order: number;
  meta?: Record<string, unknown>;
  thresholds?: Partial<Record<MetricId, Threshold>>;
}

export interface ThresholdCond { type: 'threshold'; ch: PortId; op: Cmp; value: number }

export type Trigger =
  | (ThresholdCond & { holdSec?: number })
  | { type: 'schedule'; start: string; end?: string; days?: number[] };

export type Action =
  | {
      type: 'relay';
      relay: RelayId;
      on: boolean;
      level?: number;
      until?: ThresholdCond | { type: 'duration'; sec: number } | { type: 'trigger_clears' };
    }
  | { type: 'notify'; severity: Severity };

export interface AutomationDoc<TS = unknown> {
  name: string;
  enabled: boolean;
  hubId: string;
  trigger: Trigger;
  action: Action;
  safety?: { maxRunSec?: number; cooldownSec?: number };
  source: 'manual' | 'template' | 'ai';
  templateId?: string;
  prompt?: string;
  createdBy: string;
  createdAt: TS;
  updatedAt: TS;
}

export type EventType =
  | 'alarm' | 'alarm_clear'
  | 'automation_start' | 'automation_stop'
  | 'hub_offline' | 'hub_online'
  | 'command' | 'calibration_due' | 'firmware_available'
  | 'report' | 'system';

export interface EventDoc<TS = unknown> {
  ts: TS;
  type: EventType;
  severity: Severity;
  source: 'hub' | 'app' | 'server';
  hubId?: string;
  zoneId?: string;
  ch?: PortId;
  metric?: MetricId;
  value?: number;
  relay?: RelayId;
  ruleId?: string;
  by?: string;
  title?: string;
  body?: string;
}

export interface PortAssignment<TS = unknown> {
  metric: MetricId;
  zoneId: string;
  label?: string;
  calibratedAt?: TS;
  sensorModel?: string;
}

export interface RelayAssignment {
  kind: ActuatorKind;
  label: string;
  zoneId: string;
  levels?: number;
}

export interface HubDoc<TS = unknown> {
  authUid: string;
  model: string;
  hwRev?: string;
  ownerUid: string | null;
  siteId: string | null;
  claim?: { nonce: string; expiresAt: TS } | null;
  claimNonce?: string | null;
  name?: string;
  ports: Partial<Record<PortId, PortAssignment<TS> | null>>;
  relays: Partial<Record<RelayId, RelayAssignment | null>>;
  detected?: Partial<Record<PortId, MetricId | null>>;
  fw?: { version: string; updatedAt?: TS };
  connectivity?: 'wifi' | '4g';
  configVersion?: number;
  createdAt: TS;
}

/** hubs/{hubId}/days/{yyyymmdd} — slot `tHHMM` → { P1: 4.1, ... } */
export interface TelemetryDayDoc {
  hubId: string;
  siteId: string;
  date: string;
  tzOffsetMin: number;
  s: Record<string, Partial<Record<PortId, number>>>;
}

/** hubs/{hubId}/months/{yyyymm} — kunci `dDDhHH` → { P1: [min, avg, max] } */
export interface TelemetryMonthDoc {
  hubId: string;
  siteId: string;
  month: string;
  tzOffsetMin: number;
  h: Record<string, Partial<Record<PortId, [number, number, number]>>>;
}

// ───────────────────────── Realtime Database ─────────────────────────

export interface RtdbHubMeta {
  authUid: string;
  ownerUid?: string;
  claimNonce?: string;
  siteId?: string;
}

export interface RtdbLive {
  ts: number;
  rssi?: number;
  power?: 'mains' | 'battery' | 'solar';
  batt?: number | null;
  uptimeS?: number;
  fw?: string;
  ch: Partial<Record<PortId, { v: number; err?: string } | null>>;
  relays: Partial<Record<RelayId, { on: boolean; level?: number; mode: 'auto' | 'manual'; since?: number; ruleId?: string }>>;
  pendingEvents?: number;
}

export type HubCommand =
  | { type: 'relay'; args: { relay: RelayId; on: boolean; level?: number; durationSec?: number } }
  | { type: 'relay_auto'; args: { relay: RelayId } }
  | { type: 'test_relay'; args: { relay: RelayId } }
  | { type: 'calibrate'; args: { port: PortId; step: 'zero' | 'span' | 'ph7' | 'ph4' | 'ph10'; ref?: number } }
  | { type: 'identify'; args?: Record<string, never> }
  | { type: 'restart'; args?: Record<string, never> }
  | { type: 'ota'; args: { version: string } };

export type RtdbCommand = HubCommand & { by: string; ts: number | { '.sv': 'timestamp' }; expSec: number };

export interface RtdbAck { ok: boolean; code?: string; ts: number }

/** Konfigurasi terkompilasi yang di-stream ke hub (`down/config`). Key pendek karena disimpan di flash. */
export interface HubConfig {
  v: number;
  siteId: string;
  tzOffsetMin: number;
  ports: Partial<Record<PortId, { m: MetricId; z: string }>>;
  relays: Partial<Record<RelayId, { k: ActuatorKind; z: string; lv?: number }>>;
  alarms: { ch: PortId; warn?: { lt?: number; gt?: number }; danger?: { lt?: number; gt?: number } }[];
  rules: { id: string; trigger: Trigger; action: Action; safety?: { maxRunSec?: number; cooldownSec?: number } }[];
}
