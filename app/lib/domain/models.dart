// Model domain. Bentuk field mengikuti docs/data-model.md & shared/src/types.ts.
// Konversi ke/dari Firestore/RTDB ada di data/firebase_repository.dart.

enum Role { owner, operator, viewer }

enum Severity { info, warning, danger }

/// Hasil penilaian nilai sensor terhadap ambang.
enum Level { good, warn, danger, unknown }

class Bound {
  const Bound({this.lt, this.gt});
  final double? lt;
  final double? gt;

  bool hit(double v) => (lt != null && v < lt!) || (gt != null && v > gt!);

  Map<String, dynamic> toMap() => {if (lt != null) 'lt': lt, if (gt != null) 'gt': gt};
  static Bound? fromMap(Object? m) {
    if (m is! Map) return null;
    return Bound(lt: (m['lt'] as num?)?.toDouble(), gt: (m['gt'] as num?)?.toDouble());
  }
}

class Threshold {
  const Threshold({this.ideal, this.warn, this.danger});
  final (double, double)? ideal;
  final Bound? warn;
  final Bound? danger;

  Level evaluate(double v) {
    if (danger?.hit(v) ?? false) return Level.danger;
    if (warn?.hit(v) ?? false) return Level.warn;
    return Level.good;
  }

  Map<String, dynamic> toMap() => {
        if (ideal != null) 'ideal': [ideal!.$1, ideal!.$2],
        if (warn != null) 'warn': warn!.toMap(),
        if (danger != null) 'danger': danger!.toMap(),
      };

  static Threshold? fromMap(Object? m) {
    if (m is! Map) return null;
    final i = m['ideal'];
    return Threshold(
      ideal: i is List && i.length == 2 ? ((i[0] as num).toDouble(), (i[1] as num).toDouble()) : null,
      warn: Bound.fromMap(m['warn']),
      danger: Bound.fromMap(m['danger']),
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.uid,
    this.displayName,
    this.phone,
    this.largeText = false,
    this.alarmSound = true,
    this.ownedHubIds = const [],
    this.planTier = 'free',
    this.hubLimit = 1,
    this.aiMonthlyLimit = 0,
    this.aiCount = 0,
    this.planValidUntil,
  });
  final String uid;
  final String? displayName;
  final String? phone;
  final bool largeText;
  final bool alarmSound;
  final List<String> ownedHubIds;
  final String planTier;
  final int hubLimit;
  final int aiMonthlyLimit;
  final int aiCount;
  final DateTime? planValidUntil;

  String get initials {
    final parts = (displayName ?? '?').trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }
}

class Site {
  const Site({
    required this.id,
    required this.name,
    required this.kind,
    required this.ownerUid,
    required this.roles,
    this.hubIds = const [],
    this.timezone = 'Asia/Jakarta',
  });
  final String id;
  final String name;
  final String kind;
  final String ownerUid;
  final Map<String, Role> roles;
  final List<String> hubIds;
  final String timezone;

  Role? roleOf(String uid) => roles[uid];
  bool canOperate(String uid) => roles[uid] == Role.owner || roles[uid] == Role.operator;
}

class Zone {
  const Zone({required this.id, required this.name, required this.kind, this.order = 0, this.meta = const {}, this.thresholds = const {}});
  final String id;
  final String name;
  final String kind;
  final int order;
  final Map<String, dynamic> meta;
  final Map<String, Threshold> thresholds;

  String get subtitle {
    final s = meta['species'] ?? meta['crop'] ?? meta['flock'];
    return s == null ? name : '$name · ${s.toString()[0].toUpperCase()}${s.toString().substring(1)}';
  }
}

class PortAssignment {
  const PortAssignment({required this.metric, required this.zoneId, this.label, this.calibratedAt, this.sensorModel});
  final String metric;
  final String zoneId;
  final String? label;
  final DateTime? calibratedAt;
  final String? sensorModel;
}

class RelayAssignment {
  const RelayAssignment({required this.kind, required this.label, required this.zoneId, this.levels});
  final String kind;
  final String label;
  final String zoneId;
  final int? levels;
}

class Hub {
  const Hub({
    required this.id,
    this.name,
    this.siteId,
    this.ownerUid,
    this.ports = const {},
    this.relays = const {},
    this.detected = const {},
    this.fwVersion,
    this.connectivity = 'wifi',
    this.configVersion = 0,
    this.model = 'sysnergi-hub',
  });
  final String id;
  final String? name;
  final String? siteId;
  final String? ownerUid;
  final Map<String, PortAssignment> ports;
  final Map<String, RelayAssignment> relays;
  final Map<String, String> detected;
  final String? fwVersion;
  final String connectivity;
  final int configVersion;
  final String model;

