// One-off test tool: polls all 4 PZEM-004T V3.0 meters (addresses 1-4) on
// the shared bus once a second and prints each one's readings, so you can
// confirm wiring and provisioned addresses actually work before trusting
// the main firmware's readings. Standalone project -- does not depend on
// the main firmware.
//
//   cd tools/test_pzem_read && pio run -t upload && pio device monitor
//
// To test meters one at a time instead (e.g. right after provisioning,
// before wiring the rest onto the bus), set kTestAddresses to a single
// address, e.g. {1}.

#include <Arduino.h>
#include <cstring>

constexpr int kUartNum = 2;
constexpr int kUartTxPin = 27;
constexpr int kUartRxPin = 14;

constexpr uint8_t kTestAddresses[] = {1, 2, 3, 4};

constexpr int kRegCount = 10; // voltage, current(2), power(2), energy(2), frequency, power_factor, alarm
constexpr int kExpectedLen = 3 + kRegCount * 2 + 2;
constexpr uint32_t kReadTimeoutMs = 200;

HardwareSerial uart(kUartNum);

uint16_t crc16(const uint8_t *data, size_t len) {
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

bool readMeter(uint8_t address) {
    uint8_t request[8] = {address, 0x04, 0x00, 0x00, 0x00, kRegCount, 0, 0};
    uint16_t crc = crc16(request, 6);
    request[6] = crc & 0xFF;
    request[7] = (crc >> 8) & 0xFF;

    while (uart.available()) {
        uart.read();
    }
    uart.write(request, sizeof(request));
    uart.flush();

    uint8_t response[kExpectedLen];
    int received = 0;
    uint32_t deadline = millis() + kReadTimeoutMs;
    while (received < kExpectedLen && millis() < deadline) {
        if (uart.available()) {
            response[received++] = uart.read();
        }
    }

    if (received < kExpectedLen) {
        if (received == sizeof(request) && memcmp(response, request, sizeof(request)) == 0) {
            Serial.printf("[addr=%d] LOOPBACK: the %d bytes received are an exact copy of the "
                           "request we just sent -- this is our own TX echoing into RX, not a "
                           "reply from the meter. Check for a short/bridge between the ESP32 TX "
                           "and RX pins (or their wiring), not the meter itself.\n",
                           address, received);
            return false;
        }
        Serial.printf("[addr=%d] TIMEOUT: got %d/%d bytes -- check wiring (TX/RX not swapped, "
                       "GND connected), baud rate, meter power, and that this is the address "
                       "you actually set on this meter.\n",
                       address, received, kExpectedLen);
        return false;
    }
    if (response[0] != address || response[1] != 0x04) {
        Serial.printf("[addr=%d] BAD RESPONSE: addr/function mismatch -- got addr=%d func=0x%02X "
                       "(a different meter answered, or this one is on a different address).\n",
                       address, response[0], response[1]);
        return false;
    }
    uint16_t expectedCrc = crc16(response, kExpectedLen - 2);
    uint16_t gotCrc = response[kExpectedLen - 2] | (response[kExpectedLen - 1] << 8);
    if (expectedCrc != gotCrc) {
        Serial.printf("[addr=%d] CRC ERROR -- noisy/shared bus or bad wiring.\n", address);
        return false;
    }

    uint16_t regs[kRegCount];
    for (int i = 0; i < kRegCount; i++) {
        regs[i] = (response[3 + i * 2] << 8) | response[4 + i * 2];
    }

    float voltage = regs[0] / 10.0f;
    float current = (regs[1] | ((uint32_t)regs[2] << 16)) / 1000.0f;
    float power = (regs[3] | ((uint32_t)regs[4] << 16)) / 10.0f;
    float energy = (regs[5] | ((uint32_t)regs[6] << 16)) / 1000.0f;
    float frequency = regs[7] / 10.0f;
    float powerFactor = regs[8] / 100.0f;

    Serial.printf("[addr=%d] OK  V=%.1fV  I=%.3fA  P=%.1fW  E=%.3fkWh  F=%.1fHz  PF=%.2f\n",
                   address, voltage, current, power, energy, frequency, powerFactor);
    return true;
}

constexpr int kNumAddresses = sizeof(kTestAddresses) / sizeof(kTestAddresses[0]);

void setup() {
    Serial.begin(115200);
    delay(1000);
    uart.begin(9600, SERIAL_8N1, kUartRxPin, kUartTxPin);
    Serial.print("Testing PZEM-004T at addresses:");
    for (uint8_t addr : kTestAddresses) {
        Serial.printf(" %d", addr);
    }
    Serial.println(", polling every 1s...");
}

void loop() {
    for (uint8_t addr : kTestAddresses) {
        readMeter(addr);
    }
    Serial.println();
    delay(1000);
}
