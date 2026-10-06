// Output relay dengan pengaman: batas waktu nyala maksimum, jeda minimum
// sebelum boleh nyala lagi (melindungi motor), dan prioritas sumber perintah.
#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>

enum class RelaySource : uint8_t { NONE, RULE, MANUAL, TEST };

namespace Relays {
void begin();
// Perintah dari aturan. Diabaikan bila relay sedang dikendalikan manual.
void ruleRequest(uint8_t idx, bool on, uint32_t maxRunMs);
// Perintah manual dari aplikasi; durationMs = 0 berarti sampai dimatikan.
void manual(uint8_t idx, bool on, uint32_t durationMs);
void releaseManual(uint8_t idx);
void tick();  // panggil tiap putaran kontrol
bool isOn(uint8_t idx);
void stateJson(JsonArray arr);
void runTest();  // uji relay satu per satu (menu "Uji relay")
}
