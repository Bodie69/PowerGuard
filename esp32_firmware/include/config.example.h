#pragma once

// Copy this file to config.h and fill in your own values. config.h is
// gitignored -- see README.md "Security".

namespace config {

// WiFi credentials are NOT stored here (or anywhere in firmware source).
// On first boot -- or any boot where the last saved network can't be
// reached -- the device opens its own WiFi setup portal; connect to it from
// a phone/laptop to enter your real network's SSID/password over a web
// form. That gets saved to the ESP32's flash (NVS) and reused on every boot
// after, so re-flashing never wipes it and it's never checked into git. See
// wifi_manager.h and README.md "WiFi provisioning".
//
// These two constants are only the setup portal's own temporary
// network -- what you'd connect to *before* you've told the device your
// real WiFi -- kept here (not hardcoded in wifi_manager.cpp) so you can
// rename/re-secure it without touching firmware logic. WPA2 requires 8+
// characters; kWifiSetupApPassword must be at least that long.
constexpr const char *kWifiSetupApName = "PowerGuard-Setup";
constexpr const char *kWifiSetupApPassword = "powerguard-setup";

constexpr const char *kSupabaseUrl = "https://your-project.supabase.co";
// The service_role key, NOT the anon key -- see README.md "Security" section.
constexpr const char *kSupabaseServiceKey = "your-supabase-service-role-key";

// Any UUID you generate once (e.g. `python -c "import uuid; print(uuid.uuid4())"`)
// and reuse across reflashes so the app keeps pointing at the same device row.
constexpr const char *kDeviceId = "your-device-uuid";
constexpr const char *kDeviceName = "PowerGuard IoT";
constexpr const char *kFirmwareVersion = "2.0";

// Modbus slave addresses of the 4 PZEM-004T meters, set once via
// tools/set_pzem_address before first boot. Order here maps to dashboard
// channel_number 1-4.
constexpr uint8_t kPzemAddresses[4] = {1, 2, 3, 4};
// UART2, not UART0 -- UART0 is the ESP32's USB/REPL serial console.
constexpr uint8_t kPzemUartNum = 2;
constexpr int kPzemTxPin = 14;
constexpr int kPzemRxPin = 27;
// Pause after each meter's read so the shared bus settles before the next request.
constexpr uint32_t kPzemGapMs = 100;

// GPIO pin driving each channel's relay coil (index 0 = channel 1). Avoids
// strapping pins (0, 2, 5, 12, 15) and input-only pins (34-39) -- see
// README.md "Wiring".
constexpr int kRelayPins[4] = {32, 33, 25, 26};
// Most cheap opto-isolated relay boards are active-low (LOW = energized).
constexpr bool kRelayActiveHigh = false;
constexpr uint32_t kRelayPulseMs = 1000;

constexpr float kCurrentLimitA = 1.0f;

// 20x4 I2C character LCD (PCF8574 backpack). Most backpacks answer at 0x27;
// some at 0x3F -- run an I2C scanner if the screen stays blank. GPIO21/22 are
// the ESP32's default I2C pins.
constexpr uint8_t kLcdI2cAddress = 0x27;
constexpr int kLcdSdaPin = 21;
constexpr int kLcdSclPin = 22;
// How long the welcome intro stays up before the channel readings.
constexpr uint32_t kLcdIntroMs = 3000;
constexpr uint32_t kLcdRefreshMs = 1000;

// If an OFF channel's voltage reading rises above this, firmware assumes
// the breaker was manually reset and clears breaker_status back to 'ON'.
// Assumes the PZEM is wired downstream of the breaker. See README.md.
constexpr float kResetVoltageThresholdV = 90.0f;

// Cloud sync cadence (runs on its own task, never delays the safety loop).
// kLoopIntervalMs: channel upload + history row + off-command poll.
constexpr uint32_t kLoopIntervalMs = 2000;
constexpr uint32_t kScheduleRefreshMs = 30 * 1000UL;
// The server (and app) call the device offline after 35s without a heartbeat,
// so keep this well under that.
constexpr uint32_t kHeartbeatMs = 10 * 1000UL;

// Offset of the device's local time from UTC, in seconds. off_schedules times
// are entered in the app as local clock times, so this must match the
// timezone you use the app in (e.g. UTC+8 = 8 * 3600). At 0, schedule
// times are read as UTC.
constexpr int32_t kUtcOffsetSeconds = 0;

} // namespace config
