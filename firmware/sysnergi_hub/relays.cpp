#include "relays.h"
#include "config.h"
#include "net.h"

struct RelayState {
  bool on = false;
  RelaySource src = RelaySource::NONE;
  uint32_t onSince = 0, offSince = 0, maxRunMs = 0, manualUntil = 0;
  bool lockout = false;  // batas aman tercapai; tunggu aturan melepas dulu
};

static RelayState st[NUM_RELAYS];

static void drive(uint8_t i, bool on) {
  digitalWrite(RELAY_PIN[i], (on ^ RELAY_ACTIVE_LOW) ? HIGH : LOW);
  if (st[i].on == on) return;
  st[i].on = on;
  if (on) st[i].onSince = millis();
  else st[i].offSince = millis();
}

void Relays::begin() {
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    // set level "mati" dulu sebelum jadi OUTPUT agar relay tidak klik saat boot
    digitalWrite(RELAY_PIN[i], RELAY_ACTIVE_LOW ? HIGH : LOW);
    pinMode(RELAY_PIN[i], OUTPUT);
    st[i].offSince = millis() - RELAY_MIN_OFF_MS;
  }
}

void Relays::ruleRequest(uint8_t i, bool on, uint32_t maxRunMs) {
  if (i >= NUM_RELAYS) return;
  RelayState &r = st[i];
  if (r.src == RelaySource::MANUAL || r.src == RelaySource::TEST) return;
  if (!on) {
    r.lockout = false;
    if (r.on) drive(i, false);
    r.src = RelaySource::NONE;
    return;
  }
  if (r.on || r.lockout) return;
  if (millis() - r.offSince < RELAY_MIN_OFF_MS) return;  // jeda motor belum cukup
  r.src = RelaySource::RULE;
  r.maxRunMs = maxRunMs;
  drive(i, true);
}

void Relays::manual(uint8_t i, bool on, uint32_t durationMs) {
  if (i >= NUM_RELAYS) return;
  RelayState &r = st[i];
  r.src = RelaySource::MANUAL;
  r.manualUntil = durationMs ? millis() + durationMs : 0;
  r.lockout = false;
  drive(i, on);
}

void Relays::releaseManual(uint8_t i) {
  if (i >= NUM_RELAYS || st[i].src != RelaySource::MANUAL) return;
  st[i].src = RelaySource::NONE;
  drive(i, false);  // aturan akan menyalakan lagi bila memang perlu
}

void Relays::tick() {
  uint32_t now = millis();
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    RelayState &r = st[i];
    if (r.src == RelaySource::MANUAL && r.manualUntil && (int32_t)(now - r.manualUntil) >= 0)
      releaseManual(i);
    if (r.src == RelaySource::RULE && r.on && r.maxRunMs && now - r.onSince > r.maxRunMs) {
      drive(i, false);
      r.lockout = true;
      r.src = RelaySource::NONE;
      Net::event("warn", "Relay R" + String(i + 1) + " dimatikan: batas aman waktu nyala tercapai");
    }
  }
}

bool Relays::isOn(uint8_t i) { return i < NUM_RELAYS && st[i].on; }

void Relays::stateJson(JsonArray arr) {
  static const char *srcName[] = {"none", "rule", "manual", "test"};
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    JsonObject o = arr.add<JsonObject>();
    o["on"] = st[i].on;
    o["src"] = srcName[(int)st[i].src];
    if (st[i].on) o["sec"] = (millis() - st[i].onSince) / 1000;
    if (st[i].lockout) o["lockout"] = true;
  }
}

void Relays::runTest() {
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    bool was = st[i].on;
    RelaySource prev = st[i].src;
    st[i].src = RelaySource::TEST;
    drive(i, !was); delay(700);
    drive(i, was);  delay(300);
    st[i].src = prev;
  }
}
