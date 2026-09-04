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

class SupabaseClient {
  public:
    SupabaseClient(const char *url, const char *serviceKey);

    void ensureDevice(const char *deviceId, const char *deviceName, const char *firmwareVersion);
    void heartbeat(const char *deviceId);
    void upsertChannels(const char *deviceId, const ChannelState channelState[5]);
    std::vector<OffCommand> fetchPendingOffCommands(const char *deviceId);
    void completeOffCommand(const String &commandId);
    std::vector<ScheduleEntry> fetchSchedules(const char *deviceId);
    void logOffEvent(const char *deviceId, int channelNumber, const char *reason,
                      const ChannelState &state, const char *triggeredBy);

  private:
    String _base;
    String _apiKey;
    WiFiClientSecure _client;

    // Returns the parsed JSON response body (empty string body -> null doc).
    // On transport/HTTP error, prints a message and returns an empty String
    // via `ok` = false; callers should treat that as "this call failed,
    // try again next tick" -- matching the original firmware's bare
    // `try/except: pass` around every cloud call.
    String request(const char *method, const String &path, const String &query,
                    const String &body, const char *prefer, bool &ok);
};
