create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

create type public.room_status as enum ('lobby', 'active', 'ended', 'closed');
create type public.turn_status as enum ('awaiting_draw', 'sharing', 'completed', 'skipped', 'cancelled');
create type public.draw_outcome as enum ('current', 'redrawn', 'answered', 'skipped');

create table public.prompt_categories (
  id text primary key,
  label text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint prompt_categories_id_format check (id ~ '^[a-z][a-z0-9_-]{1,31}$'),
  constraint prompt_categories_label_length check (char_length(label) between 1 and 40)
);

insert into public.prompt_categories (id, label)
values
  ('secular', 'General'),
  ('christian', 'Christian'),
  ('hybrid', 'Faith & life');

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  status public.room_status not null default 'lobby',
  host_user_id uuid not null,
  is_locked boolean not null default false,
  max_players smallint not null default 20,
  current_turn_id uuid,
  state_version bigint not null default 1,
  created_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint rooms_code_format check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  constraint rooms_player_capacity check (max_players between 1 and 30),
  constraint rooms_state_version_positive check (state_version > 0)
);

create table public.room_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null,
  display_name text not null,
  avatar_key text,
  avatar_colour text,
  selected_level smallint not null default 1,
  queue_position integer,
  joined_during_turn_id uuid,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  kicked_at timestamptz,
  last_seen_at timestamptz,
  constraint room_players_room_user_unique unique (room_id, user_id),
  constraint room_players_id_room_unique unique (id, room_id),
  constraint room_players_room_queue_position_unique
    unique (room_id, queue_position)
    deferrable initially deferred,
  constraint room_players_display_name_length check (char_length(display_name) between 1 and 40),
  constraint room_players_selected_level check (selected_level between 1 and 3),
  constraint room_players_queue_position_positive check (queue_position is null or queue_position > 0),
  constraint room_players_active_queue_required check (
    left_at is not null or kicked_at is not null or queue_position is not null
  ),
  constraint room_players_departure_state check (kicked_at is null or left_at is not null)
);

create table public.turns (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  player_id uuid not null,
  turn_number integer not null,
  status public.turn_status not null default 'awaiting_draw',
  selected_level smallint not null,
  redraw_count integer not null default 0,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  superseded_by_turn_id uuid,
  constraint turns_room_number_unique unique (room_id, turn_number),
  constraint turns_id_room_unique unique (id, room_id),
  constraint turns_player_room_fk
    foreign key (player_id, room_id)
    references public.room_players (id, room_id),
  constraint turns_superseded_by_room_fk
    foreign key (superseded_by_turn_id, room_id)
    references public.turns (id, room_id),
  constraint turns_selected_level check (selected_level between 1 and 3),
  constraint turns_redraw_count_nonnegative check (redraw_count >= 0),
  constraint turns_number_positive check (turn_number > 0)
);

create unique index turns_one_active_per_room
  on public.turns (room_id)
  where status in ('awaiting_draw', 'sharing');

alter table public.rooms
  add constraint rooms_current_turn_fk
  foreign key (current_turn_id, id)
  references public.turns (id, room_id);

alter table public.rooms
  add constraint rooms_host_membership_fk
  foreign key (id, host_user_id)
  references public.room_players (room_id, user_id)
  deferrable initially deferred;

alter table public.room_players
  add constraint room_players_joined_during_turn_fk
  foreign key (joined_during_turn_id, room_id)
  references public.turns (id, room_id);

create table public.prompts (
  id uuid primary key default gen_random_uuid(),
  prompt_text text not null,
  level smallint not null,
  category_id text not null references public.prompt_categories (id),
  is_active boolean not null default true,
  archived_at timestamptz,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint prompts_text_length check (char_length(prompt_text) between 1 and 500),
  constraint prompts_level check (level between 1 and 3),
  constraint prompts_archive_state check (archived_at is null or is_active = false)
);

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default now(),
  constraint tags_name_length check (char_length(name) between 1 and 40),
  constraint tags_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

