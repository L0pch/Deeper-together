begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

insert into public.admin_users (user_id)
values ('00000000-0000-0000-0000-0000000040a1');

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);

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

with imported as (
  select public.import_admin_prompts(
    '[
      {"promptText":"Bulk active reflection?","level":3,"categoryId":"hybrid","status":"active"},
      {"promptText":"Bulk inactive reflection?","level":2,"categoryId":"christian","status":"inactive"},
      {"promptText":"WHAT IS SOMETHING SMALL THAT MADE YOU SMILE THIS WEEK?","level":1,"categoryId":"secular","status":"active"}
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

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000040a1","role":"authenticated","is_anonymous":false}', true);

select is(
  (public.import_admin_prompts(
    '[
      {"promptText":"Bulk active reflection?","level":3,"categoryId":"hybrid"},
      {"promptText":"Bulk inactive reflection?","level":2,"categoryId":"christian"},
      {"promptText":"What is something small that made you smile this week?","level":1,"categoryId":"secular"}
    ]'::jsonb
  ) ->> 'skipped')::integer,
  3,
  'repeating the same bulk import is idempotent'
);

select is(
  (public.import_admin_prompts(
    '[{"promptText":"Bulk archived reflection?","level":3,"categoryId":"christian","status":"archived"}]'::jsonb
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
  'a failed import leaves no partial prompt inserts'
);

select * from finish();
rollback;