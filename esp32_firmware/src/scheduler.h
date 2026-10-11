#pragma once

#include <Arduino.h>
#include <map>
#include <vector>

struct ScheduleEntry {
    String id;
    int channel = 0;
    bool enabled = true;
    String offTime;         // "HH:MM" or "HH:MM:SS", first 5 chars compared
    std::vector<String> days; // e.g. "MON", "TUE", ...
};

// Caches off_schedules rows and reports which channels are due to turn off
// right now (device local time = UTC + config::kUtcOffsetSeconds, matched to
// the minute, de-duped so a schedule only fires once per matching minute).
// Reports nothing until the clock has been set by NTP.
//
// Not thread-safe: the caller serialises refresh() and dueChannels().
class Scheduler {
  public:
    void refresh(std::vector<ScheduleEntry> schedules);

    std::vector<int> dueChannels();

  private:
    std::vector<ScheduleEntry> _schedules;
    std::map<String, String> _lastFiredMinute; // schedule id -> "YYYYMMDDHHMM"
};
