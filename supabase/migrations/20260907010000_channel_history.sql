-- Persisted time-series of channel readings.
--
-- `channels` only ever holds the latest row per (device_id, channel_number)
-- -- it's upserted on every sync, so there was nowhere to read a trend or a
-- monthly total from. The app's "Power Consumption Trend" chart used to be
-- an in-memory buffer on ChannelDetailsPage that reset every time you left
-- the page.
--
-- Firmware now inserts one row per channel into this table on every cloud
-- sync tick (~2s, see kLoopIntervalMs in esp32_firmware/include/config.h),
-- so the app can subscribe to it directly for a live trend chart and
-- compute monthly consumption from the `energy` column, which is the
-- PZEM's own cumulative kWh register (monthly usage = latest energy this
-- month - earliest energy this month).
--
-- Note: at ~4 rows every 2s this grows fast (~5M rows/device/month) --
-- worth adding a retention job (e.g. delete rows older than N months) if
-- storage becomes a concern.

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
