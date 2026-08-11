create table private.rate_limit_counters (
  subject_id uuid not null,
  action_name text not null,
  scope_key text not null default 'global',
  window_started_at timestamptz not null,
  request_count integer not null,
  updated_at timestamptz not null default now(),
  primary key (subject_id, action_name, scope_key),
  constraint rate_limit_action_format check (action_name ~ '^[a-z][a-z0-9_]{1,63}$'),
  constraint rate_limit_scope_length check (char_length(scope_key) between 1 and 80),
  constraint rate_limit_count_positive check (request_count > 0)
);

revoke all on table private.rate_limit_counters from public, anon, authenticated;

create function private.enforce_rate_limit(
  p_action_name text,
  p_max_requests integer,
  p_window interval,
  p_scope_key text default 'global'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_id uuid := auth.uid();
  v_window_seconds numeric;
  v_window_start timestamptz;
  v_request_count integer;
begin
  if v_subject_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_action_name is null
    or p_action_name !~ '^[a-z][a-z0-9_]{1,63}$'
    or p_scope_key is null
    or char_length(p_scope_key) not between 1 and 80
    or p_max_requests not between 1 and 10000
    or p_window <= interval '0 seconds'
    or p_window > interval '24 hours'
  then
    raise exception using errcode = '22023', message = 'rate_limit_configuration_invalid';
  end if;

  v_window_seconds := extract(epoch from p_window);
  v_window_start := to_timestamp(
    floor(extract(epoch from statement_timestamp()) / v_window_seconds) * v_window_seconds
  );

  insert into private.rate_limit_counters (
    subject_id,
    action_name,
    scope_key,
    window_started_at,
    request_count,
    updated_at
  )
  values (
    v_subject_id,
    p_action_name,
    p_scope_key,
    v_window_start,
    1,
    statement_timestamp()
  )
  on conflict (subject_id, action_name, scope_key)
  do update set
    window_started_at = excluded.window_started_at,
    request_count = case
      when private.rate_limit_counters.window_started_at = excluded.window_started_at
        then private.rate_limit_counters.request_count + 1
      else 1
    end,
    updated_at = statement_timestamp()
  returning request_count into v_request_count;

  if v_request_count > p_max_requests then
    raise exception using errcode = 'P0001', message = 'rate_limit_exceeded';
  end if;
end;
$$;

revoke all on function private.enforce_rate_limit(text, integer, interval, text) from public, anon;
grant execute on function private.enforce_rate_limit(text, integer, interval, text) to authenticated;

comment on function private.enforce_rate_limit(text, integer, interval, text) is
  'Atomically limits successful authenticated RPC mutations by user, action, scope, and fixed time window.';

create or replace function public.create_room(p_display_name text, p_selected_level smallint default 1)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('create_room', 5, interval '10 minutes');
  return private.create_room(p_display_name, p_selected_level);
end;
$$;

create or replace function public.join_room(
  p_room_code text,
  p_display_name text,
  p_selected_level smallint default 1
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('join_room', 20, interval '10 minutes');
  return private.join_room(p_room_code, p_display_name, p_selected_level);
end;
$$;

create or replace function public.set_room_locked(p_room_id uuid, p_is_locked boolean)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('set_room_locked', 30, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.set_room_locked(p_room_id, p_is_locked);
end;
$$;

create or replace function public.start_game(p_room_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('start_game', 10, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.start_game(p_room_id);
end;
$$;

create or replace function public.draw_prompt(p_room_id uuid, p_turn_id uuid, p_level smallint)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('draw_prompt', 30, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.draw_prompt(p_room_id, p_turn_id, p_level);
end;
$$;

create or replace function public.complete_turn(
  p_room_id uuid,
  p_turn_id uuid,
  p_skipped boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('complete_turn', 30, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.complete_turn(p_room_id, p_turn_id, p_skipped);
end;
$$;

create or replace function public.leave_room(p_room_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('leave_room', 10, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.leave_room(p_room_id);
end;
$$;

create or replace function public.kick_player(p_room_id uuid, p_player_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('kick_player', 30, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.kick_player(p_room_id, p_player_id);
end;
$$;

create or replace function public.make_host(p_room_id uuid, p_player_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('make_host', 20, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.make_host(p_room_id, p_player_id);
end;
$$;

create or replace function public.play_now(p_room_id uuid, p_player_id uuid, p_turn_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('play_now', 30, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.play_now(p_room_id, p_player_id, p_turn_id);
end;
$$;

create or replace function public.close_room(p_room_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('close_room', 10, interval '1 minute', coalesce(p_room_id::text, 'invalid'));
  return private.close_room(p_room_id);
end;
$$;

create or replace function public.get_admin_prompt_catalog(
  p_search text default null,
  p_level smallint default null,
  p_category_id text default null,
  p_status text default 'all',
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('get_admin_prompt_catalog', 120, interval '1 minute');
  return private.get_admin_prompt_catalog(p_search, p_level, p_category_id, p_status, p_limit, p_offset);
end;
$$;

create or replace function public.save_admin_prompt(
  p_prompt_text text,
  p_level smallint,
  p_category_id text,
  p_tag_ids uuid[] default array[]::uuid[],
  p_prompt_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('save_admin_prompt', 60, interval '1 minute');
  return private.save_admin_prompt(p_prompt_text, p_level, p_category_id, p_tag_ids, p_prompt_id);
end;
$$;

create or replace function public.set_admin_prompt_state(p_prompt_id uuid, p_action text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('set_admin_prompt_state', 60, interval '1 minute');
  return private.set_admin_prompt_state(p_prompt_id, p_action);
end;
$$;

create or replace function public.save_admin_tag(p_name text, p_slug text, p_tag_id uuid default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('save_admin_tag', 30, interval '1 minute');
  return private.save_admin_tag(p_name, p_slug, p_tag_id);
end;
$$;

create or replace function public.set_admin_tag_active(p_tag_id uuid, p_is_active boolean)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('set_admin_tag_active', 30, interval '1 minute');
  return private.set_admin_tag_active(p_tag_id, p_is_active);
end;
$$;

create or replace function public.import_admin_prompts(p_rows jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('import_admin_prompts', 5, interval '10 minutes');
  return private.import_admin_prompts(p_rows);
end;
$$;

create or replace function public.get_admin_prompt_export()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.enforce_rate_limit('get_admin_prompt_export', 10, interval '10 minutes');
  return private.get_admin_prompt_export();
end;
$$;

create or replace function private.cleanup_expired_rooms(p_batch_size integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted_count integer;
begin
  if p_batch_size < 1 or p_batch_size > 5000 then
    raise exception using errcode = '22023', message = 'cleanup_batch_size_invalid';
  end if;

  delete from private.rate_limit_counters
  where updated_at < statement_timestamp() - interval '24 hours';

  with expired_rooms as (
    select room.id
    from public.rooms as room
    where room.expires_at <= statement_timestamp()
    order by room.expires_at, room.id
    limit p_batch_size
    for update skip locked
  ), deleted_rooms as (
    delete from public.rooms as room
    using expired_rooms
    where room.id = expired_rooms.id
    returning room.id
  )
  select count(*)::integer into v_deleted_count from deleted_rooms;

  return v_deleted_count;
end;
$$;

comment on table private.rate_limit_counters is
  'Private fixed-window counters for authenticated RPC abuse protection; no room codes or conversation content are stored.';
