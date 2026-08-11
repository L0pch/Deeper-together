begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

insert into public.admin_users (user_id)
values ('00000000-0000-0000-0000-0000000030a1');

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  $$ select public.get_admin_prompt_catalog() $$,
  '42501',
  'permission denied for function get_admin_prompt_catalog',
  'the anonymous API role cannot execute the admin catalog function'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000030a1","role":"authenticated","is_anonymous":true}', true);

select throws_ok(
  $$ select public.get_admin_prompt_catalog() $$,
  '42501',
  'admin_strong_authentication_required',
  'an allowlisted anonymous guest is rejected from administration'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030b1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000030b1","role":"authenticated","is_anonymous":false}', true);

select throws_ok(
  $$ select public.get_admin_prompt_catalog() $$,
  '42501',
  'admin_permission_required',
  'a signed-in user outside the admin allowlist cannot read prompt data'
);

select throws_ok(
  $$ select public.save_admin_prompt('Unauthorized prompt', 1::smallint, 'secular') $$,
  '42501',
  'admin_permission_required',
  'a non-admin cannot create a prompt'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000030a1","role":"authenticated","is_anonymous":false}', true);

select is(
  (public.get_admin_prompt_catalog() ->> 'total')::integer,
  9,
  'an allowlisted admin can read the seeded prompt catalog'
);

select is(
  jsonb_array_length(public.get_admin_prompt_catalog() -> 'categories'),
  3,
  'the admin catalog includes prompt categories'
);

select ok(
  not (public.get_admin_prompt_catalog() ? 'tags'),
  'the admin catalog has no tag vocabulary'
);

select throws_ok(
  $$ select public.get_admin_prompt_catalog(repeat('x', 101)) $$,
  '22023',
  'invalid_admin_search',
  'overlong admin searches are rejected'
);

select throws_ok(
  $$ select public.get_admin_prompt_catalog(null, 4::smallint) $$,
  '22023',
  'invalid_prompt_level',
  'invalid prompt-level filters are rejected'
);

select throws_ok(
  $$ select public.get_admin_prompt_catalog(null, null, 'missing') $$,
  '22023',
  'invalid_prompt_category',
  'unknown category filters are rejected'
);

select throws_ok(
  $$ select public.get_admin_prompt_catalog(null, null, null, 'deleted') $$,
  '22023',
  'invalid_prompt_status',
  'unknown status filters are rejected'
);

select throws_ok(
  $$ select public.get_admin_prompt_catalog(null, null, null, 'all', 0, 0) $$,
  '22023',
  'invalid_admin_pagination',
  'invalid pagination is rejected'
);

select throws_ok(
  $$ select public.save_admin_prompt(' ', 1::smallint, 'secular') $$,
  '22023',
  'invalid_prompt_text',
  'blank prompt text is rejected'
);

select throws_ok(
  $$ select public.save_admin_prompt('Valid text?', 1::smallint, 'missing') $$,
  '22023',
  'invalid_prompt_category',
  'unknown categories are rejected on save'
);

with saved as (
  select public.save_admin_prompt(
    'What helps you feel welcomed in a new group?',
    1::smallint,
    'secular'
  ) as value
)
select set_config('test.admin_prompt_id', value ->> 'id', true)
from saved;

select is(
  public.get_admin_prompt_catalog('welcomed') -> 'prompts' -> 0 ->> 'promptText',
  'What helps you feel welcomed in a new group?',
  'an admin can create a prompt'
);

reset role;

select is(
  (select created_by from public.prompts where id = current_setting('test.admin_prompt_id')::uuid),
  '00000000-0000-0000-0000-0000000030a1'::uuid,
  'prompt creation records the authoritative admin user ID'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000030a1","role":"authenticated","is_anonymous":false}', true);

select is(
  (public.get_admin_prompt_catalog('welcomed') ->> 'total')::integer,
  1,
  'prompt search filters on prompt text'
);

select is(
  (public.get_admin_prompt_catalog(null, 1::smallint, 'secular') ->> 'total')::integer,
  3,
  'prompt filters combine level and category'
);

reset role;
update public.prompts
set is_active = id = current_setting('test.admin_prompt_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000030a1","role":"authenticated","is_anonymous":false}', true);

with room_snapshot as (
  select public.create_room('Prompt admin', 1::smallint) as value
), started as (
  select public.start_game((room_snapshot.value -> 'room' ->> 'id')::uuid) as value
  from room_snapshot
), drawn as (
  select public.draw_prompt(
    (room_snapshot.value -> 'room' ->> 'id')::uuid,
    (started.value -> 'currentTurn' ->> 'id')::uuid,
    1::smallint
  ) as value
  from room_snapshot, started
)
select set_config('test.admin_history_room_id', value -> 'room' ->> 'id', true)
from drawn;

select is(
  public.save_admin_prompt(
    'What helps a group become a place of belonging?',
    2::smallint,
    'hybrid',
    current_setting('test.admin_prompt_id')::uuid
  ) ->> 'promptText',
  'What helps a group become a place of belonging?',
  'an admin can edit an existing prompt'
);

reset role;

select ok(
  (select level = 2 and category_id = 'hybrid'
     and updated_by = '00000000-0000-0000-0000-0000000030a1'::uuid
   from public.prompts
   where id = current_setting('test.admin_prompt_id')::uuid),
  'prompt edits persist metadata'
);

select is(
  (select prompt_text_snapshot from public.prompt_draws
   where room_id = current_setting('test.admin_history_room_id')::uuid),
  'What helps you feel welcomed in a new group?',
  'editing a prompt cannot change historical wording'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000030a1","role":"authenticated","is_anonymous":false}', true);

select is(
  (public.set_admin_prompt_state(current_setting('test.admin_prompt_id')::uuid, 'deactivate') ->> 'isActive')::boolean,
  false,
  'an admin can deactivate a prompt'
);

select is(
  (public.get_admin_prompt_catalog(null, null, null, 'inactive') ->> 'total')::integer,
  10,
  'the inactive filter reflects prompt state'
);

select is(
  (public.set_admin_prompt_state(current_setting('test.admin_prompt_id')::uuid, 'activate') ->> 'isActive')::boolean,
  true,
  'an admin can reactivate a prompt'
);

select ok(
  (public.set_admin_prompt_state(current_setting('test.admin_prompt_id')::uuid, 'archive') ->> 'archivedAt') is not null,
  'archiving records a timestamp'
);

select is(
  (public.get_admin_prompt_catalog(null, null, null, 'archived') ->> 'total')::integer,
  1,
  'archived prompts remain in the admin archive'
);

select is(
  (select prompt_text_snapshot from public.prompt_draws
   where room_id = current_setting('test.admin_history_room_id')::uuid),
  'What helps you feel welcomed in a new group?',
  'archiving cannot remove a historical draw'
);

select ok(
  (public.set_admin_prompt_state(current_setting('test.admin_prompt_id')::uuid, 'restore') ->> 'archivedAt') is null,
  'an admin can restore an archived prompt as inactive'
);

select throws_ok(
  format($sql$ select public.set_admin_prompt_state(%L::uuid, 'delete') $sql$, current_setting('test.admin_prompt_id')),
  '22023',
  'invalid_prompt_state_action',
  'unknown prompt state actions are rejected'
);

select throws_ok(
  $$ select public.save_admin_prompt('Missing prompt?', 1::smallint, 'secular', '00000000-0000-0000-0000-000000009999'::uuid) $$,
  'P0001',
  'prompt_not_found',
  'editing an unknown prompt fails safely'
);

reset role;
delete from public.admin_users where user_id = '00000000-0000-0000-0000-0000000030a1';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000030a1","role":"authenticated","is_anonymous":false}', true);

select throws_ok(
  $$ select public.get_admin_prompt_catalog() $$,
  '42501',
  'admin_permission_required',
  'removing an allowlist entry revokes admin access immediately'
);

reset role;

select * from finish();
rollback;