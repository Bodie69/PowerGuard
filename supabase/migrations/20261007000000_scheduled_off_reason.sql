-- Separate schedule-driven offs from manual ones in Off History.
--
-- The firmware used to log schedule offs as reason 'Manual Off' with
-- triggered_by 'system' (a real manual off from the app is triggered_by
-- 'admin'). It now logs them as 'Scheduled Off'; allow that value and
-- relabel the old schedule rows.
alter table off_logs drop constraint if exists off_logs_reason_check;
alter table off_logs add constraint off_logs_reason_check
  check (reason in ('Manual Off', 'Scheduled Off', 'Overcurrent'));

update off_logs
set reason = 'Scheduled Off'
where reason = 'Manual Off' and triggered_by = 'system';
