#include <Arduino.h>
#include <MycilaPZEM.h>
#include <esp_system.h>
#include <esp_task_wdt.h>
#include <time.h>
#include <vector>

#include "channel_state.h"
#include "clock_util.h"
#include "config.h"
#include "lcd_display.h"
#include "relay_bank.h"
#include "scheduler.h"
#include "supabase_client.h"
#include "wifi_manager.h"

// Four tasks:
//   loop()        safety: overcurrent, breaker-reset detection, local schedules,
//                 relay pulses. Never touches the network, so a slow or dead
//                 connection can't delay a trip.
//   pzemPollTask  reads the four meters one at a time (core 0).
//   cloudTask     WiFi/NTP/Supabase. Talks to loop() only through
//                 stateMutex-guarded state and two queues.
//   displayTask   welcome intro, then per-channel V/A on the 20x4 LCD.

namespace {

// Must exceed the slowest single Supabase call (see SupabaseClient::request);
// each task feeds the watchdog between calls.
constexpr uint32_t kWdtTimeoutS = 30;
constexpr uint32_t kSafetyLoopDelayMs = 100;
// A meter with no good read for this long is treated as silent: its live
// values are cleared so stale numbers aren't uploaded as current.
constexpr uint32_t kMeterStaleMs = 10000;
// After pulsing a channel's relay, don't pulse it again for this long: the
// breaker takes a moment to open and readings taken meanwhile still show the
// overload. (This only limits relay pulses; it never affects the reported
// status.)
constexpr uint32_t kTripCooldownMs = 3000;
// A trip needs this many consecutive over-limit readings, so one corrupted
// frame that happens to pass the meter's CRC can't trip a breaker.
constexpr uint8_t kOvercurrentConfirmReads = 2;
// Physical limits of a PZEM-004T V3 (100 A variant). A reading outside these
// is a corrupted frame, not a measurement, and is discarded.
constexpr float kMaxPlausibleVoltageV = 300.0f;
constexpr float kMaxPlausibleCurrentA = 100.0f;
constexpr float kMaxPlausiblePowerW = 30000.0f;
// The PZEM's energy register tops out at 9999.99 kWh.
constexpr float kMaxPlausibleEnergyKwh = 10000.0f;
// The cumulative energy can only rise as fast as the meter's rated power
// allows (plus slack for the register's 1 Wh resolution). Anything else is a
// corrupt frame -- or a register reset, which is accepted only once the same
// new value has been read this many times in a row.
constexpr float kMaxEnergyRiseKw = 30.0f;
constexpr float kEnergySlackKwh = 0.002f;
constexpr uint8_t kEnergyResetConfirmReads = 3;
constexpr uint32_t kCloudTaskStackBytes = 16384; // TLS handshake needs headroom
constexpr size_t kMaxPendingEvents = 16;
constexpr uint8_t kMaxEventAttempts = 5;

struct OffRequest {
    int channel;
    char commandId[40];
};

struct OffEvent {
    int channel;
    char reason[16];
    char triggeredBy[8];
    PzemReading reading;
    char commandId[40]; // empty unless this trip fulfils an off_commands row
};

SupabaseClient sb(config::kSupabaseUrl, config::kSupabaseServiceKey);
HardwareSerial pzemSerial(config::kPzemUartNum);
Mycila::PZEM pzems[4];
// Written by each meter's callback on pzemPollTask and consumed by loop().
// pzemLock guards the four fields below.
portMUX_TYPE pzemLock = portMUX_INITIALIZER_UNLOCKED;
Mycila::PZEM::Data pzemData[4];
Mycila::PZEM::EventType pzemEvent[4];
bool pzemFresh[4] = {false, false, false, false};
// Main task only.
uint16_t pzemFailures[4] = {0, 0, 0, 0}; // consecutive failed reads
uint32_t lastGoodReadMs[4] = {0, 0, 0, 0};
bool meterSilent[4] = {false, false, false, false};
uint8_t overcurrentStreak[4] = {0, 0, 0, 0}; // consecutive over-limit readings
// Energy sanity tracking (see energyPlausible).
bool haveEnergy[4] = {false, false, false, false};
float lastGoodEnergyKwh[4] = {0, 0, 0, 0};
uint32_t lastGoodEnergyMs[4] = {0, 0, 0, 0};
float pendingEnergyKwh[4] = {0, 0, 0, 0};
uint8_t pendingEnergyReads[4] = {0, 0, 0, 0};
uint32_t cooldownUntilMs[4] = {0, 0, 0, 0};
bool cooldownActive[4] = {false, false, false, false};

TaskHandle_t mainTask = nullptr;
RelayBank relays;

// stateMutex guards channelState and scheduler (loop() and cloudTask share
// them). Hold it only for short copies -- never across a relay pulse or a
// network call.
SemaphoreHandle_t stateMutex = nullptr;
Scheduler scheduler;
ChannelState channelState[5]; // index 0 unused, channels are 1-4
QueueHandle_t cmdQueue = nullptr;   // cloudTask -> loop(): OffRequest
QueueHandle_t eventQueue = nullptr; // loop() -> cloudTask: OffEvent

struct StateLock {
    StateLock() { xSemaphoreTake(stateMutex, portMAX_DELAY); }
    ~StateLock() { xSemaphoreGive(stateMutex); }
};

bool inCooldown(int index) {
    if (!cooldownActive[index]) return false;
    if ((int32_t)(millis() - cooldownUntilMs[index]) < 0) return true;
    cooldownActive[index] = false;
    return false;
}

void turnOffChannel(int channelNumber, const char *reason, const char *triggeredBy,
                    const char *commandId = "") {
    Serial.printf("[SAFETY] Turning OFF channel %d | Reason: %s\n", channelNumber, reason);
    // The relay pulse comes first and never waits on anything else.
    relays.pulse(channelNumber);

    OffEvent event = {};
    event.channel = channelNumber;
    strlcpy(event.reason, reason, sizeof(event.reason));
    strlcpy(event.triggeredBy, triggeredBy, sizeof(event.triggeredBy));
    strlcpy(event.commandId, commandId, sizeof(event.commandId));
    {
        // breakerOn is deliberately left alone: the reported status comes only
        // from what the meter measures, never from having pulsed the relay.
        StateLock lock;
        ChannelState &state = channelState[channelNumber];
        event.reading = state.reading;
        if (strcmp(reason, "Manual Off") == 0) {
            state.offCause = OffCause::Manual;
        } else if (strcmp(reason, "Scheduled Off") == 0) {
            state.offCause = OffCause::Scheduled;
        } else {
            state.offCause = OffCause::None;
        }
    }
    cooldownUntilMs[channelNumber - 1] = millis() + kTripCooldownMs;
    cooldownActive[channelNumber - 1] = true;

    // Logging to the cloud is best-effort and happens on cloudTask.
    if (xQueueSend(eventQueue, &event, 0) != pdTRUE) {
        Serial.println("[CLOUD] off-event queue full, event dropped");
    }
}

PzemReading toReading(const Mycila::PZEM::Data &data) {
    PzemReading reading;
    reading.voltage = data.voltage;
    reading.current = data.current;
    reading.power = data.activePower;
    reading.energy = data.activeEnergy / 1000.0f; // Wh -> kWh
    reading.frequency = data.frequency;
    reading.power_factor = data.powerFactor;
    return reading;
}

bool isPlausible(const PzemReading &r) {
    return r.voltage >= 0 && r.voltage <= kMaxPlausibleVoltageV && r.current >= 0 &&
           r.current <= kMaxPlausibleCurrentA && r.power >= 0 && r.power <= kMaxPlausiblePowerW &&
           (r.frequency == 0 || (r.frequency >= 45 && r.frequency <= 65)) && r.power_factor >= 0 &&
           r.power_factor <= 1.05f;
}

// Guards the cumulative energy register. The meter library only checks for
// impossible jumps against its previous value, and clears that value after
// every failed read -- so on a noisy shared bus a corrupt energy figure gets
// through exactly when it is most likely, and one such value in
// channel_history would corrupt a whole month's consumption. Main task only.
bool energyPlausible(int i, float kwh) {
    if (!(kwh >= 0 && kwh <= kMaxPlausibleEnergyKwh)) return false;

    const uint32_t now = millis();
    if (!haveEnergy[i]) { // first reading since boot: nothing to compare with
        haveEnergy[i] = true;
        lastGoodEnergyKwh[i] = kwh;
        lastGoodEnergyMs[i] = now;
        return true;
    }

    const float elapsedH = (now - lastGoodEnergyMs[i]) / 3600000.0f;
    const float rise = kwh - lastGoodEnergyKwh[i];
    if (rise >= 0 && rise <= kMaxEnergyRiseKw * elapsedH + kEnergySlackKwh) {
        pendingEnergyReads[i] = 0;
        lastGoodEnergyKwh[i] = kwh;
        lastGoodEnergyMs[i] = now;
        return true;
    }

    // A drop or an impossible jump. Reject it, unless the same new value
    // keeps coming back -- then the register really did change (reset).
    if (pendingEnergyReads[i] > 0 && fabsf(kwh - pendingEnergyKwh[i]) < 0.0015f) {
        pendingEnergyReads[i]++;
    } else {
        pendingEnergyKwh[i] = kwh;
        pendingEnergyReads[i] = 1;
    }
    if (pendingEnergyReads[i] >= kEnergyResetConfirmReads) {
        Serial.printf("[PZEM] ch %d energy register changed %.3f -> %.3f kWh, accepted after %u identical reads\n",
                      i + 1, lastGoodEnergyKwh[i], kwh, (unsigned)pendingEnergyReads[i]);
        pendingEnergyReads[i] = 0;
        lastGoodEnergyKwh[i] = kwh;
        lastGoodEnergyMs[i] = now;
        return true;
    }
    return false;
}

// Reads the meters strictly one at a time: send a request, wait for its reply
// (or the library's timeout), pause, then move to the next meter. The four
// meters' TX lines are tied together, so overlapping requests would collide
// on the bus.
void pzemPollTask(void *) {
    esp_task_wdt_add(NULL);
    while (true) {
        esp_task_wdt_reset();
        for (int i = 0; i < 4; i++) {
            if (pzems[i].isEnabled()) pzems[i].read();
            vTaskDelay(pdMS_TO_TICKS(config::kPzemGapMs));
        }
    }
}

void runSafetyChecks() {
    // Off commands the cloud task fetched from the app.
    OffRequest request;
    while (xQueueReceive(cmdQueue, &request, 0) == pdTRUE) {
        turnOffChannel(request.channel, "Manual Off", "admin", request.commandId);
        esp_task_wdt_reset();
    }

    for (int channelNumber = 1; channelNumber <= 4; channelNumber++) {
        const int i = channelNumber - 1;
        if (!pzems[i].isEnabled()) continue; // reported once at boot

        // Snapshot what the callback delivered since the last pass.
        Mycila::PZEM::Data data;
        Mycila::PZEM::EventType event;
        bool fresh;
        portENTER_CRITICAL(&pzemLock);
        fresh = pzemFresh[i];
        pzemFresh[i] = false;
        data = pzemData[i];
        event = pzemEvent[i];
        portEXIT_CRITICAL(&pzemLock);

        const PzemReading reading = toReading(data);
        const bool replied = fresh && event == Mycila::PZEM::EventType::EVT_READ;
        const bool plausible = replied && isPlausible(reading) && energyPlausible(i, reading.energy);

        if (plausible) {
            pzemFailures[i] = 0;
            lastGoodReadMs[i] = millis();
            meterSilent[i] = false;

            bool breakerReset = false;
            bool allZero = false;
            bool overcurrent = false;
            {
                StateLock lock;
                ChannelState &state = channelState[channelNumber];
                state.reading = reading;
                state.hasReading = true;

                // Status follows the sensor only. Voltage present -> ON.
                // Checked before overcurrent so a channel that is already
                // live at boot (state defaults to OFF) is protected from its
                // first reading.
                if (!state.breakerOn && reading.voltage > config::kResetVoltageThresholdV) {
                    state.breakerOn = true;
                    state.overcurrentTripped = false;
                    state.offCause = OffCause::None;
                    breakerReset = true;
                }

                // Every value zero: nothing is energised downstream, so the
                // channel is OFF (e.g. the breaker was switched off by hand).
                if (state.breakerOn && reading.voltage == 0 && reading.current == 0 &&
                    reading.power == 0 && reading.frequency == 0 && reading.power_factor == 0) {
                    state.breakerOn = false;
                    allZero = true;
                }

                if (state.breakerOn && reading.current > config::kCurrentLimitA) {
                    if (overcurrentStreak[i] < 255) overcurrentStreak[i]++;
                } else {
                    overcurrentStreak[i] = 0;
                }
                overcurrent = overcurrentStreak[i] >= kOvercurrentConfirmReads && !inCooldown(i);
                if (overcurrent) {
                    state.overcurrentTripped = true;
                    state.tripCurrentA = reading.current;
                }
            }
            if (breakerReset) {
                Serial.printf("[SYSTEM] Breaker reset on channel %d\n", channelNumber);
            }
            if (allZero) {
                Serial.printf("[SYSTEM] Channel %d reads zero on every value, status OFF\n", channelNumber);
            }
            if (overcurrent) {
                Serial.printf("[SAFETY] ch %d overcurrent confirmed: %.2f A > %.1f A (%u reads)\n",
                              channelNumber, reading.current, config::kCurrentLimitA,
                              (unsigned)overcurrentStreak[i]);
                overcurrentStreak[i] = 0;
                turnOffChannel(channelNumber, "Overcurrent", "system");
            }
        } else if (fresh) {
            overcurrentStreak[i] = 0; // a bad frame breaks the run of confirmations
            // Report the first failure of a streak, then every 30th, so a
            // dead meter doesn't flood the console.
            if (++pzemFailures[i] == 1 || pzemFailures[i] % 30 == 0) {
                const char *why = event == Mycila::PZEM::EventType::EVT_READ_TIMEOUT ? "timeout"
                                  : replied                                          ? "implausible values (corrupt frame)"
                                                                                     : "bad response";
                Serial.printf("[PZEM] Error ch %d: %s addr=%u (x%u)", channelNumber, why,
                              config::kPzemAddresses[i], (unsigned)pzemFailures[i]);
                if (replied) {
                    Serial.printf(" V=%.1f I=%.3f P=%.1f E=%.3f", reading.voltage, reading.current,
                                  reading.power, reading.energy);
                }
                Serial.println();
            }
        }

        // Time-based rather than counting failures: this also catches a
        // poll task that has stopped delivering events altogether. A silent
        // meter reads as zeros, so the channel is reported OFF; its
        // cumulative energy is kept.
        if (!meterSilent[i] && millis() - lastGoodReadMs[i] > kMeterStaleMs) {
            meterSilent[i] = true;
            overcurrentStreak[i] = 0;
            {
                StateLock lock;
                clearLiveValues(channelState[channelNumber].reading);
                channelState[channelNumber].breakerOn = false;
            }
            Serial.printf("[PZEM] ch %d silent for >%us, live values cleared, status OFF\n", channelNumber,
                          (unsigned)(kMeterStaleMs / 1000));
        }
    }

    // Local schedules (work offline from the last cached copy).
    std::vector<int> due;
    {
        StateLock lock;
        due = scheduler.dueChannels();
    }
    for (int channelNumber : due) {
        bool on;
        {
            StateLock lock;
            on = channelState[channelNumber].breakerOn;
        }
        // A silent meter reports OFF because its state is unknown, not because
        // it was measured to be off -- still pulse for the schedule.
        if (on || meterSilent[channelNumber - 1]) {
            turnOffChannel(channelNumber, "Scheduled Off", "system");
        }
    }
}

// --- cloud task ------------------------------------------------------------

struct PendingEvent {
    OffEvent event;
    uint8_t attempts;
    bool logged;
};

class CloudSync {
  public:
    void step() {
        // Always pumped, connected or not: it also polls the serial console
        // for "wifireset" and drives the setup portal's web server, neither
        // of which can be skipped just because the link is currently up.
        wifi_manager::ensureConnected();
        if (!wifi_manager::isConnected()) {
            return;
        }
        if (!clockIsSet()) {
            waitForClock();
            return;
        }

        const uint32_t now = millis();
        if (started_ && now - lastSyncMs_ < config::kLoopIntervalMs) return;
        started_ = true;
        lastSyncMs_ = now;

        // Feed the watchdog between every network call: each one can block for
        // several seconds on a bad link.
        if (!registered_) {
            registered_ = sb.ensureDevice(config::kDeviceId, config::kDeviceName, config::kFirmwareVersion);
            if (registered_) Serial.println("[CLOUD] Device registered");
            esp_task_wdt_reset();
            return; // channel rows reference the device row
        }

        fetchOffCommands();
        esp_task_wdt_reset();

        flushOffEvents();

        ChannelState snapshot[5];
        {
            StateLock lock;
            for (int i = 0; i < 5; i++) snapshot[i] = channelState[i];
        }
        sb.upsertChannels(config::kDeviceId, snapshot);
        esp_task_wdt_reset();
        sb.insertChannelHistory(config::kDeviceId, snapshot);
        esp_task_wdt_reset();

        if (!haveSchedules_ || now - lastScheduleMs_ >= config::kScheduleRefreshMs) {
            std::vector<ScheduleEntry> schedules;
            if (sb.fetchSchedules(config::kDeviceId, schedules)) {
                StateLock lock;
                scheduler.refresh(std::move(schedules));
                haveSchedules_ = true;
                lastScheduleMs_ = now;
            }
            // On failure keep the previous copy: schedules must keep working
            // offline.
            esp_task_wdt_reset();
        }

        if (now - lastHeartbeatMs_ >= config::kHeartbeatMs) {
            if (sb.heartbeat(config::kDeviceId)) lastHeartbeatMs_ = now;
            esp_task_wdt_reset();
        }
    }