create table public.prompt_tags (
  prompt_id uuid not null references public.prompts (id) on delete cascade,
  tag_id uuid not null references public.tags (id) on delete cascade,
  primary key (prompt_id, tag_id)
);

create table public.prompt_draws (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  turn_id uuid not null,
  player_id uuid not null,
  prompt_id uuid references public.prompts (id) on delete set null,
  draw_number integer not null,
  deck_cycle integer not null,
  player_name_snapshot text not null,
  prompt_text_snapshot text not null,
  prompt_level_snapshot smallint not null,
  prompt_category_snapshot text not null,
  prompt_tags_snapshot text[] not null default array[]::text[],
  outcome public.draw_outcome not null default 'current',
  drawn_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint prompt_draws_turn_number_unique unique (turn_id, draw_number),
  constraint prompt_draws_turn_room_fk
    foreign key (turn_id, room_id)
    references public.turns (id, room_id)
    on delete cascade,
  constraint prompt_draws_player_room_fk
    foreign key (player_id, room_id)
    references public.room_players (id, room_id),
  constraint prompt_draws_draw_number_positive check (draw_number > 0),
  constraint prompt_draws_deck_cycle_positive check (deck_cycle > 0),
  constraint prompt_draws_level check (prompt_level_snapshot between 1 and 3),
  constraint prompt_draws_text_length check (char_length(prompt_text_snapshot) between 1 and 500),
  constraint prompt_draws_player_name_length check (char_length(player_name_snapshot) between 1 and 40)
);

create table public.room_deck_state (
  room_id uuid not null references public.rooms (id) on delete cascade,
  level smallint not null,
  cycle integer not null default 1,
  updated_at timestamptz not null default now(),
  primary key (room_id, level),
  constraint room_deck_state_level check (level between 1 and 3),
  constraint room_deck_state_cycle_positive check (cycle > 0)
);

create table public.admin_users (
  user_id uuid primary key,
  created_at timestamptz not null default now()
);

create index room_players_user_id_idx on public.room_players (user_id);
create index room_players_active_queue_idx
  on public.room_players (room_id, queue_position)
  where left_at is null and kicked_at is null;
create index rooms_expiry_idx on public.rooms (expires_at);
create index prompts_draw_eligibility_idx
  on public.prompts (level, category_id)
  where is_active = true and archived_at is null;
create index prompt_draws_room_history_idx
  on public.prompt_draws (room_id, drawn_at, draw_number);
create index prompt_draws_prompt_cycle_idx
  on public.prompt_draws (room_id, prompt_level_snapshot, deck_cycle, prompt_id);
create unique index prompt_draws_one_current_per_turn
  on public.prompt_draws (turn_id)
  where outcome = 'current';

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger prompts_set_updated_at
before update on public.prompts
for each row execute function private.set_updated_at();

create function private.is_active_room_member(p_room_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.room_players as player
    join public.rooms as room on room.id = player.room_id
    where player.room_id = p_room_id
      and player.user_id = p_user_id
      and player.left_at is null
      and player.kicked_at is null
      and room.expires_at > statement_timestamp()
      and room.status <> 'closed'
  );
$$;

create function private.generate_room_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
    substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random() * 32) + 1)::integer, 1),
    ''
  )
  from generate_series(1, 6);
$$;

create function private.build_room_snapshot(p_room_id uuid)
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
          'promptTags', draw.prompt_tags_snapshot,
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

