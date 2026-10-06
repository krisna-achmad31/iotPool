# Sysnergi IoT — backend Firebase

Project Firebase: `autonomous-pond-system` · desain app: `iot.pen` · model data: [docs/data-model.md](docs/data-model.md)

```
firestore.rules · firestore.indexes.json   Firestore: akun, site, zona, otomasi, event, hub, telemetri
database.rules.json                        RTDB: live, perintah, config hub, ACL
shared/src/                                katalog metric/alat, tipe, path, buildHubConfig()
functions/                                 Cloud Functions (butuh Blaze)
tools/provision-hub.mjs                    provisioning pabrik per unit hub (jalan di Spark)
firmware/sysnergi-hub/                     contoh firmware ESP32
app/                                       aplikasi Flutter (mobile + web), lihat app/README.md
tests/                                     tes security rules (emulator) + unit test shared
```

## Setup pertama kali (sekali saja)

1. **Akun CLI.** Firebase CLI di laptop ini login sebagai akun yang *tidak* punya akses ke project ini.
   Tambahkan akun pemilik project:
   ```bash
   firebase login:add
   ```
   lalu `firebase login:use <email-pemilik>`.
2. **Realtime Database.** Console → Build → Realtime Database → *Create database* → lokasi
   **Singapore (asia-southeast1)** → *Locked mode*. Salin URL-nya ke `firmware/sysnergi-hub/config.h`
   dan ke env `FIREBASE_DATABASE_URL` saat provisioning (bila beda dari default).
3. **Authentication.** Aktifkan provider **Email/Password** (dipakai akun hub), **Phone** dan **Google** (untuk user).
4. **Lokasi Firestore.** Cek di Console → Firestore. Jika bukan `asia-southeast2` (Jakarta), ubah `REGION`
   di [functions/src/admin.ts](functions/src/admin.ts) sebelum deploy Functions.
5. **Deploy rules & index** (aman di Spark):
   ```bash
   firebase deploy --only firestore,database
   ```

## Provisioning hub

Butuh service account: Console → Project settings → Service accounts → *Generate new private key*.
Simpan di luar repo.
```bash
set GOOGLE_APPLICATION_CREDENTIALS=D:\kunci\autonomous-pond-system.json
npm run provision -- SYN-0A41
```
Hasilnya `provisioned/SYN-0A41.h` → salin isinya ke `firmware/sysnergi-hub/secrets.h`.

## Firmware

Arduino IDE · board **ESP32 Dev Module** (core esp32 3.x) · **Partition Scheme: Minimal SPIFFS (1.9MB APP with OTA)**
— dengan partisi default sketch ini sudah 99% flash (1,30 MB), sehingga BLE & OTA tidak akan muat. Library:
- *Firebase Arduino Client Library for ESP8266 and ESP32* (mobizt) **4.4.x**. Instalasi di laptop ini
  rusak (folder hanya berisi `library.properties`); hapus lalu install ulang lewat Library Manager.
- *ArduinoJson* 7.x

Isi `FIREBASE_API_KEY` di `config.h`, buat `secrets.h` dari `secrets.h.example`, upload.
Di Serial Monitor (115200): `pair` → mencetak nonce klaim, `status`, `reset`.
Sensor masih simulasi (`readSensor()`); ganti dengan driver modul sebenarnya.

## Tes

Tes rules memakai emulator (Java 11+). Firebase CLI v15 butuh Java 21, jadi script memakai
`firebase-tools@13` lewat npx.
```bash
npm run emulators
```
```bash
npm test
```
(Di CI/Linux cukup `npm run test:rules`. Di Windows, `emulators:exec` lewat npx bisa meninggalkan proses
Java emulator yang masih jalan.)

## Spark sekarang, Blaze nanti

Semua alur inti jalan di Spark. Yang harus dilakukan **app** selama belum ada Functions:
- Setelah mengubah otomasi / zona / port hub: panggil `buildHubConfig()` (atau port Dart-nya) dan tulis
  ke RTDB `hubs/{id}/down/config`, naikkan `hubs/{id}.configVersion`.
- Setelah mengubah anggota site: tulis `sites.roles` ke RTDB `hubs/{id}/acl` untuk tiap hub di site.
- Status offline hub: hitung dari `live.ts` (offline bila > 90 detik).
- Setelah perintah selesai: baca `ack/{cmdId}`, lalu hapus.
- Setelah kalibrasi sukses: tulis `hubs/{id}.ports.Px.calibratedAt`.

Setelah upgrade ke Blaze:
```bash
firebase deploy --only functions
```
Functions mengambil alih sinkronisasi config/ACL (idempoten dengan app), plus push notif FCM,
watchdog hub offline (event *"Hub Kolam 3 terputus"*), dan pengingat kalibrasi.
