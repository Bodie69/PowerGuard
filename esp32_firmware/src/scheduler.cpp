#include "scheduler.h"

#include <time.h>

#include "clock_util.h"
#include "config.h"

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

void Scheduler::refresh(std::vector<ScheduleEntry> schedules) {
    _schedules = std::move(schedules);
    // Forget de-dupe state of schedules that no longer exist.
    for (auto it = _lastFiredMinute.begin(); it != _lastFiredMinute.end();) {
        bool found = false;
        for (const auto &sched : _schedules) {
            if (sched.id == it->first) {
                found = true;
                break;
            }
        }
        it = found ? std::next(it) : _lastFiredMinute.erase(it);
    }
}

std::vector<int> Scheduler::dueChannels() {
    std::vector<int> due;
    if (!clockIsSet()) {
        return due;
    }

    time_t now = time(nullptr) + config::kUtcOffsetSeconds;
    struct tm local;
    gmtime_r(&now, &local); // offset already applied above

    const char *weekday = kWeekdays[(local.tm_wday + 6) % 7]; // tm_wday: 0=Sun -> MON-based
    char hhmm[6];
    snprintf(hhmm, sizeof(hhmm), "%02d:%02d", local.tm_hour, local.tm_min);
    char minuteKey[13];
    snprintf(minuteKey, sizeof(minuteKey), "%04d%02d%02d%02d%02d", local.tm_year + 1900,
              local.tm_mon + 1, local.tm_mday, local.tm_hour, local.tm_min);

    for (const auto &sched : _schedules) {
        if (!sched.enabled || sched.channel < 1 || sched.channel > 4) {
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
