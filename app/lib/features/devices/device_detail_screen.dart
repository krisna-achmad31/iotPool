import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/catalog.dart';
import '../../domain/logic.dart';
import '../../domain/models.dart';

class DeviceDetailScreen extends ConsumerWidget {
  const DeviceDetailScreen({super.key, required this.hubId});
  final String hubId;

  Future<void> _cmd(BuildContext context, WidgetRef ref, String type, String done, [Map<String, dynamic> args = const {}]) async {
    showMessage(context, 'Mengirim perintah…');
    final r = await ref.read(repositoryProvider).sendCommand(hubId, type, args);
    if (context.mounted) showMessage(context, r.ok ? done : 'Hub tidak menjawab (${r.code}).');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = ref.watch(hubProvider(hubId)).value;
    final live = ref.watch(liveProvider(hubId)).value;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    if (hub == null) return const AppPage(child: Center(child: CircularProgressIndicator()));
    final online = live?.isOnline(now) ?? false;
    final site = (ref.watch(sitesProvider).value ?? const <Site>[]).where((s) => s.id == hub.siteId).firstOrNull;
    final zones = site == null ? const <Zone>[] : ref.watch(zonesProvider(site.id)).value ?? const <Zone>[];
    final isOwner = site?.roleOf(ref.watch(authUidProvider).value ?? '') == Role.owner;

    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(children: [
            RoundIconButton(Icons.arrow_back_rounded, onPressed: () => context.pop()),
            const SizedBox(width: 12),
            Expanded(child: Text('Detail perangkat', style: T.h2)),
          ]),
          const SizedBox(height: 18),
          Glass(
            strong: true,
            radius: 32,
            padding: EdgeInsets.zero,
            child: Column(children: [
              Container(
                height: 160,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFDCE8FF), Color(0xFFE9E2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: const Center(child: Icon(Icons.router_rounded, size: 84, color: AppColors.blue)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(hub.displayName, style: T.s(24, w: FontWeight.w600, ls: -0.4)),
                        Text('Sysnergi Hub · ${hub.id}', style: T.small),
                      ]),
                    ),
                    StatusPill(online ? Level.good : Level.danger, online ? 'Online' : 'Terputus'),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    _vital(Icons.wifi_rounded, online ? (live?.signalLabel ?? '-') : '-', 'Sinyal'),
                    const SizedBox(width: 8),
                    _vital(Icons.power_outlined, switch (live?.power) { 'mains' => 'PLN', 'solar' => 'Surya', 'battery' => 'Baterai', _ => '-' }, 'Daya'),
                    const SizedBox(width: 8),
                    _vital(Icons.timer_outlined, live?.uptime == null ? '-' : '${live!.uptime!.inDays} hari', 'Aktif'),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          SectionHeader('Modul terpasang', trailing: '${hub.ports.length} dari 6 port'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              for (final p in kPortIds) _portTile(context, hub, p, live, zones),
            ],
          ),
          const SizedBox(height: 22),
          SectionHeader('Output relay', trailing: '${hub.relays.length} dari 4'),
          const SizedBox(height: 12),
          Divided(children: [
            for (final r in kRelayIds)
              if (hub.relays[r] case final a?)
                ListRow(
                  leading: IconChip(actuatorDef(a.kind).icon, size: 40),
                  title: '$r · ${a.label}',
                  subtitle: (live?.relays[r]?.on ?? false)
                      ? 'Nyala · ${live!.relays[r]!.mode == 'auto' ? 'otomatis' : 'manual'}'
                      : 'Mati',
                  trailing: TextButton(
                    onPressed: online ? () => _cmd(context, ref, 'test_relay', '${a.label} dites 3 detik', {'relay': r}) : null,
                    child: Text('Uji', style: T.s(14, w: FontWeight.w600, c: online ? AppColors.blue : AppColors.muted)),
                  ),
                )
              else
                ListRow(
                  leading: const IconChip(Icons.add_rounded, size: 40),
                  title: '$r · Belum dipakai',
                  titleColor: AppColors.ink2,
                  subtitle: 'Sambungkan alat ke relay ini',
                ),
          ]),
          const SizedBox(height: 22),
          Divided(children: [
            ListRow(
              leading: const Icon(Icons.biotech_outlined, color: AppColors.ink),
              title: 'Kalibrasi sensor',
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
              onTap: () {
                final ph = hub.ports.entries.where((e) => e.value.metric == 'ph').firstOrNull ?? hub.ports.entries.firstOrNull;
                if (ph != null) context.push('/calibrate/${hub.id}/${ph.key}');
              },
            ),
            ListRow(
              leading: const Icon(Icons.lightbulb_outline_rounded, color: AppColors.ink),
              title: 'Kedipkan lampu hub',
              subtitle: 'Untuk mencari hub yang mana',
              onTap: online ? () => _cmd(context, ref, 'identify', 'Lampu hub berkedip') : null,
            ),
            ListRow(
              leading: const Icon(Icons.restart_alt_rounded, color: AppColors.ink),
              title: 'Mulai ulang hub',
              onTap: online ? () => _cmd(context, ref, 'restart', 'Hub dimulai ulang') : null,
            ),
            if (isOwner)
              ListRow(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
                title: 'Lepas perangkat dari akun',
                titleColor: AppColors.red,
                onTap: () => showMessage(context, 'Hubungi CS untuk melepas hub (fitur menyusul).'),
              ),
          ]),
          const SizedBox(height: 12),
          Center(child: Text('Firmware ${live?.fw ?? hub.fwVersion ?? '-'} · ${hub.connectivity == '4g' ? '4G' : 'Wi‑Fi'}', style: T.s(12, c: AppColors.muted))),
        ],
      ),
    );
  }

  Widget _vital(IconData i, String v, String l) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0x0F2F6BFF), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 20, color: AppColors.blue),
            const SizedBox(height: 6),
            Text(v, style: T.s(16, w: FontWeight.w600)),
            Text(l, style: T.s(12, c: AppColors.ink2)),
          ]),
        ),
      );

  Widget _portTile(BuildContext context, Hub hub, String p, LiveState? live, List<Zone> zones) {
    final a = hub.ports[p];
    if (a == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x59FFFFFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF9AA8D0), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const IconChip(Icons.add_rounded, size: 34), const Spacer(), Text(p, style: T.s(12, w: FontWeight.w600, c: AppColors.ink2))]),
          const Spacer(),
          Text('Kosong', style: T.s(14, w: FontWeight.w500, c: AppColors.ink2)),
        ]),
      );
    }
    final def = metricDef(a.metric);
    final v = live?.ch[p]?.v;
    final zone = zones.where((z) => z.id == a.zoneId).firstOrNull;
    return Glass(
      radius: 22,
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/telemetry/${hub.id}/$p'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [IconChip(def.icon, size: 34), const Spacer(), Text(p, style: T.s(12, w: FontWeight.w600, c: AppColors.ink2))]),
        const Spacer(),
        Text(def.label, style: T.s(13, w: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(v == null ? zone?.name ?? '' : '${formatValue(v, a.metric)} ${def.unit}', style: T.s(12, c: AppColors.ink2), maxLines: 1),
      ]),
    );
  }
}

/// Dipakai juga oleh detail sensor: teks "terakhir dikalibrasi".
String calibrationText(PortAssignment a) =>
    a.calibratedAt == null ? 'Belum pernah dikalibrasi' : 'Dikalibrasi ${relativeTime(a.calibratedAt!, DateTime.now())}';
