create or replace function private.build_room_snapshot(p_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'room', jsonb_build_object(
      'id', room.id,
      'code', room.code,
      'status', room.status,
      'hostUserId', room.host_user_id,
      'isLocked', room.is_locked,
      'maxPlayers', room.max_players,
      'currentTurnId', room.current_turn_id,
      'stateVersion', room.state_version,
      'expiresAt', room.expires_at
    ),
    'players', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', player.id,
          'userId', player.user_id,
          'displayName', player.display_name,
          'avatarKey', player.avatar_key,
          'avatarColour', player.avatar_colour,
          'selectedLevel', player.selected_level,
          'queuePosition', player.queue_position,
          'isHost', player.user_id = room.host_user_id,
          'joinedAt', player.joined_at
        ) order by player.queue_position
      )
      from public.room_players as player
      where player.room_id = room.id
        and player.left_at is null
        and player.kicked_at is null
    ), '[]'::jsonb),
    'currentTurn', (
      select jsonb_build_object(
        'id', turn_row.id,
        'playerId', turn_row.player_id,
        'turnNumber', turn_row.turn_number,
        'status', turn_row.status,
        'selectedLevel', turn_row.selected_level,
        'redrawCount', turn_row.redraw_count,
        'startedAt', turn_row.started_at
      )
      from public.turns as turn_row
      where turn_row.id = room.current_turn_id
    ),
    'history', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', draw.id,
          'turnId', draw.turn_id,
          'playerId', draw.player_id,
          'playerName', draw.player_name_snapshot,
          'promptText', draw.prompt_text_snapshot,
          'promptLevel', draw.prompt_level_snapshot,
          'promptCategory', draw.prompt_category_snapshot,
          'drawNumber', draw.draw_number,
          'outcome', draw.outcome,
          'drawnAt', draw.drawn_at
        ) order by draw.drawn_at, draw.draw_number
      )
      from public.prompt_draws as draw
      where draw.room_id = room.id
    ), '[]'::jsonb)
  )
  from public.rooms as room
  where room.id = p_room_id;
$$;

create or replace function private.build_admin_prompt(p_prompt_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', prompt.id,
    'promptText', prompt.prompt_text,
    'level', prompt.level,
    'categoryId', prompt.category_id,
    'categoryLabel', category.label,
    'isActive', prompt.is_active,
    'archivedAt', prompt.archived_at,
    'createdAt', prompt.created_at,
    'updatedAt', prompt.updated_at
  )
  from public.prompts as prompt
  join public.prompt_categories as category on category.id = prompt.category_id
  where prompt.id = p_prompt_id;
$$;

create or replace function private.get_admin_prompt_catalog(
  p_search text default null,
  p_level smallint default null,
  p_category_id text default null,
  p_status text default 'all',
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(btrim(p_search), '');
  v_status text := lower(coalesce(p_status, 'all'));
begin
  perform private.require_prompt_admin();

  if v_search is not null and char_length(v_search) > 100 then
    raise exception using errcode = '22023', message = 'invalid_admin_search';
  end if;
  if p_level is not null and p_level not between 1 and 3 then
    raise exception using errcode = '22023', message = 'invalid_prompt_level';
  end if;
  if p_category_id is not null and not exists (
    select 1 from public.prompt_categories as category where category.id = p_category_id
  ) then
    raise exception using errcode = '22023', message = 'invalid_prompt_category';
  end if;
  if v_status not in ('all', 'active', 'inactive', 'archived') then
    raise exception using errcode = '22023', message = 'invalid_prompt_status';
  end if;
  if p_limit not between 1 and 200 or p_offset < 0 then
    raise exception using errcode = '22023', message = 'invalid_admin_pagination';
  end if;

  return jsonb_build_object(
    'prompts', coalesce((
      select jsonb_agg(private.build_admin_prompt(filtered.id) order by filtered.updated_at desc)
      from (
        select prompt.id, prompt.updated_at
        from public.prompts as prompt
        where (v_search is null or prompt.prompt_text ilike '%' || v_search || '%')
          and (p_level is null or prompt.level = p_level)
          and (p_category_id is null or prompt.category_id = p_category_id)
          and case v_status
            when 'active' then prompt.is_active and prompt.archived_at is null
            when 'inactive' then not prompt.is_active and prompt.archived_at is null
            when 'archived' then prompt.archived_at is not null
            else true
          end
        order by prompt.updated_at desc
        limit p_limit
        offset p_offset
      ) as filtered
    ), '[]'::jsonb),
    'total', (
      select count(*)
      from public.prompts as prompt
      where (v_search is null or prompt.prompt_text ilike '%' || v_search || '%')
        and (p_level is null or prompt.level = p_level)
        and (p_category_id is null or prompt.category_id = p_category_id)
        and case v_status
          when 'active' then prompt.is_active and prompt.archived_at is null
          when 'inactive' then not prompt.is_active and prompt.archived_at is null
          when 'archived' then prompt.archived_at is not null
          else true
        end
    ),
    'categories', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', category.id,
          'label', category.label,
          'isActive', category.is_active
        ) order by category.label
      )
      from public.prompt_categories as category
    ), '[]'::jsonb)
  );
