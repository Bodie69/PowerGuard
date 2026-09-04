#include "relay_bank.h"

void RelayBank::begin(const int pins[4], bool activeHigh, uint32_t pulseMs) {
    _activeHigh = activeHigh;
    _pulseMs = pulseMs;
    for (int i = 0; i < 4; i++) {
        _pins[i] = pins[i];
        // Set the idle level before switching the pin to OUTPUT, so it
        // never glitches through the energized level when pinMode() applies.
        digitalWrite(_pins[i], idleValue());
        pinMode(_pins[i], OUTPUT);
        digitalWrite(_pins[i], idleValue());
    }
}

void RelayBank::pulse(int channelNumber) {
    int index = channelNumber - 1;
    if (index < 0 || index >= 4 || _pins[index] < 0) {
        Serial.printf("No relay configured for channel %d\n", channelNumber);
        return;
    }
    int pin = _pins[index];
    digitalWrite(pin, energizedValue());
    delay(_pulseMs);
    digitalWrite(pin, idleValue());
}
