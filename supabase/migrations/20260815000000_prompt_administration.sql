create index prompts_admin_filter_idx
  on public.prompts (archived_at, is_active, level, category_id, updated_at desc);

insert into public.tags (name, slug)
values
  ('Everyday life', 'everyday-life'),
  ('Faith', 'faith'),
  ('Gratitude', 'gratitude'),
  ('Growth', 'growth'),
  ('Prayer', 'prayer'),
  ('Relationships', 'relationships')
on conflict (slug) do nothing;

create function private.require_prompt_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_is_anonymous boolean := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, true);
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if v_is_anonymous then
    raise exception using errcode = '42501', message = 'admin_strong_authentication_required';
  end if;

  if not exists (
    select 1
    from public.admin_users as admin_user
    where admin_user.user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'admin_permission_required';
  end if;

  return v_user_id;
end;
$$;

create function private.build_admin_prompt(p_prompt_id uuid)
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
    'updatedAt', prompt.updated_at,
    'tags', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', tag.id, 'name', tag.name, 'slug', tag.slug)
        order by tag.name
      )
      from public.prompt_tags as prompt_tag
      join public.tags as tag on tag.id = prompt_tag.tag_id
      where prompt_tag.prompt_id = prompt.id
    ), '[]'::jsonb)
  )
  from public.prompts as prompt
  join public.prompt_categories as category on category.id = prompt.category_id
  where prompt.id = p_prompt_id;
$$;

create function private.get_admin_prompt_catalog(
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
    ), '[]'::jsonb),
    'tags', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', tag.id, 'name', tag.name, 'slug', tag.slug)
        order by tag.name
      )
      from public.tags as tag
    ), '[]'::jsonb)
  );
end;
$$;

create function private.save_admin_prompt(
  p_prompt_text text,
  p_level smallint,
  p_category_id text,
  p_tag_ids uuid[] default array[]::uuid[],
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
  v_tag_ids uuid[] := coalesce(p_tag_ids, array[]::uuid[]);
  v_requested_tag_count integer;
  v_existing_tag_count integer;
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
    where category.id = p_category_id
      and category.is_active
  ) then
    raise exception using errcode = '22023', message = 'invalid_prompt_category';
  end if;

  select count(distinct tag_id), count(tag.id)
  into v_requested_tag_count, v_existing_tag_count
  from unnest(v_tag_ids) as requested(tag_id)
  left join public.tags as tag on tag.id = requested.tag_id;

  if v_requested_tag_count <> v_existing_tag_count then
    raise exception using errcode = '22023', message = 'invalid_prompt_tags';
  end if;

  if v_prompt_id is null then
    insert into public.prompts (
      prompt_text,
      level,
      category_id,
      created_by,
      updated_by
    )
    values (
      v_prompt_text,
      p_level,
      p_category_id,
      v_user_id,
      v_user_id
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

  delete from public.prompt_tags where prompt_id = v_prompt_id;

  insert into public.prompt_tags (prompt_id, tag_id)
  select v_prompt_id, requested.tag_id
  from (select distinct unnest(v_tag_ids) as tag_id) as requested;

  return private.build_admin_prompt(v_prompt_id);
end;
$$;

create function private.set_admin_prompt_state(p_prompt_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_action text := lower(btrim(p_action));
begin
  v_user_id := private.require_prompt_admin();

  if p_prompt_id is null or v_action not in ('activate', 'deactivate', 'archive', 'restore') then
    raise exception using errcode = '22023', message = 'invalid_prompt_state_action';
  end if;

  update public.prompts
  set is_active = case
        when v_action = 'activate' then true
        else false
      end,
      archived_at = case
        when v_action = 'archive' then coalesce(archived_at, statement_timestamp())
        when v_action in ('activate', 'restore') then null
        else archived_at
      end,
      updated_by = v_user_id,
      updated_at = statement_timestamp()
  where id = p_prompt_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'prompt_not_found';
  end if;

  return private.build_admin_prompt(p_prompt_id);
end;
$$;

create function public.get_admin_prompt_catalog(
  p_search text default null,
  p_level smallint default null,
  p_category_id text default null,
  p_status text default 'all',
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.get_admin_prompt_catalog(
    p_search,
    p_level,
    p_category_id,
    p_status,
    p_limit,
    p_offset
  );
$$;

create function public.save_admin_prompt(
  p_prompt_text text,
  p_level smallint,
  p_category_id text,
  p_tag_ids uuid[] default array[]::uuid[],
  p_prompt_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.save_admin_prompt(
    p_prompt_text,
    p_level,
    p_category_id,
    p_tag_ids,
    p_prompt_id
  );
$$;

create function public.set_admin_prompt_state(p_prompt_id uuid, p_action text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.set_admin_prompt_state(p_prompt_id, p_action);
$$;

revoke execute on function private.require_prompt_admin() from public, anon, authenticated;
revoke execute on function private.build_admin_prompt(uuid) from public, anon, authenticated;
revoke execute on function private.get_admin_prompt_catalog(text, smallint, text, text, integer, integer) from public, anon, authenticated;
revoke execute on function private.save_admin_prompt(text, smallint, text, uuid[], uuid) from public, anon, authenticated;
revoke execute on function private.set_admin_prompt_state(uuid, text) from public, anon, authenticated;

grant execute on function private.get_admin_prompt_catalog(text, smallint, text, text, integer, integer) to authenticated;
grant execute on function private.save_admin_prompt(text, smallint, text, uuid[], uuid) to authenticated;
grant execute on function private.set_admin_prompt_state(uuid, text) to authenticated;

revoke execute on function public.get_admin_prompt_catalog(text, smallint, text, text, integer, integer) from public, anon;
revoke execute on function public.save_admin_prompt(text, smallint, text, uuid[], uuid) from public, anon;
revoke execute on function public.set_admin_prompt_state(uuid, text) from public, anon;

grant execute on function public.get_admin_prompt_catalog(text, smallint, text, text, integer, integer) to authenticated;
grant execute on function public.save_admin_prompt(text, smallint, text, uuid[], uuid) to authenticated;
grant execute on function public.set_admin_prompt_state(uuid, text) to authenticated;

comment on function public.get_admin_prompt_catalog(text, smallint, text, text, integer, integer)
is 'Returns filtered prompt-management data only to allowlisted non-anonymous administrators.';
comment on function public.save_admin_prompt(text, smallint, text, uuid[], uuid)
is 'Creates or edits a prompt and its tag assignments for an authorized administrator.';
comment on function public.set_admin_prompt_state(uuid, text)
is 'Activates, deactivates, archives, or restores a prompt for an authorized administrator.';
