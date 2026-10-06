import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../data/provisioning.dart';
import '../../domain/catalog.dart';
import '../../domain/models.dart';

enum _Stage { type, method, scan, wifi, btFailed, done }

/// Tambah perangkat (desain 10a–10d, 13a, 13b):
/// pilih jenis → pilih cara → pindai Bluetooth → Wi‑Fi + klaim → selesai.
class AddDeviceFlow extends ConsumerStatefulWidget {
  const AddDeviceFlow({super.key});
  @override
  ConsumerState<AddDeviceFlow> createState() => _AddDeviceFlowState();
}

class _AddDeviceFlowState extends ConsumerState<AddDeviceFlow> {
  _Stage _stage = _Stage.type;
  int _type = 0;
  int _method = 0;
  StreamSubscription<List<DiscoveredHub>>? _scanSub;
  List<DiscoveredHub> _found = const [];
  DiscoveredHub? _picked;
  String? _nonce;
  ProvisioningException? _error;
  bool _busy = false;

  List<String> _ssids = const [];
  String? _ssid;
  final _password = TextEditingController();
  bool _obscure = true;
  String? _wifiError;
  String? _siteId;

  HubProvisioner get _prov => ref.read(provisionerProvider);

  @override
  void dispose() {
    _scanSub?.cancel();
    _prov.disconnect();
    _password.dispose();
    super.dispose();
  }

  void _startScan() {
    _scanSub?.cancel();
    setState(() {
      _stage = _Stage.scan;
      _found = const [];
      _picked = null;
    });
    _scanSub = _prov.scan().listen(
      (list) => setState(() {
        _found = list;
        _picked ??= list.where((h) => !h.claimed).firstOrNull;
      }),
      onError: (Object e) => setState(() {
        _error = e is ProvisioningException ? e : ProvisioningException(ProvisioningError.timeout, '$e');
        _stage = _Stage.btFailed;
      }),
    );
  }

  Future<void> _pair() async {
    final hub = _picked;
    if (hub == null) return;
    setState(() => _busy = true);
    try {
      await _scanSub?.cancel();
      _nonce = await _prov.pair(hub);
      _ssids = await _prov.scanWifi();
      _ssid = _ssids.firstOrNull;
      _siteId = ref.read(currentSiteProvider)?.id;
      setState(() => _stage = _Stage.wifi);
    } on ProvisioningException catch (e) {
      setState(() {
        _error = e;
        _stage = _Stage.btFailed;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectWifi() async {
    if (_ssid == null || _siteId == null) return;
    setState(() {
      _busy = true;
      _wifiError = null;
    });
    try {
      await _prov.sendWifi(_ssid!, _password.text);
      await ref.read(repositoryProvider).claimHub(hubId: _picked!.id, nonce: _nonce!, siteId: _siteId!, name: 'Hub ${_picked!.id.substring(4)}');
      setState(() => _stage = _Stage.done);
    } on ProvisioningException catch (e) {
      setState(() => _wifiError = e.error == ProvisioningError.wifiNotFound
          ? 'Hub tidak menemukan Wi‑Fi ini. Dekatkan router atau pilih Wi‑Fi lain.'
          : 'Kata sandi Wi‑Fi salah. Cek huruf besar/kecil, lalu coba lagi.');
    } catch (e) {
      setState(() => _wifiError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    switch (_stage) {
      case _Stage.type || _Stage.done:
        context.pop();
      case _Stage.method:
        setState(() => _stage = _Stage.type);
      case _Stage.scan || _Stage.btFailed:
        _scanSub?.cancel();
        setState(() => _stage = _Stage.method);
      case _Stage.wifi:
        _startScan();
    }
  }

  int get _stepNo => switch (_stage) { _Stage.type => 1, _Stage.method => 2, _Stage.scan || _Stage.btFailed => 3, _ => 4 };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _Stage.type || _stage == _Stage.done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AppPage(
        padding: EdgeInsets.zero,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (_stage != _Stage.done) ...[
              Row(children: [
                RoundIconButton(_stage == _Stage.type ? Icons.close_rounded : Icons.arrow_back_rounded, onPressed: _back),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tambah perangkat', style: T.h2),
                    Text('Langkah $_stepNo dari 4', style: T.small),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: i < _stepNo ? AppColors.blueGradient : null,
                        color: i < _stepNo ? null : const Color(0xB3FFFFFF),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 22),
            ],
            ...switch (_stage) {
              _Stage.type => _typeStage(),
              _Stage.method => _methodStage(),
              _Stage.scan => _scanStage(),
              _Stage.wifi => _wifiStage(),
              _Stage.btFailed => _btFailedStage(),
              _Stage.done => _doneStage(),
            },
          ],
        ),
      ),
    );
  }

  // ───────────── 10a: jenis ─────────────
  List<Widget> _typeStage() => [
        Text('Mau menambah apa?', style: T.s(24, w: FontWeight.w600, ls: -0.3)),
        const SizedBox(height: 4),
        Text('Pilih jenis perangkat yang ingin dipasang.', style: T.body),
        const SizedBox(height: 16),
        for (final (i, (icon, title, sub)) in const [
          (Icons.memory_rounded, 'Hub Sysnergi', 'Otak utama. Satu hub untuk sensor & alat di satu lokasi.'),
          (Icons.electrical_services_rounded, 'Modul sensor', 'Colok ke port hub yang kosong, terdeteksi otomatis.'),
          (Icons.toggle_on_outlined, 'Alat kontrol', 'Pompa, aerator, kipas, lampu lewat relay hub.'),
          (Icons.cell_tower_rounded, 'Gateway 4G', 'Untuk lokasi tanpa Wi‑Fi rumah.'),
        ].indexed) ...[
          _Option(icon: icon, title: title, sub: sub, selected: _type == i, onTap: () => setState(() => _type = i)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        PrimaryButton('Lanjut', trailingIcon: Icons.arrow_forward_rounded, onPressed: () {
          if (_type == 0) return setState(() => _stage = _Stage.method);
          _info(switch (_type) {
            1 => (
                'Colok modul ke port kosong',
                'Matikan dulu hub, colok modul sensor ke port P1–P6 yang kosong, lalu nyalakan lagi. '
                    'Hub mengenali modul otomatis dan kartunya muncul di Beranda.'
              ),
            2 => (
                'Sambungkan alat ke relay',
                'Minta teknisi menyambungkan pompa/aerator ke relay R1–R4. Setelah itu atur namanya di Detail perangkat.'
              ),
            _ => ('Gateway 4G segera hadir', 'Untuk sementara pakai Wi‑Fi atau hotspot HP.'),
          });
        }),
      ];

  void _info((String, String) m) => showModalBottomSheet<void>(
        context: context,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.$1, style: T.h2),
              const SizedBox(height: 8),
              Text(m.$2, style: T.body),
              const SizedBox(height: 20),
              PrimaryButton('Mengerti', onPressed: () => Navigator.pop(c)),
            ]),
          ),
        ),
      );

