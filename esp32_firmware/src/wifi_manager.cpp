#include "wifi_manager.h"

#include <WiFi.h>

#include "config.h"

namespace wifi_manager {

bool connect(uint32_t timeoutMs) {
    if (WiFi.status() == WL_CONNECTED) {
        return true;
    }
    WiFi.mode(WIFI_STA);
    WiFi.begin(config::kWifiSsid, config::kWifiPassword);

    uint32_t start = millis();
    while (WiFi.status() != WL_CONNECTED) {
        if (millis() - start > timeoutMs) {
            Serial.println("WiFi connect timeout");
            return false;
        }
        delay(200);
    }
    Serial.print("WiFi connected: ");
    Serial.println(WiFi.localIP());
    return true;
}

void ensureConnected() {
    if (WiFi.status() == WL_CONNECTED) {
        return;
    }
    if (!connect()) {
        Serial.println("WiFi reconnect failed");
    }
}

bool isConnected() {
    return WiFi.status() == WL_CONNECTED;
}

} // namespace wifi_manager
