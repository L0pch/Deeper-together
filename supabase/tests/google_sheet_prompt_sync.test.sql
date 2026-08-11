begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

insert into public.prompts (prompt_text, level, category_id)
values ('Manual prompt must stay active', 1, 'secular');

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  $$ select public.sync_google_sheet_prompts('[]'::jsonb) $$,
  '42501',
  'permission denied for function sync_google_sheet_prompts',
  'anonymous users cannot invoke sheet sync'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000060a1","role":"authenticated","is_anonymous":false}', true);

select throws_ok(
  $$ select public.sync_google_sheet_prompts('[]'::jsonb) $$,
  '42501',
  'permission denied for function sync_google_sheet_prompts',
  'authenticated users cannot invoke sheet sync directly'
);

set local role service_role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060f1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000060f1","role":"service_role"}', true);

select throws_ok(
  $$ select public.sync_google_sheet_prompts('{}'::jsonb) $$,
  '22023',
  'invalid_prompt_sync',
  'sheet sync requires a JSON array'
);

select throws_ok(
  $$ select public.sync_google_sheet_prompts('[]'::jsonb) $$,
  '22023',
  'invalid_prompt_sync_size',
  'an empty sheet cannot accidentally clear the bank'
);

select throws_ok(
  $$ select public.sync_google_sheet_prompts(
    '[
      {"promptText":"Repeated row","level":1,"categoryId":"secular","status":"active"},
      {"promptText":"repeated row","level":2,"categoryId":"christian","status":"active"}
    ]'::jsonb
  ) $$,
  '22023',
  'duplicate_prompt_sync_text',
  'case-insensitive duplicate prompt text is rejected'
);

select throws_ok(
  $$ select public.sync_google_sheet_prompts(
    '[{"promptText":"Invalid level","level":4,"categoryId":"secular","status":"active"}]'::jsonb
  ) $$,
  '22023',
  'invalid_prompt_sync_row',
  'invalid sheet levels are rejected'
);

select throws_ok(
  $$ select public.sync_google_sheet_prompts(
    '[{"promptText":"Invalid category","level":1,"categoryId":"missing","status":"active"}]'::jsonb
  ) $$,
  '22023',
  'invalid_prompt_sync_category',
  'invalid sheet categories are rejected'
);

with synced as (
  select public.sync_google_sheet_prompts(
    '[
      {"promptText":"Sheet prompt one","level":1,"categoryId":"christian","status":"active"},
      {"promptText":"Sheet prompt two","level":2,"categoryId":"hybrid","status":"inactive"}
    ]'::jsonb
  ) as value
)
select set_config('test.sheet_sync_one', value::text, true)
from synced;

select is(
  (current_setting('test.sheet_sync_one')::jsonb ->> 'inserted')::integer,
  2,
  'the first sync inserts both sheet prompts'
);

select is(
  (current_setting('test.sheet_sync_one')::jsonb ->> 'total')::integer,
  2,
  'the first sync reports its validated row count'
);

reset role;

select is(
  (select count(*) from public.prompts where source = 'google_sheet'),
  2::bigint,
  'sheet prompts are marked with their authoritative source'
);

select is(
  (select not is_active and archived_at is not null from public.prompts where prompt_text = 'Manual prompt must stay active'),
  true,
  'the private sheet is the prompt source of truth and archives rows it does not contain'
);

set local role service_role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060f1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000060f1","role":"service_role"}', true);

with synced as (
  select public.sync_google_sheet_prompts(
    '[
      {"promptText":"Sheet prompt one","level":3,"categoryId":"christian","status":"inactive"},
      {"promptText":"Sheet prompt three","level":1,"categoryId":"secular","status":"active"}
    ]'::jsonb
  ) as value
)
select set_config('test.sheet_sync_two', value::text, true)
from synced;

select is(
  (current_setting('test.sheet_sync_two')::jsonb ->> 'inserted')::integer,
  1,
  'a later sync inserts new sheet rows'
);

select is(
  (current_setting('test.sheet_sync_two')::jsonb ->> 'updated')::integer,
  1,
  'a later sync updates retained sheet rows'
);

select is(
  (current_setting('test.sheet_sync_two')::jsonb ->> 'archived')::integer,
  1,
  'a later sync archives sheet rows that were removed'
);

reset role;

select ok(
  (select level = 3 and category_id = 'christian' and not is_active and archived_at is null
   from public.prompts where prompt_text = 'Sheet prompt one'),
  'sync updates level, category, and inactive status'
);

select ok(
  (select not is_active and archived_at is not null
   from public.prompts where prompt_text = 'Sheet prompt two'),
  'a removed sheet prompt is archived instead of deleted'
);

select is(
  (select not is_active and archived_at is not null from public.prompts where prompt_text = 'Manual prompt must stay active'),
  true,
  'later syncs keep out-of-sheet prompts archived'
);

set local role service_role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060f1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000060f1","role":"service_role"}', true);

with synced as (
  select public.sync_google_sheet_prompts(
    '[
      {"promptText":"Sheet prompt one","level":3,"categoryId":"christian","status":"inactive"},
      {"promptText":"Sheet prompt three","level":1,"categoryId":"secular","status":"active"}
    ]'::jsonb
  ) as value
)
select set_config('test.sheet_sync_three', value::text, true)
from synced;

select is(
  (current_setting('test.sheet_sync_three')::jsonb ->> 'inserted')::integer,
  0,
  'repeating a sync does not insert duplicates'
);

select is(
  (current_setting('test.sheet_sync_three')::jsonb ->> 'updated')::integer,
  2,
  'repeating a sync deterministically refreshes retained rows'
);

select is(
  (current_setting('test.sheet_sync_three')::jsonb ->> 'archived')::integer,
  0,
  'repeating a sync does not archive additional rows'
);

select * from finish();
rollback;