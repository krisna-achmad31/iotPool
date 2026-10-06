import 'dart:async';
import 'dart:math';

import '../domain/models.dart';
import 'repository.dart';

/// Data contoh di memori: 3 site (kolam, kebun, kandang), 5 hub, nilai live yang bergerak.
/// Dipakai untuk mode demo dan saat Firebase belum dikonfigurasi.
class DemoRepository implements SysnergiRepository {
  DemoRepository() {
    _seed();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tickLive());
  }

  static const demoUid = 'demo-darto';
  late final Timer _timer;
  final _changes = StreamController<void>.broadcast();
  final _rnd = Random(7);

  String? _uid;
  late UserProfile _profile;
  final _sites = <String, Site>{};
  final _zones = <String, List<Zone>>{};
  final _hubs = <String, Hub>{};
  final _live = <String, LiveState>{};
  final _base = <String, Map<String, double>>{};
  final _automations = <String, List<Automation>>{};
  final _events = <String, List<AppEvent>>{};
  final _names = <String, String>{demoUid: 'Darto Wiyono', 'demo-wati': 'Bu Wati', 'demo-joko': 'Joko'};

  @override
  bool get isDemo => true;

  void dispose() {
    _timer.cancel();
    _changes.close();
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  void _emit() => _changes.add(null);

  // ───────────────────────── seed ─────────────────────────

  void _seed() {
    final now = DateTime.now();
    _profile = UserProfile(
      uid: demoUid,
      displayName: 'Darto Wiyono',
      phone: '+6281234567890',
      planTier: 'plus',
      hubLimit: 5,
      aiMonthlyLimit: 30,
      aiCount: 12,
      ownedHubIds: const ['SYN-0A12', 'SYN-0A41', 'SYN-0A77', 'SYN-0C08', 'SYN-0D15'],
      planValidUntil: DateTime(2027, 1, 12),
    );

    _sites['s_kolam'] = const Site(
      id: 's_kolam',
      name: 'Kolam Sukamaju',
      kind: 'aquaculture',
      ownerUid: demoUid,
      roles: {demoUid: Role.owner, 'demo-wati': Role.operator, 'demo-joko': Role.operator},
      hubIds: ['SYN-0A12', 'SYN-0A41', 'SYN-0A77'],
    );
    _sites['s_kebun'] = const Site(
      id: 's_kebun', name: 'Kebun Bu Sari', kind: 'horticulture', ownerUid: demoUid,
      roles: {demoUid: Role.owner}, hubIds: ['SYN-0C08'],
    );
    _sites['s_kandang'] = const Site(
      id: 's_kandang', name: 'Kandang Mas Rizal', kind: 'livestock', ownerUid: demoUid,
      roles: {demoUid: Role.owner}, hubIds: ['SYN-0D15'],
    );

    _zones['s_kolam'] = const [
      Zone(id: 'z1', name: 'Kolam 1', kind: 'pond', order: 1, meta: {'species': 'lele'}),
      Zone(id: 'z2', name: 'Kolam 2', kind: 'pond', order: 2, meta: {'species': 'lele'}),
      Zone(id: 'z3', name: 'Kolam 3', kind: 'pond', order: 3, meta: {'species': 'nila'}),
    ];
    _zones['s_kebun'] = const [
      Zone(id: 'zg', name: 'Greenhouse', kind: 'greenhouse', order: 1, meta: {'crop': 'cabai'}),
      Zone(id: 'zt', name: 'Tandon', kind: 'tank', order: 2),
    ];
    _zones['s_kandang'] = const [
      Zone(id: 'zb', name: 'Kandang B', kind: 'barn', order: 1, meta: {'flock': 'broiler'}),
    ];

    PortAssignment p(String m, String z, {int? calDays}) => PortAssignment(
        metric: m, zoneId: z, calibratedAt: calDays == null ? null : now.subtract(Duration(days: calDays)));
    RelayAssignment r(String k, String label, String z, {int? lv}) => RelayAssignment(kind: k, label: label, zoneId: z, levels: lv);

    _addHub(Hub(id: 'SYN-0A12', name: 'Hub Kolam 1', siteId: 's_kolam', ownerUid: demoUid, fwVersion: '1.4.2',
        ports: {'P1': p('do', 'z1', calDays: 10), 'P2': p('water_temp', 'z1'), 'P3': p('ph', 'z1', calDays: 10)},
        relays: {'R1': r('aerator', 'Aerator', 'z1')}),
        {'P1': 6.2, 'P2': 28.1, 'P3': 7.1});
    _addHub(Hub(id: 'SYN-0A41', name: 'Hub Kolam 2', siteId: 's_kolam', ownerUid: demoUid, fwVersion: '1.4.2', configVersion: 7,
        ports: {
          'P1': p('do', 'z2', calDays: 12),
          'P2': p('water_temp', 'z2'),
          'P3': p('ph', 'z2', calDays: 28),
          'P4': p('nh3_water', 'z2'),
          'P5': p('water_level', 'z2'),
        },
        relays: {'R1': r('aerator', 'Aerator', 'z2'), 'R2': r('pump_fill', 'Pompa isi', 'z2')}),
        {'P1': 4.1, 'P2': 28.4, 'P3': 7.2, 'P4': 0.02, 'P5': 82});
    _addHub(Hub(id: 'SYN-0A77', name: 'Hub Kolam 3', siteId: 's_kolam', ownerUid: demoUid, fwVersion: '1.4.1',
        ports: {'P1': p('do', 'z3'), 'P2': p('water_temp', 'z3')},
        relays: {'R1': r('aerator', 'Aerator', 'z3')}),
        {'P1': 5.6, 'P2': 28.9},
        offlineFor: const Duration(minutes: 18));
    _addHub(Hub(id: 'SYN-0C08', name: 'Hub Greenhouse', siteId: 's_kebun', ownerUid: demoUid, fwVersion: '1.4.2',
        ports: {
          'P1': p('soil_moisture', 'zg'),
          'P2': p('air_temp', 'zg'),
          'P3': p('air_humidity', 'zg'),
          'P4': p('light', 'zg'),
          'P5': p('tank_level', 'zt'),
        },
        relays: {'R1': r('pump_irrigation', 'Pompa siram', 'zg'), 'R2': r('grow_light', 'Lampu tumbuh', 'zg')}),
        {'P1': 28, 'P2': 31.2, 'P3': 64, 'P4': 42000, 'P5': 35});
    _addHub(Hub(id: 'SYN-0D15', name: 'Hub Kandang B', siteId: 's_kandang', ownerUid: demoUid, fwVersion: '1.4.2',
        ports: {
          'P1': p('air_temp', 'zb'),
          'P2': p('air_humidity', 'zb'),
          'P3': p('nh3_air', 'zb'),
          'P4': p('tank_level', 'zb'),
          'P5': p('light', 'zb'),
        },
        relays: {'R1': r('exhaust_fan', 'Kipas exhaust', 'zb', lv: 3), 'R2': r('heater', 'Pemanas', 'zb')}),
        {'P1': 29.1, 'P2': 68, 'P3': 12, 'P4': 76, 'P5': 20});

    _setRelay('SYN-0A41', 'R1', true, ruleId: 'r_do_low', since: now.subtract(const Duration(minutes: 42)));
    _setRelay('SYN-0D15', 'R1', true, level: 2, since: now.subtract(const Duration(hours: 2)));

    _automations['s_kolam'] = const [
      Automation(
        id: 'r_do_low', name: 'Aerator saat oksigen rendah', enabled: true, hubId: 'SYN-0A41',
        trigger: ThresholdTrigger(ThresholdCond(ch: 'P1', op: 'lt', value: 4), holdSec: 300),
        action: RelayAction(relay: 'R1', on: true), maxRunSec: 2700, source: 'template',
      ),
      Automation(
        id: 'r_night', name: 'Aerator malam hari', enabled: true, hubId: 'SYN-0A41',
        trigger: ScheduleTrigger(start: '00:00', end: '05:00'),
        action: RelayAction(relay: 'R1', on: true), source: 'template',
      ),
      Automation(
        id: 'r_nh3', name: 'Peringatan amonia', enabled: true, hubId: 'SYN-0A41',
        trigger: ThresholdTrigger(ThresholdCond(ch: 'P4', op: 'gt', value: 0.1)),
        action: NotifyAction(Severity.warning), source: 'template',
      ),
    ];
    _automations['s_kebun'] = const [
      Automation(
        id: 'r_siram', name: 'Siram saat tanah kering', enabled: true, hubId: 'SYN-0C08',
        trigger: ThresholdTrigger(ThresholdCond(ch: 'P1', op: 'lt', value: 35), holdSec: 600),
        action: RelayAction(relay: 'R1', on: true, untilThreshold: ThresholdCond(ch: 'P1', op: 'gt', value: 50)),
        maxRunSec: 1200, source: 'template',
      ),
    ];
    _automations['s_kandang'] = const [
      Automation(
        id: 'r_fan', name: 'Kipas ikut suhu', enabled: true, hubId: 'SYN-0D15',
        trigger: ThresholdTrigger(ThresholdCond(ch: 'P1', op: 'gt', value: 30)),
        action: RelayAction(relay: 'R1', on: true, level: 3), source: 'template',
      ),
    ];

    _events['s_kolam'] = [
      AppEvent(id: 'e1', ts: now.subtract(const Duration(minutes: 6)), type: 'alarm', severity: Severity.danger,
          hubId: 'SYN-0A41', zoneId: 'z2', ch: 'P1', metric: 'do', value: 3.8),
      AppEvent(id: 'e2', ts: now.subtract(const Duration(minutes: 18)), type: 'hub_offline', severity: Severity.warning,
          hubId: 'SYN-0A77', zoneId: 'z3'),
      AppEvent(id: 'e3', ts: now.subtract(const Duration(minutes: 42)), type: 'automation_start', severity: Severity.info,
          hubId: 'SYN-0A41', zoneId: 'z2', relay: 'R1', ruleId: 'r_do_low'),
      AppEvent(id: 'e4', ts: now.subtract(const Duration(hours: 15)), type: 'report', severity: Severity.info,
          title: 'Ringkasan mingguan siap',
          body: 'Oksigen sering turun pukul 02.00–05.00. Pertimbangkan tambah kincir di Kolam 2.'),
      AppEvent(id: 'e5', ts: now.subtract(const Duration(hours: 25)), type: 'calibration_due', severity: Severity.info,
          hubId: 'SYN-0A41', zoneId: 'z2', ch: 'P3', metric: 'ph'),
    ];
    _events['s_kebun'] = [
      AppEvent(id: 'k1', ts: now.subtract(const Duration(minutes: 20)), type: 'alarm', severity: Severity.warning,
          hubId: 'SYN-0C08', zoneId: 'zt', ch: 'P5', metric: 'tank_level', value: 35),
    ];
    _events['s_kandang'] = [];
  }

  void _addHub(Hub h, Map<String, double> base, {Duration offlineFor = Duration.zero}) {
    _hubs[h.id] = h;
    _base[h.id] = base;
    _live[h.id] = LiveState(
      ts: DateTime.now().subtract(offlineFor),
      rssi: -58,
      power: 'mains',
      uptime: const Duration(days: 12),
      fw: h.fwVersion,
      ch: {for (final e in base.entries) e.key: ChannelValue(e.value)},
      relays: {for (final r in h.relays.keys) r: const RelayState(on: false)},
    );
  }

  void _setRelay(String hubId, String relay, bool on, {String mode = 'auto', int? level, String? ruleId, DateTime? since}) {
    final l = _live[hubId]!;
    _live[hubId] = LiveState(
      ts: l.ts, rssi: l.rssi, power: l.power, uptime: l.uptime, fw: l.fw, ch: l.ch,
      relays: {...l.relays, relay: RelayState(on: on, mode: mode, level: level, ruleId: ruleId, since: since ?? DateTime.now())},
    );
  }

  void _tickLive() {
    final now = DateTime.now();
    for (final id in _live.keys.toList()) {
      final l = _live[id]!;
      if (!l.isOnline(now) && id == 'SYN-0A77') continue; // tetap offline untuk demo
      final ch = <String, ChannelValue>{};
      _base[id]!.forEach((port, b) {
        final jitter = b.abs() < 1 ? 0.005 : (b > 1000 ? 400 : b * 0.004);
        ch[port] = ChannelValue(b + (_rnd.nextDouble() - 0.5) * 2 * jitter);
      });
      _live[id] = LiveState(ts: now, rssi: -55 - _rnd.nextInt(8), power: l.power, uptime: l.uptime, fw: l.fw, ch: ch, relays: l.relays);
    }
    _emit();
  }

  // ───────────────────────── auth ─────────────────────────

  @override
  Stream<String?> authUid() => _watch(() => _uid);

  @override
  String? get currentUid => _uid;

  @override
  Future<String> sendOtp(String phoneE164) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return 'demo-verification';
  }

  @override
  Future<void> verifyOtp(String verificationId, String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!RegExp(r'^\d{6}$').hasMatch(code)) throw RepositoryException('Kode harus 6 angka.');
    _uid = demoUid;
    _emit();
  }

  @override
  Future<void> signInWithGoogle() async {
    _uid = demoUid;
    _emit();
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _emit();
  }

  // ───────────────────────── user ─────────────────────────

  @override
  Stream<UserProfile?> profile(String uid) => _watch(() => uid == demoUid ? _profile : null);

  @override
  Future<void> updatePrefs({bool? largeText, bool? alarmSound, String? displayName}) async {
    final p = _profile;
    _profile = UserProfile(
      uid: p.uid,
      displayName: displayName ?? p.displayName,
      phone: p.phone,
      largeText: largeText ?? p.largeText,
      alarmSound: alarmSound ?? p.alarmSound,
      ownedHubIds: p.ownedHubIds,
      planTier: p.planTier,
      hubLimit: p.hubLimit,
      aiMonthlyLimit: p.aiMonthlyLimit,
      aiCount: p.aiCount,
      planValidUntil: p.planValidUntil,
    );
    _emit();
  }

  // ───────────────────────── site/hub ─────────────────────────

  @override
  Stream<List<Site>> sites(String uid) => _watch(() => _sites.values.where((s) => s.roles.containsKey(uid)).toList());

  @override
  Future<String> createSite({required String name, required String kind}) async {
    final existing = _sites.values.where((s) => s.kind == kind);
    if (existing.isNotEmpty) return existing.first.id;
    final id = 's_${DateTime.now().millisecondsSinceEpoch}';
    _sites[id] = Site(id: id, name: name, kind: kind, ownerUid: demoUid, roles: const {demoUid: Role.owner});
    _zones[id] = const [];
    _emit();
    return id;
  }

  @override
  Stream<List<Zone>> zones(String siteId) => _watch(() => _zones[siteId] ?? const []);

  @override
  Stream<Hub?> hub(String hubId) => _watch(() => _hubs[hubId]);

  @override
  Stream<LiveState?> live(String hubId) => _watch(() => _live[hubId]);

  @override
  Future<List<TelemetryPoint>> history(String hubId, String port, Duration range) async {
    final base = _base[hubId]?[port];
    if (base == null) return const [];
    final metric = _hubs[hubId]!.ports[port]!.metric;
    final now = DateTime.now();
    final step = range.inHours <= 24 ? const Duration(hours: 1) : range.inDays <= 7 ? const Duration(hours: 6) : const Duration(days: 1);
    final n = range.inMinutes ~/ step.inMinutes;
    final rnd = Random(hubId.hashCode ^ port.hashCode ^ n);
    final out = <TelemetryPoint>[];
    double hourOf(DateTime t) => t.hour + t.minute / 60;
    // Pola harian, digeser supaya titik terakhir = nilai live sekarang.
    double daily(DateTime t) => metric == 'do'
        ? 1.6 * cos(2 * pi * (hourOf(t) - 15) / 24)
        : base * 0.03 * sin(2 * pi * (hourOf(t) - 14) / 24);
    for (var i = n; i >= 0; i--) {
      final t = now.subtract(step * i);
      var v = base + daily(t) - daily(now);
      // Kolam 2: oksigen sedang menurun beberapa jam terakhir.
      if (metric == 'do' && hubId == 'SYN-0A41') v += (i / n) * 2.4;
      if (i > 0) v += (rnd.nextDouble() - 0.5) * (base.abs() < 1 ? 0.01 : base * 0.01);
      out.add(TelemetryPoint(t, v));
    }
    return out;
  }

  @override
  Future<Map<String, String>> memberNames(Site site) async =>
      {for (final uid in site.roles.keys) uid: _names[uid] ?? uid};

  @override
  Future<void> setMemberRole(String siteId, String uid, Role? role) async {
    final s = _sites[siteId]!;
    final roles = {...s.roles};
    if (role == null) {
      roles.remove(uid);
    } else {
      roles[uid] = role;
    }
    _sites[siteId] = Site(id: s.id, name: s.name, kind: s.kind, ownerUid: s.ownerUid, roles: roles, hubIds: s.hubIds, timezone: s.timezone);
    _emit();
  }

  // ───────────────────────── otomasi & event ─────────────────────────

  @override
  Stream<List<Automation>> automations(String siteId) => _watch(() => _automations[siteId] ?? const []);

  @override
  Future<void> setAutomationEnabled(String siteId, Automation rule, bool enabled) async {
    _automations[siteId] = [for (final a in _automations[siteId] ?? <Automation>[]) a.id == rule.id ? a.copyWith(enabled: enabled) : a];
    _emit();
  }

  @override
  Future<void> saveAutomation(String siteId, Automation rule) async {
    final list = [...?_automations[siteId]]..removeWhere((a) => a.id == rule.id);
    _automations[siteId] = [...list, rule];
    _emit();
  }

  @override
  Stream<List<AppEvent>> events(String siteId, {int limit = 50}) =>
      _watch(() => (_events[siteId] ?? const <AppEvent>[]).take(limit).toList());

  @override
  Future<void> markEventsRead(String siteId) async {}

  // ───────────────────────── perintah & klaim ─────────────────────────

  @override
  Future<CommandResult> sendCommand(String hubId, String type, [Map<String, dynamic> args = const {}]) async {
    final l = _live[hubId];
    if (l == null || !l.isOnline(DateTime.now())) {
      await Future<void>.delayed(const Duration(seconds: 2));
      return const CommandResult(false, 'offline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    switch (type) {
      case 'relay':
        _setRelay(hubId, args['relay'] as String, args['on'] as bool, mode: 'manual', level: args['level'] as int?);
      case 'relay_auto':
        _setRelay(hubId, args['relay'] as String, false);
      case 'calibrate':
        final h = _hubs[hubId]!;
        final port = args['port'] as String;
        final a = h.ports[port];
        if (a != null && args['step'] == 'ph4') {
          _hubs[hubId] = Hub(
            id: h.id, name: h.name, siteId: h.siteId, ownerUid: h.ownerUid, relays: h.relays, fwVersion: h.fwVersion,
            configVersion: h.configVersion,
            ports: {...h.ports, port: PortAssignment(metric: a.metric, zoneId: a.zoneId, calibratedAt: DateTime.now())},
          );
        }
    }
    _emit();
    return const CommandResult(true);
  }

  @override
  Future<void> claimHub({required String hubId, required String nonce, required String siteId, String? name}) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final zone = (_zones[siteId] ?? const []).firstOrNull;
    _addHub(
      Hub(id: hubId, name: name ?? 'Hub baru', siteId: siteId, ownerUid: demoUid, fwVersion: '1.4.2',
          detected: const {'P1': 'do', 'P2': 'water_temp', 'P3': 'ph', 'P4': 'nh3_water', 'P5': 'water_level'},
          ports: zone == null
              ? const {}
              : {
                  for (final e in const {'P1': 'do', 'P2': 'water_temp', 'P3': 'ph', 'P4': 'nh3_water', 'P5': 'water_level'}.entries)
                    e.key: PortAssignment(metric: e.value, zoneId: zone.id),
                }),
      {'P1': 6.4, 'P2': 28.0, 'P3': 7.3, 'P4': 0.01, 'P5': 80},
    );
    final s = _sites[siteId]!;
    _sites[siteId] = Site(id: s.id, name: s.name, kind: s.kind, ownerUid: s.ownerUid, roles: s.roles, hubIds: [...s.hubIds, hubId]);
    _emit();
  }
}
