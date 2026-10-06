// Implementasi driver sensor bawaan. Untuk sensor baru:
//   1. Tambah kode jenis di enum ModuleType (sensor_driver.h)
//   2. Buat kelas turunan SensorDriver di file ini (atau file baru)
//   3. Daftarkan di createDriver() + typeName()
//   4. Tulis kode jenis itu ke EEPROM modul pakai tools/module_flasher
#include "sensor_driver.h"
#include "channels.h"
#include "config.h"
#include <Wire.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// ---------------- util ----------------
uint16_t crc16(const uint8_t *data, size_t len) {  // CRC-16/MODBUS
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (int b = 0; b < 8; b++) crc = (crc & 1) ? (crc >> 1) ^ 0xA001 : crc >> 1;
  }
  return crc;
}

static float cal(const PortContext &c, int i, float def) {
  if (!c.hasEeprom || isnan(c.desc.cal[i])) return def;
  return c.desc.cal[i];
}

static void put(const PortContext &c, const char *quantity, float v, const char *unit) {
  char key[16];
  snprintf(key, sizeof(key), "p%u.%s", c.port, quantity);
  Channels::set(key, v, unit);
}

static float readMilliVolts(uint8_t pin, int samples = 16) {
  uint32_t sum = 0;
  for (int i = 0; i < samples; i++) sum += analogReadMilliVolts(pin);
  return (float)sum / samples;
}

static bool i2cPresent(uint8_t addr) {
  Wire.beginTransmission(addr);
  return Wire.endTransmission() == 0;
}

// ---------------- DS18B20 (1-Wire di jalur D) ----------------
class DS18B20Driver : public SensorDriver {
  OneWire *ow = nullptr;
  DallasTemperature *dt = nullptr;
  uint8_t count = 0;
public:
  ~DS18B20Driver() { delete dt; delete ow; }
  const char *model() const override { return "DS18B20"; }
  bool begin(PortContext &c) override {
    ow = new OneWire(c.pinD);
    dt = new DallasTemperature(ow);
    dt->begin();
    dt->setWaitForConversion(false);  // non-blocking: baca hasil di siklus berikutnya
    count = dt->getDeviceCount();
    dt->requestTemperatures();
    return count > 0;
  }
  void sample(PortContext &c) override {
    float offset = cal(c, 0, 0);
    for (uint8_t i = 0; i < count && i < 4; i++) {
      float t = dt->getTempCByIndex(i);
      char q[8];
      snprintf(q, sizeof(q), i == 0 ? "temp" : "temp%u", i + 1);
      put(c, q, t == DEVICE_DISCONNECTED_C ? NAN : t + offset, "C");
    }
    dt->requestTemperatures();
  }
};

// ---------------- SHT3x (I2C) ----------------
class SHT3xDriver : public SensorDriver {
  uint8_t addr = 0x44;
public:
  const char *model() const override { return "SHT3x"; }
  bool begin(PortContext &c) override {
    c.selectBus();
    if (!i2cPresent(0x44)) addr = 0x45;
    return i2cPresent(addr);
  }
  void sample(PortContext &c) override {
    c.selectBus();
    Wire.beginTransmission(addr);
    Wire.write(0x24); Wire.write(0x00);  // single shot, high repeatability
    if (Wire.endTransmission() != 0) { put(c, "airtemp", NAN, "C"); return; }
    delay(16);
    uint8_t b[6];
    if (Wire.requestFrom(addr, (uint8_t)6) != 6) { put(c, "airtemp", NAN, "C"); return; }
    for (auto &x : b) x = Wire.read();
    put(c, "airtemp", -45.0f + 175.0f * ((b[0] << 8) | b[1]) / 65535.0f, "C");
    put(c, "hum", 100.0f * ((b[3] << 8) | b[4]) / 65535.0f, "%");
  }
};

// ---------------- BH1750 (I2C) ----------------
class BH1750Driver : public SensorDriver {
  uint8_t addr = 0x23;
public:
  const char *model() const override { return "BH1750"; }
  bool begin(PortContext &c) override {
    c.selectBus();
    if (!i2cPresent(0x23)) addr = 0x5C;
    Wire.beginTransmission(addr);
    Wire.write(0x10);  // continuous high-res
    return Wire.endTransmission() == 0;
  }
  void sample(PortContext &c) override {
    c.selectBus();
    if (Wire.requestFrom(addr, (uint8_t)2) != 2) { put(c, "lux", NAN, "lux"); return; }
    uint16_t raw = (Wire.read() << 8) | Wire.read();
    put(c, "lux", raw / 1.2f, "lux");
  }
};

// ---------------- Analog (pH, DO, tanah, MQ, generik) di jalur A ----------------
// Tabel kelarutan oksigen jenuh 0..40 °C (µg/L), dari DFRobot
static const uint16_t DO_TABLE[41] = {
  14460, 14220, 13820, 13440, 13090, 12740, 12420, 12110, 11810, 11530, 11260,
  11010, 10770, 10530, 10300, 10080, 9860, 9660, 9460, 9270, 9080, 8900, 8730,
  8570, 8410, 8250, 8110, 7960, 7820, 7690, 7560, 7430, 7300, 7180, 7070, 6950,
  6840, 6730, 6630, 6530, 6410};

