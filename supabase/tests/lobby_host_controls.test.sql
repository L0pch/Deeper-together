begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010a1","role":"authenticated"}', true);

with snapshot as (
  select public.create_room('Host', 2::smallint) as value
)
select
  set_config('test.controls_room_id', value -> 'room' ->> 'id', true),
  set_config('test.controls_room_code', value -> 'room' ->> 'code', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010b1', true);
select public.join_room(current_setting('test.controls_room_code'), 'Guest', 3::smallint);

select throws_ok(
  format($sql$ select public.set_room_locked(%L::uuid, true) $sql$, current_setting('test.controls_room_id')),
  '42501',
  'host_permission_required',
  'a non-host cannot lock the room'
);

select throws_ok(
  format($sql$ select public.start_game(%L::uuid) $sql$, current_setting('test.controls_room_id')),
  '42501',
  'host_permission_required',
  'a non-host cannot start the game'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a1', true);

select is(
  (public.set_room_locked(current_setting('test.controls_room_id')::uuid, true) -> 'room' ->> 'isLocked')::boolean,
  true,
  'the host lock operation returns a locked authoritative snapshot'
);

reset role;

select is(
  (select is_locked from public.rooms where id = current_setting('test.controls_room_id')::uuid),
  true,
  'the room lock is persisted'
);

select is(
  (select state_version from public.rooms where id = current_setting('test.controls_room_id')::uuid),
  3::bigint,
  'locking advances the room state version once'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a1', true);

select is(
  (public.set_room_locked(current_setting('test.controls_room_id')::uuid, true) -> 'room' ->> 'stateVersion')::bigint,
  3::bigint,
  'repeating the same lock operation is idempotent'
);

select is(
  (public.set_room_locked(current_setting('test.controls_room_id')::uuid, false) -> 'room' ->> 'isLocked')::boolean,
  false,
  'the host can unlock the room'
);

with started as (
  select public.start_game(current_setting('test.controls_room_id')::uuid) as value
)
select set_config('test.first_turn_id', value -> 'currentTurn' ->> 'id', true)
from started;

reset role;

select is(
  (select status::text from public.rooms where id = current_setting('test.controls_room_id')::uuid),
  'active',
  'starting returns an active authoritative snapshot'
);

select is(
  (select status::text from public.rooms where id = current_setting('test.controls_room_id')::uuid),
  'active',
  'start game persists the active room state'
);

select is(
  (select count(*) from public.turns where room_id = current_setting('test.controls_room_id')::uuid),
  1::bigint,
  'start game creates exactly one turn'
);

select is(
  (
    select player.display_name
    from public.turns as turn_row
    join public.room_players as player on player.id = turn_row.player_id
    where turn_row.id = current_setting('test.first_turn_id')::uuid
  ),
  'Host',
  'the first queued player receives the first turn'
);

select is(
  (select selected_level from public.turns where id = current_setting('test.first_turn_id')::uuid),
  2::smallint,
  'the first turn snapshots the current player level preference'
);

select is(
  (select current_turn_id from public.rooms where id = current_setting('test.controls_room_id')::uuid),
  current_setting('test.first_turn_id')::uuid,
  'the room references the created turn'
);

select is(
  (select state_version from public.rooms where id = current_setting('test.controls_room_id')::uuid),
  5::bigint,
  'unlocking and starting each advance room state once'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a1', true);

select is(
  public.start_game(current_setting('test.controls_room_id')::uuid) -> 'currentTurn' ->> 'id',
  current_setting('test.first_turn_id'),
  'a duplicate start returns the existing current turn'
);

reset role;

select is(
  (select count(*) from public.turns where room_id = current_setting('test.controls_room_id')::uuid),
  1::bigint,
  'a duplicate start cannot create another turn'
);

select is(
  (select state_version from public.rooms where id = current_setting('test.controls_room_id')::uuid),
  5::bigint,
  'a duplicate start does not advance room state'
);

select ok(
  exists(select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rooms'),
  'rooms are published for Realtime invalidation'
);

select ok(
  exists(select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_players'),
  'room players are published for Realtime invalidation'
);

select ok(
  exists(select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'turns'),
  'turns are published for Realtime invalidation'
);

select ok(
  exists(select 1 from pg_catalog.pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'prompt_draws'),
  'prompt draws are published for Realtime invalidation'
);

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  format($sql$ select public.set_room_locked(%L::uuid, true) $sql$, current_setting('test.controls_room_id')),
  '42501',
  'permission denied for function set_room_locked',
  'the anonymous API role cannot execute the lock operation'
);

select throws_ok(
  format($sql$ select public.start_game(%L::uuid) $sql$, current_setting('test.controls_room_id')),
  '42501',
  'permission denied for function start_game',
  'the anonymous API role cannot execute start game'
);

reset role;

select * from finish();
rollback;
