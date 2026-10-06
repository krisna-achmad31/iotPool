#include "port_manager.h"
#include "channels.h"
#include "config.h"
#include "net.h"
#include <Wire.h>
#include <LittleFS.h>
#include <OneWire.h>

#define EEPROM_ADDR 0x50

struct PortSlot {
  PortContext ctx;
  SensorDriver *drv = nullptr;
  uint16_t type = MOD_NONE;
  uint32_t serial = 0;
};

static PortSlot slots[NUM_PORTS];
static uint16_t manualType[NUM_PORTS];

void PortContext::selectBus() const {
  Wire.beginTransmission(TCA_ADDR);
  Wire.write(1 << (port - 1));
  Wire.endTransmission();
}

static void deselectAll() {
  Wire.beginTransmission(TCA_ADDR);
  Wire.write(0);
  Wire.endTransmission();
}

static bool readDescriptor(ModuleDescriptor &d) {
  Wire.beginTransmission(EEPROM_ADDR);
  Wire.write(0);
  if (Wire.endTransmission() != 0) return false;
  if (Wire.requestFrom((uint8_t)EEPROM_ADDR, (uint8_t)sizeof(d)) != sizeof(d)) return false;
  uint8_t *p = (uint8_t *)&d;
  for (size_t i = 0; i < sizeof(d); i++) p[i] = Wire.read();
  return d.magic == DESC_MAGIC && d.crc == crc16(p, offsetof(ModuleDescriptor, crc));
}

static bool oneWirePresent(uint8_t pin) {
  OneWire ow(pin);  // jalur D punya pull-up 4k7 di hub, jadi port kosong = tidak ada presence
  return ow.reset() == 1;
}

static void loadManualMap() {
  memset(manualType, 0, sizeof(manualType));
  File f = LittleFS.open(FILE_PORTS, "r");
  if (!f) return;
  JsonDocument doc;
  if (deserializeJson(doc, f) == DeserializationError::Ok)
    for (JsonPairConst kv : doc.as<JsonObjectConst>()) {
      int p = atoi(kv.key().c_str());
      if (p >= 1 && p <= NUM_PORTS) manualType[p - 1] = kv.value().as<uint16_t>();
    }
  f.close();
}

bool PortManager::begin() {
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQ);
  Wire.setTimeOut(50);
  for (uint8_t i = 0; i < NUM_PORTS; i++) {
    slots[i].ctx.port = i + 1;
    slots[i].ctx.pinA = PORT_PIN_A[i];
    slots[i].ctx.pinD = PORT_PIN_D[i];
  }
  loadManualMap();
  Wire.beginTransmission(TCA_ADDR);
  return Wire.endTransmission() == 0;
}

void PortManager::setManualMap(JsonObjectConst map) {
  File f = LittleFS.open(FILE_PORTS, "w");
  if (f) { serializeJson(map, f); f.close(); }
  loadManualMap();
  for (auto &s : slots) s.type = 0xFFFF;  // paksa deteksi ulang semua port
  scan();
}

static void detach(PortSlot &s) {
  if (s.drv) { delete s.drv; s.drv = nullptr; }
  char prefix[6];
  snprintf(prefix, sizeof(prefix), "p%u.", s.ctx.port);
  Channels::removePrefix(prefix);
}

void PortManager::scan() {
  for (uint8_t i = 0; i < NUM_PORTS; i++) {
    PortSlot &s = slots[i];
    s.ctx.selectBus();
    ModuleDescriptor d{};
    bool eeprom = readDescriptor(d);
    uint16_t type = eeprom ? d.type : manualType[i];
    if (type == MOD_NONE) type = probeBareI2C();
    if (type == MOD_NONE) {
      // DS18B20 polos yang sedang aktif tidak di-probe ulang agar konversinya tidak terganggu
      if (s.type == MOD_DS18B20 && !s.ctx.hasEeprom) continue;
      if (oneWirePresent(s.ctx.pinD)) type = MOD_DS18B20;
    }
    uint32_t serial = eeprom ? d.serial : 0;

    if (type == s.type && serial == s.serial) continue;  // tidak berubah

    bool wasEmpty = s.type == MOD_NONE || s.type == 0xFFFF;
    detach(s);
    s.type = type;
    s.serial = serial;
    s.ctx.hasEeprom = eeprom;
    s.ctx.desc = d;
    if (type == MOD_NONE) {
      if (!wasEmpty) Net::event("info", "Modul dicabut dari port " + String(i + 1));
      continue;
    }
    s.drv = createDriver(type);
    if (!s.drv || !s.drv->begin(s.ctx)) {
      Net::event("warn", "Port " + String(i + 1) + ": modul " + typeName(type) + " gagal dimulai");
      delete s.drv;
      s.drv = nullptr;
      continue;
    }
    Serial.printf("[port] P%u -> %s%s\n", i + 1, s.drv->model(), eeprom ? " (EEPROM)" : "");
    Net::event("info", "Modul " + String(s.drv->model()) + " terdeteksi di port " + String(i + 1));
  }
  deselectAll();
}

void PortManager::sampleAll() {
  for (auto &s : slots)
    if (s.drv) s.drv->sample(s.ctx);
  deselectAll();
}

void PortManager::infoJson(JsonArray arr) {
  for (auto &s : slots) {
    JsonObject o = arr.add<JsonObject>();
    o["port"] = s.ctx.port;
    o["type"] = s.drv ? s.type : 0;
    o["model"] = s.drv ? s.drv->model() : "";
    o["id"] = s.ctx.hasEeprom;
    if (s.ctx.hasEeprom) {
      o["name"] = s.ctx.desc.name;
      o["serial"] = s.ctx.desc.serial;
      o["calEpoch"] = s.ctx.desc.calEpoch;
    }
  }
}

bool PortManager::writeDescriptor(uint8_t port, const ModuleDescriptor &src) {
  if (port < 1 || port > NUM_PORTS) return false;
  ModuleDescriptor d = src;
  d.magic = DESC_MAGIC;
  d.crc = crc16((uint8_t *)&d, offsetof(ModuleDescriptor, crc));
  PortSlot &s = slots[port - 1];
  s.ctx.selectBus();
  const uint8_t *p = (const uint8_t *)&d;
  for (size_t off = 0; off < sizeof(d); off += 8) {  // AT24C02: halaman 8 byte
    Wire.beginTransmission(EEPROM_ADDR);
    Wire.write((uint8_t)off);
    for (size_t j = off; j < off + 8 && j < sizeof(d); j++) Wire.write(p[j]);
    if (Wire.endTransmission() != 0) { deselectAll(); return false; }
    delay(6);
  }
  deselectAll();
  s.ctx.desc = d;
  s.ctx.hasEeprom = true;
  return true;
}

bool PortManager::writeCalibration(uint8_t port, JsonArrayConst cal, uint32_t epoch) {
  if (port < 1 || port > NUM_PORTS || !slots[port - 1].ctx.hasEeprom) return false;
  ModuleDescriptor d = slots[port - 1].ctx.desc;
  for (size_t i = 0; i < DESC_CAL_COUNT && i < cal.size(); i++) d.cal[i] = cal[i].as<float>();
  d.calEpoch = epoch;
  return writeDescriptor(port, d);
}

uint8_t PortManager::usedCount() {
  uint8_t n = 0;
  for (auto &s : slots)
    if (s.drv) n++;
  return n;
}
