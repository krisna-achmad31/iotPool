// Sensor industri RS485 (Modbus RTU). Tidak memakai Smart Port; semua sensor
// diparalel di satu bus A/B. Jenis sensor cukup didefinisikan lewat JSON
// dari aplikasi, tanpa ubah firmware:
// [{"addr":1,"fn":3,"reg":0,"n":2,"fmt":"f32","scale":1,"key":"nh3","unit":"ppm"}]
// fmt: u16 | i16 | i32 | f32 (ABCD) | f32s (word swap CDAB)
#pragma once
#include <ArduinoJson.h>

namespace Modbus {
void begin();
bool configure(JsonArrayConst arr);  // simpan ke flash
void pollAll();                      // tulis hasil ke kanal "rs<addr>.<key>"
uint8_t count();
}
