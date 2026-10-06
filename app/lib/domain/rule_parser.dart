import 'models.dart';

/// Pengurai kalimat sederhana → usulan aturan. Dipakai sampai LLM di Cloud Function tersedia;
/// keluarannya tetap harus lewat validasi, simulasi, dan persetujuan pengguna (PRD · Otomasi cerdas).
class ParsedRule {
  const ParsedRule({required this.metric, required this.op, required this.value, this.actuator, this.until, this.maxRunSec = 2700});
  final String metric;
  final String op;
  final double value;
  final String? actuator;
  final double? until;
  final int maxRunSec;
}

const _metricWords = <String, List<String>>{
  'do': ['oksigen', 'do ', 'o2'],
  'water_level': ['tinggi air', 'airnya', 'air kolam', 'level air', 'air kurang', 'air di bawah'],
  'nh3_water': ['amonia', 'amoniak'],
  'ph': ['ph'],
  'soil_moisture': ['tanah', 'kering'],
  'tank_level': ['tandon', 'tangki'],
  'nh3_air': ['bau', 'amonia udara'],
  'air_humidity': ['lembap', 'kelembapan'],
  'water_temp': ['suhu air'],
  'air_temp': ['suhu', 'panas', 'derajat', 'dingin'],
};

const _actuatorWords = <String, List<String>>{
  'aerator': ['aerator', 'kincir'],
  'pump_fill': ['isi kolam', 'pompa isi', 'isi air', 'tambah air', 'isi'],
  'pump_drain': ['buang air', 'pompa buang', 'kuras'],
  'pump_irrigation': ['siram', 'pompa siram'],
  'exhaust_fan': ['kipas', 'exhaust'],
  'heater': ['pemanas', 'lampu pemanas'],
  'grow_light': ['lampu tumbuh'],
  'light': ['lampu'],
};

/// [available] = metric yang benar-benar terpasang di site, dipakai untuk memilih "suhu" yang tepat.
ParsedRule? parseRule(String text, {Set<String> available = const {}}) {
  final t = ' ${text.toLowerCase()} ';
  String? metric;
  for (final e in _metricWords.entries) {
    if (e.value.any(t.contains) && (available.isEmpty || available.contains(e.key))) {
      metric = e.key;
      break;
    }
  }
  if (metric == null && t.contains('suhu') && available.contains('water_temp')) metric = 'water_temp';
  if (metric == null) return null;

  final lower = RegExp(r'kurang|di ?bawah|<|turun|rendah|kering|dingin').hasMatch(t);
  final higher = RegExp(r'lebih|di ?atas|>|naik|tinggi|panas').hasMatch(t);
  final op = lower && !higher ? 'lt' : higher && !lower ? 'gt' : (metric == 'air_temp' ? 'gt' : 'lt');

  final nums = RegExp(r'(\d+(?:[.,]\d+)?)').allMatches(t).map((m) => double.parse(m.group(1)!.replaceAll(',', '.'))).toList();
  final value = nums.isNotEmpty ? nums.first : _defaultValue(metric, op);
  if (value == null) return null;

  String? actuator;
  for (final e in _actuatorWords.entries) {
    if (e.value.any(t.contains)) {
      actuator = e.key;
      break;
    }
  }
  if (t.contains('kabari') || t.contains('beri tahu') || t.contains('ingatkan') || t.contains('notif')) actuator = null;

  final until = nums.length > 1 ? nums[1] : (actuator == 'pump_fill' || actuator == 'pump_irrigation') ? value + 10 : null;
  return ParsedRule(metric: metric, op: op, value: value, actuator: actuator, until: until);
}

double? _defaultValue(String metric, String op) => switch ((metric, op)) {
      ('do', 'lt') => 4,
      ('soil_moisture', 'lt') => 35,
      ('air_temp', 'gt') => 30,
      ('tank_level', 'lt') => 30,
      _ => null,
    };

/// Simulasi terhadap riwayat: berapa kali kondisi terpicu dan perkiraan lama menyala.
({int triggers, int avgMinutes}) simulate(ParsedRule r, List<TelemetryPoint> history) {
  var triggers = 0;
  var activeSamples = 0;
  var active = false;
  for (final p in history) {
    final hit = r.op == 'lt' ? p.v < r.value : p.v > r.value;
    if (hit && !active) triggers++;
    if (hit) activeSamples++;
    active = hit;
  }
  if (triggers == 0 || history.length < 2) return (triggers: 0, avgMinutes: 0);
  final stepMin = history[1].t.difference(history[0].t).inMinutes.abs().clamp(5, 1440);
  return (triggers: triggers, avgMinutes: ((activeSamples * stepMin) / triggers).round().clamp(5, r.maxRunSec ~/ 60));
}
