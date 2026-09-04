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

-- off_logs: Historical record of off events (Manual Off, Overcurrent)
create table off_logs (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id) on delete cascade,
  channel smallint not null check (channel between 1 and 4),
  reason text not null check (reason in ('Manual Off', 'Overcurrent')),
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
