# PowerGuard IoT

Remote monitoring and shutoff for up to four electrical circuits. An ESP32
reads four PZEM-004T energy meters, uploads live readings to Supabase, and
pulses relays wired to shunt-trip breakers to turn circuits **off** — on
command from the app, on overcurrent, or on a schedule. A Flutter app shows
live voltage, current, power and energy per channel and raises alarms.

> Remote **ON** is intentionally not supported. Breakers are only ever
> tripped remotely; turning a circuit back on requires a manual reset at the
> panel.

## Architecture

```
 PZEM-004T x4 ──UART──┐                         ┌── Flutter app (Android)
                      ├── ESP32 ──HTTPS──► Supabase ◄── realtime / REST
 Relays x4 ◄──GPIO────┘    │                (Postgres, Auth, pg_cron)
                        20x4 LCD
```

| Part | Path | Stack |
| --- | --- | --- |
| Mobile app | `lib/`, `android/` | Flutter, `supabase_flutter`, `provider` |
| Firmware | `esp32_firmware/` | PlatformIO, Arduino-ESP32, MycilaPZEM, WiFiManager |
| Backend | `supabase/` | Postgres schema, RLS policies, `pg_cron` jobs |

## Features

- Live per-channel voltage, current, power, energy, frequency and power factor
- Manual remote OFF with confirmation, plus off history log
- Automatic overcurrent trip and scheduled OFF times
- Overcurrent alarms via notifications and a foreground alarm service
- Channel history, monthly energy totals, and a customizable dashboard
- Device online/offline detection (server-side staleness check)
- On-device 20x4 LCD status display and captive-portal WiFi setup
- Safety logic runs locally on the ESP32 and keeps working without network

## Getting started

### 1. Supabase

Create a Supabase project, then apply the schema with `supabase db push`
(or paste `supabase/schema.sql` into the SQL Editor). Create admin users
under **Authentication → Users** — the app has no sign-up page. See
[`supabase/README.md`](supabase/README.md) for keys and seed data.

### 2. Flutter app

```
cp .env.example .env      # set SUPABASE_URL and SUPABASE_ANON_KEY
flutter pub get
flutter run
```

### 3. ESP32 firmware

```
cd esp32_firmware
cp include/config.example.h include/config.h   # Supabase URL, service key, device ID
pio run -t upload
pio device monitor
```

On first boot, join the `PowerGuard-Setup` WiFi network to enter your WiFi
credentials. Wiring, PZEM address provisioning, and security notes are in
[`esp32_firmware/README.md`](esp32_firmware/README.md).

## Repository layout

```
lib/                 Flutter app (models, pages, services, widgets, theme)
android/             Android host project
esp32_firmware/      ESP32 firmware + standalone PZEM tools (tools/)
supabase/            schema.sql and incremental migrations
test/                Dart unit tests
*.docx, generate_*.py  Project documentation (DFDs, audit report) and generators
```

## Security notes

- `.env` and `esp32_firmware/include/config.h` hold credentials and are
  gitignored — never commit them.
- The app uses the Supabase **anon** key and relies on RLS. The firmware
  uses the **service_role** key, which bypasses RLS; this is acceptable for
  a personal/lab setup only. See the firmware README's **Security** section.
