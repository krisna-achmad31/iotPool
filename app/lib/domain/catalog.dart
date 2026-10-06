// Port Dart dari shared/src/catalog.ts. Jaga tetap identik dengan versi TypeScript:
// hub, Cloud Functions, dan app harus memakai id metric/actuator yang sama.

import 'package:flutter/material.dart' hide Threshold;

import 'models.dart';

enum Vertical { aquaculture, horticulture, livestock }

class MetricDef {
  const MetricDef(this.label, this.unit, this.decimals, this.verticals, this.icon, {this.thresholds});
  final String label;
  final String unit;
  final int decimals;
  final List<Vertical> verticals;
  final IconData icon;
  final Threshold? thresholds;
}

const _aq = [Vertical.aquaculture];

const Map<String, MetricDef> kMetrics = {
  'do': MetricDef('Oksigen air', 'mg/L', 1, _aq, Icons.waves_rounded,
      thresholds: Threshold(ideal: (5, 8), warn: Bound(lt: 5), danger: Bound(lt: 3))),
  'water_temp': MetricDef('Suhu air', '°C', 1, _aq, Icons.thermostat_rounded,
      thresholds: Threshold(ideal: (26, 30), warn: Bound(lt: 25, gt: 31), danger: Bound(lt: 22, gt: 33))),
  'ph': MetricDef('pH air', '', 1, [Vertical.aquaculture, Vertical.horticulture], Icons.water_drop_outlined,
      thresholds: Threshold(ideal: (6.5, 8.5), warn: Bound(lt: 6.5, gt: 8.5), danger: Bound(lt: 5.5, gt: 9.5))),
  'nh3_water': MetricDef('Amonia', 'ppm', 2, _aq, Icons.science_outlined,
      thresholds: Threshold(ideal: (0, 0.05), warn: Bound(gt: 0.1), danger: Bound(gt: 0.5))),
  'water_level': MetricDef('Tinggi air', 'cm', 0, _aq, Icons.straighten_rounded),
  'tds': MetricDef('TDS', 'ppm', 0, [Vertical.aquaculture, Vertical.horticulture], Icons.grain_rounded),
  'salinity': MetricDef('Salinitas', 'ppt', 1, _aq, Icons.grain_rounded),
  'turbidity': MetricDef('Kekeruhan', 'NTU', 0, _aq, Icons.blur_on_rounded),
  'soil_moisture': MetricDef('Kelembapan tanah', '%', 0, [Vertical.horticulture], Icons.grass_rounded,
      thresholds: Threshold(ideal: (40, 60), warn: Bound(lt: 35, gt: 75), danger: Bound(lt: 20))),
  'soil_ec': MetricDef('EC tanah', 'mS/cm', 2, [Vertical.horticulture], Icons.bolt_rounded),
  'light': MetricDef('Cahaya', 'lux', 0, [Vertical.horticulture, Vertical.livestock], Icons.wb_sunny_outlined),
  'tank_level': MetricDef('Isi tandon', '%', 0, [Vertical.horticulture, Vertical.livestock, Vertical.aquaculture],
      Icons.propane_tank_outlined,
      thresholds: Threshold(warn: Bound(lt: 30), danger: Bound(lt: 10))),
  'air_temp': MetricDef('Suhu udara', '°C', 1, [Vertical.horticulture, Vertical.livestock], Icons.device_thermostat),
  'air_humidity': MetricDef('Lembap udara', '%', 0, [Vertical.horticulture, Vertical.livestock], Icons.water_drop_rounded),
  'nh3_air': MetricDef('Amonia udara', 'ppm', 0, [Vertical.livestock], Icons.air_rounded,
      thresholds: Threshold(ideal: (0, 10), warn: Bound(gt: 20), danger: Bound(gt: 25))),
  'co2': MetricDef('CO₂', 'ppm', 0, [Vertical.horticulture, Vertical.livestock], Icons.co2_rounded),
};

class ActuatorDef {
  const ActuatorDef(this.label, this.icon, {this.levels});
  final String label;
  final IconData icon;
  final int? levels;
}

const Map<String, ActuatorDef> kActuators = {
  'aerator': ActuatorDef('Aerator', Icons.cyclone_rounded),
  'pump_fill': ActuatorDef('Pompa isi', Icons.water_rounded),
  'pump_drain': ActuatorDef('Pompa buang', Icons.water_damage_outlined),
  'pump_irrigation': ActuatorDef('Pompa siram', Icons.shower_outlined),
  'valve': ActuatorDef('Katup', Icons.tune_rounded),
  'feeder': ActuatorDef('Pemberi pakan', Icons.set_meal_outlined),
  'grow_light': ActuatorDef('Lampu tumbuh', Icons.lightbulb_outline_rounded),
  'light': ActuatorDef('Lampu', Icons.lightbulb_outline_rounded),
  'exhaust_fan': ActuatorDef('Kipas exhaust', Icons.mode_fan_off_outlined, levels: 3),
  'heater': ActuatorDef('Pemanas', Icons.local_fire_department_outlined),
  'mister': ActuatorDef('Pengabut', Icons.cloud_outlined),
  'generic': ActuatorDef('Alat', Icons.power_settings_new_rounded),
};

const kPortIds = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6'];
const kRelayIds = ['R1', 'R2', 'R3', 'R4'];

/// Hub dianggap offline bila `live.ts` lebih tua dari ini (shared/src/paths.ts).
const kOnlineWindow = Duration(seconds: 90);

MetricDef metricDef(String id) =>
    kMetrics[id] ?? MetricDef(id, '', 1, const [], Icons.sensors_rounded);

ActuatorDef actuatorDef(String kind) => kActuators[kind] ?? kActuators['generic']!;

IconData siteIcon(String kind) => switch (kind) {
      'aquaculture' => Icons.set_meal_rounded,
      'horticulture' => Icons.eco_rounded,
      'livestock' => Icons.egg_alt_rounded,
      _ => Icons.place_rounded,
    };

String siteKindLabel(String kind) => switch (kind) {
      'aquaculture' => 'Kolam',
      'horticulture' => 'Kebun',
      'livestock' => 'Kandang',
      'mixed' => 'Campuran',
      _ => 'Lainnya',
    };

String formatValue(double v, String metric) {
  final d = metricDef(metric).decimals;
  return v.toStringAsFixed(d).replaceAll('.', ',');
}
