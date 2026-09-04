#pragma once

#include <Arduino.h>

namespace wifi_manager {

// Blocks until connected or timeoutMs elapses (throws via Serial + returns
// false on timeout).
bool connect(uint32_t timeoutMs = 15000);

// If not connected, attempts a reconnect (blocks up to its own timeout;
// logs and returns on failure rather than halting the caller).
void ensureConnected();

bool isConnected();

} // namespace wifi_manager
