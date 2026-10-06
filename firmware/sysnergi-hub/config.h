#pragma once

// ─── Firebase project ───────────────────────────────────────────────
// API key: Console → Project settings → General → Web API Key
#define FIREBASE_API_KEY      "ISI_WEB_API_KEY"
#define FIREBASE_PROJECT_ID   "autonomous-pond-system"
// Console → Realtime Database → URL di bagian atas tab Data
#define FIREBASE_DATABASE_URL "https://autonomous-pond-system-default-rtdb.asia-southeast1.firebasedatabase.app"

// ─── Identitas hub ──────────────────────────────────────────────────
// Dibuat oleh `npm run provision -- SYN-xxxx` → provisioned/SYN-xxxx.h
// Salin isinya ke secrets.h (lihat secrets.h.example). Di produksi disimpan di NVS saat flashing pabrik.
#include "secrets.h"

#define FW_VERSION  "1.4.2"
#define HUB_MODEL   "SYN-HUB-1"

// ─── Hardware ───────────────────────────────────────────────────────
static const uint8_t RELAY_PINS[4] = {26, 27, 32, 33};   // R1..R4
#define RELAY_ACTIVE_HIGH true
#define STATUS_LED 2

// ─── Interval ───────────────────────────────────────────────────────
#define SAMPLE_INTERVAL_MS   2000UL    // baca sensor
#define LIVE_INTERVAL_MS     10000UL   // tulis RTDB live
#define RULE_TICK_MS         1000UL    // evaluasi otomasi
#define ALARM_HOLD_SEC       30        // ambang harus terlewati selama ini sebelum alarm
#define CLAIM_TTL_SEC        600       // token klaim berlaku 10 menit
