// One-off tool: zeroes the cumulative energy counter of ONE PZEM-004T V3.0 on
// the shared bus, then confirms by reading it back. Standalone project -- does
// not depend on the main firmware.
//
//   cd tools/reset_pzem_energy && pio run -t upload --upload-port COMxx && pio device monitor
//
// The reset is PERMANENT: the meter's stored kWh total is lost. It is sent to
// the single address in kAddress (never the 0xF8 broadcast address), so the
// other meters on the bus are not touched. It only runs if that meter first
// answers a normal read, which proves the address is right and the meter is
// alive. After it prints RESULT, reflash the main firmware.

#include <Arduino.h>
#include <MycilaPZEM.h>

constexpr int kUartNum = 2;
constexpr int kUartTxPin = 14;
constexpr int kUartRxPin = 27;

constexpr uint8_t kAddress = 2; // <-- channel 2's meter
constexpr int kAttempts = 8;    // the shared bus is noisy, so retry

HardwareSerial uart(kUartNum);
Mycila::PZEM pzem;

// Returns the meter's energy in Wh, or -1 if it never answered.
static long readEnergyWh() {
    for (int i = 0; i < kAttempts; i++) {
        if (pzem.read()) {
            return (long)pzem.data.activeEnergy;
        }
        delay(300);
    }
    return -1;
}

void setup() {
    Serial.begin(115200);
    delay(1500);

    // Library takes (rxPin, txPin) from the ESP32's point of view. async=false:
    // no background task, so only this code talks on the bus.
    pzem.begin(uart, kUartRxPin, kUartTxPin, kAddress, false);
    if (!pzem.isEnabled()) {
        Serial.println("RESULT: FAILED - PZEM init failed (invalid pins?).");
        return;
    }

    const long before = readEnergyWh();
    if (before < 0) {
        Serial.printf("RESULT: ABORTED - meter at address %u never answered a read, nothing was reset. "
                      "Check wiring/power.\n",
                      kAddress);
        return;
    }
    Serial.printf("Meter %u energy before reset: %ld Wh\n", kAddress, before);

    bool acked = false;
    for (int i = 0; i < kAttempts && !acked; i++) {
        acked = pzem.resetEnergy();
        if (!acked) delay(300);
    }
    Serial.printf("Reset command %s\n", acked ? "acknowledged" : "not acknowledged (checking anyway)");

    const long after = readEnergyWh();
    if (after < 0) {
        Serial.println("RESULT: UNKNOWN - reset sent but the read-back failed. Re-run to check.");
    } else if (after < 5) {
        Serial.printf("RESULT: CONFIRMED - meter %u energy is now %ld Wh (was %ld Wh).\n", kAddress, after, before);
    } else {
        Serial.printf("RESULT: FAILED - meter %u still reads %ld Wh. Re-run.\n", kAddress, after);
    }
}

void loop() {
}
