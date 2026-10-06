# Sysnergi — aplikasi Flutter

Aplikasi mobile (Android/iOS) + web untuk Sysnergi. Desain: `../iot.pen` baris **v3 Mono Blue Glass**.
Model data: [`../docs/data-model.md`](../docs/data-model.md).

## Menjalankan

```bash
flutter pub get
flutter run                 # mode demo: data contoh, tanpa Firebase
```

Mode demo: nomor HP apa saja, kode OTP 6 angka apa saja. Kata sandi Wi‑Fi `salah` (atau < 8 karakter)
memicu layar gagal Wi‑Fi; hub `SYN-0F00` memicu layar gagal Bluetooth.

### Mode Firebase

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=autonomous-pond-system   # menimpa lib/firebase_options.dart
flutter run --dart-define=SYSNERGI_MODE=firebase
```

Butuh: provider Phone & Google aktif di Authentication, RTDB sudah dibuat (lihat README root),
dan SHA-1/SHA-256 debug Android didaftarkan di Firebase Console untuk login nomor HP.

## Struktur

```
lib/
  domain/     katalog metric & alat (port shared/src/catalog.ts), model, logika ambang,
              buildHubConfig (port shared/src/hub-config.ts), pengurai kalimat → aturan
  data/       SysnergiRepository · DemoRepository · FirebaseRepository · provisioning BLE · provider Riverpod
  core/       token warna v3, komponen kaca, tombol, grafik batang
  features/   auth, onboarding, home (+telemetri), devices (+tambah, kalibrasi), automation (+asisten),
              notifications, account (+anggota, paywall), shell (tab bar)
```

`FirebaseRepository` mengikuti alur di data-model: klaim hub = batch Firestore + multi-path RTDB,
perintah = `down/cmd` → tunggu `ack` (timeout 15 detik), ubah otomasi = tulis Firestore lalu
publish `down/config` (mode Spark, sebelum Cloud Functions aktif).

## Tes

```bash
flutter analyze
flutter test
```

`test/domain_test.dart` mencerminkan `tests/shared.test.ts` untuk `buildHubConfig`, supaya hasil Dart
dan TypeScript tetap identik.

## Belum selesai

| Bagian | Status |
|---|---|
| Pairing BLE ke hub asli | Pemindaian jalan. Sesi aman ESP-IDF provisioning (security 1 + POP), kirim Wi‑Fi, dan endpoint nonce klaim belum ada di app maupun firmware `sysnergi_hub`. Mode Firebase saat ini berhenti di layar gagal Bluetooth. |
| Dua varian firmware | `firmware/sysnergi-hub` (RTDB/Firestore, cocok dengan app) dan `firmware/sysnergi_hub` (MQTT + WiFiProv BLE). Perlu diputuskan mana yang dipakai produk. |
| Undangan anggota | `users/{uid}` hanya bisa dibaca pemiliknya dan belum ada koleksi undangan; penerimaan undangan butuh Cloud Function. |
| Pembayaran | Paywall tampil, Google Play Billing belum disambungkan. |
| Scan QR, hotspot hub, unduh laporan | Tombol ada, fungsinya menyusul. |
| Asisten AI | Pengurai kalimat lokal (`domain/rule_parser.dart`). LLM lewat Cloud Function menyusul. |
| Font | Outfit diambil Google Fonts saat runtime; bundel ke `assets/` sebelum rilis agar jalan offline. |
