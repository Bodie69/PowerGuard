-- Server-side offline detection for devices.
--
-- The ESP32 only ever writes status = 'online' (on boot and on each
-- heartbeat). It has no way to mark itself offline when it loses power,
-- crashes, or drops off WiFi, so without this job `status` stays stuck at
-- 'online' forever after the last successful heartbeat.
--
-- runCloudSync() (esp32_firmware/src/main.cpp) is nominally on a 2s cadence
-- (kLoopIntervalMs), but it makes 5 sequential HTTPS calls first and each
-- one pays a fresh TLS handshake (~1-2s on this hardware, since
-- http.setReuse(false) disables keep-alive -- see supabase_client.cpp), so
-- a real cycle takes ~10-15s in practice (confirmed from serial logs:
-- upsertChannels/insertChannelHistory/fetchPendingOffCommands/
-- fetchSchedules/heartbeat each 1.5-5s), occasionally more if one call
-- spikes. 10s/15s (the original design's assumed cadence) flapped
-- constantly against that reality.
--
-- This schedules a pg_cron job that runs every 10s and flips any device
-- whose last_seen is older than 35s back to 'offline' -- real margin over
-- the ~10-15s cycle time, while still ~2.5x faster than the original 90s.
-- Because `devices` is in the supabase_realtime publication with replica
-- identity full, this UPDATE also pushes a live Realtime event to any
-- subscribed client -- the same 35s threshold the Flutter app already used
-- client-side (see lib/models/device.dart Device.isOnline), now enforced
-- at the source of truth instead of only in the app.

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
