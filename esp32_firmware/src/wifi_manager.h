#pragma once

#include <Arduino.h>

namespace wifi_manager {

// Tries the last saved network (if any) -- blocks for up to kConnectTimeoutS
// (see wifi_manager.cpp) while doing so. If that fails, or nothing is saved
// yet (e.g. first boot), opens a WiFi setup portal (config::kWifiSetupApName)
// that ensureConnected() drives non-blocking from then on: connect to it
// with a phone/laptop and enter your real network's credentials at
// http://192.168.4.1. Those credentials are saved to flash (NVS) and reused
// on every boot after, so they never live in firmware source.
void begin();

// Call frequently (this pumps the setup portal's web server/DNS while it's
// open, and retries a dropped connection). Non-blocking.
void ensureConnected();

bool isConnected();

// True while the setup portal (not a normal station connection) is active.
bool isPortalActive();

// Erases the saved network and reopens the setup portal. Also triggered by
// typing "wifireset" into the serial console (see wifi_manager.cpp) --
// useful for moving the device to a new network without reflashing.
void resetCredentials();

} // namespace wifi_manager
