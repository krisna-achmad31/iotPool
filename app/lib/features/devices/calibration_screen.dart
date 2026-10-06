import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/catalog.dart';

/// Wizard kalibrasi: siapkan larutan → titik 1 → titik 2 → selesai.
/// pH memakai titik ph7 & ph4; sensor lain memakai zero & span (perintah `calibrate` di down/cmd).
class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key, required this.hubId, required this.port});
  final String hubId;
  final String port;
  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> {
  int _step = 0; // 0 siapkan, 1 titik 1, 2 titik 2, 3 selesai
  bool _busy = false;
  final _readings = <(DateTime, double)>[];
  final _saved = <String, double>{};
  bool _remind = true;

  bool get _isPh => _metric == 'ph';
  String _metric = 'ph';

  List<(String step, String title, String instruction, double ref)> get _points => _isPh
      ? const [
          ('ph7', 'Celupkan sensor ke larutan pH 7', 'Bilas ujung sensor dengan air bersih dulu. Biarkan diam sampai angka berhenti berubah.', 7.0),
          ('ph4', 'Celupkan sensor ke larutan pH 4', 'Bilas lagi dengan air bersih, lalu celupkan ke larutan pH 4.', 4.0),
        ]
      : const [
          ('zero', 'Titik nol', 'Angkat sensor ke udara atau larutan nol sesuai petunjuk modul.', 0.0),
          ('span', 'Titik acuan', 'Celupkan sensor ke larutan acuan sesuai petunjuk modul.', 100.0),
        ];

  DateTime? _stableSince;

  /// Bacaan dianggap stabil bila tidak bergeser > 0,1 selama 10 detik. Return 0..1.
  double _stability() {
    if (_stableSince == null) return 0;
    return (DateTime.now().difference(_stableSince!).inMilliseconds / 10000).clamp(0.0, 1.0);
  }

  void _addReading(double v) {
    if (_readings.isNotEmpty && _readings.last.$2 == v) return;
    if (_readings.isEmpty || (v - _readings.first.$2).abs() > 0.1) {
      _readings.clear();
      _stableSince = DateTime.now();
    }
    _readings.add((DateTime.now(), v));
  }

  Future<void> _savePoint(double current) async {
    final (step, _, _, refValue) = _points[_step - 1];
    setState(() => _busy = true);
    final r = await ref.read(repositoryProvider).sendCommand(widget.hubId, 'calibrate', {'port': widget.port, 'step': step, 'ref': refValue});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return showMessage(context, 'Hub tidak menjawab (${r.code}). Coba lagi.');
    _saved[step] = current;
    _readings.clear();
    _stableSince = null;
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(hubProvider(widget.hubId)).value;
    final live = ref.watch(liveProvider(widget.hubId)).value;
    final a = hub?.ports[widget.port];
    if (a != null) _metric = a.metric;
    final v = live?.ch[widget.port]?.v;
    ref.watch(clockProvider); // render ulang tiap 5 detik untuk bar stabil
    if (v != null && _step > 0 && _step <= 2) _addReading(v);
    final def = metricDef(_metric);

    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(children: [
            RoundIconButton(Icons.close_rounded, onPressed: () => context.pop()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Kalibrasi sensor ${def.label.replaceAll(' air', '')}', style: T.h2),
                Text('${hub?.displayName ?? ''} · Port ${widget.port} · ±10 menit', style: T.small),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: i <= _step ? AppColors.blueGradient : null,
                    color: i <= _step ? null : const Color(0xB3FFFFFF),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          if (_step == 0) ..._prepare() else if (_step <= 2) ..._point(v, def) else ..._done(),
        ],
      ),
    );
  }

  List<Widget> _prepare() => [
        _stepCard(1, Icons.inventory_2_outlined, 'Siapkan alat',
            _isPh ? 'Larutan buffer pH 7 dan pH 4, air bersih untuk membilas, dan tisu.' : 'Larutan acuan sesuai petunjuk modul dan air bersih.'),
        const SizedBox(height: 16),
        _checklist(),
        const SizedBox(height: 20),
        PrimaryButton('Saya sudah siap', trailingIcon: Icons.arrow_forward_rounded, onPressed: () => setState(() => _step = 1)),
      ];

  List<Widget> _point(double? v, MetricDef def) {
    final (_, title, instruction, _) = _points[_step - 1];
    final stability = _stability();
    final stable = stability >= 0.95;
    return [
      _stepCard(_step + 1, Icons.science_outlined, title, instruction),
      const SizedBox(height: 16),
      BlueCard(
        radius: 26,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Bacaan sensor sekarang', style: T.s(14, c: const Color(0xFFDDEBFF)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: stable ? const Color(0xFF7CF0B5) : AppColors.amber, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(stable ? 'Stabil' : 'Menunggu stabil', style: T.s(12, w: FontWeight.w600, c: Colors.white)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(v == null ? '–' : v.toStringAsFixed(2).replaceAll('.', ','), style: T.s(56, w: FontWeight.w600, c: Colors.white, ls: -1.5, h: 1)),
            const SizedBox(width: 8),
            Text(_isPh ? 'pH' : def.unit, style: T.s(18, w: FontWeight.w500, c: const Color(0xFFDDEBFF))),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: stability, minHeight: 8, backgroundColor: const Color(0x33FFFFFF), color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text('Biarkan sensor diam sampai bar penuh', style: T.s(13, c: const Color(0xFFDDEBFF))),
        ]),
      ),
      const SizedBox(height: 16),
      _checklist(),
      const SizedBox(height: 20),
      PrimaryButton('Simpan titik ${_isPh ? 'pH ${_points[_step - 1].$4.toInt()}' : _points[_step - 1].$2.toLowerCase()}',
          icon: Icons.check_rounded, loading: _busy, onPressed: v == null || !stable ? null : () => _savePoint(v)),
    ];
  }

  List<Widget> _done() {
    final next = DateTime.now().add(const Duration(days: 30));
    return [
      const SizedBox(height: 20),
      Center(
        child: Container(
          width: 160,
          height: 160,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x1A22B573)),
          child: Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.green),
              child: const Icon(Icons.check_rounded, size: 52, color: Colors.white),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Center(child: Text('Kalibrasi berhasil', style: T.s(28, w: FontWeight.w600, ls: -0.5))),
      const SizedBox(height: 8),
      Text('Sensor sekarang lebih akurat. Data kalibrasi tersimpan di modul, jadi tetap terbawa kalau modul dipindah.',
          textAlign: TextAlign.center, style: T.body),
      const SizedBox(height: 20),
      Divided(strong: true, children: [
        for (final (step, _, _, refValue) in _points)
          _kv(_isPh ? 'Titik pH ${refValue.toInt()}' : step, '${(_saved[step] ?? refValue).toStringAsFixed(2).replaceAll('.', ',')} → ${refValue.toStringAsFixed(2).replaceAll('.', ',')}'),
        _kv('Kalibrasi berikutnya', DateFormat('d MMMM yyyy', 'id').format(next)),
      ]),
      const SizedBox(height: 14),
      Glass(
        child: Row(children: [
          const IconChip(Icons.notifications_active_outlined),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ingatkan 30 hari lagi', style: T.s(15, w: FontWeight.w600)),
            Text('Kami kabari lewat notifikasi', style: T.small),
          ])),
          BigSwitch(value: _remind, onChanged: (v) => setState(() => _remind = v)),
        ]),
      ),
      const SizedBox(height: 20),
      PrimaryButton('Selesai', onPressed: () => context.pop()),
    ];
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [Expanded(child: Text(k, style: T.s(15, c: AppColors.ink2))), Text(v, style: T.s(15, w: FontWeight.w600))]),
      );

  Widget _stepCard(int n, IconData icon, String title, String body) => Glass(
        strong: true,
        radius: 30,
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(12)),
            child: Text('Langkah $n dari 4', style: T.s(13, w: FontWeight.w600, c: AppColors.blue)),
          ),
          const SizedBox(height: 16),
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.tint),
            child: Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient),
                child: Icon(icon, size: 40, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: T.s(22, w: FontWeight.w600, ls: -0.3)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: T.body),
        ]),
      );

  Widget _checklist() {
    final items = [
      _isPh ? 'Siapkan larutan pH 4 & pH 7' : 'Siapkan larutan acuan',
      _isPh ? 'Titik pH 7' : 'Titik nol',
      _isPh ? 'Titik pH 4' : 'Titik acuan',
      'Pasang kembali sensor',
    ];
    return Divided(children: [
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _step ? AppColors.green : null,
                gradient: i == _step ? AppColors.blueGradient : null,
                border: i > _step ? Border.all(color: const Color(0xFFB8C3D6), width: 2) : null,
              ),
              child: Center(
                child: i < _step
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : Text('${i + 1}', style: T.s(13, w: FontWeight.w600, c: i == _step ? Colors.white : AppColors.ink2)),
              ),
            ),
            const SizedBox(width: 12),
            Text(items[i], style: T.s(15, w: i == _step ? FontWeight.w600 : FontWeight.w400, c: i > _step ? AppColors.ink2 : AppColors.ink)),
          ]),
        ),
    ]);
  }
}
