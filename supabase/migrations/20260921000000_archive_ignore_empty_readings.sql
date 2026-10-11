-- The monthly archive job (20260907030000_channel_monthly_energy.sql) takes the
-- chronologically first and last channel_history rows of a month as the start
-- and end of the meter's cumulative energy register.
--
-- Older firmware wrote rows with energy = 0 and voltage = 0 while a meter
-- wasn't answering. Used as a month's first row, such a row makes the meter's
-- whole register value look like that month's consumption (e.g. 0 -> 0.608 kWh
-- with no actual usage). Rows where both energy and voltage are 0 mean "no
-- reading", so ignore them when picking the start/end rows.
--
-- cron.schedule() with an existing job name replaces that job's schedule and
-- command, so this simply redefines 'archive-monthly-energy'.

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
      and (energy > 0 or voltage > 0)
    order by device_id, channel_number, recorded_at asc
  ),
  ends as (
    select distinct on (device_id, channel_number)
      device_id, channel_number, energy as end_energy
    from channel_history, period
    where recorded_at >= period.month_start and recorded_at < period.month_end
      and (energy > 0 or voltage > 0)
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
