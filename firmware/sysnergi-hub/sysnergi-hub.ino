// Sysnergi Hub — contoh firmware ESP32 untuk model data di docs/data-model.md
//
// Library (Arduino Library Manager):
//   - "Firebase Arduino Client Library for ESP8266 and ESP32" (mobizt) 4.4.x
//   - "ArduinoJson" 7.x
//
// Alur:
//   RTDB  stream  /hubs/{id}/down      ← config & perintah dari app (latensi < 1 s)
//   RTDB  set     /hubs/{id}/live      → status tiap 10 s
//   RTDB  set     /hubs/{id}/ack/{cmd} → hasil perintah
//   FS    patch   hubs/{id}/days/{d}   → rata-rata 5 menit
//   FS    patch   hubs/{id}/months/{m} → min/avg/max per jam
//   FS    create  sites/{s}/events/{id}-{ms} → alarm & otomasi (di-buffer saat offline)
//
// Otomasi dijalankan lokal dari config yang disimpan di flash: internet putus, aturan tetap jalan.
//
// Perintah Serial untuk uji tanpa app/BLE:
//   pair   → buat token klaim, cetak nonce (di produk dikirim lewat BLE)
//   reset  → reset pabrik (lepas dari akun)
//   status → cetak status

#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <time.h>
#include <math.h>
#include <ArduinoJson.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "config.h"
#include "hub_types.h"

// ═════════════════════════════ Model ═════════════════════════════

// Config (dari RTDB down/config, disimpan di flash)
String siteId;
int tzOffsetMin = 420;
bool portUsed[NPORT];
String portMetric[NPORT];
bool relayUsed[NRELAY];
Rule rules[MAX_RULES]; uint8_t nRules = 0;
Alarm alarms[MAX_ALARMS]; uint8_t nAlarms = 0;

// Runtime
float val[NPORT]; bool valOk[NPORT];
RelayState relays[NRELAY];
Event evq[EVQ_SIZE]; uint8_t evHead = 0, evCount = 0;
SlotRec slotq[SLOTQ_SIZE]; uint8_t slotHead = 0, slotCount = 0;
HourRec hourq[6]; uint8_t hourHead = 0, hourCount = 0;

double slotSum[NPORT]; uint16_t slotN[NPORT]; uint32_t slotStart = 0;
double hourSum[NPORT]; uint16_t hourN[NPORT]; float hourMin[NPORT], hourMax[NPORT]; uint32_t hourStart = 0;

FirebaseData stream, rt, fsd;   // fsd = Firestore
FirebaseAuth fbAuth;
FirebaseConfig fbConfig;
Preferences prefs;

volatile bool configDirty = true, cmdDirty = true;
bool claimed = false;
String claimNonce; uint32_t claimExp = 0;
uint32_t identifyUntil = 0;

const String HUB = HUB_ID;
const String P_DOWN = "/hubs/" + HUB + "/down";
const String P_LIVE = "/hubs/" + HUB + "/live";
const String P_META = "/hubs/" + HUB + "/meta";

// ═════════════════════════════ Waktu ═════════════════════════════

bool timeOk() { return time(nullptr) > 1700000000; }
uint32_t nowSec() { return (uint32_t)time(nullptr); }
uint64_t nowMs() { struct timeval tv; gettimeofday(&tv, nullptr); return (uint64_t)tv.tv_sec * 1000ULL + tv.tv_usec / 1000; }
uint32_t localSec(uint32_t epoch) { return epoch + tzOffsetMin * 60; }

String two(int n) { return n < 10 ? "0" + String(n) : String(n); }

String rfc3339(uint64_t ms) {
  time_t t = ms / 1000; struct tm g; gmtime_r(&t, &g);
  char b[32]; strftime(b, sizeof b, "%Y-%m-%dT%H:%M:%SZ", &g); return b;
}

// Kunci telemetri dari waktu lokal — sama persis dengan shared/src/paths.ts:telemetryKeys()
Keys keysFor(uint32_t localEpoch) {
  time_t t = localEpoch; struct tm g; gmtime_r(&t, &g);
  Keys k;
  String y = String(g.tm_year + 1900), mo = two(g.tm_mon + 1), d = two(g.tm_mday), h = two(g.tm_hour);
  k.dayId = y + mo + d; k.date = y + "-" + mo + "-" + d;
  k.slot = "t" + h + two((g.tm_min / 5) * 5);
  k.monthId = y + mo; k.month = y + "-" + mo; k.hourKey = "d" + d + "h" + h;
  return k;
}

