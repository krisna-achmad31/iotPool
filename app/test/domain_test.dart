import 'package:flutter_test/flutter_test.dart';
import 'package:sysnergi/domain/logic.dart';
import 'package:sysnergi/domain/models.dart';
import 'package:sysnergi/domain/rule_parser.dart';

void main() {
  group('buildHubConfig (cermin tests/shared.test.ts)', () {
    const hub = Hub(
      id: 'SYN-0A41',
      siteId: 'siteDarto',
      configVersion: 3,
      ports: {
        'P1': PortAssignment(metric: 'do', zoneId: 'kolam2'),
        'P5': PortAssignment(metric: 'water_level', zoneId: 'kolam2'),
      },
      relays: {'R1': RelayAssignment(kind: 'aerator', label: 'Aerator', zoneId: 'kolam2')},
    );
    final cfg = buildHubConfig(
      hub: hub,
      timezone: 'Asia/Jakarta',
      zones: const {
        'kolam2': Zone(id: 'kolam2', name: 'Kolam 2', kind: 'pond', thresholds: {
          'do': Threshold(warn: Bound(lt: 4.5), danger: Bound(lt: 2.5)),
        }),
      },
      automations: const [
        Automation(
          id: 'r_do_low', name: 'a', enabled: true, hubId: 'SYN-0A41',
          trigger: ThresholdTrigger(ThresholdCond(ch: 'P1', op: 'lt', value: 4)),
          action: RelayAction(relay: 'R1', on: true), maxRunSec: 7200,
        ),
        Automation(
          id: 'r_disabled', name: 'b', enabled: false, hubId: 'SYN-0A41',
          trigger: ScheduleTrigger(start: '00:00', end: '05:00'),
          action: RelayAction(relay: 'R1', on: true),
        ),
        Automation(
          id: 'r_relay_kosong', name: 'c', enabled: true, hubId: 'SYN-0A41',
          trigger: ThresholdTrigger(ThresholdCond(ch: 'P5', op: 'lt', value: 70)),
          action: RelayAction(relay: 'R2', on: true),
        ),
        Automation(
          id: 'r_hub_lain', name: 'd', enabled: true, hubId: 'SYN-0C88',
          trigger: ThresholdTrigger(ThresholdCond(ch: 'P1', op: 'lt', value: 4)),
          action: NotifyAction(Severity.warning),
        ),
      ],
      encodeRule: encodeRule,
    );

    test('mengompilasi port & relay terpasang saja', () {
      expect(cfg['ports'], {
        'P1': {'m': 'do', 'z': 'kolam2'},
        'P5': {'m': 'water_level', 'z': 'kolam2'},
      });
      expect(cfg['relays'], {
        'R1': {'k': 'aerator', 'z': 'kolam2'},
      });
      expect(cfg['tzOffsetMin'], 420);
      expect(cfg['v'], 3);
    });

    test('ambang zona meng-override default katalog', () {
      expect(cfg['alarms'], [
        {'ch': 'P1', 'warn': {'lt': 4.5}, 'danger': {'lt': 2.5}},
      ]);
    });

    test('melewati aturan nonaktif, hub lain, dan yang menunjuk relay kosong', () {
      expect((cfg['rules'] as List).map((r) => r['id']), ['r_do_low']);
      expect((cfg['rules'] as List).first['safety'], {'maxRunSec': 7200});
    });
  });

  group('penilaian ambang', () {
    test('oksigen 4,1 = waspada, 2,9 = bahaya, 6 = aman', () {
      expect(levelFor('do', 4.1, null), Level.warn);
      expect(levelFor('do', 2.9, null), Level.danger);
      expect(levelFor('do', 6, null), Level.good);
    });
    test('override zona dipakai', () {
      const z = Zone(id: 'z', name: 'Z', kind: 'pond', thresholds: {'do': Threshold(warn: Bound(lt: 6))});
      expect(levelFor('do', 5.5, z), Level.warn);
    });
    test('metric tanpa ambang selalu aman', () => expect(levelFor('water_level', 10, null), Level.good));
  });

  group('parseRule', () {
    const kolam = {'do', 'water_temp', 'ph', 'nh3_water', 'water_level'};

    test('"Isi kolam kalau airnya kurang dari 70 cm" (contoh desain)', () {
      final r = parseRule('Isi kolam kalau airnya kurang dari 70 cm', available: kolam)!;
      expect(r.metric, 'water_level');
      expect(r.op, 'lt');
      expect(r.value, 70);
      expect(r.actuator, 'pump_fill');
      expect(r.until, 80);
    });

    test('aerator saat oksigen rendah, angka berkoma', () {
      final r = parseRule('nyalakan aerator kalau oksigen di bawah 4,5', available: kolam)!;
      expect((r.metric, r.op, r.value, r.actuator), ('do', 'lt', 4.5, 'aerator'));
    });

    test('kandang: kipas saat panas', () {
      final r = parseRule('Nyalakan kipas kalau suhu di atas 30', available: {'air_temp', 'nh3_air'})!;
      expect((r.metric, r.op, r.value, r.actuator), ('air_temp', 'gt', 30.0, 'exhaust_fan'));
    });

    test('"kabari" menjadi notifikasi', () {
      final r = parseRule('kabari kalau tandon di bawah 30%', available: {'tank_level'})!;
      expect(r.actuator, isNull);
    });

    test('kalimat tanpa sensor dikenal → null', () => expect(parseRule('halo apa kabar', available: kolam), isNull));
  });

  test('simulasi menghitung berapa kali aturan terpicu', () {
    final t0 = DateTime(2026, 10, 1);
    final hist = [for (var i = 0; i < 6; i++) TelemetryPoint(t0.add(Duration(hours: i)), [6, 3.5, 3.8, 6, 3.9, 6][i].toDouble())];
    final s = simulate(const ParsedRule(metric: 'do', op: 'lt', value: 4), hist);
    expect(s.triggers, 2);
    expect(s.avgMinutes, 45); // 3 jam aktif / 2 kali, dibatasi maxRunSec 45 menit
  });
}
