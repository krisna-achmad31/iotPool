import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import 'otp_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  bool _loading = false;

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0'), '');
  bool get _valid => _digits.length >= 9 && _digits.length <= 13;

  Future<void> _send() async {
    setState(() => _loading = true);
    final phone = '+62$_digits';
    try {
      final id = await ref.read(repositoryProvider).sendOtp(phone);
      if (mounted) context.push('/otp', extra: OtpArgs(phone: phone, verificationId: id));
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    try {
      await ref.read(repositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(repositoryProvider).isDemo;
    return AppPage(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 24),
                const Center(child: AiOrb(size: 104)),
                const SizedBox(height: 18),
                Center(child: Text('Sysnergi', style: T.s(34, w: FontWeight.w600, ls: -0.8))),
                const SizedBox(height: 8),
                Text('Pantau kolam, kebun, dan kandang dari HP. Mudah dan aman.', textAlign: TextAlign.center, style: T.s(16, c: AppColors.ink2, h: 1.45)),
                const SizedBox(height: 32),
                Text('Nomor HP', style: T.s(16, w: FontWeight.w600)),
                const SizedBox(height: 12),
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.blue, width: 2),
                    boxShadow: const [BoxShadow(color: Color(0x1F1C6FE8), blurRadius: 20, offset: Offset(0, 8))],
                  ),
                  child: Row(children: [
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(16)),
                      alignment: Alignment.center,
                      child: Text('+62', style: T.s(17, w: FontWeight.w600, c: AppColors.blue)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13)],
                        style: T.s(20, w: FontWeight.w500, ls: 0.5),
                        decoration: InputDecoration(border: InputBorder.none, hintText: '812 3456 7890', hintStyle: T.s(20, c: const Color(0xFFB8C3D6))),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _valid ? _send() : null,
                      ),
                    ),
                    if (_phone.text.isNotEmpty)
                      IconButton(
                        onPressed: () => setState(_phone.clear),
                        icon: const Icon(Icons.cancel_outlined, color: Color(0xFFB8C3D6)),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: AppColors.green),
                  const SizedBox(width: 6),
                  Expanded(child: Text(demo ? 'Mode demo: kode apa saja 6 angka bisa dipakai' : 'Kode masuk dikirim lewat SMS', style: T.small)),
                ]),
                const Spacer(),
                const SizedBox(height: 24),
                PrimaryButton('Kirim kode', onPressed: _valid ? _send : null, loading: _loading),
                const SizedBox(height: 14),
                Row(children: [
                  const Expanded(child: Divider(color: Color(0xFFD3DBE8))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('atau', style: T.small)),
                  const Expanded(child: Divider(color: Color(0xFFD3DBE8))),
                ]),
                const SizedBox(height: 14),
                SecondaryButton('Masuk dengan Google', icon: Icons.g_mobiledata_rounded, onPressed: _google, color: AppColors.ink, height: 60),
                const SizedBox(height: 14),
                Text('Dengan masuk, Anda setuju dengan Syarat & Kebijakan Privasi.', textAlign: TextAlign.center, style: T.small),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