  private:
    bool started_ = false;
    bool registered_ = false;
    bool haveSchedules_ = false;
    bool sntpStarted_ = false;
    bool clockWasSet_ = false;
    uint32_t lastSyncMs_ = 0;
    uint32_t lastScheduleMs_ = 0;
    uint32_t lastHeartbeatMs_ = 0;
    std::vector<PendingEvent> pending_;
    // Command ids handed to loop() but not yet marked completed; stops the
    // same still-'pending' row from being fetched and executed twice.
    std::vector<String> inFlight_;

    void waitForClock() {
        if (!sntpStarted_) {
            Serial.println("[NTP] Syncing time...");
            // SNTP keeps re-syncing hourly on its own after this.
            configTime(0, 0, "pool.ntp.org", "time.nist.gov");
            sntpStarted_ = true;
        }
        struct tm timeinfo;
        getLocalTime(&timeinfo, 2000); // blocks up to 2s waiting for SNTP
        if (clockIsSet() && !clockWasSet_) {
            clockWasSet_ = true;
            Serial.printf("[NTP] Success: %04d-%02d-%02d %02d:%02d:%02d UTC\n", timeinfo.tm_year + 1900,
                          timeinfo.tm_mon + 1, timeinfo.tm_mday, timeinfo.tm_hour, timeinfo.tm_min,
                          timeinfo.tm_sec);
        }
    }