class AnalogDriver : public SensorDriver {
  uint16_t type;
public:
  explicit AnalogDriver(uint16_t t) : type(t) {}
  const char *model() const override { return typeName(type); }
  bool begin(PortContext &c) override {
    pinMode(c.pinA, INPUT);
    return true;
  }
  void sample(PortContext &c) override {
    float mv = readMilliVolts(c.pinA);
    switch (type) {
      case MOD_PH_ANALOG: {  // pH = slope*mV + intercept (kalibrasi 2 titik: buffer 7 & 4)
        float ph = cal(c, 0, -0.005639f) * mv + cal(c, 1, 15.459f);
        put(c, "ph", constrain(ph, 0.0f, 14.0f), "pH");
        break;
      }
      case MOD_DO_ANALOG: {  // kalibrasi 1 titik di udara jenuh
        float vCal = cal(c, 0, 1600), tCal = cal(c, 1, 25);
        float t = 25;
        Channels::findFirstByQuantity("temp", t);  // kompensasi suhu dari sensor suhu air mana pun
        int ti = constrain((int)roundf(t), 0, 40);
        float vSat = vCal + 35.0f * (t - tCal);
        put(c, "do", mv * DO_TABLE[ti] / vSat / 1000.0f, "mg/L");
        break;
      }
      case MOD_SOIL_CAP: {  // map mV kering..basah → 0..100 %
        float dry = cal(c, 0, 2600), wet = cal(c, 1, 1100);
        put(c, "soil", constrain((dry - mv) * 100.0f / (dry - wet), 0.0f, 100.0f), "%");
        break;
      }
      case MOD_MQ137: {  // ppm = A * (Rs/R0)^B ; keluaran 5V dibagi resistor ke 3V3
        float rl = cal(c, 0, 10), r0 = cal(c, 1, 30), a = cal(c, 2, 102.2f), b = cal(c, 3, -2.473f);
        float ratio = cal(c, 4, 0.66f), vc = cal(c, 5, 5000);
        float v = mv / ratio;
        if (v < 1) { put(c, "nh3", NAN, "ppm"); break; }
        float rs = rl * (vc - v) / v;
        put(c, "nh3", a * powf(rs / r0, b), "ppm");
        break;
      }
      default:  // generik: y = a*mV + b
        put(c, "ain", cal(c, 0, 1) * mv + cal(c, 1, 0), "");
    }
  }
};

// ---------------- A02YYUW ultrasonik (UART RX di jalur D) ----------------
class LevelA02Driver : public SensorDriver {
  static bool claimed;  // hanya 1 UART bebas (UART1); UART2 dipakai RS485
  bool mine = false;
public:
  ~LevelA02Driver() { if (mine) { Serial1.end(); claimed = false; } }
  const char *model() const override { return "A02YYUW"; }
  bool begin(PortContext &c) override {
    if (claimed) return false;
    Serial1.begin(9600, SERIAL_8N1, c.pinD, -1);
    claimed = mine = true;
    return true;
  }
  void sample(PortContext &c) override {
    int dist = -1;
    uint8_t f[4];
    while (Serial1.available() >= 4) {  // ambil frame terbaru
      if (Serial1.read() != 0xFF) continue;
      f[0] = 0xFF;
      Serial1.readBytes(f + 1, 3);
      if (((f[0] + f[1] + f[2]) & 0xFF) == f[3]) dist = (f[1] << 8) | f[2];
    }
    if (dist < 0) { put(c, "level", NAN, "cm"); return; }
    float distCm = dist / 10.0f;
    put(c, "dist", distCm, "cm");
    put(c, "level", cal(c, 0, 150) - distCm, "cm");  // cal0 = tinggi sensor dari dasar
  }
};
bool LevelA02Driver::claimed = false;

// ---------------- Pabrik ----------------
SensorDriver *createDriver(uint16_t type) {
  switch (type) {
    case MOD_DS18B20:   return new DS18B20Driver();
    case MOD_SHT3X:     return new SHT3xDriver();
    case MOD_BH1750:    return new BH1750Driver();
    case MOD_PH_ANALOG:
    case MOD_DO_ANALOG:
    case MOD_SOIL_CAP:
    case MOD_MQ137:
    case MOD_ANALOG_LIN: return new AnalogDriver(type);
    case MOD_LEVEL_A02: return new LevelA02Driver();
    default:            return nullptr;
  }
}

const char *typeName(uint16_t type) {
  switch (type) {
    case MOD_DS18B20:    return "DS18B20";
    case MOD_SHT3X:      return "SHT3x";
    case MOD_BH1750:     return "BH1750";
    case MOD_PH_ANALOG:  return "pH";
    case MOD_DO_ANALOG:  return "DO";
    case MOD_SOIL_CAP:   return "Soil";
    case MOD_MQ137:      return "MQ137";
    case MOD_ANALOG_LIN: return "Analog";
    case MOD_LEVEL_A02:  return "A02YYUW";
    default:             return "?";
  }
}

uint16_t probeBareI2C() {
  if (i2cPresent(0x44) || i2cPresent(0x45)) return MOD_SHT3X;
  if (i2cPresent(0x23) || i2cPresent(0x5C)) return MOD_BH1750;
  return MOD_NONE;
}
