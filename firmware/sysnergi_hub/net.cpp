#include "net.h"
#include "config.h"
#include <WiFi.h>
#include <WiFiProv.h>
#include <Preferences.h>
#include <LittleFS.h>
#include <esp_mac.h>
#include "mqtt_client.h"
#include <Update.h>
#include "mbedtls/sha256.h"
#include <ArduinoJson.h>

static char sHwid[12], sDevId[20], sPop[12];
static char topicCmd[48];
static volatile Net::Link sLink = Net::Link::CONNECTING;
static volatile bool sStateReq = false;
static esp_mqtt_client_handle_t mqtt = nullptr;
static bool mqttStarted = false;
static QueueHandle_t cmdQueue;
static SemaphoreHandle_t bufMutex;
static String otaUrl, otaSha;
static size_t flushOffset = 0;

// UUID layanan BLE provisioning (sama dengan contoh Espressif, aplikasi memakai yang sama)
static uint8_t provUuid[16] = {0xb4, 0xdf, 0x5a, 0x1c, 0x3f, 0x6b, 0xf4, 0xbf,
                               0xea, 0x4a, 0x82, 0x03, 0x04, 0x90, 0x1a, 0x02};

Net::Link Net::link() { return sLink; }
const char *Net::hwid() { return sHwid; }
const char *Net::deviceId() { return sDevId; }
const char *Net::pop() { return sPop; }

static void topic(char *out, size_t n, const char *sub) {
  snprintf(out, n, "%s/%s/%s", TOPIC_ROOT, sDevId, sub);
}

// ---------------- buffer offline (LittleFS, format: sub \t payload) ----------------
static void bufferAppend(const char *sub, const String &payload) {
  xSemaphoreTake(bufMutex, portMAX_DELAY);
  File f = LittleFS.open(FILE_BUFFER, "a");
  if (f && f.size() < BUFFER_MAX_BYTES) {
    f.print(sub);
    f.print('\t');
    f.println(payload);
  }
  if (f) f.close();
  xSemaphoreGive(bufMutex);
}

static void bufferFlushSome() {
  if (!mqtt || esp_mqtt_client_get_outbox_size(mqtt) > 8192) return;
  xSemaphoreTake(bufMutex, portMAX_DELAY);
  File f = LittleFS.open(FILE_BUFFER, "r");
  if (f) {
    f.seek(flushOffset);
    for (int i = 0; i < 20 && f.available(); i++) {
      String line = f.readStringUntil('\n');
      int tab = line.indexOf('\t');
      if (tab > 0) {
        char t[64];
        topic(t, sizeof(t), line.substring(0, tab).c_str());
        String p = line.substring(tab + 1);
        p.trim();
        esp_mqtt_client_enqueue(mqtt, t, p.c_str(), p.length(), 1, 0, true);
      }
    }
    flushOffset = f.position();
    bool done = !f.available();
    f.close();
    if (done) {
      LittleFS.remove(FILE_BUFFER);
      flushOffset = 0;
    }
  }
  xSemaphoreGive(bufMutex);
}

// ---------------- MQTT ----------------
static void onMqtt(void *, esp_event_base_t, int32_t id, void *data) {
  auto ev = (esp_mqtt_event_handle_t)data;
  char t[64];
  switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED:
      sLink = Net::Link::CLOUD;
      esp_mqtt_client_subscribe(mqtt, topicCmd, 1);
      topic(t, sizeof(t), "online");
      esp_mqtt_client_publish(mqtt, t, "1", 1, 1, 1);
      sStateReq = true;
      Serial.println("[net] MQTT tersambung");
      break;
    case MQTT_EVENT_DISCONNECTED:
      if (sLink == Net::Link::CLOUD) sLink = Net::Link::WIFI_ONLY;
      break;
    case MQTT_EVENT_DATA:
      if (ev->current_data_offset == 0 && ev->data_len == ev->total_data_len &&
          ev->topic_len == (int)strlen(topicCmd) && !strncmp(ev->topic, topicCmd, ev->topic_len)) {
        char *msg = (char *)malloc(ev->data_len + 1);
        if (!msg) break;
        memcpy(msg, ev->data, ev->data_len);
        msg[ev->data_len] = 0;
        if (xQueueSend(cmdQueue, &msg, 0) != pdTRUE) free(msg);
      }
      break;
    default:
      break;
  }
}

