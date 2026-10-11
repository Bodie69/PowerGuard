#include "supabase_client.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <esp_task_wdt.h>
#include <time.h>

// Mozilla root CA bundle embedded in the Arduino-ESP32 core (covers Google
// Trust Services / GlobalSign, which Supabase's certificate chains to).
extern const uint8_t rootca_crt_bundle_start[] asm("_binary_x509_crt_bundle_start");

namespace {
String nowIso() {
    time_t now = time(nullptr);
    struct tm utc;
    gmtime_r(&now, &utc);
    char buf[21];
    snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02dZ", utc.tm_year + 1900,
              utc.tm_mon + 1, utc.tm_mday, utc.tm_hour, utc.tm_min, utc.tm_sec);
    return String(buf);
}

void addReading(JsonObject obj, const PzemReading &r) {
    obj["voltage"] = r.voltage;
    obj["current"] = r.current;
    obj["power"] = r.power;
    obj["energy"] = r.energy;
    obj["frequency"] = r.frequency;
    obj["power_factor"] = r.power_factor;
}
} // namespace

SupabaseClient::SupabaseClient(const char *url, const char *serviceKey) : _apiKey(serviceKey) {
    _base = String(url);
    while (_base.endsWith("/")) {
        _base.remove(_base.length() - 1);
    }
    _base += "/rest/v1/";
}

void SupabaseClient::begin() {
    // The service_role key travels in every request, so the server's identity
    // must be verified -- otherwise anyone on the WiFi path could impersonate
    // Supabase and read the key.
    _client.setCACertBundle(rootca_crt_bundle_start);
    // WiFiClientSecure's TLS handshake timeout defaults to 120s and is NOT
    // governed by HTTPClient::setTimeout()/setConnectTimeout() below -- on a
    // weak/slow link it can block a single request far past kWdtTimeoutS
    // (main.cpp) with nothing feeding the watchdog. Bound it well
    // under that so a bad handshake fails fast instead of hanging the task.
    _client.setHandshakeTimeout(5);
}

