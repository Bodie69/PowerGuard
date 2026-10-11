#pragma once

#include <Arduino.h>
#include <WiFiClientSecure.h>
#include <vector>

#include "channel_state.h"
#include "scheduler.h"

struct OffCommand {
    String id;
    int channel = 0;
};

// Every call returns true only if the server accepted the request. Callers
// decide whether to retry; none of them may be made while holding a lock or
// from the safety loop, since one call can block for up to ~17s.
//
// Not thread-safe: use from a single task.
class SupabaseClient {
  public:
    SupabaseClient(const char *url, const char *serviceKey);

    // Configures TLS; call once before the first request. Certificates are
    // validated against the current time, so requests fail until NTP has set
    // the clock.
    void begin();

    bool ensureDevice(const char *deviceId, const char *deviceName, const char *firmwareVersion);
    bool heartbeat(const char *deviceId);
    // Channels whose meter has never answered are reported as zeros / OFF
    // without touching their stored `energy`.
    bool upsertChannels(const char *deviceId, const ChannelState channelState[5]);
    bool insertChannelHistory(const char *deviceId, const ChannelState channelState[5]);
    bool fetchPendingOffCommands(const char *deviceId, std::vector<OffCommand> &out);
    bool completeOffCommand(const String &commandId);
    // `out` is only modified on success, so a failed fetch can't be mistaken
    // for "no schedules".
    bool fetchSchedules(const char *deviceId, std::vector<ScheduleEntry> &out);
    bool logOffEvent(const char *deviceId, int channelNumber, const char *reason,
                      const PzemReading &reading, const char *triggeredBy);

  private:
    String _base;
    String _apiKey;
    WiFiClientSecure _client;

    // Returns the response body. `ok` is false on a transport error or an
    // HTTP status >= 400 (the error is logged); the body is then empty.
    String request(const char *method, const String &path, const String &query,
                    const String &body, const char *prefer, bool &ok);
};
