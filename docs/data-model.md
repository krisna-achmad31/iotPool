# Sysnergi — Model Data Firebase

Project: `autonomous-pond-system` (nama project historis; skemanya generik untuk semua vertikal:
kolam, kebun, kandang, dan apa pun berikutnya).

## Prinsip

1. **Dua database, dua peran.**
   - **Realtime Database (RTDB)** = jalur *live*: status sensor/relay detik-ini, perintah app→hub,
     konfigurasi yang di-stream ke hub. ESP32 bisa *stream* RTDB (latensi < 1 detik); Firestore tidak.
   - **Firestore** = sumber kebenaran untuk akun, lokasi, zona, otomasi, riwayat telemetri, dan notifikasi.
2. **Hub tetap otonom.** Otomasi dikompilasi menjadi `config` di RTDB, disimpan hub di flash, dan dijalankan
   lokal. Internet putus → aturan tetap jalan, event di-buffer lalu dikirim saat online.
3. **Generik.** Tidak ada field "kolam" di skema. Vertikal diekspresikan lewat `site.kind`, `zone.kind`,
   katalog **metric** (jenis besaran sensor) dan **actuator kind** (jenis alat) di
   [`shared/src/catalog.ts`](../shared/src/catalog.ts). Menambah vertikal baru = menambah entri katalog.
4. **Bisa jalan di Spark (gratis).** Semua alur inti (klaim hub, telemetri, perintah, notifikasi in-app)
   hanya butuh client + security rules. Cloud Functions (Blaze) menambah: push notif FCM, deteksi hub
   offline, pengingat kalibrasi, dan sinkronisasi config/ACL di sisi server.

## Hierarki

```
User ──(roles)──▶ Site  "Kolam Sukamaju" / "Kebun Bu Sari" / "Kandang Mas Rizal"
                   ├── Zone   "Kolam 2" (pond) · "Greenhouse" (greenhouse) · "Kandang B" (barn)
                   ├── Automation  "Aerator saat oksigen rendah"
                   ├── Event  (feed notifikasi + penanda di grafik)
                   └── Hub  SYN-0A41
                         ├── ports  P1..P6  → modul sensor (metric + zone)
                         ├── relays R1..R4  → alat kontrol (actuator kind + zone)
                         ├── days/{yyyymmdd}   telemetri 5 menit
                         └── months/{yyyymm}   agregat per jam
```

Satu **channel** = satu port sensor di satu hub (`P1`). Grafik zona = semua channel yang `zoneId`-nya zona itu.

---

## Firestore

### `users/{uid}`
| field | tipe | ditulis oleh | catatan |
|---|---|---|---|
| `displayName`, `phone`, `photoURL` | string | user | |
| `prefs` | `{ largeText: bool, alarmSound: bool, locale: 'id'\|'en' }` | user | layar Akun · Kenyamanan |
| `readAt` | `{ [siteId]: Timestamp }` | user | "Tandai dibaca" — event dengan `ts <= readAt` dianggap terbaca |
| `ownedHubIds` | `string[]` | user (divalidasi rules) | dipakai untuk batas kuota hub per paket |
| `plan` | `{ tier: 'free'\|'plus'\|'pro', validUntil: Timestamp, hubLimit: int, aiMonthlyLimit: int }` | **server/admin saja** | default bila kosong: free, `hubLimit` 1 |
| `usage` | `{ aiMonth: 'YYYY-MM', aiCount: int }` | **server/admin saja** | |
| `createdAt` | Timestamp | user (create) | |

`users/{uid}/fcmTokens/{token}` → `{ platform: 'android'|'ios'|'web', updatedAt }`

### `sites/{siteId}` — "usaha / lokasi"
| field | tipe | catatan |
|---|---|---|
| `name` | string | "Kolam Sukamaju" |
| `kind` | string | `aquaculture` \| `horticulture` \| `livestock` \| `mixed` \| … (bebas, lihat katalog) |
| `ownerUid` | string | tidak bisa diubah |
| `roles` | `{ [uid]: 'owner'\|'operator'\|'viewer' }` | owner: semua · operator: kontrol alat & ubah otomasi · viewer: lihat saja |
| `memberUids` | string[] | **harus** = `roles.keys()` (untuk query `array-contains`) |
| `hubIds` | string[] | hub yang terpasang di site ini |
| `timezone` | string | `Asia/Jakarta` |
| `createdAt`, `updatedAt` | Timestamp | |

