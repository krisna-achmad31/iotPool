# Firmware Sysnergi Hub (ESP32)

Firmware hub IoT modular: 6 Smart Port sensor plug & play, bus RS485/Modbus, 4 relay,
aturan otomasi yang jalan di hub (tetap jalan walau offline), provisioning Bluetooth,
MQTT, buffer offline, dan OTA.

## Upload lewat Arduino IDE 2

1. Board manager: **esp32 by Espressif** versi 3.x (sudah teruji di 3.3.1).
2. Library: **ArduinoJson** 7.x, **OneWire**, **DallasTemperature**.
3. Buka `sysnergi_hub/sysnergi_hub.ino`.
4. Tools → Board: **ESP32 Dev Module**.
5. Tools → Partition Scheme: **Huge APP (3MB No OTA/1MB SPIFFS)**.
   Pilihan ini hanya supaya IDE tidak menolak ukuran sketch. Tabel partisi yang
   benar-benar ditulis ke flash adalah `partitions.csv` di folder sketch (2 slot OTA
   masing-masing 1,94 MB + LittleFS 64 KB). Angka "62%" di IDE dihitung terhadap
   3 MB; terhadap slot sebenarnya pemakaiannya ±97,5%.
6. Upload, lalu buka Serial Monitor 115200 baud.

## Uji cepat tanpa cloud

Ketik JSON satu baris di Serial Monitor:

```
{"cmd":"relay","idx":0,"on":true,"min":1}
{"cmd":"rules","rules":[{"id":"r1","name":"Aerator oksigen rendah","if":{"ch":"p2.do","op":"<","val":4,"hyst":0.5},"then":{"relay":0},"maxMin":45,"fail":"on","notify":true}]}
{"cmd":"module_write","port":2,"type":514,"name":"DO Kolam 2"}
{"cmd":"ports","map":{"3":513}}
{"cmd":"modbus","list":[{"addr":1,"fn":3,"reg":0,"fmt":"f32","key":"nh3","unit":"ppm"}]}
{"cmd":"state"}
```

Kode jenis modul ada di `sensor_driver.h` (mis. 0x0202 = 514 = DO analog).

## Struktur

| File | Isi |
|---|---|
| `config.h` | Semua pin & konstanta |
| `sensor_driver.h`, `drivers.cpp` | Lapisan driver sensor + pabrik driver |
| `port_manager.*` | Deteksi modul otomatis, hot-plug, EEPROM ID, kalibrasi |
| `channels.*` | Tabel nilai sensor (`p2.do`, `rs1.nh3`, ...) |
| `rules.*` | Mesin aturan lokal (histeresis, jendela waktu, batas aman) |
| `relays.*` | Relay + pengaman (maks. lama nyala, jeda motor) |
| `modbus.*` | Sensor RS485 yang didefinisikan lewat JSON |
| `net.*` | Provisioning BLE/hotspot, Wi-Fi, MQTT, buffer offline, OTA |
| `ui.*` | LED status & tombol |

## Catatan ukuran flash

Stack Bluetooth bawaan Arduino-ESP32 (Bluedroid) besar. Sisa ruang di slot aplikasi
sekitar 50 KB. Untuk produksi pakai modul **ESP32-WROOM-32E N8 (8 MB)** atau build
dengan `custom_sdkconfig` di pioarduino untuk mematikan Bluetooth Classic.
