// =====================================================================
//  SYSNERGI HUB — firmware hub IoT modular untuk kolam, kebun, kandang
//  MCU   : ESP32-WROOM-32 DevKit ("ESP32 V3"), Arduino core esp32 3.x
//  Arsitektur:
//    core 1 (loop)  : sensor -> tabel kanal -> aturan -> relay  (kontrol, selalu jalan)
//    core 0 (net)   : provisioning, Wi-Fi, MQTT, buffer offline, OTA
//  Perintah bisa dikirim lewat MQTT (topik .../cmd) ATAU Serial Monitor
//  (ketik JSON satu baris, mis. {"cmd":"relay","idx":0,"on":true,"min":5})
// =====================================================================
#include "config.h"
#include "channels.h"
#include "port_manager.h"
#include "relays.h"
#include "rules.h"
#include "modbus.h"
#include "net.h"
#include "ui.h"
#include <WiFi.h>
#include <Wire.h>
#include <LittleFS.h>
#include <sys/time.h>

static bool hasMux = false;
static bool rtcSynced = false;

// ---------------- RTC DS3231: jam tetap benar walau tanpa internet ----------------
static uint8_t bcd2dec(uint8_t v) { return (v >> 4) * 10 + (v & 0x0F); }
static uint8_t dec2bcd(uint8_t v) { return ((v / 10) << 4) | (v % 10); }

static void rtcLoadSystemTime() {
  Wire.beginTransmission(RTC_ADDR);
  Wire.write(0);
  if (Wire.endTransmission() != 0 || Wire.requestFrom((uint8_t)RTC_ADDR, (uint8_t)7) != 7) return;
  struct tm t = {};
  t.tm_sec = bcd2dec(Wire.read() & 0x7F);
  t.tm_min = bcd2dec(Wire.read());
  t.tm_hour = bcd2dec(Wire.read() & 0x3F);
  Wire.read();
  t.tm_mday = bcd2dec(Wire.read());
  t.tm_mon = bcd2dec(Wire.read() & 0x1F) - 1;
  t.tm_year = bcd2dec(Wire.read()) + 100;
  setenv("TZ", "UTC0", 1); tzset();
  time_t epoch = mktime(&t);  // RTC menyimpan UTC
  setenv("TZ", "WIB-7", 1); tzset();
  if (epoch > 1700000000) {
    struct timeval tv = {epoch, 0};
    settimeofday(&tv, nullptr);
    Serial.println("[rtc] jam diambil dari DS3231");
  }
}

static void rtcSaveSystemTime() {
  time_t now = time(nullptr);
  struct tm t;
  gmtime_r(&now, &t);
  Wire.beginTransmission(RTC_ADDR);
  Wire.write(0);
  uint8_t v[7] = {dec2bcd(t.tm_sec), dec2bcd(t.tm_min), dec2bcd(t.tm_hour), (uint8_t)(t.tm_wday + 1),
                  dec2bcd(t.tm_mday), dec2bcd(t.tm_mon + 1), dec2bcd(t.tm_year - 100)};
  Wire.write(v, 7);
  Wire.endTransmission();
}

// ---------------- telemetri & status ----------------
static void publishTelemetry() {
  JsonDocument doc;
  doc["ts"] = (uint32_t)time(nullptr);
  doc["up"] = millis() / 1000;
  if (WiFi.isConnected()) doc["rssi"] = WiFi.RSSI();
  Channels::toJson(doc["ch"].to<JsonObject>());
  JsonArray r = doc["relay"].to<JsonArray>();
  for (uint8_t i = 0; i < NUM_RELAYS; i++) r.add(Relays::isOn(i) ? 1 : 0);
  String s;
  serializeJson(doc, s);
  Serial.println(s);
  static uint32_t n = 0;
  bool keep = Net::link() == Net::Link::CLOUD || (n++ % OFFLINE_BUFFER_EVERY) == 0;
  Net::publish("telemetry", s, keep);
}

static void publishState() {
  JsonDocument doc;
  doc["fw"] = FW_VERSION;
  doc["hwid"] = Net::hwid();
  doc["mux"] = hasMux;
  doc["heap"] = ESP.getFreeHeap();
  PortManager::infoJson(doc["ports"].to<JsonArray>());
  Relays::stateJson(doc["relays"].to<JsonArray>());
  Rules::stateJson(doc["rules"].to<JsonArray>());
  doc["modbus"] = Modbus::count();
  String s;
  serializeJson(doc, s);
  Net::publish("state", s, false, true);
}

static void ack(const char *cmd, bool ok) {
  String s = String("{\"cmd\":\"") + cmd + "\",\"ok\":" + (ok ? "true" : "false") + "}";
  Serial.println(s);
  Net::publish("ack", s, false);
}