### `sites/{siteId}/zones/{zoneId}` — kolam, bedeng, kandang, tandon…
| field | tipe | catatan |
|---|---|---|
| `name` | string | "Kolam 2" |
| `kind` | string | `pond`, `greenhouse`, `bed`, `tank`, `barn`, `warehouse`, … |
| `order` | int | urutan chip di Beranda |
| `meta` | map | bebas per vertikal: `{ species: 'lele' }`, `{ crop: 'cabai' }`, `{ flock: 'broiler', placedAt: Timestamp }` |
| `thresholds` | `{ [metric]: Threshold }` | override ambang default katalog |

```ts
type Threshold = {
  ideal?: [number, number];         // "Ideal 40–60%"
  warn?:   { lt?: number; gt?: number };  // Waspada
  danger?: { lt?: number; gt?: number };  // Bahaya
};
// contoh oksigen: { ideal: [5, 8], warn: { lt: 5 }, danger: { lt: 3 } }
```

### `sites/{siteId}/automations/{ruleId}`
| field | tipe | catatan |
|---|---|---|
| `name` | string | "Aerator saat oksigen rendah" |
| `enabled` | bool | |
| `hubId` | string | hub yang mengeksekusi (sensor & relay harus di hub yang sama agar bisa offline) |
| `trigger` | Trigger | lihat bawah |
| `action` | Action | |
| `safety` | `{ maxRunSec?: int, cooldownSec?: int }` | "BATAS AMAN · maksimal 45 menit" |
| `source` | `'manual'\|'template'\|'ai'` | `prompt` disimpan bila dari Asisten |
| `templateId?`, `prompt?` | string | |
| `createdBy`, `createdAt`, `updatedAt` | | |

```ts
type Trigger =
  | { type: 'threshold'; ch: 'P1'; op: 'lt' | 'gt'; value: number; holdSec?: number }
  | { type: 'schedule'; start: 'HH:MM'; end?: 'HH:MM'; days?: number[] /* 1=Senin..7 */ };

type Action =
  | { type: 'relay'; relay: 'R1'; on: boolean; level?: number;
      until?: { type: 'threshold'; ch: string; op: 'lt' | 'gt'; value: number }
            | { type: 'duration'; sec: number }
            | { type: 'trigger_clears' } }      // default
  | { type: 'notify'; severity: 'info' | 'warning' | 'danger' };
```

Contoh dari desain — *"Isi kolam kalau airnya kurang dari 70 cm"*:
```json
{
  "name": "Isi kolam otomatis", "enabled": true, "hubId": "SYN-0A41", "source": "ai",
  "prompt": "Isi kolam kalau airnya kurang dari 70 cm",
  "trigger": { "type": "threshold", "ch": "P5", "op": "lt", "value": 70, "holdSec": 60 },
  "action":  { "type": "relay", "relay": "R2", "on": true,
               "until": { "type": "threshold", "ch": "P5", "op": "gt", "value": 80 } },
  "safety":  { "maxRunSec": 2700, "cooldownSec": 600 }
}
```

### `sites/{siteId}/events/{eventId}` — feed notifikasi & penanda grafik
| field | tipe | catatan |
|---|---|---|
| `ts` | Timestamp | waktu kejadian **di hub** (bisa lebih lama dari waktu tulis bila di-buffer offline) |
| `type` | string | `alarm`, `alarm_clear`, `automation_start`, `automation_stop`, `hub_offline`, `hub_online`, `command`, `calibration_due`, `firmware_available`, `report`, `system` |
| `severity` | `'danger'\|'warning'\|'info'` | filter tab Notifikasi |
| `source` | `'hub'\|'app'\|'server'` | |
| `hubId?`, `zoneId?`, `ch?`, `metric?`, `value?`, `relay?`, `ruleId?`, `by?` | | konteks terstruktur, app merender teks dari sini (i18n) |
| `title?`, `body?` | string | opsional, untuk event `report`/`system` dari server |

ID event dari hub = `{hubId}-{epochMs}` → retry kirim ulang tidak membuat duplikat.

### `hubs/{hubId}` — identitas perangkat (global, satu dokumen per hub fisik)
| field | tipe | ditulis oleh |
|---|---|---|
| `authUid` | string | **admin** (provisioning pabrik) |
| `model`, `hwRev` | string | admin |
| `ownerUid`, `siteId` | string \| null | user saat klaim / lepas |
| `claim` | `{ nonce: string, expiresAt: Timestamp }` | hub (saat mode pairing) |
| `claimNonce` | string | user saat klaim (bukti) |
| `name` | string | owner/operator — "Hub Kolam 2" |
| `ports` | `{ P1..P6: { metric, zoneId, label?, calibratedAt?, sensorModel? } \| null }` | owner/operator |
| `relays` | `{ R1..R4: { kind, label, zoneId, levels? } \| null }` | owner/operator |
| `detected` | `{ P1: 'do', … }` | hub — modul yang terdeteksi otomatis |
| `fw` | `{ version: '1.4.2', updatedAt }` | hub |
| `connectivity` | `'wifi'\|'4g'` | hub |
| `configVersion` | int | owner/operator (dinaikkan saat config dipublish) |

