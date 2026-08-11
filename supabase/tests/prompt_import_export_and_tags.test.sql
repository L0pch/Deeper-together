begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

insert into public.admin_users (user_id)
values ('00000000-0000-0000-0000-0000000040a1');

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  $$ select public.save_admin_tag('Care', 'care') $$,
  '42501',
  'permission denied for function save_admin_tag',
  'the anonymous API role cannot manage tags'
);

select throws_ok(
  $$ select public.import_admin_prompts('[]'::jsonb) $$,
  '42501',
  'permission denied for function import_admin_prompts',
  'the anonymous API role cannot bulk import prompts'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040b1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000040b1","role":"authenticated","is_anonymous":false}', true);

select throws_ok(
  $$ select public.get_admin_prompt_export() $$,
  '42501',
  'admin_permission_required',
  'a signed-in non-admin cannot export prompt content'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000040a1","role":"authenticated","is_anonymous":false}', true);

select ok(
  (public.get_admin_prompt_catalog() -> 'tags' -> 0) ? 'isActive',
  'the prompt catalog exposes tag activation state to administrators'
);

select throws_ok(
  $$ select public.save_admin_tag(' ', 'care') $$,
  '22023',
  'invalid_tag_name',
  'blank tag names are rejected'
);

select throws_ok(
  $$ select public.save_admin_tag('Care', 'Not A Slug') $$,
  '22023',
  'invalid_tag_slug',
  'invalid tag slugs are rejected'
);

select throws_ok(
  $$ select public.save_admin_tag('Faith duplicate', 'faith') $$,
  '23505',
  'tag_slug_exists',
  'duplicate tag slugs are rejected'
);

with saved as (
  select public.save_admin_tag('Care', 'care') as value
)
select set_config('test.import_tag_id', value ->> 'id', true)
from saved;

select is(
  public.save_admin_tag('Care', 'care', current_setting('test.import_tag_id')::uuid) ->> 'name',
  'Care',
  'an administrator can create a tag'
);

reset role;

select is(
  (select created_by from public.tags where id = current_setting('test.import_tag_id')::uuid),
  '00000000-0000-0000-0000-0000000040a1'::uuid,
  'tag creation records the authoritative administrator ID'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000040a1","role":"authenticated","is_anonymous":false}', true);

select is(
  public.save_admin_tag(
    'Community care',
    'community-care',
    current_setting('test.import_tag_id')::uuid
  ) ->> 'slug',
  'community-care',
  'an administrator can edit a tag name and slug'
);

select is(
  (public.set_admin_tag_active(current_setting('test.import_tag_id')::uuid, false) ->> 'isActive')::boolean,
  false,
  'an administrator can deactivate a tag'
);

select is(
  (
    select (tag ->> 'isActive')::boolean
    from jsonb_array_elements(public.get_admin_prompt_catalog() -> 'tags') as tag
    where tag ->> 'id' = current_setting('test.import_tag_id')
  ),
  false,
  'tag deactivation is reflected in the admin catalog'
);

select throws_ok(
  $sql$ select public.import_admin_prompts(
    '[{"promptText":"Inactive tag import?","level":1,"categoryId":"secular","tags":["community-care"],"status":"active"}]'::jsonb
  ) $sql$,
  '22023',
  'invalid_prompt_import_tags',
  'bulk imports cannot assign inactive tags'
);

select is(
  (public.set_admin_tag_active(current_setting('test.import_tag_id')::uuid, true) ->> 'isActive')::boolean,
  true,
  'an administrator can reactivate a tag'
);

select throws_ok(
  $$ select public.import_admin_prompts('{}'::jsonb) $$,
  '22023',
  'invalid_prompt_import',
  'bulk import requires a JSON array'
);

select throws_ok(
  $$ select public.import_admin_prompts('[]'::jsonb) $$,
  '22023',
  'invalid_prompt_import_size',
  'bulk import rejects an empty batch'
);

select throws_ok(
  $$ select public.import_admin_prompts((select jsonb_agg('{}'::jsonb) from generate_series(1, 501))) $$,
  '22023',
  'invalid_prompt_import_size',
  'bulk import caps each transaction at 500 rows'
);

select throws_ok(
  $$ select public.import_admin_prompts('[{"promptText":"Bad level","level":4,"categoryId":"secular"}]'::jsonb) $$,
  '22023',
  'invalid_prompt_import_row',
  'bulk import validates every row level and shape'
);

select throws_ok(
  $$ select public.import_admin_prompts('[{"promptText":"Bad category","level":1,"categoryId":"missing"}]'::jsonb) $$,
  '22023',
  'invalid_prompt_import_category',
  'bulk import validates every row category'
);

select throws_ok(
  $$ select public.import_admin_prompts('[{"promptText":"Bad tags","level":1,"categoryId":"secular","tags":["missing"]}]'::jsonb) $$,
  '22023',
  'invalid_prompt_import_tags',
  'bulk import validates every row tag slug'
);

with imported as (
  select public.import_admin_prompts(
    '[
      {"promptText":"Bulk active reflection?","level":3,"categoryId":"hybrid","tags":["community-care","growth"],"status":"active"},
      {"promptText":"Bulk inactive reflection?","level":2,"categoryId":"christian","tags":["faith"],"status":"inactive"},
      {"promptText":"WHAT IS SOMETHING SMALL THAT MADE YOU SMILE THIS WEEK?","level":1,"categoryId":"secular","tags":[],"status":"active"}
    ]'::jsonb
  ) as value
)
select set_config('test.import_result', value::text, true)
from imported;

select is(
  (current_setting('test.import_result')::jsonb ->> 'imported')::integer,
  2,
  'bulk import inserts all new validated prompts'
);

select is(
  (current_setting('test.import_result')::jsonb ->> 'skipped')::integer,
  1,
  'bulk import skips case-insensitive prompt-text duplicates'
);

reset role;

select set_config('test.import_active_prompt_id', (
  select id::text from public.prompts where prompt_text = 'Bulk active reflection?'
), true);

select is(
  (select count(*) from public.prompts),
  11::bigint,
  'bulk import persists only the two new prompts'
);

select is(
  (select is_active from public.prompts where prompt_text = 'Bulk inactive reflection?'),
  false,
  'bulk import preserves inactive status'
);

select is(
  (
    select count(*)
    from public.prompt_tags as prompt_tag
    where prompt_tag.prompt_id = current_setting('test.import_active_prompt_id')::uuid
  ),
  2::bigint,
  'bulk import assigns all validated tags'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000040a1","role":"authenticated","is_anonymous":false}', true);

select is(
  (public.import_admin_prompts(
    '[
      {"promptText":"Bulk active reflection?","level":3,"categoryId":"hybrid","tags":["community-care"],"status":"active"},
      {"promptText":"Bulk inactive reflection?","level":2,"categoryId":"christian","tags":["faith"],"status":"inactive"},
      {"promptText":"What is something small that made you smile this week?","level":1,"categoryId":"secular","tags":[],"status":"active"}
    ]'::jsonb
  ) ->> 'imported')::integer,
  0,
  'repeating the same bulk import is idempotent'
);

select is(
  (public.import_admin_prompts(
    '[
      {"promptText":"Bulk active reflection?","level":3,"categoryId":"hybrid"},
      {"promptText":"Bulk inactive reflection?","level":2,"categoryId":"christian"},
      {"promptText":"What is something small that made you smile this week?","level":1,"categoryId":"secular"}
    ]'::jsonb
  ) ->> 'skipped')::integer,
  3,
  'an idempotent repeat reports every duplicate as skipped'
);

select is(
  (public.import_admin_prompts(
    '[{"promptText":"Bulk archived reflection?","level":3,"categoryId":"christian","tags":["prayer"],"status":"archived"}]'::jsonb
  ) ->> 'imported')::integer,
  1,
  'bulk import supports archived rows from a previous export'
);

reset role;

select ok(
  (select not is_active and archived_at is not null from public.prompts where prompt_text = 'Bulk archived reflection?'),
  'an imported archived row preserves its terminal prompt state'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000040a1","role":"authenticated","is_anonymous":false}', true);

select is(
  jsonb_array_length(public.get_admin_prompt_export()),
  12,
  'prompt export returns the complete prompt library without pagination'
);

select is(
  (
    select exported ->> 'status'
    from jsonb_array_elements(public.get_admin_prompt_export()) as exported
    where exported ->> 'promptText' = 'Bulk inactive reflection?'
  ),
  'inactive',
  'prompt export preserves prompt status'
);

select ok(
  not ((public.get_admin_prompt_export() -> 0) ?| array['roomId', 'roomCode', 'playerId']),
  'prompt export contains no room or player identifiers'
);

select throws_ok(
  $sql$ select public.import_admin_prompts(
    '[
      {"promptText":"This row must roll back","level":1,"categoryId":"secular"},
      {"promptText":"This row is invalid","level":1,"categoryId":"missing"}
    ]'::jsonb
  ) $sql$,
  '22023',
  'invalid_prompt_import_category',
  'one invalid import row rejects the whole transaction'
);

reset role;

select is(
  (select count(*) from public.prompts where prompt_text = 'This row must roll back'),
  0::bigint,
  'a failed bulk import leaves no earlier rows behind'
);

update public.prompts
set is_active = id = current_setting('test.import_active_prompt_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000040a1","role":"authenticated","is_anonymous":false}', true);

with room_snapshot as (
  select public.create_room('Import history', 3::smallint) as value
), started as (
  select public.start_game((room_snapshot.value -> 'room' ->> 'id')::uuid) as value
  from room_snapshot
), drawn as (
  select public.draw_prompt(
    (room_snapshot.value -> 'room' ->> 'id')::uuid,
    (started.value -> 'currentTurn' ->> 'id')::uuid,
    3::smallint
  ) as value
  from room_snapshot, started
)
select set_config('test.import_history_room_id', value -> 'room' ->> 'id', true)
from drawn;

select is(
  public.save_admin_tag(
    'Shared care',
    'shared-care',
    current_setting('test.import_tag_id')::uuid
  ) ->> 'slug',
  'shared-care',
  'an administrator can rename a tag after it has been used'
);

reset role;

select is(
  (select prompt_tags_snapshot[1] from public.prompt_draws where room_id = current_setting('test.import_history_room_id')::uuid),
  'community-care',
  'renaming a tag cannot change tag metadata already preserved in room history'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040b1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000040b1","role":"authenticated","is_anonymous":false}', true);

select throws_ok(
  format($sql$ select public.set_admin_tag_active(%L::uuid, false) $sql$, current_setting('test.import_tag_id')),
  '42501',
  'admin_permission_required',
  'a signed-in non-admin cannot change tag state'
);

reset role;

select * from finish();
rollback;
