begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

select has_function(
  'private',
  'cleanup_stale_anonymous_users',
  array['integer'],
  'the private anonymous-user cleanup function exists'
);

select ok(
  not has_function_privilege('anon', 'private.cleanup_stale_anonymous_users(integer)', 'EXECUTE'),
  'anonymous users cannot execute anonymous-user cleanup'
);

select ok(
  not has_function_privilege('authenticated', 'private.cleanup_stale_anonymous_users(integer)', 'EXECUTE'),
  'authenticated users cannot execute anonymous-user cleanup'
);

select is(
  (
    select job.schedule
    from cron.job as job
    where job.jobname = 'cleanup-stale-anonymous-users-hourly'
  ),
  '37 * * * *',
  'anonymous-user cleanup is scheduled hourly'
);

select is(
  (
    select job.command
    from cron.job as job
    where job.jobname = 'cleanup-stale-anonymous-users-hourly'
  ),
  'select private.cleanup_stale_anonymous_users(500);',
  'the scheduled job invokes the bounded private cleanup function'
);

select throws_ok(
  $$ select private.cleanup_stale_anonymous_users(0) $$,
  '22023',
  'cleanup_batch_size_invalid',
  'cleanup rejects a zero-sized batch'
);

select throws_ok(
  $$ select private.cleanup_stale_anonymous_users(5001) $$,
  '22023',
  'cleanup_batch_size_invalid',
  'cleanup rejects an excessively large batch'
);

insert into auth.users (
  id,
  aud,
  role,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_anonymous
)
values
  ('00000000-0000-0000-0000-0000000090a1', 'authenticated', 'authenticated', '{}', '{}', statement_timestamp() - interval '31 days', statement_timestamp() - interval '31 days', true),
  ('00000000-0000-0000-0000-0000000090b1', 'authenticated', 'authenticated', '{}', '{}', statement_timestamp() - interval '29 days', statement_timestamp() - interval '29 days', true),
  ('00000000-0000-0000-0000-0000000090c1', 'authenticated', 'authenticated', '{}', '{}', statement_timestamp() - interval '31 days', statement_timestamp() - interval '31 days', true),
  ('00000000-0000-0000-0000-0000000090d1', 'authenticated', 'authenticated', '{}', '{}', statement_timestamp() - interval '31 days', statement_timestamp() - interval '31 days', false),
  ('00000000-0000-0000-0000-0000000090e1', 'authenticated', 'authenticated', '{}', '{}', statement_timestamp() - interval '31 days', statement_timestamp() - interval '31 days', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000090c1', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000090c1","role":"authenticated","is_anonymous":true}', true);
select public.create_room('Retained guest', 1::smallint);
reset role;

insert into public.admin_users (user_id)
values ('00000000-0000-0000-0000-0000000090e1');

select is(
  private.cleanup_stale_anonymous_users(),
  1,
  'cleanup deletes only an eligible orphaned anonymous user'
);

select is(
  (select count(*)::integer from auth.users where id = '00000000-0000-0000-0000-0000000090a1'),
  0,
  'a stale orphaned anonymous user is deleted'
);

select is(
  (select count(*)::integer from auth.users where id = '00000000-0000-0000-0000-0000000090b1'),
  1,
  'a recent anonymous user is preserved'
);

select is(
  (select count(*)::integer from auth.users where id = '00000000-0000-0000-0000-0000000090c1'),
  1,
  'an anonymous user with room membership is preserved'
);

select is(
  (select count(*)::integer from auth.users where id = '00000000-0000-0000-0000-0000000090d1'),
  1,
  'a non-anonymous user is preserved regardless of age'
);

select is(
  (select count(*)::integer from auth.users where id = '00000000-0000-0000-0000-0000000090e1'),
  1,
  'an allowlisted administrator identity is preserved defensively'
);

select is(
  private.cleanup_stale_anonymous_users(),
  0,
  'cleanup is idempotent when no eligible users remain'
);

select is(
  (
    select proconfig
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname = 'cleanup_stale_anonymous_users'
  ),
  array['search_path=""'],
  'cleanup pins an empty search path'
);

rollback;