end;
$$;

drop function public.save_admin_prompt(text, smallint, text, uuid[], uuid);
drop function private.save_admin_prompt(text, smallint, text, uuid[], uuid);

create function private.save_admin_prompt(
  p_prompt_text text,
  p_level smallint,
  p_category_id text,
  p_prompt_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_prompt_text text := btrim(p_prompt_text);
  v_prompt_id uuid := p_prompt_id;
begin
  v_user_id := private.require_prompt_admin();

  if v_prompt_text is null
    or char_length(v_prompt_text) not between 1 and 500
    or v_prompt_text ~ '[[:cntrl:]]'
  then
    raise exception using errcode = '22023', message = 'invalid_prompt_text';
  end if;
  if p_level is null or p_level not between 1 and 3 then
    raise exception using errcode = '22023', message = 'invalid_prompt_level';
  end if;
  if p_category_id is null or not exists (
    select 1
    from public.prompt_categories as category
    where category.id = p_category_id and category.is_active
  ) then
    raise exception using errcode = '22023', message = 'invalid_prompt_category';
  end if;

  if v_prompt_id is null then
    insert into public.prompts (
      prompt_text, level, category_id, created_by, updated_by
    )
    values (
      v_prompt_text, p_level, p_category_id, v_user_id, v_user_id
    )
    returning id into v_prompt_id;
  else
    update public.prompts
    set prompt_text = v_prompt_text,
        level = p_level,
        category_id = p_category_id,
        updated_by = v_user_id,
        updated_at = statement_timestamp()
    where id = v_prompt_id;

    if not found then
      raise exception using errcode = 'P0001', message = 'prompt_not_found';
    end if;
  end if;

  return private.build_admin_prompt(v_prompt_id);
end;
$$;

create function public.save_admin_prompt(
  p_prompt_text text,
  p_level smallint,
  p_category_id text,
  p_prompt_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('save_admin_prompt', 60, interval '1 minute');
  return private.save_admin_prompt(p_prompt_text, p_level, p_category_id, p_prompt_id);
end;
$$;

create or replace function private.import_admin_prompts(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_row jsonb;
  v_row_count integer;
  v_prompt_text text;
  v_level smallint;
  v_category_id text;
  v_status text;
  v_imported integer := 0;
  v_skipped integer := 0;
begin
  v_user_id := private.require_prompt_admin();

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception using errcode = '22023', message = 'invalid_prompt_import';
  end if;

  v_row_count := jsonb_array_length(p_rows);
  if v_row_count not between 1 and 500 then
    raise exception using errcode = '22023', message = 'invalid_prompt_import_size';
  end if;

  for v_row in select row.value from jsonb_array_elements(p_rows) as row(value)
  loop
    if jsonb_typeof(v_row) <> 'object'
      or coalesce(v_row ->> 'level', '') !~ '^[1-3]$'
    then
      raise exception using errcode = '22023', message = 'invalid_prompt_import_row';
    end if;

    v_prompt_text := btrim(v_row ->> 'promptText');
    v_level := (v_row ->> 'level')::smallint;
    v_category_id := btrim(v_row ->> 'categoryId');
    v_status := lower(coalesce(nullif(btrim(v_row ->> 'status'), ''), 'active'));

    if v_prompt_text is null
      or char_length(v_prompt_text) not between 1 and 500
      or v_prompt_text ~ '[[:cntrl:]]'
      or v_status not in ('active', 'inactive', 'archived')
    then
      raise exception using errcode = '22023', message = 'invalid_prompt_import_row';
    end if;
    if not exists (
      select 1 from public.prompt_categories as category
      where category.id = v_category_id and category.is_active
    ) then
      raise exception using errcode = '22023', message = 'invalid_prompt_import_category';
    end if;
    if exists (
      select 1 from public.prompts as prompt
      where lower(prompt.prompt_text) = lower(v_prompt_text)
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into public.prompts (
      prompt_text, level, category_id, is_active, archived_at, created_by, updated_by
    )
    values (
      v_prompt_text,
      v_level,
      v_category_id,
      v_status = 'active',
      case when v_status = 'archived' then statement_timestamp() else null end,
      v_user_id,
      v_user_id
    );

    v_imported := v_imported + 1;
  end loop;

  return jsonb_build_object(
    'total', v_row_count,
    'imported', v_imported,
    'skipped', v_skipped
  );
end;
$$;

create or replace function private.get_admin_prompt_export()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_prompt_admin();

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'promptText', prompt.prompt_text,
        'level', prompt.level,
        'categoryId', prompt.category_id,
        'status', case
          when prompt.archived_at is not null then 'archived'
          when prompt.is_active then 'active'
          else 'inactive'
        end
      ) order by prompt.created_at, prompt.id
    )
    from public.prompts as prompt
  ), '[]'::jsonb);
