// Mesin aturan lokal: dijalankan di hub, jadi otomasi tetap jalan walau
// internet putus. Aturan dikirim dari aplikasi (hasil "Asisten Sysnergi")
// dalam bentuk JSON lalu disimpan di flash. Contoh:
// [{"id":"r1","name":"Aerator saat oksigen rendah","en":true,
//   "if":{"ch":"p2.do","op":"<","val":4,"hyst":0.5},
//   "time":{"from":"00:00","to":"05:00"},      (opsional)
//   "then":{"relay":0},                        (opsional; tanpa ini = peringatan saja)
//   "maxMin":45, "fail":"on", "notify":true}]
#pragma once
#include <ArduinoJson.h>

namespace Rules {
void begin();                         // muat dari flash
bool replaceAll(JsonArrayConst arr);  // dari aplikasi; simpan ke flash
void evaluate();                      // panggil tiap RULE_PERIOD_MS
void stateJson(JsonArray arr);
bool anyAlertActive();  // ada aturan peringatan yang sedang aktif
}
