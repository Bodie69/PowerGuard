# PowerGuard IoT — ESP32 Firmware

Arduino/C++ (PlatformIO) firmware for the ESP32: reads 4x PZEM-004T V3.0
energy meters, uploads readings to Supabase, and pulses a 4-channel relay
module to turn off breakers (manual command, overcurrent, or schedule).
Remote ON is never supported — see `safety_requirements` in the project
spec.

## Wiring

- **PZEM-004T x4** share a single UART bus, wired to UART2 (default
  TX=GPIO14, RX=GPIO27, configurable in `config.h`) so UART0 stays free for
  the USB/serial console. All 4 meters' TX pins tied together, all 4 RX
  pins tied together. Each meter is given a unique Modbus RTU address (1-4)
  so only one drives the bus at a time when polled — see **Provisioning
  the PZEM meters** below. This is the standard approach for multi-PZEM
  setups, but note the TX lines are tied together directly; if you see bus
  contention/corruption in practice, isolate each meter's TX with a diode
  or use a proper RS-485 transceiver per meter instead.
- **4-channel relay module**: one GPIO per channel, default GPIO32/33/25/26
  (`kRelayPins` in `config.h`). These are chosen to avoid the ESP32's
  strapping pins (0, 2, 5, 12, 15 — sampled at boot to select flash/download
  mode; driving them externally can prevent the board from booting) and the
  input-only pins (34-39, no output driver). If you rewire to different
  GPIOs, avoid those ranges. Wire each relay's NO (normally open) contact
  in series with its shunt-trip coil's trigger circuit — firmware only ever
  pulses a relay for `kRelayPulseMs` (default 1000ms), never holds it
  energized, per the momentary-pulse safety requirement. Most cheap
  opto-isolated relay boards are **active-low** (`kRelayActiveHigh = false`
  by default) — check your board's datasheet/silkscreen and flip this if
  yours is active-high; wiring the wrong polarity means the relay is
  energized at boot until firmware runs, which you do not want on a
  breaker-tripping circuit.
- **20x4 I2C LCD** (PCF8574 backpack): SDA=GPIO21, SCL=GPIO22, VCC=5V,
  GND=GND (`kLcdSdaPin`/`kLcdSclPin`/`kLcdI2cAddress` in `config.h`, default
  address 0x27 — some backpacks use 0x3F). Shows a centered welcome intro for
  `kLcdIntroMs`, then one row per channel (`COM1 230V 0.5A ON`), refreshed
  every second; an OFF channel shows `COM1 000V 0.0A OFF`. If the text is invisible
  with the backlight on, turn the contrast pot on the backpack.

## Toolchain

This is a [PlatformIO](https://platformio.org/) project (`platformio.ini`
at the firmware root). Install the `pio` CLI (`pip install platformio`) or
use the PlatformIO IDE extension for VS Code — both read the same project
files, so either works. `platformio.ini` targets the generic `esp32dev`
board; if you're on a different ESP32 dev board, change the `board =` line
(`pio boards espressif32` lists the available IDs) and double-check
`kRelayPins`/`kPzemTxPin`/`kPzemRxPin` in `config.h` are still valid,
unused GPIOs on that specific board.

## Deployment

1. Copy `include/config.example.h` to `include/config.h`, fill in your
   Supabase URL/service key and a `kDeviceId` UUID you generate once
   (`python -c "import uuid; print(uuid.uuid4())"`). WiFi credentials are
   *not* set here — see **WiFi provisioning** below. `config.h` is
   gitignored — see **Security** below.
2. Build and flash (from `esp32_firmware/`, with the board connected via
   USB):
   ```
   pio run -t upload
   ```
   PlatformIO fetches the ESP32 platform, the Arduino framework, and the
   dependencies (`ArduinoJson`, `MycilaPZEM`, `WiFiManager`) automatically on
   first build.
3. Watch the serial console for the setup-portal prompt (first boot) or
   `[WIFI] connected: ...` and the `[NTP] Success` line (subsequent boots):
   ```
   pio device monitor
   ```

## WiFi provisioning

