#pragma once

#include <Arduino.h>

#include "pzem004t.h"

static const char *STATUS_ON = "ON";
static const char *STATUS_OFF = "OFF";

struct ChannelState {
    PzemReading reading;
    String breakerStatus = STATUS_OFF;
};
