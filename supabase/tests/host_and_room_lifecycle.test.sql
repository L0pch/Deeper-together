begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

-- Manual host transfer remains server-authoritative.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000020a1","role":"authenticated"}', true);

with snapshot as (
  select public.create_room('Transfer host', 1::smallint) as value
)
select
  set_config('test.transfer_room_id', value -> 'room' ->> 'id', true),
  set_config('test.transfer_room_code', value -> 'room' ->> 'code', true),
  set_config('test.transfer_host_player_id', value -> 'players' -> 0 ->> 'id', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020b1', true);
with snapshot as (
  select public.join_room(current_setting('test.transfer_room_code'), 'New host', 2::smallint) as value
)
select set_config('test.transfer_guest_player_id', value -> 'players' -> 1 ->> 'id', true)
from snapshot;

select throws_ok(
  format($sql$ select public.make_host(%L::uuid, %L::uuid) $sql$,
    current_setting('test.transfer_room_id'), current_setting('test.transfer_guest_player_id')),
  '42501',
  'host_permission_required',
  'a non-host cannot transfer host authority'
);

select throws_ok(
  format($sql$ select public.kick_player(%L::uuid, %L::uuid) $sql$,
    current_setting('test.transfer_room_id'), current_setting('test.transfer_host_player_id')),
  '42501',
  'host_permission_required',
  'a non-host cannot kick a player'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);

select is(
  public.make_host(
    current_setting('test.transfer_room_id')::uuid,
    current_setting('test.transfer_guest_player_id')::uuid
  ) -> 'room' ->> 'hostUserId',
  '00000000-0000-0000-0000-0000000020b1',
  'the host transfer returns the new authoritative host'
);

reset role;

select is(
  (select host_user_id from public.rooms where id = current_setting('test.transfer_room_id')::uuid),
  '00000000-0000-0000-0000-0000000020b1'::uuid,
  'the host transfer is persisted'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);

select throws_ok(
  format($sql$ select public.close_room(%L::uuid) $sql$, current_setting('test.transfer_room_id')),
  '42501',
  'host_permission_required',
  'the previous host loses host permissions immediately'
);

-- Play now supersedes a drawn turn and preserves cyclic queue order.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a1', true);
with snapshot as (
  select public.create_room('A', 1::smallint) as value
)
select
  set_config('test.play_room_id', value -> 'room' ->> 'id', true),
  set_config('test.play_room_code', value -> 'room' ->> 'code', true),
  set_config('test.play_a_id', value -> 'players' -> 0 ->> 'id', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021b1', true);
select public.join_room(current_setting('test.play_room_code'), 'B', 2::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021c1', true);
select public.join_room(current_setting('test.play_room_code'), 'C', 3::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021d1', true);
select public.join_room(current_setting('test.play_room_code'), 'D', 1::smallint);

reset role;
select set_config('test.play_c_id', (
  select id::text from public.room_players
  where room_id = current_setting('test.play_room_id')::uuid and display_name = 'C'
), true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a1', true);
with started as (
  select public.start_game(current_setting('test.play_room_id')::uuid) as value
)
select set_config('test.play_old_turn_id', value -> 'currentTurn' ->> 'id', true)
from started;

select public.draw_prompt(
  current_setting('test.play_room_id')::uuid,
  current_setting('test.play_old_turn_id')::uuid,
  1::smallint
);

with played as (
  select public.play_now(
    current_setting('test.play_room_id')::uuid,
    current_setting('test.play_c_id')::uuid,
    current_setting('test.play_old_turn_id')::uuid
  ) as value
)
select set_config('test.play_new_turn_id', value -> 'currentTurn' ->> 'id', true)
from played;

reset role;

select is(
  (select string_agg(display_name, ',' order by queue_position)
   from public.room_players
   where room_id = current_setting('test.play_room_id')::uuid and left_at is null),
  'C,A,B,D',
  'play now moves the selected player into the current slot and preserves cyclic order'
);

select is(
  (select status::text from public.turns where id = current_setting('test.play_old_turn_id')::uuid),
  'cancelled',
  'play now cancels the replaced turn'
);

select is(
  (select superseded_by_turn_id from public.turns where id = current_setting('test.play_old_turn_id')::uuid),
  current_setting('test.play_new_turn_id')::uuid,
  'the replaced turn points to its unique replacement'
);

select is(
  (select player_id from public.turns where id = current_setting('test.play_new_turn_id')::uuid),
  current_setting('test.play_c_id')::uuid,
  'the selected player owns the replacement turn'
);

select is(
  (select outcome::text from public.prompt_draws where turn_id = current_setting('test.play_old_turn_id')::uuid),
  'skipped',
  'the replaced visible prompt remains in history as skipped'
);

select is(
  (select count(*) from public.turns
   where room_id = current_setting('test.play_room_id')::uuid
     and status in ('awaiting_draw', 'sharing')),
  1::bigint,
  'play now leaves exactly one active turn'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a1', true);

select throws_ok(
  format($sql$ select public.play_now(%L::uuid, %L::uuid, %L::uuid) $sql$,
    current_setting('test.play_room_id'), current_setting('test.play_a_id'), current_setting('test.play_old_turn_id')),
  'P0001',
  'stale_turn',
  'a host action against the replaced turn fails safely'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021b1', true);
select throws_ok(
  format($sql$ select public.play_now(%L::uuid, %L::uuid, %L::uuid) $sql$,
    current_setting('test.play_room_id'), current_setting('test.play_a_id'), current_setting('test.play_new_turn_id')),
  '42501',
  'host_permission_required',
  'a non-host cannot use play now'
);

-- Kicking the current player replaces the turn and retains a readable removal marker.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000022a1', true);
with snapshot as (
  select public.create_room('Kick host', 1::smallint) as value
)
select
  set_config('test.kick_room_id', value -> 'room' ->> 'id', true),
  set_config('test.kick_room_code', value -> 'room' ->> 'code', true),
  set_config('test.kick_host_id', value -> 'players' -> 0 ->> 'id', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000022b1', true);
with snapshot as (
  select public.join_room(current_setting('test.kick_room_code'), 'Kick target', 2::smallint) as value
)
select set_config('test.kick_target_id', value -> 'players' -> 1 ->> 'id', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000022c1', true);
select public.join_room(current_setting('test.kick_room_code'), 'Remaining', 3::smallint);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000022a1', true);
with started as (
  select public.start_game(current_setting('test.kick_room_id')::uuid) as value
), played as (
  select public.play_now(
    current_setting('test.kick_room_id')::uuid,
    current_setting('test.kick_target_id')::uuid,
    (started.value -> 'currentTurn' ->> 'id')::uuid
  ) as value from started
)
select set_config('test.kick_target_turn_id', value -> 'currentTurn' ->> 'id', true)
from played;

select throws_ok(
  format($sql$ select public.kick_player(%L::uuid, %L::uuid) $sql$,
    current_setting('test.kick_room_id'), current_setting('test.kick_host_id')),
  'P0001',
  'cannot_kick_host',
  'the host cannot kick themselves'
);

with kicked as (
  select public.kick_player(
    current_setting('test.kick_room_id')::uuid,
    current_setting('test.kick_target_id')::uuid
  ) as value
)
select set_config('test.kick_replacement_turn_id', value -> 'currentTurn' ->> 'id', true)
from kicked;

reset role;

select ok(
  (select left_at is not null and kicked_at is not null and queue_position is null
   from public.room_players where id = current_setting('test.kick_target_id')::uuid),
  'a kicked membership records both departure markers and leaves the queue'
);

select is(
  (select string_agg(display_name, ',' order by queue_position)
   from public.room_players
   where room_id = current_setting('test.kick_room_id')::uuid and left_at is null),
  'Kick host,Remaining',
  'kicking compacts the remaining queue'
);

select is(
  (select player.display_name
   from public.turns as turn_row
   join public.room_players as player on player.id = turn_row.player_id
   where turn_row.id = current_setting('test.kick_replacement_turn_id')::uuid),
  'Kick host',
  'kicking the current player advances to the next player in cyclic order'
);

select is(
  (select status::text from public.turns where id = current_setting('test.kick_target_turn_id')::uuid),
  'cancelled',
  'the kicked current player turn is cancelled'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000022b1', true);

select is(
  (select count(*) from public.room_players where id = current_setting('test.kick_target_id')::uuid),
  1::bigint,
  'a kicked player can still read their own removal marker'
);

select is(
  (select count(*) from public.rooms where id = current_setting('test.kick_room_id')::uuid),
  0::bigint,
  'a kicked player can no longer read the room'
);

-- Explicit host leave chooses the next queued active player, never presence state.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', true);
with snapshot as (
  select public.create_room('Leaving A', 1::smallint) as value
)
select
  set_config('test.leave_room_id', value -> 'room' ->> 'id', true),
  set_config('test.leave_room_code', value -> 'room' ->> 'code', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023b1', true);
select public.join_room(current_setting('test.leave_room_code'), 'Leaving B', 1::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023c1', true);
select public.join_room(current_setting('test.leave_room_code'), 'Staying C', 1::smallint);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', true);
select is(
  (public.leave_room(current_setting('test.leave_room_id')::uuid) ->> 'left')::boolean,
  true,
  'a player can explicitly leave'
);

select is(
  (public.leave_room(current_setting('test.leave_room_id')::uuid) ->> 'left')::boolean,
  true,
  'repeating an explicit leave is idempotent'
);

reset role;

select is(
  (select host_user_id from public.rooms where id = current_setting('test.leave_room_id')::uuid),
  '00000000-0000-0000-0000-0000000023b1'::uuid,
  'host status transfers to the next queued player on explicit leave'
);

select is(
  (select string_agg(display_name, ',' order by queue_position)
   from public.room_players
   where room_id = current_setting('test.leave_room_id')::uuid and left_at is null),
  'Leaving B,Staying C',
  'leaving compacts the remaining queue'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023b1', true);
select public.leave_room(current_setting('test.leave_room_id')::uuid);
reset role;

select is(
  (select host_user_id from public.rooms where id = current_setting('test.leave_room_id')::uuid),
  '00000000-0000-0000-0000-0000000023c1'::uuid,
  'successive host leaves continue deterministically through queue order'
);

-- Leaving an active current turn safely advances and transfers host authority.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024a1', true);
with snapshot as (
  select public.create_room('Active leaver', 1::smallint) as value
)
select
  set_config('test.active_leave_room_id', value -> 'room' ->> 'id', true),
  set_config('test.active_leave_room_code', value -> 'room' ->> 'code', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024b1', true);
select public.join_room(current_setting('test.active_leave_room_code'), 'Active successor', 2::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024a1', true);

with started as (
  select public.start_game(current_setting('test.active_leave_room_id')::uuid) as value
)
select set_config('test.active_leave_old_turn_id', value -> 'currentTurn' ->> 'id', true)
from started;

select public.draw_prompt(
  current_setting('test.active_leave_room_id')::uuid,
  current_setting('test.active_leave_old_turn_id')::uuid,
  1::smallint
);
select public.leave_room(current_setting('test.active_leave_room_id')::uuid);

reset role;

select is(
  (select player.display_name
   from public.rooms as room
   join public.turns as turn_row on turn_row.id = room.current_turn_id
   join public.room_players as player on player.id = turn_row.player_id
   where room.id = current_setting('test.active_leave_room_id')::uuid),
  'Active successor',
  'the next player receives a unique turn when the current player leaves'
);

select is(
  (select outcome::text from public.prompt_draws where turn_id = current_setting('test.active_leave_old_turn_id')::uuid),
  'skipped',
  'a visible card remains in history when its player leaves'
);

select is(
  (select host_user_id from public.rooms where id = current_setting('test.active_leave_room_id')::uuid),
  '00000000-0000-0000-0000-0000000024b1'::uuid,
  'an active host leave transfers host authority to the same successor'
);

-- Closing revokes room access but retains the room and prompt history until expiry.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025a1', true);
with snapshot as (
  select public.create_room('Closing host', 1::smallint) as value
)
select
  set_config('test.close_room_id', value -> 'room' ->> 'id', true),
  set_config('test.close_room_code', value -> 'room' ->> 'code', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025b1', true);
select public.join_room(current_setting('test.close_room_code'), 'Closing guest', 1::smallint);
select throws_ok(
  format($sql$ select public.close_room(%L::uuid) $sql$, current_setting('test.close_room_id')),
  '42501',
  'host_permission_required',
  'a non-host cannot close the room'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025a1', true);
with started as (
  select public.start_game(current_setting('test.close_room_id')::uuid) as value
)
select set_config('test.close_turn_id', value -> 'currentTurn' ->> 'id', true)
from started;
select public.draw_prompt(
  current_setting('test.close_room_id')::uuid,
  current_setting('test.close_turn_id')::uuid,
  1::smallint
);

select is(
  (public.close_room(current_setting('test.close_room_id')::uuid) ->> 'closed')::boolean,
  true,
  'the host can close the room'
);

reset role;

select ok(
  (select status = 'closed' and is_locked and current_turn_id is null
   from public.rooms where id = current_setting('test.close_room_id')::uuid),
  'closing persists a locked terminal room state with no current turn'
);

select is(
  (select count(*) from public.prompt_draws where room_id = current_setting('test.close_room_id')::uuid),
  1::bigint,
  'closing retains prompt history until room expiry'
);

select is(
  (select status::text from public.turns where id = current_setting('test.close_turn_id')::uuid),
  'cancelled',
  'closing cancels the active turn'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025a1', true);
select is(
  (select count(*) from public.rooms where id = current_setting('test.close_room_id')::uuid),
  0::bigint,
  'room members cannot read a closed room through the exposed table'
);

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  format($sql$ select public.leave_room(%L::uuid) $sql$, current_setting('test.close_room_id')),
  '42501',
  'permission denied for function leave_room',
  'the anonymous API role cannot execute lifecycle operations'
);

reset role;

select * from finish();
rollback;
