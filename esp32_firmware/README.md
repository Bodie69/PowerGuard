# PowerGuard IoT — ESP32 Firmware

Arduino/C++ (PlatformIO) firmware for the ESP32: reads 4x PZEM-004T V3.0
energy meters, uploads readings to Supabase, and pulses a 4-channel relay
module to turn off breakers (manual command, overcurrent, or schedule).
Remote ON is never supported — see `safety_requirements` in the project
spec.

## Wiring

- **PZEM-004T x4** share a single UART bus, wired to UART2 (default
  TX=GPIO27, RX=GPIO14, configurable in `config.h`) so UART0 stays free for
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
   WiFi credentials, Supabase URL/service key, and a `kDeviceId` UUID you
   generate once (`python -c "import uuid; print(uuid.uuid4())"`).
   `config.h` is gitignored — see **Security** below.
2. Build and flash (from `esp32_firmware/`, with the board connected via
   USB):
   ```
   pio run -t upload
   ```
   PlatformIO fetches the ESP32 platform, the Arduino framework, and the
   one dependency (`ArduinoJson`) automatically on first build.
3. Watch the serial console for `WiFi connected: ...` and NTP sync
   confirmation on first boot:
   ```
   pio device monitor
   ```

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

`SupabaseClient` calls `WiFiClientSecure::setInsecure()`, so TLS is
encrypted but the server certificate isn't validated (no CA bundle for
Supabase is pinned). This matches the trust posture of the original
firmware; pin a CA cert here before using this beyond a personal/lab setup.

## Documented assumptions / known limitations

- **Breaker reset detection**: if a channel is `OFF` and its measured
  voltage rises above `kResetVoltageThresholdV` (default 90V), firmware
  assumes someone manually reset the breaker and clears `breaker_status`
  back to `'ON'`. This assumes each PZEM is wired **downstream** of its
  breaker (measuring the protected load), so voltage collapses to ~0V when
  the breaker is open. If your PZEM is wired upstream instead, this
  heuristic won't work and `breaker_status` will stay `'OFF'` in the
  database until you address this separately.
- **Schedules are UTC-only.** The ESP32 has no battery-backed RTC by
  default, so firmware syncs time via NTP on boot (and hourly) and compares
  `off_schedules.off_time`/`days` directly against UTC — no timezone
  conversion. Enter schedule times in UTC in the app for now.
- **No offline detection.** Firmware marks the device `online` on boot and
  every heartbeat, but nothing currently flips it back to `offline` if the
  device loses power or crashes — that would need a server-side staleness
  check (e.g. a Supabase Edge Function/cron), which is not implemented yet.
- **Single-core, cooperative loop.** `loop()` runs the safety checks (PZEM
  polling, overcurrent/reset logic, local schedules) every ~100ms and folds
  in a cloud-sync pass every `kLoopIntervalMs` (default 2s) on the same
  core — it does not use FreeRTOS tasks across both cores. This mirrors the
  original firmware's behavior (a single-threaded MicroPython event loop
  where a blocking network call also stalls safety checks): a slow
  Supabase request briefly delays the next safety poll. If that latency
  becomes a problem, moving `runCloudSync()` to its own task pinned to the
  second core (with a mutex around `channelState`) would decouple them.
- Network calls are batched (one channel upload + one off-command poll,
  one schedule refresh, and one heartbeat per `kLoopIntervalMs` tick) to
  stay within the loop budget given the ESP32's TLS handshake overhead. If
  you see the loop consistently running behind, raise `kLoopIntervalMs` in
  `config.h`.