static void startMqtt() {
  static char lwtTopic[64];
  topic(lwtTopic, sizeof(lwtTopic), "online");
  esp_mqtt_client_config_t cfg = {};
  cfg.broker.address.uri = MQTT_URI;
  cfg.credentials.client_id = sDevId;
  if (strlen(MQTT_USER)) {
    cfg.credentials.username = MQTT_USER;
    cfg.credentials.authentication.password = MQTT_PASS;
  }
  cfg.session.last_will.topic = lwtTopic;
  cfg.session.last_will.msg = "0";
  cfg.session.last_will.qos = 1;
  cfg.session.last_will.retain = 1;
  cfg.session.keepalive = 30;
  cfg.buffer.size = 4096;
  cfg.network.reconnect_timeout_ms = 5000;
  mqtt = esp_mqtt_client_init(&cfg);
  esp_mqtt_client_register_event(mqtt, MQTT_EVENT_ANY, onMqtt, nullptr);
  esp_mqtt_client_start(mqtt);
  mqttStarted = true;
}

// ---------------- Wi-Fi & provisioning ----------------
static void onSys(arduino_event_t *e) {
  switch (e->event_id) {
    case ARDUINO_EVENT_PROV_START:
      sLink = Net::Link::PROVISIONING;
      Serial.printf("[prov] mulai. Nama: %s  POP: %s\n", sHwid, sPop);
      break;
    case ARDUINO_EVENT_PROV_CRED_FAIL:
      Serial.println("[prov] gagal masuk Wi-Fi (sandi salah / AP tidak ditemukan)");
      break;
    case ARDUINO_EVENT_PROV_CRED_SUCCESS:
      sLink = Net::Link::CONNECTING;
      break;
    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
      Serial.printf("[net] IP %s\n", WiFi.localIP().toString().c_str());
      if (sLink != Net::Link::CLOUD) sLink = Net::Link::WIFI_ONLY;
      configTzTime("WIB-7", "pool.ntp.org", "time.google.com");
      if (!mqttStarted) startMqtt();
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
      if (sLink == Net::Link::CLOUD || sLink == Net::Link::WIFI_ONLY) sLink = Net::Link::CONNECTING;
      break;
    default:
      break;
  }
}

// OTA ringan: unduh biner lewat HTTP langsung ke partisi OTA cadangan, lalu
// cocokkan SHA-256 dengan nilai yang dikirim lewat perintah MQTT (kanal yang
// sudah terautentikasi). Gagal di tengah jalan = partisi lama tetap dipakai.
static bool parseUrl(const String &url, String &host, uint16_t &port, String &path) {
  if (!url.startsWith("http://")) return false;
  String rest = url.substring(7);
  int slash = rest.indexOf('/');
  String hp = slash < 0 ? rest : rest.substring(0, slash);
  path = slash < 0 ? "/" : rest.substring(slash);
  int colon = hp.indexOf(':');
  host = colon < 0 ? hp : hp.substring(0, colon);
  port = colon < 0 ? 80 : hp.substring(colon + 1).toInt();
  return host.length() > 0;
}

static String doOtaInner(const String &url, const String &sha256Hex) {
  String host, path;
  uint16_t port;
  if (!parseUrl(url, host, port, path)) return "URL harus http://host/path";
  if (sha256Hex.length() != 64) return "sha256 wajib diisi";
  WiFiClient c;
  c.setTimeout(15);
  if (!c.connect(host.c_str(), port)) return "server tidak terjangkau";
  c.printf("GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", path.c_str(), host.c_str());
  String status = c.readStringUntil('\n');
  if (status.indexOf(" 200") < 0) return "HTTP " + status;
  int len = -1;
  for (;;) {
    String h = c.readStringUntil('\n');
    h.trim();
    if (!h.length()) break;
    if (h.startsWith("Content-Length:") || h.startsWith("content-length:")) len = h.substring(15).toInt();
  }
  if (len <= 0) return "Content-Length tidak ada";
  if (!Update.begin(len)) return "partisi OTA terlalu kecil";
  mbedtls_sha256_context sha;
  mbedtls_sha256_init(&sha);
  mbedtls_sha256_starts(&sha, 0);
  uint8_t buf[1024];
  int got = 0;
  uint32_t lastData = millis();
  while (got < len && millis() - lastData < 15000) {
    int n = c.read(buf, sizeof(buf));
    if (n <= 0) { delay(5); continue; }
    lastData = millis();
    mbedtls_sha256_update(&sha, buf, n);
    if (Update.write(buf, n) != (size_t)n) { Update.abort(); return "gagal menulis flash"; }
    got += n;
  }
  uint8_t digest[32];
  mbedtls_sha256_finish(&sha, digest);
  mbedtls_sha256_free(&sha);
  if (got != len) { Update.abort(); return "unduhan terputus"; }
  char hex[65];
  for (int i = 0; i < 32; i++) sprintf(hex + 2 * i, "%02x", digest[i]);
  if (!sha256Hex.equalsIgnoreCase(hex)) { Update.abort(); return "SHA-256 tidak cocok"; }
  if (!Update.end(true)) return "verifikasi image gagal";
  return "";
}