String SupabaseClient::request(const char *method, const String &path, const String &query,
                                const String &body, const char *prefer, bool &ok) {
    ok = false;
    String url = _base + path;
    if (query.length() > 0) {
        url += "?" + query;
    }

    // -1 (HTTPC_ERROR_CONNECTION_REFUSED) means the TCP/TLS connection was
    // never established, so nothing was sent and an immediate retry cannot
    // duplicate a POST. Any other transport error may have reached the server
    // and is not retried here.
    constexpr int kMaxAttempts = 2;
    int status = 0;
    String responseBody;
    for (int attempt = 1; attempt <= kMaxAttempts; attempt++) {
        HTTPClient http;
        if (!http.begin(_client, url)) {
            Serial.println("Supabase: begin() failed");
            return "";
        }
        // Bound each round-trip well under kWdtTimeoutS -- WiFiClientSecure's
        // default TLS handshake timeout can otherwise run far longer than that
        // on a weak/slow link, and the cloud task makes several of these calls
        // back-to-back.
        // Read timeout is longer than connect: Supabase answers in ~0.3s from a
        // PC, but over a phone hotspot the reply can straggle past 4s (-11
        // HTTPC_ERROR_READ_TIMEOUT). Worst case per attempt is handshake 5s +
        // connect 4s + read 8s, which must stay under kWdtTimeoutS in main.cpp
        // (the watchdog is fed between attempts).
        http.setConnectTimeout(4000);
        http.setTimeout(8000);
        // Force a fresh connect() every call instead of keep-alive reuse. Each
        // request() here builds a new HTTPClient wrapping the same shared
        // _client socket; if the previous call's connection was kept open,
        // HTTPClient::connect() sees it as already connected and skips the
        // connect() path entirely -- which is the only place the timeouts above
        // get applied to the underlying socket. A stale/dropped keep-alive
        // connection then blocks on read/write with no timeout at all, past
        // kWdtTimeoutS, causing the watchdog reboot.
        http.setReuse(false);
        http.addHeader("apikey", _apiKey);
        http.addHeader("Authorization", "Bearer " + _apiKey);
        http.addHeader("Content-Type", "application/json");
        if (prefer != nullptr) {
            http.addHeader("Prefer", prefer);
        }

        status = http.sendRequest(method, body.length() > 0 ? (uint8_t *)body.c_str() : nullptr,
                                    body.length());
        responseBody = http.getString();
        http.end();

        if (status >= 0) {
            break;
        }
        char tlsError[80] = "";
        _client.lastError(tlsError, sizeof(tlsError));
        // Heap and signal strength tell memory pressure apart from a weak link.
        Serial.printf("Supabase %s %s -> transport error %d%s%s (attempt %d/%d) | heap free=%u "
                       "minFree=%u largest=%u | RSSI=%d dBm\n",
                       method, path.c_str(), status, tlsError[0] ? " | TLS: " : "", tlsError, attempt,
                       kMaxAttempts, (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getMinFreeHeap(),
                       (unsigned)ESP.getMaxAllocHeap(), (int)WiFi.RSSI());
        if (status != HTTPC_ERROR_CONNECTION_REFUSED || attempt == kMaxAttempts) {
            return "";
        }
        esp_task_wdt_reset();
    }
    if (status >= 400) {
        Serial.printf("Supabase %s %s -> %d: %s\n", method, path.c_str(), status,
                       responseBody.c_str());
        return "";
    }
    ok = true;
    return responseBody;
}

bool SupabaseClient::ensureDevice(const char *deviceId, const char *deviceName,
                                   const char *firmwareVersion) {
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    JsonObject obj = arr.add<JsonObject>();
    obj["id"] = deviceId;
    obj["device_name"] = deviceName;
    obj["status"] = "online";
    obj["firmware_version"] = firmwareVersion;
    obj["last_seen"] = nowIso();

    String body;
    serializeJson(doc, body);
    bool ok;
    request("POST", "devices", "on_conflict=id", body, "resolution=merge-duplicates", ok);
    return ok;
}

bool SupabaseClient::heartbeat(const char *deviceId) {
    JsonDocument doc;
    doc["status"] = "online";
    doc["last_seen"] = nowIso();
    String body;
    serializeJson(doc, body);
    bool ok;
    request("PATCH", "devices", "id=eq." + String(deviceId), body, nullptr, ok);
    return ok;
}

bool SupabaseClient::upsertChannels(const char *deviceId, const ChannelState channelState[5]) {
    String ts = nowIso();
    bool allOk = true;

    // Channels whose meter has answered: full row.
    JsonDocument metered;
    JsonArray meteredRows = metered.to<JsonArray>();
    // Channels whose meter has never answered since boot: status and live
    // values only. `energy` is left out of the payload entirely so the
    // upsert keeps the stored cumulative value instead of overwriting it
    // with 0. Sent as its own request because every object in one bulk
    // upsert must carry the same columns.
    JsonDocument unmetered;
    JsonArray unmeteredRows = unmetered.to<JsonArray>();

    for (int channelNumber = 1; channelNumber <= 4; channelNumber++) {
        const ChannelState &state = channelState[channelNumber];
        JsonObject obj = (state.hasReading ? meteredRows : unmeteredRows).add<JsonObject>();
        obj["device_id"] = deviceId;
        obj["channel_number"] = channelNumber;
        if (state.hasReading) {
            addReading(obj, state.reading);
        } else {
            obj["voltage"] = 0;
            obj["current"] = 0;
            obj["power"] = 0;
            obj["frequency"] = 0;
            obj["power_factor"] = 0;
        }
        obj["breaker_status"] = state.breakerStatus();
        obj["updated_at"] = ts;
    }

    for (JsonDocument *doc : {&metered, &unmetered}) {
        if (doc->as<JsonArray>().size() == 0) {
            continue;
        }
        String body;
        serializeJson(*doc, body);
        bool ok;
        request("POST", "channels", "on_conflict=device_id,channel_number", body,
                "resolution=merge-duplicates", ok);
        allOk = allOk && ok;
    }
    return allOk;
}

bool SupabaseClient::insertChannelHistory(const char *deviceId, const ChannelState channelState[5]) {
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    String ts = nowIso();
    for (int channelNumber = 1; channelNumber <= 4; channelNumber++) {
        const ChannelState &state = channelState[channelNumber];
        // A never-read channel would record energy = 0, which the monthly
        // consumption calculation would treat as the meter's real start/end.
        if (!state.hasReading) {
            continue;
        }
        JsonObject obj = arr.add<JsonObject>();
        obj["device_id"] = deviceId;
        obj["channel_number"] = channelNumber;
        addReading(obj, state.reading);
        obj["breaker_status"] = state.breakerStatus();
        obj["recorded_at"] = ts;
    }
    if (arr.size() == 0) {
        return true;
    }
    String body;
    serializeJson(doc, body);
    bool ok;
    // Plain insert, not upsert -- every call is a new row, unlike upsertChannels.
    request("POST", "channel_history", "", body, nullptr, ok);
    return ok;
}

bool SupabaseClient::fetchPendingOffCommands(const char *deviceId, std::vector<OffCommand> &out) {
    String query = "device_id=eq." + String(deviceId) + "&status=eq.pending&select=id,channel";
    bool ok;
    String body = request("GET", "off_commands", query, "", nullptr, ok);
    if (!ok) {
        return false;
    }
    JsonDocument doc;
    if (deserializeJson(doc, body) != DeserializationError::Ok || !doc.is<JsonArray>()) {
        return false;
    }
    for (JsonObject obj : doc.as<JsonArray>()) {
        OffCommand cmd;
        cmd.id = obj["id"].as<String>();
        cmd.channel = obj["channel"].as<int>();
        if (cmd.id.length() == 0 || cmd.channel < 1 || cmd.channel > 4) {
            continue;
        }
        out.push_back(cmd);
    }
    return true;
}

bool SupabaseClient::completeOffCommand(const String &commandId) {
    JsonDocument doc;
    doc["status"] = "completed";
    doc["processed_at"] = nowIso();
    String body;
    serializeJson(doc, body);
    bool ok;
    request("PATCH", "off_commands", "id=eq." + commandId, body, nullptr, ok);
    return ok;
}

bool SupabaseClient::fetchSchedules(const char *deviceId, std::vector<ScheduleEntry> &out) {
    String query = "device_id=eq." + String(deviceId) + "&select=*";
    bool ok;
    String body = request("GET", "off_schedules", query, "", nullptr, ok);
    if (!ok) {
        return false;
    }
    JsonDocument doc;
    if (deserializeJson(doc, body) != DeserializationError::Ok || !doc.is<JsonArray>()) {
        return false;
    }
    std::vector<ScheduleEntry> result;
    for (JsonObject obj : doc.as<JsonArray>()) {
        ScheduleEntry entry;
        entry.id = obj["id"].as<String>();
        entry.channel = obj["channel"].as<int>();
        entry.enabled = obj["enabled"].isNull() ? true : obj["enabled"].as<bool>();
        entry.offTime = obj["off_time"].isNull() ? "" : obj["off_time"].as<String>();
        if (obj["days"].is<JsonArray>()) {
            for (JsonVariant d : obj["days"].as<JsonArray>()) {
                entry.days.push_back(d.as<String>());
            }
        }
        result.push_back(entry);
    }
    out = std::move(result);
    return true;
}

bool SupabaseClient::logOffEvent(const char *deviceId, int channelNumber, const char *reason,
                                  const PzemReading &reading, const char *triggeredBy) {
    JsonDocument doc;
    doc["device_id"] = deviceId;
    doc["channel"] = channelNumber;
    doc["reason"] = reason;
    doc["voltage"] = reading.voltage;
    doc["current"] = reading.current;
    doc["power"] = reading.power;
    doc["triggered_by"] = triggeredBy;
    String body;
    serializeJson(doc, body);
    bool ok;
    request("POST", "off_logs", "", body, nullptr, ok);
    return ok;
}
