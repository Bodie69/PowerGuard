#include "supabase_client.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <time.h>

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
} // namespace

SupabaseClient::SupabaseClient(const char *url, const char *serviceKey) : _apiKey(serviceKey) {
    _base = String(url);
    while (_base.endsWith("/")) {
        _base.remove(_base.length() - 1);
    }
    _base += "/rest/v1/";
    // Matches the original firmware's TLS posture (no cert pinning) --
    // ESP32's WiFiClientSecure has no CA bundle for Supabase pre-loaded.
    _client.setInsecure();
}

String SupabaseClient::request(const char *method, const String &path, const String &query,
                                const String &body, const char *prefer, bool &ok) {
    ok = false;
    String url = _base + path;
    if (query.length() > 0) {
        url += "?" + query;
    }

    HTTPClient http;
    if (!http.begin(_client, url)) {
        Serial.println("Supabase: begin() failed");
        return "";
    }
    http.addHeader("apikey", _apiKey);
    http.addHeader("Authorization", "Bearer " + _apiKey);
    http.addHeader("Content-Type", "application/json");
    if (prefer != nullptr) {
        http.addHeader("Prefer", prefer);
    }

    int status = http.sendRequest(method, body.length() > 0 ? (uint8_t *)body.c_str() : nullptr,
                                    body.length());
    String responseBody = http.getString();
    http.end();

    if (status < 0) {
        Serial.printf("Supabase %s %s -> transport error %d\n", method, path.c_str(), status);
        return "";
    }
    if (status >= 400) {
        Serial.printf("Supabase %s %s -> %d: %s\n", method, path.c_str(), status,
                       responseBody.c_str());
        return "";
    }
    ok = true;
    return responseBody;
}

void SupabaseClient::ensureDevice(const char *deviceId, const char *deviceName,
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
}

void SupabaseClient::heartbeat(const char *deviceId) {
    JsonDocument doc;
    doc["status"] = "online";
    doc["last_seen"] = nowIso();
    String body;
    serializeJson(doc, body);
    bool ok;
    request("PATCH", "devices", "id=eq." + String(deviceId), body, nullptr, ok);
}

void SupabaseClient::upsertChannels(const char *deviceId, const ChannelState channelState[5]) {
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    String ts = nowIso();
    for (int channelNumber = 1; channelNumber <= 4; channelNumber++) {
        const ChannelState &state = channelState[channelNumber];
        JsonObject obj = arr.add<JsonObject>();
        obj["device_id"] = deviceId;
        obj["channel_number"] = channelNumber;
        obj["voltage"] = state.reading.voltage;
        obj["current"] = state.reading.current;
        obj["power"] = state.reading.power;
        obj["energy"] = state.reading.energy;
        obj["frequency"] = state.reading.frequency;
        obj["power_factor"] = state.reading.power_factor;
        obj["breaker_status"] = state.breakerStatus;
        obj["updated_at"] = ts;
    }
    String body;
    serializeJson(doc, body);
    bool ok;
    request("POST", "channels", "on_conflict=device_id,channel_number", body,
            "resolution=merge-duplicates", ok);
}

std::vector<OffCommand> SupabaseClient::fetchPendingOffCommands(const char *deviceId) {
    std::vector<OffCommand> result;
    String query = "device_id=eq." + String(deviceId) + "&status=eq.pending&select=id,channel";
    bool ok;
    String body = request("GET", "off_commands", query, "", nullptr, ok);
    if (!ok || body.length() == 0) {
        return result;
    }
    JsonDocument doc;
    if (deserializeJson(doc, body) != DeserializationError::Ok || !doc.is<JsonArray>()) {
        return result;
    }
    for (JsonObject obj : doc.as<JsonArray>()) {
        OffCommand cmd;
        cmd.id = obj["id"].as<String>();
        cmd.channel = obj["channel"].as<int>();
        result.push_back(cmd);
    }
    return result;
}

void SupabaseClient::completeOffCommand(const String &commandId) {
    JsonDocument doc;
    doc["status"] = "completed";
    doc["processed_at"] = nowIso();
    String body;
    serializeJson(doc, body);
    bool ok;
    request("PATCH", "off_commands", "id=eq." + commandId, body, nullptr, ok);
}

std::vector<ScheduleEntry> SupabaseClient::fetchSchedules(const char *deviceId) {
    std::vector<ScheduleEntry> result;
    String query = "device_id=eq." + String(deviceId) + "&select=*";
    bool ok;
    String body = request("GET", "off_schedules", query, "", nullptr, ok);
    if (!ok || body.length() == 0) {
        return result;
    }
    JsonDocument doc;
    if (deserializeJson(doc, body) != DeserializationError::Ok || !doc.is<JsonArray>()) {
        return result;
    }
    for (JsonObject obj : doc.as<JsonArray>()) {
        ScheduleEntry entry;
        entry.id = obj["id"].as<String>();
        entry.channel = obj["channel"].as<int>();
        entry.enabled = obj["enabled"].isNull() ? true : obj["enabled"].as<bool>();
        entry.offTime = obj["off_time"].isNull() ? "" : obj["off_time"].as<String>();
        if (!obj["days"].isNull()) {
            for (JsonVariant d : obj["days"].as<JsonArray>()) {
                entry.days.push_back(d.as<String>());
            }
        }
        result.push_back(entry);
    }
    return result;
}

void SupabaseClient::logOffEvent(const char *deviceId, int channelNumber, const char *reason,
                                  const ChannelState &state, const char *triggeredBy) {
    JsonDocument doc;
    doc["device_id"] = deviceId;
    doc["channel"] = channelNumber;
    doc["reason"] = reason;
    doc["voltage"] = state.reading.voltage;
    doc["current"] = state.reading.current;
    doc["power"] = state.reading.power;
    doc["triggered_by"] = triggeredBy;
    String body;
    serializeJson(doc, body);
    bool ok;
    request("POST", "off_logs", "", body, nullptr, ok);
}
