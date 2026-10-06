#include "modbus.h"
#include "channels.h"
#include "config.h"
#include "sensor_driver.h"
#include <LittleFS.h>

#define MAX_MB 8

struct MbPoint {
  uint8_t addr, fn;
  uint16_t reg;
  uint8_t n;
  char fmt[5];
  float scale;
  char key[10];
  char unit[8];
};

static MbPoint pts[MAX_MB];
static uint8_t nPts = 0;
static HardwareSerial &bus = Serial2;

static void parse(JsonArrayConst arr) {
  nPts = 0;
  for (JsonObjectConst o : arr) {
    if (nPts >= MAX_MB) break;
    MbPoint &p = pts[nPts++];
    p.addr = o["addr"] | 1;
    p.fn = o["fn"] | 3;
    p.reg = o["reg"] | 0;
    strlcpy(p.fmt, o["fmt"] | "u16", sizeof(p.fmt));
    p.n = (!strcmp(p.fmt, "u16") || !strcmp(p.fmt, "i16")) ? 1 : 2;
    p.scale = o["scale"] | 1.0f;
    strlcpy(p.key, o["key"] | "val", sizeof(p.key));
    strlcpy(p.unit, o["unit"] | "", sizeof(p.unit));
  }
}

void Modbus::begin() {
  pinMode(PIN_RS485_DE, OUTPUT);
  digitalWrite(PIN_RS485_DE, LOW);
  bus.begin(RS485_BAUD, SERIAL_8N1, PIN_RS485_RX, PIN_RS485_TX);
  File f = LittleFS.open(FILE_MODBUS, "r");
  if (!f) return;
  JsonDocument doc;
  if (deserializeJson(doc, f) == DeserializationError::Ok) parse(doc.as<JsonArrayConst>());
  f.close();
}

bool Modbus::configure(JsonArrayConst arr) {
  File f = LittleFS.open(FILE_MODBUS, "w");
  if (!f) return false;
  serializeJson(arr, f);
  f.close();
  parse(arr);
  return true;
}

static bool readRegs(uint8_t addr, uint8_t fn, uint16_t reg, uint8_t n, uint16_t *out) {
  uint8_t req[8] = {addr, fn, (uint8_t)(reg >> 8), (uint8_t)reg, 0, n};
  uint16_t crc = crc16(req, 6);
  req[6] = crc & 0xFF;
  req[7] = crc >> 8;
  while (bus.available()) bus.read();
  digitalWrite(PIN_RS485_DE, HIGH);
  bus.write(req, 8);
  bus.flush();
  digitalWrite(PIN_RS485_DE, LOW);

  uint8_t resp[5 + 2 * 4];
  size_t want = 5 + 2 * n;
  bus.setTimeout(200);
  if (bus.readBytes(resp, want) != want) return false;
  if (resp[0] != addr || resp[1] != fn || resp[2] != 2 * n) return false;
  uint16_t rc = crc16(resp, want - 2);
  if (resp[want - 2] != (rc & 0xFF) || resp[want - 1] != (rc >> 8)) return false;
  for (uint8_t i = 0; i < n; i++) out[i] = (resp[3 + 2 * i] << 8) | resp[4 + 2 * i];
  return true;
}

void Modbus::pollAll() {
  for (uint8_t i = 0; i < nPts; i++) {
    MbPoint &p = pts[i];
    uint16_t r[2];
    float v = NAN;
    if (readRegs(p.addr, p.fn, p.reg, p.n, r)) {
      if (!strcmp(p.fmt, "i16")) v = (int16_t)r[0];
      else if (!strcmp(p.fmt, "u16")) v = r[0];
      else if (!strcmp(p.fmt, "i32")) v = (int32_t)(((uint32_t)r[0] << 16) | r[1]);
      else {
        uint32_t raw = !strcmp(p.fmt, "f32s") ? ((uint32_t)r[1] << 16) | r[0] : ((uint32_t)r[0] << 16) | r[1];
        memcpy(&v, &raw, 4);
      }
      v *= p.scale;
    }
    char key[16];
    snprintf(key, sizeof(key), "rs%u.%s", p.addr, p.key);
    Channels::set(key, v, p.unit);
    delay(20);  // jeda antar-frame Modbus
  }
}

uint8_t Modbus::count() { return nPts; }
