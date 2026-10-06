// Smart Port manager: deteksi modul otomatis (plug & play) + hot-plug.
// Urutan identifikasi tiap port:
//   1. EEPROM ID di modul (0x50)  -> paling andal, kalibrasi ikut modul
//   2. Penetapan manual dari aplikasi (/ports.json)
//   3. Probe alamat I2C sensor polos (SHT3x, BH1750)
//   4. Probe presence 1-Wire di jalur D (DS18B20 polos)
#pragma once
#include "sensor_driver.h"
#include <ArduinoJson.h>

namespace PortManager {
bool begin();                  // false bila TCA9548A tidak terdeteksi
void scan();                   // panggil berkala; mendeteksi pasang/cabut
void sampleAll();
void infoJson(JsonArray arr);  // ringkasan port untuk aplikasi
bool writeCalibration(uint8_t port, JsonArrayConst cal, uint32_t epoch);
bool writeDescriptor(uint8_t port, const ModuleDescriptor &d);
void setManualMap(JsonObjectConst map);  // {"3":513} port -> kode jenis
uint8_t usedCount();
}
