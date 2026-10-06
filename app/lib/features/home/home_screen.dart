import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/catalog.dart';
import '../../domain/logic.dart';
import '../../domain/models.dart';
import '../devices/relay_control.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(sitesProvider);
    final site = ref.watch(currentSiteProvider);
    final profile = ref.watch(profileProvider).value;

    if (sitesAsync.isLoading) return const AppPage(child: Center(child: CircularProgressIndicator()));
    if (site == null) return _NoSite(name: profile?.displayName);

    final zones = ref.watch(zonesProvider(site.id)).value ?? const <Zone>[];
    final selectedZoneId = ref.watch(selectedZoneIdProvider);
    final zone = zones.where((z) => z.id == selectedZoneId).firstOrNull ?? zones.firstOrNull;
    final events = ref.watch(eventsProvider(site.id)).value ?? const <AppEvent>[];
    final unread = events.where((e) => e.severity != Severity.info && DateTime.now().difference(e.ts).inHours < 24).length;

    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          _Header(site: site, profile: profile, unread: unread),
          const SizedBox(height: 18),
          if (site.hubIds.isEmpty)
            const _EmptyHub()
          else ...[
            if (zones.length > 1) ...[
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: zones.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _ZoneChip(site: site, zone: zones[i], selected: zones[i].id == zone?.id),
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (zone != null) _ZoneBody(site: site, zone: zone),
          ],
          const SizedBox(height: 18),
          _AskAi(onTap: () => context.push('/assistant')),
        ],
      ),
    );
  }
}

String _greeting() {
  final h = DateTime.now().hour;
  return h < 11 ? 'Selamat pagi' : h < 15 ? 'Selamat siang' : h < 18 ? 'Selamat sore' : 'Selamat malam';
}

class _Header extends ConsumerWidget {
  const _Header({required this.site, required this.profile, required this.unread});
  final Site site;
  final UserProfile? profile;
  final int unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sitesProvider).value ?? const <Site>[];
    return Row(children: [
      Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient, border: Border.all(color: Colors.white, width: 2)),
        child: Text(profile?.initials ?? '', style: T.s(18, w: FontWeight.w600, c: Colors.white)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: sites.length < 2 ? null : () => _pickSite(context, ref, sites),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_greeting()}, ${profile?.displayName?.split(' ').first ?? ''}', style: T.s(15, c: AppColors.ink2)),
            Row(children: [
              Flexible(child: Text(site.name, style: T.s(24, w: FontWeight.w600, ls: -0.4), overflow: TextOverflow.ellipsis)),
              if (sites.length > 1) const Icon(Icons.expand_more_rounded, color: AppColors.ink2),
            ]),
          ]),
        ),
      ),
      RoundIconButton(Icons.notifications_none_rounded, size: 52, badge: unread, onPressed: () => context.push('/notifications')),
    ]);
  }

  void _pickSite(BuildContext context, WidgetRef ref, List<Site> sites) {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pilih lokasi', style: T.h2),
            const SizedBox(height: 12),
            for (final s in sites)
              ListRow(
                leading: IconChip(siteIcon(s.kind), filled: s.id == site.id),
                title: s.name,
                subtitle: '${siteKindLabel(s.kind)} · ${s.hubIds.length} hub',
                trailing: s.id == site.id ? const Icon(Icons.check_rounded, color: AppColors.blue) : null,
                onTap: () {
                  ref.read(selectedSiteIdProvider.notifier).select(s.id);
                  ref.read(selectedZoneIdProvider.notifier).select(null);
                  Navigator.pop(c);
                },
              ),
            const SizedBox(height: 8),
            SecondaryButton('Tambah usaha', icon: Icons.add_rounded, onPressed: () {
              Navigator.pop(c);
              context.push('/onboarding');
            }),
          ]),
        ),
      ),
    );
  }
}

/// Level terburuk di sebuah zona (untuk titik di chip & kartu hero).
Level _worst(Iterable<Level> ls) => ls.fold(Level.good, (a, b) => b.index > a.index && b != Level.unknown ? b : a);

