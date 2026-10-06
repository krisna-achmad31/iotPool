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

/// Teks event dirender di app dari field terstruktur (docs/data-model.md · events).
({String title, String body, IconData icon}) describeEvent(AppEvent e, {Hub? hub, List<Zone> zones = const [], List<Automation> rules = const []}) {
  final zone = zones.where((z) => z.id == e.zoneId).firstOrNull;
  final where = zone?.name ?? hub?.displayName ?? '';
  final metric = e.metric ?? (e.ch == null ? null : hub?.ports[e.ch]?.metric);
  final def = metric == null ? null : metricDef(metric);
  final relayLabel = e.relay == null ? null : hub?.relays[e.relay]?.label ?? e.relay;
  final rule = rules.where((r) => r.id == e.ruleId).firstOrNull;
  return switch (e.type) {
    'alarm' => (
        title: def == null
            ? 'Peringatan sensor'
            : '${def.label} ${e.value == null ? 'di luar batas' : 'ke ${formatValue(e.value!, metric!)} ${def.unit}'.trim()}',
        body: e.severity == Severity.danger
            ? '$where · segera dicek. ${metric == 'do' ? 'Ikan bisa naik ke permukaan.' : ''}'.trim()
            : '$where · di luar batas aman',
        icon: def?.icon ?? Icons.warning_amber_rounded,
      ),
    'alarm_clear' => (title: '${def?.label ?? 'Sensor'} kembali normal', body: where, icon: Icons.check_circle_outline_rounded),
    'hub_offline' => (title: '${hub?.displayName ?? 'Hub'} terputus', body: 'Aturan tetap jalan di hub. Data dikirim saat online lagi.', icon: Icons.wifi_off_rounded),
    'hub_online' => (title: '${hub?.displayName ?? 'Hub'} tersambung lagi', body: where, icon: Icons.wifi_rounded),
    'automation_start' => (
        title: '${relayLabel ?? 'Alat'} menyala otomatis',
        body: rule == null ? where : 'Aturan “${rule.name}”',
        icon: Icons.auto_awesome_outlined,
      ),
    'automation_stop' => (title: '${relayLabel ?? 'Alat'} berhenti otomatis', body: rule == null ? where : 'Aturan “${rule.name}”', icon: Icons.auto_awesome_outlined),
    'command' => (title: '${relayLabel ?? 'Alat'} dikontrol manual', body: where, icon: Icons.touch_app_outlined),
    'calibration_due' => (
        title: 'Waktunya kalibrasi ${def?.label ?? 'sensor'}',
        body: '$where · butuh sekitar 10 menit',
        icon: Icons.biotech_outlined,
      ),
    'firmware_available' => (title: 'Pembaruan hub tersedia', body: hub?.displayName ?? '', icon: Icons.system_update_alt_rounded),
    _ => (title: e.title ?? 'Info', body: e.body ?? '', icon: e.type == 'report' ? Icons.auto_awesome : Icons.info_outline_rounded),
  };
}

