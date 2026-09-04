#include "scheduler.h"

#include <time.h>

namespace {
const char *kWeekdays[7] = {"MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"};

bool hasDay(const std::vector<String> &days, const char *day) {
    for (const auto &d : days) {
        if (d == day) {
            return true;
        }
    }
    return false;
}
} // namespace

std::vector<int> Scheduler::dueChannels() {
    time_t now = time(nullptr);
    struct tm utc;
    gmtime_r(&now, &utc);

    const char *weekday = kWeekdays[(utc.tm_wday + 6) % 7]; // tm_wday: 0=Sun -> MON-based
    char hhmm[6];
    snprintf(hhmm, sizeof(hhmm), "%02d:%02d", utc.tm_hour, utc.tm_min);
    char minuteKey[13];
    snprintf(minuteKey, sizeof(minuteKey), "%04d%02d%02d%02d%02d", utc.tm_year + 1900,
              utc.tm_mon + 1, utc.tm_mday, utc.tm_hour, utc.tm_min);

    std::vector<int> due;
    for (const auto &sched : _schedules) {
        if (!sched.enabled) {
            continue;
        }
        if (!hasDay(sched.days, weekday)) {
            continue;
        }
        if (sched.offTime.substring(0, 5) != hhmm) {
            continue;
        }
        auto it = _lastFiredMinute.find(sched.id);
        if (it != _lastFiredMinute.end() && it->second == minuteKey) {
            continue;
        }
        _lastFiredMinute[sched.id] = minuteKey;
        due.push_back(sched.channel);
    }
    return due;
}
