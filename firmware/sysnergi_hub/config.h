// =====================================================================
//  Sysnergi Hub — konfigurasi pin & konstanta
//  Board : ESP32-WROOM-32 DevKit 38 pin ("ESP32 V3"), core arduino-esp32 3.x
// =====================================================================
#pragma once
#include <Arduino.h>

#define FW_VERSION "1.0.0"

// ---------- Bus I2C utama (ke TCA9548A + RTC) ----------
#define PIN_I2C_SDA   21
#define PIN_I2C_SCL   22
#define I2C_FREQ      50000      // 50 kHz: lebih tahan kabel panjang ke modul
#define TCA_ADDR      0x70       // multiplexer I2C 8 kanal
#define RTC_ADDR      0x68       // DS3231 (di bus utama, bukan di mux)

// ---------- 6 Smart Port (konektor GX16-8) ----------
// Tiap port: 12V, 5V, 3V3, GND, SDA, SCL (kanal mux = nomor port), A, D
#define NUM_PORTS 6
// A = jalur analog. WAJIB ADC1 karena ADC2 tidak bisa dipakai saat Wi-Fi aktif.
static const uint8_t PORT_PIN_A[NUM_PORTS] = {36, 39, 34, 35, 32, 33};
// D = jalur digital dua arah (1-Wire, UART RX, pulsa). Hindari GPIO12 (strapping).
static const uint8_t PORT_PIN_D[NUM_PORTS] = {13, 14, 18, 19, 5, 15};

// ---------- RS485 (bus sensor industri: DO/pH/amonia Modbus) ----------
#define PIN_RS485_RX  16
#define PIN_RS485_TX  17
#define PIN_RS485_DE  4          // DE + /RE dijumper jadi satu
#define RS485_BAUD    9600

// ---------- 4 Relay output ----------
#define NUM_RELAYS 4
static const uint8_t RELAY_PIN[NUM_RELAYS] = {25, 26, 27, 23};
#define RELAY_ACTIVE_LOW true    // modul relay optocoupler umumnya aktif LOW

// ---------- UI di casing ----------
#define PIN_STATUS_LED 2         // 1x WS2812B (LED RGB status)
#define PIN_BUTTON     0         // tombol BOOT onboard + tombol eksternal paralel

// ---------- Timing ----------
#define CONTROL_TICK_MS      50
#define SENSOR_PERIOD_MS     5000
#define RULE_PERIOD_MS       1000
#define PORT_SCAN_PERIOD_MS  10000
#define TELEMETRY_PERIOD_MS  30000
#define RELAY_MIN_OFF_MS     30000   // anti on/off cepat (lindungi motor pompa/aerator)
#define SENSOR_STALE_MS      60000   // data lebih tua dari ini dianggap tidak valid

// ---------- Cloud (MQTT) ----------
// Ganti dengan broker Anda. Untuk produksi pakai mqtts:// + sertifikat CA.
#define MQTT_URI   "mqtt://broker.hivemq.com:1883"
#define MQTT_USER  ""
#define MQTT_PASS  ""
#define TOPIC_ROOT "sysnergi"        // sysnergi/<HWID>/{telemetry,event,state,cmd}

// ---------- Penyimpanan ----------
#define FILE_RULES   "/rules.json"
#define FILE_PORTS   "/ports.json"   // penetapan manual modul tanpa EEPROM ID
#define FILE_MODBUS  "/modbus.json"  // daftar sensor RS485
#define FILE_BUFFER  "/buffer.jsonl" // antrean telemetri saat offline
#define BUFFER_MAX_BYTES (28 * 1024)   // LittleFS cuma 64 KB (lihat partitions.csv)
#define OFFLINE_BUFFER_EVERY 10        // saat offline simpan 1 dari 10 telemetri (= tiap 5 menit, ~12 jam)