class EventRow extends ConsumerWidget {
  const EventRow(this.e, {super.key, this.hub, this.zones = const [], this.rules = const [], this.unread = false});
  final AppEvent e;
  final Hub? hub;
  final List<Zone> zones;
  final List<Automation> rules;
  final bool unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = hub ?? (e.hubId == null ? null : ref.watch(hubProvider(e.hubId!)).value);
    final d = describeEvent(e, hub: h, zones: zones, rules: rules);
    final color = switch (e.severity) { Severity.danger => AppColors.red, Severity.warning => AppColors.amberInk, _ => AppColors.blue };
    return InkWell(
      onTap: e.hubId != null && e.ch != null ? () => context.push('/telemetry/${e.hubId}/${e.ch}') : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconChip(d.icon, color: color, bg: e.severity == Severity.info ? null : color.withValues(alpha: 0.1)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(d.title, style: T.s(15, w: FontWeight.w600, h: 1.3))),
                if (unread) Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle)),
              ]),
              if (d.body.isNotEmpty) ...[const SizedBox(height: 3), Text(d.body, style: T.s(14, c: AppColors.ink2, h: 1.4))],
              const SizedBox(height: 3),
              Text(DateFormat('HH.mm', 'id').format(e.ts), style: T.s(12, w: FontWeight.w500, c: AppColors.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  Severity? _filter;

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(currentSiteProvider);
    if (site == null) return const AppPage(child: SizedBox());
    final all = ref.watch(eventsProvider(site.id)).value ?? const <AppEvent>[];
    final zones = ref.watch(zonesProvider(site.id)).value ?? const <Zone>[];
    final rules = ref.watch(automationsProvider(site.id)).value ?? const <Automation>[];
    final events = all.where((e) => _filter == null || e.severity == _filter || (_filter == Severity.info && e.severity == Severity.warning)).toList();
    final now = DateTime.now();
    final critical = events.where((e) => e.severity == Severity.danger && now.difference(e.ts).inHours < 6).firstOrNull;
    final rest = events.where((e) => e != critical).toList();
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final today = rest.where((e) => sameDay(e.ts, now)).toList();
    final older = rest.where((e) => !sameDay(e.ts, now)).toList();

    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(children: [
            RoundIconButton(Icons.arrow_back_rounded, onPressed: () => context.pop()),
            const SizedBox(width: 12),
            Expanded(child: Text('Notifikasi', style: T.title)),
            TextButton(
              onPressed: () {
                ref.read(repositoryProvider).markEventsRead(site.id);
                showMessage(context, 'Semua ditandai sudah dibaca');
              },
              child: Text('Tandai dibaca', style: T.s(15, w: FontWeight.w500, c: AppColors.blue)),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SelectChip('Semua · ${all.length}', selected: _filter == null, onTap: () => setState(() => _filter = null)),
            SelectChip('Bahaya · ${all.where((e) => e.severity == Severity.danger).length}', selected: _filter == Severity.danger,
                onTap: () => setState(() => _filter = Severity.danger)),
            SelectChip('Info · ${all.where((e) => e.severity != Severity.danger).length}', selected: _filter == Severity.info,
                onTap: () => setState(() => _filter = Severity.info)),
          ]),
          const SizedBox(height: 18),
          if (events.isEmpty) Glass(child: Text('Belum ada notifikasi. Kami kabari kalau ada yang perlu dicek.', style: T.body)),
          if (critical != null) ...[
            _group('SEKARANG'),
            _CriticalCard(e: critical, zones: zones),
            const SizedBox(height: 16),
          ],
          if (today.isNotEmpty) ...[
            _group('HARI INI'),
            Divided(children: [for (final e in today) EventRow(e, zones: zones, rules: rules, unread: now.difference(e.ts).inHours < 1)]),
            const SizedBox(height: 16),
          ],
          if (older.isNotEmpty) ...[
            _group('SEBELUMNYA'),
            Divided(children: [for (final e in older) EventRow(e, zones: zones, rules: rules)]),
          ],
        ],
      ),
    );
  }

  Widget _group(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: T.s(13, w: FontWeight.w600, c: AppColors.ink2, ls: 0.6)),
      );
}

class _CriticalCard extends ConsumerWidget {
  const _CriticalCard({required this.e, required this.zones});
  final AppEvent e;
  final List<Zone> zones;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = e.hubId == null ? null : ref.watch(hubProvider(e.hubId!)).value;
    final d = describeEvent(e, hub: hub, zones: zones);
    final zone = zones.where((z) => z.id == e.zoneId).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F3),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF6C4C8), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x1FEF4E5A), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconChip(Icons.campaign_rounded, size: 44, color: AppColors.red, bg: const Color(0x1AEF4E5A)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('BAHAYA · ${zone?.name ?? ''}', style: T.s(12, w: FontWeight.w600, c: AppColors.red, ls: 0.6)),
              Text('${DateFormat('HH.mm', 'id').format(e.ts)} · ${relativeTime(e.ts, DateTime.now())}', style: T.small),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(d.title, style: T.s(22, w: FontWeight.w600, ls: -0.3)),
        const SizedBox(height: 6),
        Text(d.body, style: T.s(15, c: const Color(0xFF4A3B3D), h: 1.45)),
        const SizedBox(height: 14),
        PrimaryButton('Lihat kondisi', icon: Icons.show_chart_rounded, color: AppColors.red, height: 52,
            onPressed: e.hubId != null && e.ch != null ? () => context.push('/telemetry/${e.hubId}/${e.ch}') : null),
      ]),
    );
  }
}
