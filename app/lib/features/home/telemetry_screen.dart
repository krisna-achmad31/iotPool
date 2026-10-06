import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/catalog.dart';
import '../../domain/logic.dart';
import '../../domain/models.dart';
import '../notifications/notifications_screen.dart';

class TelemetryScreen extends ConsumerStatefulWidget {
  const TelemetryScreen({super.key, required this.hubId, required this.initialPort});
  final String hubId;
  final String initialPort;
  @override
  ConsumerState<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends ConsumerState<TelemetryScreen> {
  late String _port = widget.initialPort;
  int _hours = 24;

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(hubProvider(widget.hubId)).value;
    final live = ref.watch(liveProvider(widget.hubId)).value;
    final site = ref.watch(currentSiteProvider);
    if (hub == null || site == null) return const AppPage(child: Center(child: CircularProgressIndicator()));

    final zones = ref.watch(zonesProvider(site.id)).value ?? const <Zone>[];
    final assignment = hub.ports[_port] ?? hub.ports.values.first;
    final metric = assignment.metric;
    final zone = zones.where((z) => z.id == assignment.zoneId).firstOrNull;
    final def = metricDef(metric);
    final hist = ref.watch(historyProvider((hubId: hub.id, port: _port, hours: _hours)));
    final points = hist.value ?? const <TelemetryPoint>[];
    final now = live?.ch[_port]?.v;
    final events = (ref.watch(eventsProvider(site.id)).value ?? const <AppEvent>[]).where((e) => e.hubId == hub.id).take(3).toList();

    final values = points.map((p) => p.v).toList();
    double? trend;
    if (points.length > 6) trend = points.last.v - points[points.length - 7].v;
    final fmt = DateFormat(_hours <= 24 ? 'HH.mm' : 'd MMM', 'id');
    final labels = points.isEmpty
        ? <String>[]
        : [for (var i = 0; i < 5; i++) fmt.format(points[(i * (points.length - 1) / 4).round()].t)];
    if (labels.isNotEmpty) labels[labels.length - 1] = 'Kini';
    final t = thresholdFor(metric, zone);
    final maxY = [...values, if (t?.ideal != null) t!.ideal!.$2].fold<double>(0, (a, b) => b > a ? b : a) * 1.1;
    final isPro = ref.watch(profileProvider).value?.planTier == 'pro';

    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(children: [
            RoundIconButton(Icons.arrow_back_rounded, onPressed: () => context.pop()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Telemetri', style: T.h2),
                Text('${zone?.name ?? hub.displayName} · ${hub.ports.length} sensor', style: T.small),
              ]),
            ),
            RoundIconButton(Icons.download_rounded, onPressed: () => isPro ? showMessage(context, 'Laporan sedang disiapkan…') : context.push('/paywall')),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final e in hub.ports.entries) ...[
                SelectChip(metricDef(e.value.metric).label, icon: metricDef(e.value.metric).icon, selected: e.key == _port,
                    onTap: () => setState(() => _port = e.key)),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          Glass(
            strong: true,
            radius: 30,
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(def.label, style: T.label),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(now == null ? '–' : formatValue(now, metric), style: T.s(44, w: FontWeight.w600, ls: -1.5, h: 1)),
                      const SizedBox(width: 5),
                      Text(def.unit, style: T.s(16, w: FontWeight.w500, c: AppColors.ink2)),
                    ]),
                  ]),
                ),
                if (trend != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: trend < 0 ? const Color(0x26F5A524) : const Color(0xFFEEF3FA), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(trend < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded, size: 16,
                          color: trend < 0 ? AppColors.amberInk : AppColors.ink2),
                      const SizedBox(width: 4),
                      Text('${trend < 0 ? '−' : '+'}${formatValue(trend.abs(), metric)}', style: T.s(13, w: FontWeight.w600,
                          c: trend < 0 ? AppColors.amberInk : AppColors.ink2)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 16),
              _RangeSwitch(hours: _hours, onChanged: (h) => setState(() => _hours = h)),
              const SizedBox(height: 16),
              hist.isLoading
                  ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
                  : BarChart(
                      values: values.length > 24 ? _downsample(values, 24) : values,
                      height: 180,
                      maxY: maxY <= 0 ? null : maxY,
                      levelOf: (v) => levelFor(metric, v, zone),
                      labels: labels,
                    ),
              const SizedBox(height: 12),
              Wrap(spacing: 16, children: [
                _legend(AppColors.blue, 'Aman'),
                _legend(AppColors.amber, 'Waspada'),
                if (idealLabel(metric, zone).isNotEmpty) Text(idealLabel(metric, zone), style: T.small),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          if (values.isNotEmpty)
            Row(children: [
              _stat('Terendah', formatValue(values.reduce((a, b) => a < b ? a : b), metric), AppColors.amberInk),
              const SizedBox(width: 10),
              _stat('Rata-rata', formatValue(values.reduce((a, b) => a + b) / values.length, metric), AppColors.ink),
              const SizedBox(width: 10),
              _stat('Tertinggi', formatValue(values.reduce((a, b) => a > b ? a : b), metric), AppColors.greenInk),
            ]),
          const SizedBox(height: 22),
          Text('Kejadian terkait', style: T.h2),
          const SizedBox(height: 12),
          Divided(children: [
            for (final e in events) EventRow(e, hub: hub, zones: zones),
            if (assignment.calibratedAt != null || metric == 'ph' || metric == 'do')
              ListRow(
                leading: const IconChip(Icons.biotech_outlined, size: 36),
                title: 'Kalibrasi sensor',
                subtitle: assignment.calibratedAt == null
                    ? 'Belum pernah dikalibrasi'
                    : 'Terakhir ${relativeTime(assignment.calibratedAt!, DateTime.now())} · disarankan tiap 30 hari',
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
                onTap: () => context.push('/calibrate/${hub.id}/$_port'),
              ),
          ]),
          const SizedBox(height: 18),
          PrimaryButton(isPro ? 'Unduh laporan (CSV / PDF)' : 'Unduh laporan · Pro', icon: Icons.file_download_outlined,
              color: AppColors.ink, onPressed: () => isPro ? showMessage(context, 'Laporan sedang disiapkan…') : context.push('/paywall')),
        ],
      ),
    );
  }

  List<double> _downsample(List<double> v, int n) {
    final size = v.length / n;
    return [
      for (var i = 0; i < n; i++)
        () {
          final part = v.sublist((i * size).floor(), ((i + 1) * size).floor().clamp(0, v.length));
          return part.isEmpty ? v[(i * size).floor()] : part.reduce((a, b) => a + b) / part.length;
        }(),
    ];
  }

  Widget _legend(Color c, String l) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 6),
        Text(l, style: T.small),
      ]);

  Widget _stat(String l, String v, Color c) => Expanded(
        child: Glass(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: T.small),
            const SizedBox(height: 4),
            Text(v, style: T.s(24, w: FontWeight.w600, c: c, ls: -0.5)),
          ]),
        ),
      );
}

class _RangeSwitch extends StatelessWidget {
  const _RangeSwitch({required this.hours, required this.onChanged});
  final int hours;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0x0F1C6FE8), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          for (final (h, l) in const [(24, '24 jam'), (168, '7 hari'), (720, '30 hari')])
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(h),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: h == hours ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: h == hours ? const [BoxShadow(color: Color(0x1A1E3A8A), blurRadius: 6, offset: Offset(0, 2))] : null,
                  ),
                  child: Text(l, style: T.s(14, w: h == hours ? FontWeight.w600 : FontWeight.w500, c: h == hours ? AppColors.ink : AppColors.ink2)),
                ),
              ),
            ),
        ]),
      );
}
