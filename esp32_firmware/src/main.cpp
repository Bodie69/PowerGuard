#include <Arduino.h>
#include <esp_task_wdt.h>
#include <time.h>

#include "channel_state.h"
#include "config.h"
#include "pzem004t.h"
#include "relay_bank.h"
#include "scheduler.h"
#include "supabase_client.h"
#include "wifi_manager.h"

namespace {

constexpr uint32_t kWdtTimeoutS = 15;
constexpr uint32_t kSafetyLoopDelayMs = 100;

SupabaseClient sb(config::kSupabaseUrl, config::kSupabaseServiceKey);
HardwareSerial pzemSerial(config::kPzemUartNum);
PZEM004T *meters[4];
RelayBank relays;
Scheduler scheduler;
ChannelState channelState[5]; // index 0 unused, channels are 1-4

uint32_t lastCloudTick = 0;
uint32_t lastNtpSync = 0;

void turnOffChannel(int channelNumber, const char *reason, const char *triggeredBy) {
    Serial.printf("[SAFETY] Turning OFF channel %d | Reason: %s\n", channelNumber, reason);
    relays.pulse(channelNumber);
    ChannelState &state = channelState[channelNumber];
    state.breakerStatus = STATUS_OFF;
    // Best-effort; SupabaseClient logs and swallows its own errors, matching
    // the original firmware's bare try/except around this call so a failed
    // upload never blocks the safety-critical relay pulse above.
    sb.logOffEvent(config::kDeviceId, channelNumber, reason, state, triggeredBy);
}

void syncTime() {
    Serial.println("[NTP] Syncing time...");
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
    struct tm timeinfo;
    if (getLocalTime(&timeinfo, 5000)) {
        Serial.printf("[NTP] Success: %04d-%02d-%02d %02d:%02d:%02d UTC\n",
                       timeinfo.tm_year + 1900, timeinfo.tm_mon + 1, timeinfo.tm_mday,
                       timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
    } else {
        Serial.println("[NTP] Failed");
    }
}

void runSafetyChecks() {
    for (int channelNumber = 1; channelNumber <= 4; channelNumber++) {
        PzemReading reading;
        String err;
        if (meters[channelNumber - 1]->read(reading, err)) {
            ChannelState &state = channelState[channelNumber];
            state.reading = reading;

            // 1. Overcurrent protection
            if (state.breakerStatus != STATUS_OFF && reading.current > config::kCurrentLimitA) {
                turnOffChannel(channelNumber, "Overcurrent", "system");
            }

            // 2. Auto-reset status (manual reset detected)
            if (state.breakerStatus == STATUS_OFF &&
                reading.voltage > config::kResetVoltageThresholdV) {
                Serial.printf("[SYSTEM] Breaker reset on channel %d\n", channelNumber);
                state.breakerStatus = STATUS_ON;
            }
        } else {
            Serial.printf("[PZEM] Error ch %d: %s\n", channelNumber, err.c_str());
        }
    }

    // 3. Check local schedules (offline safe)
    for (int channelNumber : scheduler.dueChannels()) {
        if (channelState[channelNumber].breakerStatus != STATUS_OFF) {
            turnOffChannel(channelNumber, "Manual Off", "system");
        }
    }
}

void runCloudSync() {
    if (!wifi_manager::isConnected()) {
        wifi_manager::ensureConnected();
        return;
    }

    sb.upsertChannels(config::kDeviceId, channelState);

    for (const OffCommand &cmd : sb.fetchPendingOffCommands(config::kDeviceId)) {
        turnOffChannel(cmd.channel, "Manual Off", "admin");
        sb.completeOffCommand(cmd.id);
    }

    scheduler.refresh(sb.fetchSchedules(config::kDeviceId));
    sb.heartbeat(config::kDeviceId);
}

} // namespace

void setup() {
    Serial.begin(115200);

    esp_task_wdt_init(kWdtTimeoutS, true);
    esp_task_wdt_add(NULL);

    wifi_manager::connect();
    syncTime();
    lastNtpSync = millis();

    pzemSerial.begin(9600, SERIAL_8N1, config::kPzemRxPin, config::kPzemTxPin);
    for (int i = 0; i < 4; i++) {
        meters[i] = new PZEM004T(pzemSerial, config::kPzemAddresses[i]);
    }
    relays.begin(config::kRelayPins, config::kRelayActiveHigh, config::kRelayPulseMs);

    sb.ensureDevice(config::kDeviceId, config::kDeviceName, config::kFirmwareVersion);
    Serial.println("[CLOUD] Device registered");

    lastCloudTick = millis();
}

void loop() {
    esp_task_wdt_reset();

    runSafetyChecks();

    if (millis() - lastCloudTick >= config::kLoopIntervalMs) {
        lastCloudTick = millis();
        runCloudSync();
    }

    if (millis() - lastNtpSync >= config::kNtpResyncMs) {
        lastNtpSync = millis();
        syncTime();
    }

    delay(kSafetyLoopDelayMs);
}
