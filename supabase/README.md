# PowerGuard IoT — Supabase Backend

## Applying the schema

Option A — Supabase CLI (if the project is linked):

```
supabase db push
```

Option B — no CLI: paste the contents of `schema.sql` into the
Supabase Dashboard's SQL Editor and run it.

## Admin accounts

There is a single "Administrator" role and no self-service signup page in the app.
Create admin accounts directly in the Supabase Dashboard under Authentication > Users
(or via `supabase auth admin create-user` on the CLI). The Flutter app only exposes a
Login page.

## Keys

- The Flutter app uses the **anon key** (`SUPABASE_ANON_KEY`) plus the RLS policies in
  the migration — an authenticated admin can read devices/channels/off_logs, manage
  off_schedules, and insert off_commands.
- The ESP32 firmware will need the **service_role key** to write
  channel readings, device status, and off_logs, since those tables have no `anon`/
  `authenticated` write policies. Embedding a service_role key in firmware is the
  simplest option but bypasses RLS entirely — if the device is ever compromised, so is
  the whole database. Revisit with a scoped device credential (e.g. a Postgres role
  restricted to specific tables, or a Supabase Edge Function acting as a proxy) before
  shipping this beyond a personal/lab setup.

## Manual seed data (for testing the Flutter app before firmware exists)

```sql
insert into devices (device_name, status, last_seen, firmware_version)
values ('PowerGuard ESP32', 'online', now(), '0.1.0')
returning id;

-- use the id returned above in place of <device_id> below
insert into channels (device_id, channel_number, voltage, current, power, energy, frequency, power_factor, breaker_status)
values
  ('<device_id>', 1, 230.1, 2.3, 529.2, 12.4, 60.0, 0.98, 'ON'),
  ('<device_id>', 2, 229.8, 0.0, 0.0, 3.1, 60.0, 1.0, 'ON'),
  ('<device_id>', 3, 230.5, 5.6, 1290.8, 40.2, 60.0, 0.95, 'ON'),
  ('<device_id>', 4, 0, 0, 0, 0, 0, 0, 'OFF');
```
