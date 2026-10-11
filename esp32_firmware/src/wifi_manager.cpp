#include "wifi_manager.h"

#include <WiFi.h>
#include <WiFiManager.h>

#include "config.h"

namespace wifi_manager {

namespace {
// Bounds the one blocking step: trying the last saved network before
// falling back to the (non-blocking) setup portal. setConfigPortalTimeout
// is intentionally not used -- WiFiManager ignores it in non-blocking mode,
// and closing the portal on its own with no other way onto the network
// would just leave the device both offline and unreachable to reconfigure.
constexpr uint32_t kConnectTimeoutS = 10;

WiFiManager wm;
uint32_t connectedAtMs = 0; // 0 while not connected
bool portalActive = false;
String serialLine;

void onGotIp(WiFiEvent_t, WiFiEventInfo_t) {
    connectedAtMs = millis();
    Serial.printf("[WIFI] connected: %s RSSI=%d dBm ch=%d\n", WiFi.localIP().toString().c_str(),
                  (int)WiFi.RSSI(), (int)WiFi.channel());
}

void onDisconnected(WiFiEvent_t, WiFiEventInfo_t info) {
    const uint8_t reason = info.wifi_sta_disconnected.reason;
    Serial.printf("[WIFI] disconnected, reason=%u (%s), was up %us\n", (unsigned)reason,
                  WiFi.disconnectReasonName((wifi_err_reason_t)reason),
                  connectedAtMs ? (unsigned)((millis() - connectedAtMs) / 1000) : 0u);
    connectedAtMs = 0;
}

void onPortalStart(WiFiManager *) {
    portalActive = true;
    Serial.printf("[WIFI] setup portal open -- connect to WiFi \"%s\" (password \"%s\") and open "
                  "http://192.168.4.1 to enter your network's SSID/password\n",
                  config::kWifiSetupApName, config::kWifiSetupApPassword);
}

void onSaveConfig() {
    portalActive = false;
    Serial.println("[WIFI] new credentials saved, connecting...");
}

// Lets "wifireset" typed into the serial console (e.g. via `pio device
// monitor`) erase the saved network and reopen the setup portal, without
// needing a spare GPIO for a physical reset button.
void pollSerialCommand() {
    while (Serial.available()) {
        char c = (char)Serial.read();
        if (c == '\n' || c == '\r') {
            if (serialLine == "wifireset") resetCredentials();
            serialLine = "";
        } else if (serialLine.length() < 32) {
            serialLine += c;
        }
    }
}
} // namespace

void begin() {
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    // Modem power-save (the default) makes the radio sleep between beacons;
    // phone hotspots often drop or stall such clients every few minutes.
    // Mains-powered device, so the extra draw doesn't matter.
    WiFi.setSleep(false);
    WiFi.onEvent(onGotIp, ARDUINO_EVENT_WIFI_STA_GOT_IP);
    WiFi.onEvent(onDisconnected, ARDUINO_EVENT_WIFI_STA_DISCONNECTED);

    wm.setConfigPortalBlocking(false); // ensureConnected() pumps the portal from cloudTask
    wm.setConnectTimeout(kConnectTimeoutS);
    wm.setAPCallback(onPortalStart);
    wm.setSaveConfigCallback(onSaveConfig);

    // Tries the last saved network for up to kConnectTimeoutS. On failure --
    // or on first boot, with nothing saved yet -- starts the setup portal,
    // which (setConfigPortalBlocking(false) above) returns immediately;
    // ensureConnected() takes it from there.
    wm.autoConnect(config::kWifiSetupApName, config::kWifiSetupApPassword);
}

void ensureConnected() {
    pollSerialCommand();
    wm.process();
}

bool isConnected() {
    return WiFi.status() == WL_CONNECTED;
}

bool isPortalActive() {
    return portalActive;
}

void resetCredentials() {
    Serial.println("[WIFI] resetting saved credentials, reopening setup portal");
    wm.resetSettings();
    portalActive = false;
    wm.startConfigPortal(config::kWifiSetupApName, config::kWifiSetupApPassword);
}

} // namespace wifi_manager
