begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

select has_extension('pg_cron', 'the room cleanup scheduler extension is installed');

select has_function(
  'private',
  'cleanup_expired_rooms',
  array['integer'],
  'the private room cleanup function exists'
);

select ok(
  not has_function_privilege('anon', 'private.cleanup_expired_rooms(integer)', 'EXECUTE'),
  'anonymous users cannot execute room cleanup'
);

select ok(
  not has_function_privilege('authenticated', 'private.cleanup_expired_rooms(integer)', 'EXECUTE'),
  'authenticated users cannot execute room cleanup'
);

select is(
  (
    select job.schedule
    from cron.job as job
    where job.jobname = 'cleanup-expired-rooms-hourly'
  ),
  '7 * * * *',
  'expired-room cleanup is scheduled hourly'
);

select is(
  (
    select job.command
    from cron.job as job
    where job.jobname = 'cleanup-expired-rooms-hourly'
  ),
  'select private.cleanup_expired_rooms(500);',
  'the scheduled job invokes the bounded private cleanup function'
);

select throws_ok(
  $$ select private.cleanup_expired_rooms(0) $$,
  '22023',
  'cleanup_batch_size_invalid',
  'cleanup rejects a zero-sized batch'
);

select throws_ok(
  $$ select private.cleanup_expired_rooms(5001) $$,
  '22023',
  'cleanup_batch_size_invalid',
  'cleanup rejects an excessively large batch'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000050a1","role":"authenticated","is_anonymous":true}', true);

with snapshot as (
  select public.create_room('Expired host', 1::smallint) as value
)
select
  set_config('test.expired_room_id', value -> 'room' ->> 'id', true),
  set_config('test.expired_player_id', value -> 'players' -> 0 ->> 'id', true)
from snapshot;

select public.start_game(current_setting('test.expired_room_id')::uuid);

select set_config(
  'test.expired_turn_id',
  public.get_room_snapshot(current_setting('test.expired_room_id')::uuid) -> 'currentTurn' ->> 'id',
  true
);

select public.draw_prompt(
  current_setting('test.expired_room_id')::uuid,
  current_setting('test.expired_turn_id')::uuid,
  1::smallint
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050b1', true);
with snapshot as (
  select public.create_room('Active host', 2::smallint) as value
)
select
  set_config('test.active_room_id', value -> 'room' ->> 'id', true),
  set_config('test.active_player_id', value -> 'players' -> 0 ->> 'id', true)
from snapshot;

reset role;

update public.rooms
set expires_at = statement_timestamp() - interval '1 minute'
where id = current_setting('test.expired_room_id')::uuid;

select is(
  private.cleanup_expired_rooms(),
  1,
  'cleanup deletes the expired room'
);

select is(
  (select count(*)::integer from public.rooms where id = current_setting('test.expired_room_id')::uuid),
  0,
  'the expired room is removed'
);

select is(
  (select count(*)::integer from public.room_players where room_id = current_setting('test.expired_room_id')::uuid),
  0,
  'expired-room players are cascade-deleted'
);

select is(
  (select count(*)::integer from public.turns where room_id = current_setting('test.expired_room_id')::uuid),
  0,
  'expired-room turns are cascade-deleted'
);

select is(
  (select count(*)::integer from public.prompt_draws where room_id = current_setting('test.expired_room_id')::uuid),
  0,
  'expired-room prompt history is cascade-deleted'
);

select is(
  (select count(*)::integer from public.room_deck_state where room_id = current_setting('test.expired_room_id')::uuid),
  0,
  'expired-room deck state is cascade-deleted'
);

select is(
  (select count(*)::integer from public.rooms where id = current_setting('test.active_room_id')::uuid),
  1,
  'cleanup preserves a room whose expiry is still in the future'
);

select is(
  (select count(*)::integer from public.room_players where id = current_setting('test.active_player_id')::uuid),
  1,
  'cleanup preserves the active room membership'
);

select is(
  private.cleanup_expired_rooms(),
  0,
  'cleanup is idempotent when no rooms are expired'
);

rollback;
