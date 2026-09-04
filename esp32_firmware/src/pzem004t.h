#pragma once

#include <Arduino.h>

// Modbus RTU driver for one PZEM-004T V3.0 meter sharing a UART bus with
// other meters, distinguished by slave address.

struct PzemReading {
    float voltage = 0;
    float current = 0;
    float power = 0;
    float energy = 0;
    float frequency = 0;
    float power_factor = 0;
};

uint16_t pzemCrc16(const uint8_t *data, size_t len);

class PZEM004T {
  public:
    PZEM004T(HardwareSerial &uart, uint8_t address) : _uart(uart), _address(address) {}

    // Throws (via returning false) on timeout, bad response, or CRC error.
    // On success, fills `out` and returns true.
    bool read(PzemReading &out, String &error);

  private:
    HardwareSerial &_uart;
    uint8_t _address;
};