class _ZoneChip extends ConsumerWidget {
  const _ZoneChip({required this.site, required this.zone, required this.selected});
  final Site site;
  final Zone zone;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chs = ref.watch(zoneChannelsProvider((siteId: site.id, zoneId: zone.id)));
    final offline = chs.isNotEmpty && chs.every((c) => !c.online);
    final worst = _worst(chs.where((c) => c.online).map((c) => levelFor(c.metric, c.value, zone)));
    final dot = offline ? AppColors.red : worst == Level.danger ? AppColors.red : worst == Level.warn ? AppColors.amber : null;
    return SelectChip(zone.name, selected: selected, dot: dot, onTap: () => ref.read(selectedZoneIdProvider.notifier).select(zone.id));
  }
}

class _ZoneBody extends ConsumerWidget {
  const _ZoneBody({required this.site, required this.zone});
  final Site site;
  final Zone zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (siteId: site.id, zoneId: zone.id);
    final chs = ref.watch(zoneChannelsProvider(key));
    final relays = ref.watch(zoneRelaysProvider(key));
    final offline = chs.isNotEmpty && chs.every((c) => !c.online);
    final sectionTitle = switch (site.kind) { 'aquaculture' => 'Kualitas air', 'horticulture' => 'Kondisi lahan', 'livestock' => 'Kondisi kandang', _ => 'Kondisi' };

    if (chs.isEmpty) {
      return Glass(child: Text('Belum ada sensor di ${zone.name}. Pasang modul di hub, lalu atur port di Detail perangkat.', style: T.body));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      offline ? _OfflineHero(zone: zone, hub: chs.first.hub) : _Hero(zone: zone, channels: chs, relays: relays),
      const SizedBox(height: 22),
      SectionHeader(offline ? 'Data terakhir' : sectionTitle,
          action: 'Telemetri', onAction: () => context.push('/telemetry/${chs.first.hub.id}/${chs.first.port}')),
      const SizedBox(height: 12),
      _Grid(children: [for (final c in chs) _ChannelTile(c, zone: zone)]),
      if (relays.isNotEmpty) ...[
        const SizedBox(height: 22),
        SectionHeader(offline ? 'Perangkat (tidak bisa dikontrol)' : 'Perangkat', action: 'Semua', onAction: () => context.go('/devices')),
        const SizedBox(height: 12),
        _Grid(children: [for (final r in relays) RelayTile(r)]),
      ],
    ]);
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final w in children) SizedBox(width: (c.maxWidth - 12) / 2, child: w)],
        ),
      );
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.zone, required this.channels, required this.relays});
  final Zone zone;
  final List<ChannelView> channels;
  final List<RelayView> relays;

  /// Alat yang paling relevan untuk metric bermasalah.
  RelayView? _fixFor(String metric) {
    final kinds = switch (metric) {
      'do' => ['aerator'],
      'water_level' => ['pump_fill'],
      'soil_moisture' || 'tank_level' => ['pump_irrigation', 'pump_fill'],
      'air_temp' || 'nh3_air' => ['exhaust_fan'],
      'water_temp' => ['aerator'],
      _ => const <String>[],
    };
    return relays.where((r) => kinds.contains(r.assignment.kind)).firstOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranked = [...channels]..sort((a, b) => levelFor(b.metric, b.value, zone).index.compareTo(levelFor(a.metric, a.value, zone).index));
    final top = ranked.first;
    final level = levelFor(top.metric, top.value, zone);
    final bad = level == Level.warn || level == Level.danger;
    final def = metricDef(top.metric);
    final fix = bad ? _fixFor(top.metric) : null;
    final hist = ref.watch(historyProvider((hubId: top.hub.id, port: top.port, hours: 24))).value ?? const [];
    final spark = hist.length > 8 ? hist.sublist(hist.length - 8) : hist;

    return BlueCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _pill(Icon(siteIconForZone(zone.kind), size: 16, color: Colors.white), zone.subtitle, const Color(0x26FFFFFF), Colors.white),
          const Spacer(),
          bad
              ? _pill(Icon(Icons.warning_amber_rounded, size: 16, color: level == Level.danger ? Colors.white : const Color(0xFF3D2400)),
                  level == Level.danger ? 'Bahaya' : 'Perlu dicek', level == Level.danger ? AppColors.red : AppColors.amber,
                  level == Level.danger ? Colors.white : const Color(0xFF3D2400))
              : _pill(const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.white), 'Semua aman', const Color(0x33FFFFFF), Colors.white),
        ]),
        const SizedBox(height: 14),
        Text(bad ? headline(top.metric, level) : '${zone.name} dalam kondisi baik', style: T.s(22, w: FontWeight.w600, c: Colors.white, ls: -0.3)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(top.value == null ? '–' : formatValue(top.value!, top.metric), style: T.s(64, w: FontWeight.w600, c: Colors.white, ls: -2, h: 1)),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(def.unit, style: T.s(18, w: FontWeight.w500, c: const Color(0xFFC9D8FF)))),
          const Spacer(),
          SizedBox(
            width: 92,
            height: 48,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < spark.length; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: _sparkH(spark, i),
                    decoration: BoxDecoration(
                      color: levelFor(top.metric, spark[i].v, zone).index >= Level.warn.index && i >= spark.length - 2
                          ? const Color(0xFFFFC56B)
                          : const Color(0x59FFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          [
            idealLabel(top.metric, zone),
            if (fix != null)
              fix.on
                  ? '${fix.assignment.label} sedang menyala${fix.state?.mode == 'auto' ? ' otomatis' : ''}.'
                  : '${fix.assignment.label} bisa dinyalakan dari sini.',
          ].where((s) => s.isNotEmpty).join('. '),
          style: T.s(15, c: const Color(0xFFDDEBFF), h: 1.45),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, shape: const StadiumBorder()),
                onPressed: fix != null && !fix.on
                    ? () => toggleRelay(context, ref, fix, true)
                    : () => context.push('/telemetry/${top.hub.id}/${top.port}'),
                icon: Icon(fix != null && !fix.on ? actuatorDef(fix.assignment.kind).icon : Icons.show_chart_rounded, color: AppColors.blue),
                label: Text(
                  fix != null && !fix.on ? 'Nyalakan ${fix.assignment.label.toLowerCase()}' : 'Lihat grafik',
                  style: T.s(16, w: FontWeight.w600, c: AppColors.ink),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            height: 56,
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: const Color(0x26FFFFFF)),
              onPressed: () => context.push('/telemetry/${top.hub.id}/${top.port}'),
              icon: const Icon(Icons.show_chart_rounded, color: Colors.white),
              tooltip: 'Grafik',
            ),
          ),
        ]),
      ]),
    );
  }

  double _sparkH(List<TelemetryPoint> pts, int i) {
    final vs = pts.map((p) => p.v);
    final lo = vs.reduce((a, b) => a < b ? a : b), hi = vs.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 1e-9 ? 1 : hi - lo;
    return 16 + 32 * ((pts[i].v - lo) / span);
  }

  Widget _pill(Widget icon, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(width: 6), Text(text, style: T.s(14, w: FontWeight.w600, c: fg))]),
      );
}