create function private.create_room(p_display_name text, p_selected_level smallint default 1)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_display_name text := btrim(p_display_name);
  v_room_id uuid := gen_random_uuid();
  v_room_code text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if v_display_name is null
    or char_length(v_display_name) not between 1 and 40
    or v_display_name ~ '[[:cntrl:]]'
  then
    raise exception using errcode = '22023', message = 'invalid_display_name';
  end if;

  if p_selected_level is null or p_selected_level not between 1 and 3 then
    raise exception using errcode = '22023', message = 'invalid_prompt_level';
  end if;

  for v_attempt in 1..10 loop
    v_room_code := private.generate_room_code();

    begin
      insert into public.rooms (
        id,
        code,
        host_user_id,
        max_players,
        expires_at
      )
      values (
        v_room_id,
        v_room_code,
        v_user_id,
        20,
        statement_timestamp() + interval '24 hours'
      );
      exit;
    exception
      when unique_violation then
        if v_attempt = 10 then
          raise exception using errcode = '55000', message = 'room_code_generation_failed';
        end if;
    end;
  end loop;

  insert into public.room_players (
    room_id,
    user_id,
    display_name,
    selected_level,
    queue_position
  )
  values (
    v_room_id,
    v_user_id,
    v_display_name,
    p_selected_level,
    1
  );

  return private.build_room_snapshot(v_room_id);
end;
$$;