// ═════════════════════════════ Sensor & relay (hardware) ═════════════════════════════

// TODO: ganti dengan driver modul sebenarnya (deteksi otomatis lewat ID resistor/I2C di tiap port).
const char* detectModule(int port) {
  static const char* demo[NPORT] = {"do", "water_temp", "ph", "nh3_water", "water_level", nullptr};
  return demo[port];
}

bool readSensor(int port, const String& metric, float& out) {
  // Simulasi agar alur data bisa diuji tanpa sensor.
  float t = millis() / 60000.0f;
  if (metric == "do")          out = 5.0f + 1.2f * sinf(t / 30) + random(-10, 10) / 100.0f;
  else if (metric == "water_temp") out = 28.4f + random(-5, 5) / 10.0f;
  else if (metric == "ph")     out = 7.2f + random(-5, 5) / 100.0f;
  else if (metric == "nh3_water") out = 0.02f + random(0, 3) / 100.0f;
  else if (metric == "water_level") out = 82 - fmodf(t, 20);
  else return false;
  return true;
}

bool calibrateSensor(int port, const String& step, float ref) {
  Serial.printf("[cal] P%d step=%s ref=%.2f\n", port + 1, step.c_str(), ref);
  return true;  // TODO: simpan offset/slope ke NVS per port
}

void applyRelay(int r) {
  bool level = relays[r].on == RELAY_ACTIVE_HIGH;
  digitalWrite(RELAY_PINS[r], level ? HIGH : LOW);
}

// ═════════════════════════════ Event queue ═════════════════════════════

void pushEvent(const char* type, uint8_t sev, int8_t ch = -1, float value = NAN, int8_t relay = -1, const char* ruleId = "") {
  uint8_t idx = (evHead + evCount) % EVQ_SIZE;
  if (evCount == EVQ_SIZE) { evHead = (evHead + 1) % EVQ_SIZE; evCount--; }  // buang yang paling lama
  Event& e = evq[idx];
  e.ms = nowMs(); strlcpy(e.type, type, sizeof e.type); e.severity = sev;
  e.ch = ch; e.value = value; e.relay = relay; strlcpy(e.ruleId, ruleId, sizeof e.ruleId);
  evCount++;
  Serial.printf("[event] %s sev=%d ch=%d v=%.2f relay=%d rule=%s\n", type, sev, ch, value, relay, ruleId);
}

const char* sevName(uint8_t s) { return s == 2 ? "danger" : s == 1 ? "warning" : "info"; }

bool flushOneEvent() {
  if (!evCount || siteId.isEmpty()) return true;
  Event& e = evq[evHead];
  String id = HUB + "-" + String((unsigned long long)e.ms);
  String path = "sites/" + siteId + "/events/" + id;

  FirebaseJson c;
  c.set("fields/ts/timestampValue", rfc3339(e.ms));
  c.set("fields/type/stringValue", e.type);
  c.set("fields/severity/stringValue", sevName(e.severity));
  c.set("fields/source/stringValue", "hub");
  c.set("fields/hubId/stringValue", HUB);
  if (e.ch >= 0) {
    c.set("fields/ch/stringValue", "P" + String(e.ch + 1));
    c.set("fields/metric/stringValue", portMetric[e.ch]);
  }
  if (!isnan(e.value)) c.set("fields/value/doubleValue", e.value);
  if (e.relay >= 0) c.set("fields/relay/stringValue", "R" + String(e.relay + 1));
  if (e.ruleId[0]) c.set("fields/ruleId/stringValue", e.ruleId);

  bool ok = Firebase.Firestore.createDocument(&fsd, FIREBASE_PROJECT_ID, "", path.c_str(), c.raw());
  if (!ok && fsd.errorReason().indexOf("ALREADY_EXISTS") >= 0) ok = true;  // retry setelah sukses parsial
  if (ok) { evHead = (evHead + 1) % EVQ_SIZE; evCount--; }
  else Serial.printf("[event] gagal: %s\n", fsd.errorReason().c_str());
  return ok;
}

// ═════════════════════════════ Telemetri ═════════════════════════════

