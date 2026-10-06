#pragma once
// Struct dipisah ke header agar prototype otomatis Arduino tidak mendahului deklarasinya.

#include <Arduino.h>

#define NPORT 6
#define NRELAY 4
#define MAX_RULES 16
#define MAX_ALARMS NPORT
#define EVQ_SIZE 32
#define SLOTQ_SIZE 36   // 3 jam slot 5 menit

struct Cond { int8_t ch = -1; bool gt = false; float value = 0; };

enum TrigType : uint8_t { TRIG_THRESHOLD, TRIG_SCHEDULE };
enum ActType  : uint8_t { ACT_RELAY, ACT_NOTIFY };
enum UntilType: uint8_t { UNTIL_TRIGGER_CLEARS, UNTIL_THRESHOLD, UNTIL_DURATION };

struct Rule {
  char id[28];
  TrigType trig; Cond tc; uint16_t holdSec; uint16_t startMin, endMin; uint8_t daysMask;
  ActType act; int8_t relay; bool on; uint8_t level;
  UntilType untilType; Cond uc; uint32_t durSec;
  uint8_t severity;                    // 0 info, 1 warning, 2 danger
  uint32_t maxRunSec, cooldownSec;
  // runtime
  uint32_t condSince; bool active; uint32_t startedAt, cooldownUntil;
};

struct Alarm {
  int8_t ch; float warnLt, warnGt, dangerLt, dangerGt;
  uint8_t level; uint8_t pending; uint32_t pendingSince;
};

struct RelayState {
  bool on; uint8_t level; bool manual; uint32_t manualUntil;   // 0 = sampai relay_auto
  uint32_t since; char ruleId[28];
};

struct Event {
  uint64_t ms; char type[20]; uint8_t severity;
  int8_t ch; float value; int8_t relay; char ruleId[28];
};

struct SlotRec { uint32_t localEpoch; float v[NPORT]; uint8_t mask; };
struct HourRec { uint32_t localEpoch; float mn[NPORT], av[NPORT], mx[NPORT]; uint8_t mask; };

struct Keys { String dayId, date, slot, monthId, month, hourKey; };
