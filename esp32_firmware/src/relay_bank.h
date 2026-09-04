#pragma once

#include <Arduino.h>

// Momentary-pulse relay control. Never holds a coil continuously energized
// -- see safety_requirements in the project spec.
class RelayBank {
  public:
    void begin(const int pins[4], bool activeHigh, uint32_t pulseMs);

    // channelNumber is 1-4.
    void pulse(int channelNumber);

  private:
    int _pins[4] = {-1, -1, -1, -1};
    bool _activeHigh = false;
    uint32_t _pulseMs = 1000;

    int idleValue() const { return _activeHigh ? LOW : HIGH; }
    int energizedValue() const { return _activeHigh ? HIGH : LOW; }
};
