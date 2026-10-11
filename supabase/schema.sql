-- ===========================================================================
-- PowerGuard IoT: Supabase PostgreSQL Schema
-- ===========================================================================
-- This script sets up the tables, Row Level Security (RLS), and Realtime
-- configuration required for the PowerGuard IoT system.
--
-- ⚠️ CAUTION: This script will DROP existing PowerGuard tables and reset data.
--
-- How to use:
-- 1. Go to your Supabase Dashboard.
-- 2. Select your project.
-- 3. Click on "SQL Editor" in the left sidebar.
-- 4. Create a "New query".
-- 5. Paste this entire script and click "Run".
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 0. Cleanup (Optional: Remove if you want to keep existing tables)
-- ---------------------------------------------------------------------------
drop table if exists channel_monthly_energy cascade;
drop table if exists channel_history cascade;
drop table if exists off_logs cascade;
drop table if exists off_schedules cascade;
drop table if exists off_commands cascade;
drop table if exists channels cascade;
drop table if exists devices cascade;

-- Also cleanup old naming convention tables if they exist
drop table if exists trip_logs cascade;
drop table if exists trip_schedules cascade;
drop table if exists trip_commands cascade;

-- Enable pgcrypto for UUID generation
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

-- devices: Stores physical ESP32 hardware information
create table devices (
  id uuid primary key default gen_random_uuid(),
  device_name text not null,
  status text not null default 'offline' check (status in ('online', 'offline')),
  last_seen timestamptz,
  firmware_version text,
  created_at timestamptz not null default now()
);

-- channels: Real-time electrical readings from PZEM-004T
create table channels (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id) on delete cascade,
  channel_number smallint not null check (channel_number between 1 and 4),
  voltage numeric default 0,
  current numeric default 0,
  power numeric default 0,
  energy numeric default 0,
  frequency numeric default 50.0,
  power_factor numeric default 1.0,
  breaker_status text not null default 'ON' check (breaker_status in ('ON', 'OFF')),
  updated_at timestamptz not null default now(),
  unique (device_id, channel_number)
);

-- off_commands: Outbound instructions for the ESP32 to turn off a relay
create table off_commands (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id) on delete cascade,
  channel smallint not null check (channel between 1 and 4),
  command text not null default 'OFF' check (command = 'OFF'),
  status text not null default 'pending' check (status in ('pending', 'completed', 'failed')),
  requested_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

-- off_schedules: Automatic shutdown times per channel
create table off_schedules (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id) on delete cascade,
  channel smallint not null check (channel between 1 and 4),
  days text[] not null default '{}',
  off_time time not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

-- off_logs: Historical record of off events (Manual Off, Scheduled Off, Overcurrent)
create table off_logs (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id) on delete cascade,
  channel smallint not null check (channel between 1 and 4),
  reason text not null check (reason in ('Manual Off', 'Scheduled Off', 'Overcurrent')),
  voltage numeric,
  current numeric,
  power numeric,
  timestamp timestamptz not null default now(),
  triggered_by text
);

-- ---------------------------------------------------------------------------
-- 2. Indexes
-- ---------------------------------------------------------------------------
create index off_logs_channel_timestamp_idx on off_logs (channel, timestamp desc);
create index off_schedules_channel_idx on off_schedules (channel);
create index channels_device_id_idx on channels (device_id);

-- ---------------------------------------------------------------------------
-- 3. Row Level Security (RLS)
-- ---------------------------------------------------------------------------

alter table devices enable row level security;
alter table channels enable row level security;
alter table off_commands enable row level security;
alter table off_schedules enable row level security;
alter table off_logs enable row level security;

-- devices: Authenticated users can read
create policy "devices_select_authenticated" on devices
  for select to authenticated using (true);

-- channels: Authenticated users can read
create policy "channels_select_authenticated" on channels
  for select to authenticated using (true);

-- off_commands: Authenticated users can read and insert commands
create policy "off_commands_select_authenticated" on off_commands
  for select to authenticated using (true);

create policy "off_commands_insert_authenticated" on off_commands
  for insert to authenticated with check (requested_by = auth.uid());

-- off_schedules: Authenticated users have full CRUD access
create policy "off_schedules_select_authenticated" on off_schedules
  for select to authenticated using (true);

create policy "off_schedules_insert_authenticated" on off_schedules
  for insert to authenticated with check (true);

