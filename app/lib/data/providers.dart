import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import 'provisioning.dart';
import 'repository.dart';

/// Di-override di main.dart dengan DemoRepository atau FirebaseRepository.
final repositoryProvider = Provider<SysnergiRepository>((ref) => throw UnimplementedError());
final provisionerProvider = Provider<HubProvisioner>((ref) => throw UnimplementedError());

final authUidProvider = StreamProvider<String?>((ref) => ref.watch(repositoryProvider).authUid());

final profileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(null);
  return ref.watch(repositoryProvider).profile(uid);
});

final sitesProvider = StreamProvider<List<Site>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).sites(uid);
});

class _SelectedId extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final selectedSiteIdProvider = NotifierProvider<_SelectedId, String?>(_SelectedId.new);
final selectedZoneIdProvider = NotifierProvider<_SelectedId, String?>(_SelectedId.new);

/// Site aktif: yang dipilih, atau site pertama.
final currentSiteProvider = Provider<Site?>((ref) {
  final sites = ref.watch(sitesProvider).value ?? const [];
  if (sites.isEmpty) return null;
  final id = ref.watch(selectedSiteIdProvider);
  return sites.where((s) => s.id == id).firstOrNull ?? sites.first;
});

final zonesProvider = StreamProvider.family<List<Zone>, String>((ref, siteId) => ref.watch(repositoryProvider).zones(siteId));
final hubProvider = StreamProvider.family<Hub?, String>((ref, hubId) => ref.watch(repositoryProvider).hub(hubId));
final liveProvider = StreamProvider.family<LiveState?, String>((ref, hubId) => ref.watch(repositoryProvider).live(hubId));
final automationsProvider =
    StreamProvider.family<List<Automation>, String>((ref, siteId) => ref.watch(repositoryProvider).automations(siteId));
final eventsProvider = StreamProvider.family<List<AppEvent>, String>((ref, siteId) => ref.watch(repositoryProvider).events(siteId));

typedef HistoryKey = ({String hubId, String port, int hours});
final historyProvider = FutureProvider.family<List<TelemetryPoint>, HistoryKey>(
    (ref, k) => ref.watch(repositoryProvider).history(k.hubId, k.port, Duration(hours: k.hours)));

/// Detak 5 detik untuk status online/offline & "x menit lalu".
final clockProvider = StreamProvider<DateTime>(
    (ref) => Stream.periodic(const Duration(seconds: 5), (_) => DateTime.now()));

DateTime nowOf(Ref ref) => ref.watch(clockProvider).value ?? DateTime.now();

/// Semua hub di site aktif (yang sudah termuat).
final siteHubsProvider = Provider.family<List<Hub>, String>((ref, siteId) {
  final site = (ref.watch(sitesProvider).value ?? const <Site>[]).where((s) => s.id == siteId).firstOrNull;
  if (site == null) return const [];
  return [for (final id in site.hubIds) ?ref.watch(hubProvider(id)).value];
});

/// Satu sensor yang terpasang: hub + port + assignment + nilai live.
class ChannelView {
  const ChannelView({required this.hub, required this.port, required this.assignment, this.value, required this.online});
  final Hub hub;
  final String port;
  final PortAssignment assignment;
  final double? value;
  final bool online;
  String get metric => assignment.metric;
}

class RelayView {
  const RelayView({required this.hub, required this.relay, required this.assignment, this.state, required this.online});
  final Hub hub;
  final String relay;
  final RelayAssignment assignment;
  final RelayState? state;
  final bool online;
  bool get on => state?.on ?? false;
}

typedef ZoneKey = ({String siteId, String zoneId});

final zoneChannelsProvider = Provider.family<List<ChannelView>, ZoneKey>((ref, k) {
  final now = nowOf(ref);
  final out = <ChannelView>[];
  for (final hub in ref.watch(siteHubsProvider(k.siteId))) {
    final live = ref.watch(liveProvider(hub.id)).value;
    final online = live?.isOnline(now) ?? false;
    hub.ports.forEach((port, a) {
      if (a.zoneId == k.zoneId) {
        out.add(ChannelView(hub: hub, port: port, assignment: a, value: live?.ch[port]?.v, online: online));
      }
    });
  }
  return out;
});

final zoneRelaysProvider = Provider.family<List<RelayView>, ZoneKey>((ref, k) {
  final now = nowOf(ref);
  final out = <RelayView>[];
  for (final hub in ref.watch(siteHubsProvider(k.siteId))) {
    final live = ref.watch(liveProvider(hub.id)).value;
    final online = live?.isOnline(now) ?? false;
    hub.relays.forEach((relay, a) {
      if (a.zoneId == k.zoneId) {
        out.add(RelayView(hub: hub, relay: relay, assignment: a, state: live?.relays[relay], online: online));
      }
    });
  }
  return out;
});
