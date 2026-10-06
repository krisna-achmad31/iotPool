import 'dart:async';
import 'dart:math';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/models.dart';

/// Alur "Tambah perangkat": pindai hub lewat BLE → pairing (dapat nonce klaim) → kirim Wi‑Fi.
abstract class HubProvisioner {
  Stream<List<DiscoveredHub>> scan();
  Future<void> stopScan();

  /// Sambung ke hub dan buka sesi aman. [pop] = proof-of-possession dari stiker QR (opsional untuk BLE).
  /// Return nonce klaim yang dibuat hub (docs/data-model.md · Alur 2).
  Future<String> pair(DiscoveredHub hub, {String? pop});
  Future<List<String>> scanWifi();
  Future<void> sendWifi(String ssid, String password);
  Future<void> disconnect();
}

enum ProvisioningError { bluetoothOff, permissionDenied, timeout, wrongWifiPassword, wifiNotFound, unsupported }

class ProvisioningException implements Exception {
  ProvisioningException(this.error, [this.detail]);
  final ProvisioningError error;
  final String? detail;

  /// Kode singkat untuk CS ("Kode bantuan: BLE-TIMEOUT-0A41").
  String helpCode(String hubId) {
    final tag = switch (error) {
      ProvisioningError.bluetoothOff => 'BLE-OFF',
      ProvisioningError.permissionDenied => 'BLE-PERM',
      ProvisioningError.timeout => 'BLE-TIMEOUT',
      ProvisioningError.wrongWifiPassword => 'WIFI-AUTH',
      ProvisioningError.wifiNotFound => 'WIFI-NOAP',
      ProvisioningError.unsupported => 'BLE-PROTO',
    };
    return '$tag-${hubId.replaceFirst('SYN-', '')}';
  }

  @override
  String toString() => 'ProvisioningException($error, $detail)';
}

/// Simulasi untuk mode demo. Kata sandi Wi‑Fi "salah" memicu layar gagal Wi‑Fi,
/// hub SYN-0F00 memicu layar gagal Bluetooth.
class DemoProvisioner implements HubProvisioner {
  @override
  Stream<List<DiscoveredHub>> scan() async* {
    yield const [];
    await Future<void>.delayed(const Duration(milliseconds: 900));
    yield const [DiscoveredHub(id: 'SYN-0B5E', rssi: -52, claimed: false)];
    await Future<void>.delayed(const Duration(milliseconds: 900));
    yield const [
      DiscoveredHub(id: 'SYN-0B5E', rssi: -52, claimed: false),
      DiscoveredHub(id: 'SYN-0F00', rssi: -71, claimed: false),
      DiscoveredHub(id: 'SYN-0B17', rssi: -80, claimed: true),
    ];
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<String> pair(DiscoveredHub hub, {String? pop}) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (hub.id == 'SYN-0F00') throw ProvisioningException(ProvisioningError.timeout);
    return List.generate(16, (_) => Random().nextInt(16).toRadixString(16)).join();
  }

  @override
  Future<List<String>> scanWifi() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return const ['WiFi_Rumah_Darto', 'Indihome-7731', 'Kolam_AP'];
  }

  @override
  Future<void> sendWifi(String ssid, String password) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (password.toLowerCase() == 'salah' || password.length < 8) {
      throw ProvisioningException(ProvisioningError.wrongWifiPassword);
    }
  }

  @override
  Future<void> disconnect() async {}
}

/// Provisioning ke firmware `firmware/sysnergi_hub` (WiFiProv, skema BLE, security 1, nama `SYN-xxxx`).
///
/// Pemindaian BLE sudah jalan. Sesi aman protocomm "security 1" (X25519 + AES-CTR dengan POP)
/// dan endpoint `prov-config`/`prov-scan` belum diimplementasikan di Dart, begitu juga endpoint
/// custom untuk nonce klaim (firmware belum menyediakannya). Sampai itu ada, [pair] melempar
/// [ProvisioningError.unsupported] dan app menampilkan layar gagal + opsi cara lain.
class BleHubProvisioner implements HubProvisioner {
  BleHubProvisioner([FlutterReactiveBle? ble]) : _ble = ble ?? FlutterReactiveBle();

  /// UUID layanan provisioning di firmware (net.cpp `provUuid`, urutan byte little-endian).
  static final provService = Uuid.parse('021a9004-0382-4aea-bff4-6b3f1c5adfb4');

  final FlutterReactiveBle _ble;
  StreamSubscription<DiscoveredDevice>? _sub;

  Future<void> _ensurePermissions() async {
    final statuses = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    if (statuses.values.any((s) => s.isPermanentlyDenied || s.isDenied)) {
      throw ProvisioningException(ProvisioningError.permissionDenied);
    }
    if (_ble.status == BleStatus.poweredOff) throw ProvisioningException(ProvisioningError.bluetoothOff);
  }

  @override
  Stream<List<DiscoveredHub>> scan() {
    final found = <String, DiscoveredHub>{};
    late final StreamController<List<DiscoveredHub>> out;
    out = StreamController<List<DiscoveredHub>>(
      onListen: () async {
        try {
          await _ensurePermissions();
        } on ProvisioningException catch (e) {
          out.addError(e);
          return;
        }
        out.add(const []);
        _sub = _ble.scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency).listen((d) {
          if (!d.name.startsWith('SYN-')) return;
          found[d.name] = DiscoveredHub(id: d.name, rssi: d.rssi, claimed: false, bleId: d.id);
          out.add(found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
        }, onError: out.addError);
      },
      onCancel: stopScan,
    );
    return out.stream;
  }

  @override
  Future<void> stopScan() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<String> pair(DiscoveredHub hub, {String? pop}) async {
    await stopScan();
    throw ProvisioningException(ProvisioningError.unsupported, 'protocomm security 1 belum diimplementasikan');
  }

  @override
  Future<List<String>> scanWifi() async => throw ProvisioningException(ProvisioningError.unsupported);

  @override
  Future<void> sendWifi(String ssid, String password) async => throw ProvisioningException(ProvisioningError.unsupported);

  @override
  Future<void> disconnect() => stopScan();
}