end;
$$;

create or replace function private.draw_prompt(
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

  select room.* into v_room
  from public.rooms as room
  where room.id = p_room_id
  for update;

  if not found or v_room.status <> 'active' or v_room.expires_at <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'room_not_active';
  end if;
  if v_room.current_turn_id is distinct from p_turn_id then
    raise exception using errcode = 'P0001', message = 'stale_turn';
  end if;

  select turn_row.* into v_turn
  from public.turns as turn_row
  where turn_row.id = p_turn_id and turn_row.room_id = p_room_id;

  if not found or v_turn.status not in ('awaiting_draw', 'sharing') then
    raise exception using errcode = 'P0001', message = 'stale_turn';
  end if;

  select player.* into v_player
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

  select deck.cycle into v_cycle
  from public.room_deck_state as deck
  where deck.room_id = p_room_id and deck.level = p_level
  for update;

  select prompt.* into v_prompt
  from public.prompts as prompt
  join public.prompt_categories as category on category.id = prompt.category_id
  where prompt.level = p_level
    and prompt.is_active
    and prompt.archived_at is null
    and category.is_active
    and not exists (
      select 1 from public.prompt_draws as previous_draw
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
    set cycle = cycle + 1, updated_at = statement_timestamp()
    where room_id = p_room_id and level = p_level
    returning cycle into v_cycle;

    select prompt.* into strict v_prompt
    from public.prompts as prompt
    join public.prompt_categories as category on category.id = prompt.category_id
    where prompt.level = p_level
      and prompt.is_active
      and prompt.archived_at is null
      and category.is_active
    order by random()
    limit 1;
  end if;

  select exists (
    select 1 from public.prompt_draws as draw
    where draw.turn_id = p_turn_id and draw.outcome = 'current'
  ) into v_had_current;

  select coalesce(max(draw.draw_number), 0) + 1 into v_draw_number
  from public.prompt_draws as draw
  where draw.turn_id = p_turn_id;

  if v_had_current then
    update public.prompt_draws
    set outcome = 'redrawn', resolved_at = statement_timestamp()
    where turn_id = p_turn_id and outcome = 'current';
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
    prompt_category_snapshot
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
    v_prompt.category_id
  );

  update public.turns
  set status = 'sharing',
      selected_level = p_level,
      redraw_count = redraw_count + case when v_had_current then 1 else 0 end
  where id = p_turn_id;

  update public.room_players set selected_level = p_level where id = v_player.id;

  update public.rooms
  set state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = p_room_id;

  return private.build_room_snapshot(p_room_id);
end;
$$;

drop function public.save_admin_tag(text, text, uuid);
drop function public.set_admin_tag_active(uuid, boolean);
drop function private.save_admin_tag(text, text, uuid);
drop function private.set_admin_tag_active(uuid, boolean);

drop table public.prompt_tags;
alter table public.prompt_draws drop column prompt_tags_snapshot;
drop table public.tags;

revoke execute on function private.save_admin_prompt(text, smallint, text, uuid) from public, anon, authenticated;
grant execute on function private.save_admin_prompt(text, smallint, text, uuid) to authenticated;
revoke execute on function public.save_admin_prompt(text, smallint, text, uuid) from public, anon;
grant execute on function public.save_admin_prompt(text, smallint, text, uuid) to authenticated;

comment on function public.save_admin_prompt(text, smallint, text, uuid)
is 'Creates or edits prompt wording, level, and category for an authorized administrator.';
comment on function public.import_admin_prompts(jsonb)
is 'Transactionally imports up to 500 validated tag-free prompts and skips case-insensitive text duplicates.';
comment on function public.get_admin_prompt_export()
is 'Exports prompt content and metadata, excluding all room and player data, for an authorized administrator.';