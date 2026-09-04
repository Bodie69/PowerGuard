// One-off provisioning tool: connect exactly ONE PZEM-004T V3.0 to the bus
// (TX/RX per kUartTxPin/kUartRxPin below), set kNewAddress, then flash this
// standalone project with the meter's power on:
//   cd tools/set_pzem_address && pio run -t upload && pio device monitor
// Repeat once per meter (addresses 1-4) before wiring them all onto the
// shared bus. Standalone project -- does not depend on the main firmware.

#include <Arduino.h>
#include <cstring>

constexpr int kUartNum = 2;
constexpr int kUartTxPin = 27;
constexpr int kUartRxPin = 14;

constexpr uint8_t kGeneralAddress = 0xF8;
constexpr uint16_t kAddressRegister = 0x0002;

constexpr uint8_t kNewAddress = 1; // <-- change this before each run (1, then 2, then 3, then 4)

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

void setAddress(uint8_t newAddress) {
    if (newAddress < 1 || newAddress > 247) {
        Serial.println("address must be between 1 and 247");
        return;
    }

    uint8_t frame[8] = {
        kGeneralAddress,
        0x06,
        (uint8_t)((kAddressRegister >> 8) & 0xFF),
        (uint8_t)(kAddressRegister & 0xFF),
        (uint8_t)((newAddress >> 8) & 0xFF),
        (uint8_t)(newAddress & 0xFF),
        0,
        0,
    };
    uint16_t crc = crc16(frame, 6);
    frame[6] = crc & 0xFF;
    frame[7] = (crc >> 8) & 0xFF;

    while (uart.available()) {
        uart.read();
    }
    uart.write(frame, sizeof(frame));
    uart.flush();
    delay(200);

    uint8_t response[16];
    int received = 0;
    while (uart.available() && received < (int)sizeof(response)) {
        response[received++] = uart.read();
    }

    Serial.print("Sent:");
    for (uint8_t b : frame) {
        Serial.printf(" %02X", b);
    }
    Serial.println();

    Serial.print("Response:");
    for (int i = 0; i < received; i++) {
        Serial.printf(" %02X", response[i]);
    }
    Serial.println();

    // A successful Modbus "write single register" reply is an exact echo of
    // the request frame (address, function, register, value, CRC) -- so a
    // byte-for-byte match is the real confirmation, not just a response
    // existing. A response starting with (address | 0x80) is a Modbus
    // exception reply -- the meter understood the request but rejected it.
    if (received == sizeof(frame) && memcmp(response, frame, sizeof(frame)) == 0) {
        Serial.printf("CONFIRMED: address set to %d (echoed frame matches exactly).\n", newAddress);
    } else if (received >= 2 && response[1] == (0x06 | 0x80)) {
        Serial.printf("REJECTED: meter returned Modbus exception code 0x%02X.\n", response[2]);
    } else if (received == 0) {
        Serial.println("NO RESPONSE - check wiring (TX/RX not swapped, GND connected), baud rate, "
                        "and that the meter is powered and only one is connected.");
    } else {
        Serial.println("UNEXPECTED RESPONSE - see bytes above; does not match a successful write.");
    }
}

void setup() {
    Serial.begin(115200);
    delay(1000);
    uart.begin(9600, SERIAL_8N1, kUartRxPin, kUartTxPin);
    setAddress(kNewAddress);
}

void loop() {
}
