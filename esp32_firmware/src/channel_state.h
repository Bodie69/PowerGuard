#pragma once

#include <Arduino.h>

struct PzemReading {
    float voltage = 0;
    float current = 0;
    float power = 0;
    float energy = 0; // kWh, the meter's cumulative register
    float frequency = 0;
    float power_factor = 0;
};

// Zeroes the instantaneous values but keeps `energy`: it is a cumulative
// counter, and uploading 0 would corrupt the monthly-consumption maths that
// diffs the first and last energy reading of a month.
inline void clearLiveValues(PzemReading &r) {
    r.voltage = 0;
    r.current = 0;
    r.power = 0;
    r.frequency = 0;
    r.power_factor = 0;
}

// Why the device last switched a channel off (other than overcurrent, which
// has its own latch below). Shown on the LCD while the channel stays off.
enum class OffCause : uint8_t { None, Manual, Scheduled };

struct ChannelState {
    PzemReading reading;
    // False until the meter has answered at least once since boot; such a
    // channel is not uploaded (its zeros would be recorded as real data).
    bool hasReading = false;
    bool breakerOn = false;
    // Latched when loop() trips this channel for overcurrent, cleared when the
    // breaker is reset (voltage returns). Shown on the LCD until then.
    bool overcurrentTripped = false;
    float tripCurrentA = 0; // current that caused the trip
    // Set when loop() turns this channel off for a manual or scheduled off,
    // cleared when the breaker is reset (voltage returns).
    OffCause offCause = OffCause::None;

    const char *breakerStatus() const { return breakerOn ? "ON" : "OFF"; }
};
