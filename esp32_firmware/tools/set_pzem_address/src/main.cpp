// One-off provisioning tool: connect exactly ONE PZEM-004T V3.0 to the bus
// (TX/RX per kUartTxPin/kUartRxPin below), set kNewAddress, then flash this
// standalone project with the meter's power on:
//   cd tools/set_pzem_address && pio run -t upload && pio device monitor
// Repeat once per meter (addresses 1-4) before wiring them all onto the
// shared bus. Standalone project -- does not depend on the main firmware.
//
// Built on MycilaPZEM: begin() on the general address (0xF8) detects the
// single connected meter's current address, then setDeviceAddress() writes
// the new one and verifies it by reading the meter back at that address.

#include <Arduino.h>
#include <MycilaPZEM.h>

constexpr int kUartNum = 2;
constexpr int kUartTxPin = 14;
constexpr int kUartRxPin = 27;

constexpr uint8_t kNewAddress = 4; // <-- change this before each run (1, then 2, then 3, then 4)

HardwareSerial uart(kUartNum);
Mycila::PZEM pzem;

void setup() {
    Serial.begin(115200);
    delay(1000);

    if (kNewAddress < MYCILA_PZEM_ADDRESS_MIN || kNewAddress > MYCILA_PZEM_ADDRESS_MAX) {
        Serial.printf("address must be between %d and %d\n", MYCILA_PZEM_ADDRESS_MIN, MYCILA_PZEM_ADDRESS_MAX);
        return;
    }

    // Library takes (rxPin, txPin) from the ESP32's point of view.
    pzem.begin(uart, kUartRxPin, kUartTxPin, MYCILA_PZEM_ADDRESS_GENERAL);
    if (!pzem.isEnabled()) {
        Serial.println("PZEM init failed - invalid pins?");
        return;
    }

    uint8_t current = pzem.getDeviceAddress();
    Serial.printf("Meter currently at address 0x%02X\n", current);

    if (!pzem.setDeviceAddress(kNewAddress)) {
        Serial.println("FAILED: no confirmed reply at the new address - check wiring (TX/RX not swapped, "
                       "GND connected), meter power, and that only ONE meter is connected.");
        pzem.end();
        return;
    }

    if (pzem.read()) {
        // read() succeeded at the new address, so it is confirmed on the wire.
        Serial.printf("CONFIRMED: address set to %d (meter answered a read at the new address).\n", kNewAddress);
    } else {
        Serial.printf("Address written (%d) but the verification read failed - re-run or check wiring.\n", kNewAddress);
    }
    pzem.end();
}

void loop() {
}
