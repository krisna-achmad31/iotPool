import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';

class OtpArgs {
  const OtpArgs({required this.phone, required this.verificationId});
  final String phone;
  final String verificationId;
}

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.args});
  final OtpArgs args;
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _code = '';
  String? _error;
  bool _busy = false;
  late String _verificationId = widget.args.verificationId;
  int _resendIn = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _resendIn = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn == 0) return t.cancel();
      setState(() => _resendIn--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _press(String k) {
    if (_busy) return;
    setState(() {
      _error = null;
      if (k == 'del') {
        if (_code.isNotEmpty) _code = _code.substring(0, _code.length - 1);
      } else if (_code.length < 6) {
        _code += k;
      }
    });
    if (_code.length == 6) _verify();
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).verifyOtp(_verificationId, _code);
      // Redirect router memindahkan ke /home setelah status auth berubah.
    } catch (e) {
      setState(() {
        _error = '$e';
        _code = '';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      _verificationId = await ref.read(repositoryProvider).sendOtp(widget.args.phone);
      _startTimer();
      if (mounted) showMessage(context, 'Kode baru sudah dikirim');
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    }
  }

  String get _prettyPhone {
    final p = widget.args.phone.replaceFirst('+62', '0');
    return p.replaceAllMapped(RegExp(r'(\d{4})(?=\d)'), (m) => '${m[1]}-');
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RoundIconButton(Icons.arrow_back_rounded, onPressed: () => context.pop()),
            const SizedBox(height: 24),
            Text('Masukkan kode', style: T.s(30, w: FontWeight.w600, ls: -0.6)),
            const SizedBox(height: 8),
            Text('Kami kirim 6 angka ke $_prettyPhone', style: T.s(16, c: AppColors.ink2, h: 1.45)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (var i = 0; i < 6; i++) _box(i),
            ]),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: T.s(14, w: FontWeight.w500, c: AppColors.redInk))
            else
              Row(children: [
                const Icon(Icons.timer_outlined, size: 18, color: AppColors.ink2),
                const SizedBox(width: 6),
                Expanded(
                  child: _resendIn > 0
                      ? Text('Kirim ulang dalam 0:${_resendIn.toString().padLeft(2, '0')}', style: T.s(15, c: AppColors.ink2))
                      : GestureDetector(onTap: _resend, child: Text('Kirim ulang kode', style: T.s(15, w: FontWeight.w600, c: AppColors.blue))),
                ),
                if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
          ]),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(children: [
            for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', 'del']])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  for (final k in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: k.isEmpty
                            ? const SizedBox(height: 60)
                            : Material(
                                color: k == 'del' ? Colors.transparent : const Color(0xCCFFFFFF),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _press(k),
                                  child: SizedBox(
                                    height: 60,
                                    child: Center(
                                      child: k == 'del'
                                          ? const Icon(Icons.backspace_outlined, size: 26, color: AppColors.ink, semanticLabel: 'Hapus')
                                          : Text(k, style: T.s(26, w: FontWeight.w500)),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _box(int i) {
    final active = i == _code.length && !_busy;
    final filled = i < _code.length;
    return Container(
      width: 50,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _error != null ? AppColors.red : active ? AppColors.blue : filled ? const Color(0xFFB9D3FA) : AppColors.line,
          width: active ? 2 : 1.5,
        ),
        boxShadow: active ? const [BoxShadow(color: Color(0x261C6FE8), blurRadius: 14, offset: Offset(0, 6))] : null,
      ),
      child: filled
          ? Text(_code[i], style: T.s(26, w: FontWeight.w600))
          : active
              ? Container(width: 2, height: 26, color: AppColors.blue)
              : null,
    );
  }
}