  // ───────────── 10b: cara ─────────────
  List<Widget> _methodStage() => [
        Text('Hubungkan dengan cara apa?', style: T.s(24, w: FontWeight.w600, ls: -0.3)),
        const SizedBox(height: 4),
        Text('Pilih yang paling mudah. Bisa diganti kalau gagal.', style: T.body),
        const SizedBox(height: 16),
        for (final (i, (icon, title, sub, badge)) in const [
          (Icons.bluetooth_rounded, 'Bluetooth', 'Hub di dekat Anda dicari otomatis.', 'Disarankan'),
          (Icons.qr_code_scanner_rounded, 'Scan QR di casing', 'Arahkan kamera ke stiker QR pada hub.', null),
          (Icons.keyboard_alt_outlined, 'Ketik kode manual', 'Masukkan kode hub di stiker (SYN-xxxx).', null),
          (Icons.wifi_tethering_rounded, 'Hotspot hub', 'Cadangan bila Bluetooth HP bermasalah.', null),
        ].indexed) ...[
          _Option(icon: icon, title: title, sub: sub, badge: badge, selected: _method == i, onTap: () => setState(() => _method = i)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        PrimaryButton('Lanjut', trailingIcon: Icons.arrow_forward_rounded, onPressed: () {
          if (_method == 0 || _method == 2) return _startScan();
          _info(_method == 1
              ? ('Scan QR menyusul', 'Untuk sekarang pakai Bluetooth atau ketik kode SYN-xxxx yang ada di stiker.')
              : ('Hotspot hub', 'Tahan tombol hub 10 detik sampai lampu ungu, lalu sambungkan HP ke Wi‑Fi bernama SYN-xxxx. Panduan lengkap menyusul.'));
        }),
      ];

  // ───────────── 10c: pindai ─────────────
  List<Widget> _scanStage() => [
        Text('Pilih hub Anda', style: T.s(24, w: FontWeight.w600, ls: -0.3)),
        const SizedBox(height: 4),
        Text('Pastikan hub menyala dan lampunya berkedip biru.', style: T.body),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient),
              child: const Icon(Icons.bluetooth_searching_rounded, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mencari… ${_found.length} hub ditemukan', style: T.s(15, w: FontWeight.w600)),
                GestureDetector(
                  onTap: () => setState(() => _stage = _Stage.method),
                  child: Text('Tidak muncul? Coba cara lain', style: T.s(13, w: FontWeight.w500, c: AppColors.blue)),
                ),
              ]),
            ),
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
        const SizedBox(height: 14),
        for (final h in _found) ...[
          Opacity(
            opacity: h.claimed ? 0.5 : 1,
            child: _Option(
              icon: Icons.memory_rounded,
              title: h.id,
              sub: h.claimed ? 'Sudah terdaftar di akun lain' : '${h.signalLabel} · belum terdaftar',
              badge: h == _found.where((x) => !x.claimed).firstOrNull ? 'Baru' : null,
              selected: _picked?.id == h.id,
              onTap: h.claimed ? null : () => setState(() => _picked = h),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        PrimaryButton('Hubungkan', trailingIcon: Icons.arrow_forward_rounded, loading: _busy, onPressed: _picked == null ? null : _pair),
      ];

  // ───────────── 10d / 13b: Wi‑Fi ─────────────
  List<Widget> _wifiStage() {
    final sites = ref.watch(sitesProvider).value ?? const <Site>[];
    final detected = const ['do', 'water_temp', 'ph', 'nh3_water', 'water_level'];
    return [
      if (_wifiError != null) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3F3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF6C4C8), width: 1.5),
          ),
          child: Row(children: [
            const IconChip(Icons.wifi_off_rounded, color: AppColors.red, bg: Color(0x1AEF4E5A)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hub gagal masuk ke Wi‑Fi', style: T.s(16, w: FontWeight.w600)),
                Text('Hub tetap tersambung Bluetooth, tidak perlu mengulang dari awal.', style: T.small),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
      ],
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.blue, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const IconChip(Icons.memory_rounded, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sysnergi Hub', style: T.s(17, w: FontWeight.w600)),
                Text('${_picked!.id} · ${_picked!.signalLabel.toLowerCase()}', style: T.small),
              ]),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
            ),
          ]),
          const SizedBox(height: 12),
          Text('${detected.length} modul terdeteksi otomatis', style: T.s(13, w: FontWeight.w600, c: AppColors.ink2)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in detected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: const Color(0x141C6FE8), borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(metricDef(m).icon, size: 16, color: AppColors.blue),
                  const SizedBox(width: 6),
                  Text(metricDef(m).label.replaceAll(' air', ''), style: T.s(13, w: FontWeight.w600)),
                ]),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 20),
      if (sites.length > 1) ...[
        Text('Pasang di lokasi mana?', style: T.s(18, w: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in sites) SelectChip(s.name, icon: siteIcon(s.kind), selected: _siteId == s.id, onTap: () => setState(() => _siteId = s.id)),
        ]),
        const SizedBox(height: 20),
      ],
      Text('Sambungkan ke Wi‑Fi', style: T.s(18, w: FontWeight.w600)),
      const SizedBox(height: 10),
      Glass(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _ssid,
            icon: const Icon(Icons.expand_more_rounded),
            items: [
              for (final s in _ssids)
                DropdownMenuItem(
                  value: s,
                  child: Row(children: [
                    const Icon(Icons.wifi_rounded, color: AppColors.blue),
                    const SizedBox(width: 12),
                    Text(s, style: T.s(16, w: FontWeight.w600)),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _ssid = v),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _wifiError != null ? AppColors.red : AppColors.line, width: _wifiError != null ? 2 : 1.5),
        ),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, color: _wifiError != null ? AppColors.red : AppColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _password,
              obscureText: _obscure,
              style: T.s(18, w: FontWeight.w600),
              decoration: InputDecoration(border: InputBorder.none, hintText: 'Kata sandi Wi‑Fi', hintStyle: T.s(16, c: AppColors.muted)),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.ink2),
          ),
        ]),
      ),
      if (_wifiError != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0x12EF4E5A), borderRadius: BorderRadius.circular(16)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(_wifiError!, style: T.s(14, w: FontWeight.w500, c: AppColors.redInk, h: 1.4))),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      Row(children: [
        const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.green),
        const SizedBox(width: 6),
        Text('Dikirim terenkripsi lewat Bluetooth', style: T.s(13, w: FontWeight.w500, c: AppColors.ink2)),
      ]),
      const SizedBox(height: 20),
      PrimaryButton(_wifiError == null ? 'Hubungkan' : 'Coba lagi',
          trailingIcon: _wifiError == null ? Icons.arrow_forward_rounded : Icons.refresh_rounded,
          loading: _busy,
          onPressed: _ssid == null ? null : _connectWifi),
    ];
  }

  // ───────────── 13a: gagal Bluetooth ─────────────
  List<Widget> _btFailedStage() {
    final e = _error;
    final code = e?.helpCode(_picked?.id ?? 'SYN-0000') ?? '-';
    final title = switch (e?.error) {
      ProvisioningError.bluetoothOff => 'Bluetooth HP mati',
      ProvisioningError.permissionDenied => 'Izin Bluetooth belum diberikan',
      ProvisioningError.unsupported => 'Cara ini belum tersedia',
      _ => 'Hub belum tersambung',
    };
    return [
      Center(
        child: Container(
          width: 150,
          height: 150,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x12EF4E5A)),
          child: Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: const Color(0xFFF6C4C8), width: 1.5)),
              child: const Icon(Icons.bluetooth_disabled_rounded, size: 42, color: AppColors.red),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Center(child: Text(title, style: T.s(26, w: FontWeight.w600, ls: -0.4))),
      const SizedBox(height: 8),
      Text(
        e?.error == ProvisioningError.unsupported
            ? 'Pairing aman dengan hub belum selesai dibuat di versi ini. Coba mode demo, atau hubungi CS untuk bantuan pemasangan.'
            : 'Tidak apa-apa, ini sering terjadi. Coba cek 4 hal di bawah ini.',
        textAlign: TextAlign.center,
        style: T.body,
      ),
      const SizedBox(height: 18),
      Divided(strong: true, children: [
        for (final (i, (icon, t, s)) in const [
          (Icons.bluetooth_rounded, 'Bluetooth HP menyala', 'Buka pengaturan cepat di HP'),
          (Icons.open_with_rounded, 'HP dekat dengan hub', 'Jarak kurang dari 3 meter'),
          (Icons.lightbulb_outline_rounded, 'Lampu hub berkedip biru', 'Tanda hub siap disambungkan'),
          (Icons.back_hand_outlined, 'Belum berkedip?', 'Tahan tombol di hub 5 detik'),
        ].indexed)
          ListRow(
            leading: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.tint),
              child: Text('${i + 1}', style: T.s(14, w: FontWeight.w600, c: AppColors.blue)),
            ),
            title: t,
            subtitle: s,
            trailing: Icon(icon, color: AppColors.blue),
          ),
      ]),
      const SizedBox(height: 20),
      PrimaryButton('Coba lagi', icon: Icons.refresh_rounded, onPressed: _startScan),
      const SizedBox(height: 12),
      SecondaryButton('Pakai cara lain (QR / kode)', icon: Icons.qr_code_scanner_rounded, onPressed: () => setState(() => _stage = _Stage.method)),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: () => showMessage(context, 'Hubungi CS di WhatsApp dan sebutkan kode $code'),
          icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.green, size: 18),
          label: Text('Masih gagal? Chat CS via WhatsApp', style: T.s(15, w: FontWeight.w500)),
        ),
      ),
      Center(child: Text('Kode bantuan: $code', style: T.s(12, c: AppColors.muted))),
    ];
  }

  // ───────────── selesai ─────────────
  List<Widget> _doneStage() => [
        const SizedBox(height: 60),
        Center(
          child: Container(
            width: 160,
            height: 160,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x1A22B573)),
            child: Center(
              child: Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.green),
                child: const Icon(Icons.check_rounded, size: 52, color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(child: Text('Hub tersambung!', style: T.s(28, w: FontWeight.w600, ls: -0.5))),
        const SizedBox(height: 8),
        Text('Data pertama akan muncul di Beranda dalam beberapa detik. Sensor yang dicolok dikenali otomatis.',
            textAlign: TextAlign.center, style: T.body),
        const SizedBox(height: 32),
        PrimaryButton('Ke Beranda', onPressed: () => context.go('/home')),
      ];
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, required this.sub, required this.selected, this.onTap, this.badge});
  final IconData icon;
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? Colors.white : const Color(0xB3FFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: selected ? AppColors.blue : AppColors.line, width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                IconChip(icon, size: 48, filled: selected),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(title, style: T.s(16, w: FontWeight.w600))),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0x1F22B573), borderRadius: BorderRadius.circular(8)),
                          child: Text(badge!, style: T.s(11, w: FontWeight.w600, c: AppColors.greenInk)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(sub, style: T.s(13, c: AppColors.ink2, h: 1.35)),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? AppColors.blue : const Color(0xFFB8C3D6), width: 2)),
                  child: selected
                      ? Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.blue)))
                      : null,
                ),
              ]),
            ),
          ),
        ),
      );
}