### `hubs/{hubId}/days/{yyyymmdd}` — telemetri resolusi 5 menit (grafik 24 jam & 7 hari)
```json
{
  "hubId": "SYN-0A41", "siteId": "abc123", "date": "2026-10-02", "tzOffsetMin": 420,
  "s": {
    "t0935": { "P1": 4.1, "P2": 28.4, "P3": 7.2, "P4": 0.02, "P5": 82 },
    "t0940": { "P1": 4.0, "P2": 28.4, "P3": 7.2, "P4": 0.02, "P5": 82 }
  }
}
```
- Kunci slot `tHHMM` = awal jendela 5 menit **waktu lokal**; nilai = rata-rata sampel di jendela itu.
- Hub menulis dengan `patchDocument` + `updateMask: hubId,siteId,date,tzOffsetMin,s.tHHMM` → 288 tulis/hari/hub.
- Maks 288 slot × 6 channel ≈ 35 KB/dokumen. Indexing field `s` dimatikan (lihat `firestore.indexes.json`).
- 24 jam = baca 2 dokumen, 7 hari = 8 dokumen.

### `hubs/{hubId}/months/{yyyymm}` — agregat per jam (grafik 30 hari, laporan CSV/PDF)
```json
{ "hubId": "SYN-0A41", "siteId": "abc123", "month": "2026-10", "tzOffsetMin": 420,
  "h": { "d02h03": { "P1": [3.8, 4.2, 4.6] } } }   // [min, avg, max]
```

> **Kenapa `siteId` disalin ke dokumen telemetri?** Hak baca dicek terhadap `siteId` *pada saat data ditulis*.
> Jika hub dipindah/dijual, pemilik lama tetap melihat riwayatnya sendiri, pemilik baru tidak melihat
> riwayat pemilik lama.

---

## Realtime Database

```
/hubs/{hubId}
  meta/        authUid (admin) · ownerUid · claimNonce · siteId
  acl/{uid}    'owner' | 'operator' | 'viewer'          ← cermin sites.roles
  claim/       { nonce, exp }                            hub → (tidak bisa dibaca user)
  live/        hub → app, ditimpa tiap ~10 detik
  ack/{cmdId}  hub → app
  down/        app → hub (hub men-stream path ini)
    config     konfigurasi terkompilasi (port, relay, aturan, alarm)
    cmd/{id}   antrean perintah
/firmware/{model}   { version, url, sha256, notes }      admin →
```

### `live`
```json
{
  "ts": 1790000000000,               // {".sv":"timestamp"} — app: online jika now - ts < 90 s
  "rssi": -58, "power": "mains", "batt": null, "uptimeS": 1036800, "fw": "1.4.2",
  "ch": { "P1": { "v": 4.1 }, "P2": { "v": 28.4 }, "P6": null },
  "relays": { "R1": { "on": true, "mode": "auto", "since": 1789997480000, "ruleId": "r_do_low" },
              "R2": { "on": false, "mode": "auto" } },
  "pendingEvents": 0                 // > 0 berarti ada event offline yang belum terkirim
}
```

### `down/cmd/{pushId}` — perintah
```json
{ "type": "relay", "args": { "relay": "R1", "on": true, "durationSec": 1800 },
  "by": "uidDarto", "ts": {".sv": "timestamp"}, "expSec": 60 }
```
| `type` | `args` |
|---|---|
| `relay` | `{ relay, on, level?, durationSec? }` — override manual; `durationSec` habis → kembali `auto` |
| `relay_auto` | `{ relay }` — kembalikan ke mode otomatis |
| `test_relay` | `{ relay }` — nyala 3 detik |
| `calibrate` | `{ port, step: 'zero'\|'span'\|'ph7'\|'ph4'\|'ph10', ref? }` |
| `identify` | `{}` — LED berkedip |
| `restart` | `{}` |
| `ota` | `{ version }` |

Hub **menolak** perintah yang `now - ts > expSec` (mencegah "nyalakan pompa" yang tertunda jam-jaman
dieksekusi saat hub online lagi). Setelah diproses hub menulis `ack/{cmdId} = { ok, code, ts }` lalu
menghapus `down/cmd/{cmdId}`. App pengirim menghapus `ack/{cmdId}` setelah membacanya.

