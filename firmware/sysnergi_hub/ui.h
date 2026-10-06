// LED status RGB + tombol di casing.
//  LED: biru berkedip = siap disambungkan (provisioning) | biru kedip pelan = menyambung
//       kuning = jalan offline (aturan tetap aktif)      | hijau = online ke cloud
//       merah berkedip = ada peringatan bahaya
//  Tombol (tahan): 5 s = sambung ulang via Bluetooth | 10 s = mode hotspot hub
//                  20 s = reset pabrik. Tekan singkat = identifikasi (LED putih).
#pragma once
#include <Arduino.h>

namespace Ui {
void begin();
void tick();               // panggil tiap CONTROL_TICK_MS
void setAlert(bool on);
}
