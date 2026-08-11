create function private.draw_prompt(
  p_room_id uuid,
  p_turn_id uuid,
  p_level smallint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_turn public.turns%rowtype;
  v_player public.room_players%rowtype;
  v_prompt public.prompts%rowtype;
  v_cycle integer;
  v_draw_number integer;
  v_had_current boolean;
  v_prompt_tags text[];
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_room_id is null or p_turn_id is null then
    raise exception using errcode = '22023', message = 'invalid_turn_action';
  end if;

  if p_level is null or p_level not between 1 and 3 then
    raise exception using errcode = '22023', message = 'invalid_prompt_level';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found
    or v_room.status <> 'active'
    or v_room.expires_at <= statement_timestamp()
  then
    raise exception using errcode = 'P0001', message = 'room_not_active';
  end if;

  if v_room.current_turn_id is distinct from p_turn_id then
    raise exception using errcode = 'P0001', message = 'stale_turn';
  end if;

  select turn_row.*
  into v_turn
  from public.turns as turn_row
  where turn_row.id = p_turn_id
    and turn_row.room_id = p_room_id;

  if not found or v_turn.status not in ('awaiting_draw', 'sharing') then
    raise exception using errcode = 'P0001', message = 'stale_turn';
  end if;

  select player.*
  into v_player
  from public.room_players as player
  where player.id = v_turn.player_id
    and player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null;

  if not found or v_player.user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'current_player_required';
  end if;

  insert into public.room_deck_state (room_id, level, cycle)
  values (p_room_id, p_level, 1)
  on conflict (room_id, level) do nothing;

  select deck.cycle
  into v_cycle
  from public.room_deck_state as deck
  where deck.room_id = p_room_id
    and deck.level = p_level
  for update;

  select prompt.*
  into v_prompt
  from public.prompts as prompt
  join public.prompt_categories as category on category.id = prompt.category_id
  where prompt.level = p_level
    and prompt.is_active
    and prompt.archived_at is null
    and category.is_active
    and not exists (
      select 1
      from public.prompt_draws as previous_draw
      where previous_draw.room_id = p_room_id
        and previous_draw.prompt_level_snapshot = p_level
        and previous_draw.deck_cycle = v_cycle
        and previous_draw.prompt_id = prompt.id
    )
  order by random()
  limit 1;

  if not found then
    if not exists (
      select 1
      from public.prompts as prompt
      join public.prompt_categories as category on category.id = prompt.category_id
      where prompt.level = p_level
        and prompt.is_active
        and prompt.archived_at is null
        and category.is_active
    ) then
      raise exception using errcode = 'P0001', message = 'no_prompts_available';
    end if;

    update public.room_deck_state
    set cycle = cycle + 1,
        updated_at = statement_timestamp()
    where room_id = p_room_id
      and level = p_level
    returning cycle into v_cycle;

    select prompt.*
    into strict v_prompt
    from public.prompts as prompt
    join public.prompt_categories as category on category.id = prompt.category_id
    where prompt.level = p_level
      and prompt.is_active
      and prompt.archived_at is null
      and category.is_active
    order by random()
    limit 1;
  end if;

  select coalesce(array_agg(tag.slug order by tag.slug), array[]::text[])
  into v_prompt_tags
  from public.prompt_tags as prompt_tag
  join public.tags as tag on tag.id = prompt_tag.tag_id
  where prompt_tag.prompt_id = v_prompt.id;

  select exists (
    select 1
    from public.prompt_draws as draw
    where draw.turn_id = p_turn_id
      and draw.outcome = 'current'
  )
  into v_had_current;

  select coalesce(max(draw.draw_number), 0) + 1
  into v_draw_number
  from public.prompt_draws as draw
  where draw.turn_id = p_turn_id;

  if v_had_current then
    update public.prompt_draws
    set outcome = 'redrawn',
        resolved_at = statement_timestamp()
    where turn_id = p_turn_id
      and outcome = 'current';
  end if;

  insert into public.prompt_draws (
    room_id,
    turn_id,
    player_id,
    prompt_id,
    draw_number,
    deck_cycle,
    player_name_snapshot,
    prompt_text_snapshot,
    prompt_level_snapshot,
    prompt_category_snapshot,
    prompt_tags_snapshot
  )
  values (
    p_room_id,
    p_turn_id,
    v_player.id,
    v_prompt.id,
    v_draw_number,
    v_cycle,
    v_player.display_name,
    v_prompt.prompt_text,
    p_level,
    v_prompt.category_id,
    v_prompt_tags
  );

  update public.turns
  set status = 'sharing',
      selected_level = p_level,
      redraw_count = redraw_count + case when v_had_current then 1 else 0 end
  where id = p_turn_id;

  update public.room_players
  set selected_level = p_level
  where id = v_player.id;

  update public.rooms
  set state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = p_room_id;

  return private.build_room_snapshot(p_room_id);
end;
$$;

create function private.complete_turn(
  p_room_id uuid,
  p_turn_id uuid,
  p_skipped boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_turn public.turns%rowtype;
  v_player public.room_players%rowtype;
  v_next_player public.room_players%rowtype;
  v_next_turn_id uuid;
  v_next_turn_number integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_room_id is null or p_turn_id is null or p_skipped is null then
    raise exception using errcode = '22023', message = 'invalid_turn_action';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found
    or v_room.status <> 'active'
    or v_room.expires_at <= statement_timestamp()
  then
    raise exception using errcode = 'P0001', message = 'room_not_active';
  end if;

  select turn_row.*
  into v_turn
  from public.turns as turn_row
  where turn_row.id = p_turn_id
    and turn_row.room_id = p_room_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'stale_turn';
  end if;

  if v_room.current_turn_id is distinct from p_turn_id then
    if v_turn.status in ('completed', 'skipped') then
      return private.build_room_snapshot(p_room_id);
    end if;
    raise exception using errcode = 'P0001', message = 'stale_turn';
  end if;

  select player.*
  into v_player
  from public.room_players as player
  where player.id = v_turn.player_id
    and player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null;

  if not found or v_player.user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'current_player_required';
  end if;

  if v_turn.status <> 'sharing'
    or not exists (
      select 1
      from public.prompt_draws as draw
      where draw.turn_id = p_turn_id
        and draw.outcome = 'current'
    )
  then
    raise exception using errcode = 'P0001', message = 'prompt_required';
  end if;

  update public.prompt_draws
  set outcome = case when p_skipped then 'skipped'::public.draw_outcome else 'answered'::public.draw_outcome end,
      resolved_at = statement_timestamp()
  where turn_id = p_turn_id
    and outcome = 'current';

  update public.turns
  set status = case when p_skipped then 'skipped'::public.turn_status else 'completed'::public.turn_status end,
      completed_at = statement_timestamp()
  where id = p_turn_id;

  select player.*
  into v_next_player
  from public.room_players as player
  where player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null
    and player.queue_position > v_player.queue_position
  order by player.queue_position
  limit 1;

  if not found then
    select player.*
    into v_next_player
    from public.room_players as player
    where player.room_id = p_room_id
      and player.left_at is null
      and player.kicked_at is null
    order by player.queue_position
    limit 1;
  end if;

  if not found then
    raise exception using errcode = 'P0001', message = 'room_has_no_players';
  end if;

  select coalesce(max(turn_row.turn_number), 0) + 1
  into v_next_turn_number
  from public.turns as turn_row
  where turn_row.room_id = p_room_id;

  insert into public.turns (
    room_id,
    player_id,
    turn_number,
    selected_level
  )
  values (
    p_room_id,
    v_next_player.id,
    v_next_turn_number,
    v_next_player.selected_level
  )
  returning id into v_next_turn_id;

  update public.rooms
  set current_turn_id = v_next_turn_id,
      state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = p_room_id;

  return private.build_room_snapshot(p_room_id);
end;
$$;

create function public.draw_prompt(
  p_room_id uuid,
  p_turn_id uuid,
  p_level smallint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.draw_prompt(p_room_id, p_turn_id, p_level);
$$;

create function public.complete_turn(
  p_room_id uuid,
  p_turn_id uuid,
  p_skipped boolean default false
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.complete_turn(p_room_id, p_turn_id, p_skipped);
$$;

revoke execute on function private.draw_prompt(uuid, uuid, smallint) from public, anon, authenticated;
revoke execute on function private.complete_turn(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function private.draw_prompt(uuid, uuid, smallint) to authenticated;
grant execute on function private.complete_turn(uuid, uuid, boolean) to authenticated;

revoke execute on function public.draw_prompt(uuid, uuid, smallint) from public, anon;
revoke execute on function public.complete_turn(uuid, uuid, boolean) from public, anon;
grant execute on function public.draw_prompt(uuid, uuid, smallint) to authenticated;
grant execute on function public.complete_turn(uuid, uuid, boolean) to authenticated;

comment on function public.draw_prompt(uuid, uuid, smallint)
is 'Draws or redraws an eligible prompt for the authenticated current player and snapshots it in history.';
comment on function public.complete_turn(uuid, uuid, boolean)
is 'Idempotently resolves the current prompt and advances to the next queued player.';
