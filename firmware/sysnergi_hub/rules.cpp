#include "rules.h"
#include "channels.h"
#include "config.h"
#include "net.h"
#include "relays.h"
#include <LittleFS.h>
#include <time.h>

#define MAX_RULES 16

enum class Fail : uint8_t { HOLD, ON, OFF };

struct Rule {
  char id[12];
  char name[40];
  bool enabled;
  bool hasCond;
  char ch[16];
  char op;  // '<' atau '>'
  float val, hyst;
  int16_t fromMin, toMin;  // -1 = tanpa jendela waktu
  int8_t relay;            // -1 = peringatan saja
  uint32_t maxRunMs;
  Fail fail;
  bool notify;
  bool active;             // keadaan saat ini
};

static Rule rules[MAX_RULES];
static uint8_t ruleCount = 0;

static int16_t parseHHMM(const char *s) {
  if (!s) return -1;
  int h, m;
  return sscanf(s, "%d:%d", &h, &m) == 2 ? h * 60 + m : -1;
}

static bool parse(JsonArrayConst arr) {
  ruleCount = 0;
  for (JsonObjectConst o : arr) {
    if (ruleCount >= MAX_RULES) break;
    Rule &r = rules[ruleCount];
    memset(&r, 0, sizeof(r));
    strlcpy(r.id, o["id"] | "", sizeof(r.id));
    strlcpy(r.name, o["name"] | "Aturan", sizeof(r.name));
    r.enabled = o["en"] | true;
    JsonObjectConst c = o["if"];
    r.hasCond = !c.isNull();
    if (r.hasCond) {
      strlcpy(r.ch, c["ch"] | "", sizeof(r.ch));
      r.op = (c["op"] | "<")[0];
      r.val = c["val"] | 0.0f;
      r.hyst = c["hyst"] | 0.0f;
    }
    r.fromMin = parseHHMM(o["time"]["from"].as<const char *>());
    r.toMin = parseHHMM(o["time"]["to"].as<const char *>());
    r.relay = o["then"]["relay"] | -1;
    r.maxRunMs = (o["maxMin"] | 0) * 60000UL;
    const char *f = o["fail"] | "hold";
    r.fail = !strcmp(f, "on") ? Fail::ON : !strcmp(f, "off") ? Fail::OFF : Fail::HOLD;
    r.notify = o["notify"] | false;
    ruleCount++;
  }
  return true;
}

void Rules::begin() {
  File f = LittleFS.open(FILE_RULES, "r");
  if (!f) return;
  JsonDocument doc;
  if (deserializeJson(doc, f) == DeserializationError::Ok) parse(doc.as<JsonArrayConst>());
  f.close();
  Serial.printf("[rules] %u aturan dimuat\n", ruleCount);
}

bool Rules::replaceAll(JsonArrayConst arr) {
  File f = LittleFS.open(FILE_RULES, "w");
  if (!f) return false;
  serializeJson(arr, f);
  f.close();
  // matikan relay milik aturan lama sebelum aturan baru berlaku
  for (uint8_t i = 0; i < ruleCount; i++)
    if (rules[i].relay >= 0) Relays::ruleRequest(rules[i].relay, false, 0);
  return parse(arr);
}

static bool inWindow(const Rule &r, bool &known) {
  known = true;
  if (r.fromMin < 0 || r.toMin < 0) return true;
  time_t now = time(nullptr);
  if (now < 1700000000) { known = false; return false; }  // jam belum valid
  struct tm t;
  localtime_r(&now, &t);
  int m = t.tm_hour * 60 + t.tm_min;
  return r.fromMin <= r.toMin ? (m >= r.fromMin && m < r.toMin)
                              : (m >= r.fromMin || m < r.toMin);  // lewat tengah malam
}

void Rules::evaluate() {
  bool want[NUM_RELAYS] = {};
  bool owned[NUM_RELAYS] = {};
  uint32_t maxRun[NUM_RELAYS] = {};

  for (uint8_t i = 0; i < ruleCount; i++) {
    Rule &r = rules[i];
    bool next = false;
    if (r.enabled) {
      bool known;
      bool timeOk = inWindow(r, known);
      if (!r.hasCond) {
        next = timeOk;
      } else {
        float v;
        if (!Channels::get(r.ch, v)) {
          next = r.fail == Fail::ON ? true : r.fail == Fail::OFF ? false : r.active;
        } else if (r.op == '<') {
          next = r.active ? v < r.val + r.hyst : v < r.val;  // histeresis
        } else {
          next = r.active ? v > r.val - r.hyst : v > r.val;
        }
        next = next && timeOk;
      }
      if (next && !r.active && r.notify) {
        float v = NAN;
        Channels::get(r.ch, v);
        Net::event("alert", String(r.name) + (isnan(v) ? "" : " (" + String(v, 2) + ")"), r.id);
      }
    }
    r.active = next;
    if (r.relay >= 0 && r.relay < NUM_RELAYS) {
      owned[r.relay] = true;
      if (next) {
        want[r.relay] = true;  // beberapa aturan ke relay yang sama = OR
        if (r.maxRunMs && (!maxRun[r.relay] || r.maxRunMs < maxRun[r.relay])) maxRun[r.relay] = r.maxRunMs;
      }
    }
  }
  for (uint8_t i = 0; i < NUM_RELAYS; i++)
    if (owned[i]) Relays::ruleRequest(i, want[i], maxRun[i]);
}

void Rules::stateJson(JsonArray arr) {
  for (uint8_t i = 0; i < ruleCount; i++) {
    JsonObject o = arr.add<JsonObject>();
    o["id"] = rules[i].id;
    o["active"] = rules[i].active;
  }
}

bool Rules::anyAlertActive() {
  for (uint8_t i = 0; i < ruleCount; i++)
    if (rules[i].active && rules[i].notify) return true;
  return false;
}
