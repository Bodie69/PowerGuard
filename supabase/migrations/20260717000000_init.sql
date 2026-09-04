-- PowerGuard IoT initial schema
-- Tables: devices, channels, off_commands, off_schedules, off_logs
-- RLS: authenticated (admin app) gets read + scoped write access; service_role (firmware) bypasses RLS.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- devices
-- ---------------------------------------------------------------------------
create table devices (
  id uuid primary key default gen_random_uuid(),
  device_name text not null,
  status text not null default 'offline' check (status in ('online', 'offline')),
  last_seen timestamptz,
  firmware_version text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- channels
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- off_commands
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- off_schedules
-- ---------------------------------------------------------------------------
create table off_schedules (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id) on delete cascade,
  channel smallint not null check (channel between 1 and 4),
  days text[] not null default '{}',
  off_time time not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- off_logs
-- ---------------------------------------------------------------------------
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

create index off_logs_channel_timestamp_idx on off_logs (channel, timestamp desc);
create index off_schedules_channel_idx on off_schedules (channel);
create index channels_device_id_idx on channels (device_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table devices enable row level security;
alter table channels enable row level security;
alter table off_commands enable row level security;
alter table off_schedules enable row level security;
alter table off_logs enable row level security;

-- devices: admin app can read; only service_role (firmware) writes.
create policy "devices_select_authenticated" on devices
  for select to authenticated using (true);

-- channels: admin app can read; only service_role (firmware) writes.
create policy "channels_select_authenticated" on channels
  for select to authenticated using (true);

-- off_commands: admin app can read all commands, and insert its own.
create policy "off_commands_select_authenticated" on off_commands
  for select to authenticated using (true);

create policy "off_commands_insert_authenticated" on off_commands
  for insert to authenticated with check (requested_by = auth.uid());

-- off_schedules: admin app has full CRUD.
create policy "off_schedules_select_authenticated" on off_schedules
  for select to authenticated using (true);

create policy "off_schedules_insert_authenticated" on off_schedules
  for insert to authenticated with check (true);

create policy "off_schedules_update_authenticated" on off_schedules
  for update to authenticated using (true) with check (true);

create policy "off_schedules_delete_authenticated" on off_schedules
  for delete to authenticated using (true);

-- off_logs: admin app can read; only service_role (firmware) writes.
create policy "off_logs_select_authenticated" on off_logs
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
alter table devices replica identity full;

alter publication supabase_realtime add table channels;
alter publication supabase_realtime add table off_logs;
alter publication supabase_realtime add table devices;
alter publication supabase_realtime add table off_commands;
alter publication supabase_realtime add table off_schedules;