void accumulate() {
  uint32_t now = nowSec();
  uint32_t loc = localSec(now);
  uint32_t slot = loc - loc % 300, hour = loc - loc % 3600;

  if (slotStart && slot != slotStart) {
    SlotRec r{slotStart, {}, 0};
    for (int p = 0; p < NPORT; p++) if (slotN[p]) { r.v[p] = slotSum[p] / slotN[p]; r.mask |= 1 << p; }
    if (r.mask) {
      if (slotCount == SLOTQ_SIZE) { slotHead = (slotHead + 1) % SLOTQ_SIZE; slotCount--; }
      slotq[(slotHead + slotCount++) % SLOTQ_SIZE] = r;
    }
    memset(slotSum, 0, sizeof slotSum); memset(slotN, 0, sizeof slotN);
  }
  if (hourStart && hour != hourStart) {
    HourRec r{hourStart, {}, {}, {}, 0};
    for (int p = 0; p < NPORT; p++) if (hourN[p]) {
      r.mn[p] = hourMin[p]; r.mx[p] = hourMax[p]; r.av[p] = hourSum[p] / hourN[p]; r.mask |= 1 << p;
    }
    if (r.mask) {
      if (hourCount == 6) { hourHead = (hourHead + 1) % 6; hourCount--; }
      hourq[(hourHead + hourCount++) % 6] = r;
    }
    memset(hourSum, 0, sizeof hourSum); memset(hourN, 0, sizeof hourN);
  }
  slotStart = slot; hourStart = hour;

  for (int p = 0; p < NPORT; p++) {
    if (!valOk[p]) continue;
    slotSum[p] += val[p]; slotN[p]++;
    if (!hourN[p] || val[p] < hourMin[p]) hourMin[p] = val[p];
    if (!hourN[p] || val[p] > hourMax[p]) hourMax[p] = val[p];
    hourSum[p] += val[p]; hourN[p]++;
  }
}

float round2(float v) { return roundf(v * 100) / 100; }

bool flushOneSlot() {
  if (!slotCount || siteId.isEmpty()) return true;
  SlotRec& r = slotq[slotHead];
  Keys k = keysFor(r.localEpoch);
  FirebaseJson c;
  c.set("fields/hubId/stringValue", HUB);
  c.set("fields/siteId/stringValue", siteId);
  c.set("fields/date/stringValue", k.date);
  c.set("fields/tzOffsetMin/integerValue", String(tzOffsetMin));
  for (int p = 0; p < NPORT; p++) if (r.mask & (1 << p))
    c.set("fields/s/mapValue/fields/" + k.slot + "/mapValue/fields/P" + String(p + 1) + "/doubleValue", round2(r.v[p]));
  String path = "hubs/" + HUB + "/days/" + k.dayId;
  String mask = "hubId,siteId,date,tzOffsetMin,s." + k.slot;
  bool ok = Firebase.Firestore.patchDocument(&fsd, FIREBASE_PROJECT_ID, "", path.c_str(), c.raw(), mask.c_str());
  if (ok) { slotHead = (slotHead + 1) % SLOTQ_SIZE; slotCount--; }
  else Serial.printf("[slot] gagal: %s\n", fsd.errorReason().c_str());
  return ok;
}

bool flushOneHour() {
  if (!hourCount || siteId.isEmpty()) return true;
  HourRec& r = hourq[hourHead];
  Keys k = keysFor(r.localEpoch);
  FirebaseJson c;
  c.set("fields/hubId/stringValue", HUB);
  c.set("fields/siteId/stringValue", siteId);
  c.set("fields/month/stringValue", k.month);
  c.set("fields/tzOffsetMin/integerValue", String(tzOffsetMin));
  for (int p = 0; p < NPORT; p++) if (r.mask & (1 << p)) {
    String base = "fields/h/mapValue/fields/" + k.hourKey + "/mapValue/fields/P" + String(p + 1) + "/arrayValue/values/";
    c.set(base + "[0]/doubleValue", round2(r.mn[p]));
    c.set(base + "[1]/doubleValue", round2(r.av[p]));
    c.set(base + "[2]/doubleValue", round2(r.mx[p]));
  }
  String path = "hubs/" + HUB + "/months/" + k.monthId;
  String mask = "hubId,siteId,month,tzOffsetMin,h." + k.hourKey;
  bool ok = Firebase.Firestore.patchDocument(&fsd, FIREBASE_PROJECT_ID, "", path.c_str(), c.raw(), mask.c_str());
  if (ok) { hourHead = (hourHead + 1) % 6; hourCount--; }
  return ok;
}

