#include "ui.h"
#include "config.h"
#include "net.h"

static bool alert = false;
static uint32_t pressedAt = 0;
static bool wasPressed = false;
static uint32_t identifyUntil = 0;

static void led(uint8_t r, uint8_t g, uint8_t b) {
  static uint32_t last = 0xFFFFFFFF;
  uint32_t c = (r << 16) | (g << 8) | b;
  if (c == last) return;
  last = c;
  rgbLedWrite(PIN_STATUS_LED, r, g, b);
}

void Ui::begin() {
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  led(0, 0, 0);
}

void Ui::setAlert(bool on) { alert = on; }

void Ui::tick() {
  uint32_t now = millis();
  bool pressed = digitalRead(PIN_BUTTON) == LOW;

  // ---------- tombol ----------
  if (pressed && !wasPressed) pressedAt = now;
  uint32_t held = pressed ? now - pressedAt : 0;
  if (!pressed && wasPressed) {
    uint32_t dur = now - pressedAt;
    if (dur >= 20000) Net::factoryReset();
    else if (dur >= 10000) Net::requestProvisioning(Net::ProvMode::SOFTAP);
    else if (dur >= 5000) Net::requestProvisioning(Net::ProvMode::BLE);
    else if (dur > 50) {
      identifyUntil = now + 3000;
      Net::event("info", "Tombol hub ditekan");
    }
  }
  wasPressed = pressed;

  // ---------- LED ----------
  bool blinkFast = (now / 250) % 2, blinkSlow = (now % 1000) < 120;
  if (pressed && held >= 20000) return led(40, 0, 0);
  if (pressed && held >= 10000) return led(25, 0, 40);
  if (pressed && held >= 5000) return led(0, 0, 50);
  if (now < identifyUntil) return led(blinkFast ? 40 : 0, blinkFast ? 40 : 0, blinkFast ? 40 : 0);
  if (alert) return led(blinkFast ? 50 : 0, 0, 0);
  switch (Net::link()) {
    case Net::Link::PROVISIONING: return led(0, 0, blinkFast ? 50 : 0);
    case Net::Link::CONNECTING:   return led(0, 0, blinkSlow ? 40 : 0);
    case Net::Link::WIFI_ONLY:    return led(25, 15, 0);
    case Net::Link::CLOUD:        return led(0, 20, 0);
  }
}
