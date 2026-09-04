#include "pzem004t.h"

namespace {
constexpr int kRegCount = 10; // voltage, current(2), power(2), energy(2), frequency, power_factor, alarm
constexpr int kExpectedLen = 3 + kRegCount * 2 + 2;
constexpr uint32_t kReadTimeoutMs = 200;
}

uint16_t pzemCrc16(const uint8_t *data, size_t len) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; bit++) {
            if (crc & 1) {
                crc = (crc >> 1) ^ 0xA001;
            } else {
                crc >>= 1;
            }
        }
    }
    return crc;
}

bool PZEM004T::read(PzemReading &out, String &error) {
    uint8_t request[8] = {_address, 0x04, 0x00, 0x00, 0x00, kRegCount, 0, 0};
    uint16_t crc = pzemCrc16(request, 6);
    request[6] = crc & 0xFF;
    request[7] = (crc >> 8) & 0xFF;

    while (_uart.available()) {
        _uart.read();
    }
    _uart.write(request, sizeof(request));
    _uart.flush();

    uint8_t response[kExpectedLen];
    int received = 0;
    uint32_t deadline = millis() + kReadTimeoutMs;
    while (received < kExpectedLen && millis() < deadline) {
        if (_uart.available()) {
            response[received++] = _uart.read();
        }
    }

    if (received < kExpectedLen) {
        error = "PZEM timeout addr=" + String(_address);
        return false;
    }
    if (response[0] != _address || response[1] != 0x04) {
        error = "PZEM bad response addr=" + String(_address);
        return false;
    }
    uint16_t expectedCrc = pzemCrc16(response, kExpectedLen - 2);
    uint16_t gotCrc = response[kExpectedLen - 2] | (response[kExpectedLen - 1] << 8);
    if (expectedCrc != gotCrc) {
        error = "PZEM CRC error addr=" + String(_address);
        return false;
    }

    uint16_t regs[kRegCount];
    for (int i = 0; i < kRegCount; i++) {
        regs[i] = (response[3 + i * 2] << 8) | response[4 + i * 2];
    }

    out.voltage = regs[0] / 10.0f;
    out.current = (regs[1] | ((uint32_t)regs[2] << 16)) / 1000.0f;
    out.power = (regs[3] | ((uint32_t)regs[4] << 16)) / 10.0f;
    out.energy = (regs[5] | ((uint32_t)regs[6] << 16)) / 1000.0f; // Wh -> kWh
    out.frequency = regs[7] / 10.0f;
    out.power_factor = regs[8] / 100.0f;
    return true;
}
