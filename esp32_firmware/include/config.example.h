#pragma once

// Copy this file to config.h and fill in your own values. config.h is
// gitignored -- see README.md "Security".

namespace config {

constexpr const char *kWifiSsid = "your-wifi-ssid";
constexpr const char *kWifiPassword = "your-wifi-password";

constexpr const char *kSupabaseUrl = "https://your-project.supabase.co";
// The service_role key, NOT the anon key -- see README.md "Security" section.
constexpr const char *kSupabaseServiceKey = "your-supabase-service-role-key";

// Any UUID you generate once (e.g. `python -c "import uuid; print(uuid.uuid4())"`)
// and reuse across reflashes so the app keeps pointing at the same device row.
constexpr const char *kDeviceId = "your-device-uuid";
constexpr const char *kDeviceName = "PowerGuard ESP32";
constexpr const char *kFirmwareVersion = "0.1.0";

// Modbus slave addresses of the 4 PZEM-004T meters, set once via
// tools/set_pzem_address before first boot. Order here maps to dashboard
// channel_number 1-4.
constexpr uint8_t kPzemAddresses[4] = {1, 2, 3, 4};
// UART2, not UART0 -- UART0 is the ESP32's USB/REPL serial console.
constexpr uint8_t kPzemUartNum = 2;
constexpr int kPzemTxPin = 27;
constexpr int kPzemRxPin = 14;

// GPIO pin driving each channel's relay coil (index 0 = channel 1). Avoids
// strapping pins (0, 2, 5, 12, 15) and input-only pins (34-39) -- see
// README.md "Wiring".
constexpr int kRelayPins[4] = {32, 33, 25, 26};
// Most cheap opto-isolated relay boards are active-low (LOW = energized).
constexpr bool kRelayActiveHigh = false;
constexpr uint32_t kRelayPulseMs = 1000;

constexpr float kCurrentLimitA = 5.0f;

// If an OFF channel's voltage reading rises above this, firmware assumes
// the breaker was manually reset and clears breaker_status back to 'ON'.
// Assumes the PZEM is wired downstream of the breaker. See README.md.
constexpr float kResetVoltageThresholdV = 90.0f;

constexpr uint32_t kLoopIntervalMs = 2000;
constexpr uint32_t kScheduleRefreshMs = 5 * 60 * 1000UL;
constexpr uint32_t kHeartbeatMs = 30 * 1000UL;
constexpr uint32_t kNtpResyncMs = 60 * 60 * 1000UL;

} // namespace config
