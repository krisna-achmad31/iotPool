#include "channels.h"
#include "config.h"

static Channel table[MAX_CHANNELS];

static Channel *find(const char *key) {
  for (auto &c : table)
    if (c.used && strcmp(c.key, key) == 0) return &c;
  return nullptr;
}

void Channels::set(const char *key, float value, const char *unit) {
  Channel *c = find(key);
  if (!c) {
    for (auto &slot : table)
      if (!slot.used) { c = &slot; break; }
    if (!c) return;  // tabel penuh
    c->used = true;
    strlcpy(c->key, key, sizeof(c->key));
  }
  strlcpy(c->unit, unit ? unit : "", sizeof(c->unit));
  c->value = value;
  c->ts = millis();
}

bool Channels::get(const char *key, float &out) {
  Channel *c = find(key);
  if (!c || isnan(c->value) || millis() - c->ts > SENSOR_STALE_MS) return false;
  out = c->value;
  return true;
}

bool Channels::findFirstByQuantity(const char *quantity, float &out) {
  for (auto &c : table) {
    if (!c.used || isnan(c.value) || millis() - c.ts > SENSOR_STALE_MS) continue;
    const char *dot = strchr(c.key, '.');
    if (dot && strcmp(dot + 1, quantity) == 0) { out = c.value; return true; }
  }
  return false;
}

void Channels::removePrefix(const char *prefix) {
  size_t n = strlen(prefix);
  for (auto &c : table)
    if (c.used && strncmp(c.key, prefix, n) == 0) c.used = false;
}

void Channels::toJson(JsonObject obj) {
  for (auto &c : table) {
    if (!c.used || isnan(c.value) || millis() - c.ts > SENSOR_STALE_MS) continue;
    obj[c.key] = serialized(String(c.value, 2));
  }
}
