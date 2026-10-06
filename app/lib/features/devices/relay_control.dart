import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/catalog.dart';

/// Nyalakan/matikan relay lewat RTDB `down/cmd`. Mematikan alat yang sedang dijalankan otomasi
/// minta konfirmasi dulu (aksi berisiko bagi ikan/ternak).
Future<void> toggleRelay(BuildContext context, WidgetRef ref, RelayView r, bool on) async {
  if (!r.online) {
    showMessage(context, '${r.hub.displayName} sedang terputus. Alat tidak bisa dikontrol dulu.');
    return;
  }
  if (!on && r.state?.ruleId != null) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Matikan ${r.assignment.label}?', style: T.h2),
        content: Text('Alat ini sedang dinyalakan otomasi. Kalau dimatikan, otomasi berhenti sampai Anda mengembalikannya ke mode otomatis.', style: T.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Batal', style: T.s(16, w: FontWeight.w600, c: AppColors.ink2))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Ya, matikan', style: T.s(16, w: FontWeight.w600, c: Colors.white))),
        ],
      ),
    );
    if (ok != true) return;
  }
  if (!context.mounted) return;
  showMessage(context, '${on ? 'Menyalakan' : 'Mematikan'} ${r.assignment.label}…');
  final res = await ref.read(repositoryProvider).sendCommand(r.hub.id, 'relay', {'relay': r.relay, 'on': on});
  if (!context.mounted) return;
  showMessage(
    context,
    res.ok
        ? '${r.assignment.label} ${on ? 'menyala' : 'mati'}'
        : res.code == 'offline' || res.code == 'timeout'
            ? 'Hub tidak menjawab. Periksa listrik & Wi‑Fi hub.'
            : 'Gagal (${res.code}).',
  );
}

class RelayTile extends ConsumerWidget {
  const RelayTile(this.r, {super.key, this.showLocation});
  final RelayView r;
  final String? showLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final def = actuatorDef(r.assignment.kind);
    final on = r.on;
    final since = r.state?.since;
    final now = DateTime.now();
    final state = !r.online
        ? 'Tidak terhubung'
        : on
            ? 'Nyala${r.state?.level != null ? ' · level ${r.state!.level}' : since != null ? ' · ${now.difference(since).inMinutes} menit' : ''}'
            : 'Mati';
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: on ? const Color(0x33FFFFFF) : AppColors.tint, borderRadius: BorderRadius.circular(15)),
          child: Icon(def.icon, color: on ? Colors.white : AppColors.blue),
        ),
        const Spacer(),
        BigSwitch(value: on, onDark: on, onChanged: r.online ? (v) => toggleRelay(context, ref, r, v) : null),
      ]),
      const SizedBox(height: 16),
      Text(r.assignment.label, style: T.s(18, w: FontWeight.w600, c: on ? Colors.white : AppColors.ink)),
      Text(showLocation ?? state, style: T.s(14, w: FontWeight.w500, c: on ? const Color(0xFFDDEBFF) : AppColors.ink2)),
    ]);
    final tile = on
        ? BlueCard(padding: const EdgeInsets.all(16), radius: 26, child: content)
        : Glass(child: content);
    return Opacity(opacity: r.online ? 1 : 0.5, child: tile);
  }
}
