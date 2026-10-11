#pragma once

#include <time.h>

// The ESP32 has no RTC battery, so before NTP answers time() counts up from
// 1970. Anything derived from the wall clock (schedules, upload timestamps,
// TLS certificate validity) must wait until this is true.
inline bool clockIsSet() {
    return time(nullptr) > 1700000000; // 2023-11-14
}