// ═════════════════════════════ Config ═════════════════════════════

int8_t portIdx(const char* s) { return (s && s[0] == 'P') ? atoi(s + 1) - 1 : -1; }
int8_t relayIdx(const char* s) { return (s && s[0] == 'R') ? atoi(s + 1) - 1 : -1; }
uint16_t hhmm(const char* s) { return s ? atoi(s) * 60 + atoi(s + 3) : 0; }
float numOr(JsonVariantConst v) { return v.isNull() ? NAN : v.as<float>(); }

Cond parseCond(JsonObjectConst o) {
  Cond c; c.ch = portIdx(o["ch"]); c.gt = strcmp(o["op"] | "lt", "gt") == 0; c.value = o["value"] | 0.0f; return c;
}

bool applyConfig(const String& json) {
  JsonDocument doc;
  if (deserializeJson(doc, json) || !doc["siteId"].is<const char*>()) return false;

  siteId = doc["siteId"].as<String>();
  tzOffsetMin = doc["tzOffsetMin"] | 420;

  for (int p = 0; p < NPORT; p++) {
    JsonObjectConst o = doc["ports"]["P" + String(p + 1)];
    portUsed[p] = !o.isNull(); portMetric[p] = portUsed[p] ? o["m"].as<String>() : "";
  }
  for (int r = 0; r < NRELAY; r++) relayUsed[r] = !doc["relays"]["R" + String(r + 1)].isNull();

  nAlarms = 0;
  for (JsonObjectConst a : doc["alarms"].as<JsonArrayConst>()) {
    if (nAlarms >= MAX_ALARMS) break;
    Alarm& al = alarms[nAlarms++];
    al = Alarm{portIdx(a["ch"]), numOr(a["warn"]["lt"]), numOr(a["warn"]["gt"]),
               numOr(a["danger"]["lt"]), numOr(a["danger"]["gt"]), 0, 0, 0};
  }

  nRules = 0;
  for (JsonObjectConst o : doc["rules"].as<JsonArrayConst>()) {
    if (nRules >= MAX_RULES) break;
    Rule& r = rules[nRules]; memset(&r, 0, sizeof r);
    strlcpy(r.id, o["id"] | "", sizeof r.id);
    JsonObjectConst t = o["trigger"], a = o["action"], s = o["safety"];
    if (strcmp(t["type"] | "", "schedule") == 0) {
      r.trig = TRIG_SCHEDULE; r.startMin = hhmm(t["start"]); r.endMin = t["end"].isNull() ? r.startMin + 1 : hhmm(t["end"]);
      r.daysMask = 0x7F;
      if (t["days"].is<JsonArrayConst>()) { r.daysMask = 0; for (int d : t["days"].as<JsonArrayConst>()) r.daysMask |= 1 << (d - 1); }
    } else {
      r.trig = TRIG_THRESHOLD; r.tc = parseCond(t); r.holdSec = t["holdSec"] | 0;
    }
    if (strcmp(a["type"] | "", "notify") == 0) {
      r.act = ACT_NOTIFY;
      const char* sv = a["severity"] | "info"; r.severity = !strcmp(sv, "danger") ? 2 : !strcmp(sv, "warning") ? 1 : 0;
    } else {
      r.act = ACT_RELAY; r.relay = relayIdx(a["relay"]); r.on = a["on"] | true; r.level = a["level"] | 0;
      JsonObjectConst u = a["until"];
      const char* ut = u["type"] | "trigger_clears";
      if (!strcmp(ut, "threshold")) { r.untilType = UNTIL_THRESHOLD; r.uc = parseCond(u); }
      else if (!strcmp(ut, "duration")) { r.untilType = UNTIL_DURATION; r.durSec = u["sec"] | 0; }
      else r.untilType = UNTIL_TRIGGER_CLEARS;
    }
    r.maxRunSec = s["maxRunSec"] | 0; r.cooldownSec = s["cooldownSec"] | 0;
    nRules++;
  }
  Serial.printf("[config] v%d site=%s rules=%d alarms=%d\n", (int)(doc["v"] | 0), siteId.c_str(), nRules, nAlarms);
  return true;
}

