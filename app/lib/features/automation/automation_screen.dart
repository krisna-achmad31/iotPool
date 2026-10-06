import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/catalog.dart';
import '../../domain/logic.dart';
import '../../domain/models.dart';

/// Resep siap pakai. `metric` = sensor pemicu, `actuator` = alat yang dijalankan (null = notifikasi).
class Recipe {
  const Recipe(this.name, this.icon, this.metric, this.op, this.value, {this.actuator, this.until, this.maxRunSec, this.level});
  final String name;
  final IconData icon;
  final String metric;
  final String op;
  final double value;
  final String? actuator;
  final double? until;
  final int? maxRunSec;
  final int? level;
}

const kRecipes = <String, List<Recipe>>{
  'aquaculture': [
    Recipe('Aerator saat oksigen rendah', Icons.cyclone_rounded, 'do', 'lt', 4, actuator: 'aerator', maxRunSec: 2700),
    Recipe('Isi kolam otomatis', Icons.water_rounded, 'water_level', 'lt', 70, actuator: 'pump_fill', until: 80, maxRunSec: 2700),
    Recipe('Waspada suhu air panas', Icons.thermostat_rounded, 'water_temp', 'gt', 31),
  ],
  'horticulture': [
    Recipe('Siram saat tanah kering', Icons.shower_outlined, 'soil_moisture', 'lt', 35, actuator: 'pump_irrigation', until: 50, maxRunSec: 1200),
    Recipe('Peringatan tandon rendah', Icons.propane_tank_outlined, 'tank_level', 'lt', 30),
  ],
  'livestock': [
    Recipe('Kipas ikut suhu', Icons.mode_fan_off_outlined, 'air_temp', 'gt', 30, actuator: 'exhaust_fan', level: 3),
    Recipe('Pemanas saat dingin', Icons.local_fire_department_outlined, 'air_temp', 'lt', 26, actuator: 'heater', until: 28, maxRunSec: 3600),
  ],
};

/// Bangun aturan dari resep untuk hub pertama yang punya sensor & alatnya. Null bila tidak ada.
Automation? buildFromRecipe(Recipe r, List<Hub> hubs) {
  for (final h in hubs) {
    final port = h.ports.entries.where((e) => e.value.metric == r.metric).firstOrNull?.key;
    if (port == null) continue;
    String? relay;
    if (r.actuator != null) {
      relay = h.relays.entries.where((e) => e.value.kind == r.actuator).firstOrNull?.key;
      if (relay == null) continue;
    }
    return Automation(
      id: 'tpl_${DateTime.now().millisecondsSinceEpoch}',
      name: r.name,
      enabled: true,
      hubId: h.id,
      trigger: ThresholdTrigger(ThresholdCond(ch: port, op: r.op, value: r.value), holdSec: 120),
      action: relay == null
          ? const NotifyAction(Severity.warning)
          : RelayAction(
              relay: relay,
              on: true,
              level: r.level,
              untilThreshold: r.until == null ? null : ThresholdCond(ch: port, op: r.op == 'lt' ? 'gt' : 'lt', value: r.until!),
            ),
      maxRunSec: r.maxRunSec,
      cooldownSec: relay == null ? null : 600,
      source: 'template',
    );
  }
  return null;
}

class AutomationScreen extends ConsumerWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(currentSiteProvider);
    if (site == null) return const AppPage(child: SizedBox());
    final uid = ref.watch(authUidProvider).value ?? '';
    final canEdit = site.canOperate(uid);
    final rules = ref.watch(automationsProvider(site.id)).value ?? const <Automation>[];
    final hubs = ref.watch(siteHubsProvider(site.id));
    final hubById = {for (final h in hubs) h.id: h};
    final recipes = (kRecipes[site.kind] ?? const <Recipe>[]).where((r) => !rules.any((x) => x.name == r.name)).toList();
    final subject = switch (site.kind) { 'horticulture' => 'kebun', 'livestock' => 'kandang', _ => 'kolam' };

    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Row(children: [
            Expanded(child: Text('Otomasi', style: T.title)),
            Glass(
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.green),
                const SizedBox(width: 6),
                Text('Jalan offline', style: T.s(13, w: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Glass(
            strong: true,
            radius: 32,
            padding: const EdgeInsets.all(20),
            onTap: () => context.push('/assistant'),
            child: Column(children: [
              const AiOrb(size: 84),
              const SizedBox(height: 14),
              Text('Asisten Sysnergi', style: T.s(14, w: FontWeight.w600, c: AppColors.blue)),
              const SizedBox(height: 4),
              Text('Mau $subject diatur seperti apa?', textAlign: TextAlign.center, style: T.s(22, w: FontWeight.w600, ls: -0.3)),
              const SizedBox(height: 14),
              Container(
                height: 56,
                padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: AppColors.line)),
                child: Row(children: [
                  Expanded(child: Text('Contoh: “isi kolam kalau air kurang dari 70 cm”', style: T.s(14, c: AppColors.ink2), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient),
                    child: const Icon(Icons.mic_none_rounded, color: Colors.white),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          SectionHeader('Sedang aktif', trailing: '${rules.where((r) => r.enabled).length} aturan'),
          const SizedBox(height: 12),
          if (rules.isEmpty)
            Glass(child: Text('Belum ada otomasi. Pakai resep di bawah atau minta asisten membuatkan.', style: T.body))
          else
            Divided(children: [
              for (final r in rules)
                ListRow(
                  leading: IconChip(r.action is NotifyAction ? Icons.notifications_active_outlined : Icons.auto_awesome_outlined),
                  title: r.name,
                  subtitle: '${describeTrigger(r.trigger, hubById[r.hubId])} → ${describeAction(r.action, hubById[r.hubId]).toLowerCase()}',
                  trailing: BigSwitch(
                    value: r.enabled,
                    onChanged: canEdit ? (v) => ref.read(repositoryProvider).setAutomationEnabled(site.id, r, v) : null,
                  ),
                ),
            ]),
          if (recipes.isNotEmpty && canEdit) ...[
            const SizedBox(height: 22),
            const SectionHeader('Resep siap pakai'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (_, c) => Wrap(spacing: 12, runSpacing: 12, children: [
                for (final r in recipes)
                  SizedBox(
                    width: (c.maxWidth - 12) / 2,
                    child: Glass(
                      onTap: () => _apply(context, ref, site, r, hubs),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        IconChip(r.icon),
                        const SizedBox(height: 18),
                        Text(r.name, style: T.s(16, w: FontWeight.w600, h: 1.3)),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.add_rounded, size: 18, color: AppColors.blue),
                          Text('Pakai', style: T.s(15, w: FontWeight.w600, c: AppColors.blue)),
                        ]),
                      ]),
                    ),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref, Site site, Recipe r, List<Hub> hubs) async {
    final rule = buildFromRecipe(r, hubs);
    if (rule == null) {
      showMessage(context,
          'Resep ini butuh sensor ${metricDef(r.metric).label.toLowerCase()}${r.actuator == null ? '' : ' dan ${actuatorDef(r.actuator!).label.toLowerCase()}'} di hub yang sama.');
      return;
    }
    await ref.read(repositoryProvider).saveAutomation(site.id, rule);
    if (context.mounted) showMessage(context, '“${r.name}” aktif. Hub menjalankannya walau internet putus.');
  }
}
