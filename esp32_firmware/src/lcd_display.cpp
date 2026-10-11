#include "lcd_display.h"

#include <LiquidCrystal_I2C.h>
#include <Wire.h>

#include "config.h"

namespace lcd_display {

namespace {

constexpr uint8_t kCols = 20;
constexpr uint8_t kRows = 4;

LiquidCrystal_I2C lcd(config::kLcdI2cAddress, kCols, kRows);

void printCentered(uint8_t row, const char *text) {
    const size_t len = strlen(text);
    lcd.setCursor(len < kCols ? (kCols - len) / 2 : 0, row);
    lcd.print(text);
}

} // namespace

void begin() {
    // Before lcd.init(): its own Wire.begin() then keeps these pins.
    Wire.begin(config::kLcdSdaPin, config::kLcdSclPin);
    lcd.init();
    lcd.backlight();
    lcd.clear();
    printCentered(0, "POWERGUARD");
    printCentered(1, "IoT");
    printCentered(2, "CAPSTONE");
    printCentered(3, "2026");
}

void showChannels(const ChannelState channelState[5]) {
    // Flips every refresh so a tripped row blinks between its two messages.
    static bool altPhase = false;
    altPhase = !altPhase;

    for (int ch = 1; ch <= 4; ch++) {
        const ChannelState &state = channelState[ch];
        char text[kCols + 1];
        if (state.overcurrentTripped) {
            if (altPhase) {
                snprintf(text, sizeof(text), "COM%d OVERCURRENT", ch);
            } else {
                snprintf(text, sizeof(text), "COM%d TRIP @ %.2fA", ch, state.tripCurrentA);
            }
        } else if (!state.breakerOn && state.offCause == OffCause::Manual) {
            snprintf(text, sizeof(text), "COM%d MANUAL OFF", ch);
        } else if (!state.breakerOn && state.offCause == OffCause::Scheduled) {
            snprintf(text, sizeof(text), "COM%d SCHEDULED OFF", ch);
        } else {
            const float voltage = state.breakerOn ? state.reading.voltage : 0.0f;
            const float current = state.breakerOn ? state.reading.current : 0.0f;
            const char *status = state.breakerOn && current > config::kCurrentLimitA
                                     ? "OC"
                                     : state.breakerStatus();
            // "COM1 230V 0.5A ON"
            snprintf(text, sizeof(text), "COM%d %03dV %.1fA %s", ch, (int)lroundf(voltage), current,
                     status);
        }
        // Padded to the full 20 columns so each row overwrites the previous
        // one without a flickering lcd.clear().
        char line[kCols + 1];
        snprintf(line, sizeof(line), "%-20s", text);
        lcd.setCursor(0, ch - 1);
        lcd.print(line);
    }
}

} // namespace lcd_display
