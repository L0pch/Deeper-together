create function private.set_room_locked(p_room_id uuid, p_is_locked boolean)
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

  if p_room_id is null or p_is_locked is null then
    raise exception using errcode = '22023', message = 'invalid_host_action';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found
    or v_room.expires_at <= statement_timestamp()
    or v_room.status not in ('lobby', 'active')
  then
    raise exception using errcode = 'P0001', message = 'room_not_found';
  end if;

  if v_room.host_user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'host_permission_required';
  end if;

  if v_room.is_locked = p_is_locked then
    return private.build_room_snapshot(v_room.id);
  end if;

  update public.rooms
  set is_locked = p_is_locked,
      state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = v_room.id;

  return private.build_room_snapshot(v_room.id);
end;
$$;

create function private.start_game(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_first_player public.room_players%rowtype;
  v_turn_id uuid;
  v_turn_number integer;
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

  if not found
    or v_room.expires_at <= statement_timestamp()
    or v_room.status not in ('lobby', 'active')
  then
    raise exception using errcode = 'P0001', message = 'room_not_found';
  end if;

  if v_room.host_user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'host_permission_required';
  end if;

  if v_room.status = 'active' and v_room.current_turn_id is not null then
    return private.build_room_snapshot(v_room.id);
  end if;

  if v_room.status <> 'lobby' then
    raise exception using errcode = 'P0001', message = 'invalid_room_state';
  end if;

  select player.*
  into v_first_player
  from public.room_players as player
  where player.room_id = v_room.id
    and player.left_at is null
    and player.kicked_at is null
  order by player.queue_position
  limit 1;

  if not found then
    raise exception using errcode = 'P0001', message = 'room_has_no_players';
  end if;

  select coalesce(max(turn_row.turn_number), 0) + 1
  into v_turn_number
  from public.turns as turn_row
  where turn_row.room_id = v_room.id;

  insert into public.turns (
    room_id,
    player_id,
    turn_number,
    selected_level
  )
  values (
    v_room.id,
    v_first_player.id,
    v_turn_number,
    v_first_player.selected_level
  )
  returning id into v_turn_id;

  update public.rooms
  set status = 'active',
      current_turn_id = v_turn_id,
      started_at = coalesce(started_at, statement_timestamp()),
      state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = v_room.id;

  return private.build_room_snapshot(v_room.id);
end;
$$;

create function public.set_room_locked(p_room_id uuid, p_is_locked boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.set_room_locked(p_room_id, p_is_locked);
$$;

create function public.start_game(p_room_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.start_game(p_room_id);
$$;

revoke execute on function private.set_room_locked(uuid, boolean) from public, anon, authenticated;
revoke execute on function private.start_game(uuid) from public, anon, authenticated;
grant execute on function private.set_room_locked(uuid, boolean) to authenticated;
grant execute on function private.start_game(uuid) to authenticated;

revoke execute on function public.set_room_locked(uuid, boolean) from public, anon;
revoke execute on function public.start_game(uuid) from public, anon;
grant execute on function public.set_room_locked(uuid, boolean) to authenticated;
grant execute on function public.start_game(uuid) to authenticated;

alter publication supabase_realtime
add table public.rooms, public.room_players, public.turns, public.prompt_draws;

comment on function public.set_room_locked(uuid, boolean)
is 'Allows the authoritative room host to lock or unlock joining.';
comment on function public.start_game(uuid)
is 'Idempotently starts a room and creates its first authoritative turn.';
