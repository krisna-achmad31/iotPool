import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';

/// Harga di sini masih hipotesis PRD — belum divalidasi di pilot.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});
  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _yearly = true;
  String _plan = 'pro';

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(profileProvider).value?.planTier ?? 'free';
    final plans = [
      ('free', 'Gratis', 'Rp 0', '1 hub · data 24 jam'),
      ('plus', 'Plus', _yearly ? 'Rp 390 rb' : 'Rp 39 rb', '${_yearly ? '/tahun' : '/bulan'} · 3 hub · data 90 hari · AI 30×/bln'),
      ('pro', 'Pro', _yearly ? 'Rp 1,19 jt' : 'Rp 119 rb', '${_yearly ? '/tahun' : '/bulan'} · hub tanpa batas · semua fitur'),
    ];
    return AppPage(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(children: [
            RoundIconButton(Icons.close_rounded, onPressed: () => context.pop()),
            const Spacer(),
            TextButton(onPressed: () => showMessage(context, 'Tidak ada pembelian untuk dipulihkan'), child: Text('Pulihkan pembelian', style: T.s(14, w: FontWeight.w500, c: AppColors.blue))),
          ]),
          const SizedBox(height: 12),
          const Center(child: AiOrb(size: 84)),
          const SizedBox(height: 12),
          Text('Usaha lebih aman, panen lebih tenang', textAlign: TextAlign.center, style: T.s(26, w: FontWeight.w600, ls: -0.5, h: 1.2)),
          const SizedBox(height: 20),
          Glass(
            strong: true,
            radius: 24,
            child: Column(children: [
              for (final (i, t) in const [
                (Icons.auto_awesome, 'Asisten AI tanpa batas + analisis mingguan'),
                (Icons.history_rounded, 'Riwayat data 2 tahun & unduh laporan'),
                (Icons.memory_rounded, 'Hub tanpa batas untuk semua kolam'),
                (Icons.group_outlined, 'Ajak keluarga & pekerja dengan peran'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [IconChip(i, size: 36), const SizedBox(width: 12), Expanded(child: Text(t, style: T.s(15, w: FontWeight.w500)))]),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white)),
            child: Row(children: [
              for (final (y, l) in const [(false, 'Bulanan'), (true, 'Tahunan')])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _yearly = y),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _yearly == y ? Colors.white : null, borderRadius: BorderRadius.circular(18)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(l, style: T.s(15, w: _yearly == y ? FontWeight.w600 : FontWeight.w500, c: _yearly == y ? AppColors.ink : AppColors.ink2)),
                        if (y) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0x1F22B573), borderRadius: BorderRadius.circular(8)),
                            child: Text('Hemat 2 bln', style: T.s(11, w: FontWeight.w600, c: AppColors.greenInk)),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          for (final (id, name, price, desc) in plans) ...[
            GestureDetector(
              onTap: id == 'free' ? null : () => setState(() => _plan = id),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _plan == id ? Colors.white : AppColors.glassStrong,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _plan == id ? AppColors.blue : AppColors.glassStroke, width: _plan == id ? 2 : 1.5),
                ),
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _plan == id ? AppColors.blue : const Color(0xFFB8C3D6), width: 2)),
                    child: _plan == id
                        ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.blue)))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(name, style: T.s(18, w: FontWeight.w600)),
                        if (id == current || id == 'pro') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: id == 'pro' ? AppColors.blueGradient : null,
                              color: id == 'pro' ? null : const Color(0xFFEEF3FA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(id == current ? 'Paket Anda' : 'Paling lengkap',
                                style: T.s(11, w: FontWeight.w600, c: id == 'pro' && id != current ? Colors.white : AppColors.ink2)),
                          ),
                        ],
                      ]),
                      Text(desc, style: T.s(13, c: AppColors.ink2, h: 1.35)),
                    ]),
                  ),
                  Text(price, style: T.s(18, w: FontWeight.w600, c: _plan == id ? AppColors.blue : AppColors.ink)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0x1422B573), borderRadius: BorderRadius.circular(18)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.greenInk),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Notifikasi bahaya, kontrol manual, dan otomasi yang sudah aktif tetap jalan walau tidak berlangganan.',
                    style: T.s(14, w: FontWeight.w500, c: const Color(0xFF14532D), h: 1.4)),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          PrimaryButton('Coba ${_plan == 'pro' ? 'Pro' : 'Plus'} gratis 14 hari',
              onPressed: _plan == current ? null : () => showMessage(context, 'Pembayaran Google Play belum disambungkan di versi ini.')),
          const SizedBox(height: 10),
          Text('Lalu ${plans.firstWhere((p) => p.$1 == _plan).$3}${_yearly ? '/tahun' : '/bulan'} via Google Play. Batalkan kapan saja.',
              textAlign: TextAlign.center, style: T.small),
        ],
      ),
    );
  }
}