create policy "off_schedules_update_authenticated" on off_schedules
  for update to authenticated using (true) with check (true);

create policy "off_schedules_delete_authenticated" on off_schedules
  for delete to authenticated using (true);

-- off_logs: Authenticated users can read logs
create policy "off_logs_select_authenticated" on off_logs
  for select to authenticated using (true);

-- NOTE: The firmware (ESP32) should use the `service_role` key
-- to bypass RLS and perform writes to these tables.

-- ---------------------------------------------------------------------------
-- 4. Realtime Configuration
-- ---------------------------------------------------------------------------

-- Needed to detect online/offline status changes effectively
alter table devices replica identity full;

-- Enable realtime for all major tables
-- This uses 'alter publication' which may need manual adjustments if
-- the publication doesn't exist yet, but for most projects 'supabase_realtime' exists.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

alter publication supabase_realtime add table channels;
alter publication supabase_realtime add table off_logs;
alter publication supabase_realtime add table devices;
alter publication supabase_realtime add table off_commands;
alter publication supabase_realtime add table off_schedules;

-- ---------------------------------------------------------------------------
-- 5. Offline detection (server-side staleness check)
-- ---------------------------------------------------------------------------
-- The ESP32 only ever writes status = 'online' (on boot and on each
-- heartbeat). It has no way to mark itself offline when it loses power,
-- crashes, or drops off WiFi, so without this job `status` stays stuck at
-- 'online' forever after the last successful heartbeat.
--
-- runCloudSync() (esp32_firmware/src/main.cpp) is nominally on a 2s cadence
-- but makes 5 sequential HTTPS calls first, each paying a fresh TLS
-- handshake (~1-2s on this hardware, since http.setReuse(false) disables
-- keep-alive), so a real cycle takes ~10-15s in practice. This runs every
-- 10s and flips any device whose last_seen is older than 35s back to
-- 'offline' -- real margin over that ~10-15s cycle time, while still ~2.5x
-- faster than the original 90s. Because `devices` is in the
-- supabase_realtime publication with replica identity full, this also
-- pushes a live Realtime event to any subscribed client.

create extension if not exists pg_cron with schema extensions;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.schedule(
  'mark-devices-offline',
  '10 seconds', -- pg_cron also accepts second-level intervals, not just
                -- standard 1-minute cron syntax; this keeps the extra lag
                -- this job adds on top of the 35s staleness threshold small
  $$
  update devices
  set status = 'offline'
  where status = 'online'
    and (last_seen is null or last_seen < now() - interval '35 seconds');
  $$
);

-- ---------------------------------------------------------------------------
-- 6. Channel history (persisted trend + monthly consumption)
-- ---------------------------------------------------------------------------
-- `channels` only ever holds the latest row per (device_id, channel_number)
-- -- it's upserted on every sync. This table keeps every reading so the app
-- can show a live trend chart and compute monthly consumption from
-- `energy` (the PZEM's own cumulative kWh register: monthly usage = latest
-- energy this month - earliest energy this month), backed by data instead
-- of an in-memory buffer that reset on navigation.
--
-- Firmware inserts one row per channel on every cloud sync tick (~2s, see
-- kLoopIntervalMs in esp32_firmware/include/config.h) -- at ~4 rows/2s this
-- grows fast (~5M rows/device/month); worth adding a retention job (e.g.
-- delete rows older than N months) if storage becomes a concern.

create table channel_history (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id) on delete cascade,
  channel_number smallint not null check (channel_number between 1 and 4),
  voltage numeric default 0,
  current numeric default 0,
  power numeric default 0,
  energy numeric default 0,
  frequency numeric default 50.0,
  power_factor numeric default 1.0,
  breaker_status text not null default 'ON' check (breaker_status in ('ON', 'OFF')),
  recorded_at timestamptz not null default now()
);

-- Matches the existing off_logs_channel_timestamp_idx pattern: queries
-- filter by channel_number and a recorded_at range (single-device app for
-- now, same assumption channelsStream()/off_logs already make).
create index channel_history_channel_time_idx
  on channel_history (channel_number, recorded_at desc);

alter table channel_history enable row level security;

create policy "channel_history_select_authenticated" on channel_history
  for select to authenticated using (true);

-- NOTE: firmware uses the service_role key and bypasses RLS for inserts,
-- same as every other firmware-write-only table above.

alter publication supabase_realtime add table channel_history;

