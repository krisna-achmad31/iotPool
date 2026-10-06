// Konektivitas: provisioning BLE/SoftAP, Wi-Fi, MQTT, buffer offline, OTA.
// Berjalan di task terpisah (core 0) sehingga kontrol sensor/relay di core 1
// tidak pernah tertahan oleh internet yang lambat atau putus.
#pragma once
#include <Arduino.h>

namespace Net {
enum class Link : uint8_t { PROVISIONING, CONNECTING, WIFI_ONLY, CLOUD };
enum class ProvMode : uint8_t { NONE = 0, BLE = 1, SOFTAP = 2 };

void begin();
Link link();
const char *hwid();      // "SYN-0A41" (tampil di aplikasi & stiker)
const char *deviceId();  // "syn-a1b2c3d40a41" (dipakai di topik MQTT)
const char *pop();       // proof-of-possession provisioning (dicetak di QR)

// Aman dipanggil dari task mana pun
void publish(const char *sub, const String &payload, bool bufferIfOffline, bool retain = false);
void event(const char *level, const String &text, const char *ruleId = nullptr);
bool nextCommand(String &out);
bool takeStateRequest();      // true sekali setelah tersambung ke cloud
void startOta(const String &url, const String &sha256);
void requestProvisioning(ProvMode m);  // simpan mode lalu restart
void factoryReset();
}