void loadConfigFromFlash() {
  String s = prefs.getString("config", "");
  if (s.length() && applyConfig(s)) Serial.println("[config] dimuat dari flash");
}

void fetchConfig() {
  configDirty = false;   // stream memberi tahu lagi bila ada perubahan / setelah reconnect
  if (!Firebase.RTDB.getJSON(&rt, P_DOWN + "/config")) return;
  String s = rt.jsonString();
  if (applyConfig(s)) prefs.putString("config", s);
}

// ═════════════════════════════ Otomasi ═════════════════════════════

bool condTrue(const Cond& c) {
  if (c.ch < 0 || !valOk[c.ch]) return false;
  return c.gt ? val[c.ch] > c.value : val[c.ch] < c.value;
}

bool inSchedule(const Rule& r, uint32_t loc) {
  time_t t = loc; struct tm g; gmtime_r(&t, &g);
  int dow = g.tm_wday == 0 ? 7 : g.tm_wday;   // 1=Senin..7=Minggu
  if (!(r.daysMask & (1 << (dow - 1)))) return false;
  uint16_t m = g.tm_hour * 60 + g.tm_min;
  return r.startMin <= r.endMin ? (m >= r.startMin && m < r.endMin) : (m >= r.startMin || m < r.endMin);
}

void stopRule(Rule& r, uint32_t now, const char* why) {
  r.active = false; r.condSince = 0;
  if (r.cooldownSec) r.cooldownUntil = now + r.cooldownSec;
  if (r.act == ACT_RELAY) pushEvent("automation_stop", strcmp(why, "safety") ? 0 : 1, -1, NAN, r.relay, r.id);
}

void tickRules() {
  if (!timeOk()) return;
  uint32_t now = nowSec(), loc = localSec(now);

  for (int i = 0; i < nRules; i++) {
    Rule& r = rules[i];
    bool trig = r.trig == TRIG_SCHEDULE ? inSchedule(r, loc) : condTrue(r.tc);

    if (!r.active) {
      if (!trig || now < r.cooldownUntil) { r.condSince = 0; continue; }
      if (!r.condSince) r.condSince = now;
      if (now - r.condSince < r.holdSec) continue;
      r.active = true; r.startedAt = now;
      if (r.act == ACT_NOTIFY) pushEvent("alarm", r.severity, r.tc.ch, r.tc.ch >= 0 ? val[r.tc.ch] : NAN, -1, r.id);
      else pushEvent("automation_start", 0, r.trig == TRIG_THRESHOLD ? r.tc.ch : -1,
                     r.trig == TRIG_THRESHOLD && r.tc.ch >= 0 ? val[r.tc.ch] : NAN, r.relay, r.id);
      continue;
    }

    if (r.maxRunSec && now - r.startedAt >= r.maxRunSec) { stopRule(r, now, "safety"); continue; }
    bool done =
      r.act == ACT_NOTIFY        ? !trig :
      r.untilType == UNTIL_THRESHOLD ? condTrue(r.uc) :
      r.untilType == UNTIL_DURATION  ? now - r.startedAt >= r.durSec :
      !trig;
    if (done) stopRule(r, now, "done");
  }

  // Arbitrase relay: override manual menang; selain itu aturan aktif (off menang atas on).
  for (int k = 0; k < NRELAY; k++) {
    RelayState& rs = relays[k];
    if (rs.manual && rs.manualUntil && now >= rs.manualUntil) rs.manual = false;
    bool want = rs.on; uint8_t lvl = rs.level; const char* by = "";
    if (!rs.manual) {
      bool anyOn = false, anyOff = false;
      for (int i = 0; i < nRules; i++) {
        Rule& r = rules[i];
        if (!r.active || r.act != ACT_RELAY || r.relay != k) continue;
        if (r.on) { anyOn = true; lvl = r.level; by = r.id; } else anyOff = true;
      }
      want = relayUsed[k] && anyOn && !anyOff;
    }
    if (want != rs.on || lvl != rs.level) {
      rs.on = want; rs.level = lvl; rs.since = now; strlcpy(rs.ruleId, by, sizeof rs.ruleId);
      applyRelay(k);
    }
  }
}