    bool isInFlight(const String &id) const {
        for (const String &s : inFlight_) {
            if (s == id) return true;
        }
        return false;
    }

    void fetchOffCommands() {
        std::vector<OffCommand> commands;
        if (!sb.fetchPendingOffCommands(config::kDeviceId, commands)) return;
        for (const OffCommand &cmd : commands) {
            if (isInFlight(cmd.id)) continue;
            OffRequest request = {};
            request.channel = cmd.channel;
            strlcpy(request.commandId, cmd.id.c_str(), sizeof(request.commandId));
            if (xQueueSend(cmdQueue, &request, 0) == pdTRUE) {
                if (inFlight_.size() >= 32) inFlight_.erase(inFlight_.begin());
                inFlight_.push_back(cmd.id);
            }
        }
    }

    // Uploads the off_logs row for each trip and marks fulfilled commands
    // completed. Stops at the first failure (the network is probably down)
    // and retries next tick; an event that keeps failing is eventually
    // dropped so a permanently rejected row can't block the rest.
    void flushOffEvents() {
        OffEvent event;
        while (xQueueReceive(eventQueue, &event, 0) == pdTRUE) {
            if (pending_.size() >= kMaxPendingEvents) pending_.erase(pending_.begin());
            pending_.push_back({event, 0, false});
        }

        while (!pending_.empty()) {
            PendingEvent &p = pending_.front();
            if (!p.logged) {
                p.logged = sb.logOffEvent(config::kDeviceId, p.event.channel, p.event.reason,
                                          p.event.reading, p.event.triggeredBy);
                esp_task_wdt_reset();
            }
            bool done = p.logged;
            if (done && p.event.commandId[0] != '\0') {
                const String commandId(p.event.commandId);
                done = sb.completeOffCommand(commandId);
                esp_task_wdt_reset();
                if (done) {
                    for (size_t k = 0; k < inFlight_.size(); k++) {
                        if (inFlight_[k] == commandId) {
                            inFlight_.erase(inFlight_.begin() + k);
                            break;
                        }
                    }
                }
            }
            if (!done && ++p.attempts < kMaxEventAttempts) break;
            if (!done) Serial.println("[CLOUD] giving up on an off-event after repeated failures");
            pending_.erase(pending_.begin());
        }
    }
};

void cloudTask(void *) {
    esp_task_wdt_add(NULL);
    CloudSync sync;
    while (true) {
        esp_task_wdt_reset();
        sync.step();
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

// Owns the LCD. Runs at the lowest priority and only reads a snapshot of
// channelState, so a slow or missing display can never delay a trip.
void displayTask(void *) {
    lcd_display::begin();
    vTaskDelay(pdMS_TO_TICKS(config::kLcdIntroMs));
    while (true) {
        ChannelState snapshot[5];
        {
            StateLock lock;
            for (int i = 0; i < 5; i++) snapshot[i] = channelState[i];
        }
        lcd_display::showChannels(snapshot);
        vTaskDelay(pdMS_TO_TICKS(config::kLcdRefreshMs));
    }
}

} // namespace

const char *resetReasonName(esp_reset_reason_t reason) {
    switch (reason) {
    case ESP_RST_POWERON: return "power-on";
    case ESP_RST_SW: return "software";
    case ESP_RST_PANIC: return "panic/crash";
    case ESP_RST_INT_WDT: return "interrupt watchdog";
    case ESP_RST_TASK_WDT: return "task watchdog";
    case ESP_RST_WDT: return "other watchdog";
    case ESP_RST_BROWNOUT: return "brownout (power sag)";
    case ESP_RST_EXT: return "EN pin";
    default: return "other";
    }
}

void setup() {
    Serial.begin(115200);
    // A reboot looks like "WiFi reconnecting" from outside; this tells them apart.
    Serial.printf("[BOOT] reset reason: %s\n", resetReasonName(esp_reset_reason()));

    // First, before anything slow: these pins drive breaker-trip coils and
    // float until configured.
    relays.begin(config::kRelayPins, config::kRelayActiveHigh, config::kRelayPulseMs);

    esp_task_wdt_init(kWdtTimeoutS, true);
    esp_task_wdt_add(NULL);
    mainTask = xTaskGetCurrentTaskHandle();
    // Outrank cloudTask (same core) so a trip is never delayed by TLS work;
    // loop() sleeps between meter readings so this doesn't starve it.
    vTaskPrioritySet(nullptr, 2);

    stateMutex = xSemaphoreCreateMutex();
    cmdQueue = xQueueCreate(8, sizeof(OffRequest));
    eventQueue = xQueueCreate(kMaxPendingEvents, sizeof(OffEvent));

    // Started before the WiFi connect below so the intro shows during it.
    xTaskCreatePinnedToCore(displayTask, "display", 4096, nullptr, 1, nullptr, 1);

    // Blocks briefly (up to ~10s) trying the last saved network; falls back
    // to a non-blocking setup portal if that fails or none is saved yet --
    // see wifi_manager.h. Relay pins are already set safe (relays.begin()
    // above) before this, and cloudTask/pzemPollTask below wait for the link.
    wifi_manager::begin();
    sb.begin();

    for (int i = 0; i < 4; i++) {
        lastGoodReadMs[i] = millis();
        pzems[i].setSharedSerial(true);
        // Runs on pzemPollTask: store + wake loop() only. The relay pulse
        // blocks, so it stays on the main task.
        pzems[i].setCallback([i](Mycila::PZEM::EventType type, const Mycila::PZEM::Data &data) {
            portENTER_CRITICAL(&pzemLock);
            pzemEvent[i] = type;
            pzemData[i] = data;
            pzemFresh[i] = true;
            portEXIT_CRITICAL(&pzemLock);
            if (mainTask) xTaskNotifyGive(mainTask);
        });
        // async=false: no library task and no startup probe; pzemPollTask below
        // does the reads, so only one request is ever on the shared bus.
        pzems[i].begin(pzemSerial, config::kPzemRxPin, config::kPzemTxPin, config::kPzemAddresses[i], false);
        if (!pzems[i].isEnabled()) {
            Serial.printf("[PZEM] ch %d: begin() failed (addr=%u), channel will not be monitored\n", i + 1,
                          config::kPzemAddresses[i]);
        }
    }
    xTaskCreatePinnedToCore(pzemPollTask, "pzemPoll", 4096, nullptr, 1, nullptr, 0);
    xTaskCreatePinnedToCore(cloudTask, "cloud", kCloudTaskStackBytes, nullptr, 1, nullptr, 1);
}

void loop() {
    esp_task_wdt_reset();

    runSafetyChecks();

    // Sleep until a PZEM callback wakes us; the timeout keeps the watchdog fed
    // and schedules/commands ticking when no meter is responding.
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(kSafetyLoopDelayMs));
}
