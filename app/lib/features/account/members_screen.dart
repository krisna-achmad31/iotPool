import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

final _memberNamesProvider = FutureProvider.family<Map<String, String>, Site>((ref, site) => ref.watch(repositoryProvider).memberNames(site));

String roleLabel(Role r) => switch (r) { Role.owner => 'Pemilik', Role.operator => 'Operator', Role.viewer => 'Penonton' };

class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key});
  final Role role;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: role == Role.owner ? AppColors.blueGradient : null,
          color: role == Role.owner ? null : role == Role.operator ? AppColors.tint : const Color(0xFFEEF3FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(roleLabel(role), style: T.s(12, w: FontWeight.w600, c: role == Role.owner ? Colors.white : role == Role.operator ? AppColors.blue : AppColors.ink2)),
      );
}

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});
  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  final _pending = <(String phone, Role role)>[];

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(currentSiteProvider);
    final me = ref.watch(authUidProvider).value;
    if (site == null) return const AppPage(child: SizedBox());
    final names = ref.watch(_memberNamesProvider(site)).value ?? const <String, String>{};
    final isOwner = site.roleOf(me ?? '') == Role.owner;
    final members = site.roles.entries.toList()..sort((a, b) => a.value.index.compareTo(b.value.index));

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
                Text('Anggota & pekerja', style: T.h2),
                Text('${site.name} · ${members.length} orang', style: T.small),
              ]),
            ),
            if (isOwner) RoundIconButton(Icons.person_add_alt_1_rounded, filled: true, onPressed: () => _invite(context, site)),
          ]),
          const SizedBox(height: 18),
          if (isOwner)
            BlueCard(
              radius: 26,
              padding: const EdgeInsets.all(16),
              onTap: () => _invite(context, site),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.groups_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Ajak keluarga atau pekerja', style: T.s(16, w: FontWeight.w600, c: Colors.white)),
                    Text('Undangan dikirim lewat WhatsApp', style: T.s(13, c: const Color(0xFFDDEBFF))),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Text('Undang', style: T.s(14, w: FontWeight.w600, c: AppColors.blue)),
                ),
              ]),
            ),
          const SizedBox(height: 18),
          Text('ANGGOTA', style: T.s(13, w: FontWeight.w600, c: AppColors.ink2, ls: 0.6)),
          const SizedBox(height: 10),
          Divided(strong: true, children: [
            for (final m in members)
              ListRow(
                leading: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: m.key == me ? AppColors.blueGradient : null,
                    color: m.key == me ? null : AppColors.tint,
                  ),
                  child: Text(_initials(names[m.key] ?? '?'), style: T.s(15, w: FontWeight.w600, c: m.key == me ? Colors.white : AppColors.blue)),
                ),
                title: '${names[m.key] ?? m.key}${m.key == me ? ' (Anda)' : ''}',
                subtitle: switch (m.value) {
                  Role.owner => 'Semua akses',
                  Role.operator => 'Pantau & kontrol alat',
                  Role.viewer => 'Hanya melihat',
                },
                trailing: RoleBadge(m.value),
                onTap: isOwner && m.key != me ? () => _changeRole(context, site, m.key, names[m.key] ?? '') : null,
              ),
          ]),
          if (_pending.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('MENUNGGU DITERIMA', style: T.s(13, w: FontWeight.w600, c: AppColors.ink2, ls: 0.6)),
            const SizedBox(height: 10),
            for (final (phone, role) in _pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  child: Row(children: [
                    const IconChip(Icons.schedule_rounded, color: AppColors.ink2, bg: Color(0xFFEEF3FA)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(phone, style: T.s(15, w: FontWeight.w600)),
                        Text('${roleLabel(role)} · baru dikirim', style: T.small),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: 18),
          Text('ARTI PERAN', style: T.s(13, w: FontWeight.w600, c: AppColors.ink2, ls: 0.6)),
          const SizedBox(height: 10),
          Glass(
            child: Column(children: [
              for (final (r, d) in const [
                (Role.owner, 'Semua akses, termasuk langganan dan hapus perangkat'),
                (Role.operator, 'Lihat data, nyalakan alat, ubah otomasi'),
                (Role.viewer, 'Hanya melihat data dan menerima notifikasi'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 92, child: Align(alignment: Alignment.centerLeft, child: RoleBadge(r))),
                    Expanded(child: Text(d, style: T.s(14, c: AppColors.ink2, h: 1.4))),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  String _initials(String n) => n.trim().split(RegExp(r'\s+')).take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();

  Future<void> _changeRole(BuildContext context, Site site, String uid, String name) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Peran $name', style: T.h2),
            const SizedBox(height: 8),
            for (final r in [Role.operator, Role.viewer])
              ListRow(title: roleLabel(r), trailing: site.roles[uid] == r ? const Icon(Icons.check_rounded, color: AppColors.blue) : null, onTap: () => Navigator.pop(c, r)),
            ListRow(title: 'Keluarkan dari ${site.name}', titleColor: AppColors.red, onTap: () => Navigator.pop(c, 'remove')),
          ]),
        ),
      ),
    );
    if (choice == null) return;
    await ref.read(repositoryProvider).setMemberRole(site.id, uid, choice is Role ? choice : null);
  }

  Future<void> _invite(BuildContext context, Site site) async {
    final result = await showModalBottomSheet<(String, Role)>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _InviteSheet(site: site),
    );
    if (result == null) return;
    setState(() => _pending.add(result));
    if (context.mounted) {
      showMessage(context, ref.read(repositoryProvider).isDemo
          ? 'Undangan terkirim (demo)'
          : 'Undangan disalin. Penerimaan undangan otomatis butuh Cloud Function (lihat README).');
    }
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.site});
  final Site site;
  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _phone = TextEditingController();
  Role _role = Role.operator;
  final _zones = <String>{};

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(zonesProvider(widget.site.id)).value ?? const <Zone>[];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Undang anggota', style: T.s(24, w: FontWeight.w600)),
        const SizedBox(height: 14),
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.blue, width: 2)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(14)),
              child: Text('+62', style: T.s(16, w: FontWeight.w600, c: AppColors.blue)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: T.s(18, w: FontWeight.w500),
                decoration: InputDecoration(border: InputBorder.none, hintText: '812 9090 1212', hintStyle: T.s(18, c: AppColors.muted)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Perannya apa?', style: T.s(16, w: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          for (final (r, icon, desc) in const [(Role.operator, Icons.tune_rounded, 'Pantau & kontrol'), (Role.viewer, Icons.visibility_outlined, 'Hanya lihat')]) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _role = r),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _role == r ? Colors.white : const Color(0xB3FFFFFF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _role == r ? AppColors.blue : AppColors.line, width: _role == r ? 2 : 1),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    IconChip(icon, filled: _role == r),
                    const SizedBox(height: 10),
                    Text(roleLabel(r), style: T.s(16, w: FontWeight.w600)),
                    Text(desc, style: T.small),
                  ]),
                ),
              ),
            ),
            if (r == Role.operator) const SizedBox(width: 8),
          ],
        ]),
        if (zones.length > 1) ...[
          const SizedBox(height: 16),
          Text('Boleh akses mana?', style: T.s(16, w: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final z in zones)
              SelectChip(z.name, icon: _zones.contains(z.id) ? Icons.check_rounded : Icons.add_rounded, selected: _zones.contains(z.id),
                  onTap: () => setState(() => _zones.contains(z.id) ? _zones.remove(z.id) : _zones.add(z.id))),
          ]),
        ],
        const SizedBox(height: 20),
        PrimaryButton('Kirim undangan via WhatsApp', icon: Icons.send_rounded,
            onPressed: _phone.text.length < 9 && _phone.text.isNotEmpty ? null : () => Navigator.pop(context, ('0${_phone.text}', _role))),
      ]),
    );
  }
}