// Alarm ambang dengan hold & histeresis 3%
uint8_t levelFor(const Alarm& a, float v, uint8_t current) {
  auto past = [&](float th, bool gt, bool clearing) {
    if (isnan(th)) return false;
    float h = clearing ? fabsf(th) * 0.03f : 0;
    return gt ? v > th - h : v < th + h;
  };
  bool c = current > 0;
  if (past(a.dangerLt, false, current == 2 && c) || past(a.dangerGt, true, current == 2 && c)) return 2;
  if (past(a.warnLt, false, current >= 1 && c) || past(a.warnGt, true, current >= 1 && c)) return 1;
  return 0;
}

void tickAlarms() {
  uint32_t now = nowSec();
  for (int i = 0; i < nAlarms; i++) {
    Alarm& a = alarms[i];
    if (a.ch < 0 || !valOk[a.ch]) continue;
    uint8_t lv = levelFor(a, val[a.ch], a.level);
    if (lv == a.level) { a.pendingSince = 0; continue; }
    if (lv != a.pending || !a.pendingSince) { a.pending = lv; a.pendingSince = now; continue; }
    if (now - a.pendingSince < ALARM_HOLD_SEC) continue;
    if (lv > a.level) pushEvent("alarm", lv, a.ch, val[a.ch]);
    else if (lv == 0) pushEvent("alarm_clear", 0, a.ch, val[a.ch]);
    a.level = lv; a.pendingSince = 0;
  }
}

// ═════════════════════════════ Perintah ═════════════════════════════

void ack(const String& cmdId, bool ok, const char* code) {
  FirebaseJson j;
  j.set("ok", ok); j.set("ts/.sv", "timestamp"); if (code) j.set("code", code);
  Firebase.RTDB.setJSON(&rt, "/hubs/" + HUB + "/ack/" + cmdId, &j);
  Firebase.RTDB.deleteNode(&rt, P_DOWN + "/cmd/" + cmdId);
}

void runCommand(const String& id, JsonObjectConst c) {
  uint64_t ts = c["ts"] | 0ULL; uint32_t exp = c["expSec"] | 60;
  if (!ts || nowMs() - ts > (uint64_t)exp * 1000ULL) { ack(id, false, "expired"); return; }

  const char* type = c["type"] | "";
  JsonObjectConst a = c["args"];
  uint32_t now = nowSec();
  Serial.printf("[cmd] %s %s\n", id.c_str(), type);

  if (!strcmp(type, "relay") || !strcmp(type, "test_relay") || !strcmp(type, "relay_auto")) {
    int8_t r = relayIdx(a["relay"]);
    if (r < 0 || r >= NRELAY) { ack(id, false, "bad_relay"); return; }
    RelayState& rs = relays[r];
    if (!strcmp(type, "relay_auto")) rs.manual = false;
    else {
      bool on = !strcmp(type, "test_relay") ? true : (a["on"] | false);
      uint32_t dur = !strcmp(type, "test_relay") ? 3 : (a["durationSec"] | 0);
      rs.manual = true; rs.manualUntil = dur ? now + dur : 0;
      if (rs.on != on) { rs.on = on; rs.since = now; rs.ruleId[0] = 0; applyRelay(r); }
      rs.level = a["level"] | rs.level;
    }
    ack(id, true, nullptr);
  } else if (!strcmp(type, "calibrate")) {
    int8_t p = portIdx(a["port"]);
    ack(id, p >= 0 && calibrateSensor(p, a["step"] | "", a["ref"] | 0.0f), nullptr);
  } else if (!strcmp(type, "identify")) {
    identifyUntil = millis() + 10000; ack(id, true, nullptr);
  } else if (!strcmp(type, "restart")) {
    ack(id, true, nullptr); delay(500); ESP.restart();
  } else {
    ack(id, false, "unsupported");   // ota: belum diimplementasi di contoh ini
  }
}

void fetchCommands() {
  cmdDirty = false;
  if (!Firebase.RTDB.getJSON(&rt, P_DOWN + "/cmd")) return;
  JsonDocument doc;
  if (deserializeJson(doc, rt.jsonString())) return;
  for (JsonPairConst kv : doc.as<JsonObjectConst>()) runCommand(kv.key().c_str(), kv.value().as<JsonObjectConst>());
}

void onStream(FirebaseStream d) {
  String p = d.dataPath();
  if (p == "/" || p.startsWith("/config")) configDirty = true;
  if (p == "/" || p.startsWith("/cmd")) cmdDirty = true;
}
void onStreamTimeout(bool timeout) {
  if (timeout) Serial.println("[stream] timeout, menyambung ulang…");
}

