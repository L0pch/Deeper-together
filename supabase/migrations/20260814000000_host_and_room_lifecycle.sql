drop policy room_players_members_can_read on public.room_players;

create policy room_players_members_can_read
on public.room_players
for select
to authenticated
using (
  user_id = (select auth.uid())
  or (select private.is_active_room_member(room_id, (select auth.uid())))
);

create function private.compact_room_queue(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player_id uuid;
  v_player_count integer;
  v_position integer := 0;
begin
  select count(*)::integer
  into v_player_count
  from public.room_players as player
  where player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null;

  update public.room_players
  set queue_position = queue_position + v_player_count
  where room_id = p_room_id
    and left_at is null
    and kicked_at is null;

  for v_player_id in
    select player.id
    from public.room_players as player
    where player.room_id = p_room_id
      and player.left_at is null
      and player.kicked_at is null
    order by player.queue_position
  loop
    v_position := v_position + 1;
    update public.room_players
    set queue_position = v_position
    where id = v_player_id;
  end loop;
end;
$$;

create function private.leave_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_player public.room_players%rowtype;
  v_successor public.room_players%rowtype;
  v_current_turn public.turns%rowtype;
  v_next_turn_id uuid;
  v_next_turn_number integer;
  v_remaining integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_room_id is null then
    raise exception using errcode = '22023', message = 'invalid_room_action';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'room_not_found';
  end if;

  select player.*
  into v_player
  from public.room_players as player
  where player.room_id = p_room_id
    and player.user_id = v_user_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'room_access_denied';
  end if;

  if v_player.left_at is not null or v_player.kicked_at is not null then
    return jsonb_build_object('left', true, 'roomId', p_room_id, 'roomClosed', v_room.status = 'closed');
  end if;

  if v_room.status not in ('lobby', 'active') or v_room.expires_at <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'invalid_room_state';
  end if;

  select player.*
  into v_successor
  from public.room_players as player
  where player.room_id = p_room_id
    and player.id <> v_player.id
    and player.left_at is null
    and player.kicked_at is null
  order by
    case when player.queue_position > v_player.queue_position then 0 else 1 end,
    player.queue_position
  limit 1;

  select count(*)::integer
  into v_remaining
  from public.room_players as player
  where player.room_id = p_room_id
    and player.id <> v_player.id
    and player.left_at is null
    and player.kicked_at is null;

  if v_room.current_turn_id is not null then
    select turn_row.*
    into v_current_turn
    from public.turns as turn_row
    where turn_row.id = v_room.current_turn_id;
  end if;

  if v_current_turn.id is not null and v_current_turn.player_id = v_player.id then
    update public.prompt_draws
    set outcome = 'skipped',
        resolved_at = statement_timestamp()
    where turn_id = v_current_turn.id
      and outcome = 'current';

    update public.turns
    set status = 'cancelled',
        completed_at = statement_timestamp()
    where id = v_current_turn.id;

    if v_remaining > 0 then
      select coalesce(max(turn_row.turn_number), 0) + 1
      into v_next_turn_number
      from public.turns as turn_row
      where turn_row.room_id = p_room_id;

      insert into public.turns (room_id, player_id, turn_number, selected_level)
      values (p_room_id, v_successor.id, v_next_turn_number, v_successor.selected_level)
      returning id into v_next_turn_id;

      update public.turns
      set superseded_by_turn_id = v_next_turn_id
      where id = v_current_turn.id;
    end if;
  else
    v_next_turn_id := v_room.current_turn_id;
  end if;

  update public.room_players
  set left_at = statement_timestamp(),
      queue_position = null
  where id = v_player.id;

  perform private.compact_room_queue(p_room_id);

  if v_remaining = 0 then
    update public.rooms
    set status = 'closed',
        is_locked = true,
        current_turn_id = null,
        ended_at = statement_timestamp(),
        state_version = state_version + 1,
        last_activity_at = statement_timestamp(),
        expires_at = statement_timestamp() + interval '24 hours'
    where id = p_room_id;

    return jsonb_build_object('left', true, 'roomId', p_room_id, 'roomClosed', true);
  end if;

  update public.rooms
  set host_user_id = case when host_user_id = v_user_id then v_successor.user_id else host_user_id end,
      current_turn_id = v_next_turn_id,
      state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = p_room_id;

  return jsonb_build_object('left', true, 'roomId', p_room_id, 'roomClosed', false);
end;
$$;

create function private.kick_player(p_room_id uuid, p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_target public.room_players%rowtype;
  v_successor public.room_players%rowtype;
  v_current_turn public.turns%rowtype;
  v_next_turn_id uuid;
  v_next_turn_number integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_room_id is null or p_player_id is null then
    raise exception using errcode = '22023', message = 'invalid_host_action';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found or v_room.status not in ('lobby', 'active') or v_room.expires_at <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'room_not_found';
  end if;

  if v_room.host_user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'host_permission_required';
  end if;

  select player.*
  into v_target
  from public.room_players as player
  where player.id = p_player_id
    and player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'player_not_active';
  end if;

  if v_target.user_id = v_user_id then
    raise exception using errcode = 'P0001', message = 'cannot_kick_host';
  end if;

  if v_room.current_turn_id is not null then
    select turn_row.*
    into v_current_turn
    from public.turns as turn_row
    where turn_row.id = v_room.current_turn_id;
  end if;

  if v_current_turn.id is not null and v_current_turn.player_id = v_target.id then
    select player.*
    into v_successor
    from public.room_players as player
    where player.room_id = p_room_id
      and player.id <> v_target.id
      and player.left_at is null
      and player.kicked_at is null
    order by
      case when player.queue_position > v_target.queue_position then 0 else 1 end,
      player.queue_position
    limit 1;

    update public.prompt_draws
    set outcome = 'skipped',
        resolved_at = statement_timestamp()
    where turn_id = v_current_turn.id
      and outcome = 'current';

    update public.turns
    set status = 'cancelled',
        completed_at = statement_timestamp()
    where id = v_current_turn.id;

    select coalesce(max(turn_row.turn_number), 0) + 1
    into v_next_turn_number
    from public.turns as turn_row
    where turn_row.room_id = p_room_id;

    insert into public.turns (room_id, player_id, turn_number, selected_level)
    values (p_room_id, v_successor.id, v_next_turn_number, v_successor.selected_level)
    returning id into v_next_turn_id;

    update public.turns
    set superseded_by_turn_id = v_next_turn_id
    where id = v_current_turn.id;
  else
    v_next_turn_id := v_room.current_turn_id;
  end if;

  update public.room_players
  set left_at = statement_timestamp(),
      kicked_at = statement_timestamp(),
      queue_position = null
  where id = v_target.id;

  perform private.compact_room_queue(p_room_id);

  update public.rooms
  set current_turn_id = v_next_turn_id,
      state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = p_room_id;

  return private.build_room_snapshot(p_room_id);
end;
$$;

create function private.make_host(p_room_id uuid, p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_target public.room_players%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_room_id is null or p_player_id is null then
    raise exception using errcode = '22023', message = 'invalid_host_action';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found or v_room.status not in ('lobby', 'active') or v_room.expires_at <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'room_not_found';
  end if;

  if v_room.host_user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'host_permission_required';
  end if;

  select player.*
  into v_target
  from public.room_players as player
  where player.id = p_player_id
    and player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null;

  if not found then
    raise exception using errcode = 'P0001', message = 'player_not_active';
  end if;

  if v_target.user_id = v_user_id then
    return private.build_room_snapshot(p_room_id);
  end if;

  update public.rooms
  set host_user_id = v_target.user_id,
      state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = p_room_id;

  return private.build_room_snapshot(p_room_id);
end;
$$;

create function private.play_now(p_room_id uuid, p_player_id uuid, p_turn_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_target public.room_players%rowtype;
  v_current_turn public.turns%rowtype;
  v_current_position integer;
  v_player_count integer;
  v_ordered_players uuid[];
  v_ordered_positions integer[];
  v_next_turn_id uuid;
  v_next_turn_number integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_room_id is null or p_player_id is null or p_turn_id is null then
    raise exception using errcode = '22023', message = 'invalid_host_action';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found or v_room.status <> 'active' or v_room.expires_at <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'room_not_active';
  end if;

  if v_room.host_user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'host_permission_required';
  end if;

  if v_room.current_turn_id is distinct from p_turn_id then
    raise exception using errcode = 'P0001', message = 'stale_turn';
  end if;

  select turn_row.*
  into v_current_turn
  from public.turns as turn_row
  where turn_row.id = p_turn_id
    and turn_row.room_id = p_room_id
    and turn_row.status in ('awaiting_draw', 'sharing');

  if not found then
    raise exception using errcode = 'P0001', message = 'stale_turn';
  end if;

  select player.*
  into v_target
  from public.room_players as player
  where player.id = p_player_id
    and player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null;

  if not found then
    raise exception using errcode = 'P0001', message = 'player_not_active';
  end if;

  if v_target.id = v_current_turn.player_id then
    return private.build_room_snapshot(p_room_id);
  end if;

  select player.queue_position
  into v_current_position
  from public.room_players as player
  where player.id = v_current_turn.player_id;

  select count(*)::integer
  into v_player_count
  from public.room_players as player
  where player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null;

  select array_prepend(
    v_target.id,
    array_agg(player.id order by
      case
        when player.queue_position >= v_current_position then player.queue_position
        else player.queue_position + v_player_count
      end
    ) filter (where player.id <> v_target.id)
  )
  into v_ordered_players
  from public.room_players as player
  where player.room_id = p_room_id
    and player.left_at is null
    and player.kicked_at is null;

  select array_agg(position order by sequence)
  into v_ordered_positions
  from (
    select position, row_number() over () as sequence
    from generate_series(v_current_position, v_player_count) as position
    union all
    select position, (v_player_count + row_number() over ()) as sequence
    from generate_series(1, v_current_position - 1) as position
  ) as positions;

  update public.room_players
  set queue_position = queue_position + v_player_count
  where room_id = p_room_id
    and left_at is null
    and kicked_at is null;

  for v_index in 1..v_player_count loop
    update public.room_players
    set queue_position = v_ordered_positions[v_index]
    where id = v_ordered_players[v_index];
  end loop;

  update public.prompt_draws
  set outcome = 'skipped',
      resolved_at = statement_timestamp()
  where turn_id = v_current_turn.id
    and outcome = 'current';

  update public.turns
  set status = 'cancelled',
      completed_at = statement_timestamp()
  where id = v_current_turn.id;

  select coalesce(max(turn_row.turn_number), 0) + 1
  into v_next_turn_number
  from public.turns as turn_row
  where turn_row.room_id = p_room_id;

  insert into public.turns (room_id, player_id, turn_number, selected_level)
  values (p_room_id, v_target.id, v_next_turn_number, v_target.selected_level)
  returning id into v_next_turn_id;

  update public.turns
  set superseded_by_turn_id = v_next_turn_id
  where id = v_current_turn.id;

  update public.rooms
  set current_turn_id = v_next_turn_id,
      state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = p_room_id;

  return private.build_room_snapshot(p_room_id);
end;
$$;

create function private.close_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_room_id is null then
    raise exception using errcode = '22023', message = 'invalid_host_action';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'room_not_found';
  end if;

  if v_room.host_user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'host_permission_required';
  end if;

  if v_room.status = 'closed' then
    return jsonb_build_object('closed', true, 'roomId', p_room_id);
  end if;

  if v_room.status not in ('lobby', 'active') or v_room.expires_at <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'invalid_room_state';
  end if;

  if v_room.current_turn_id is not null then
    update public.prompt_draws
    set outcome = 'skipped',
        resolved_at = statement_timestamp()
    where turn_id = v_room.current_turn_id
      and outcome = 'current';

    update public.turns
    set status = 'cancelled',
        completed_at = statement_timestamp()
    where id = v_room.current_turn_id
      and status in ('awaiting_draw', 'sharing');
  end if;

  update public.rooms
  set status = 'closed',
      is_locked = true,
      current_turn_id = null,
      ended_at = statement_timestamp(),
      state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = p_room_id;

  return jsonb_build_object('closed', true, 'roomId', p_room_id);
end;
$$;

create function public.leave_room(p_room_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.leave_room(p_room_id); $$;

create function public.kick_player(p_room_id uuid, p_player_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.kick_player(p_room_id, p_player_id); $$;

create function public.make_host(p_room_id uuid, p_player_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.make_host(p_room_id, p_player_id); $$;

create function public.play_now(p_room_id uuid, p_player_id uuid, p_turn_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.play_now(p_room_id, p_player_id, p_turn_id); $$;

create function public.close_room(p_room_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.close_room(p_room_id); $$;

revoke execute on function private.compact_room_queue(uuid) from public, anon, authenticated;
revoke execute on function private.leave_room(uuid) from public, anon, authenticated;
revoke execute on function private.kick_player(uuid, uuid) from public, anon, authenticated;
revoke execute on function private.make_host(uuid, uuid) from public, anon, authenticated;
revoke execute on function private.play_now(uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function private.close_room(uuid) from public, anon, authenticated;

grant execute on function private.leave_room(uuid) to authenticated;
grant execute on function private.kick_player(uuid, uuid) to authenticated;
grant execute on function private.make_host(uuid, uuid) to authenticated;
grant execute on function private.play_now(uuid, uuid, uuid) to authenticated;
grant execute on function private.close_room(uuid) to authenticated;

revoke execute on function public.leave_room(uuid) from public, anon;
revoke execute on function public.kick_player(uuid, uuid) from public, anon;
revoke execute on function public.make_host(uuid, uuid) from public, anon;
revoke execute on function public.play_now(uuid, uuid, uuid) from public, anon;
revoke execute on function public.close_room(uuid) from public, anon;

grant execute on function public.leave_room(uuid) to authenticated;
grant execute on function public.kick_player(uuid, uuid) to authenticated;
grant execute on function public.make_host(uuid, uuid) to authenticated;
grant execute on function public.play_now(uuid, uuid, uuid) to authenticated;
grant execute on function public.close_room(uuid) to authenticated;

comment on function public.leave_room(uuid)
is 'Explicitly removes the authenticated player and transfers host/current-turn authority when required.';
comment on function public.kick_player(uuid, uuid)
is 'Allows the authoritative host to remove an active player and safely replace their current turn.';
comment on function public.make_host(uuid, uuid)
is 'Transactionally transfers host authority to another active room player.';
comment on function public.play_now(uuid, uuid, uuid)
is 'Allows the authoritative host to supersede the current turn and move a selected player into its queue slot.';
comment on function public.close_room(uuid)
is 'Allows the authoritative host to close a room while retaining its data until normal expiry.';
