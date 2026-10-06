// Lapisan abstraksi sensor (HAL). Semua sensor — analog, digital, I2C,
// 1-Wire, UART, RS485 — dibungkus kelas turunan SensorDriver. Hub inti
// tidak pernah tahu detail sensor; ia hanya memanggil begin() dan sample().
#pragma once
#include <Arduino.h>

// ---------- Kode jenis modul (disimpan di EEPROM ID tiap modul) ----------
enum ModuleType : uint16_t {
  MOD_NONE        = 0x0000,
  MOD_DS18B20     = 0x0101,  // suhu air / tanah, 1-Wire di jalur D
  MOD_SHT3X       = 0x0102,  // suhu & lembap udara, I2C 0x44
  MOD_BH1750      = 0x0103,  // cahaya, I2C 0x23
  MOD_PH_ANALOG   = 0x0201,  // pH analog (PH-4502C / Gravity pH)
  MOD_DO_ANALOG   = 0x0202,  // oksigen terlarut analog (Gravity DO)
  MOD_SOIL_CAP    = 0x0203,  // kelembapan tanah kapasitif
  MOD_MQ137       = 0x0204,  // amonia udara (kandang)
  MOD_ANALOG_LIN  = 0x02FF,  // analog generik y = a*mV + b
  MOD_LEVEL_A02   = 0x0301,  // tinggi air ultrasonik A02YYUW (UART di jalur D)
};

// ---------- Deskriptor di EEPROM AT24C02 (alamat 0x50) pada modul ----------
#define DESC_MAGIC 0x314E5953UL  // "SYN1"
#define DESC_CAL_COUNT 6
struct __attribute__((packed)) ModuleDescriptor {
  uint32_t magic;
  uint16_t type;               // ModuleType
  uint16_t hwRev;
  uint32_t serial;
  char name[16];               // nama tampilan, mis. "DO Kolam"
  float cal[DESC_CAL_COUNT];   // koefisien kalibrasi, arti tergantung jenis
  uint32_t calEpoch;           // waktu kalibrasi terakhir (unix)
  uint16_t crc;                // CRC16 seluruh byte sebelum field ini
};

uint16_t crc16(const uint8_t *data, size_t len);

// ---------- Konteks port yang diberikan ke driver ----------
struct PortContext {
  uint8_t port;        // 1..6
  uint8_t pinA, pinD;
  ModuleDescriptor desc;
  bool hasEeprom;
  void selectBus() const;  // aktifkan kanal mux port ini sebelum akses I2C
};

class SensorDriver {
public:
  virtual ~SensorDriver() {}
  virtual bool begin(PortContext &ctx) = 0;
  // Baca sensor lalu tulis hasil ke tabel Channels dengan prefix "p<port>."
  virtual void sample(PortContext &ctx) = 0;
  virtual const char *model() const = 0;
};

// Pabrik driver: kode jenis → objek driver. Tambah sensor baru = tambah 1 baris di drivers.cpp
SensorDriver *createDriver(uint16_t type);
// Deteksi otomatis modul I2C polos (tanpa EEPROM ID) dari alamatnya
uint16_t probeBareI2C();
const char *typeName(uint16_t type);