// ═════════════════════════════ Live ═════════════════════════════

void writeLive() {
  FirebaseJson j;
  j.set("ts/.sv", "timestamp");
  j.set("rssi", WiFi.RSSI());
  j.set("power", "mains");
  j.set("uptimeS", (int)(millis() / 1000));
  j.set("fw", FW_VERSION);
  j.set("pendingEvents", evCount);
  for (int p = 0; p < NPORT; p++) {
    if (portUsed[p] && valOk[p]) j.set("ch/P" + String(p + 1) + "/v", round2(val[p]));
  }
  for (int r = 0; r < NRELAY; r++) {
    if (!relayUsed[r]) continue;
    String b = "relays/R" + String(r + 1) + "/";
    j.set(b + "on", relays[r].on);
    j.set(b + "mode", relays[r].manual ? "manual" : "auto");
    if (relays[r].since) j.set(b + "since", (double)relays[r].since * 1000.0);
    if (relays[r].ruleId[0]) j.set(b + "ruleId", relays[r].ruleId);
    if (relays[r].level) j.set(b + "level", relays[r].level);
  }
  if (!Firebase.RTDB.setJSON(&rt, P_LIVE, &j)) Serial.printf("[live] gagal: %s\n", rt.errorReason().c_str());
}

// ═════════════════════════════ Klaim & reset ═════════════════════════════

void startPairing() {
  uint8_t b[12]; esp_fill_random(b, sizeof b);
  claimNonce = ""; for (uint8_t x : b) { char h[3]; sprintf(h, "%02x", x); claimNonce += h; }
  uint64_t expMs = nowMs() + CLAIM_TTL_SEC * 1000ULL;
  claimExp = nowSec() + CLAIM_TTL_SEC;

  FirebaseJson j; j.set("nonce", claimNonce); j.set("exp", (double)expMs);
  Firebase.RTDB.setJSON(&rt, "/hubs/" + HUB + "/claim", &j);

  FirebaseJson c;
  c.set("fields/claim/mapValue/fields/nonce/stringValue", claimNonce);
  c.set("fields/claim/mapValue/fields/expiresAt/timestampValue", rfc3339(expMs));
  Firebase.Firestore.patchDocument(&fsd, FIREBASE_PROJECT_ID, "", ("hubs/" + HUB).c_str(), c.raw(), "claim");

  // Di produk: nonce dikirim ke app lewat karakteristik BLE terenkripsi.
  Serial.printf("[pair] nonce=%s (berlaku %d detik)\n", claimNonce.c_str(), CLAIM_TTL_SEC);
}

void checkClaimed() {
  if (!Firebase.RTDB.getString(&rt, P_META + "/ownerUid")) { claimed = false; return; }
  bool was = claimed; claimed = rt.stringData().length() > 0;
  if (claimed && !was && claimNonce.length()) {
    Firebase.RTDB.deleteNode(&rt, "/hubs/" + HUB + "/claim");
    claimNonce = ""; claimExp = 0;
    Serial.println("[pair] hub sudah diklaim");
  }
}

void factoryReset() {
  FirebaseJson j;
  j.set("meta/ownerUid"); j.set("meta/claimNonce"); j.set("meta/siteId");
  j.set("acl");   // set(path) tanpa nilai = null
  Firebase.RTDB.updateNode(&rt, "/hubs/" + HUB, &j);

  FirebaseJson c;
  c.set("fields/ownerUid/nullValue"); c.set("fields/siteId/nullValue");
  c.set("fields/claimNonce/nullValue"); c.set("fields/claim/nullValue");
  Firebase.Firestore.patchDocument(&fsd, FIREBASE_PROJECT_ID, "", ("hubs/" + HUB).c_str(), c.raw(),
                                   "ownerUid,siteId,claimNonce,claim");
  prefs.remove("config");
  Serial.println("[reset] selesai, restart…");
  delay(500); ESP.restart();
}