// ---------------- perintah dari aplikasi / Serial ----------------
static void handleCommand(const String &json) {
  JsonDocument doc;
  if (deserializeJson(doc, json) != DeserializationError::Ok) return ack("parse", false);
  const char *cmd = doc["cmd"] | "";
  bool ok = true;

  if (!strcmp(cmd, "relay")) {  // {"cmd":"relay","idx":0,"on":true,"min":10}
    Relays::manual(doc["idx"] | 0, doc["on"] | false, (doc["min"] | 0) * 60000UL);
  } else if (!strcmp(cmd, "relay_auto")) {  // kembalikan relay ke kendali aturan
    Relays::releaseManual(doc["idx"] | 0);
  } else if (!strcmp(cmd, "rules")) {
    ok = Rules::replaceAll(doc["rules"].as<JsonArrayConst>());
  } else if (!strcmp(cmd, "ports")) {  // {"cmd":"ports","map":{"3":513}}
    PortManager::setManualMap(doc["map"].as<JsonObjectConst>());
  } else if (!strcmp(cmd, "modbus")) {
    ok = Modbus::configure(doc["list"].as<JsonArrayConst>());
  } else if (!strcmp(cmd, "calibrate")) {  // {"cmd":"calibrate","port":3,"cal":[-0.0056,15.4]}
    ok = PortManager::writeCalibration(doc["port"] | 0, doc["cal"].as<JsonArrayConst>(),
                                       doc["epoch"] | (uint32_t)time(nullptr));
  } else if (!strcmp(cmd, "module_write")) {  // program EEPROM ID modul baru dari aplikasi/serial
    ModuleDescriptor d = {};
    d.type = doc["type"] | 0;
    d.hwRev = doc["rev"] | 1;
    d.serial = doc["serial"] | (uint32_t)esp_random();
    strlcpy(d.name, doc["name"] | typeName(d.type), sizeof(d.name));
    for (int i = 0; i < DESC_CAL_COUNT; i++) d.cal[i] = NAN;  // NAN = pakai nilai bawaan driver
    JsonArrayConst cal = doc["cal"];
    for (size_t i = 0; i < DESC_CAL_COUNT && i < cal.size(); i++) d.cal[i] = cal[i];
    d.calEpoch = (uint32_t)time(nullptr);
    ok = PortManager::writeDescriptor(doc["port"] | 0, d);
  } else if (!strcmp(cmd, "rescan")) {
    PortManager::scan();
  } else if (!strcmp(cmd, "relay_test")) {
    Relays::runTest();
  } else if (!strcmp(cmd, "ota")) {  // {"cmd":"ota","url":"http://.../fw.bin","sha256":"..."}
    Net::startOta(doc["url"] | "", doc["sha256"] | "");
  } else if (!strcmp(cmd, "state")) {
  } else if (!strcmp(cmd, "reboot")) {
    ack(cmd, true);
    delay(300);
    ESP.restart();
  } else {
    ok = false;
  }
  ack(cmd, ok);
  publishState();
}

static void readSerialCommand() {
  static String line;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (line.length()) handleCommand(line);
      line = "";
    } else if (line.length() < 1024) {
      line += c;
    }
  }
}

// ---------------- setup & loop ----------------
void setup() {
  Relays::begin();  // paling awal: pastikan semua relay MATI
  Serial.begin(115200);
  Serial.printf("\n=== Sysnergi Hub fw %s ===\n", FW_VERSION);
  Ui::begin();
  if (!LittleFS.begin(true)) Serial.println("[fs] LittleFS gagal");

  hasMux = PortManager::begin();
  if (!hasMux) Serial.println("[port] TCA9548A tidak terdeteksi! cek kabel SDA/SCL");
  setenv("TZ", "WIB-7", 1); tzset();
  rtcLoadSystemTime();

  Rules::begin();
  Modbus::begin();
  Net::begin();
  Serial.printf("[net] HWID %s  ID %s  POP %s\n", Net::hwid(), Net::deviceId(), Net::pop());

  PortManager::scan();
  enableLoopWDT();  // reset otomatis bila loop kontrol macet > 5 detik
}

void loop() {
  static uint32_t tSensor = 0, tRule = 0, tScan = 0, tTele = 0;
  uint32_t now = millis();

  Ui::tick();
  Relays::tick();
  readSerialCommand();
  String cmd;
  while (Net::nextCommand(cmd)) handleCommand(cmd);
  if (Net::takeStateRequest()) publishState();

  if (now - tSensor >= SENSOR_PERIOD_MS) {
    tSensor = now;
    PortManager::sampleAll();
    Modbus::pollAll();
  }
  if (now - tRule >= RULE_PERIOD_MS) {
    tRule = now;
    Rules::evaluate();
    Ui::setAlert(Rules::anyAlertActive());
    if (!rtcSynced && Net::link() == Net::Link::CLOUD && time(nullptr) > 1700000000) {
      rtcSaveSystemTime();  // jam NTP -> RTC
      rtcSynced = true;
    }
  }
  if (now - tScan >= PORT_SCAN_PERIOD_MS) {
    tScan = now;
    PortManager::scan();  // hot-plug modul
  }
  if (now - tTele >= TELEMETRY_PERIOD_MS) {
    tTele = now;
    publishTelemetry();
  }
  delay(CONTROL_TICK_MS);
}
