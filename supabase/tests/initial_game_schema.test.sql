begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

select throws_ok(
  $$ select public.create_room('Unauthenticated', 1::smallint) $$,
  '42501',
  'authentication_required',
  'room creation requires authentication'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

with snapshot as (
  select public.create_room('A', 1::smallint) as value
)
select
  set_config('test.room_id', value -> 'room' ->> 'id', true),
  set_config('test.room_code', value -> 'room' ->> 'code', true)
from snapshot;

reset role;

select is(
  (select count(*) from public.rooms where id = current_setting('test.room_id')::uuid),
  1::bigint,
  'create_room inserts one room'
);

select is(
  (select count(*) from public.room_players where room_id = current_setting('test.room_id')::uuid and user_id = '00000000-0000-0000-0000-0000000000a1'),
  1::bigint,
  'the creator receives one host membership'
);

select is(
  (select max_players from public.rooms where id = current_setting('test.room_id')::uuid),
  20::smallint,
  'new rooms default to twenty players'
);

select ok(
  (select expires_at between created_at + interval '23 hours 59 minutes' and created_at + interval '24 hours 1 minute' from public.rooms where id = current_setting('test.room_id')::uuid),
  'new rooms expire approximately twenty-four hours after creation'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in ('rooms', 'room_players', 'turns', 'prompt_categories', 'prompts', 'prompt_draws', 'room_deck_state', 'admin_users')
      and relation.relrowsecurity
  ),
  8::bigint,
  'RLS is enabled on every exposed application table'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
select public.join_room(current_setting('test.room_code'), 'A changed', 3::smallint);
reset role;

select is(
  (select count(*) from public.room_players where room_id = current_setting('test.room_id')::uuid),
  1::bigint,
  'joining again with the same identity does not duplicate the player'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
select public.join_room(current_setting('test.room_code'), 'B', 1::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
select public.join_room(current_setting('test.room_code'), 'C', 2::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', true);
select public.join_room(current_setting('test.room_code'), 'D', 3::smallint);
reset role;

select is(
  (select string_agg(display_name, ',' order by queue_position) from public.room_players where room_id = current_setting('test.room_id')::uuid and left_at is null),
  'A,B,C,D',
  'lobby joins append in arrival order'
);

with first_player as (
  select id
  from public.room_players
  where room_id = current_setting('test.room_id')::uuid
    and display_name = 'A'
), new_turn as (
  insert into public.turns (room_id, player_id, turn_number, selected_level)
  select current_setting('test.room_id')::uuid, id, 1, 1
  from first_player
  returning id
)
update public.rooms
set status = 'active',
    started_at = statement_timestamp(),
    current_turn_id = (select id from new_turn)
where id = current_setting('test.room_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);
select public.join_room(current_setting('test.room_code'), 'E', 2::smallint);
reset role;

select is(
  (select string_agg(display_name, ',' order by queue_position) from public.room_players where room_id = current_setting('test.room_id')::uuid and left_at is null),
  'A,E,B,C,D',
  'the first active-game join is inserted after the current player'
);

select is(
  (select joined_during_turn_id from public.room_players where room_id = current_setting('test.room_id')::uuid and display_name = 'E'),
  (select current_turn_id from public.rooms where id = current_setting('test.room_id')::uuid),
  'the first late join records the active turn'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', true);
select public.join_room(current_setting('test.room_code'), 'F', 2::smallint);
reset role;

select is(
  (select string_agg(display_name, ',' order by queue_position) from public.room_players where room_id = current_setting('test.room_id')::uuid and left_at is null),
  'A,E,F,B,C,D',
  'multiple active-game joins preserve their arrival order after the current player'
);

select is(
  (select joined_during_turn_id from public.room_players where room_id = current_setting('test.room_id')::uuid and display_name = 'F'),
  (select current_turn_id from public.rooms where id = current_setting('test.room_id')::uuid),
  'the second late join records the same active turn'
);

select is(
  (select state_version from public.rooms where id = current_setting('test.room_id')::uuid),
  6::bigint,
  'state version advances once per successful new membership'
);

update public.rooms
set max_players = 6
where id = current_setting('test.room_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select throws_ok(
  format($sql$ select public.join_room(%L, 'G', 1::smallint) $sql$, current_setting('test.room_code')),
  'P0001',
  'room_is_full',
  'the room capacity is enforced inside the join transaction'
);
reset role;

update public.rooms
set max_players = 20,
    is_locked = true
where id = current_setting('test.room_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select throws_ok(
  format($sql$ select public.join_room(%L, 'G', 1::smallint) $sql$, current_setting('test.room_code')),
  '42501',
  'room_is_locked',
  'a locked room rejects a new player'
);

select is(
  (select count(*) from public.rooms where id = current_setting('test.room_id')::uuid),
  0::bigint,
  'an outsider cannot select the room through RLS'
);

select is(
  (select count(*) from public.room_players where room_id = current_setting('test.room_id')::uuid),
  0::bigint,
  'an outsider cannot select the player list through RLS'
);

select throws_ok(
  format($sql$ select public.get_room_snapshot(%L::uuid) $sql$, current_setting('test.room_id')),
  '42501',
  'room_access_denied',
  'an outsider cannot request an authoritative snapshot'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);

select is(
  public.get_room_snapshot(current_setting('test.room_id')::uuid) -> 'room' ->> 'id',
  current_setting('test.room_id'),
  'a current member can request the authoritative snapshot'
);

select throws_ok(
  $$ update public.rooms set is_locked = false $$,
  '42501',
  'permission denied for table rooms',
  'authenticated clients cannot directly mutate critical room state'
);

select throws_ok(
  $$ select * from public.prompts $$,
  '42501',
  'permission denied for table prompts',
  'the prompt bank is not directly readable by players'
);

select ok(
  (public.get_room_snapshot(current_setting('test.room_id')::uuid) -> 'players' -> 0 ->> 'isHost')::boolean,
  'the snapshot derives the visible host tag from authoritative room data'
);

select is(
  jsonb_array_length(public.get_room_snapshot(current_setting('test.room_id')::uuid) -> 'history'),
  0,
  'a new room snapshot has an empty prompt history'
);
reset role;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$ select public.create_room('Anon', 1::smallint) $$,
  '42501',
  'permission denied for function create_room',
  'the unauthenticated API role cannot execute room creation'
);
reset role;

select matches(
  current_setting('test.room_code'),
  '^[A-HJ-NP-Z2-9]{6}$',
  'room codes use six unambiguous uppercase characters'
);

select ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.rooms', 'INSERT'),
  'authenticated clients have no direct room insert privilege'
);

select ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.turns', 'UPDATE'),
  'authenticated clients have no direct turn update privilege'
);

select * from finish();
rollback;
