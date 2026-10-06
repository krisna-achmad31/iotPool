import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/catalog.dart';
import '../../domain/logic.dart';
import '../../domain/models.dart';
import 'relay_control.dart';

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});
  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  String? _kind;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(sitesProvider).value ?? const <Site>[];
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final entries = <(Site, Hub, LiveState?)>[];
    for (final s in sites.where((s) => _kind == null || s.kind == _kind)) {
      for (final h in ref.watch(siteHubsProvider(s.id))) {
        if (_q.isNotEmpty && !'${h.displayName} ${h.id} ${s.name}'.toLowerCase().contains(_q.toLowerCase())) continue;
        entries.add((s, h, ref.watch(liveProvider(h.id)).value));
      }
    }
    final online = entries.where((e) => e.$3?.isOnline(now) ?? false).length;
    final relays = <RelayView>[
      for (final (_, h, live) in entries)
        for (final r in h.relays.entries)
          RelayView(hub: h, relay: r.key, assignment: r.value, state: live?.relays[r.key], online: live?.isOnline(now) ?? false),
    ];
    final kinds = sites.map((s) => s.kind).toSet().toList();

    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Row(children: [
            Expanded(child: Text('Perangkat', style: T.title)),
            RoundIconButton(Icons.qr_code_scanner_rounded, onPressed: () => context.push('/add-device')),
            const SizedBox(width: 10),
            RoundIconButton(Icons.add_rounded, filled: true, onPressed: () => context.push('/add-device')),
          ]),
          const SizedBox(height: 16),
          Glass(
            radius: 26,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: T.s(16),
              decoration: InputDecoration(
                border: InputBorder.none,
                icon: const Icon(Icons.search_rounded, color: AppColors.ink2),
                hintText: 'Cari perangkat…',
                hintStyle: T.s(16, c: AppColors.ink2),
              ),
            ),
          ),
          if (kinds.length > 1) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              SelectChip('Semua', selected: _kind == null, onTap: () => setState(() => _kind = null)),
              for (final k in kinds) SelectChip(siteKindLabel(k), selected: _kind == k, onTap: () => setState(() => _kind = k)),
            ]),
          ],
          const SizedBox(height: 16),
          BlueCard(
            radius: 28,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.memory_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${entries.length} hub · ${relays.length} alat', style: T.s(20, w: FontWeight.w600, c: Colors.white)),
                  Text('$online online${entries.length - online > 0 ? ' · ${entries.length - online} terputus' : ''}', style: T.s(14, c: const Color(0xFFDDEBFF))),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          SectionHeader('Hub', trailing: '${entries.length} perangkat'),
          const SizedBox(height: 12),
          for (final (site, hub, live) in entries) ...[
            _HubCard(site: site, hub: hub, live: live, now: now),
            const SizedBox(height: 12),
          ],
          if (entries.isEmpty) Glass(child: Text('Belum ada hub. Tekan + untuk menambah perangkat.', style: T.body)),
          if (relays.isNotEmpty) ...[
            const SizedBox(height: 10),
            const SectionHeader('Alat kontrol', trailing: 'Ketuk sakelar untuk nyalakan'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (_, c) => Wrap(spacing: 12, runSpacing: 12, children: [
                for (final r in relays) SizedBox(width: (c.maxWidth - 12) / 2, child: RelayTile(r)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.site, required this.hub, required this.live, required this.now});
  final Site site;
  final Hub hub;
  final LiveState? live;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final on = live?.isOnline(now) ?? false;
    final meta = on
        ? '${hub.ports.length} modul · ${hub.relays.length} relay'
        : 'Terputus ${live == null ? '' : relativeTime(live!.ts, now)}';
    return Glass(
      strong: true,
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/device/${hub.id}'),
      child: Row(children: [
        Opacity(
          opacity: on ? 1 : 0.55,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.router_rounded, size: 36, color: AppColors.blue),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hub.displayName, style: T.s(17, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(siteIcon(site.kind), size: 14, color: AppColors.ink2),
              const SizedBox(width: 5),
              Flexible(child: Text(site.name, style: T.small, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            StatusPill(on ? Level.good : Level.danger, meta),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
      ]),
    );
  }
}