  String get displayName => name ?? 'Hub $id';
}

class ChannelValue {
  const ChannelValue(this.v, {this.err});
  final double v;
  final String? err;
}

class RelayState {
  const RelayState({required this.on, this.mode = 'auto', this.level, this.since, this.ruleId});
  final bool on;
  final String mode;
  final int? level;
  final DateTime? since;
  final String? ruleId;
}

/// RTDB `hubs/{id}/live`.
class LiveState {
  const LiveState({required this.ts, this.rssi, this.power, this.uptime, this.fw, this.ch = const {}, this.relays = const {}, this.pendingEvents = 0});
  final DateTime ts;
  final int? rssi;
  final String? power;
  final Duration? uptime;
  final String? fw;
  final Map<String, ChannelValue> ch;
  final Map<String, RelayState> relays;
  final int pendingEvents;

  bool isOnline(DateTime now) => now.difference(ts) < const Duration(seconds: 90);

  String get signalLabel {
    final r = rssi;
    if (r == null) return '-';
    if (r > -60) return 'Kuat';
    if (r > -75) return 'Sedang';
    return 'Lemah';
  }
}

class ThresholdCond {
  const ThresholdCond({required this.ch, required this.op, required this.value});
  final String ch;
  final String op; // 'lt' | 'gt'
  final double value;
}

sealed class Trigger {
  const Trigger();
}

class ThresholdTrigger extends Trigger {
  const ThresholdTrigger(this.cond, {this.holdSec});
  final ThresholdCond cond;
  final int? holdSec;
}

class ScheduleTrigger extends Trigger {
  const ScheduleTrigger({required this.start, this.end, this.days});
  final String start;
  final String? end;
  final List<int>? days;
}

sealed class AutomationAction {
  const AutomationAction();
}

class RelayAction extends AutomationAction {
  const RelayAction({required this.relay, required this.on, this.level, this.untilThreshold, this.untilDurationSec});
  final String relay;
  final bool on;
  final int? level;
  final ThresholdCond? untilThreshold;
  final int? untilDurationSec;
}

class NotifyAction extends AutomationAction {
  const NotifyAction(this.severity);
  final Severity severity;
}

class Automation {
  const Automation({
    required this.id,
    required this.name,
    required this.enabled,
    required this.hubId,
    required this.trigger,
    required this.action,
    this.maxRunSec,
    this.cooldownSec,
    this.source = 'manual',
    this.prompt,
  });
  final String id;
  final String name;
  final bool enabled;
  final String hubId;
  final Trigger trigger;
  final AutomationAction action;
  final int? maxRunSec;
  final int? cooldownSec;
  final String source;
  final String? prompt;

  Automation copyWith({bool? enabled}) => Automation(
        id: id,
        name: name,
        enabled: enabled ?? this.enabled,
        hubId: hubId,
        trigger: trigger,
        action: action,
        maxRunSec: maxRunSec,
        cooldownSec: cooldownSec,
        source: source,
        prompt: prompt,
      );
}

class AppEvent {
  const AppEvent({
    required this.id,
    required this.ts,
    required this.type,
    required this.severity,
    this.hubId,
    this.zoneId,
    this.ch,
    this.metric,
    this.value,
    this.relay,
    this.ruleId,
    this.title,
    this.body,
  });
  final String id;
  final DateTime ts;
  final String type;
  final Severity severity;
  final String? hubId;
  final String? zoneId;
  final String? ch;
  final String? metric;
  final double? value;
  final String? relay;
  final String? ruleId;
  final String? title;
  final String? body;
}

/// Satu titik data telemetri (rata-rata 5 menit dari `days/{yyyymmdd}`).
class TelemetryPoint {
  const TelemetryPoint(this.t, this.v);
  final DateTime t;
  final double v;
}

/// Hub yang ditemukan lewat BLE saat menambah perangkat.
class DiscoveredHub {
  const DiscoveredHub({required this.id, required this.rssi, required this.claimed, this.bleId});
  final String id;
  final int rssi;
  final bool claimed;
  final String? bleId;

  String get signalLabel => rssi > -60 ? 'Sinyal kuat' : rssi > -75 ? 'Sinyal sedang' : 'Sinyal lemah';
}
