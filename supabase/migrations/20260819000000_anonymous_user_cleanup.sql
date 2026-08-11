create or replace function private.cleanup_stale_anonymous_users(
  p_batch_size integer default 500
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted_count integer;
begin
  if p_batch_size < 1 or p_batch_size > 5000 then
    raise exception using
      errcode = '22023',
      message = 'cleanup_batch_size_invalid';
  end if;

  with stale_users as (
    select auth_user.id
    from auth.users as auth_user
    where auth_user.is_anonymous is true
      and auth_user.created_at <= statement_timestamp() - interval '30 days'
      and not exists (
        select 1
        from public.room_players as player
        where player.user_id = auth_user.id
      )
      and not exists (
        select 1
        from public.admin_users as admin_user
        where admin_user.user_id = auth_user.id
      )
    order by auth_user.created_at, auth_user.id
    limit p_batch_size
    for update skip locked
  ), deleted_users as (
    delete from auth.users as auth_user
    using stale_users
    where auth_user.id = stale_users.id
    returning auth_user.id
  )
  select count(*)::integer
  into v_deleted_count
  from deleted_users;

  return v_deleted_count;
end;
$$;

revoke all on function private.cleanup_stale_anonymous_users(integer) from public;
revoke all on function private.cleanup_stale_anonymous_users(integer) from anon;
revoke all on function private.cleanup_stale_anonymous_users(integer) from authenticated;

comment on function private.cleanup_stale_anonymous_users(integer) is
  'Deletes anonymous Auth users older than 30 days in bounded batches, after all room membership and administrator references are gone.';

do $$
declare
  v_existing_job_id bigint;
begin
  select job.jobid
  into v_existing_job_id
  from cron.job as job
  where job.jobname = 'cleanup-stale-anonymous-users-hourly';

  if v_existing_job_id is not null then
    perform cron.unschedule(v_existing_job_id);
  end if;

  perform cron.schedule(
    'cleanup-stale-anonymous-users-hourly',
    '37 * * * *',
    'select private.cleanup_stale_anonymous_users(500);'
  );
end;
$$;
