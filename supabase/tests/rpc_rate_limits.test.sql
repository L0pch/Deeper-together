begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

select has_table('private', 'rate_limit_counters', 'private rate-limit counters exist');
select has_function(
  'private',
  'enforce_rate_limit',
  array['text', 'integer', 'interval', 'text'],
  'the private atomic rate-limit helper exists'
);

select ok(
  not has_table_privilege('anon', 'private.rate_limit_counters', 'SELECT'),
  'anonymous users cannot read rate-limit counters'
);

select ok(
  not has_table_privilege('authenticated', 'private.rate_limit_counters', 'SELECT'),
  'authenticated users cannot read rate-limit counters'
);

select throws_ok(
  $$ select private.enforce_rate_limit('bad action', 1, interval '1 minute', 'global') $$,
  '42501',
  'authentication_required',
  'the helper requires an authenticated identity before processing configuration'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060a1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000060a1","role":"authenticated","is_anonymous":true}', true);

select throws_ok(
  $$ select private.enforce_rate_limit('bad action', 1, interval '1 minute', 'global') $$,
  '22023',
  'rate_limit_configuration_invalid',
  'invalid internal rate-limit configuration is rejected'
);

select lives_ok(
  $$ select private.enforce_rate_limit('test_action', 2, interval '1 hour', 'room-a') $$,
  'the first scoped action is allowed'
);

select lives_ok(
  $$ select private.enforce_rate_limit('test_action', 2, interval '1 hour', 'room-a') $$,
  'the action is allowed up to its configured limit'
);

select throws_ok(
  $$ select private.enforce_rate_limit('test_action', 2, interval '1 hour', 'room-a') $$,
  'P0001',
  'rate_limit_exceeded',
  'the next action in the same window is rejected'
);

select lives_ok(
  $$ select private.enforce_rate_limit('test_action', 2, interval '1 hour', 'room-b') $$,
  'a different scope has an independent allowance'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060b1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000060b1","role":"authenticated","is_anonymous":true}', true);

select lives_ok(
  $$ select private.enforce_rate_limit('test_action', 2, interval '1 hour', 'room-a') $$,
  'a different authenticated user has an independent allowance'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060c1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000060c1","role":"authenticated","is_anonymous":true}', true);

select lives_ok($$ select public.create_room('Room one', 1::smallint) $$, 'room creation one is allowed');
select lives_ok($$ select public.create_room('Room two', 1::smallint) $$, 'room creation two is allowed');
select lives_ok($$ select public.create_room('Room three', 1::smallint) $$, 'room creation three is allowed');
select lives_ok($$ select public.create_room('Room four', 1::smallint) $$, 'room creation four is allowed');
select lives_ok($$ select public.create_room('Room five', 1::smallint) $$, 'room creation five is allowed');

select throws_ok(
  $$ select public.create_room('Room six', 1::smallint) $$,
  'P0001',
  'rate_limit_exceeded',
  'the public room-creation wrapper enforces its five-per-ten-minute limit'
);

reset role;

select is(
  (
    select request_count
    from private.rate_limit_counters
    where subject_id = '00000000-0000-0000-0000-0000000060c1'::uuid
      and action_name = 'create_room'
      and scope_key = 'global'
  ),
  5,
  'the rejected request does not corrupt the successful request count'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060d1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000060d1","role":"authenticated","is_anonymous":true}', true);

select throws_ok(
  $$ select public.create_room('', 1::smallint) $$,
  '22023',
  'invalid_display_name',
  'underlying validation failures remain unchanged'
);

reset role;

select is(
  (
    select count(*)::integer
    from private.rate_limit_counters
    where subject_id = '00000000-0000-0000-0000-0000000060d1'::uuid
      and action_name = 'create_room'
  ),
  0,
  'a failed RPC rolls its database counter back and therefore needs complementary edge limiting'
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
  '00000000-0000-0000-0000-0000000060e1'::uuid,
  'stale_action',
  'global',
  statement_timestamp() - interval '25 hours',
  1,
  statement_timestamp() - interval '25 hours'
);

select lives_ok(
  $$ select private.cleanup_expired_rooms() $$,
  'the scheduled room cleanup also prunes stale counters'
);

select is(
  (select count(*)::integer from private.rate_limit_counters where action_name = 'stale_action'),
  0,
  'rate-limit counters older than 24 hours are removed'
);

rollback;
