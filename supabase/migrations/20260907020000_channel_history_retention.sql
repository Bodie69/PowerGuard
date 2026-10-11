-- Prune old channel_history rows.
--
-- channel_history grows by ~4 rows every 2s (~5M rows/device/month, see
-- migration 20260907010000_channel_history.sql) since firmware inserts on
-- every cloud sync tick. Monthly consumption only ever needs back to the
-- start of the current month; keep a few months of buffer for
-- month-over-month comparisons and drop anything older, so storage doesn't
-- grow unbounded.

select cron.schedule(
  'prune-channel-history',
  '0 3 * * *', -- once a day at 03:00 UTC
  $$
  delete from channel_history
  where recorded_at < now() - interval '3 months';
  $$
);