create function private.join_room(
  p_room_code text,
  p_display_name text,
  p_selected_level smallint default 1
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(btrim(p_room_code));
  v_display_name text := btrim(p_display_name);
  v_room public.rooms%rowtype;
  v_player public.room_players%rowtype;
  v_active_count integer;
  v_insert_position integer;
  v_current_position integer;
  v_late_join_tail integer;
  v_joined_during_turn_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if v_code is null or v_code !~ '^[A-HJ-NP-Z2-9]{6}$' then
    raise exception using errcode = '22023', message = 'invalid_room_code';
  end if;

  if v_display_name is null
    or char_length(v_display_name) not between 1 and 40
    or v_display_name ~ '[[:cntrl:]]'
  then
    raise exception using errcode = '22023', message = 'invalid_display_name';
  end if;

  if p_selected_level is null or p_selected_level not between 1 and 3 then
    raise exception using errcode = '22023', message = 'invalid_prompt_level';
  end if;

  select room.*
  into v_room
  from public.rooms as room
  where room.code = v_code
  for update;

  if not found
    or v_room.expires_at <= statement_timestamp()
    or v_room.status not in ('lobby', 'active')
  then
    raise exception using errcode = 'P0001', message = 'room_not_found';
  end if;

  select player.*
  into v_player
  from public.room_players as player
  where player.room_id = v_room.id
    and player.user_id = v_user_id;

  if found and v_player.left_at is null and v_player.kicked_at is null then
    return private.build_room_snapshot(v_room.id);
  end if;

  if found and v_player.kicked_at is not null then
    raise exception using errcode = '42501', message = 'player_was_kicked';
  end if;

  if v_room.is_locked then
    raise exception using errcode = '42501', message = 'room_is_locked';
  end if;

  update public.room_players
  set queue_position = null
  where room_id = v_room.id
    and (left_at is not null or kicked_at is not null)
    and queue_position is not null;

  select count(*)
  into v_active_count
  from public.room_players as player
  where player.room_id = v_room.id
    and player.left_at is null
    and player.kicked_at is null;

  if v_active_count >= v_room.max_players then
    raise exception using errcode = 'P0001', message = 'room_is_full';
  end if;

  if v_room.status = 'active' and v_room.current_turn_id is not null then
    select player.queue_position
    into v_current_position
    from public.turns as turn_row
    join public.room_players as player on player.id = turn_row.player_id
    where turn_row.id = v_room.current_turn_id
      and turn_row.room_id = v_room.id;

    if v_current_position is not null then
      select max(player.queue_position)
      into v_late_join_tail
      from public.room_players as player
      where player.room_id = v_room.id
        and player.left_at is null
        and player.kicked_at is null
        and player.joined_during_turn_id = v_room.current_turn_id;

      v_insert_position := coalesce(v_late_join_tail + 1, v_current_position + 1);
      v_joined_during_turn_id := v_room.current_turn_id;

      update public.room_players
      set queue_position = queue_position + 1
      where room_id = v_room.id
        and left_at is null
        and kicked_at is null
        and queue_position >= v_insert_position;
    end if;
  end if;

  if v_insert_position is null then
    select coalesce(max(player.queue_position), 0) + 1
    into v_insert_position
    from public.room_players as player
    where player.room_id = v_room.id
      and player.left_at is null
      and player.kicked_at is null;
  end if;

  if v_player.id is not null then
    update public.room_players
    set display_name = v_display_name,
        selected_level = p_selected_level,
        queue_position = v_insert_position,
        joined_during_turn_id = v_joined_during_turn_id,
        joined_at = clock_timestamp(),
        left_at = null,
        last_seen_at = null
    where id = v_player.id;
  else
    insert into public.room_players (
      room_id,
      user_id,
      display_name,
      selected_level,
      queue_position,
      joined_during_turn_id
    )
    values (
      v_room.id,
      v_user_id,
      v_display_name,
      p_selected_level,
      v_insert_position,
      v_joined_during_turn_id
    );
  end if;

  update public.rooms
  set state_version = state_version + 1,
      last_activity_at = statement_timestamp(),
      expires_at = statement_timestamp() + interval '24 hours'
  where id = v_room.id;

  return private.build_room_snapshot(v_room.id);
end;
$$;

create function private.get_room_snapshot(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if not private.is_active_room_member(p_room_id, auth.uid()) then
    raise exception using errcode = '42501', message = 'room_access_denied';
  end if;

  return private.build_room_snapshot(p_room_id);
end;
$$;

create function public.create_room(p_display_name text, p_selected_level smallint default 1)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.create_room(p_display_name, p_selected_level);
$$;

create function public.join_room(
  p_room_code text,
  p_display_name text,
  p_selected_level smallint default 1
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.join_room(p_room_code, p_display_name, p_selected_level);
$$;

create function public.get_room_snapshot(p_room_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.get_room_snapshot(p_room_id);
$$;

alter table public.rooms enable row level security;
alter table public.room_players enable row level security;
alter table public.turns enable row level security;
alter table public.prompt_categories enable row level security;
alter table public.prompts enable row level security;
alter table public.tags enable row level security;
alter table public.prompt_tags enable row level security;
alter table public.prompt_draws enable row level security;
alter table public.room_deck_state enable row level security;
alter table public.admin_users enable row level security;

create policy rooms_members_can_read
on public.rooms
for select
to authenticated
using ((select private.is_active_room_member(id, (select auth.uid()))));

create policy room_players_members_can_read
on public.room_players
for select
to authenticated
using ((select private.is_active_room_member(room_id, (select auth.uid()))));

create policy turns_members_can_read
on public.turns
for select
to authenticated
using ((select private.is_active_room_member(room_id, (select auth.uid()))));

create policy prompt_draws_members_can_read
on public.prompt_draws
for select
to authenticated
using ((select private.is_active_room_member(room_id, (select auth.uid()))));

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
grant select on public.rooms to authenticated;
grant select on public.room_players to authenticated;
grant select on public.turns to authenticated;
grant select on public.prompt_draws to authenticated;

revoke execute on all functions in schema private from public;
revoke execute on all functions in schema private from anon;
revoke execute on all functions in schema private from authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_active_room_member(uuid, uuid) to authenticated;
grant execute on function private.create_room(text, smallint) to authenticated;
grant execute on function private.join_room(text, text, smallint) to authenticated;
grant execute on function private.get_room_snapshot(uuid) to authenticated;

revoke execute on function public.create_room(text, smallint) from public, anon;
revoke execute on function public.join_room(text, text, smallint) from public, anon;
revoke execute on function public.get_room_snapshot(uuid) from public, anon;
grant execute on function public.create_room(text, smallint) to authenticated;
grant execute on function public.join_room(text, text, smallint) to authenticated;
grant execute on function public.get_room_snapshot(uuid) to authenticated;

comment on function public.create_room(text, smallint)
is 'Creates a room and host membership for the authenticated user.';
comment on function public.join_room(text, text, smallint)
is 'Transactionally joins or resumes membership in a room and returns its authoritative snapshot.';
comment on function public.get_room_snapshot(uuid)
is 'Returns the authoritative room snapshot to a current room member.';
