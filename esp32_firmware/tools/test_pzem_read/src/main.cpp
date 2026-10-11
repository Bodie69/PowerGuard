// One-off test tool: reads all 4 PZEM-004T V3.0 meters (addresses 1-4) on the
// shared bus using MycilaPZEM in async mode, and prints each meter's readings
// as JSON once a second, so you can confirm wiring and provisioned addresses
// actually work before trusting the main firmware's readings. Standalone
// project -- does not depend on the main firmware.
//
//   cd tools/test_pzem_read && pio run -t upload && pio device monitor
//
// A meter that is not answering shows "not connected". To test meters one
// at a time, connect only that meter's TX/RX; the others just report so.

#include <Arduino.h>
#include <ArduinoJson.h>
#include <MycilaPZEM.h>

constexpr int kUartNum = 2;
constexpr int kUartTxPin = 14;
constexpr int kUartRxPin = 27;

constexpr uint8_t kAddresses[] = {1, 2, 3, 4};
constexpr size_t kMeterCount = sizeof(kAddresses) / sizeof(kAddresses[0]);

HardwareSerial uart(kUartNum);
Mycila::PZEM pzems[kMeterCount];

void setup() {
    Serial.begin(115200);
    delay(1000);

    // Library takes (rxPin, txPin) from the ESP32's point of view.
    for (size_t i = 0; i < kMeterCount; i++) {
        pzems[i].setSharedSerial(true);
        pzems[i].begin(uart, kUartRxPin, kUartTxPin, kAddresses[i], true);
    }
    Serial.println("Testing PZEM-004T at addresses: 1 2 3 4, printing every 1s...");
}

void loop() {
    delay(2000);
    for (size_t i = 0; i < kMeterCount; i++) {
        Mycila::PZEM &pzem = pzems[i];
        if (!pzem.isEnabled()) {
            Serial.printf("[addr=%u] disabled (init failed)\n", kAddresses[i]);
            continue;
        }
        if (!pzem.isConnected()) {
            Serial.printf("[addr=%u] not connected -- check wiring (TX/RX not swapped, GND connected), "
                          "meter power, and that this is the address you set on this meter.\n",
                          kAddresses[i]);
            continue;
        }
        JsonDocument doc;
        pzem.toJson(doc.to<JsonObject>());
        Serial.printf("[addr=%u] OK ", kAddresses[i]);
        serializeJson(doc, Serial);
        Serial.println();
    }
    Serial.println();
}
