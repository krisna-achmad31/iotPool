// Katalog besaran sensor (metric) dan jenis alat (actuator). Menambah vertikal baru cukup
// menambah entri di sini — skema database tidak berubah.

import type { Threshold } from './types';

export type Vertical = 'aquaculture' | 'horticulture' | 'livestock';

export interface MetricDef {
  label: string;
  unit: string;
  decimals: number;
  verticals: Vertical[];
  /** Ambang default; bisa di-override per zona lewat `zone.thresholds`. */
  thresholds?: Threshold;
}

export const METRICS = {
  do:              { label: 'Oksigen air',     unit: 'mg/L', decimals: 1, verticals: ['aquaculture'],
                     thresholds: { ideal: [5, 8], warn: { lt: 5 }, danger: { lt: 3 } } },
  water_temp:      { label: 'Suhu air',        unit: '°C',   decimals: 1, verticals: ['aquaculture'],
                     thresholds: { ideal: [26, 30], warn: { lt: 25, gt: 31 }, danger: { lt: 22, gt: 33 } } },
  ph:              { label: 'pH air',          unit: '',     decimals: 1, verticals: ['aquaculture', 'horticulture'],
                     thresholds: { ideal: [6.5, 8.5], warn: { lt: 6.5, gt: 8.5 }, danger: { lt: 5.5, gt: 9.5 } } },
  nh3_water:       { label: 'Amonia',          unit: 'ppm',  decimals: 2, verticals: ['aquaculture'],
                     thresholds: { ideal: [0, 0.05], warn: { gt: 0.1 }, danger: { gt: 0.5 } } },
  water_level:     { label: 'Tinggi air',      unit: 'cm',   decimals: 0, verticals: ['aquaculture'] },
  tds:             { label: 'TDS',             unit: 'ppm',  decimals: 0, verticals: ['aquaculture', 'horticulture'] },
  salinity:        { label: 'Salinitas',       unit: 'ppt',  decimals: 1, verticals: ['aquaculture'] },
  turbidity:       { label: 'Kekeruhan',       unit: 'NTU',  decimals: 0, verticals: ['aquaculture'] },

  soil_moisture:   { label: 'Kelembapan tanah', unit: '%',   decimals: 0, verticals: ['horticulture'],
                     thresholds: { ideal: [40, 60], warn: { lt: 35, gt: 75 }, danger: { lt: 20 } } },
  soil_ec:         { label: 'EC tanah',        unit: 'mS/cm', decimals: 2, verticals: ['horticulture'] },
  light:           { label: 'Cahaya',          unit: 'lux',  decimals: 0, verticals: ['horticulture', 'livestock'] },
  tank_level:      { label: 'Isi tandon',      unit: '%',    decimals: 0, verticals: ['horticulture', 'livestock', 'aquaculture'],
                     thresholds: { warn: { lt: 30 }, danger: { lt: 10 } } },

  air_temp:        { label: 'Suhu udara',      unit: '°C',   decimals: 1, verticals: ['horticulture', 'livestock'] },
  air_humidity:    { label: 'Lembap udara',    unit: '%',    decimals: 0, verticals: ['horticulture', 'livestock'] },
  nh3_air:         { label: 'Amonia udara',    unit: 'ppm',  decimals: 0, verticals: ['livestock'],
                     thresholds: { ideal: [0, 10], warn: { gt: 20 }, danger: { gt: 25 } } },
  co2:             { label: 'CO₂',             unit: 'ppm',  decimals: 0, verticals: ['horticulture', 'livestock'] },
} as const satisfies Record<string, MetricDef>;

export type MetricId = keyof typeof METRICS;

export interface ActuatorDef {
  label: string;
  /** Jumlah level kecepatan (kipas, dll). Tidak ada = on/off saja. */
  levels?: number;
  verticals: Vertical[];
}

export const ACTUATORS = {
  aerator:         { label: 'Aerator',        verticals: ['aquaculture'] },
  pump_fill:       { label: 'Pompa isi',      verticals: ['aquaculture', 'livestock'] },
  pump_drain:      { label: 'Pompa buang',    verticals: ['aquaculture'] },
  pump_irrigation: { label: 'Pompa siram',    verticals: ['horticulture'] },
  valve:           { label: 'Katup',          verticals: ['horticulture', 'aquaculture', 'livestock'] },
  feeder:          { label: 'Pemberi pakan',  verticals: ['aquaculture', 'livestock'] },
  grow_light:      { label: 'Lampu tumbuh',   verticals: ['horticulture'] },
  light:           { label: 'Lampu',          verticals: ['livestock'] },
  exhaust_fan:     { label: 'Kipas exhaust',  levels: 3, verticals: ['livestock', 'horticulture'] },
  heater:          { label: 'Pemanas',        verticals: ['livestock', 'aquaculture'] },
  mister:          { label: 'Pengabut',       verticals: ['horticulture', 'livestock'] },
  generic:         { label: 'Alat',           verticals: ['aquaculture', 'horticulture', 'livestock'] },
} as const satisfies Record<string, ActuatorDef>;

export type ActuatorKind = keyof typeof ACTUATORS;

export const SITE_KINDS = ['aquaculture', 'horticulture', 'livestock', 'mixed', 'other'] as const;
export const ZONE_KINDS = ['pond', 'tank', 'greenhouse', 'bed', 'field', 'barn', 'coop', 'warehouse', 'other'] as const;

export const PORT_IDS = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6'] as const;
export const RELAY_IDS = ['R1', 'R2', 'R3', 'R4'] as const;
export type PortId = (typeof PORT_IDS)[number];
export type RelayId = (typeof RELAY_IDS)[number];
