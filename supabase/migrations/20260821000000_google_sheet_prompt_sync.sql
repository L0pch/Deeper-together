alter table public.prompts
  add column source text not null default 'manual',
  add column source_key text,
  add column last_synced_at timestamptz,
  add constraint prompts_source check (source in ('manual', 'google_sheet')),
  add constraint prompts_source_key check (
    (source = 'manual' and source_key is null)
    or (source = 'google_sheet' and source_key is not null)
  );

create unique index prompts_source_key_unique
  on public.prompts (source, source_key)
  where source_key is not null;

create table private.prompt_sync_state (
  source text primary key,
  last_success_at timestamptz not null,
  row_count integer not null,
  result jsonb not null,
  constraint prompt_sync_state_source check (source in ('google_sheet')),
  constraint prompt_sync_state_row_count check (row_count >= 0)
);

create function private.sync_google_sheet_prompts(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_row_count integer;
  v_prompt_text text;
  v_level smallint;
  v_category_id text;
  v_status text;
  v_source_key text;
  v_prompt_id uuid;
  v_seen_keys text[] := array[]::text[];
  v_inserted integer := 0;
  v_updated integer := 0;
  v_archived integer := 0;
  v_result jsonb;
begin
  if auth.role() <> 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception using errcode = '22023', message = 'invalid_prompt_sync';
  end if;

  v_row_count := jsonb_array_length(p_rows);
  if v_row_count not between 1 and 500 then
    raise exception using errcode = '22023', message = 'invalid_prompt_sync_size';
  end if;

  if exists (
    select 1
    from (
      select lower(btrim(row.value ->> 'promptText')) as normalized_text, count(*) as occurrences
      from jsonb_array_elements(p_rows) as row(value)
      group by lower(btrim(row.value ->> 'promptText'))
    ) as duplicates
    where duplicates.normalized_text is null
      or duplicates.normalized_text = ''
      or duplicates.occurrences > 1
  ) then
    raise exception using errcode = '22023', message = 'duplicate_prompt_sync_text';
  end if;

  perform pg_advisory_xact_lock(hashtext('deeper_together_google_sheet_prompt_sync'));

  for v_row in
    select row.value
    from jsonb_array_elements(p_rows) as row(value)
  loop
    if jsonb_typeof(v_row) <> 'object'
      or coalesce(v_row ->> 'level', '') !~ '^[1-3]$'
    then
      raise exception using errcode = '22023', message = 'invalid_prompt_sync_row';
    end if;

    v_prompt_text := btrim(v_row ->> 'promptText');
    v_level := (v_row ->> 'level')::smallint;
    v_category_id := lower(btrim(v_row ->> 'categoryId'));
    v_status := lower(coalesce(nullif(btrim(v_row ->> 'status'), ''), 'active'));

    if v_prompt_text is null
      or char_length(v_prompt_text) not between 1 and 500
      or v_prompt_text ~ '[[:cntrl:]]'
      or v_status not in ('active', 'inactive', 'archived')
    then
      raise exception using errcode = '22023', message = 'invalid_prompt_sync_row';
    end if;

    if not exists (
      select 1
      from public.prompt_categories as category
      where category.id = v_category_id
        and category.is_active
    ) then
      raise exception using errcode = '22023', message = 'invalid_prompt_sync_category';
    end if;

    v_source_key := md5(lower(v_prompt_text));
    v_seen_keys := array_append(v_seen_keys, v_source_key);

    select prompt.id
    into v_prompt_id
    from public.prompts as prompt
    where (prompt.source = 'google_sheet' and prompt.source_key = v_source_key)
       or lower(prompt.prompt_text) = lower(v_prompt_text)
    order by (prompt.source = 'google_sheet') desc, prompt.created_at
    limit 1
    for update;

    if found then
      update public.prompts
      set prompt_text = v_prompt_text,
          level = v_level,
          category_id = v_category_id,
          is_active = v_status = 'active',
          archived_at = case
            when v_status = 'archived' then coalesce(archived_at, statement_timestamp())
            else null
          end,
          source = 'google_sheet',
          source_key = v_source_key,
          last_synced_at = statement_timestamp(),
          updated_by = null,
          updated_at = statement_timestamp()
      where id = v_prompt_id;

      v_updated := v_updated + 1;
    else
      insert into public.prompts (
        prompt_text,
        level,
        category_id,
        is_active,
        archived_at,
        source,
        source_key,
        last_synced_at
      )
      values (
        v_prompt_text,
        v_level,
        v_category_id,
        v_status = 'active',
        case when v_status = 'archived' then statement_timestamp() else null end,
        'google_sheet',
        v_source_key,
        statement_timestamp()
      );

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  with archived as (
    update public.prompts
    set is_active = false,
        archived_at = coalesce(archived_at, statement_timestamp()),
        last_synced_at = statement_timestamp(),
        updated_by = null,
        updated_at = statement_timestamp()
    where not (source = 'google_sheet' and source_key = any(v_seen_keys))
      and (is_active or archived_at is null)
    returning id
  )
  select count(*)::integer into v_archived from archived;

  v_result := jsonb_build_object(
    'total', v_row_count,
    'inserted', v_inserted,
    'updated', v_updated,
    'archived', v_archived,
    'syncedAt', statement_timestamp()
  );

  insert into private.prompt_sync_state (source, last_success_at, row_count, result)
  values ('google_sheet', statement_timestamp(), v_row_count, v_result)
  on conflict (source) do update
  set last_success_at = excluded.last_success_at,
      row_count = excluded.row_count,
      result = excluded.result;

  return v_result;
end;
$$;

create function public.sync_google_sheet_prompts(p_rows jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.sync_google_sheet_prompts(p_rows);
$$;

revoke all on table private.prompt_sync_state from public, anon, authenticated;
revoke execute on function private.sync_google_sheet_prompts(jsonb) from public, anon, authenticated;
revoke execute on function public.sync_google_sheet_prompts(jsonb) from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.sync_google_sheet_prompts(jsonb) to service_role;
grant execute on function public.sync_google_sheet_prompts(jsonb) to service_role;

comment on column public.prompts.source is
  'Identifies whether a prompt is managed manually or by the private Google Sheet sync.';
comment on column public.prompts.source_key is
  'Stable normalized key used to make Google Sheet syncs idempotent.';
comment on function public.sync_google_sheet_prompts(jsonb) is
  'Service-role-only transactional replacement sync that makes the private Google Sheet the prompt source of truth.';