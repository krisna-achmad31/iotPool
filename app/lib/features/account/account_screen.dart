import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider).value;
    final repo = ref.watch(repositoryProvider);
    final sites = ref.watch(sitesProvider).value ?? const <Site>[];
    final site = ref.watch(currentSiteProvider);
    if (p == null) return const AppPage(child: Center(child: CircularProgressIndicator()));
    final planName = switch (p.planTier) { 'pro' => 'Paket Pro', 'plus' => 'Paket Plus', _ => 'Paket Gratis' };

    Widget group(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(t, style: T.s(13, w: FontWeight.w600, c: AppColors.ink2, ls: 0.6)),
        );

    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Row(children: [
            Expanded(child: Text('Akun', style: T.title)),
            if (repo.isDemo)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0x1FF5A524), borderRadius: BorderRadius.circular(10)),
                child: Text('Mode demo', style: T.s(12, w: FontWeight.w600, c: AppColors.amberInk)),
              ),
          ]),
          const SizedBox(height: 18),
          Glass(
            child: Row(children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient, border: Border.all(color: Colors.white, width: 2)),
                child: Text(p.initials, style: T.s(22, w: FontWeight.w600, c: Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.displayName ?? 'Tanpa nama', style: T.s(19, w: FontWeight.w600)),
                  if (p.phone != null) Text(p.phone!.replaceFirst('+62', '0'), style: T.small),
                  if (site != null) Text('${site.name} · ${sites.length} lokasi', style: T.s(13, w: FontWeight.w500, c: AppColors.blue)),
                ]),
              ),
              IconButton.filledTonal(onPressed: () => _editName(context, ref, p.displayName), icon: const Icon(Icons.edit_outlined)),
            ]),
          ),
          const SizedBox(height: 14),
          BlueCard(
            radius: 30,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(planName, style: T.s(20, w: FontWeight.w600, c: Colors.white))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(12)),
                  child: Text('Aktif', style: T.s(12, w: FontWeight.w600, c: Colors.white)),
                ),
              ]),
              if (p.planValidUntil != null) ...[
                const SizedBox(height: 8),
                Text('Berlaku sampai ${DateFormat('d MMMM yyyy', 'id').format(p.planValidUntil!)}', style: T.s(14, c: const Color(0xFFDDEBFF))),
              ],
              const SizedBox(height: 16),
              _meter('Hub terpakai', p.ownedHubIds.length, p.hubLimit),
              if (p.aiMonthlyLimit > 0) ...[const SizedBox(height: 12), _meter('Permintaan AI bulan ini', p.aiCount, p.aiMonthlyLimit)],
              const SizedBox(height: 16),
              if (p.planTier != 'pro')
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, shape: const StadiumBorder()),
                    onPressed: () => context.push('/paywall'),
                    icon: const Icon(Icons.auto_awesome, color: AppColors.blue),
                    label: Text('Upgrade ke Pro', style: T.s(16, w: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
          group('USAHA'),
          Divided(children: [
            ListRow(
              leading: const IconChip(Icons.place_outlined, size: 36),
              title: 'Lokasi & usaha',
              trailing: Text('${sites.length} lokasi', style: T.small),
              onTap: () => context.push('/onboarding'),
            ),
            ListRow(
              leading: const IconChip(Icons.group_outlined, size: 36),
              title: 'Anggota & pekerja',
              trailing: Text('${site?.roles.length ?? 0} orang', style: T.small),
              onTap: () => context.push('/members'),
            ),
          ]),
          group('KENYAMANAN'),
          Divided(children: [
            ListRow(
              leading: const IconChip(Icons.notifications_active_outlined, size: 36),
              title: 'Suara alarm bahaya',
              trailing: BigSwitch(value: p.alarmSound, onChanged: (v) => repo.updatePrefs(alarmSound: v)),
            ),
            ListRow(
              leading: const IconChip(Icons.text_fields_rounded, size: 36),
              title: 'Tulisan lebih besar',
              trailing: BigSwitch(value: p.largeText, onChanged: (v) => repo.updatePrefs(largeText: v)),
            ),
            ListRow(
              leading: const IconChip(Icons.translate_rounded, size: 36),
              title: 'Bahasa',
              trailing: Text('Indonesia', style: T.small),
            ),
          ]),
          group('BANTUAN'),
          Divided(children: [
            ListRow(
              leading: const IconChip(Icons.chat_bubble_outline_rounded, size: 36),
              title: 'Chat CS via WhatsApp',
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
              onTap: () => showMessage(context, 'Nomor WhatsApp CS belum diisi'),
            ),
            ListRow(
              leading: const IconChip(Icons.menu_book_outlined, size: 36),
              title: 'Panduan & video',
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
              onTap: () => showMessage(context, 'Panduan menyusul'),
            ),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            height: 56,
            child: TextButton.icon(
              style: TextButton.styleFrom(backgroundColor: const Color(0x14EF4E5A), shape: const StadiumBorder()),
              onPressed: () => repo.signOut(),
              icon: const Icon(Icons.logout_rounded, color: AppColors.red),
              label: Text('Keluar', style: T.s(16, w: FontWeight.w600, c: AppColors.red)),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text('Sysnergi v1.0.0', style: T.s(12, c: AppColors.muted))),
        ],
      ),
    );
  }

  Widget _meter(String label, int used, int max) => Column(children: [
        Row(children: [
          Expanded(child: Text(label, style: T.s(14, c: const Color(0xFFE6E9FF)))),
          Text('$used / $max', style: T.s(14, w: FontWeight.w600, c: Colors.white)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: max == 0 ? 0 : (used / max).clamp(0, 1), minHeight: 8, backgroundColor: const Color(0x33FFFFFF), color: Colors.white),
        ),
      ]);

  Future<void> _editName(BuildContext context, WidgetRef ref, String? current) async {
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Nama Anda', style: T.h2),
        content: TextField(controller: c, autofocus: true, style: T.s(18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await ref.read(repositoryProvider).updatePrefs(displayName: name);
  }
}
