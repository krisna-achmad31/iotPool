import 'catalog.dart';
import 'models.dart';

/// Ambang efektif: override zona → default katalog.
Threshold? thresholdFor(String metric, Zone? zone) => zone?.thresholds[metric] ?? metricDef(metric).thresholds;

Level levelFor(String metric, double? v, Zone? zone) {
  if (v == null) return Level.unknown;
  return thresholdFor(metric, zone)?.evaluate(v) ?? Level.good;
}

String levelLabel(Level l) => switch (l) {
      Level.good => 'Aman',
      Level.warn => 'Waspada',
      Level.danger => 'Bahaya',
      Level.unknown => 'Tidak ada data',
    };

String idealLabel(String metric, Zone? zone) {
  final t = thresholdFor(metric, zone);
  final unit = metricDef(metric).unit;
  final i = t?.ideal;
  if (i != null) return 'Ideal ${_n(i.$1)}–${_n(i.$2)}${unit.isEmpty ? '' : ' $unit'}';
  final w = t?.warn;
  if (w?.lt != null) return 'Aman di atas ${_n(w!.lt!)}${unit.isEmpty ? '' : ' $unit'}';
  if (w?.gt != null) return 'Aman di bawah ${_n(w!.gt!)}${unit.isEmpty ? '' : ' $unit'}';
  return '';
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');

/// Kalimat status per metric untuk kartu hero Beranda.
String headline(String metric, Level level) {
  final label = metricDef(metric).label;
  final lower = label[0].toLowerCase() + label.substring(1);
  final hi = switch (metric) { 'nh3_water' || 'nh3_air' || 'water_temp' || 'air_temp' => true, _ => false };
  return switch (level) {
    Level.danger => hi ? '${_cap(lower)} terlalu tinggi' : '${_cap(lower)} terlalu rendah',
    Level.warn => hi ? '${_cap(lower)} mulai naik' : '${_cap(lower)} mulai turun',
    _ => 'Kondisi aman',
  };
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

/// Port Dart dari shared/src/hub-config.ts — hasil harus identik dengan versi TypeScript.
/// Dipakai app saat mode Spark untuk menulis RTDB `hubs/{id}/down/config`.
Map<String, dynamic> buildHubConfig({
  required Hub hub,
  required String timezone,
  required Map<String, Zone> zones,
  required List<Automation> automations,
  required Map<String, dynamic> Function(Automation) encodeRule,
}) {
  if (hub.siteId == null) throw StateError('hub ${hub.id} belum diklaim');
  final cfg = <String, dynamic>{
    'v': hub.configVersion,
    'siteId': hub.siteId,
    'tzOffsetMin': tzOffsetMin(timezone),
    'ports': <String, dynamic>{},
    'relays': <String, dynamic>{},
    'alarms': <Map<String, dynamic>>[],
    'rules': <Map<String, dynamic>>[],
  };
  for (final p in kPortIds) {
    final a = hub.ports[p];
    if (a == null) continue;
    (cfg['ports'] as Map)[p] = {'m': a.metric, 'z': a.zoneId};
    final t = zones[a.zoneId]?.thresholds[a.metric] ?? metricDef(a.metric).thresholds;
    if (t != null && (t.warn != null || t.danger != null)) {
      (cfg['alarms'] as List).add({
        'ch': p,
        if (t.warn != null) 'warn': t.warn!.toMap(),
        if (t.danger != null) 'danger': t.danger!.toMap(),
      });
    }
  }
  for (final r in kRelayIds) {
    final a = hub.relays[r];
    if (a == null) continue;
    (cfg['relays'] as Map)[r] = {'k': a.kind, 'z': a.zoneId, if (a.levels != null && a.levels! > 0) 'lv': a.levels};
  }
  final sorted = [...automations]..sort((a, b) => a.id.compareTo(b.id));
  for (final rule in sorted) {
    if (!rule.enabled || rule.hubId != hub.id) continue;
    if (!_referencesExist(rule, cfg)) continue;
    (cfg['rules'] as List).add({'id': rule.id, ...encodeRule(rule)});
  }
  return cfg;
}

bool _referencesExist(Automation rule, Map<String, dynamic> cfg) {
  final ports = cfg['ports'] as Map;
  final relays = cfg['relays'] as Map;
  final chs = <String>[];
  final t = rule.trigger;
  if (t is ThresholdTrigger) chs.add(t.cond.ch);
  final a = rule.action;
  if (a is RelayAction) {
    if (!relays.containsKey(a.relay)) return false;
    if (a.untilThreshold != null) chs.add(a.untilThreshold!.ch);
  }
  return chs.every(ports.containsKey);
}

int tzOffsetMin(String timezone) => const {
      'Asia/Jakarta': 420,
      'Asia/Pontianak': 420,
      'Asia/Makassar': 480,
      'Asia/Jayapura': 540,
    }[timezone] ??
    420;

/// Kalimat aturan untuk UI ("Oksigen air di bawah 4 mg/L").
String describeTrigger(Trigger t, Hub? hub) => switch (t) {
      ThresholdTrigger(:final cond) => describeCond(cond, hub),
      ScheduleTrigger(:final start, :final end) => end == null ? 'Setiap pukul $start' : 'Pukul $start – $end',
    };

String describeCond(ThresholdCond c, Hub? hub) {
  final metric = hub?.ports[c.ch]?.metric;
  final def = metric == null ? null : metricDef(metric);
  final label = def?.label ?? c.ch;
  final unit = def == null || def.unit.isEmpty ? '' : ' ${def.unit}';
  final v = metric == null ? c.value.toString() : formatValue(c.value, metric);
  return '$label ${c.op == 'lt' ? 'di bawah' : 'di atas'} $v$unit';
}

String describeAction(AutomationAction a, Hub? hub) => switch (a) {
      RelayAction(:final relay, :final on, :final untilThreshold, :final untilDurationSec) =>
        '${hub?.relays[relay]?.label ?? relay} ${on ? 'menyala' : 'mati'}'
            '${untilThreshold != null ? ' sampai ${describeCond(untilThreshold, hub).toLowerCase()}' : ''}'
            '${untilDurationSec != null ? ' selama ${untilDurationSec ~/ 60} menit' : ''}',
      NotifyAction(:final severity) => severity == Severity.danger ? 'Kirim peringatan bahaya' : 'Kirim notifikasi',
    };

String relativeTime(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 60) return d.inSeconds < 5 ? 'baru saja' : '${d.inSeconds} detik lalu';
  if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}

Map<String, dynamic> _cond(ThresholdCond c) => {'type': 'threshold', 'ch': c.ch, 'op': c.op, 'value': c.value};

/// Bentuk `trigger`/`action`/`safety` di Firestore & `down/config` (shared/src/types.ts).
Map<String, dynamic> encodeRule(Automation a) => {
      'trigger': switch (a.trigger) {
        ThresholdTrigger(:final cond, :final holdSec) => {..._cond(cond), 'holdSec': ?holdSec},
        ScheduleTrigger(:final start, :final end, :final days) => {'type': 'schedule', 'start': start, 'end': ?end, 'days': ?days},
      },
      'action': switch (a.action) {
        RelayAction(:final relay, :final on, :final level, :final untilThreshold, :final untilDurationSec) => {
            'type': 'relay',
            'relay': relay,
            'on': on,
            'level': ?level,
            if (untilThreshold != null) 'until': _cond(untilThreshold),
            if (untilDurationSec != null) 'until': {'type': 'duration', 'sec': untilDurationSec},
          },
        NotifyAction(:final severity) => {'type': 'notify', 'severity': severity.name},
      },
      if (a.maxRunSec != null || a.cooldownSec != null) 'safety': {'maxRunSec': ?a.maxRunSec, 'cooldownSec': ?a.cooldownSec},
    };
