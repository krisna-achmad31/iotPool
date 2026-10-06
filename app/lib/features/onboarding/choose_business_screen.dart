import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';

class ChooseBusinessScreen extends ConsumerStatefulWidget {
  const ChooseBusinessScreen({super.key});
  @override
  ConsumerState<ChooseBusinessScreen> createState() => _ChooseBusinessScreenState();
}

class _ChooseBusinessScreenState extends ConsumerState<ChooseBusinessScreen> {
  final _selected = <String>{'aquaculture'};
  bool _busy = false;

  static const _options = [
    ('aquaculture', Icons.set_meal_rounded, 'Kolam ikan', 'Oksigen, pH, suhu, amonia, tinggi air', 'Kolam saya'),
    ('horticulture', Icons.eco_rounded, 'Kebun & sawah', 'Kelembapan tanah, cahaya, siram otomatis', 'Kebun saya'),
    ('livestock', Icons.egg_alt_rounded, 'Kandang ternak', 'Suhu, amonia udara, kipas & pemanas', 'Kandang saya'),
  ];

  Future<void> _continue() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      String? first;
      for (final o in _options.where((o) => _selected.contains(o.$1))) {
        final id = await repo.createSite(name: o.$5, kind: o.$1);
        first ??= id;
      }
      ref.read(selectedSiteIdProvider.notifier).select(first);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final largeText = ref.watch(profileProvider).value?.largeText ?? false;
    return AppPage(
      child: ListView(children: [
        const SizedBox(height: 8),
        Row(children: [
          Container(width: 28, height: 8, decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(4))),
          for (var i = 0; i < 2; i++)
            Container(margin: const EdgeInsets.only(left: 6), width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFFC9D3E3), borderRadius: BorderRadius.circular(4))),
        ]),
        const SizedBox(height: 22),
        Text('Usaha apa yang ingin dipantau?', style: T.s(30, w: FontWeight.w600, ls: -0.6, h: 1.15)),
        const SizedBox(height: 8),
        Text('Boleh pilih lebih dari satu. Bisa diubah nanti.', style: T.s(16, c: AppColors.ink2)),
        const SizedBox(height: 22),
        for (final o in _options) ...[
          _OptionCard(
            icon: o.$2,
            title: o.$3,
            desc: o.$4,
            selected: _selected.contains(o.$1),
            onTap: () => setState(() => _selected.contains(o.$1) ? _selected.remove(o.$1) : _selected.add(o.$1)),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        Glass(
          child: Row(children: [
            Container(
              width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(15)),
              child: Text('Aa', style: T.s(18, w: FontWeight.w600, c: AppColors.blue)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tulisan lebih besar', style: T.s(16, w: FontWeight.w600)),
                Text('Lebih nyaman dibaca', style: T.small),
              ]),
            ),
            BigSwitch(value: largeText, onChanged: (v) => ref.read(repositoryProvider).updatePrefs(largeText: v)),
          ]),
        ),
        const SizedBox(height: 22),
        PrimaryButton('Lanjut · ${_selected.length} dipilih', onPressed: _selected.isEmpty ? null : _continue, loading: _busy),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: () => context.go('/home'),
            child: Text('Lihat contoh dulu tanpa alat', style: T.s(15, w: FontWeight.w600, c: AppColors.blue)),
          ),
        ),
      ]),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.icon, required this.title, required this.desc, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        checked: selected,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: selected ? Colors.white : AppColors.glassStrong,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: selected ? AppColors.blue : AppColors.glassStroke, width: selected ? 2 : 1.5),
            boxShadow: selected ? const [BoxShadow(color: Color(0x261C6FE8), blurRadius: 24, offset: Offset(0, 10))] : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                IconChip(icon, size: 64, filled: selected),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: T.s(19, w: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(desc, style: T.s(14, c: AppColors.ink2, h: 1.35)),
                  ]),
                ),
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: selected ? AppColors.blueGradient : null,
                    border: selected ? null : Border.all(color: const Color(0xFFB8C3D6), width: 2),
                  ),
                  child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                ),
              ]),
            ),
          ),
        ),
      );
}