-- ---------------------------------------------------------------------------
-- 7. Channel history retention (prevent unbounded growth)
-- ---------------------------------------------------------------------------
-- Monthly consumption only ever needs back to the start of the current
-- month; keep a few months of buffer for month-over-month comparisons and
-- drop anything older, so channel_history's ~5M rows/device/month doesn't
-- grow unbounded.

select cron.schedule(
  'prune-channel-history',
  '0 3 * * *', -- once a day at 03:00 UTC
  $$
  delete from channel_history
  where recorded_at < now() - interval '3 months';
  $$
);

-- ---------------------------------------------------------------------------
-- 8. Monthly energy archive (survives channel_history retention)
-- ---------------------------------------------------------------------------
-- "This month" is computed on the fly from channel_history (see
-- SupabaseService.monthStartEnergy), which works for the current month but
-- becomes unrecoverable for past months once their rows age out of the
-- 3-month retention window above. This table snapshots each completed
-- month's consumption once so it survives regardless of raw-row pruning.

create table channel_monthly_energy (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id) on delete cascade,
  channel_number smallint not null check (channel_number between 1 and 4),
  month date not null, -- first day of the month (UTC) this row summarizes
  start_energy numeric not null default 0,
  end_energy numeric not null default 0,
  consumed_kwh numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (device_id, channel_number, month)
);

create index channel_monthly_energy_channel_month_idx
  on channel_monthly_energy (channel_number, month desc);

alter table channel_monthly_energy enable row level security;

create policy "channel_monthly_energy_select_authenticated" on channel_monthly_energy
  for select to authenticated using (true);

-- Written only by the cron job below (as the postgres role, which bypasses
-- RLS), same as the mark-devices-offline job above -- no firmware/client
-- write path needed.

alter publication supabase_realtime add table channel_monthly_energy;

-- Runs just after each month rolls over and archives the month that just
-- ended. Uses DISTINCT ON rather than min/max(energy) because energy is a
-- monotonically-increasing cumulative register that can reset mid-period
-- (e.g. a power cycle) -- the chronologically first/last readings are what
-- "start" and "end" mean here, not the smallest/largest values. consumed_kwh
-- is clamped to >=0 for the same reason the app's own monthKwh calc is
-- (see channel_details_page.dart), in case a reset lands exactly on a month
-- boundary.
select cron.schedule(
  'archive-monthly-energy',
  '5 0 1 * *', -- 00:05 UTC on the 1st of every month
  $$
  with period as (
    select date_trunc('month', now() - interval '1 day') as month_start,
           date_trunc('month', now()) as month_end
  ),
  bounds as (
    select distinct on (device_id, channel_number)
      device_id, channel_number, energy as start_energy
    from channel_history, period
    where recorded_at >= period.month_start and recorded_at < period.month_end
      and (energy > 0 or voltage > 0) -- skip "no reading" rows
    order by device_id, channel_number, recorded_at asc
  ),
  ends as (
    select distinct on (device_id, channel_number)
      device_id, channel_number, energy as end_energy
    from channel_history, period
    where recorded_at >= period.month_start and recorded_at < period.month_end
      and (energy > 0 or voltage > 0) -- skip "no reading" rows
    order by device_id, channel_number, recorded_at desc
  )
  insert into channel_monthly_energy
    (device_id, channel_number, month, start_energy, end_energy, consumed_kwh)
  select
    b.device_id, b.channel_number, (select month_start from period)::date,
    b.start_energy, e.end_energy, greatest(e.end_energy - b.start_energy, 0)
  from bounds b
  join ends e using (device_id, channel_number)
  on conflict (device_id, channel_number, month) do update set
    start_energy = excluded.start_energy,
    end_energy = excluded.end_energy,
    consumed_kwh = excluded.consumed_kwh;
  $$
);

-- ---------------------------------------------------------------------------
-- 9. Expire stale off commands
-- ---------------------------------------------------------------------------
-- The firmware executes every 'pending' off_command as soon as it is online,
-- so a command created while the device was offline would trip a breaker
-- hours later. An OFF request is only meaningful right now: anything still
-- pending after 2 minutes is marked 'failed' and never executed.
-- (Same as migrations/20260921010000_expire_stale_off_commands.sql.)

select cron.schedule(
  'expire-stale-off-commands',
  '30 seconds',
  $$
  update off_commands
  set status = 'failed', processed_at = now()
  where status = 'pending'
    and created_at < now() - interval '2 minutes';
  $$
);