static void doOta(const String &url, const String &sha) {
  Serial.printf("[ota] unduh %s\n", url.c_str());
  Net::event("info", "Pembaruan firmware dimulai");
  String err = doOtaInner(url, sha);
  if (!err.length()) {
    Net::event("info", "Firmware diperbarui, hub mulai ulang");
    delay(1500);
    ESP.restart();
  }
  Net::event("warn", "Pembaruan firmware gagal: " + err);
}

static void netTask(void *) {
  for (;;) {
    String u, h;
    xSemaphoreTake(bufMutex, portMAX_DELAY);
    u = otaUrl;
    h = otaSha;
    otaUrl = "";
    xSemaphoreGive(bufMutex);
    if (u.length()) doOta(u, h);
    if (sLink == Net::Link::CLOUD) bufferFlushSome();
    vTaskDelay(pdMS_TO_TICKS(1000));
  }
}

void Net::begin() {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  snprintf(sHwid, sizeof(sHwid), "SYN-%02X%02X", mac[4], mac[5]);
  snprintf(sDevId, sizeof(sDevId), "syn-%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  // POP prototipe diturunkan dari MAC. Produksi: acak per unit, simpan di NVS saat produksi.
  uint32_t h = 2166136261UL;
  for (uint8_t b : mac) h = (h ^ b) * 16777619UL;
  snprintf(sPop, sizeof(sPop), "%08lx", (unsigned long)h);
  snprintf(topicCmd, sizeof(topicCmd), "%s/%s/cmd", TOPIC_ROOT, sDevId);

  cmdQueue = xQueueCreate(8, sizeof(char *));
  bufMutex = xSemaphoreCreateMutex();

  Preferences prefs;
  prefs.begin("syn", false);
  ProvMode mode = (ProvMode)prefs.getUChar("prov", 0);
  prefs.putUChar("prov", 0);
  prefs.end();

  WiFi.onEvent(onSys);
  bool reset = mode != ProvMode::NONE;
  if (mode == ProvMode::SOFTAP) {
    // "Hotspot hub": HP tersambung ke AP bernama SYN-xxxx
    WiFiProv.beginProvision(NETWORK_PROV_SCHEME_SOFTAP, NETWORK_PROV_SCHEME_HANDLER_NONE,
                            NETWORK_PROV_SECURITY_1, sPop, sHwid, nullptr, nullptr, reset);
  } else {
    WiFiProv.beginProvision(NETWORK_PROV_SCHEME_BLE, NETWORK_PROV_SCHEME_HANDLER_FREE_BLE,
                            NETWORK_PROV_SECURITY_1, sPop, sHwid, nullptr, provUuid, reset);
  }
  xTaskCreatePinnedToCore(netTask, "net", 8192, nullptr, 1, nullptr, 0);
}

void Net::publish(const char *sub, const String &payload, bool bufferIfOffline, bool retain) {
  if (sLink == Link::CLOUD && mqtt) {
    char t[64];
    topic(t, sizeof(t), sub);
    esp_mqtt_client_enqueue(mqtt, t, payload.c_str(), payload.length(), 1, retain, true);
  } else if (bufferIfOffline) {
    bufferAppend(sub, payload);
  }
}

void Net::event(const char *level, const String &text, const char *ruleId) {
  Serial.printf("[event] %s: %s\n", level, text.c_str());
  JsonDocument doc;
  doc["ts"] = (uint32_t)time(nullptr);
  doc["level"] = level;
  doc["msg"] = text;
  if (ruleId) doc["rule"] = ruleId;
  String p;
  serializeJson(doc, p);
  publish("event", p, true);
}

bool Net::nextCommand(String &out) {
  char *msg;
  if (!cmdQueue || xQueueReceive(cmdQueue, &msg, 0) != pdTRUE) return false;
  out = msg;
  free(msg);
  return true;
}

bool Net::takeStateRequest() {
  if (!sStateReq) return false;
  sStateReq = false;
  return true;
}

void Net::startOta(const String &url, const String &sha256) {
  xSemaphoreTake(bufMutex, portMAX_DELAY);
  otaUrl = url;
  otaSha = sha256;
  xSemaphoreGive(bufMutex);
}

void Net::requestProvisioning(ProvMode m) {
  Preferences prefs;
  prefs.begin("syn", false);
  prefs.putUChar("prov", (uint8_t)m);
  prefs.end();
  delay(200);
  ESP.restart();
}

void Net::factoryReset() {
  LittleFS.format();
  requestProvisioning(ProvMode::BLE);  // sekalian hapus kredensial Wi-Fi
}
