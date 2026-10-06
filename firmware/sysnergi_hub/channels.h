// Tabel nilai sensor bersama. Setiap nilai punya kunci "kanal":
//   p<port>.<besaran>   contoh: p2.do, p1.temp, p4.level
//   rs<addr>.<besaran>  contoh: rs1.nh3  (sensor RS485/Modbus)
// Aturan otomasi & telemetri hanya mengenal kunci kanal, bukan jenis sensornya.
// Itulah yang membuat sensor apa pun bisa langsung dipakai di aturan.
#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>

#define MAX_CHANNELS 48

struct Channel {
  char key[16];
  char unit[8];
  float value;
  uint32_t ts;     // millis() saat terakhir diperbarui
  bool used;
};

namespace Channels {
void set(const char *key, float value, const char *unit);
bool get(const char *key, float &out);   // false bila tidak ada / basi
bool findFirstByQuantity(const char *quantity, float &out);  // mis. "temp" dari port mana pun
void removePrefix(const char *prefix);   // hapus kanal saat modul dicabut
void toJson(JsonObject obj);
}