IconData siteIconForZone(String kind) => switch (kind) {
      'pond' || 'tank' => Icons.set_meal_rounded,
      'greenhouse' || 'bed' || 'field' => Icons.eco_rounded,
      'barn' || 'coop' => Icons.egg_alt_rounded,
      _ => Icons.place_rounded,
    };

class _OfflineHero extends ConsumerWidget {
  const _OfflineHero({required this.zone, required this.hub});
  final Zone zone;
  final Hub hub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveProvider(hub.id)).value;
    final ago = live == null ? 'belum pernah' : relativeTime(live.ts, DateTime.now());
    return Column(children: [
      BlueCard(
        gradient: AppColors.greyGradient,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(zone.subtitle, style: T.s(14, w: FontWeight.w600, c: Colors.white)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text('Terputus', style: T.s(14, w: FontWeight.w600, c: Colors.white)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Text('Hub tidak mengirim data', style: T.s(22, w: FontWeight.w600, c: Colors.white)),
          const SizedBox(height: 6),
          Text('Terakhir $ago', style: T.s(18, w: FontWeight.w500, c: Colors.white)),
          const SizedBox(height: 8),
          Text('Aturan otomatis tetap jalan di hub. Data yang tertunda akan dikirim saat online lagi.', style: T.s(15, c: const Color(0xFFE6ECF4), h: 1.45)),
        ]),
      ),
      const SizedBox(height: 12),
      Divided(strong: true, children: [
        for (final (icon, title, sub) in const [
          (Icons.power_outlined, 'Cek listrik ke hub', 'Lampu hub harus menyala'),
          (Icons.router_outlined, 'Cek router Wi‑Fi', 'Coba nyalakan ulang router'),
          (Icons.wifi_rounded, 'Ganti Wi‑Fi hub', 'Kalau sandi Wi‑Fi baru diubah'),
        ])
          ListRow(
            leading: IconChip(icon),
            title: title,
            subtitle: sub,
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
            onTap: () => context.push('/device/${hub.id}'),
          ),
      ]),
    ]);
  }
}

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile(this.c, {required this.zone});
  final ChannelView c;
  final Zone zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final def = metricDef(c.metric);
    final level = c.online ? levelFor(c.metric, c.value, zone) : Level.unknown;
    final hist = ref.watch(historyProvider((hubId: c.hub.id, port: c.port, hours: 24))).value ?? const [];
    final spark = hist.length > 7 ? hist.sublist(hist.length - 7) : hist;
    return Opacity(
      opacity: c.online ? 1 : 0.55,
      child: Glass(
        onTap: () => context.push('/telemetry/${c.hub.id}/${c.port}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconChip(def.icon),
            const Spacer(),
            StatusPill(level, c.online ? levelLabel(level) : 'Terputus'),
          ]),
          const SizedBox(height: 12),
          Text(def.label, style: T.s(15, w: FontWeight.w500, c: AppColors.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Flexible(child: Text(c.value == null ? '–' : formatValue(c.value!, c.metric), style: T.s(30, w: FontWeight.w600, ls: -0.8, h: 1))),
            const SizedBox(width: 4),
            Text(def.unit, style: T.s(14, w: FontWeight.w500, c: AppColors.ink2)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 24,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < spark.length; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    height: 10 + 14 * _norm(spark, i),
                    decoration: BoxDecoration(
                      color: i == spark.length - 1 ? AppColors.blue : const Color(0x331C6FE8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  double _norm(List<TelemetryPoint> p, int i) {
    final lo = p.map((e) => e.v).reduce((a, b) => a < b ? a : b), hi = p.map((e) => e.v).reduce((a, b) => a > b ? a : b);
    return hi - lo < 1e-9 ? 0.5 : (p[i].v - lo) / (hi - lo);
  }
}

class _EmptyHub extends StatelessWidget {
  const _EmptyHub();
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Glass(
          strong: true,
          radius: 32,
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(children: [
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.tint),
              child: const Icon(Icons.router_outlined, size: 64, color: AppColors.blue),
            ),
            const SizedBox(height: 16),
            Text('Belum ada perangkat', style: T.s(24, w: FontWeight.w600, ls: -0.4)),
            const SizedBox(height: 8),
            Text('Sambungkan hub Sysnergi untuk mulai memantau. Hanya butuh sekitar 5 menit.', textAlign: TextAlign.center, style: T.body),
            const SizedBox(height: 16),
            Row(children: [
              for (final (i, l) in const [(Icons.power_outlined, 'Colok hub'), (Icons.bluetooth_rounded, 'Sambung HP'), (Icons.wifi_rounded, 'Masuk Wi‑Fi')])
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [Icon(i, color: AppColors.blue, size: 20), const SizedBox(height: 6), Text(l, style: T.s(12, w: FontWeight.w500, c: AppColors.ink2))]),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            PrimaryButton('Tambah perangkat', icon: Icons.add_rounded, onPressed: () => context.push('/add-device')),
          ]),
        ),
      ]);
}

class _NoSite extends StatelessWidget {
  const _NoSite({this.name});
  final String? name;
  @override
  Widget build(BuildContext context) => AppPage(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const AiOrb(size: 88),
            const SizedBox(height: 20),
            Text('Selamat datang${name == null ? '' : ', ${name!.split(' ').first}'}', style: T.title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Pilih jenis usaha dulu supaya tampilan sesuai kebutuhan Anda.', style: T.body, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            PrimaryButton('Pilih usaha', onPressed: () => context.push('/onboarding')),
          ]),
        ),
      );
}

class _AskAi extends StatelessWidget {
  const _AskAi({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Glass(
        onTap: onTap,
        radius: 32,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Row(children: [
          const AiOrb(size: 46),
          const SizedBox(width: 12),
          Expanded(child: Text('Tanya Sysnergi…', style: T.s(16, w: FontWeight.w500, c: AppColors.ink2))),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient),
            child: const Icon(Icons.mic_none_rounded, color: Colors.white),
          ),
        ]),
      );
}
