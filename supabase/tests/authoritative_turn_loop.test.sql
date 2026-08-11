begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

update public.prompts set is_active = false;

insert into public.prompts (prompt_text, level, category_id, is_active)
values
  ('Level one alpha', 1, 'secular', true),
  ('Level one beta', 1, 'christian', true),
  ('Inactive level two', 2, 'secular', false),
  ('Active level two', 2, 'hybrid', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000020a1","role":"authenticated"}', true);

with snapshot as (
  select public.create_room('A', 1::smallint) as value
)
select
  set_config('test.turn_room_id', value -> 'room' ->> 'id', true),
  set_config('test.turn_room_code', value -> 'room' ->> 'code', true)
from snapshot;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020b1', true);
select public.join_room(current_setting('test.turn_room_code'), 'B', 1::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020c1', true);
select public.join_room(current_setting('test.turn_room_code'), 'C', 1::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020d1', true);
select public.join_room(current_setting('test.turn_room_code'), 'D', 1::smallint);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);
with started as (
  select public.start_game(current_setting('test.turn_room_id')::uuid) as value
)
select set_config('test.turn_one_id', value -> 'currentTurn' ->> 'id', true)
from started;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020e1', true);
select public.join_room(current_setting('test.turn_room_code'), 'E', 2::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020f1', true);
select public.join_room(current_setting('test.turn_room_code'), 'F', 3::smallint);

reset role;

select is(
  (select string_agg(display_name, ',' order by queue_position) from public.room_players where room_id = current_setting('test.turn_room_id')::uuid and left_at is null),
  'A,E,F,B,C,D',
  'late joins retain A, E, F, B, C, D queue order before completion'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020b1', true);

select throws_ok(
  format($sql$ select public.draw_prompt(%L::uuid, %L::uuid, 1::smallint) $sql$, current_setting('test.turn_room_id'), current_setting('test.turn_one_id')),
  '42501',
  'current_player_required',
  'a non-current player cannot draw'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);

with drawn as (
  select public.draw_prompt(
    current_setting('test.turn_room_id')::uuid,
    current_setting('test.turn_one_id')::uuid,
    1::smallint
  ) as value
)
select
  set_config('test.first_prompt_text', value -> 'history' -> 0 ->> 'promptText', true)
from drawn;

select is(
  (select count(*) from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid),
  1::bigint,
  'the first draw creates one history record'
);

select is(
  (select outcome::text from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid),
  'current',
  'the first draw is the visible current card'
);

reset role;

update public.prompts
set prompt_text = 'Edited after drawing'
where id = (
  select prompt_id
  from public.prompt_draws
  where turn_id = current_setting('test.turn_one_id')::uuid
    and outcome = 'current'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);

select is(
  public.get_room_snapshot(current_setting('test.turn_room_id')::uuid) -> 'history' -> 0 ->> 'promptText',
  current_setting('test.first_prompt_text'),
  'draw history preserves the original prompt wording after edits'
);

select is(
  public.get_room_snapshot(current_setting('test.turn_room_id')::uuid) -> 'currentTurn' ->> 'status',
  'sharing',
  'drawing moves the current turn into sharing state'
);

with redrawn as (
  select public.draw_prompt(
    current_setting('test.turn_room_id')::uuid,
    current_setting('test.turn_one_id')::uuid,
    1::smallint
  ) as value
)
select
  set_config('test.second_prompt_text', value -> 'history' -> 1 ->> 'promptText', true)
from redrawn;

select is(
  (select count(*) from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid),
  2::bigint,
  'a redraw appends rather than replaces history'
);

select is(
  (select outcome::text from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid and draw_number = 1),
  'redrawn',
  'the replaced first card is marked redrawn'
);

select is(
  (select outcome::text from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid and draw_number = 2),
  'current',
  'the replacement card becomes current'
);

select isnt(
  current_setting('test.second_prompt_text'),
  current_setting('test.first_prompt_text'),
  'prompts do not repeat before the level deck is exhausted'
);

select is(
  (select redraw_count from public.turns where id = current_setting('test.turn_one_id')::uuid),
  1,
  'the turn records one redraw'
);

select public.draw_prompt(
  current_setting('test.turn_room_id')::uuid,
  current_setting('test.turn_one_id')::uuid,
  1::smallint
);

reset role;

select is(
  (select cycle from public.room_deck_state where room_id = current_setting('test.turn_room_id')::uuid and level = 1),
  2,
  'the level deck advances to a new cycle after exhaustion'
);

select is(
  (select count(*) from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid),
  3::bigint,
  'drawing remains available after a deck cycle reset'
);

select is(
  (select redraw_count from public.turns where id = current_setting('test.turn_one_id')::uuid),
  2,
  'redraw count remains unlimited across deck cycles'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);

with level_changed as (
  select public.draw_prompt(
    current_setting('test.turn_room_id')::uuid,
    current_setting('test.turn_one_id')::uuid,
    2::smallint
  ) as value
)
select is(
  (value -> 'history' -> (jsonb_array_length(value -> 'history') - 1) ->> 'promptLevel')::integer,
  2,
  'a redraw may use a newly selected level'
)
from level_changed;

select is(
  (select prompt_text_snapshot from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid and outcome = 'current'),
  'Active level two',
  'inactive prompts are excluded from selection'
);

select is(
  (select selected_level from public.room_players where room_id = current_setting('test.turn_room_id')::uuid and display_name = 'A'),
  2::smallint,
  'a successful level change persists to the player preference'
);

select is(
  (select selected_level from public.turns where id = current_setting('test.turn_one_id')::uuid),
  2::smallint,
  'the current turn records the selected redraw level'
);

select is(
  (select redraw_count from public.turns where id = current_setting('test.turn_one_id')::uuid),
  3,
  'the cross-level replacement is also counted as a redraw'
);

select throws_ok(
  format($sql$ select public.draw_prompt(%L::uuid, %L::uuid, 3::smallint) $sql$, current_setting('test.turn_room_id'), current_setting('test.turn_one_id')),
  'P0001',
  'no_prompts_available',
  'drawing a level without eligible prompts fails safely'
);

select is(
  (select prompt_text_snapshot from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid and outcome = 'current'),
  'Active level two',
  'a failed redraw leaves the visible card unchanged'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020b1', true);

select throws_ok(
  format($sql$ select public.complete_turn(%L::uuid, %L::uuid, false) $sql$, current_setting('test.turn_room_id'), current_setting('test.turn_one_id')),
  '42501',
  'current_player_required',
  'a non-current player cannot complete the turn'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);

with completed as (
  select public.complete_turn(
    current_setting('test.turn_room_id')::uuid,
    current_setting('test.turn_one_id')::uuid,
    false
  ) as value
)
select
  set_config('test.turn_two_id', value -> 'currentTurn' ->> 'id', true),
  set_config('test.completed_state_version', value -> 'room' ->> 'stateVersion', true)
from completed;

select is(
  (select string_agg(display_name, ',' order by queue_position) from public.room_players where room_id = current_setting('test.turn_room_id')::uuid and left_at is null),
  'A,E,F,B,C,D',
  'the queue still places E directly after A'
);

reset role;

select is(
  (
    select player.display_name
    from public.turns as turn_row
    join public.room_players as player on player.id = turn_row.player_id
    where turn_row.id = current_setting('test.turn_two_id')::uuid
  ),
  'E',
  'after A completes E becomes the current player'
);

select is(
  (select outcome::text from public.prompt_draws where turn_id = current_setting('test.turn_one_id')::uuid and draw_number = 4),
  'answered',
  'Done marks the final visible card answered'
);

select is(
  (select status::text from public.turns where id = current_setting('test.turn_one_id')::uuid),
  'completed',
  'Done marks the old turn completed'
);

select is(
  (select selected_level from public.turns where id = current_setting('test.turn_two_id')::uuid),
  2::smallint,
  'the next turn begins with E persisted level preference'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', true);

select is(
  public.complete_turn(
    current_setting('test.turn_room_id')::uuid,
    current_setting('test.turn_one_id')::uuid,
    false
  ) -> 'currentTurn' ->> 'id',
  current_setting('test.turn_two_id'),
  'duplicate Done returns the already-advanced authoritative snapshot'
);

reset role;

select is(
  (select count(*) from public.turns where room_id = current_setting('test.turn_room_id')::uuid),
  2::bigint,
  'duplicate Done cannot create an extra turn'
);

select is(
  (select state_version from public.rooms where id = current_setting('test.turn_room_id')::uuid),
  current_setting('test.completed_state_version')::bigint,
  'duplicate Done cannot advance room state twice'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020e1', true);

select public.draw_prompt(
  current_setting('test.turn_room_id')::uuid,
  current_setting('test.turn_two_id')::uuid,
  1::smallint
);

with skipped as (
  select public.complete_turn(
    current_setting('test.turn_room_id')::uuid,
    current_setting('test.turn_two_id')::uuid,
    true
  ) as value
)
select set_config('test.turn_three_id', value -> 'currentTurn' ->> 'id', true)
from skipped;

reset role;

select is(
  (
    select player.display_name
    from public.turns as turn_row
    join public.room_players as player on player.id = turn_row.player_id
    where turn_row.id = current_setting('test.turn_three_id')::uuid
  ),
  'F',
  'skipping advances from E to F in queue order'
);

select is(
  (select outcome::text from public.prompt_draws where turn_id = current_setting('test.turn_two_id')::uuid),
  'skipped',
  'Skip records the visible prompt as skipped'
);

select is(
  (select status::text from public.turns where id = current_setting('test.turn_two_id')::uuid),
  'skipped',
  'Skip records the turn as skipped'
);

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  format($sql$ select public.draw_prompt(%L::uuid, %L::uuid, 1::smallint) $sql$, current_setting('test.turn_room_id'), current_setting('test.turn_three_id')),
  '42501',
  'permission denied for function draw_prompt',
  'the anonymous API role cannot draw'
);

select throws_ok(
  format($sql$ select public.complete_turn(%L::uuid, %L::uuid, false) $sql$, current_setting('test.turn_room_id'), current_setting('test.turn_three_id')),
  '42501',
  'permission denied for function complete_turn',
  'the anonymous API role cannot complete a turn'
);

reset role;

select * from finish();
rollback;