### `down/config` — dibangun oleh `buildHubConfig()` di [`shared/src/hub-config.ts`](../shared/src/hub-config.ts)
```json
{
  "v": 7, "siteId": "abc123", "tzOffsetMin": 420,
  "ports":  { "P1": { "m": "do", "z": "zoneKolam2" } },
  "relays": { "R1": { "k": "aerator", "z": "zoneKolam2" } },
  "alarms": [ { "ch": "P1", "warn": { "lt": 5 }, "danger": { "lt": 3 } } ],
  "rules":  [ { "id": "r_do_low", "trigger": {...}, "action": {...}, "safety": {...} } ]
}
```
Key dibuat pendek karena ikut disimpan di flash hub.

---

## Alur utama

### 1. Provisioning pabrik (admin, sekali per unit)
`tools/provision-hub.mjs SYN-0A41` → buat akun Auth hub (email/password), dokumen `hubs/SYN-0A41`
(`authUid`), dan RTDB `hubs/SYN-0A41/meta/authUid`. Kredensial di-flash ke NVS hub.
Rules mengenali hub dari `authUid`, **bukan** dari email, jadi orang lain tidak bisa menyamar jadi hub.

### 2. Klaim hub (layar *Tambah perangkat*)
1. App terhubung BLE ke hub → minta pairing.
2. Hub membuat `nonce` acak, menulis `claim` ke RTDB & Firestore (berlaku 10 menit), dan mengirim
   `nonce` ke app **lewat BLE** (hanya orang yang secara fisik dekat hub yang bisa tahu).
3. App mengirim kredensial Wi-Fi lewat BLE (terenkripsi).
4. App menulis dalam **satu batch Firestore**: `hubs/{id}` (`ownerUid`, `siteId`, `claimNonce`),
   `sites/{siteId}.hubIds += id`, `users/{uid}.ownedHubIds += id`. Rules memastikan nonce cocok,
   belum ada pemilik, dan kuota paket (`plan.hubLimit`) tidak terlampaui.
5. App menulis **satu multi-path update RTDB**: `meta/ownerUid`, `meta/claimNonce`, `meta/siteId`,
   `acl/{uid}='owner'`.
6. Hub melihat `meta/ownerUid` terisi → menghapus `claim`, lalu menunggu `down/config`.

"Sudah terdaftar di akun lain" = `ownerUid` sudah terisi (hub mengiklankan flag ini di BLE).

### 3. Telemetri
- Tiap ~10 detik → RTDB `live` (ditimpa, murah).
- Tiap 5 menit → Firestore `days/{date}` slot `tHHMM`.
- Tiap jam → Firestore `months/{yyyymm}` kunci `dDDhHH`.
- Lewat ambang alarm (dengan histeresis) → Firestore `sites/{siteId}/events`.

### 4. Kontrol dari app
App `push()` ke `down/cmd` → hub menerima via stream (< 1 detik) → relay berubah → `live.relays`
ter-update → UI berubah. Event `command` dicatat oleh app (opsional, untuk riwayat).

### 5. Mengubah otomasi / port / anggota
| | Spark (sekarang) | Blaze (Cloud Functions aktif) |
|---|---|---|
| Publish config ke hub | app memanggil `buildHubConfig()` lalu set `down/config` | trigger `syncHubConfig` |
| Sinkron `roles` → RTDB `acl` | app menulis `acl` di tiap hub site | trigger `syncSiteAcl` |
| Push notif HP | — (feed in-app saja) | trigger `notifyOnEvent` (FCM) |
| Hub terputus | app menghitung dari `live.ts` | `hubWatchdog` tiap 5 menit → event `hub_offline` |
| Pengingat kalibrasi | app menghitung dari `calibratedAt` | `calibrationReminder` harian |

Kedua jalur menulis data yang sama (idempoten), jadi aman dijalankan bersamaan saat transisi ke Blaze.

---

## Perkiraan kuota Spark (per hub per hari)
| operasi | jumlah | batas Spark |
|---|---|---|
| Firestore write (days + months + events) | ~288 + 24 + ±10 ≈ 325 | 20.000/hari → ±60 hub |
| Firestore read akibat rules (`get(hubs/…)`) | ≈ 325 | 50.000/hari |
| RTDB upload `live` | 8.640 × ±400 B ≈ 3,5 MB | 10 GB/bulan download (yang dihitung download) |

Saat melewati ±40 hub aktif, sebaiknya pindah ke Blaze.
