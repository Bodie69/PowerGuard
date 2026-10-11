-- ONE-OFF data cleanup. Review, then run once in the Supabase SQL editor.
-- (Not idempotent-critical: re-running just deletes nothing.)
--
-- 1. False overcurrent events. Corrupted PZEM frames used to be accepted as
--    real readings (millions of amps, hundreds of megawatts) and pulsed the
--    relays. The firmware now rejects such frames, but the log rows remain and
--    show up in the app's Off History. No real channel can exceed 100 A, so
--    anything above 1000 A is a corrupt frame.
delete from off_logs
where reason = 'Overcurrent' and current > 1000;

-- 2. "No reading" history rows: energy and voltage both 0 (written before a
--    meter had answered, plus two rows per channel stamped 1970 from before
--    NTP). They skew month-start baselines and the trend chart.
delete from channel_history
where energy = 0 and voltage = 0;
