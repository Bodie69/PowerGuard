#pragma once

#include "channel_state.h"

// 20x4 character LCD on an I2C (PCF8574) backpack. Driven only from the
// display task in main.cpp -- the Wire bus is not shared with anything else.
namespace lcd_display {

// Initialises the LCD and shows the centered welcome intro.
void begin();

// One row per channel: "COM1 230V 0.5A ON". An OFF channel shows zeros.
// A live reading above the limit shows "OC" as the status; a channel tripped
// for overcurrent alternates "COM1 OVERCURRENT" / "COM1 TRIP @ 1.23A" on
// each refresh until its breaker is reset. A channel the device switched off
// manually or by schedule shows "COM1 MANUAL OFF" / "COM1 SCHEDULED OFF"
// while it reads OFF, until its breaker is reset.
void showChannels(const ChannelState channelState[5]);

} // namespace lcd_display
