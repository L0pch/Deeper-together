alter table public.tags
  add column is_active boolean not null default true,
  add column created_by uuid,
  add column updated_by uuid,
  add column updated_at timestamptz not null default now();

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
    'updatedAt', prompt.updated_at,
    'tags', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', tag.id,
          'name', tag.name,
          'slug', tag.slug,
          'isActive', tag.is_active
        ) order by tag.name
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
    ), '[]'::jsonb),
    'tags', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', tag.id,
          'name', tag.name,
          'slug', tag.slug,
          'isActive', tag.is_active
        ) order by tag.name
      )
      from public.tags as tag
    ), '[]'::jsonb)
  );
end;
$$;

create function private.save_admin_tag(
  p_name text,
  p_slug text,
  p_tag_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_name text := btrim(p_name);
  v_slug text := lower(btrim(p_slug));
  v_tag_id uuid := p_tag_id;
begin
  v_user_id := private.require_prompt_admin();

  if v_name is null
    or char_length(v_name) not between 1 and 40
    or v_name ~ '[[:cntrl:]]'
  then
    raise exception using errcode = '22023', message = 'invalid_tag_name';
  end if;

  if v_slug is null or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or char_length(v_slug) > 48 then
    raise exception using errcode = '22023', message = 'invalid_tag_slug';
  end if;

  if exists (
    select 1 from public.tags as tag
    where tag.slug = v_slug
      and tag.id is distinct from v_tag_id
  ) then
    raise exception using errcode = '23505', message = 'tag_slug_exists';
  end if;

  if v_tag_id is null then
    insert into public.tags (name, slug, created_by, updated_by)
    values (v_name, v_slug, v_user_id, v_user_id)
    returning id into v_tag_id;
  else
    update public.tags
    set name = v_name,
        slug = v_slug,
        updated_by = v_user_id,
        updated_at = statement_timestamp()
    where id = v_tag_id;

    if not found then
      raise exception using errcode = 'P0001', message = 'tag_not_found';
    end if;
  end if;

  return (
    select jsonb_build_object(
      'id', tag.id,
      'name', tag.name,
      'slug', tag.slug,
      'isActive', tag.is_active
    )
    from public.tags as tag
    where tag.id = v_tag_id
  );
end;
$$;

create function private.set_admin_tag_active(p_tag_id uuid, p_is_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  v_user_id := private.require_prompt_admin();

  if p_tag_id is null or p_is_active is null then
    raise exception using errcode = '22023', message = 'invalid_tag_state';
  end if;

  update public.tags
  set is_active = p_is_active,
      updated_by = v_user_id,
      updated_at = statement_timestamp()
  where id = p_tag_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'tag_not_found';
  end if;

  return (
    select jsonb_build_object(
      'id', tag.id,
      'name', tag.name,
      'slug', tag.slug,
      'isActive', tag.is_active
    )
    from public.tags as tag
    where tag.id = p_tag_id
  );
end;
$$;

create function private.import_admin_prompts(p_rows jsonb)
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
  v_tag_slugs text[];
  v_prompt_id uuid;
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

  for v_row in
    select row.value
    from jsonb_array_elements(p_rows) as row(value)
  loop
    if jsonb_typeof(v_row) <> 'object'
      or jsonb_typeof(coalesce(v_row -> 'tags', '[]'::jsonb)) <> 'array'
      or coalesce(v_row ->> 'level', '') !~ '^[1-3]$'
    then
      raise exception using errcode = '22023', message = 'invalid_prompt_import_row';
    end if;

    v_prompt_text := btrim(v_row ->> 'promptText');
    v_level := (v_row ->> 'level')::smallint;
    v_category_id := btrim(v_row ->> 'categoryId');
    v_status := lower(coalesce(nullif(btrim(v_row ->> 'status'), ''), 'active'));

    select coalesce(array_agg(distinct lower(btrim(tag_slug))), array[]::text[])
    into v_tag_slugs
    from jsonb_array_elements_text(coalesce(v_row -> 'tags', '[]'::jsonb)) as requested(tag_slug);

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
      select 1
      from unnest(v_tag_slugs) as requested(slug)
      left join public.tags as tag on tag.slug = requested.slug and tag.is_active
      where tag.id is null
    ) then
      raise exception using errcode = '22023', message = 'invalid_prompt_import_tags';
    end if;

    if exists (
      select 1 from public.prompts as prompt
      where lower(prompt.prompt_text) = lower(v_prompt_text)
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into public.prompts (
      prompt_text,
      level,
      category_id,
      is_active,
      archived_at,
      created_by,
      updated_by
    )
    values (
      v_prompt_text,
      v_level,
      v_category_id,
      v_status = 'active',
      case when v_status = 'archived' then statement_timestamp() else null end,
      v_user_id,
      v_user_id
    )
    returning id into v_prompt_id;

    insert into public.prompt_tags (prompt_id, tag_id)
    select v_prompt_id, tag.id
    from public.tags as tag
    where tag.slug = any(v_tag_slugs);

    v_imported := v_imported + 1;
  end loop;

  return jsonb_build_object(
    'total', v_row_count,
    'imported', v_imported,
    'skipped', v_skipped
  );
end;
$$;

create function private.get_admin_prompt_export()
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
        'tags', coalesce((
          select jsonb_agg(tag.slug order by tag.slug)
          from public.prompt_tags as prompt_tag
          join public.tags as tag on tag.id = prompt_tag.tag_id
          where prompt_tag.prompt_id = prompt.id
        ), '[]'::jsonb),
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

create function public.save_admin_tag(p_name text, p_slug text, p_tag_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.save_admin_tag(p_name, p_slug, p_tag_id); $$;

create function public.set_admin_tag_active(p_tag_id uuid, p_is_active boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.set_admin_tag_active(p_tag_id, p_is_active); $$;

create function public.import_admin_prompts(p_rows jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.import_admin_prompts(p_rows); $$;

create function public.get_admin_prompt_export()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select private.get_admin_prompt_export(); $$;

revoke execute on function private.save_admin_tag(text, text, uuid) from public, anon, authenticated;
revoke execute on function private.set_admin_tag_active(uuid, boolean) from public, anon, authenticated;
revoke execute on function private.import_admin_prompts(jsonb) from public, anon, authenticated;
revoke execute on function private.get_admin_prompt_export() from public, anon, authenticated;

grant execute on function private.save_admin_tag(text, text, uuid) to authenticated;
grant execute on function private.set_admin_tag_active(uuid, boolean) to authenticated;
grant execute on function private.import_admin_prompts(jsonb) to authenticated;
grant execute on function private.get_admin_prompt_export() to authenticated;

revoke execute on function public.save_admin_tag(text, text, uuid) from public, anon;
revoke execute on function public.set_admin_tag_active(uuid, boolean) from public, anon;
revoke execute on function public.import_admin_prompts(jsonb) from public, anon;
revoke execute on function public.get_admin_prompt_export() from public, anon;

grant execute on function public.save_admin_tag(text, text, uuid) to authenticated;
grant execute on function public.set_admin_tag_active(uuid, boolean) to authenticated;
grant execute on function public.import_admin_prompts(jsonb) to authenticated;
grant execute on function public.get_admin_prompt_export() to authenticated;

comment on function public.save_admin_tag(text, text, uuid)
is 'Creates or edits an administrator-managed prompt tag.';
comment on function public.set_admin_tag_active(uuid, boolean)
is 'Activates or deactivates a prompt tag without changing historical prompt snapshots.';
comment on function public.import_admin_prompts(jsonb)
is 'Transactionally imports up to 500 validated prompts and skips case-insensitive text duplicates.';
comment on function public.get_admin_prompt_export()
is 'Exports prompt content and metadata, excluding all room and player data, for an authorized administrator.';