void reportIdentity() {
  FirebaseJson c;
  for (int p = 0; p < NPORT; p++) {
    const char* m = detectModule(p);
    String f = "fields/detected/mapValue/fields/P" + String(p + 1);
    if (m) c.set(f + "/stringValue", m); else c.set(f + "/nullValue");
  }
  c.set("fields/fw/mapValue/fields/version/stringValue", FW_VERSION);
  c.set("fields/fw/mapValue/fields/updatedAt/timestampValue", rfc3339(nowMs()));
  c.set("fields/connectivity/stringValue", "wifi");
  if (!Firebase.Firestore.patchDocument(&fsd, FIREBASE_PROJECT_ID, "", ("hubs/" + HUB).c_str(), c.raw(),
                                        "detected,fw,connectivity"))
    Serial.printf("[identity] gagal: %s\n", fsd.errorReason().c_str());
}

// ═════════════════════════════ Setup & loop ═════════════════════════════

void handleSerial() {
  if (!Serial.available()) return;
  String s = Serial.readStringUntil('\n'); s.trim();
  if (s == "pair") startPairing();
  else if (s == "reset") factoryReset();
  else if (s == "status") {
    Serial.printf("claimed=%d site=%s rules=%d events=%d slots=%d heap=%u\n",
                  claimed, siteId.c_str(), nRules, evCount, slotCount, ESP.getFreeHeap());
    for (int p = 0; p < NPORT; p++) if (portUsed[p]) Serial.printf("  P%d %s=%.2f\n", p + 1, portMetric[p].c_str(), val[p]);
    for (int r = 0; r < NRELAY; r++) if (relayUsed[r]) Serial.printf("  R%d %s %s\n", r + 1, relays[r].on ? "ON" : "off", relays[r].manual ? "manual" : "auto");
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(STATUS_LED, OUTPUT);
  for (int r = 0; r < NRELAY; r++) { pinMode(RELAY_PINS[r], OUTPUT); relays[r] = RelayState{}; applyRelay(r); }

  prefs.begin("sysnergi", false);
  loadConfigFromFlash();   // otomasi langsung jalan walau belum ada internet

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  configTime(0, 0, "pool.ntp.org", "time.google.com");

  fbConfig.api_key = FIREBASE_API_KEY;
  fbConfig.database_url = FIREBASE_DATABASE_URL;
  fbConfig.token_status_callback = tokenStatusCallback;
  fbAuth.user.email = HUB_EMAIL;
  fbAuth.user.password = HUB_PASSWORD;
  Firebase.reconnectNetwork(true);
  stream.keepAlive(5, 5, 1);
  Firebase.begin(&fbConfig, &fbAuth);
}

void loop() {
  static uint32_t tSample = 0, tLive = 0, tRule = 0, tClaim = 0, tFlush = 0;
  static bool streaming = false, identified = false;
  uint32_t ms = millis();

  handleSerial();

  if (ms - tSample >= SAMPLE_INTERVAL_MS) {
    tSample = ms;
    for (int p = 0; p < NPORT; p++) valOk[p] = portUsed[p] && readSensor(p, portMetric[p], val[p]);
    if (timeOk()) accumulate();
  }
  if (ms - tRule >= RULE_TICK_MS) { tRule = ms; tickRules(); tickAlarms(); }

  digitalWrite(STATUS_LED, ms < identifyUntil ? (ms / 150) % 2 : (WiFi.isConnected() ? HIGH : (ms / 1000) % 2));

  // ── Semua di bawah butuh internet ──
  if (!WiFi.isConnected() || !Firebase.ready() || !timeOk()) return;

  if (!streaming) {
    streaming = Firebase.RTDB.beginStream(&stream, P_DOWN);
    if (streaming) Firebase.RTDB.setStreamCallback(&stream, onStream, onStreamTimeout);
    else Serial.printf("[stream] gagal: %s\n", stream.errorReason().c_str());
  }
  if (!identified) { reportIdentity(); checkClaimed(); identified = true; }

  if (configDirty) fetchConfig();
  if (cmdDirty) fetchCommands();

  if (ms - tLive >= LIVE_INTERVAL_MS) { tLive = ms; writeLive(); }

  if (claimNonce.length() && ms - tClaim >= 3000) {
    tClaim = ms; checkClaimed();
    if (claimExp && nowSec() > claimExp) { claimNonce = ""; claimExp = 0; Serial.println("[pair] kedaluwarsa"); }
  }

  // Kirim antrean offline sedikit demi sedikit agar loop tetap responsif.
  if (ms - tFlush >= 500) {
    tFlush = ms;
    if (evCount) flushOneEvent();
    else if (slotCount) flushOneSlot();
    else if (hourCount) flushOneHour();
  }
}
