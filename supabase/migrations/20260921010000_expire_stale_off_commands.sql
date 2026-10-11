-- Expire off_commands the device never picked up.
--
-- The firmware executes every row with status = 'pending' as soon as it is
-- online. A command created while the device was offline (or before a long
-- outage) therefore stayed pending and would trip that breaker the moment the
-- device reconnected -- possibly hours later, when nobody expects it. An OFF
-- request is only meaningful right now, so anything still pending after 2
-- minutes is marked 'failed' (an allowed status) and never executed.

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