WiFi credentials are never stored in firmware source or `config.h` — the
device asks for them at runtime instead, using
[WiFiManager](https://github.com/tzapu/WiFiManager):

1. On first boot (or any boot where the last saved network can't be
   reached), the device opens its own temporary WiFi network — by default
   named `PowerGuard-Setup`, password `powerguard-setup` (both set by
   `kWifiSetupApName`/`kWifiSetupApPassword` in `config.h`).
2. From a phone or laptop, connect to that network, then open
   `http://192.168.4.1` (most phones prompt automatically — a "captive
   portal" login page).
3. Pick your real WiFi network and enter its password. The device connects
   and saves the credentials to its internal flash (NVS); the setup network
   disappears once connected.
4. On every boot after, the device reconnects using the saved credentials
   automatically — no re-provisioning needed unless you move it to a
   different network or `config.h`'s AP name/password changes.

A temporary outage (router reboot, brief WiFi drop) is handled by the
ESP32's own auto-reconnect and never reopens the portal. To move the
device to a different network on purpose, type `wifireset` into
`pio device monitor`'s serial console — this erases the saved network and
reopens the setup portal immediately. Power-cycling the device after
moving it (with the old network now unreachable) also reopens the portal,
since the saved-network connect attempt is retried, and re-fails, once at
every boot.

## Provisioning the PZEM meters (one-time, before wiring all 4 together)

PZEM-004T V3.0 meters ship at a default address and must each be given a
unique address (1-4) before sharing a bus. `tools/set_pzem_address/` is a
**separate, standalone PlatformIO project** (its own `platformio.ini`) so
provisioning never depends on — or risks overwriting — the main firmware's
build:

1. Connect **only one** meter to the ESP32's PZEM UART pins, powered on.
2. Edit `tools/set_pzem_address/src/main.cpp`, set `kNewAddress` to `1`.
3. Build and flash it:
   ```
   cd tools/set_pzem_address
   pio run -t upload
   pio device monitor
   ```
4. Power off, disconnect that meter, connect the next one, set
   `kNewAddress = 2`, repeat for all 4 (addresses 1-4).
5. Wire all 4 meters onto the shared bus, then reflash the main firmware
   (`cd ../.. && pio run -t upload`). `config.h`'s `kPzemAddresses` array
   order determines which meter maps to dashboard channel 1-4.

`tools/test_pzem_read/` is another standalone PlatformIO project — polls
one address once a second and prints `V`/`I`/`P`/`E`/`F`/`PF`, or a
specific error (timeout, addr/function mismatch, CRC) if something's
wrong. Useful after each provisioning step, or after wiring all 4 onto the
shared bus, to confirm a meter actually responds at the address you set
before trusting the main firmware's readings.

## Security

Firmware authenticates to Supabase with the **service_role key**, which
bypasses Row Level Security entirely (see `supabase/README.md` in the repo
root). This is the simplest option for a personal/lab setup but means
`include/config.h` — containing that key — must never be shared or
committed anywhere (it's in `.gitignore`). If this ever moves beyond a
personal setup, replace this with a scoped device credential (e.g. a
restricted Postgres role or an Edge Function acting as a write proxy).

`SupabaseClient` validates Supabase's TLS certificate against the Mozilla
root bundle built into the Arduino-ESP32 core, so the service key can't be
read by someone impersonating the server on the WiFi path. Validation needs
a correct clock, so cloud sync only starts once NTP has set the time (a
failed handshake is logged with the mbedTLS error).

The WiFi setup portal (see **WiFi provisioning**) is itself a WPA2-secured
network (`kWifiSetupApPassword`, default `powerguard-setup` — change it in
`config.h` before deploying), since anyone who can join it can point the
device at a different WiFi network and, from there, at a different
Supabase project. It's only up while unconfigured or after an explicit
`wifireset`, not during normal operation.

## Documented assumptions / known limitations

- **Breaker reset detection**: if a channel is `OFF` and its measured
  voltage rises above `kResetVoltageThresholdV` (default 90V), firmware
  assumes someone manually reset the breaker and clears `breaker_status`
  back to `'ON'`. This assumes each PZEM is wired **downstream** of its
  breaker (measuring the protected load), so voltage collapses to ~0V when
  the breaker is open. If your PZEM is wired upstream instead, this
  heuristic won't work and `breaker_status` will stay `'OFF'` in the
  database until you address this separately.
- **Schedule time zone.** The ESP32 has no battery-backed RTC, so firmware
  gets the time from NTP (nothing time-based runs until it has). The app
  stores schedule times as plain local clock times, so set
  `kUtcOffsetSeconds` in `config.h` to your timezone (e.g. `8 * 3600` for
  UTC+8); it defaults to 0, which reads schedules as UTC. Schedules are
  cached from the last successful fetch (refreshed every
  `kScheduleRefreshMs`), so they keep firing while offline.
- **Offline detection** is server-side, not firmware-side. Firmware only
  ever writes `status = 'online'` (on boot and every heartbeat) — it has no
  way to mark itself offline when it loses power or crashes. A `pg_cron`
  job (`supabase/schema.sql` section 5 / migration
  `20260907000000_offline_staleness.sql`) runs every 30s and flips any
  device whose `last_seen` is older than 90s back to `offline`, so
  `devices.status` in the database itself stays accurate, not just the
  app's client-side computed `Device.isOnline`.
- **Task layout.** Safety (`loop()`: PZEM readings, overcurrent/reset
  logic, local schedules, relay pulses) never touches the network. All
  WiFi/NTP/Supabase work runs on a separate `cloud` task; the two share
  channel state behind a mutex and exchange off commands / off-log events
  through queues, so a slow or dead connection can't delay a trip. Each
  task is on the task watchdog (30s). A meter with no good read for 10s has
  its live values cleared (its cumulative `energy` is kept so monthly
  totals stay correct), and channels that have never answered are not
  uploaded.
- Off events are uploaded best-effort with a few retries; they are held in
  RAM only, so an off-log row is lost if the device reboots before it could
  be sent.
- Cloud sync makes several HTTPS calls per `kLoopIntervalMs` tick (each a
  fresh TLS handshake). If ticks consistently run late, raise
  `kLoopIntervalMs` in `config.h`; this only slows uploads, not safety.
