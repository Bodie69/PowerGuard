-- Persisted monthly energy totals, independent of channel_history's 3-month
-- retention window (see 20260907020000_channel_history_retention.sql).
--
-- The app currently computes "this month's" consumption on the fly by
-- diffing the latest energy reading against the earliest one recorded this
-- month (SupabaseService.monthStartEnergy + channelHistoryStream). That's
-- fine for the *current* month, but once channel_history rows age past the
-- retention window, any earlier month's total becomes unrecoverable -- there
-- was nowhere to look it up. This table snapshots each completed month's
-- consumption once, so it survives regardless of what happens to the raw
-- rows afterward.

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
-- RLS), same as the mark-devices-offline job in schema.sql -- no
-- firmware/client write path needed.

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
    order by device_id, channel_number, recorded_at asc
  ),
  ends as (
    select distinct on (device_id, channel_number)
      device_id, channel_number, energy as end_energy
    from channel_history, period
    where recorded_at >= period.month_start and recorded_at < period.month_end
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
